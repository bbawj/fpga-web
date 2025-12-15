module test_ip(
  input clk,
  input decode_rst,
  input decode_valid,
  input [7:0] decode_din,
  output reg [31:0] decode_sa,
  output reg [31:0] decode_da,
  output reg decode_err,
  output reg decode_done,

  input encode_rst,
  input encode_en,
  input reg [31:0] encode_sa,
  input reg [31:0] encode_da,
  input reg [15:0] encode_len,
  output reg encode_valid,
  output reg [7:0] encode_dout
  );

  ip_decode dec (
    .clk(clk),
    .rst(decode_rst),
    .valid(decode_valid),
    .din(decode_din),
    .sa(decode_sa),
    .da(decode_da),
    .err(decode_err),
    .done(decode_done)
    );

 ip_encode enc (
    .clk(clk),
    .rst(encode_rst),
    .en(encode_en),
    .sa(encode_sa),
    .da(encode_da),
    .len(encode_len),
    .ovalid(encode_valid),
    .dout(encode_dout)
  );
  endmodule
