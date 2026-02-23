module test_tcp_sm (
    input rst,
    input clk,
    input tcp_packet_valid,
    input tcp_packet_rx,
    input tcp_packet_tx,
    input tcp_echo_en,
    input tcp::packet_t packet,
    output pkt_tx_en,
    output tcp::packet_t pkt_to_send,
    output tcp_payload_valid,
    output tcp_arb_rdy,
    output [tcp::BUFF_WIDTH-1:0] tcp_payload_addr,
    output tcp::tcb_t tcb_arb,
    output reg sm_accept_payload,
    output reg sm_reject_payload,
    output tcp::tcb_t tcb_sm
);
  reg tcp_sm_is_rx, tcp_sm_is_tx;
  tcp_arbiter _arb (
      .clk(clk),
      .rst(rst),
      .valid(tcp_packet_valid),
      .rdy(tcp_arb_rdy),
      .is_tx(tcp_packet_tx),
      .to_send_payload_addr(),
      .to_send_payload_size(),
      .is_rx(tcp_packet_rx),
      .pkt(packet),
      .sm_reject_payload(sm_reject_payload),
      .sm_accept_payload(sm_accept_payload),
      .i_tcb(tcb_sm),
      .tcp_echo_en(tcp_echo_en),

      .tcp_is_rx(tcp_sm_is_rx),
      .tcp_is_tx(tcp_sm_is_tx),
      .tcp_payload_valid(tcp_payload_valid),
      .tcp_payload_addr(tcp_payload_addr),
      .o_tcb(tcb_arb)
  );

  tcp_sm sm (
      .clk(clk),
      .rst(rst),
      .current_tcb(tcb_arb),
      .is_tx(tcp_sm_is_tx),
      .is_rx(tcp_sm_is_rx),
      .incoming_pkt(packet),

      .tx_en(pkt_tx_en),
      .pkt_to_send(pkt_to_send),
      .next_tcb(tcb_sm),
      .accept_payload(sm_accept_payload),
      .reject_payload(sm_reject_payload)
  );

endmodule
