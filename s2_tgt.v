`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.10.2026 00:23:00
// Design Name: 
// Module Name: s2_tgt
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
// slave 2 - target ctrl
// st: 0 idle, 1 searching, 2 found, 3 locking, 4 locked, 5 impact
// START MISSION dat = {tx,ty}.  DETECT dat = {ax,ay}, lock only if aim is within 1 cell
module s2_tgt #(parameter TS = 200_000_000, TL = 150_000_000)(
    input clk, got, input [7:0] c, d,
    output reg [2:0] st, output reg [7:0] tg
);
    reg [27:0] tm;
    wire [3:0] dx = (d[7:4] >= tg[7:4]) ? d[7:4] - tg[7:4] : tg[7:4] - d[7:4];
    wire [3:0] dy = (d[3:0] >= tg[3:0]) ? d[3:0] - tg[3:0] : tg[3:0] - d[3:0];
    initial begin st = 0; tg = 0; tm = 0; end

    always @(posedge clk) begin
        if (st == 1 || st == 3) tm <= tm + 1; else tm <= 0;
        if (st == 1 && tm == TS) st <= 2;
        if (st == 3 && tm == TL) st <= 4;
        if (got) case (c)
            8'h03: begin tg <= d; st <= 1; tm <= 0; end
            8'h04: if (st == 2 && dx <= 1 && dy <= 1) begin st <= 3; tm <= 0; end
            8'h05: if (st == 4) st <= 5;
            8'h06, 8'h07, 8'h08: st <= 0;
        endcase
    end
endmodule
