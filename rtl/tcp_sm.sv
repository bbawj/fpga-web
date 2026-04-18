
module tcp_sm (
    input clk,
    input rst,
    input tcp::CONN_STATE tcb_state,
    input [31:0] tcb_ack_num,
    input [31:0] tcb_sequence_num,
    input [31:0] tcb_expected_ack_num,
    // input tcp::tcb_t current_tcb,
    // whether "current_tcb" is the tcb target with data to send in to_be_sent
    // modules present "incoming_pkt" which is then appended into this
    // current_tcb's to_be_sent list
    input is_tx,
    // whether "current_tcb" is the tcb target for receiving data below
    input is_rx,
    // data from incoming_pkt
    input [31:0] i_ack_num,
    input [31:0] i_sequence_num,
    input [7:0] i_flags,
    input [15:0] i_payload_size,
    // tx_en asserted high with pkt_to_send, a reader needs to detect this and
    // save pkt_to_send
    output reg tx_en,

    output tcp::CONN_STATE next_state,
    output reg [1:0] ack_op,
    output reg [1:0] seq_op,
    output reg clear_ack_en,
    output reg reject_payload,
    output reg accept_payload
);

  always @(posedge clk) begin
    if (rst || !is_rx) begin
      tx_en <= 1'b0;
      reject_payload <= 0;
      accept_payload <= 0;
      ack_op <= '0;
      seq_op <= '0;
      clear_ack_en <= '0;
      // there is an incoming TCB on the line
    end else begin
      tx_en <= 1'b0;
      reject_payload <= 0;
      accept_payload <= 0;
      ack_op <= '0;
      seq_op <= '0;
      clear_ack_en <= '0;
      case (tcb_state)
        tcp::LISTEN: begin
          if (i_flags == tcp::SYN) begin
            ack_op <= 2'b01;
            seq_op <= 2'b01;
            next_state <= tcp::SYN_RECV;
            reject_payload <= 1'b1;
            tx_en <= 1'b1;
          end
        end
        tcp::SYN_RECV: begin
          reject_payload <= 1'b1;
          if (((i_flags & tcp::ACK) != '0) && (tcb_ack_num == i_sequence_num) &&
            tcb_sequence_num == i_ack_num) begin
            next_state <= tcp::ESTABLISHED;
          end else next_state <= tcp::LISTEN;
        end
        tcp::ESTABLISHED: begin
          if ((i_flags & tcp::ACK) != '0) begin
            // find a match
            // Ack came for one of to_be_ack, due to cumulative ack, we can
            // safely deallocate all smaller acks
            clear_ack_en <= i_ack_num >= tcb_expected_ack_num;
          end

          if (i_payload_size > 0) begin
            if (i_sequence_num == tcb_ack_num) begin
              // received sequence number is what we expect the next byte to be
              accept_payload <= 1'b1;
              ack_op <= 2'b10;
              tx_en <= 1'b1;
            end else if (i_sequence_num > tcb_ack_num) begin
              // received sequence number is larger than our last acknowledged
              // packet, means that we lost a packet/out of order
              $display("ERROR: incoming seq > current ack");
              reject_payload <= 1'b1;
            end
          end else begin
            $display("LOG: no payload data in incoming packet");
            reject_payload <= 1'b1;
          end

          if ((i_flags & tcp::FIN) != '0) begin
            ack_op <= 2'b01;
            next_state <= tcp::LASTACK;
            tx_en <= 1'b1;
          end else next_state <= tcp::ESTABLISHED;
        end
        tcp::LASTACK: begin
          if ((i_flags & tcp::ACK) != '0) begin
            next_state <= tcp::CLOSED;
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
