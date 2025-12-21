`timescale 1ns/1ps
`default_nettype none

// SPI Controller (Mode 0) for the Arduino tft module
// COPI only (no transaction from peripheral to controller)
// sends 8-bit bytes, MSB first
// start is a 1 cycle pulse when idle
// busy signal stays high during transfer
// the done signal pulses for 1 cycle when transfer is complete

// Timing:
// sclk idles low
// COPI changes on the falling edges of sclk to be stable by the rising egdes

module spi_controller #(
    parameter int unsigned CLK_HZ = 100_000_000,
    parameter int SCLK_CYCLES = 10                  // number of sys_clk cycles for the sclk period
)(
    input wire clk,
    input wire rst,

    input wire start,
    input wire [7:0] data_in,

    output logic busy,
    output logic done,

    output logic sclk,
    output logic copi
);

    // making sure that the SCLK has a 50% duty cycle
    localparam int unsigned HALF_PERIOD = SCLK_CYCLES >> 1;
    localparam int unsigned FULL_PERIOD = HALF_PERIOD << 1;

    logic [$clog2(FULL_PERIOD)-1 : 0] div_count;

    logic [7:0] shreg;
    logic [3:0] bits_left;
    logic running;

    always_ff @(posedge clk) begin
        if (rst) begin
            div_count <= '0;
            sclk <= 1'b0;
            shreg <= 8'b0;
            bits_left <= 4'b0;
            running <= 1'b0;

            busy <= 1'b0;
            done <= 1'b0;
            copi <= 1'b0;
        end
        
        else begin 
            done <= 1'b0;

            // Launching transaction
            if (start && !running) begin
                running <= 1'b1;
                busy <= 1'b1;
                sclk <= 1'b0;
                div_count <= '0;

                shreg <= data_in;
                bits_left <= 4'd8;
                copi <= data_in[7];  // present MSB before first rising edge
            end

            if (running) begin
                // clock divider tick
                if (HALF_PERIOD == 1 || div_count == HALF_PERIOD-1) begin
                    div_count <= '0;
                    sclk <= ~sclk;

                    // Shift on falling edges (so data is stable before rising)
                    if (sclk == 1'b1) begin
                        // just transitioned 1 -> 0 (falling edge)
                        if (bits_left != 0) begin
                            shreg <= {shreg[6:0], 1'b0};
                            bits_left <= bits_left - 1'b1;
                            copi <= shreg[6]; // next bit out
                        end

                        // finish after that falling edge for the last bit
                        if (bits_left == 1) begin
                            running <= 1'b0;
                            busy <= 1'b0;
                            done <= 1'b1;
                            sclk <= 1'b0; // idle low
                        end
                    end
                end else begin
                    div_count <= div_count + 1'b1;
                end
            end
        end
    end

endmodule //  spi_controller module

`default_nettype wire