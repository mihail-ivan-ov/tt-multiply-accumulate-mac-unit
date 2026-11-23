// ============================================================================
// signed int4 MAC cell + 2x2 output-stationary systolic array + Tiny Tapeout wrapper
// Top module: tt_um_mihail_ivan_ov_multiply_accumulate_mac_unit
// ============================================================================

module mac_cell #(
  parameter DW = 4,
  parameter AW = 12
)(
  input  wire                  clk,
  input  wire                  rst_n,
  input  wire                  clear,
  input  wire                  en,
  input  wire signed [DW-1:0]  a_in,
  input  wire signed [DW-1:0]  b_in,
  output reg  signed [DW-1:0]  a_out,
  output reg  signed [DW-1:0]  b_out,
  output reg  signed [AW-1:0]  acc
);
  wire signed [2*DW-1:0] prod     = a_in * b_in;
  wire signed [AW-1:0] prod_ext = {{(AW-2*DW){prod[2*DW-1]}}, prod};

  always @(posedge clk) begin
    if (!rst_n) begin
      acc   <= {AW{1'b0}};
      a_out <= {DW{1'b0}};
      b_out <= {DW{1'b0}};
    end else if (clear) begin
      acc   <= {AW{1'b0}};
      a_out <= {DW{1'b0}};
      b_out <= {DW{1'b0}};
    end else if (en) begin
      a_out <= a_in;
      b_out <= b_in;
      acc   <= acc + prod_ext;
    end
  end
endmodule


module mxu2x2 #(
  parameter DW = 4,
  parameter AW = 12
)(
  input  wire                 clk,
  input  wire                 rst_n,
  input  wire                 clear,
  input  wire                 en,
  input  wire signed [DW-1:0] a0,
  input  wire signed [DW-1:0] a1,
  input  wire signed [DW-1:0] b0,
  input  wire signed [DW-1:0] b1,
  output wire signed [AW-1:0] c00,
  output wire signed [AW-1:0] c01,
  output wire signed [AW-1:0] c10,
  output wire signed [AW-1:0] c11
);
  // input skew: row 1 of A and column 1 of B enter one step later
  reg signed [DW-1:0] a1_d, b1_d;
  always @(posedge clk) begin
    if (!rst_n || clear) begin
      a1_d <= {DW{1'b0}};
      b1_d <= {DW{1'b0}};
    end else if (en) begin
      a1_d <= a1;
      b1_d <= b1;
    end
  end

  /* verilator lint_off UNUSEDSIGNAL */
  wire signed [DW-1:0] a00_o, b00_o;
  wire signed [DW-1:0] a01_o, b01_o;
  wire signed [DW-1:0] a10_o, b10_o;
  wire signed [DW-1:0] a11_o, b11_o;
  /* verilator lint_on UNUSEDSIGNAL */

  mac_cell #(.DW(DW), .AW(AW)) u00 (.clk(clk), .rst_n(rst_n), .clear(clear), .en(en),
    .a_in(a0),    .b_in(b0),    .a_out(a00_o), .b_out(b00_o), .acc(c00));

  mac_cell #(.DW(DW), .AW(AW)) u01 (.clk(clk), .rst_n(rst_n), .clear(clear), .en(en),
    .a_in(a00_o), .b_in(b1_d),  .a_out(a01_o), .b_out(b01_o), .acc(c01));

  mac_cell #(.DW(DW), .AW(AW)) u10 (.clk(clk), .rst_n(rst_n), .clear(clear), .en(en),
    .a_in(a1_d),  .b_in(b00_o), .a_out(a10_o), .b_out(b10_o), .acc(c10));

  mac_cell #(.DW(DW), .AW(AW)) u11 (.clk(clk), .rst_n(rst_n), .clear(clear), .en(en),
    .a_in(a10_o), .b_in(b01_o), .a_out(a11_o), .b_out(b11_o), .acc(c11));
endmodule


// ----------------------------------------------------------------------------
// Tiny Tapeout wrapper
//   ui_in[3:0]  data (int4)           uio_in[4:5] result select (00=c00 .. 11=c11)
//   ui_in[5:4]  target reg 0=a0 1=a1  uio_in[6]   en (one clock = one step)
//               2=b0 3=b1             uo_out[7:0] + uio_out[3:0] = 12-bit result
//   ui_in[6]    write strobe
//   ui_in[7]    clear
// ----------------------------------------------------------------------------
module tt_um_mihail_ivan_ov_multiply_accumulate_mac_unit (
  input  wire [7:0] ui_in,
  output wire [7:0] uo_out,
  input  wire [7:0] uio_in,
  output wire [7:0] uio_out,
  output wire [7:0] uio_oe,
  input  wire       ena,
  input  wire       clk,
  input  wire       rst_n
);
  reg signed [3:0] a0, a1, b0, b1;
  always @(posedge clk) begin
    if (!rst_n) begin
      a0 <= 4'sd0; a1 <= 4'sd0; b0 <= 4'sd0; b1 <= 4'sd0;
    end else if (ui_in[6]) begin
      case (ui_in[5:4])
        2'd0: a0 <= ui_in[3:0];
        2'd1: a1 <= ui_in[3:0];
        2'd2: b0 <= ui_in[3:0];
        2'd3: b1 <= ui_in[3:0];
      endcase
    end
  end

  wire signed [11:0] c00, c01, c10, c11;

  mxu2x2 #(.DW(4), .AW(12)) core (
    .clk(clk), .rst_n(rst_n), .clear(ui_in[7]), .en(uio_in[6]),
    .a0(a0), .a1(a1), .b0(b0), .b1(b1),
    .c00(c00), .c01(c01), .c10(c10), .c11(c11)
  );

  reg [11:0] sel;
  always @* begin
    case (uio_in[5:4])
      2'd0:    sel = c00;
      2'd1:    sel = c01;
      2'd2:    sel = c10;
      default: sel = c11;
    endcase
  end

  assign uo_out  = sel[7:0];
  assign uio_out = {4'b0000, sel[11:8]};
  assign uio_oe  = 8'h0F;

  wire _unused = &{ena, uio_in[7], uio_in[3:0], 1'b0};
endmodule
