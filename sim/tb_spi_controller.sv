`timescale 1ns/1ps
`default_nettype none

module tb_spi_controller;

    // Clock generation: 100 MHz
    logic clk = 0;
    always #5 clk = ~clk;

    // DUT interface
    logic rst;
    logic start;
    logic [7:0] data_in;
    logic busy, done;
    logic sclk, copi;

    // Configurable SCLK period
    localparam int SCLK_CYCLES = 10;

    spi_controller #(
        .CLK_HZ(100_000_000),
        .SCLK_CYCLES(SCLK_CYCLES)
    ) dut (
        .clk,
        .rst,
        .start,
        .data_in,
        .busy,
        .done,
        .sclk,
        .copi
    );


    // Scoreboard FIFO of expected bytes
    byte exp_q[$];
    int pass = 0;
    int fail = 0;


    // SPI receiver model (Mode 0):
    // sample COPI on posedge SCLK while busy is high
    logic [7:0] rx_shift;
    int unsigned rx_bits;

    // capture bytes on sclk edges
    always @(posedge sclk) begin
        if (busy) begin
            rx_shift <= {rx_shift[6:0], copi};
            rx_bits  <= rx_bits + 1;

            if (rx_bits == 7) begin
                // completed 8 bits, form the byte
                byte got = {rx_shift[6:0], copi};

                if (exp_q.size() == 0) begin
                    $error("[RX] Got 0x%02h but expected queue empty (time=%0t)", got, $time);
                    fail++;
                end else begin
                    byte exp = exp_q.pop_front();
                    if (got !== exp) begin
                        $error("[RX] MISMATCH got 0x%02h expected 0x%02h (time=%0t)", got, exp, $time);
                        fail++;
                    end else begin
                        $display("[RX] OK 0x%02h (time=%0t)", got, $time);
                        pass++;
                    end
                end

                rx_bits  <= 0;
                rx_shift <= 8'h00;
            end
        end
    end

    // reset receiver state when idle
    always @(negedge busy) begin
        rx_bits  <= 0;
        rx_shift <= 8'h00;
    end

    // Driver tasks
    task automatic send_byte(input byte b);
        begin
            // enqueue expected
            exp_q.push_back(b);

            // pulse start for 1 clk when idle
            @(posedge clk);
            wait(!busy);
            data_in <= b;
            start   <= 1'b1;
            @(posedge clk);
            start   <= 1'b0;

            // wait for done
            wait(done);
            @(posedge clk);
        end
    endtask

    task automatic send_burst(input int N, input byte seed);
        int i;
        begin
            for (i = 0; i < N; i++) begin
                send_byte(seed + i);
            end
        end
    endtask

    // "TFT init-ish" stream: command bytes + data bytes
    task automatic send_tft_like_sequence();
        begin
            // Commands
            send_byte(8'h01); // SWRESET
            send_byte(8'h11); // SLPOUT
            send_byte(8'h3A); // COLMOD
            // Data
            send_byte(8'h05); // 16bpp
            // More commands/data
            send_byte(8'h36); // MADCTL
            send_byte(8'h00); // MADCTL data
        end
    endtask

    // Stress: attempt start while busy (should be ignored by DUT)
    task automatic start_while_busy_should_be_ignored();
        begin
            // enqueue only the real first byte
            exp_q.push_back(8'hAA);

            // Start AA
            @(posedge clk);
            wait(!busy);
            data_in <= 8'hAA;
            start   <= 1'b1;
            @(posedge clk);
            start   <= 1'b0;

            // While busy, try to start BB (should be ignored)
            wait(busy);
            @(posedge clk);
            data_in <= 8'hBB;
            start   <= 1'b1;
            @(posedge clk);
            start   <= 1'b0;

            // wait for completion of the first one
            wait(done);
            @(posedge clk);
        end
    endtask

    // Main
    initial begin
        $display("=== TB: spi_controller (event-based sampling) ===");
        $dumpfile("tb_spi_controller.vcd");
        $dumpvars(0, tb_spi_controller);

        rst    = 1;
        start  = 0;
        data_in= 8'h00;
        rx_shift = 0;
        rx_bits  = 0;

        repeat (5) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        // Test 1: TFT-like command/data traffic
        send_tft_like_sequence();

        // Test 2: Pixel-like burst bytes
        send_burst(10, 8'hF0);

        // Test 3: start-while-busy ignored
        start_while_busy_should_be_ignored();

        // Final settle
        repeat (200) @(posedge clk);

        // Final queue empty check
        if (exp_q.size() != 0) begin
            $error("Expected queue not empty at end: %0d bytes remain", exp_q.size());
            fail += exp_q.size();
        end

        $display("=== RESULT: pass=%0d fail=%0d ===", pass, fail);
        if (fail == 0) $display("ALL TESTS PASSED");
        else $display("TESTS FAILED ");

        $finish;
    end

endmodule

`default_nettype wire
