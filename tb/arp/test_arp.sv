module test_arp(
  input clk,
  input decode_rst,
  input decode_valid,
  input [7:0] decode_din,
  output reg [47:0] decode_sha,
  output reg [47:0] decode_tha,
  output reg [31:0] decode_spa,
  output reg [31:0] decode_tpa,
  output reg decode_err,
  output reg decode_done,

  input encode_rst,
  input encode_en,
  input reg [47:0] encode_tha,
  input reg [31:0] encode_tpa,
  output reg encode_ovalid,
  output reg [7:0] encode_dout
  );
  arp_encode enc (
    .clk(clk),
    .rst(encode_rst),
    .en(encode_en),
    .tha(encode_tha),
    .tpa(encode_tpa),
    .ovalid(encode_ovalid),
    .dout(encode_dout)
    );

  arp_decode dec (
    .clk(clk),
    .rst(decode_rst),
    .valid(decode_valid),
    .din(decode_din),
    .sha(decode_sha),
    .tha(decode_tha),
    .spa(decode_spa),
    .tpa(decode_tpa),
    .err(decode_err),
    .done(decode_done)
    );
  endmodule
