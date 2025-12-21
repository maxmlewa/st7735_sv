`timescale 1ns/1ps
`default_nettype none

module st7735_controller #(
    parameter int unsigned CLK_HZ = 100_000_000,
    parameter int unsigned RESET_LOW_CYCLES   = 2_000_000,
    parameter int unsigned RESET_HIGH_CYCLES  = 2_000_000,
    parameter int unsigned SLPOUT_WAIT_CYCLES = 12_000_000,
    parameter int unsigned TEST_PIXELS        = 20480  // 128*160
)(
    input  wire        clk,
    input  wire        rst,

    input  wire [3:0]  pattern,   // NEW: selects pattern

    output logic       spi_start,
    output logic [7:0] spi_data,
    input  wire        spi_busy,
    input  wire        spi_done,

    output logic       tft_cs,
    output logic       tft_dc,
    output logic       tft_rst
);

    // ---- init ROM ----
    localparam int unsigned INIT_N = 22;
    logic [$clog2(INIT_N)-1:0] init_idx;
    logic rom_is_data;
    logic [7:0] rom_byte;

    st7735_init_rom #(.N(INIT_N)) u_init_rom (
        .idx     (init_idx),
        .is_data (rom_is_data),
        .byte_out(rom_byte)
    );

    // ---- helpers for pixel patterns ----
    // Map pix_count -> x,y for 128x160
    logic [15:0] pix_color;
    logic [$clog2(TEST_PIXELS)-1:0] pix_count;
    logic [7:0] x;
    logic [7:0] y;

    always_comb begin
        x = pix_count % 128;
        y = pix_count / 128;

        unique case (pattern)
            4'h0: pix_color = 16'hF800; // solid red
            4'h1: pix_color = 16'h07E0; // solid green
            4'h2: pix_color = 16'h001F; // solid blue
            4'h3: pix_color = 16'hFFFF; // solid white
            4'h4: pix_color = (x[4] ^ y[4]) ? 16'hFFFF : 16'h0000; // checker
            4'h5: pix_color = {x[7:3], 6'b0, 5'b0}; // red gradient
            4'h6: pix_color = {5'b0, y[7:2], 5'b0}; // green gradient
            4'h7: pix_color = {5'b0, 6'b0, x[7:3]}; // blue gradient
            4'h8: pix_color = (x < 43) ? 16'hF800 : (x < 86) ? 16'h07E0 : 16'h001F; // RGB bars
            default: pix_color = {x[7:3], y[7:2], x[7:3]}; // colorful mix
        endcase
    end

    // ---- state machine ----
    typedef enum logic [4:0] {
        S_RESET_LOW,
        S_RESET_HIGH,
        S_INIT_SEND,
        S_INIT_WAIT,
        S_SLPOUT_DELAY,

        S_RAMWR_CMD_SEND,
        S_RAMWR_CMD_WAIT,

        S_PIX_HI_SEND,
        S_PIX_HI_WAIT,
        S_PIX_LO_SEND,
        S_PIX_LO_WAIT,

        S_IDLE
    } state_t;

    state_t st;
    logic [31:0] delay_cnt;

    // latch pattern and force redraw on change
    logic [3:0] pattern_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            st        <= S_RESET_LOW;
            delay_cnt <= 32'd0;

            init_idx  <= '0;

            spi_start <= 1'b0;
            spi_data  <= 8'h00;

            tft_cs    <= 1'b1;
            tft_dc    <= 1'b1;
            tft_rst   <= 1'b0;

            pix_count <= '0;
            pattern_q <= 4'h0;

        end else begin
            spi_start <= 1'b0;

            // track pattern changes
            pattern_q <= pattern_q; // default
            if (pattern != pattern_q) begin
                pattern_q <= pattern;
                // If we're idle/done, kick a redraw by restarting RAMWR+pixels.
                if (st == S_IDLE) begin
                    st <= S_RAMWR_CMD_SEND;
                end
            end

            unique case (st)

                S_RESET_LOW: begin
                    tft_cs  <= 1'b1;
                    tft_dc  <= 1'b1;
                    tft_rst <= 1'b0;

                    delay_cnt <= delay_cnt + 1'b1;
                    if (delay_cnt == RESET_LOW_CYCLES-1) begin
                        delay_cnt <= 32'd0;
                        st <= S_RESET_HIGH;
                    end
                end

                S_RESET_HIGH: begin
                    tft_rst <= 1'b1;
                    delay_cnt <= delay_cnt + 1'b1;
                    if (delay_cnt == RESET_HIGH_CYCLES-1) begin
                        delay_cnt <= 32'd0;
                        init_idx  <= '0;
                        st <= S_INIT_SEND;
                    end
                end

                S_INIT_SEND: begin
                    if (!spi_busy) begin
                        tft_cs   <= 1'b0;
                        tft_dc   <= rom_is_data;
                        spi_data <= rom_byte;
                        spi_start<= 1'b1;
                        st <= S_INIT_WAIT;
                    end
                end

                S_INIT_WAIT: begin
                    if (spi_done) begin
                        tft_cs <= 1'b1;

                        // after SLPOUT (idx==1) pause
                        if (init_idx == 1) begin
                            delay_cnt <= 32'd0;
                            init_idx  <= init_idx + 1'b1;
                            st <= S_SLPOUT_DELAY;
                        end else if (init_idx == INIT_N-1) begin
                            // init finished, start drawing loop
                            pix_count <= '0;
                            pattern_q <= pattern; // sync baseline
                            st <= S_RAMWR_CMD_SEND;
                        end else begin
                            init_idx <= init_idx + 1'b1;
                            st <= S_INIT_SEND;
                        end
                    end
                end

                S_SLPOUT_DELAY: begin
                    delay_cnt <= delay_cnt + 1'b1;
                    if (delay_cnt == SLPOUT_WAIT_CYCLES-1) begin
                        delay_cnt <= 32'd0;
                        st <= S_INIT_SEND;
                    end
                end

                // Start a new memory write for a full redraw
                S_RAMWR_CMD_SEND: begin
                    if (!spi_busy) begin
                        tft_cs   <= 1'b0;
                        tft_dc   <= 1'b0;   // command
                        spi_data <= 8'h2C;  // RAMWR
                        spi_start<= 1'b1;
                        st <= S_RAMWR_CMD_WAIT;
                    end
                end

                S_RAMWR_CMD_WAIT: begin
                    if (spi_done) begin
                        tft_cs    <= 1'b0; // keep low while streaming pixels
                        tft_dc    <= 1'b1; // data
                        pix_count <= '0;
                        st <= S_PIX_HI_SEND;
                    end
                end

                S_PIX_HI_SEND: begin
                    if (!spi_busy) begin
                        spi_data  <= pix_color[15:8];
                        spi_start <= 1'b1;
                        st <= S_PIX_HI_WAIT;
                    end
                end

                S_PIX_HI_WAIT: begin
                    if (spi_done) begin
                        st <= S_PIX_LO_SEND;
                    end
                end

                S_PIX_LO_SEND: begin
                    if (!spi_busy) begin
                        spi_data  <= pix_color[7:0];
                        spi_start <= 1'b1;
                        st <= S_PIX_LO_WAIT;
                    end
                end

                S_PIX_LO_WAIT: begin
                    if (spi_done) begin
                        if (pix_count == TEST_PIXELS-1) begin
                            tft_cs <= 1'b1;
                            st <= S_IDLE;
                        end else begin
                            pix_count <= pix_count + 1'b1;
                            st <= S_PIX_HI_SEND;
                        end
                    end
                end

                // Sit here; if pattern changes we jump to RAMWR_CMD_SEND above.
                S_IDLE: begin
                    tft_cs <= 1'b1;
                end

                default: st <= S_RESET_LOW;

            endcase
        end
    end

endmodule

`default_nettype wire
