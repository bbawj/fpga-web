module tcp_arbiter #(
    parameter MSS = 1464
) (
    input clk,
    input rxc,
    input rst,
    // the pkt is coming from the wire
    input is_rx,
    input tcp::packet_t packet,
    // assert to start transferring payload data into buffer
    input tcp_rx_payload_valid,
    input [7:0] tcp_rx_payload_data,
    input tcp_rx_payload_rd_en,
    output [31:0] tcp_rx_payload_rd_data,
    output reg tcp_rx_payload_rd_valid,
    // TODO; when handling more than 1 TCP, we need to identify by addr and
    // port
    // input tcp_rx_payload_peer_addr,
    // input [18:0] tcp_rx_payload_addr,

    // upper layer is trying to send a packet
    input is_tx,
    input [31:0] to_send_peer_addr,
    input [15:0] to_send_peer_port,
    input [18:0] to_send_payload_addr,
    input [15:0] to_send_payload_size,
    // Enable TCP echo, which directly transitions an incoming TCP payload
    // packet to TX state. Connects the incoming EBR to outgoing EBR
    input tcp_echo_en,

    output reg rdy,
    // From TCP SM
    output reg send_tcp,
    output tcp::packet_t pkt_to_send,
    // Tells the upper layer of the network stack that there is a new TCP payload
    // available for tcp parameters in o_tcb
    output reg tcp_payload_valid
);

  // TODO: array of size MAX_CONNECTIONS
  tcp::tcb_t tcb;
  // TODO: control for correct TCB when there is more than 1
  ebr #(
      .SIZE(tcp::MSS),
      .RD_WIDTH(32)
  ) tcp_incoming_buffer (
      .wr_clk(rxc),
      .wr_en(tcp_rx_payload_valid),
      .wr_addr('0),
      .wr_data(tcp_rx_payload_data),
      .rd_clk(clk),
      .rd_en(tcp_rx_payload_rd_en),
      .rd_addr('0),
      .rd_valid(),
      .rd_valid_q1(tcp_rx_payload_rd_valid),
      .rd_data(),
      .rd_data_q1(tcp_rx_payload_rd_data)
  );


  typedef enum {
    IDLE,
    RX_PACKET,
    WAIT_SM_RX_TRANSITION,
    TX_PACKET,
    WAIT_SM_TX_TRANSITION
  } state_t;
  state_t state = IDLE;

  tcp::CONN_STATE base_state;
  reg [31:0] base_ack_num;
  reg [31:0] base_sequence_num;
  always @(posedge clk) begin
    tcp_sm_is_rx <= 0;
    tcp_sm_is_tx <= 0;
    case (state)
      RX_PACKET: begin
        base_state <= tcb.state;
        base_sequence_num <= tcb.sequence_num;
        base_ack_num <= tcb.ack_num;
        tcp_sm_is_rx <= 1;
      end
      TX_PACKET: tcp_sm_is_tx <= 1;
      default: begin
      end
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      tcp_payload_valid <= 0;
      tcb <= '0;
      rdy <= '0;
    end else begin
      case (state)
        IDLE: begin
          rdy <= '1;
          tcp_payload_valid <= 0;
          if (is_rx) begin
            rdy   <= 0;
            state <= RX_PACKET;
            // TODO: should block new connections if out of TCBs
            if (tcb.peer_port == packet.peer_port && tcb.peer_addr == packet.peer_addr) begin
              // tcb.window <= pkt.window;
            end else begin
              // no matching TCB, create a new one
              // for now we do no validation of other fields, assume they are 0
              tcb.peer_addr <= packet.peer_addr;
              tcb.peer_port <= packet.peer_port;
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
          state <= WAIT_SM_RX_TRANSITION;
        end
        WAIT_SM_RX_TRANSITION: begin
          tcb.ack_num <= next_ack_num;
          tcb.sequence_num <= next_sequence_num;
          tcb.state <= next_state;
          // TODO: copy to SDRAM
          if (sm_accept_payload) begin
            rdy <= 1;
            tcp_payload_valid <= 1'b1;
            state <= IDLE;
            if (tcp_echo_en) begin
              state <= TX_PACKET;
              tcp_payload_valid <= 1'b0;
            end
          end else if (sm_reject_payload) begin
            state <= IDLE;
            rdy   <= 1;
          end
        end
        TX_PACKET: begin
          state <= WAIT_SM_TX_TRANSITION;
          // o_tcb.to_be_sent[tcb.to_be_sent_wr_ptr].ack_num <= tcb.ack_num;
          // o_tcb.to_be_sent[tcb.to_be_sent_wr_ptr].sequence_num <= tcb.sequence_num + {16'd0, pkt.payload_size};
          // WRITE_TO_SEND_LIST(0, i_payload_size);
          // if (tcp_echo_en) begin
          //   o_tcb.to_be_sent[tcb.to_be_sent_wr_ptr].payload_addr <= '0;
          //   o_tcb.to_be_sent[tcb.to_be_sent_wr_ptr].payload_size <= pkt.payload_size;
          // end else begin
          //   o_tcb.to_be_sent[tcb.to_be_sent_wr_ptr].payload_addr <= to_send_payload_addr;
          //   o_tcb.to_be_sent[tcb.to_be_sent_wr_ptr].payload_size <= to_send_payload_size;
          // end
        end
        WAIT_SM_TX_TRANSITION: begin
          tcb.ack_num <= next_ack_num;
          tcb.sequence_num <= next_sequence_num;
          tcb.state <= next_state;
          if (sm_accept_payload) begin
            rdy <= 1;
            tcb.to_be_ack_wr_ptr <= tcb.to_be_ack_wr_ptr + 1;
            state <= IDLE;
          end else if (sm_reject_payload) begin
            state <= IDLE;
            tcb.to_be_ack_wr_ptr <= tcb.to_be_ack_wr_ptr + 1;
            rdy <= 1;
          end
        end
        default: begin
        end
      endcase
    end
  end

  // control signal to the TCP_SM to tell it the TCB is rx or tx
  reg tcp_sm_is_rx, tcp_sm_is_tx;
  // TCP_SM deems payload is good
  reg sm_accept_payload;
  // TCP_SM deems payload is bad or there is no payload
  reg sm_reject_payload;
  tcp::CONN_STATE next_state;
  reg [31:0] next_ack_num;
  reg [31:0] next_sequence_num;
  tcp_sm sm (
      .clk(clk),
      .rst(rst),
      .base_state(base_state),
      .base_ack_num(base_ack_num),
      .base_sequence_num(base_sequence_num),
      .is_tx(tcp_sm_is_tx),
      .is_rx(tcp_sm_is_rx),
      .i_peer_addr(tcb.peer_addr),
      .i_peer_port(tcb.peer_port),
      .i_ack_num(packet.ack_num),
      .i_sequence_num(packet.sequence_num),
      .i_payload_size(packet.payload_size),
      .i_flags(packet.flags),

      .tx_en(send_tcp),
      .pkt_to_send(pkt_to_send),

      .next_ack_num(next_ack_num),
      .next_sequence_num(next_sequence_num),
      .next_state(next_state),

      .accept_payload(sm_accept_payload),
      .reject_payload(sm_reject_payload)
  );


  // task automatic WRITE_TO_SEND_LIST(input [18:0] pa, input [15:0] ps);
  //   o_tcb.to_be_sent_wr_ptr <= tcb.to_be_sent_wr_ptr + 1;
  //   for (logic [tcp::BUFF_WIDTH:0] i = '0; i < {1'b0, {tcp::BUFF_WIDTH{1'b1}}}; i = i + 1) begin
  //     if (tcb.to_be_sent_wr_ptr == i) begin
  //       o_tcb.to_be_sent[i].sequence_num <= tcb.sequence_num;
  //       o_tcb.to_be_sent[i].payload_addr <= pa;
  //       o_tcb.to_be_sent[i].payload_size <= ps;
  //     end
  //   end
  // endtask
  // ;
endmodule
