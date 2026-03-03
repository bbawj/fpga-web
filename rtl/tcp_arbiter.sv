module tcp_arbiter #(
    parameter MSS = 1464
) (
    input clk,
    input rxc,
    input rst,
    // the pkt is coming from the wire
    input is_rx,
    input tcp::packet_t pkt,
    // assert to start transferring payload data into buffer
    input tcp_rx_payload_valid,
    input [7:0] tcp_rx_payload_data,
    input tcp_rx_payload_rd_en,
    output [31:0] tcp_rx_payload_rd_data,
    // TODO; when handling more than 1 TCP, we need to identify by addr and
    // port
    // input tcp_rx_payload_peer_addr,
    // input [18:0] tcp_rx_payload_addr,

    // TCP_SM deems payload is good
    input sm_accept_payload,
    // TCP_SM deems payload is bad or there is no payload
    input sm_reject_payload,
    // upper layer is trying to send a packet
    input is_tx,
    input [31:0] to_send_peer_addr,
    input [15:0] to_send_peer_port,
    input [18:0] to_send_payload_addr,
    input [15:0] to_send_payload_size,
    // TCB input updated from TCP state machine transitions
    input tcp::tcb_t i_tcb,
    // Enable TCP echo, which directly transitions an incoming TCP payload
    // packet to TX state. Connects the incoming EBR to outgoing EBR
    input tcp_echo_en,

    output reg rdy,
    // control signal to the TCP_SM to tell it the TCB is rx or tx
    output reg sm_tcp_is_tx,
    output reg sm_tcp_is_rx,
    // Tells the upper layer of the network stack that there is a new TCP payload
    // available for tcp parameters in o_tcb
    output reg tcp_payload_valid,
    output tcp::tcb_t o_tcb
);

  // TODO: array of size MAX_CONNECTIONS
  tcp::tcb_t tcb;
  // TODO: control for correct TCB when there is more than 1
  ebr #(
      .SIZE(tcp::MSS),
      .RD_WIDTH(32)
  ) tcp_incoming_buffer (
      .wr_clk (rxc),
      .wr_en  (tcp_rx_payload_valid),
      .wr_addr('0),
      .wr_data(tcp_rx_payload_data),
      .rd_clk (clk),
      .rd_en  (tcp_rx_payload_rd_en),
      .rd_addr('0),
      .rd_data(tcp_rx_payload_rd_data)
  );


  typedef enum {
    IDLE,
    RX_PACKET,
    WAIT_SM_RX_TRANSITION,
    TX_PACKET,
    WAIT_SM_TX_TRANSITION
  } state_t;
  state_t state = IDLE;

  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      sm_tcp_is_rx <= 0;
      tcp_payload_valid <= 0;
      tcb <= '0;
      o_tcb <= '0;
      rdy <= '0;
    end else begin
      case (state)
        IDLE: begin
          rdy <= '1;
          tcp_payload_valid <= 0;
          sm_tcp_is_rx <= 0;
          if (is_rx) begin
            rdy   <= 0;
            state <= RX_PACKET;
            // TODO: should block new connections if out of TCBs
            if (tcb.peer_port == pkt.peer_port && tcb.peer_addr == pkt.peer_addr) begin
              tcb.window <= pkt.window;
            end else begin
              // no matching TCB, create a new one
              // for now we do no validation of other fields, assume they are 0
              tcb.peer_addr <= pkt.peer_addr;
              tcb.peer_port <= pkt.peer_port;
              tcb.sequence_num <= '0;
              tcb.ack_num <= '0;
              tcb.window <= '0;
              tcb.state <= tcp::LISTEN;
            end
          end else if (is_tx) begin
            state <= TX_PACKET;
          end
        end
        RX_PACKET: begin
          o_tcb <= tcb;
          sm_tcp_is_rx <= 'b1;
          state <= WAIT_SM_RX_TRANSITION;
        end
        WAIT_SM_RX_TRANSITION: begin
          sm_tcp_is_rx <= 0;
          if (sm_accept_payload) begin
            rdy <= 1;
            tcp_payload_valid <= 1'b1;
            // TODO: copy to SDRAM
            tcb <= i_tcb;
            state <= IDLE;
            if (tcp_echo_en) begin
              state <= TX_PACKET;
            end
          end else if (sm_reject_payload) begin
            state <= IDLE;
            tcb   <= i_tcb;
            rdy   <= 1;
          end
        end
        TX_PACKET: begin
          o_tcb <= tcb;
          sm_tcp_is_tx <= 'b1;
          state <= WAIT_SM_TX_TRANSITION;
          o_tcb.to_be_sent_wr_ptr <= tcb.to_be_sent_wr_ptr + 1;
          o_tcb.to_be_sent[tcb.to_be_sent_wr_ptr].ack_num <= tcb.ack_num;
          o_tcb.to_be_sent[tcb.to_be_sent_wr_ptr].sequence_num <= tcb.sequence_num;
          if (tcp_echo_en) begin
            o_tcb.to_be_sent[tcb.to_be_sent_wr_ptr].payload_addr <= '0;
            o_tcb.to_be_sent[tcb.to_be_sent_wr_ptr].payload_size <= pkt.payload_size;
          end else begin
            o_tcb.to_be_sent[tcb.to_be_sent_wr_ptr].payload_addr <= to_send_payload_addr;
            o_tcb.to_be_sent[tcb.to_be_sent_wr_ptr].payload_size <= to_send_payload_size;
          end
        end
        WAIT_SM_TX_TRANSITION: begin
          sm_tcp_is_tx <= 0;
          if (sm_accept_payload) begin
            rdy   <= 1;
            tcb   <= i_tcb;
            state <= IDLE;
          end else if (sm_reject_payload) begin
            state <= IDLE;
            rdy   <= 1;
          end
        end
        default: begin
        end
      endcase
    end
  end
endmodule
