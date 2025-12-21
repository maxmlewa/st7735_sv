`timescale 1ns/1ps
`default_nettype none

module tb_st7735_controller;

    // 100 MHz
    logic clk = 0;
    always #5 clk = ~clk;

    logic rst;

    // SPI wires
    logic spi_start;
    logic [7:0] spi_data;
    logic spi_busy, spi_done;
    logic sclk, copi;

    // TFT control pins
    logic tft_cs, tft_dc, tft_rst;

    // Instantiate SPI controller (validated)
    localparam int SCLK_CYCLES = 10;

    spi_controller #(
        .CLK_HZ(100_000_000),
        .SCLK_CYCLES(SCLK_CYCLES)
    ) u_spi_controller (
        .clk(clk),
        .rst(rst),
        .start(spi_start),
        .data_in(spi_data),
        .busy(spi_busy),
        .done(spi_done),
        .sclk(sclk),
        .copi(copi)
    );

    // Instantiate ST7735 controller with short delays for simulation
    st7735_controller #(
        .CLK_HZ(100_000_000),
        .RESET_LOW_CYCLES(200),      // shorten for sim
        .RESET_HIGH_CYCLES(200),
        .SLPOUT_WAIT_CYCLES(500),
        .TEST_PIXELS(8)
    ) u_st7735_controller (
        .clk(clk),
        .rst(rst),
        .spi_start(spi_start),
        .spi_data(spi_data),
        .spi_busy(spi_busy),
        .spi_done(spi_done),
        .tft_cs(tft_cs),
        .tft_dc(tft_dc),
        .tft_rst(tft_rst)
    );

    // ---------------------------------------
    // “Fake TFT” receiver: captures bytes only when CS is active
    // Also captures DC state per byte to verify cmd/data pattern
    // ---------------------------------------
    typedef struct packed {
        logic dc;
        logic [7:0] b;
    } cap_t;

    cap_t cap_list[$];

    logic [7:0] rx_shift;
    int unsigned rx_bits;

    always @(posedge sclk) begin
        if (!tft_cs) begin
            rx_shift <= {rx_shift[6:0], copi};
            rx_bits  <= rx_bits + 1;

            if (rx_bits == 7) begin
                cap_t item;
                item.dc = tft_dc;
                item.b  = {rx_shift[6:0], copi};
                cap_list.push_back(item);

                rx_bits  <= 0;
                rx_shift <= 8'h00;
            end
        end
    end


    // Expected prefix checker (basic sanity)
    task automatic expect_prefix();
        int i = 0;
        begin
            // wait until we captured enough bytes
            wait(cap_list.size() >= 8);

            // Expect: 01(cmd), 11(cmd), 3A(cmd), 05(data), 36(cmd), 00(data)
            // (plus more init...)
            assert(cap_list[0].dc == 1'b0 && cap_list[0].b == 8'h01) else $error("Expected SWRESET");
            assert(cap_list[1].dc == 1'b0 && cap_list[1].b == 8'h11) else $error("Expected SLPOUT");
            assert(cap_list[2].dc == 1'b0 && cap_list[2].b == 8'h3A) else $error("Expected COLMOD cmd");
            assert(cap_list[3].dc == 1'b1 && cap_list[3].b == 8'h05) else $error("Expected COLMOD data");
            assert(cap_list[4].dc == 1'b0 && cap_list[4].b == 8'h36) else $error("Expected MADCTL cmd");
            assert(cap_list[5].dc == 1'b1 && cap_list[5].b == 8'h00) else $error("Expected MADCTL data");

            $display("[OK] Init prefix sequence looks correct.");
        end
    endtask

    initial begin
        $dumpfile("tb_st7735_controller.vcd");
        $dumpvars(0, tb_st7735_controller);

        rst = 1'b1;
        rx_shift = 0;
        rx_bits  = 0;

        repeat(10) @(posedge clk);
        rst = 1'b0;

        fork
            expect_prefix();
        join_none

        // run for a while
        repeat(5000) @(posedge clk);

        // Print captured bytes (first 40)
        $display("Captured %0d bytes:", cap_list.size());
        for (int k = 0; k < cap_list.size() && k < 40; k++) begin
            $display("  [%0d] DC=%0d 0x%02h", k, cap_list[k].dc, cap_list[k].b);
        end

        $finish;
    end

endmodule

`default_nettype wire
