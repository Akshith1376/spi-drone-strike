`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.10.2026 00:19:59
// Design Name: 
// Module Name: top
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
// top: uart bridge (pc) -> spi master -> 4 slaves
// pc frame : AA ss cmd dat
// fpga resp: 55 ss stat   (stat = slave status as it was when the frame started)
module top #(parameter TS = 200_000_000, TL = 150_000_000)(
    input clk, rx,
    output tx,
    output [15:0] led,
    output [6:0] seg,
    output [7:0] an,
    output [3:0] ja            // ja[0] buzzer, ja[1] drone servo, ja[2] target servo
);
    // ---- uart bridge ----
    wire [7:0] rd; wire rv, txb;
    reg [7:0] txd = 0, cm = 0, dt = 0, sb = 0;
    reg txg = 0, go = 0;
    reg [1:0] ss = 0;
    reg [3:0] s = 0;
    wire mdone, mbusy, sclk, mosi, miso;
    wire [3:0] cs;
    wire [15:0] mrx;
    wire [3:0] mi;
    assign miso = |mi;

    u_rx urx(.clk(clk), .rx(rx), .d(rd), .v(rv));
    u_tx utx(.clk(clk), .d(txd), .go(txg), .tx(tx), .bz(txb));
    spi_m #(50) m(.clk(clk), .rst(1'b0), .st(go), .ss(ss), .tx({cm, dt}), .miso(miso),
                  .sclk(sclk), .mosi(mosi), .cs_n(cs), .busy(mbusy), .done(mdone), .rx(mrx));

    always @(posedge clk) begin
        go <= 0; txg <= 0;
        case (s)
            0: if (rv && rd == 8'hAA) s <= 1;
            1: if (rv) begin ss <= rd[1:0]; s <= 2; end
            2: if (rv) begin cm <= rd; s <= 3; end
            3: if (rv) begin dt <= rd; go <= 1; s <= 4; end
            4: if (mdone) begin sb <= mrx[15:8]; s <= 5; end
            5: if (!txb && !txg) begin txd <= 8'h55; txg <= 1; s <= 6; end
            6: if (!txb && !txg) begin txd <= {6'b0, ss}; txg <= 1; s <= 7; end
            7: if (!txb && !txg) begin txd <= sb; txg <= 1; s <= 0; end
        endcase
    end

    // ---- slaves ----
    wire [7:0] c1, d1, c2, d2, c3, d3, c4, d4, tg, msb, hsb;
    wire g1, g2, g3, g4, bz;
    wire [2:0] st1, st2;
    wire [3:0] ax, wl;

    spi_s u1(.clk(clk), .sclk(sclk), .mosi(mosi), .cs_n(cs[0]), .stat({ax, 1'b0, st1}), .miso(mi[0]), .cmd(c1), .dat(d1), .got(g1));
    spi_s u2(.clk(clk), .sclk(sclk), .mosi(mosi), .cs_n(cs[1]), .stat({5'b0, st2}),     .miso(mi[1]), .cmd(c2), .dat(d2), .got(g2));
    spi_s u3(.clk(clk), .sclk(sclk), .mosi(mosi), .cs_n(cs[2]), .stat(hsb),             .miso(mi[2]), .cmd(c3), .dat(d3), .got(g3));
    spi_s u4(.clk(clk), .sclk(sclk), .mosi(mosi), .cs_n(cs[3]), .stat({4'b0, wl}),      .miso(mi[3]), .cmd(c4), .dat(d4), .got(g4));

    s1_fly a1(.clk(clk), .got(g1), .c(c1), .d(d1), .st(st1), .ax(ax));
    s2_tgt #(TS, TL) a2(.clk(clk), .got(g2), .c(c2), .d(d2), .st(st2), .tg(tg));
    s3_tel a3(.clk(clk), .got(g3), .c(c3), .d(d3), .ms(msb), .hs(hsb));
    s4_flt a4(.clk(clk), .got(g4), .c(c4), .d(d4), .wl(wl), .bz(bz));

    servo sv1(.clk(clk), .p(ax), .o(ja[1]));
    servo sv2(.clk(clk), .p(tg[7:4]), .o(ja[2]));
    sseg  sg(.clk(clk), .d({msb, hsb}), .seg(seg), .an(an));

    assign ja[0] = bz;
    assign ja[3] = 1'b0;
    assign led = {wl, 4'b0, 1'b0, st2, 1'b0, st1};
endmodule