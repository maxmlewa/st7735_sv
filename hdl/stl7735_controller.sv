`timescale 1ns/1ps
`default_nettype none

// ST7735 controller: reset + init script + optional small pixel burst
// Drives TFT pins: CS, DC/RS, RST
//
// Uses external spi_controller for byte shifting (Mode 0).
//
// After init, this module sends RAMWR and streams a small number of pixels
// (enough to prove the display path in hardware; in sim, the bytes should be apparent).
module st7735_controller #(
    parameter int unsigned CLK_HZ = 100_000_000,

    // Reset delays (in clk cycles)
    parameter int unsigned RESET_LOW_CYCLES   = 2_000_000,  // 20ms at sysclk 100MHz
    parameter int unsigned RESET_HIGH_CYCLES  = 2_000_000,  // 20ms
    parameter int unsigned SLPOUT_WAIT_CYCLES = 12_000_000, // 120ms

    // How many pixels to stream after RAMWR for test (each pixel = 2 bytes RGB565)
    parameter int unsigned TEST_PIXELS = 16
)(
    input wire clk,
    input wire rst,     

    // Interface to spi_controller
    output logic spi_start,
    output logic [7:0] spi_data,
    input wire spi_busy,
    input wire spi_done,

    // TFT control pins
    output logic tft_cs,   // active low
    output logic tft_dc,   // RS/DC: 0=command, 1=data
    output logic tft_rst   // active low reset
);

    // Init ROM
    localparam int unsigned INIT_N = 22;
    logic [$clog2(INIT_N)-1:0] init_idx;
    logic rom_is_data;
    logic [7:0] rom_byte;

    st7735_init_rom #(.N(INIT_N)) u_init_rom (
        .idx(init_idx),
        .is_data(rom_is_data),
        .byte_out(rom_byte)
    );

    typedef enum logic [3:0] {
        S_RESET_LOW,
        S_RESET_HIGH,
        S_INIT_SEND,
        S_INIT_WAIT,
        S_SLPOUT_DELAY,
        S_POST_INIT_RAMWR_CMD,
        S_POST_INIT_RAMWR_WAIT,
        S_STREAM_PIX_HI,
        S_STREAM_PIX_LO,
        S_DONE
    } state_t;

    state_t st;
    logic [31:0] delay_cnt;

    // Test pixel data: cycle through a few obvious colors
    logic [15:0] pix_color;
    logic [$clog2(TEST_PIXELS+1)-1:0] pix_count;

    always_comb begin
        // color sequence per pixel index (repeat)
        unique case (pix_count[1:0])
            2'd0: pix_color = 16'hF800; // red
            2'd1: pix_color = 16'h07E0; // green
            2'd2: pix_color = 16'h001F; // blue
            default: pix_color = 16'hFFFF; // white
        endcase
    end

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
        end else begin
            spi_start <= 1'b0;

            unique case (st)

                // Hold reset low
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

                // Release reset
                S_RESET_HIGH: begin
                    tft_rst <= 1'b1;
                    delay_cnt <= delay_cnt + 1'b1;
                    if (delay_cnt == RESET_HIGH_CYCLES-1) begin
                        delay_cnt <= 32'd0;
                        init_idx <= '0;
                        st <= S_INIT_SEND;
                    end
                end

                // Send current init ROM entry
                S_INIT_SEND: begin
                    if (!spi_busy) begin
                        tft_cs   <= 1'b0;
                        tft_dc   <= rom_is_data;
                        spi_data <= rom_byte;
                        spi_start<= 1'b1;
                        st <= S_INIT_WAIT;
                    end
                end

                // Wait for SPI done then advance
                S_INIT_WAIT: begin
                    if (spi_done) begin
                        // deassert CS between bytes (safe default)
                        tft_cs <= 1'b1;

                        // After SLPOUT (idx==1), wait a while before continuing
                        if (init_idx == 1) begin
                            delay_cnt <= 32'd0;
                            init_idx  <= init_idx + 1'b1;
                            st <= S_SLPOUT_DELAY;
                        end else if (init_idx == INIT_N-1) begin
                            // finished init ROM (note: last few entries may be NOPs)
                            st <= S_POST_INIT_RAMWR_CMD;
                        end else begin
                            init_idx <= init_idx + 1'b1;
                            st <= S_INIT_SEND;
                        end
                    end
                end

                // Delay after SLPOUT
                S_SLPOUT_DELAY: begin
                    delay_cnt <= delay_cnt + 1'b1;
                    if (delay_cnt == SLPOUT_WAIT_CYCLES-1) begin
                        delay_cnt <= 32'd0;
                        st <= S_INIT_SEND;
                    end
                end

                // After init: send RAMWR command (0x2C)
                S_POST_INIT_RAMWR_CMD: begin
                    if (!spi_busy) begin
                        tft_cs   <= 1'b0;
                        tft_dc   <= 1'b0;     // command
                        spi_data <= 8'h2C;    // RAMWR
                        spi_start<= 1'b1;
                        st <= S_POST_INIT_RAMWR_WAIT;
                    end
                end

                S_POST_INIT_RAMWR_WAIT: begin
                    if (spi_done) begin
                        // Keep CS low during pixel streaming (typical)
                        tft_cs <= 1'b0;
                        tft_dc <= 1'b1; // data for pixel bytes
                        pix_count <= '0;
                        st <= S_STREAM_PIX_HI;
                    end
                end

                // Stream TEST_PIXELS pixels (2 bytes each)
                S_STREAM_PIX_HI: begin
                    if (!spi_busy) begin
                        spi_data  <= pix_color[15:8];
                        spi_start <= 1'b1;
                        st <= S_STREAM_PIX_LO;
                    end
                end

                S_STREAM_PIX_LO: begin
                    if (spi_done && !spi_busy) begin
                        spi_data  <= pix_color[7:0];
                        spi_start <= 1'b1;

                        // advance pixel count after low byte launches
                        pix_count <= pix_count + 1'b1;
                        if (pix_count == TEST_PIXELS-1) begin
                            st <= S_DONE;
                            tft_cs <= 1'b1;
                        end else begin
                            st <= S_STREAM_PIX_HI;
                        end
                    end
                end

                S_DONE: begin
                    tft_cs <= 1'b1;
                    // idle
                end

                default: st <= S_RESET_LOW;

            endcase
        end
    end

endmodule

`default_nettype wire
