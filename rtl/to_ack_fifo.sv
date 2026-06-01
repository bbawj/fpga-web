module to_ack_fifo (
    input clk,
    input rst,
    input clear,
    input [31:0] i_target_ack_to_clear,
    input wr_en,
    input [18:0] to_send_payload_addr,
    input [15:0] to_send_payload_size,
    input [31:0] to_send_sequence_num,
    input [31:0] to_send_ack_num,
    input [7:0] to_send_flags,
    input retransmit_granted,

    output reg [18:0] to_ack_payload_addr,
    output reg [15:0] to_ack_payload_size,
    output reg [31:0] to_ack_sequence_num,
    output reg [31:0] to_ack_ack_num,
    output reg [7:0] to_ack_flags,
    output reg empty,
    output retransmit_pending
);
  reg rd_en;
  fifo #(
      .LOOKAHEAD(1),
      .DATA_WIDTH(107),
      .DEPTH(32)
  ) to_ack (
      .clk(clk),
      .rst(rst),
      .wr_en(wr_en),
      .din({
        to_send_sequence_num,
        to_send_ack_num,
        to_send_payload_size,
        to_send_payload_addr,
        to_send_flags
      }),
      .full(),
      .rd_en(rd_en),
      .dout({
        to_ack_sequence_num, to_ack_ack_num, to_ack_payload_size, to_ack_payload_addr, to_ack_flags
      }),
      .empty(empty),
      .count()
  );

  logic [31:0] target_ack_to_clear, current_ack;
  typedef enum {
    IDLE,
    MATCH,
    LOOP_WAIT,
    LOOP_WAIT2,
    LOOP,
    WAIT_RETRANSMIT
  } state_t;
  state_t state = IDLE;
  reg [15:0] size;
  reg [31:0] seq;
  reg [7:0] flags;
  always @(posedge clk) begin
    seq   <= to_ack_sequence_num;
    size  <= to_ack_payload_size;
    flags <= to_ack_flags;
  end
  always @(posedge clk) begin
    // the FIN ACK packet has 0 payload but expects a FIN ACK response that has ACK = SEQ + 1
    current_ack <= seq + ((flags == (tcp::FIN | tcp::ACK)) ? 'd1 : {16'b0, size});
  end
  always @(posedge clk) begin
    if (rst) state <= IDLE;
    else begin
      case (state)
        IDLE: begin
          rd_en <= 1'b0;
          target_ack_to_clear <= i_target_ack_to_clear;
          if (clear && !empty) begin
            state <= MATCH;
          end else if (retransmit_pending) begin
            state <= WAIT_RETRANSMIT;
          end
        end
        MATCH: begin
          if (target_ack_to_clear >= current_ack) begin
            rd_en <= 1;
            state <= LOOP_WAIT;
          end else state <= IDLE;
        end
        LOOP_WAIT: begin
          // wait for current_ack to update
          rd_en <= 0;
          state <= LOOP_WAIT2;
        end
        LOOP_WAIT2: begin
          // wait for current_ack to update
          rd_en <= 0;
          state <= LOOP;
        end
        LOOP: begin
          rd_en <= 0;
          if (empty) state <= IDLE;
          else state <= MATCH;
        end
        WAIT_RETRANSMIT: begin
          if (retransmit_granted) begin
            state <= IDLE;
            rd_en <= 1;
          end
        end
        default: begin
          state <= IDLE;
        end
      endcase
    end
  end

`ifdef SYNTHESIS
  assign retransmit_pending = retransmit_timer == 'd1250000000;
`else
  assign retransmit_pending = retransmit_timer == 'd2500;
`endif
  reg [31:0] retransmit_timer;
  always @(posedge clk) begin
    if (rd_en || rst || empty || retransmit_granted) retransmit_timer <= 0;
    else if (retransmit_pending) retransmit_timer <= retransmit_timer;
    else retransmit_timer <= retransmit_timer + 1;
  end
endmodule
