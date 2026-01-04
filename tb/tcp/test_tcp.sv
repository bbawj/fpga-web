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
  reg [31:0] ip_sa;
  reg [31:0] ip_da;
  reg [7:0] ip_ihl;
  reg [15:0] ip_payload_size;
  reg ip_done;

  ip_decode ip_dec (
    .clk(clk),
    .rst(decode_rst),
    .valid(decode_valid),
    .din(decode_din),
    .sa(ip_sa),
    .da(ip_da),
    .packet_size(ip_payload_size),
    .ihl(ip_ihl),
    .err(),
    .done(ip_done)
    );

  tcp_decode dec (
    .clk(clk),
    .rst(decode_rst),
    .valid(ip_done),
    .din(decode_din),
    .ip_sa(ip_sa),
    .ip_da(ip_da),
    .ip_ihl(ip_ihl),
    .ip_payload_size(ip_payload_size),

    .source_port(decode_source_port),
    .dest_port(decode_dest_port),
    .sequence_num(decode_sequence_num),
    .ack_num(decode_ack_num),

    .done(decode_done),
    .err(decode_err)
    );

  endmodule
