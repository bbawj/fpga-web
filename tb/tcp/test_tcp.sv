module test_tcp(
  input clk,
  input decode_rst,
  input decode_valid,
  input [7:0] decode_din,
  output reg [15:0] decode_source_port,
  output reg [15:0] decode_dest_port,
  output reg [31:0] decode_sequence_num,
  output reg [31:0] decode_ack_num,
  output reg decode_err,
  output reg decode_done
  );

  tcp_decode dec (
    .clk(clk),
    .rst(decode_rst),
    .valid(decode_valid),
    .din(decode_din),

    .source_port(decode_source_port),
    .dest_port(decode_dest_port),
    .sequence_num(decode_sequence_num),
    .ack_num(decode_ack_num),

    .done(decode_done),
    .err(decode_err)
    );

  endmodule
