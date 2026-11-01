`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.10.2026 00:21:40
// Design Name: 
// Module Name: spi_s
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
// spi slave core, mode 0, 16 bit frame {cmd, dat}
// master gets {stat, 8'h00} back on miso (stat is latched at cs fall)
module spi_s(
    input clk, sclk, mosi, cs_n,
    input [7:0] stat,
    output miso,
    output reg [7:0] cmd, dat,
    output reg got
);
    reg [2:0] sc = 3'b000, cc = 3'b111;
    reg [1:0] mo = 0;
    reg [15:0] rx = 0, tx = 0;
    reg [4:0] n = 0;

    wire rise = (sc[2:1] == 2'b01);
    wire fall = (sc[2:1] == 2'b10);
    wire csf  = (cc[2:1] == 2'b10);
    wire csr  = (cc[2:1] == 2'b01);

    assign miso = cs_n ? 1'b0 : tx[15];

    initial begin cmd = 0; dat = 0; got = 0; end

    always @(posedge clk) begin
        sc <= {sc[1:0], sclk};
        cc <= {cc[1:0], cs_n};
        mo <= {mo[0], mosi};
        got <= 0;
        if (csf) begin
            tx <= {stat, 8'h00}; n <= 0;
        end else if (!cc[1]) begin
            if (rise) begin rx <= {rx[14:0], mo[1]}; n <= n + 1; end
            if (fall) tx <= {tx[14:0], 1'b0};
        end
        if (csr && n == 16) begin
            cmd <= rx[15:8]; dat <= rx[7:0]; got <= 1;
        end
    end
endmodule
