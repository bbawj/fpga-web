module test_tcp (
    input rst,
    input clk,
    input sys_clk,
    input decode_valid,
    input [7:0] decode_din,
    input tcp_payload_rd_en,
    output [31:0] tcp_payload_rd_data,
    output reg [15:0] tcp_source_port,
    output reg [15:0] tcp_dest_port,
    output reg [31:0] tcp_sequence_num,
    output reg [31:0] tcp_ack_num,
    output reg [15:0] tcp_payload_size,
    output reg [7:0] tcp_flags,
    output reg [15:0] tcp_window,
    output tcp::tcb_t n_tcb,
    output reg send_syn_en,
    output reg send_ack_en,
    output reg decode_err,
    output reg decode_done
);
  parameter int MSS = 1460;
  reg [31:0] ip_sa;
  reg [31:0] ip_da;
  reg [3:0] ip_ihl;
  reg [15:0] ip_payload_size;
  reg ip_done;

  ip_decode ip_dec (
      .clk(clk),
      .rst(rst),
      .valid(decode_valid),
      .din(decode_din),
      .sa(ip_sa),
      .da(ip_da),
      .packet_size(ip_payload_size),
      .ihl(ip_ihl),
      .err(),
      .done(ip_done)
  );

  reg [7:0] tcp_payload;
  reg tcp_payload_valid;
  tcp_decode dec (
      .clk(clk),
      .rst(rst),
      .valid(ip_done),
      .din(decode_din),
      .ip_sa(ip_sa),
      .ip_da(ip_da),
      .ip_ihl(ip_ihl),
      .ip_payload_size(ip_payload_size),

      .source_port(tcp_source_port),
      .dest_port(tcp_dest_port),
      .sequence_num(tcp_sequence_num),
      .flags(tcp_flags),
      .ack_num(tcp_ack_num),
      .window(tcp_window),
      .payload(tcp_payload),
      .payload_valid(tcp_payload_valid),
      .payload_size(tcp_payload_size),

      .done(decode_done),
      .err (decode_err)
  );

  ebr #(
      .SIZE(MSS),
      .RD_WIDTH(32)
  ) tcp_incoming_buffer (
      .wr_clk (clk),
      .wr_en  (tcp_payload_valid),
      .wr_addr(0),
      .wr_data(tcp_payload),
      .rd_clk (sys_clk),
      .rd_en  (tcp_payload_rd_en),
      .rd_addr(0),
      .rd_data(tcp_payload_rd_data)
  );

  reg sm_accept_payload;
  reg tcp_packet_valid, tcp_packet_rx;
  tcp_arbiter _arb (
      .clk(sys_clk),
      .rst(rst),
      .valid(tcp_packet_valid),
      .is_rx(tcp_packet_rx),
      .pkt(packet),
      .sm_accept_payload(sm_accept_payload),
      .i_tcb(),

      .tcp_is_rx(),
      .tcp_payload_valid(),
      .tcp_payload_addr(),
      .o_tcb()
  );

  tcp::packet_t packet;
  always @(posedge clk) begin
    if (decode_done && !decode_err) begin
      packet.payload_addr = 0;
      packet.payload_size = tcp_payload_size;
      packet.checksum = 0;
      packet.flags = tcp_flags;
      packet.peer_port = tcp_source_port;
      packet.window = tcp_window;
      packet.ack_num = tcp_ack_num;
      packet.sequence_num = tcp_sequence_num;
      tcp_packet_rx <= 1;
      tcp_packet_valid <= 1;
    end

  end

endmodule
