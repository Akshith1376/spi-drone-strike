`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.10.2026 00:26:48
// Design Name: 
// Module Name: tb
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
`timescale 1ns/1ps
module tb;
    reg clk = 0, rx = 1;
    wire tx; wire [15:0] led; wire [6:0] seg; wire [7:0] an; wire [3:0] ja;
    top #(.TS(200000), .TL(150000)) dut(.clk(clk), .rx(rx), .tx(tx), .led(led), .seg(seg), .an(an), .ja(ja));
    always #5 clk = ~clk;

    task ub(input [7:0] b); integer i; begin
        rx = 0; #8680;
        for (i = 0; i < 8; i = i + 1) begin rx = b[i]; #8680; end
        rx = 1; #8680;
    end endtask

    task cmd(input [7:0] ss, c, d); begin
        ub(8'hAA); ub(ss); ub(c); ub(d);
        #800000;
    end endtask

    initial begin
        #1000;
        cmd(0, 1, 0);  $display("s1=%0d want 1", dut.st1);
        cmd(0, 2, 0);  $display("s1=%0d want 2", dut.st1);
        cmd(1, 3, 8'h58); cmd(2, 3, 0);
        $display("s2=%0d want 1 (searching)", dut.st2);
        #3000000;      $display("s2=%0d want 2 (found)", dut.st2);
        cmd(1, 4, 8'h9F); $display("far aim -> s2=%0d want 2 (no lock)", dut.st2);
        cmd(1, 4, 8'h58); $display("good aim -> s2=%0d want 3 (locking)", dut.st2);
        #3000000;      $display("s2=%0d want 4 (locked)", dut.st2);
        cmd(0, 5, 0);  $display("s1=%0d want 3", dut.st1);
        cmd(1, 5, 0);  $display("s2=%0d want 5 (impact)", dut.st2);
        cmd(2, 5, 0);  $display("hits=%h want 01  missions=%h want 01", dut.hsb, dut.msb);
        $finish;
    end
endmodule