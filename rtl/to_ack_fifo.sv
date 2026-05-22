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
    input retransmit_granted,

    output reg [18:0] to_ack_payload_addr,
    output reg [15:0] to_ack_payload_size,
    output reg [31:0] to_ack_sequence_num,
    output reg [31:0] to_ack_ack_num,
    output reg empty,
    output reg retransmit_pending
);
  reg rd_en;
  fifo #(
      .LOOKAHEAD(1),
      .DATA_WIDTH(99),
      .DEPTH(32)
  ) to_ack (
      .clk  (clk),
      .rst  (rst),
      .wr_en(wr_en),
      .din  ({to_send_sequence_num, to_send_ack_num, to_send_payload_size, to_send_payload_addr}),
      .full (),
      .rd_en(rd_en),
      .dout ({to_ack_sequence_num, to_ack_ack_num, to_ack_payload_size, to_ack_payload_addr}),
      .empty(empty),
      .count()
  );

  logic [31:0] target_ack_to_clear, current_ack;
  typedef enum {
    IDLE,
    MATCH,
    LOOP,
    WAIT_RETRANSMIT
  } state_t;
  state_t state = IDLE;
  always @(posedge clk) begin
    if (rst) state <= IDLE;
    else begin
      case (state)
        IDLE: begin
          rd_en <= 1'b0;
          target_ack_to_clear <= i_target_ack_to_clear;
          if (clear && !empty) begin
            state <= MATCH;
            current_ack <= to_ack_sequence_num + {16'b0, to_ack_payload_size};
          end else if (retransmit_pending) begin
            state <= WAIT_RETRANSMIT;
          end
        end
        MATCH: begin
          if (target_ack_to_clear >= current_ack) begin
            rd_en <= 1;
            state <= LOOP;
          end else state <= IDLE;
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
  assign retransmit_pending = retransmit_timer == 'd1250;
`endif
  reg [31:0] retransmit_timer;
  always @(posedge clk) begin
    if (rd_en || rst || empty || retransmit_granted) retransmit_timer <= 0;
    else if (retransmit_pending) retransmit_timer <= retransmit_timer;
    else retransmit_timer <= retransmit_timer + 1;
  end
endmodule
