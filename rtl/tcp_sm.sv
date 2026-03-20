import tcp::*;

module tcp_sm (
    input clk,
    input rst,
    input tcp::CONN_STATE base_state,
    input [31:0] base_ack_num,
    input [31:0] base_sequence_num,
    // input tcp::tcb_t current_tcb,
    // whether "current_tcb" is the tcb target with data to send in to_be_sent
    // modules present "incoming_pkt" which is then appended into this
    // current_tcb's to_be_sent list
    input is_tx,
    // whether "current_tcb" is the tcb target for receiving data below
    input is_rx,
    input [31:0] i_peer_addr,
    input [15:0] i_peer_port,
    input [31:0] i_ack_num,
    input [31:0] i_sequence_num,
    input [7:0] i_flags,
    input [15:0] i_payload_size,
    // tx_en asserted high with pkt_to_send, a reader needs to detect this and
    // save pkt_to_send
    output reg tx_en,
    output tcp::packet_t pkt_to_send,

    output tcp::CONN_STATE next_state,
    output reg [31:0] next_ack_num,
    output reg [31:0] next_sequence_num,
    output reg reject_payload,
    output reg accept_payload
);

  reg [BUFF_SIZE-1:0] ack_match_idx;
  reg [BUFF_WIDTH-1:0] idx;
  wire match_found = 0;

  // wire to_be_sent_empty = current_tcb.to_be_sent_rd_ptr == current_tcb.to_be_sent_wr_ptr;
  // wire to_be_sent_full = (BUFF_WIDTH'(current_tcb.to_be_sent_wr_ptr - current_tcb.to_be_sent_rd_ptr)) == BUFF_WIDTH'(tcp::BUFF_SIZE);

  reg [31:0] random;
  lfsr_rng #(
      .DATA_WIDTH(32)
  ) rng (
      .clk (clk),
      .rst (rst),
      .seed(32'hCAFEBABE),
      .dout(random)
  );

  // genvar j;
  // generate
  //   for (j = 0; j < tcp::BUFF_SIZE; j = j + 1) begin
  //     always @(posedge clk) begin
  //       if ((j >= current_tcb.to_be_ack_rd_ptr || j < current_tcb.to_be_ack_wr_ptr) &&
  //     (i_ack_num == current_tcb.to_be_ack[j].sequence_num + {16'd0, current_tcb.to_be_ack[j].payload_size})) begin
  //         ack_match_idx[j] <= 1'b1;
  //       end else ack_match_idx[j] <= 1'b0;
  //     end
  //   end
  // endgenerate

  always @(posedge clk) begin
    // clear the packet to send register by default
    pkt_to_send <= '0;
    pkt_to_send.peer_addr <= i_peer_addr;
    pkt_to_send.peer_port <= i_peer_port;
  end

  always @(posedge clk) begin
    next_sequence_num <= base_sequence_num;
    next_ack_num <= base_ack_num;
    next_state <= base_state;
    if (rst || !is_rx) begin
      tx_en <= 1'b0;
      reject_payload <= 0;
      accept_payload <= 0;
      // there is an incoming TCB on the line
    end else begin
      tx_en <= 1'b0;
      reject_payload <= 0;
      accept_payload <= 0;
      case (base_state)
        LISTEN: begin
          if (i_flags == SYN) begin
            next_ack_num <= i_sequence_num + 1;
            next_sequence_num <= random + 1;
            next_state <= SYN_RECV;
            reject_payload <= 1'b1;

            tx_en <= 1'b1;
            pkt_to_send.sequence_num <= random;
            pkt_to_send.ack_num <= i_sequence_num + 1;
            pkt_to_send.flags <= tcp::SYN | tcp::ACK;
          end
        end
        SYN_RECV: begin
          if (((i_flags & ACK) != '0) && (base_ack_num == i_sequence_num)) begin
            next_state <= SYN_RECV2;
          end else next_state <= LISTEN;
        end
        SYN_RECV2: begin
          reject_payload <= 1'b1;
          if (base_sequence_num == i_ack_num) begin
            next_state <= ESTABLISHED;
            next_sequence_num <= base_sequence_num;
          end else next_state <= LISTEN;
        end
        // ESTABLISHED2: begin
        //   if (i_payload_size > 0) begin
        //     if (i_sequence_num == current_tcb.ack_num) begin
        //       // received sequence number is what we expect the next byte to be
        //       accept_payload <= 1'b1;
        //       next_tcb.ack_num <= i_sequence_num + {16'b0, i_payload_size};
        //       tx_en <= 1'b1;
        //       pkt_to_send.ack_num <= i_sequence_num + {16'b0, i_payload_size};
        //       pkt_to_send.flags <= tcp::ACK;
        //     end else if (i_sequence_num > current_tcb.ack_num) begin
        //       // received sequence number is larger than our last acknowledged
        //       // packet, means that we lost a packet/out of order
        //       $display("ERROR: incoming seq > current ack");
        //       reject_payload <= 1'b1;
        //     end
        //   end else begin
        //     $display("LOG: no payload data in incoming packet");
        //     reject_payload <= 1'b1;
        //   end
        //   // Check if there is packet to send to piggy back off the ACK reply
        //   if (!to_be_sent_empty) begin
        //     READ_FROM_TO_SEND_LIST();
        //     APPEND_TO_ACK_LIST();
        //   end
        //   if ((i_flags & FIN) != '0) begin
        //     next_tcb.ack_num <= i_sequence_num + 1;
        //     next_tcb.state <= LASTACK;
        //     pkt_to_send.ack_num <= i_sequence_num + 1;
        //     pkt_to_send.flags <= tcp::ACK | tcp::FIN;
        //     tx_en <= 1'b1;
        //   end else next_tcb.state <= ESTABLISHED;
        // end
        ESTABLISHED: begin
          pkt_to_send.sequence_num <= base_sequence_num;
          if ((i_flags & ACK) != '0) begin
            // find a match
            // if (i_ack_num < current_tcb.to_be_ack[current_tcb.to_be_ack_rd_ptr].ack_num) begin
            // Ack came for an old data. NOOP
            if (ack_match_idx != '0) begin
              // Ack came for one of to_be_ack, due to cumulative ack, we can
              // safely deallocate all smaller acks
              for (
                  logic [tcp::BUFF_WIDTH:0] j = 0; j < (BUFF_WIDTH + 1)'(tcp::BUFF_SIZE); j = j + 1
              ) begin
                // TODO: should use rd_ptr??
                if (ack_match_idx[j[tcp::BUFF_WIDTH-1:0]] != 0) idx = j[tcp::BUFF_WIDTH-1:0];
              end
              // next_tcb.to_be_ack_rd_ptr <= idx + 1;
            end else begin
              // ack came for none of those to_be_ack???
            end
          end
          next_state <= ESTABLISHED2;
        end
        LASTACK: begin
          if ((i_flags & ACK) != '0) begin
            next_state <= CLOSED;
            reject_payload <= 1'b1;
          end
        end
        default: begin
        end
      endcase
    end
  end

  // always @(posedge clk) begin
  //   if (is_tx) begin
  //     tx_en <= 1'b0;
  //     reject_payload <= 0;
  //     accept_payload <= 0;
  //     case (current_tcb.state)
  //       ESTABLISHED: begin
  //         if (!to_be_sent_empty) begin
  //           tx_en <= 1'b1;
  //           pkt_to_send.ack_num <= current_tcb.ack_num;
  //           READ_FROM_TO_SEND_LIST();
  //           // TODO: update based on availabe buffer
  //           pkt_to_send.window <= tcp::MSS;
  //           pkt_to_send.flags <= tcp::ACK;
  //
  //           accept_payload <= 1'b1;
  //           APPEND_TO_ACK_LIST();
  //           // assumed that the packet for tx is in the to_be_sent array
  //         end else begin
  //           reject_payload <= 1'b1;
  //           $display("ERROR: tried to send when to_be_sent is empty");
  //         end
  //       end
  //       // not in ESTABLISHED cannot send normal packets
  //       default: begin
  //         $display("ERROR: cannot send when not ESTABLISHED");
  //         reject_payload <= 1'b1;
  //       end
  //     endcase
  //   end else begin
  //     tx_en <= 1'b0;
  //     accept_payload <= 0;
  //     reject_payload <= 0;
  //   end
  // end


  // task automatic READ_FROM_TO_SEND_LIST();
  //   next_tcb.to_be_sent_rd_ptr <= next_tcb.to_be_sent_rd_ptr + 1;
  //   for (logic [tcp::BUFF_WIDTH:0] i = '0; i < {1'b0, {tcp::BUFF_WIDTH{1'b1}}}; i = i + 1) begin
  //     if (current_tcb.to_be_sent_rd_ptr == i) begin
  //       pkt_to_send.payload_size <= current_tcb.to_be_sent[i].payload_size;
  //       pkt_to_send.payload_addr <= current_tcb.to_be_sent[i].payload_addr;
  //       pkt_to_send.sequence_num <= current_tcb.to_be_sent[i].sequence_num;
  //     end
  //   end
  // endtask
  // ;
  //
  // task automatic APPEND_TO_ACK_LIST();
  //   next_tcb.to_be_ack_wr_ptr  <= current_tcb.to_be_ack_wr_ptr + 1;
  //   next_tcb.to_be_sent_rd_ptr <= current_tcb.to_be_sent_rd_ptr + 1;
  //   for (logic [tcp::BUFF_WIDTH:0] i = '0; i < {1'b0, {tcp::BUFF_WIDTH{1'b1}}}; i = i + 1) begin
  //     for (logic [tcp::BUFF_WIDTH:0] j = '0; j < {1'b0, {tcp::BUFF_WIDTH{1'b1}}}; j = j + 1) begin
  //       if (current_tcb.to_be_ack_wr_ptr == i && current_tcb.to_be_sent_rd_ptr == j) begin
  //         next_tcb.to_be_ack[i].payload_addr <= current_tcb.to_be_sent[j].payload_addr;
  //         next_tcb.to_be_ack[i].payload_size <= current_tcb.to_be_sent[j].payload_size;
  //         next_tcb.to_be_ack[i].ack_num <= current_tcb.to_be_sent[j].ack_num;
  //       end
  //     end
  //   end
  // endtask


endmodule
