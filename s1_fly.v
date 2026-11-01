`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.10.2026 00:22:26
// Design Name: 
// Module Name: s1_fly
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
// slave 1 - flight ctrl
// st: 0 idle, 1 armed, 2 airborne, 3 missile away, 4 rtb, 5 abort
module s1_fly(input clk, got, input [7:0] c, d, output reg [2:0] st, output reg [3:0] ax);
    initial begin st = 0; ax = 0; end
    always @(posedge clk) if (got) case (c)
        8'h01: if (st == 0) st <= 1;
        8'h02: if (st == 1) st <= 2;
        8'h05: if (st == 2) st <= 3;
        8'h06: if (st == 2 || st == 3) st <= 4;
        8'h07: st <= 5;
        8'h08: st <= 0;
        8'h09: ax <= d[7:4];
    endcase
endmodule