`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.10.2026 00:25:19
// Design Name: 
// Module Name: u_tx
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
module u_tx #(parameter B = 868)(input clk, input [7:0] d, input go, output reg tx, output reg bz);
    reg [9:0] sh = 10'h3FF;
    reg [15:0] c = 0;
    reg [3:0] n = 0;
    initial begin tx = 1; bz = 0; end
    always @(posedge clk) begin
        if (!bz) begin
            if (go) begin sh <= {1'b1, d, 1'b0}; bz <= 1; c <= B - 1; n <= 0; tx <= 0; end
        end else if (c == 0) begin
            c <= B - 1;
            if (n == 9) begin bz <= 0; tx <= 1; end
            else begin sh <= {1'b1, sh[9:1]}; tx <= sh[1]; n <= n + 1; end
        end else c <= c - 1;
    end
endmodule
