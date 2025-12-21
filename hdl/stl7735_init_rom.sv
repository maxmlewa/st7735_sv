
`timescale 1ns/1ps
`default_nettype none

// Simple init ROM for ST7735 128x160 SPI TFT
// Each entry is {is_data, byte_out}
// is_data=0 => command (DC/RS low)
// is_data=1 => data (DC/RS high)
//
// Notes:
// - Many ST7735 variants exist (tab colors/offsets). This is a minimal baseline.
// - include CASET/RASET for full window 0..127 / 0..159 and DISPON.
// - After SLPOUT, the controller module enforces a delay before continuing.

module st7735_init_rom #(
    parameter int unsigned N = 22
)(
    input wire [$clog2(N)-1:0] idx,
    output logic is_data,
    output logic [7:0] byte_out
);

    always_comb begin
        is_data = 1'b0;
        byte_out = 8'h00;

        unique case (idx)
            //  Reset + Sleep out 
            0:  begin is_data=1'b0; byte_out=8'h01; end // SWRESET
            1:  begin is_data=1'b0; byte_out=8'h11; end // SLPOUT

            //  Color mode: 16bpp 
            2:  begin is_data=1'b0; byte_out=8'h3A; end // COLMOD
            3:  begin is_data=1'b1; byte_out=8'h05; end // 16-bit/pixel

            //  Memory access control (orientation) 
            4:  begin is_data=1'b0; byte_out=8'h36; end // MADCTL
            5:  begin is_data=1'b1; byte_out=8'h00; end // tweak later if needed

            //  Column address set: 0..127 
            6:  begin is_data=1'b0; byte_out=8'h2A; end // CASET
            7:  begin is_data=1'b1; byte_out=8'h00; end // XSTART hi
            8:  begin is_data=1'b1; byte_out=8'h00; end // XSTART lo
            9:  begin is_data=1'b1; byte_out=8'h00; end // XEND hi
            10: begin is_data=1'b1; byte_out=8'h7F; end // XEND lo (127)

            //  Row address set: 0..159 
            11: begin is_data=1'b0; byte_out=8'h2B; end // RASET
            12: begin is_data=1'b1; byte_out=8'h00; end // YSTART hi
            13: begin is_data=1'b1; byte_out=8'h00; end // YSTART lo
            14: begin is_data=1'b1; byte_out=8'h00; end // YEND hi
            15: begin is_data=1'b1; byte_out=8'h9F; end // YEND lo (159)

            //  Display ON 
            16: begin is_data=1'b0; byte_out=8'h29; end // DISPON

            // Optional "NOP" padding (keeps N flexible)
            default: begin is_data=1'b0; byte_out=8'h00; end // NOP
        endcase
    end

endmodule

`default_nettype wire
