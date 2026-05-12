
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
    output reg send_ack,

    output tcp::CONN_STATE next_state,
    output reg [1:0] ack_op,
    output reg [1:0] seq_op,
    output reg clear_ack_en,
    output reg reject_payload,
    output reg accept_payload
);

  always @(posedge clk) begin
    if (rst || !is_rx) begin
      send_ack <= 1'b0;
      reject_payload <= 0;
      accept_payload <= 0;
      ack_op <= '0;
      seq_op <= '0;
      clear_ack_en <= '0;
      // there is an incoming TCB on the line
    end else begin
      send_ack <= 1'b0;
      reject_payload <= 0;
      accept_payload <= 0;
      ack_op <= '0;
      seq_op <= '0;
      clear_ack_en <= '0;
      case (tcb_state)
        tcp::LISTEN: begin
          next_state <= tcp::LISTEN;
          if (i_flags == tcp::SYN) begin
            ack_op <= 2'b01;
            seq_op <= 2'b01;
            next_state <= tcp::SYN_RECV;
            reject_payload <= 1'b1;
            send_ack <= 1'b1;
          end
        end
        tcp::SYN_RECV: begin
          reject_payload <= 1'b1;
          if (((i_flags & tcp::ACK) != '0) && (tcb_ack_num == i_sequence_num) &&
            tcb_expected_ack_num == i_ack_num) begin
            next_state <= tcp::ESTABLISHED;
            seq_op <= 2'b10;
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
              send_ack <= 1'b1;
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
            send_ack <= 1'b1;
          end else if ((i_flags & tcp::RST) != '0) begin
            next_state <= tcp::LISTEN;
          end else next_state <= tcp::ESTABLISHED;
        end
        tcp::LASTACK: begin
          if (i_ack_num == tcb_expected_ack_num && (i_flags & tcp::ACK) != '0) begin
            next_state <= tcp::LISTEN;
            reject_payload <= 1'b1;
          end else if ((i_flags & tcp::FIN) != '0) begin
            next_state <= tcp::LASTACK;
            send_ack   <= 1'b1;
          end
        end
        tcp::FINWAIT: begin
          reject_payload <= 1'b1;
          if ((i_flags & (tcp::ACK | tcp::FIN)) == (tcp::ACK | tcp::FIN)) begin
            next_state <= tcp::LISTEN;
            ack_op <= 2'b01;
            seq_op <= 2'b10;
            send_ack <= 1'b1;
          end else next_state <= tcp::FINWAIT;
        end
        default: begin
        end
      endcase
    end
  end

endmodule
