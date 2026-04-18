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
    // From TCP SM, connect to encoder FIFO
    output reg send_tcp,
    output tcp::packet_t o_pkt_to_send,
    // Tells the upper layer of the network stack that there is a new TCP payload
    // available for tcp parameters in o_tcb
    output reg tcp_payload_valid
);

  // TODO: array of size MAX_CONNECTIONS
  logic [1:0] tcb_rx_sel, tcb_tx_sel = '0;
  always @(posedge clk) begin
    case (tcb_tx_sel)
      0: o_pkt_to_send <= o_pkt_to_send;
      1: o_pkt_to_send <= tcb_pkt;
    endcase
    o_pkt_to_send.window <= MSS;
  end

  reg pkt_pending, to_send_wr_en;
  tcp::CONN_STATE tcb_state;
  tcp::packet_t tcb_pkt;
  logic [31:0] tcb_expected_ack_num;
  tcb #(
      .ID(1)
  ) tcb (
      .clk(clk),
      .rst(rst),
      .tcb_rx_sel(tcb_rx_sel),
      .tcb_tx_sel(tcb_tx_sel),
      .sm_tx_en(tx_en),
      .to_send_wr_en(to_send_wr_en),
      .pkt_granted(pkt_granted),
      .clear_ack_en(clear_ack_en),
      .ack_op(ack_op),
      .seq_op(seq_op),

      .i_state(next_state),
      .i_pkt  (packet),

      .pkt_pending(pkt_pending),
      .o_state(tcb_state),
      .o_expected_ack(tcb_expected_ack_num),
      .o_pkt(tcb_pkt)
  );

  // TODO: control for correct Tket.peer_addrCB when there is more than 1
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
      .rd_valid(tcp_rx_payload_rd_valid),
      .rd_data(tcp_rx_payload_rd_data)
  );

  typedef enum {
    GRANT_IDLE,
    GRANT_PENDING,
    WAIT_PKT,
    SEND_PKT,
    GRANT_ECHO
  } grant_state_t;
  grant_state_t grant_state;
  logic pkt_granted, echo_granted, echo_pending;
  always @(posedge clk) begin
    case (grant_state)
      GRANT_IDLE: begin
        tcb_tx_sel <= '0;
        send_tcp <= '0;
        pkt_granted <= '0;
        echo_granted <= '0;
        to_send_wr_en <= '0;
        if (pkt_pending) begin
          grant_state <= GRANT_PENDING;
          pkt_granted <= 1'b1;
          tcb_tx_sel  <= 1;
        end else if (echo_pending) begin
          grant_state  <= GRANT_ECHO;
          echo_granted <= 1'b1;
        end
      end
      GRANT_PENDING: begin
        // 1 cyle stall due to latency for pkt to return after granted
        pkt_granted <= 1'b0;
        grant_state <= WAIT_PKT;
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
        tcb_tx_sel <= tcb_rx_sel;
        echo_granted <= 1'b0;
        to_send_wr_en <= 1'b1;
      end
      default: begin
        grant_state <= GRANT_IDLE;
      end
    endcase
  end

  typedef enum {
    IDLE,
    RX_PACKET,
    WAIT_SM_RX_TRANSITION,
    TX_PACKET,
    WAIT_SM_TX_TRANSITION
  } state_t;
  state_t state = IDLE;

  always @(posedge clk) begin
    tcp_sm_is_rx <= 0;
    tcp_sm_is_tx <= 0;
    case (state)
      RX_PACKET: begin
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
      tcb_rx_sel <= '0;
      rdy <= '0;
    end else begin
      case (state)
        IDLE: begin
          rdy <= '1;
          tcb_rx_sel <= '0;
          tcp_payload_valid <= 0;
          if (is_rx) begin
            rdy   <= 0;
            state <= RX_PACKET;
            // TODO: should block new connections if out of TCBs
          end else if (is_tx) begin
            state <= TX_PACKET;
          end
        end
        RX_PACKET: begin
          state <= WAIT_SM_RX_TRANSITION;
          if (tcb_pkt.peer_port == packet.peer_port && tcb_pkt.peer_addr == packet.peer_addr) begin
            tcb_rx_sel <= 1;
          end else begin
            // no matching TCB, create a new one
            // for now we do no validation of other fields, assume they are 0
            tcb_rx_sel <= 1;
          end
        end
        WAIT_SM_RX_TRANSITION: begin
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
          // TODO: arbitrate writes to 'to_send' in case tx path is also
          // writing at the same time
          state <= WAIT_SM_TX_TRANSITION;
          echo_pending <= 1'b1;
        end
        WAIT_SM_TX_TRANSITION: begin
          if (echo_granted) begin
            state <= IDLE;
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
  tcp::CONN_STATE next_state;
  reg tx_en, clear_ack_en;
  logic [1:0] ack_op, seq_op;

  tcp_sm sm (
      .clk(clk),
      .rst(rst),
      .tcb_state(tcb_state),
      .tcb_ack_num(tcb_pkt.ack_num),
      .tcb_sequence_num(tcb_pkt.sequence_num),
      .tcb_expected_ack_num(tcb_expected_ack_num),
      .is_tx(tcp_sm_is_tx),
      .is_rx(tcp_sm_is_rx),
      .i_ack_num(packet.ack_num),
      .i_sequence_num(packet.sequence_num),
      .i_payload_size(packet.payload_size),
      .i_flags(packet.flags),

      .tx_en(tx_en),

      .next_state(next_state),
      .ack_op(ack_op),
      .seq_op(seq_op),
      .clear_ack_en(clear_ack_en),
      .accept_payload(sm_accept_payload),
      .reject_payload(sm_reject_payload)
  );

endmodule
