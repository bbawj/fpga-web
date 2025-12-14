module test_ip(
  input clk,
  input decode_rst,
  input decode_valid,
  input [7:0] decode_din,
  output reg [31:0] decode_sa,
  output reg [31:0] decode_da,
  output reg decode_err,
  output reg decode_done
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
  endmodule
