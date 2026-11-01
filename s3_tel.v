`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.10.2026 00:23:34
// Design Name: 
// Module Name: s3_tel
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
// slave 3 - telemetry. ms = mission count, hs = hits (both bcd)
module s3_tel(input clk, got, input [7:0] c, d, output reg [7:0] ms, hs);
    function [7:0] inc(input [7:0] x);
        inc = (x[3:0] == 9) ? ((x[7:4] == 9) ? 8'h00 : {x[7:4] + 4'd1, 4'd0})
                            : {x[7:4], x[3:0] + 4'd1};
    endfunction
    initial begin ms = 0; hs = 0; end
    always @(posedge clk) if (got) case (c)
        8'h03: ms <= inc(ms);
        8'h05: hs <= inc(hs);
        8'h08: if (d[0]) begin ms <= 0; hs <= 0; end
    endcase
endmodule
