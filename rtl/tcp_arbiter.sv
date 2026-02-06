module tcp_arbiter #(
    parameter MSS = 1464
) (
    input clk,
    input rst,
    input valid,
    // the pkt is coming from the wire
    input is_rx,
    input tcp::packet_t pkt,
    input sm_accept_payload,
    // TCB input updated from TCP state machine transitions
    input tcp::tcb_t i_tcb,

    output tcp_is_rx,
    // Tells the upper layer of the network stack that there is a new TCP payload
    // available at tcp_payload_addr.
    output tcp_payload_valid,
    // Address of the payload in the TCP incoming buffer
    output [tcp::BUFF_WIDTH-1:0] tcp_payload_addr,
    output tcp::tcb_t o_tcb
);

  // TODO: array of
  tcp::tcb_t tcb;

  typedef enum {
    IDLE,
    RX_PACKET
  } state_t;
  state_t state = IDLE;

  always @(posedge clk) begin
    case (state)
      IDLE: begin
        if (valid) begin
          if (is_rx) begin
            state <= RX_PACKET;
            if (tcb.source_port == pkt.peer_port && tcb.ip_source_addr == pkt.ip_source_addr) begin
              tcb.sequence_num <= pkt.sequence_num;
              tcb.ack_num <= pkt.ack_num;
              tcb.window <= pkt.window;
            end else begin
              // no matching TCB, create a new one
              // for now we do no validation of other fields, assume they are 0
              tcb.ip_source_addr <= pkt.ip_source_addr;
              tcb.source_port <= pkt.peer_port;
              tcb.sequence_num <= '0;
              tcb.ack_num <= '0;
              tcb.window <= '0;
              tcb.state <= tcp::LISTEN;
            end
          end
        end
      end
      RX_PACKET: begin
        o_tcb <= tcb;
        tcp_is_rx <= 'b1;
        if (sm_accept_payload) begin
          tcp_payload_valid <= 1'b1;
          tcp_payload_addr <= pkt.payload_addr;
          tcb <= i_tcb;
        end
      end
      default: begin
      end
    endcase
  end

  // reg fifo_rd_en = 0;
  // wire fifo_empty, fifo_full;
  // reg [$bits(tcp::packet_t) - 1:0] next_pkt;
  // fifo #(
  //     .DATA_WIDTH($bits(tcp::packet_t))
  // ) _fifo (
  //     .clk  (clk),
  //     .rst  (rst),
  //     .wr_en(valid),
  //     .din  (pkt_to_send),
  //     .full (fifo_full),
  //     .rd_en(fifo_rd_en),
  //     .dout (next_pkt),
  //     .empty(fifo_empty),
  //     .count()
  // );
  //
  // always @(posedge clk) begin
  //   case (state)
  //     IDLE: begin
  //       if (!fifo_empty && mac_encoder_ready) begin
  //         state <= TX;
  //         fifo_rd_en <= 1'b1;
  //
  //         mac_encode_en <= 1'b1;
  //       end
  //     end
  //     TX: begin
  //       fifo_rd_en <= 1'b0;
  //       if (mac_encoder_send_next) begin
  //         ip_encode_en  <= 1'b1;
  //         ip_packet_len <= next_pkt.payload_size + 16'd40;
  //       end
  //       if (ip_encode_done) begin
  //         tcp_dest_port <= next_pkt.dest_port;
  //         tcp_sequence_num <= next_pkt.sequence_num;
  //         tcp_ack_num <= next_pkt.ack_num;
  //         tcp_flags <= next_pkt.flags;
  //         tcp_window <= next_pkt.window;
  //         tcp_encode_en <= 1'b1;
  //       end
  //     end
  //   endcase
  // end

endmodule
