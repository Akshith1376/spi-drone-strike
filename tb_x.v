`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.10.2026 00:52:20
// Design Name: 
// Module Name: tb_x
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
// tb for driving the spi system live from python through vivado's tcl console (see xlive.tcl).
// no uart here: the tcl side pokes go/ss/cm/dt straight into the spi master.
module tb_x;
    reg clk = 0;
    always #5 clk = ~clk;

    reg go = 0;
    reg [1:0] ss = 0;
    reg [7:0] cm = 0, dt = 0;

    wire sclk, mosi, miso, mdone, mbusy;
    wire [3:0] cs, mi, wl, ax;
    wire [15:0] mrx;
    wire [7:0] c1, d1, c2, d2, c3, d3, c4, d4, tg, msb, hsb;
    wire g1, g2, g3, g4, bz;
    wire [2:0] st1, st2;
    assign miso = |mi;

    spi_m #(50) m(.clk(clk), .rst(1'b0), .st(go), .ss(ss), .tx({cm, dt}), .miso(miso),
                  .sclk(sclk), .mosi(mosi), .cs_n(cs), .busy(mbusy), .done(mdone), .rx(mrx));

    spi_s u1(.clk(clk), .sclk(sclk), .mosi(mosi), .cs_n(cs[0]), .stat({ax, 1'b0, st1}), .miso(mi[0]), .cmd(c1), .dat(d1), .got(g1));
    spi_s u2(.clk(clk), .sclk(sclk), .mosi(mosi), .cs_n(cs[1]), .stat({5'b0, st2}),     .miso(mi[1]), .cmd(c2), .dat(d2), .got(g2));
    spi_s u3(.clk(clk), .sclk(sclk), .mosi(mosi), .cs_n(cs[2]), .stat(hsb),             .miso(mi[2]), .cmd(c3), .dat(d3), .got(g3));
    spi_s u4(.clk(clk), .sclk(sclk), .mosi(mosi), .cs_n(cs[3]), .stat({4'b0, wl}),      .miso(mi[3]), .cmd(c4), .dat(d4), .got(g4));

    s1_fly a1(.clk(clk), .got(g1), .c(c1), .d(d1), .st(st1), .ax(ax));
    s2_tgt #(200000, 150000) a2(.clk(clk), .got(g2), .c(c2), .d(d2), .st(st2), .tg(tg));   // 1 sim ms ~ 1 s on the hud
    s3_tel a3(.clk(clk), .got(g3), .c(c3), .d(d3), .ms(msb), .hs(hsb));
    s4_flt a4(.clk(clk), .got(g4), .c(c4), .d(d4), .wl(wl), .bz(bz));
endmodule
