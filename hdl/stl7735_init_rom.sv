`timescale 1ns/1ps
`default_nettype none

module st7735_init_rom #(
    parameter int unsigned N = 22
)(
    input  wire [$clog2(N)-1:0] idx,
    output logic                 is_data,
    output logic [7:0]           byte_out
);
    always_comb begin
        is_data  = 1'b0;
        byte_out = 8'h00;

        unique case (idx)
            // SWRESET
            0:  begin is_data=1'b0; byte_out=8'h01; end

            // SLPOUT
            1:  begin is_data=1'b0; byte_out=8'h11; end

            // COLMOD = 16-bit (0x05)
            2:  begin is_data=1'b0; byte_out=8'h3A; end
            3:  begin is_data=1'b1; byte_out=8'h05; end

            // MADCTL (rotation/color order). 0x00 is a safe baseline.
            4:  begin is_data=1'b0; byte_out=8'h36; end
            5:  begin is_data=1'b1; byte_out=8'h00; end

            // CASET (0..127)
            6:  begin is_data=1'b0; byte_out=8'h2A; end
            7:  begin is_data=1'b1; byte_out=8'h00; end
            8:  begin is_data=1'b1; byte_out=8'h00; end
            9:  begin is_data=1'b1; byte_out=8'h00; end
            10: begin is_data=1'b1; byte_out=8'h7F; end

            // RASET (0..159)
            11: begin is_data=1'b0; byte_out=8'h2B; end
            12: begin is_data=1'b1; byte_out=8'h00; end
            13: begin is_data=1'b1; byte_out=8'h00; end
            14: begin is_data=1'b1; byte_out=8'h00; end
            15: begin is_data=1'b1; byte_out=8'h9F; end

            // NORON (normal mode on) – often used
            16: begin is_data=1'b0; byte_out=8'h13; end

            // DISPON (display on)
            17: begin is_data=1'b0; byte_out=8'h29; end

            // RAMWR (start memory write)
            18: begin is_data=1'b0; byte_out=8'h2C; end

            // remaining: NOPs
            default: begin is_data=1'b0; byte_out=8'h00; end
        endcase
    end
endmodule

`default_nettype wire
