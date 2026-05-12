`default_nettype none

module tcb #(
    parameter logic [1:0] ID = 0
) (
    input clk,
    input rst,
    input echo_en,
    input [1:0] tcb_tx_sel,
    input to_send_wr_en,
    input [18:0] upper_to_send_payload_addr,
    input [15:0] upper_to_send_payload_size,
    input [15:0] upper_to_send_payload_checksum,
    input pkt_granted,
    // Signals from TCP state machine handler. For now only the RX path enters
    // the TCP SM and cause updates to these signals. When tcb_rx_sel matches
    // the ID of this TCB, the state changes.
    input [1:0] tcb_rx_sel,
    input tcp::packet_t i_pkt,
    input tcp::CONN_STATE i_state,
    input send_ack,
    input clear_ack_en,
    input [1:0] ack_op,
    input [1:0] seq_op,
    // This is the main way to inform arbiter that there is a transmission
    // required. Currently there are a few interactions:
    // 1. If SM asserts send_ack, this triggers pkt_pending after some time
    // 2. If arbiter wrote into the to_send FIFO
    // 3. If sending a packet in non-echo mode, this re-asserts when
    // internally transition into FINWAIT for HTTP1.0 closing.
    output pkt_pending,
    output reg [31:0] o_expected_ack,

    output tcp::CONN_STATE o_state,
    output tcp::packet_t   o_pkt
);
  tcp::tcb_t tcb_mem;

  wire tx_update_en = tcb_tx_sel == ID;
  wire rx_update_en = tcb_rx_sel == ID;

  /**
  * SM can request a TCP packet when transmitting control state without
  * payload.
  * During this, allow some delay for actual packet with payloads to arrive.
  *
  * If a packet arrives, stop the timer, allowing packet to propagate into
  * to_send FIFO. Otherwise, raise pseudo_pkt_pending to continue transmit
  * control path.
  */
  logic [3:0] wait_pkt_count;
  logic wait_pkt_done, pseudo_pkt_pending;
  assign wait_pkt_done = wait_pkt_count[3];
  always @(posedge clk) begin
    if (wait_pkt_done || (to_send_wr_en && tx_update_en)) wait_pkt_count <= 0;
    else if (rx_update_en && send_ack && to_send_empty) wait_pkt_count <= 1;
    else if (wait_pkt_count != '0) wait_pkt_count <= wait_pkt_count << 1;
  end
  always @(posedge clk) begin
    if (tx_update_en && pkt_granted) pseudo_pkt_pending <= 1'b0;
    // allow transition to FINWAIT to trigger pseudo packet
    else if (wait_pkt_done || (pkt_to_send_valid && !echo_en)) pseudo_pkt_pending <= 1'b1;
  end

  always @(posedge clk) begin
    o_state <= tcb_mem.state;
    o_pkt.peer_addr <= tcb_mem.peer_addr;
    o_pkt.peer_port <= tcb_mem.peer_port;
    o_pkt.ack_num <= tcb_mem.ack_num;
    o_pkt.sequence_num <= tcb_mem.sequence_num;
    o_pkt.payload_size <= pkt_to_send_valid ? to_send_payload_size : '0;
    o_pkt.payload_addr <= pkt_to_send_valid ? to_send_payload_addr : '0;
    o_pkt.checksum <= pkt_to_send_valid ? to_send_payload_checksum : '0;
    o_pkt.flags <= pkt_to_send_valid ? o_pkt.flags | tcp::PSH | (echo_en ? 0 : tcp::FIN) : o_pkt.flags;
    // Flag update according to the SM transition
    if (rx_update_en) begin
      case (i_state)
        tcp::SYN_RECV: begin
          o_pkt.flags <= tcp::SYN | tcp::ACK;
        end
        tcp::ESTABLISHED: begin
          o_pkt.flags <= tcp::ACK;
        end
        tcp::LASTACK: begin
          o_pkt.flags <= tcp::ACK | tcp::FIN;
        end
        // transitioned to LISTEN
        // This happens on some error states, like wrong ACK on SYN_RECV
        // It also happesn when closing the connection, from FINWAIT. In these
        // cases ACK needed to be set for final ACK.
        tcp::LISTEN: begin
          o_pkt.flags <= tcb_mem.state == tcp::FINWAIT ? tcp::ACK : 0;
        end
        default: begin
          o_pkt.flags <= '0;
        end
      endcase
    end else if (tcb_mem.state == tcp::FINWAIT) o_pkt.flags <= tcp::FIN | tcp::ACK;
  end

  always @(posedge clk) begin
    if (rst) begin
      tcb_mem.state <= tcp::LISTEN;
    end else if (rx_update_en) begin
      tcb_mem.peer_addr <= i_pkt.peer_addr;
      tcb_mem.peer_port <= i_pkt.peer_port;
      tcb_mem.state <= i_state;
    end else if (pkt_to_send_valid && !echo_en) begin
      // HTTP 1.0: we tag a FIN along with the HTTP payload
      tcb_mem.state <= tcp::FINWAIT;
    end
  end

  always @(posedge clk) begin
    case (ack_op)
      2'b01:   tcb_mem.ack_num <= i_pkt.sequence_num + 1;
      2'b10:   tcb_mem.ack_num <= i_pkt.sequence_num + {16'b0, i_pkt.payload_size};
      default: tcb_mem.ack_num <= tcb_mem.ack_num;
    endcase
  end

  reg [31:0] random;
  lfsr_rng #(
      .DATA_WIDTH(32)
  ) rng (
      .clk (clk),
      .rst (rst),
      // TODO: create seed from some real entropy
      .seed(32'hCAFEBABE),
      .dout(random)
  );

  // Handshake with pkt_to_send module
  reg pkt_to_send_valid, pseudo_pkt_to_send_valid;
  always @(posedge clk) begin
    case (seq_op)
      2'b01: tcb_mem.sequence_num <= random;
      2'b10: tcb_mem.sequence_num <= tcb_mem.sequence_num + 1;
      default: begin
        if (pkt_to_send_valid) begin
          tcb_mem.sequence_num <= to_send_sequence_num + {16'b0, to_send_payload_size};
        end else if (pseudo_pkt_to_send_valid) begin
          // FIXME: FIN should increment seq but then again there is no more
          // transfers after FIN
          // tcb_mem.sequence_num <= tcb_mem.sequence_num + 1;
        end
      end
    endcase
  end

  // Whenever we send a "real" packet, we add it to the to_ack FIFO
  // TODO: should we add FIN packets also?
  // TODO: should we add ACK packets also..?
  always @(posedge clk) begin
    to_ack_wr_en <= pkt_to_send_valid;
  end

  always @(posedge clk) begin
    pseudo_pkt_to_send_valid <= 1'b0;
    pkt_to_send_valid <= 1'b0;
    if (tx_update_en && pkt_granted) begin
      if (!to_send_empty) begin
        pkt_to_send_valid <= 1'b1;
      end else pseudo_pkt_to_send_valid <= 1'b1;
    end
  end

  // Cache oldest expected ack number for faster checking
  always @(posedge clk) begin
    case (tcb_mem.state)
      tcp::LASTACK, tcp::SYN_RECV: o_expected_ack <= tcb_mem.sequence_num + 1;
      tcp::ESTABLISHED:
      if (to_ack_empty && to_ack_wr_en) begin
        o_expected_ack <= tcb_mem.sequence_num;
      end
      default: o_expected_ack <= 0;
    endcase
  end

  reg to_send_empty;
  logic [18:0] to_send_payload_addr;
  logic [15:0] to_send_payload_size;
  logic [15:0] to_send_payload_checksum;
  logic [31:0] to_send_sequence_num;
  logic [31:0] to_send_ack_num;
  assign pkt_pending = !to_send_empty | pseudo_pkt_pending;
  fifo #(
      .DATA_WIDTH(115),
      .DEPTH(2)
  ) to_send (
      .clk(clk),
      .rst(rst),
      .wr_en(to_send_wr_en && tx_update_en),
      .din({
        tcb_mem.sequence_num,
        tcb_mem.ack_num,
        upper_to_send_payload_size,
        upper_to_send_payload_addr,
        upper_to_send_payload_checksum
      }),
      .full(),
      .rd_en(tx_update_en && pkt_granted),
      .dout({
        to_send_sequence_num,
        to_send_ack_num,
        to_send_payload_size,
        to_send_payload_addr,
        to_send_payload_checksum
      }),
      .empty(to_send_empty),
      .count()
  );

  logic to_ack_wr_en, to_ack_rd_en, to_ack_empty;
  logic [18:0] to_ack_payload_addr;
  logic [15:0] to_ack_payload_size;
  logic [31:0] to_ack_sequence_num;
  logic [31:0] to_ack_ack_num;
  fifo #(
      .DATA_WIDTH(99),
      .DEPTH(2)
  ) to_ack (
      .clk  (clk),
      .rst  (rst),
      .wr_en(to_ack_wr_en),
      .din  ({to_send_sequence_num, to_send_ack_num, to_send_payload_size, to_send_payload_addr}),
      .full (),
      .rd_en(to_ack_rd_en),
      .dout ({to_ack_sequence_num, to_ack_ack_num, to_ack_payload_size, to_ack_payload_addr}),
      .empty(to_ack_empty),
      .count()
  );

  logic [31:0] target_ack_to_clear, current_ack_num;
  logic [1:0] clear_ack_state = 0;
  always @(posedge clk) begin
    case (clear_ack_state)
      0: begin
        target_ack_to_clear <= '0;
        to_ack_rd_en <= 1'b0;
        if (clear_ack_en && !to_ack_empty) begin
          target_ack_to_clear <= i_pkt.ack_num;
          clear_ack_state <= 1;
          to_ack_rd_en <= 1;
        end
      end
      1: begin
        to_ack_rd_en <= 1'b0;
        current_ack_num <= to_ack_sequence_num + {16'b0, to_ack_payload_size};
        clear_ack_state <= 'd2;
      end
      2: begin
        if (to_ack_empty || current_ack_num == target_ack_to_clear) begin
          clear_ack_state <= 0;
          to_ack_rd_en <= 0;
        end else begin
          clear_ack_state <= '1;
          to_ack_rd_en <= 1;
        end
      end
      default: begin
        clear_ack_state <= 0;
      end
    endcase
  end
  // TODO: Re-transmission timer that moves packets from to_ack to to_send
endmodule
