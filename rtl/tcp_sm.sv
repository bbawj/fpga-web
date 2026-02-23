module tcp_sm (
    input clk,
    input rst,
    input tcp::tcb_t current_tcb,
    // whether "current_tcb" is the tcb target with data to send in to_be_sent
    // modules present "incoming_pkt" which is then appended into this
    // current_tcb's to_be_sent list
    input is_tx,
    // whether "current_tcb" is the tcb target for receiving data below
    input is_rx,
    input tcp::packet_t incoming_pkt,
    // tx_en asserted high with pkt_to_send, a reader needs to detect this and
    // save pkt_to_send
    output reg tx_en,
    output tcp::packet_t pkt_to_send,

    output tcp::tcb_t next_tcb,
    output reg reject_payload,
    output reg accept_payload
);

  import tcp::*;

  reg [BUFF_SIZE-1:0] ack_match_idx;
  reg [BUFF_WIDTH-1:0] idx;
  wire match_found = 0;

  wire to_be_sent_empty = current_tcb.to_be_sent_rd_ptr == current_tcb.to_be_sent_wr_ptr;
  wire to_be_sent_full = (BUFF_WIDTH'(current_tcb.to_be_sent_wr_ptr - current_tcb.to_be_sent_rd_ptr)) == BUFF_WIDTH'(tcp::BUFF_SIZE);

  reg [31:0] random;
  lfsr_rng #(
      .DATA_WIDTH(32)
  ) rng (
      .clk (clk),
      .rst (rst),
      .seed(32'hCAFEBABE),
      .dout(random)
  );

  genvar j;
  generate
    for (j = 0; j < tcp::BUFF_SIZE; j = j + 1) begin
      always @* begin
        if ((j >= current_tcb.to_be_ack_rd_ptr || j < current_tcb.to_be_ack_wr_ptr) &&
      (incoming_pkt.ack_num == current_tcb.to_be_ack[j].ack_num)) begin
          ack_match_idx[j] = 1'b1;
        end else ack_match_idx[j] = 1'b0;
      end
    end
  endgenerate

  always @(posedge clk) begin
    pkt_to_send.peer_addr <= current_tcb.peer_addr;
    pkt_to_send.peer_port <= current_tcb.peer_port;
  end

  always @(posedge clk) begin
    next_tcb <= current_tcb;
    if (rst) begin
      tx_en <= 1'b0;
      reject_payload <= 0;
      accept_payload <= 0;
      // there is an incoming TCB on the line
    end else if (is_rx) begin
      tx_en <= 1'b0;
      reject_payload <= 0;
      accept_payload <= 0;
      case (current_tcb.state)
        LISTEN: begin
          case (incoming_pkt.flags)
            SYN: begin
              next_tcb.ack_num <= incoming_pkt.sequence_num + 1;
              next_tcb.sequence_num <= random;
              next_tcb.state <= SYN_RECV;
              reject_payload <= 1'b1;

              tx_en <= 1'b1;
              pkt_to_send.sequence_num <= random;
              pkt_to_send.ack_num <= incoming_pkt.sequence_num + 1;
              pkt_to_send.flags <= tcp::SYN | tcp::ACK;
            end
            default: begin
            end
          endcase
        end
        SYN_RECV: begin
          if (((incoming_pkt.flags & ACK) != '0) && (current_tcb.ack_num == incoming_pkt.sequence_num) &&
            (current_tcb.sequence_num + 1 == incoming_pkt.ack_num)) begin
            next_tcb.state <= ESTABLISHED;
            next_tcb.sequence_num <= current_tcb.sequence_num + 1;
            reject_payload <= 1'b1;
          end else next_tcb.state <= LISTEN;
        end
        ESTABLISHED: begin
          if ((incoming_pkt.flags & FIN) != '0) begin
            next_tcb.ack_num <= incoming_pkt.sequence_num + 1;
            next_tcb.state <= LASTACK;
            pkt_to_send.ack_num <= incoming_pkt.sequence_num + 1;
            pkt_to_send.flags <= tcp::ACK | tcp::FIN;
            tx_en <= 1'b1;
          end
          if ((incoming_pkt.flags & ACK) != '0) begin
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
              next_tcb.to_be_ack_rd_ptr <= idx + 1;
            end else begin
              // ack came for none of those to_be_ack???
            end
          end
          if (incoming_pkt.payload_size > 0) begin
            if (incoming_pkt.sequence_num == current_tcb.ack_num) begin
              // received sequence number is what we expect the next byte to be
              accept_payload <= 1'b1;
              next_tcb.ack_num <= incoming_pkt.sequence_num + {16'b0, incoming_pkt.payload_size};
              tx_en <= 1'b1;
              pkt_to_send.ack_num <= incoming_pkt.sequence_num + {16'b0, incoming_pkt.payload_size};
              pkt_to_send.flags <= tcp::ACK;
            end else if (incoming_pkt.sequence_num > current_tcb.ack_num) begin
              // received sequence number is larger than our last acknowledged
              // packet, means that we lost a packet/out of order
              $display("ERROR: incoming seq > current ack");
              reject_payload <= 1'b1;
            end
          end else begin
            $display("LOG: no payload data in incoming packet");
            reject_payload <= 1'b1;
          end
        end
        LASTACK: begin
          if ((incoming_pkt.flags & ACK) != '0) begin
            next_tcb.state <= CLOSED;
            reject_payload <= 1'b1;
          end
        end
        default: begin
        end
      endcase
    end else if (is_tx) begin
      tx_en <= 1'b0;
      reject_payload <= 0;
      accept_payload <= 0;
      case (current_tcb.state)
        ESTABLISHED: begin
          if (!to_be_sent_empty) begin
            tx_en <= 1'b1;
            pkt_to_send <= current_tcb.to_be_sent[current_tcb.to_be_sent_rd_ptr];
            pkt_to_send.flags <= tcp::ACK;

            accept_payload <= 1'b1;
            APPEND_TO_ACK_LIST();
            next_tcb.to_be_ack_wr_ptr  <= current_tcb.to_be_ack_wr_ptr + 1;
            next_tcb.to_be_sent_rd_ptr <= current_tcb.to_be_sent_rd_ptr + 1;
            // assumed that the packet for tx is in the to_be_sent array
          end else begin
            reject_payload <= 1'b1;
            $display("ERROR: tried to send when to_be_sent is empty");
          end
        end
        // not in ESTABLISHED cannot send normal packets
        default: begin
          $display("ERROR: cannot send when not ESTABLISHED");
          reject_payload <= 1'b1;
        end
      endcase
    end else begin
      tx_en <= 1'b0;
      accept_payload <= 0;
      reject_payload <= 0;
    end
  end

  always @(posedge clk) begin
  end

  task automatic APPEND_TO_ACK_LIST();
    logic [31:0] next_ack_num = incoming_pkt.sequence_num + {16'b0, incoming_pkt.payload_size};
    for (logic [tcp::BUFF_WIDTH:0] i = '0; i < {1'b0, {tcp::BUFF_WIDTH{1'b1}}}; i = i + 1) begin
      for (logic [tcp::BUFF_WIDTH:0] j = '0; j < {1'b0, {tcp::BUFF_WIDTH{1'b1}}}; j = j + 1) begin
        case ({
          i, j
        })
          0:
          if (current_tcb.to_be_ack_wr_ptr == 0 && current_tcb.to_be_sent_rd_ptr == 0) begin
            next_tcb.to_be_ack[0].payload_addr <= current_tcb.to_be_sent[0].payload_addr;
            next_tcb.to_be_ack[0].ack_num <= current_tcb.to_be_sent[0].ack_num;
          end
          1:
          if (current_tcb.to_be_ack_wr_ptr == 0 && current_tcb.to_be_sent_rd_ptr == 1) begin
            next_tcb.to_be_ack[0].payload_addr <= current_tcb.to_be_sent[1].payload_addr;
            next_tcb.to_be_ack[0].ack_num <= current_tcb.to_be_sent[1].ack_num;
          end
          2:
          if (current_tcb.to_be_ack_wr_ptr == 0 && current_tcb.to_be_sent_rd_ptr == 2) begin
            next_tcb.to_be_ack[0].payload_addr <= current_tcb.to_be_sent[2].payload_addr;
            next_tcb.to_be_ack[0].ack_num <= current_tcb.to_be_sent[2].ack_num;
          end
          3:
          if (current_tcb.to_be_ack_wr_ptr == 0 && current_tcb.to_be_sent_rd_ptr == 3) begin
            next_tcb.to_be_ack[0].payload_addr <= current_tcb.to_be_sent[3].payload_addr;
            next_tcb.to_be_ack[0].ack_num <= current_tcb.to_be_sent[3].ack_num;
          end
          4:
          if (current_tcb.to_be_ack_wr_ptr == 1 && current_tcb.to_be_sent_rd_ptr == 0) begin
            next_tcb.to_be_ack[1].payload_addr <= current_tcb.to_be_sent[0].payload_addr;
            next_tcb.to_be_ack[1].ack_num <= current_tcb.to_be_sent[0].ack_num;
          end
          5:
          if (current_tcb.to_be_ack_wr_ptr == 1 && current_tcb.to_be_sent_rd_ptr == 1) begin
            next_tcb.to_be_ack[1].payload_addr <= current_tcb.to_be_sent[1].payload_addr;
            next_tcb.to_be_ack[1].ack_num <= current_tcb.to_be_sent[1].ack_num;
          end
          6:
          if (current_tcb.to_be_ack_wr_ptr == 1 && current_tcb.to_be_sent_rd_ptr == 2) begin
            next_tcb.to_be_ack[1].payload_addr <= current_tcb.to_be_sent[2].payload_addr;
            next_tcb.to_be_ack[1].ack_num <= current_tcb.to_be_sent[2].ack_num;
          end
          7:
          if (current_tcb.to_be_ack_wr_ptr == 1 && current_tcb.to_be_sent_rd_ptr == 3) begin
            next_tcb.to_be_ack[1].payload_addr <= current_tcb.to_be_sent[3].payload_addr;
            next_tcb.to_be_ack[1].ack_num <= current_tcb.to_be_sent[3].ack_num;
          end
          8:
          if (current_tcb.to_be_ack_wr_ptr == 2 && current_tcb.to_be_sent_rd_ptr == 0) begin
            next_tcb.to_be_ack[2].payload_addr <= current_tcb.to_be_sent[0].payload_addr;
            next_tcb.to_be_ack[2].ack_num <= current_tcb.to_be_sent[0].ack_num;
          end
          9:
          if (current_tcb.to_be_ack_wr_ptr == 2 && current_tcb.to_be_sent_rd_ptr == 1) begin
            next_tcb.to_be_ack[2].payload_addr <= current_tcb.to_be_sent[1].payload_addr;
            next_tcb.to_be_ack[2].ack_num <= current_tcb.to_be_sent[1].ack_num;
          end
          10:
          if (current_tcb.to_be_ack_wr_ptr == 2 && current_tcb.to_be_sent_rd_ptr == 2) begin
            next_tcb.to_be_ack[2].payload_addr <= current_tcb.to_be_sent[2].payload_addr;
            next_tcb.to_be_ack[2].ack_num <= current_tcb.to_be_sent[2].ack_num;
          end
          11:
          if (current_tcb.to_be_ack_wr_ptr == 2 && current_tcb.to_be_sent_rd_ptr == 3) begin
            next_tcb.to_be_ack[2].payload_addr <= current_tcb.to_be_sent[3].payload_addr;
            next_tcb.to_be_ack[2].ack_num <= current_tcb.to_be_sent[3].ack_num;
          end
          12:
          if (current_tcb.to_be_ack_wr_ptr == 3 && current_tcb.to_be_sent_rd_ptr == 0) begin
            next_tcb.to_be_ack[3].payload_addr <= current_tcb.to_be_sent[0].payload_addr;
            next_tcb.to_be_ack[3].ack_num <= current_tcb.to_be_sent[0].ack_num;
          end
          13:
          if (current_tcb.to_be_ack_wr_ptr == 3 && current_tcb.to_be_sent_rd_ptr == 1) begin
            next_tcb.to_be_ack[3].payload_addr <= current_tcb.to_be_sent[1].payload_addr;
            next_tcb.to_be_ack[3].ack_num <= current_tcb.to_be_sent[1].ack_num;
          end
          14:
          if (current_tcb.to_be_ack_wr_ptr == 3 && current_tcb.to_be_sent_rd_ptr == 2) begin
            next_tcb.to_be_ack[3].payload_addr <= current_tcb.to_be_sent[2].payload_addr;
            next_tcb.to_be_ack[3].ack_num <= current_tcb.to_be_sent[2].ack_num;
          end
          15:
          if (current_tcb.to_be_ack_wr_ptr == 3 && current_tcb.to_be_sent_rd_ptr == 3) begin
            next_tcb.to_be_ack[3].payload_addr <= current_tcb.to_be_sent[3].payload_addr;
            next_tcb.to_be_ack[3].ack_num <= current_tcb.to_be_sent[3].ack_num;
          end
        endcase
      end
    end
  endtask


endmodule
