`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.10.2026 00:24:44
// Design Name: 
// Module Name: u_rx
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
module u_rx #(parameter B = 868)(input clk, rx, output reg [7:0] d, output reg v);
    reg [1:0] r = 2'b11;
    reg [15:0] c = 0;
    reg [3:0] n = 0;
    reg run = 0;
    initial begin d = 0; v = 0; end
    always @(posedge clk) begin
        r <= {r[0], rx};
        v <= 0;
        if (!run) begin
            if (!r[1]) begin run <= 1; c <= B/2; n <= 0; end
        end else if (c == 0) begin
            c <= B - 1;
            if (n == 0) begin
                if (r[1]) run <= 0; else n <= 1;     // false start
            end else if (n <= 8) begin
                d <= {r[1], d[7:1]}; n <= n + 1;
            end else begin
                run <= 0; v <= 1;
            end
        end else c <= c - 1;
    end
endmodule