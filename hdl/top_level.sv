`timescale 1ns/1ps
`default_nettype none

module top_level (
    input  wire        clk_100mhz,
    input  wire        btnC,
    input  wire [15:0] sw,

    output logic       tft_sclk,
    output logic       tft_copi,
    output logic       tft_cs,
    output logic       tft_rs,
    output logic       tft_rst,
    output logic       tft_bl
);

    // sync reset
    logic rst;
    always_ff @(posedge clk_100mhz) rst <= btnC;

    logic        spi_start;
    logic [7:0]  spi_data;
    logic        spi_busy;
    logic        spi_done;

    assign tft_bl = 1'b1;

    spi_controller #(
        .CLK_HZ(100_000_000),
        .SCLK_CYCLES(10)
    ) u_spi_controller (
        .clk     (clk_100mhz),
        .rst     (rst),
        .start   (spi_start),
        .data_in (spi_data),
        .busy    (spi_busy),
        .done    (spi_done),
        .sclk    (tft_sclk),
        .copi    (tft_copi)
    );

    st7735_controller #(
        .CLK_HZ(100_000_000),
        .RESET_LOW_CYCLES   (2_000_000),
        .RESET_HIGH_CYCLES  (2_000_000),
        .SLPOUT_WAIT_CYCLES (12_000_000),
        .TEST_PIXELS        (20480) // 128*160
    ) u_st7735_controller (
        .clk      (clk_100mhz),
        .rst      (rst),

        .pattern  (sw[3:0]),

        .spi_start(spi_start),
        .spi_data (spi_data),
        .spi_busy (spi_busy),
        .spi_done (spi_done),

        .tft_cs   (tft_cs),
        .tft_dc   (tft_rs),
        .tft_rst  (tft_rst)
    );

endmodule

`default_nettype wire
