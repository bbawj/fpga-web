module test_tcp_sm (
    input rst,
    input clk,
    input tcp_packet_valid,
    input tcp_sm_is_tx,
    input tcp_packet_rx,
    input tcp::packet_t packet,
    output pkt_tx_en,
    output tcp::packet_t pkt_to_send,
    output tcp_payload_valid,
    output [tcp::BUFF_WIDTH-1:0] tcp_payload_addr,
    output tcp::tcb_t tcb_arb,
    output reg sm_accept_payload,
    output tcp::tcb_t tcb_sm
);
  reg tcp_sm_is_rx;
  tcp_arbiter _arb (
      .clk(clk),
      .rst(rst),
      .valid(tcp_packet_valid),
      .is_rx(tcp_packet_rx),
      .pkt(packet),
      .sm_accept_payload(sm_accept_payload),
      .i_tcb(tcb_sm),

      .tcp_is_rx(tcp_sm_is_rx),
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
      .reject_payload(),
      .accept_payload(sm_accept_payload)
  );

endmodule
