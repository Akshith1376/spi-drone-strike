`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.10.2026 00:21:05
// Design Name: 
// Module Name: spi_m
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
// spi master, mode 0, 16 bit frame, msb first
// DIV = sys clk cycles per half sclk period (50 -> 1 MHz sclk @100MHz)
module spi_m #(parameter DIV = 50)(
    input clk, rst, st,
    input [1:0] ss,
    input [15:0] tx,
    input miso,
    output reg sclk, mosi,
    output reg [3:0] cs_n,
    output reg busy, done,
    output reg [15:0] rx
);
    reg [1:0] s;
    reg [15:0] sh;
    reg [7:0] c;
    reg [4:0] bc;

    initial begin s = 0; sclk = 0; mosi = 0; cs_n = 4'hF; busy = 0; done = 0; rx = 0; c = 0; bc = 0; sh = 0; end

    always @(posedge clk) begin
        done <= 0;
        if (rst) begin
            s <= 0; sclk <= 0; mosi <= 0; cs_n <= 4'hF; busy <= 0; c <= 0; bc <= 0;
        end else case (s)
            0: if (st) begin
                sh <= tx; mosi <= tx[15]; cs_n <= ~(4'b0001 << ss);
                busy <= 1; c <= 0; bc <= 0; s <= 1;
            end
            1: if (c == DIV-1) begin c <= 0; s <= 2; end else c <= c + 1;   // cs setup
            2: if (c == DIV-1) begin
                c <= 0;
                sclk <= ~sclk;
                if (!sclk) begin                    // rising edge -> sample
                    rx <= {rx[14:0], miso};
                    bc <= bc + 1;
                end else begin                      // falling edge -> shift
                    sh <= {sh[14:0], 1'b0};
                    mosi <= sh[14];
                    if (bc == 16) s <= 3;
                end
            end else c <= c + 1;
            3: if (c == DIV-1) begin                // cs hold
                cs_n <= 4'hF; busy <= 0; done <= 1; s <= 0; c <= 0;
            end else c <= c + 1;
        endcase
    end
endmodule
