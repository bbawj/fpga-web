/**
* Arbitrate access to a set of transmission control blocks (TCB).
*
* It takes incoming packets as the main input and runs 2 key flows.
*
* The first flow is for an incoming packet i.e the RX path:
* 1. Tries to find an existing TCB with matching address and port. Allocates
*    one if it is new.
* 2. Passes the TCB state, the current packet parameters (flags, ack_num,
*    whether the packet is RX or TX etc.) to the state machine handler.
* 3. Waits for a response from the state machine and updates the TCB state
*    accordingly.
*
* The second flow happens simultaneuously i.e. TX path:
* 1. Checks whether any TCB has packet pending asserted.
* 2. Grants 1 TCB the transmit opportunity at one time. Selects the packet
*    from the chosen TCB and raises "send_tcp".
*/
module tcp_arbiter #(
    parameter logic [15:0] MSS = 1464
) (
    input clk,
    input rxc,
    input rst,
    // the pkt is coming from the wire
    input is_rx,
    input tcp::packet_t rx_packet,
    // TODO; when handling more than 1 TCP, we need to identify by addr and
    // port
    // input tcp_rx_payload_peer_addr,
    // input [18:0] tcp_rx_payload_addr,

    // upper layer is trying to send a packet
    input is_tx,
    // handshake for "is_tx". When asserted, the sender should change state
    output reg upper_granted,
    input [18:0] to_send_payload_addr,
    input [15:0] to_send_payload_size,
    // Enable TCP echo, which directly transitions an incoming TCP payload
    // packet to TX state. Connects the incoming EBR to outgoing EBR
    input tcp_echo_en,

    output reg rdy,
    // From TCP SM, connect to encoder FIFO
    output reg send_tcp,
    output tcp::packet_t o_pkt_to_send,
    // Tells the upper layer of the network stack that there is a new TCP payload
    // available for tcp parameters in o_tcb. Pulse for 1 cycle
    output reg tcp_payload_valid,
    // Issue with payload, do not process it
    output reg tcp_payload_err
);

  // TODO: array of size MAX_CONNECTIONS
  logic [1:0] tcb_rx_sel, tcb_tx_sel = '0;
  always @(posedge clk) begin
    case (tcb_tx_sel)
      0: o_pkt_to_send <= o_pkt_to_send;
      1: o_pkt_to_send <= tcb_pkt;
    endcase
    // TODO: update the window based on size of tcp_incoming_buffer
    o_pkt_to_send.window <= MSS;
  end

  reg pkt_pending, to_send_wr_en;
  tcp::CONN_STATE tcb_state;
  tcp::packet_t tcb_pkt, tcb_pkt_sel;
  logic [31:0] tcb_expected_ack_num;
  tcb #(
      .ID(1)
  ) tcb (
      .clk(clk),
      .rst(rst),
      .echo_en(tcp_echo_en),

      .tcb_rx_sel(tcb_rx_sel),
      .i_state(next_state),
      .i_pkt(rx_packet),
      .clear_ack_en(clear_ack_en),
      .ack_op(ack_op),
      .seq_op(seq_op),
      .send_ack(send_ack),

      .tcb_tx_sel(tcb_tx_sel),
      .upper_to_send_payload_addr(mux_to_send_payload_addr),
      .upper_to_send_payload_size(mux_to_send_payload_size),
      .to_send_wr_en(to_send_wr_en),
      .pkt_granted(pkt_granted),

      .pkt_pending(pkt_pending),
      .o_state(tcb_state),
      .o_expected_ack(tcb_expected_ack_num),
      .o_pkt(tcb_pkt)
  );

  typedef enum {
    GRANT_IDLE,
    GRANT_BREAK,
    GRANT_UPPER,
    GRANT_UPPER_WAIT,
    GRANT_PENDING,
    WAIT_PKT,
    SEND_PKT,
    GRANT_ECHO
  } grant_state_t;
  grant_state_t grant_state;
  logic pkt_granted, echo_granted, echo_pending, upper_pending;
  logic [18:0] mux_to_send_payload_addr, remaining_payload_addr;
  logic [15:0] mux_to_send_payload_size, remaining_payload_size;
  always @(posedge clk) begin
    if (rst) begin
      grant_state <= GRANT_IDLE;
      pkt_granted <= 0;
      upper_granted <= 0;
      echo_granted <= '0;
      send_tcp <= '0;
    end else
      case (grant_state)
        GRANT_IDLE: begin
          tcb_tx_sel <= '0;
          send_tcp <= '0;
          pkt_granted <= '0;
          upper_granted <= 0;
          echo_granted <= '0;
          to_send_wr_en <= '0;
          remaining_payload_size <= '0;
          remaining_payload_addr <= '0;
          if (pkt_pending) begin
            grant_state <= GRANT_PENDING;
            pkt_granted <= 1'b1;
            tcb_tx_sel  <= 1;
          end else if (upper_pending) begin
            grant_state <= GRANT_UPPER;
          end else if (echo_pending) begin
            grant_state  <= GRANT_ECHO;
            echo_granted <= 1'b1;
          end
        end
        GRANT_UPPER: begin
          tcb_tx_sel <= 1;
          upper_granted <= 1'b1;
          to_send_wr_en <= 1'b1;
          // 1440 is chosen as a multiple of 32 that is smaller than MSS of 1460
          if (to_send_payload_size <= 1440) begin
            mux_to_send_payload_size <= to_send_payload_size;
            mux_to_send_payload_addr <= to_send_payload_addr;
            grant_state <= GRANT_UPPER_WAIT;
          end else begin
            mux_to_send_payload_size <= 1440;
            remaining_payload_size <= to_send_payload_size - 1440;
            remaining_payload_addr <= to_send_payload_addr + (1440 / 4);
            mux_to_send_payload_addr <= to_send_payload_addr;
            grant_state <= GRANT_BREAK;
          end
        end
        GRANT_UPPER_WAIT: begin
          // for upper_pending to transition
          upper_granted <= 0;
          grant_state   <= GRANT_IDLE;
          to_send_wr_en <= 0;
        end
        GRANT_BREAK: begin
          upper_granted <= 0;
          to_send_wr_en <= 1'b1;
          remaining_payload_size <= remaining_payload_size - 1440;
          remaining_payload_addr <= remaining_payload_addr + (1440 / 4);
          mux_to_send_payload_addr <= remaining_payload_addr;
          if (remaining_payload_size <= 1440) begin
            mux_to_send_payload_size <= remaining_payload_size;
            grant_state <= GRANT_IDLE;
          end else begin
            mux_to_send_payload_size <= 1440;
            grant_state <= GRANT_BREAK;
          end
        end
        GRANT_PENDING: begin
          // 1 cyle stall due to latency for pkt to return after granted
          pkt_granted <= 1'b0;
          grant_state <= WAIT_PKT;
          mux_to_send_payload_size <= 0;
          mux_to_send_payload_addr <= 0;
        end
        WAIT_PKT: begin
          // 1 cyle stall due to latency for tcb to update with pkt_to_send
          grant_state <= SEND_PKT;
        end
        SEND_PKT: begin
          grant_state <= GRANT_IDLE;
          send_tcp <= 1'b1;
        end
        GRANT_ECHO: begin
          grant_state <= GRANT_IDLE;
          tcb_tx_sel <= target_tcb;
          to_send_wr_en <= 1'b1;
          mux_to_send_payload_size <= rx_packet.payload_size;
          mux_to_send_payload_addr <= rx_packet.payload_addr;
        end
        default: begin
          grant_state <= GRANT_IDLE;
        end
      endcase
  end

  // TODO: find matching TCB for TX path
  reg upper_state = 0;
  // assign upper_pending = upper_state == 1 && !upper_granted;
  always @(posedge clk) begin
    if (rst) begin
      upper_state   <= 0;
      upper_pending <= 0;
    end else
      case (upper_state)
        0: begin
          upper_pending <= 0;
          if (is_tx && rx_packet.peer_addr == tcb_pkt.peer_addr &&
          rx_packet.peer_port == tcb_pkt.peer_port) begin
            upper_state <= 1;
          end
        end
        1: begin
          upper_pending <= 1;
          if (upper_granted) begin
            upper_pending <= 0;
            upper_state   <= 0;
          end
        end
        default: upper_state <= 0;
      endcase
  end

  typedef enum {
    RX_IDLE,
    SELECT_TCB,
    RX_PACKET,
    WAIT_SM_RX_TRANSITION,
    TX_ECHO_PACKET,
    WAIT_ECHO
  } state_t;
  state_t state = RX_IDLE;

  always @(posedge clk) begin
    if (sm_accept_payload || sm_reject_payload) begin
      next_state <= sm_next_state;
      send_ack <= sm_send_ack;
      ack_op <= sm_ack_op;
      seq_op <= sm_seq_op;
      clear_ack_en <= sm_clear_ack_en;
      tcb_rx_sel <= target_tcb;
    end else begin
      tcb_rx_sel <= 0;
    end
  end

  // FIXME: latch all the SM updates on reject/accept payload to break routing
  // assign tcb_rx_sel = (sm_reject_payload | sm_accept_payload) ? target_tcb : 0;
  logic [1:0] target_tcb = 0;
  always @(posedge clk) begin
    if (rst) begin
      state <= RX_IDLE;
      tcp_payload_valid <= 0;
      target_tcb <= 0;
      rdy <= '0;
    end else begin
      case (state)
        RX_IDLE: begin
          target_tcb <= 0;
          rdy <= '1;
          tcp_payload_valid <= 0;
          tcp_payload_err <= 0;
          if (is_rx) begin
            rdy   <= 0;
            state <= SELECT_TCB;
            // TODO: should block new connections if out of TCBs
          end
        end
        SELECT_TCB: begin
          // TODO: choose correct target id
          target_tcb <= 1;
          rx_packet_q <= rx_packet;
          state <= RX_PACKET;
        end
        RX_PACKET: begin
          tcb_pkt_sel <= tcb_pkt;
          if (tcb_pkt.peer_port == rx_packet.peer_port && tcb_pkt.peer_addr == rx_packet.peer_addr) begin
            tcp_sm_is_rx <= 1;
            state <= WAIT_SM_RX_TRANSITION;
          end else if (tcb_state == tcp::LISTEN) begin
            // no matching TCB, create a new one
            // for now we do no validation of other fields, assume they are 0
            tcp_sm_is_rx <= 1;
            state <= WAIT_SM_RX_TRANSITION;
          end else state <= RX_IDLE;
        end
        WAIT_SM_RX_TRANSITION: begin
          tcp_sm_is_rx <= 0;
          // TODO: copy to SDRAM

          if (sm_accept_payload) begin
            rdy <= 1;
            tcp_payload_valid <= 1'b1;
            state <= RX_IDLE;
            if (tcp_echo_en) begin
              state <= TX_ECHO_PACKET;
              tcp_payload_valid <= 1'b0;
            end
          end else if (sm_reject_payload) begin
            tcp_payload_valid <= 1'b1;
            tcp_payload_err <= 1'b1;
            state <= RX_IDLE;
            rdy <= 1;
          end
        end
        TX_ECHO_PACKET: begin
          // TODO: arbitrate writes to 'to_send' in case tx path is also
          // writing at the same time
          state <= WAIT_ECHO;
          echo_pending <= 1'b1;
        end
        WAIT_ECHO: begin
          if (echo_granted) begin
            state <= RX_IDLE;
            rdy <= 1;
            echo_pending <= 1'b0;
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
  tcp::CONN_STATE next_state, sm_next_state;
  reg send_ack, sm_send_ack, clear_ack_en, sm_clear_ack_en;
  logic [1:0] ack_op, sm_ack_op, seq_op, sm_seq_op;

  tcp::packet_t rx_packet_q;
  tcp_sm sm (
      .clk(clk),
      .rst(rst),
      .tcb_state(tcb_state),
      .tcb_ack_num(tcb_pkt_sel.ack_num),
      .tcb_sequence_num(tcb_pkt_sel.sequence_num),
      .tcb_expected_ack_num(tcb_expected_ack_num),
      .is_tx(tcp_sm_is_tx),
      .is_rx(tcp_sm_is_rx),
      .i_ack_num(rx_packet_q.ack_num),
      .i_sequence_num(rx_packet_q.sequence_num),
      .i_payload_size(rx_packet_q.payload_size),
      .i_flags(rx_packet_q.flags),

      .send_ack(sm_send_ack),

      .next_state(sm_next_state),
      .ack_op(sm_ack_op),
      .seq_op(sm_seq_op),
      .clear_ack_en(sm_clear_ack_en),
      .accept_payload(sm_accept_payload),
      .reject_payload(sm_reject_payload)
  );

endmodule
