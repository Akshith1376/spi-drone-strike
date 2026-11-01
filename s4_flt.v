`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.10.2026 00:24:11
// Design Name: 
// Module Name: s4_flt
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
// slave 4 - fault / game. buzzer + warning leds
// 04 short chirp, 05 long chirp, 07 fault (dat[3:0] -> warn leds), 08 clear
module s4_flt(input clk, got, input [7:0] c, d, output reg [3:0] wl, output bz);
    reg [26:0] bt = 0;
    reg [16:0] dv = 0, cn = 0;
    reg tg = 0;
    assign bz = tg;
    initial wl = 0;
    always @(posedge clk) begin
        if (bt != 0) begin
            bt <= bt - 1;
            if (cn >= dv) begin cn <= 0; tg <= ~tg; end else cn <= cn + 1;
        end else tg <= 0;
        if (got) case (c)
            8'h04: begin bt <= 10_000_000; dv <= 25000; end
            8'h05: begin bt <= 30_000_000; dv <= 16666; end
            8'h07: begin bt <= 50_000_000; dv <= 50000; wl <= (d[3:0] == 0) ? 4'hF : d[3:0]; end
            8'h08: begin wl <= 0; bt <= 0; end
        endcase
    end
endmodule
