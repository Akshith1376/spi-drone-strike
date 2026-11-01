`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.10.2026 00:26:15
// Design Name: 
// Module Name: sseg
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
// 4 digit mux on an0..an3, active low
module sseg(input clk, input [15:0] d, output reg [6:0] seg, output reg [7:0] an);
    reg [17:0] r = 0;
    reg [3:0] n;
    always @(posedge clk) r <= r + 1;
    always @* begin
        case (r[17:16])
            2'd0: begin an = 8'b11111110; n = d[3:0];   end
            2'd1: begin an = 8'b11111101; n = d[7:4];   end
            2'd2: begin an = 8'b11111011; n = d[11:8];  end
            default: begin an = 8'b11110111; n = d[15:12]; end
        endcase
        case (n)
            0: seg = 7'b1000000; 1: seg = 7'b1111001; 2: seg = 7'b0100100; 3: seg = 7'b0110000;
            4: seg = 7'b0011001; 5: seg = 7'b0010010; 6: seg = 7'b0000010; 7: seg = 7'b1111000;
            8: seg = 7'b0000000; 9: seg = 7'b0010000; default: seg = 7'b1111111;
        endcase
    end
endmodule
