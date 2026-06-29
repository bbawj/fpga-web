
module tcp_sm (
    input clk,
    input rst,
    input tcp::CONN_STATE i_tcb_state,
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

  tcp::CONN_STATE tcb_state;
  reg valid = 0;
  reg i_flags_has_fin, i_flags_has_ack, i_flags_has_rst, i_flags_is_syn;
  reg seq_match, ack_match, ack_ge, has_payload;
  always @(posedge clk) begin
    valid <= is_rx;
    if (is_rx) begin
      tcb_state       <= i_tcb_state;
      i_flags_has_fin <= (i_flags & tcp::FIN) != '0;
      i_flags_has_ack <= (i_flags & tcp::ACK) != '0;
      i_flags_has_rst <= (i_flags & tcp::RST) != '0;
      i_flags_is_syn  <= i_flags == tcp::SYN;
      seq_match       <= i_sequence_num == tcb_ack_num;
      ack_match       <= tcb_expected_ack_num == i_ack_num;
      ack_ge          <= i_ack_num >= tcb_expected_ack_num;
      has_payload     <= i_payload_size > 0;
    end
  end

  always @(posedge clk) begin
    if (rst || !valid) begin
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
          if (i_flags_is_syn) begin
            ack_op <= 2'b01;
            seq_op <= 2'b01;
            next_state <= tcp::SYN_RECV;
            send_ack <= 1'b1;
            reject_payload <= 1'b1;
          end else begin
            next_state <= tcp::LISTEN;
            reject_payload <= 1'b1;
          end
        end
        tcp::SYN_RECV: begin
          reject_payload <= 1'b1;
          // repeated SYN should remain here
          if (i_flags_is_syn) begin
            next_state <= tcp::SYN_RECV;
          end else if (i_flags_has_ack && seq_match && ack_match) begin
            next_state <= tcp::ESTABLISHED;
            seq_op <= 2'b10;
            clear_ack_en <= 1'b1;
          end else next_state <= tcp::LISTEN;
        end
        tcp::ESTABLISHED: begin
          if (i_flags_has_ack) begin
            // find a match
            // Ack came for one of to_be_ack, due to cumulative ack, we can
            // safely deallocate all smaller acks
            clear_ack_en <= i_ack_num >= tcb_expected_ack_num;
          end

          if (has_payload) begin
            if (seq_match) begin
              // received sequence number is what we expect the next byte to be
              accept_payload <= 1'b1;
              ack_op <= 2'b10;
              send_ack <= 1'b1;
            end else begin
              // simply do not accept out of order packets right now
              $display("ERROR: incoming seq > current ack");
              reject_payload <= 1'b1;
            end
          end else begin
            $display("LOG: no payload data in incoming packet");
            reject_payload <= 1'b1;
          end

          if (i_flags_has_rst) begin
            next_state <= tcp::LISTEN;
          end else if (i_flags_has_fin) begin
            ack_op <= 2'b01;
            next_state <= tcp::LASTACK;
            send_ack <= 1'b1;
          end else next_state <= tcp::ESTABLISHED;
        end
        tcp::LASTACK: begin
          reject_payload <= 1'b1;
          if (i_flags_has_rst || (ack_match && i_flags_has_ack)) begin
            next_state <= tcp::LISTEN;
          end else begin
            next_state <= tcp::LASTACK;
            send_ack   <= 1'b1;
          end
        end
        tcp::FINWAIT: begin
          reject_payload <= 1'b1;
          if (i_flags_has_rst) begin
            next_state <= tcp::LISTEN;
          end else if (i_flags_has_fin && i_flags_has_ack) begin
            next_state <= tcp::LISTEN;
            ack_op <= 2'b01;
            seq_op <= 2'b10;
            send_ack <= 1'b1;
          end else if (i_flags_has_ack) begin
            clear_ack_en <= i_ack_num >= tcb_expected_ack_num;
            next_state   <= tcp::FINWAIT;
          end else begin
            next_state <= tcp::FINWAIT;
            // send_ack   <= 1'b1;
          end
        end
        default: begin
          next_state <= tcp::LISTEN;
        end
      endcase
    end
  end

`ifdef FORMAL
  // initial assume (rst);
  reg f_past_valid;
  initial f_past_valid = 1'b0;
  always_comb begin
    assume (tcb_state <= tcp::LASTACK);
  end
  always @(posedge clk) begin
    if (rst) f_past_valid <= 1;
    // tcp_sm should always provide reject_payload or accept_payload so that
    // arbiter does not get stuck waiting
    if (f_past_valid && !$past(rst) && $past(valid)) assert (reject_payload || accept_payload);
    // only 1 of them is asserted
    if (f_past_valid) assert (!(reject_payload && accept_payload));
  end
`endif
endmodule
