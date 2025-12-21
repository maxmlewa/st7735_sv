`timescale 1ns/1ps
`default_nettype none

module tft_pattern #(
    parameter int unsigned W = 128,
    parameter int unsigned H = 160
)(
    input wire [$clog2(W)-1:0] x,
    input wire [$clog2(H)-1:0] y,
    input wire [3:0] sw,
    output logic [15:0] rgb565
);

    localparam logic [15:0] C_BLACK = 16'h0000;
    localparam logic [15:0] C_WHITE = 16'hFFFF;
    localparam logic [15:0] C_RED   = 16'hF800;
    localparam logic [15:0] C_GREEN = 16'h07E0;
    localparam logic [15:0] C_BLUE  = 16'h001F;
    localparam logic [15:0] C_YELL  = 16'hFFE0;
    localparam logic [15:0] C_CYAN  = 16'h07FF;
    localparam logic [15:0] C_MAG   = 16'hF81F;

    always_comb begin
        unique case (sw[3:2])

            2'b00: begin
                // solid color (sw[1:0])
                unique case (sw[1:0])
                    2'b00: rgb565 = C_BLACK;
                    2'b01: rgb565 = C_RED;
                    2'b10: rgb565 = C_GREEN;
                    default: rgb565 = C_BLUE;
                endcase
            end

            2'b01: begin
                // 8 vertical color bars (super obvious)
                unique case (x[6:4]) // 0..7 for 128 width
                    3'd0: rgb565 = C_RED;
                    3'd1: rgb565 = C_YELL;
                    3'd2: rgb565 = C_GREEN;
                    3'd3: rgb565 = C_CYAN;
                    3'd4: rgb565 = C_BLUE;
                    3'd5: rgb565 = C_MAG;
                    3'd6: rgb565 = C_WHITE;
                    default: rgb565 = C_BLACK;
                endcase
            end

            2'b10: begin
                // checkerboard; block size via sw[1:0]
                logic [3:0] shift;
                shift = 4'(sw[1:0]) + 2; // 2..5
                rgb565 = (((x >> shift) ^ (y >> shift)) & 1) ? C_WHITE : C_BLACK;
            end

            default: begin
                // diagonal gradient
                rgb565 = {x[6:2], y[7:2], (x ^ y)[6:2]};
            end
        endcase
    end

endmodule

`default_nettype wire
