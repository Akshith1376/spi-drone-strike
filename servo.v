`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.10.2026 00:25:47
// Design Name: 
// Module Name: servo
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
// 50Hz servo pwm, p = 0..15 -> 1.0 .. 2.0 ms
module servo(input clk, input [3:0] p, output reg o);
    reg [21:0] c = 0;
    wire [17:0] w = 18'd100000 + p * 13'd6667;
    always @(posedge clk) begin
        c <= (c == 1999999) ? 0 : c + 1;
        o <= (c < w);
    end
endmodule
