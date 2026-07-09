`default_nettype none

module tcb #(
    parameter logic [1:0] ID = 0
) (
    input wire clk,
    input wire rst,
    input wire echo_en,
    input wire [1:0] tcb_tx_sel,
    input wire to_send_wr_en,
    input wire [18:0] upper_to_send_payload_addr,
    input wire [15:0] upper_to_send_payload_size,
    input wire pkt_granted,
    // Signals from TCP state machine handler. For now only the RX path enters
    // the TCP SM and cause updates to these signals. When tcb_rx_sel matches
    // the ID of this TCB, the state changes.
    input wire [1:0] tcb_rx_sel,
    input tcp::packet_t i_pkt,
    input wire tcp::CONN_STATE i_state,
    input wire send_ack,
    input wire clear_ack_en,
    input wire [1:0] ack_op,
    input wire [1:0] seq_op,
    // This is the main way to inform arbiter that there is a transmission
    // required. Currently there are a few interactions:
    // 1. If SM asserts send_ack, this triggers pkt_pending after some time
    // 2. If arbiter wrote into the to_send FIFO
    // 3. If sending a packet in non-echo mode, this re-asserts when
    // internally transition into FINWAIT for HTTP1.0 closing.
    output reg pkt_pending,
    output reg [31:0] o_expected_ack,

    output tcp::CONN_STATE o_state,
    output reg [7:0] o_serial_state,
    output tcp::packet_t o_pkt
);
  tcp::tcb_t tcb_mem;
  reg to_send_empty, to_send_rden;

  wire tx_update_en = tcb_tx_sel == ID;
  wire rx_update_en = tcb_rx_sel == ID;
  tcp::CONN_STATE prev_state;
  reg state_rst;
  always @(posedge clk) begin
    if (rst) begin
      prev_state <= tcp::LISTEN;
      state_rst  <= 0;
    end else begin
      prev_state <= tcb_mem.state;
      state_rst  <= prev_state != tcp::LISTEN && tcb_mem.state == tcp::LISTEN;
    end
  end

  /**
  * SM can request a TCP packet when transmitting control state without
  * payload.
  * During this, allow some delay for actual packet with payloads to arrive.
  *
  * If a packet arrives, stop the timer, allowing packet to propagate into
  * to_send FIFO. Otherwise, raise pseudo_pkt_pending to continue transmit
  * control path.
  */
  logic [7:0] wait_pkt_count;
  logic wait_pkt_done, pseudo_pkt_pending, pseudo_pkt_granted;
  assign wait_pkt_done = wait_pkt_count[7];
  always @(posedge clk) begin
    if (rst || wait_pkt_done || (to_send_wr_en && tx_update_en)) wait_pkt_count <= 0;
    else if (rx_update_en && send_ack && to_send_empty) wait_pkt_count <= 1;
    else if (wait_pkt_count != '0) wait_pkt_count <= wait_pkt_count << 1;
  end
  always @(posedge clk) begin
    if (rst || state_rst || pseudo_pkt_granted) pseudo_pkt_pending <= 1'b0;
    // allow transition to FINWAIT to trigger pseudo packet
    else if (wait_pkt_done || (fin_pending && !fin_pending_q)) pseudo_pkt_pending <= 1'b1;
  end

  reg serial_wren, serial_empty;
  always @(posedge clk) begin
    pkt_pending <= !serial_empty;
  end
  logic [31:0] serial_sequence_num, serial_sequence_num_q;
  logic [31:0] serial_ack_num, serial_ack_num_q;
  logic [18:0] serial_payload_addr, serial_payload_addr_q;
  logic [15:0] serial_payload_size, serial_payload_size_q;
  logic [7:0] serial_flags, serial_flags_q;
  fifo #(
      .DATA_WIDTH(107),
      .DEPTH(64)
  ) serialized (
      .clk(clk),
      .rst(state_rst || rst),
      .wr_en(serial_wren),
      .din({
        serial_sequence_num, serial_ack_num, serial_payload_size, serial_payload_addr, serial_flags
      }),
      .full(),
      .rd_en(tx_update_en && pkt_granted),
      .dout({
        serial_sequence_num_q,
        serial_ack_num_q,
        serial_payload_size_q,
        serial_payload_addr_q,
        serial_flags_q
      }),
      .empty(serial_empty),
      .valid(),
      .count()
  );
  always_ff @(posedge clk) begin
    o_pkt.peer_addr <= tcb_mem.peer_addr;
    o_pkt.peer_port <= tcb_mem.peer_port;
    o_pkt.window <= '0;
    if (pkt_to_send_valid) begin
      o_pkt.sequence_num <= serial_sequence_num_q;
      o_pkt.ack_num <= serial_ack_num_q;
      o_pkt.payload_size <= serial_payload_size_q;
      o_pkt.payload_addr <= serial_payload_addr_q;
      o_pkt.flags <= serial_flags_q;
    end
  end

  typedef enum reg [7:0] {
    SERIAL_IDLE = 0,
    SERIAL_UPPER_WAIT = 1,
    SERIAL_UPPER = 2,
    SERIAL_UPPER_UPDATE = 4,
    SERIAL_PSEUDO = 8,
    SERIAL_PSEUDO_WAIT = 16,
    SERIAL_RETRANSMIT = 32
  } serial_state_t;
  serial_state_t serial_state = SERIAL_IDLE;
  always @(posedge clk) begin
    case (serial_state)
      SERIAL_IDLE: o_serial_state <= 0;
      SERIAL_UPPER_WAIT: o_serial_state <= 'd1;
      SERIAL_UPPER: o_serial_state <= 'd2;
      SERIAL_UPPER_UPDATE: o_serial_state <= 'd3;
      SERIAL_PSEUDO: o_serial_state <= 'd4;
      SERIAL_PSEUDO_WAIT: o_serial_state <= 'd5;
      SERIAL_RETRANSMIT: o_serial_state <= 'd6;
      default: begin
      end
    endcase
  end
  reg actual_payload_serialized = 0;
  always @(posedge clk) begin
    if (rst || state_rst || tcb_mem.state == tcp::LISTEN) actual_payload_serialized <= 0;
    else if (serial_state == SERIAL_UPPER_UPDATE) actual_payload_serialized <= 1'b1;
  end

  always @(posedge clk) begin
    if (serial_state == SERIAL_PSEUDO) pseudo_pkt_granted <= 1;
    else pseudo_pkt_granted <= 0;
  end

  logic to_ack_wr_en, to_ack_empty, to_ack_retransmit_granted, to_ack_retransmit_pending;

  always @(posedge clk) begin
    if (rst || state_rst) begin
      serial_state <= SERIAL_IDLE;
    end else
      case (serial_state)
        SERIAL_IDLE: begin
          serial_wren <= 0;
          serial_sequence_num <= tcb_mem.sequence_num;
          if (!to_send_empty) begin
            serial_state <= SERIAL_UPPER_WAIT;
          end else if (pseudo_pkt_pending) begin
            serial_state <= SERIAL_PSEUDO;
          end else if (to_ack_retransmit_pending) begin
            serial_state <= SERIAL_RETRANSMIT;
            to_ack_retransmit_granted <= 1'b1;
          end
        end
        SERIAL_UPPER_WAIT: begin
          serial_state <= SERIAL_UPPER;
          to_send_rden <= 1;
          serial_payload_size <= to_send_payload_size;
          serial_payload_addr <= to_send_payload_addr;
        end
        SERIAL_UPPER: begin
          to_send_rden <= 0;
          serial_state <= SERIAL_UPPER_UPDATE;
          serial_wren <= 1;
          serial_ack_num <= tcb_mem.ack_num;
          case (tcb_mem.state)
            tcp::SYN_RECV: begin
              serial_flags <= tcp::SYN | tcp::ACK;
            end
            tcp::ESTABLISHED: begin
              serial_flags <= tcp::ACK | tcp::PSH;
            end
            tcp::LASTACK, tcp::FINWAIT: begin
              serial_flags <= tcp::ACK | tcp::FIN;
            end
            tcp::LISTEN: begin
              serial_flags <= tcp::ACK;
            end
            default: begin
              serial_flags <= 0;
            end
          endcase
        end
        SERIAL_UPPER_UPDATE: begin
          serial_wren <= 0;
          serial_sequence_num <= serial_sequence_num + {16'b0, serial_payload_size};
          serial_state <= SERIAL_IDLE;
        end
        SERIAL_PSEUDO: begin
          serial_state <= SERIAL_PSEUDO_WAIT;
          serial_wren <= 1;
          serial_ack_num <= tcb_mem.ack_num;
          serial_payload_size <= 0;
          serial_payload_addr <= 0;
          case (tcb_mem.state)
            tcp::SYN_RECV: begin
              serial_flags <= tcp::SYN | tcp::ACK;
            end
            tcp::ESTABLISHED, tcp::LISTEN: begin
              serial_flags <= tcp::ACK;
            end
            tcp::LASTACK, tcp::FINWAIT: begin
              serial_flags <= tcp::ACK | tcp::FIN;
            end
            default: begin
              serial_flags <= 0;
            end
          endcase
        end
        SERIAL_PSEUDO_WAIT: begin
          serial_state <= SERIAL_IDLE;
          serial_wren  <= 0;
        end
        SERIAL_RETRANSMIT: begin
          serial_state <= SERIAL_IDLE;
          to_ack_retransmit_granted <= 1'b0;
          serial_wren <= 1;
          serial_sequence_num <= to_ack_sequence_num;
          serial_ack_num <= to_ack_ack_num;
          serial_payload_size <= to_ack_payload_size;
          serial_payload_addr <= to_ack_payload_addr;
          serial_flags <= to_ack_flags;
        end
        default: begin
          serial_state <= SERIAL_IDLE;
        end
      endcase
  end

  always @(posedge clk) begin
    o_state <= tcb_mem.state;
  end

  reg fin_pending = 0, fin_pending_q = 0;
  always @(posedge clk) begin
    if (rst || state_rst) begin
      fin_pending   <= 0;
      fin_pending_q <= 0;
    end else begin
      fin_pending_q <= fin_pending;
      if (tcb_mem.state == tcp::FINWAIT) begin
        fin_pending <= 1'b1;
      end else if (tcb_mem.state == tcp::ESTABLISHED && !echo_en && serial_empty && actual_payload_serialized && to_ack_empty && to_send_empty) begin
        fin_pending <= 1'b1;
      end else if (tcb_mem.state != tcp::ESTABLISHED) begin
        fin_pending <= 0;
      end
    end
  end

`ifdef SYNTHESIS
  localparam int FIN_TIMEOUT = 'd1250000000;
  localparam int IDLE_TIMEOUT = 'd1250000000;
`else
  localparam int FIN_TIMEOUT = 'd12500;
  localparam int IDLE_TIMEOUT = 'd12500;
`endif
  wire fin_timeout;
  assign fin_timeout = fin_timeout_counter == '0;
  reg [31:0] fin_timeout_counter;
  always @(posedge clk) begin
    if (fin_pending) fin_timeout_counter <= fin_timeout_counter == 0 ? 0 : fin_timeout_counter - 1;
    else fin_timeout_counter <= FIN_TIMEOUT;
  end

  wire idle_timeout;
  assign idle_timeout = idle_timeout_counter == '0;
  reg [31:0] idle_timeout_counter;
  always @(posedge clk) begin
    if (tcb_mem.state == tcp::ESTABLISHED && to_send_empty)
      idle_timeout_counter <= idle_timeout_counter == 0 ? 0 : idle_timeout_counter - 1;
    else idle_timeout_counter <= IDLE_TIMEOUT;
  end

  always @(posedge clk) begin
    if (rx_update_en) begin
      tcb_mem.peer_addr <= i_pkt.peer_addr;
      tcb_mem.peer_port <= i_pkt.peer_port;
    end
  end

  // TODO: send RST on change to listen
  always @(posedge clk) begin
    if (rst) begin
      tcb_mem.state <= tcp::LISTEN;
    end else if (rx_update_en) begin
      tcb_mem.state <= i_state;
    end else if (fin_timeout) begin
      tcb_mem.state <= tcp::LISTEN;
    end else if (tcb_mem.state == tcp::ESTABLISHED && !echo_en) begin
      if (idle_timeout || (serial_empty && actual_payload_serialized && to_ack_empty))
        tcb_mem.state <= tcp::FINWAIT;
    end
  end

  always @(posedge clk) begin
    if (rx_update_en) begin
      case (ack_op)
        2'b01:   tcb_mem.ack_num <= i_pkt.sequence_num + 1;
        2'b10:   tcb_mem.ack_num <= i_pkt.sequence_num + {16'b0, i_pkt.payload_size};
        default: tcb_mem.ack_num <= tcb_mem.ack_num;
      endcase
    end
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
  reg pkt_to_send_valid, pkt_to_send_valid_q;
  always @(posedge clk) begin
    if (rx_update_en) begin
      case (seq_op)
        2'b01: tcb_mem.sequence_num <= random;
        2'b10: tcb_mem.sequence_num <= tcb_mem.sequence_num + 1;
        default: begin
        end
      endcase
    end else if (serial_wren) begin
      tcb_mem.sequence_num <= tcb_mem.sequence_num + {16'b0, serial_payload_size};
    end
  end

  // Whenever we send a "real" packet, we add it to the to_ack FIFO
  // TODO: should we add FIN packets also?
  // TODO: should we add ACK packets also..?
  always @(posedge clk) begin
    if (rst || state_rst) begin
      to_ack_wr_en <= 0;
    end else begin
      to_ack_wr_en <= pkt_to_send_valid_q && o_pkt.flags != tcp::ACK;
    end
  end

  always @(posedge clk) begin
    if (rst || state_rst) begin
      pkt_to_send_valid   <= 1'b0;
      pkt_to_send_valid_q <= 0;
    end else begin
      pkt_to_send_valid   <= 1'b0;
      pkt_to_send_valid_q <= pkt_to_send_valid;
      if (tx_update_en && pkt_granted) begin
        pkt_to_send_valid <= 1'b1;
      end
    end
  end

  // Cache oldest expected ack number for faster checking
  always @(posedge clk) begin
    case (tcb_mem.state)
      tcp::LASTACK, tcp::SYN_RECV: o_expected_ack <= tcb_mem.sequence_num + 1;
      tcp::ESTABLISHED:
      if (to_ack_empty && to_ack_wr_en) begin
        o_expected_ack <= o_pkt.sequence_num + {16'b0, o_pkt.payload_size};
      end
      default: o_expected_ack <= o_expected_ack;
    endcase
  end

  logic [18:0] to_send_payload_addr, to_send_payload_addr_q;
  logic [15:0] to_send_payload_size, to_send_payload_size_q;
  always @(posedge clk) begin
    to_send_payload_size_q <= to_send_payload_size;
    to_send_payload_addr_q <= to_send_payload_addr;
  end
  fifo #(
      .LOOKAHEAD(1),
      .DATA_WIDTH(35),
      .DEPTH(64)
  ) to_send (
      .clk  (clk),
      .rst  (rst || state_rst),
      .wr_en(to_send_wr_en && tx_update_en),
      .din  ({upper_to_send_payload_size, upper_to_send_payload_addr}),
      .full (),
      .rd_en(to_send_rden),
      .dout ({to_send_payload_size, to_send_payload_addr}),
      .empty(to_send_empty),
      .valid(),
      .count()
  );

  logic [18:0] to_ack_payload_addr;
  logic [15:0] to_ack_payload_size;
  logic [31:0] to_ack_sequence_num;
  logic [31:0] to_ack_ack_num;
  logic [ 7:0] to_ack_flags;
  to_ack_fifo to_ack_fifo_ (
      .clk(clk),
      .rst(rst || state_rst),
      .clear(rx_update_en && clear_ack_en),
      .retransmit_granted(to_ack_retransmit_granted),
      .i_target_ack_to_clear(i_pkt.ack_num),
      .wr_en(to_ack_wr_en),
      .to_send_payload_addr(o_pkt.payload_addr),
      .to_send_payload_size(o_pkt.payload_size),
      .to_send_sequence_num(o_pkt.sequence_num),
      .to_send_ack_num(o_pkt.ack_num),
      .to_send_flags(o_pkt.flags),
      .to_ack_payload_addr(to_ack_payload_addr),
      .to_ack_payload_size(to_ack_payload_size),
      .to_ack_sequence_num(to_ack_sequence_num),
      .to_ack_ack_num(to_ack_ack_num),
      .to_ack_flags(to_ack_flags),
      .empty(to_ack_empty),
      .retransmit_pending(to_ack_retransmit_pending)
  );

`ifdef FORMAL
  // initial assume (rst);
  reg f_past_valid;
  initial f_past_valid = 1'b0;
  always @(posedge clk) begin
    if (rst) f_past_valid <= 1;
    if (f_past_valid && !$past(state_rst) && !rst && !$past(rst) && !$past(to_send_empty))
      cover ($stable(serial_state));
  end
`endif

endmodule
