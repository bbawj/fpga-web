/**
* Shall extract the what we need from the TCP header. Asserts done when
* finished with TCP header and payload starts
*/
`default_nettype none

module tcp_decode #(
    parameter MSS = 1460 + 4
) (
    input wire valid,
    input wire clk,
    input wire rst,
    input wire [7:0] din,
    // used for IP pseudo header in TCP checksum calc
    input wire [31:0] ip_sa,
    input wire [31:0] ip_da,
    input wire [3:0] ip_ihl,
    input wire [15:0] ip_payload_size,

    output reg [15:0] source_port,
    output reg [15:0] dest_port,
    output reg [31:0] sequence_num,
    output reg [31:0] ack_num,
    output reg [7:0] flags,
    output reg [15:0] window,
    // Asserted when a valid payload is on the line. Tie to a buffer for writing
    output reg payload_valid,
    output reg [7:0] payload,
    output reg [15:0] payload_size,
    output reg [15:0] payload_checksum,
    output reg err,
    output reg done
);

  reg [17:0] working_checksum = '0;
  reg [15:0] checksum = '0;
  reg [31:0] working = '0;
  reg [15:0] counter = '0, counter_q;
  reg [3:0] data_offset;

  typedef enum {
    IDLE,
    SRC_1,
    SRC_2,
    DEST_1,
    DEST_2,
    SEQ_1,
    SEQ_2,
    SEQ_3,
    SEQ_4,
    ACK_1,
    ACK_2,
    ACK_3,
    ACK_4,
    OFS,
    FLAGS,
    WNDW_1,
    WNDW_2,
    CHECKSUM_1,
    CHECKSUM_2,
    URG_1,
    URG_2,
    PAYLOAD_1,
    PAYLOAD_2,
    DONE
  } state_t;
  state_t state = IDLE;
  state_t next_state;
  state_t prev_state = IDLE;

  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      counter <= '0;
      counter_q <= 0;
    end else begin
      counter <= (state == IDLE) ? 'd1 : counter + 'd1;
      counter_q <= counter;
      working <= {working[23:0], din};
      state <= next_state;
      prev_state <= state;
    end
  end

  always_comb begin
    next_state = state;
    case (state)
      IDLE: if (valid) next_state = SRC_1;
      SRC_1: next_state = SRC_2;
      SRC_2: next_state = DEST_1;
      DEST_1: next_state = DEST_2;
      DEST_2: next_state = SEQ_1;
      SEQ_1: next_state = SEQ_2;
      SEQ_2: next_state = SEQ_3;
      SEQ_3: next_state = SEQ_4;
      SEQ_4: next_state = ACK_1;
      ACK_1: next_state = ACK_2;
      ACK_2: next_state = ACK_3;
      ACK_3: next_state = ACK_4;
      ACK_4: next_state = OFS;
      OFS: next_state = FLAGS;
      FLAGS: next_state = WNDW_1;
      WNDW_1: next_state = WNDW_2;
      WNDW_2: next_state = CHECKSUM_1;
      CHECKSUM_1: next_state = CHECKSUM_2;
      CHECKSUM_2: next_state = URG_1;
      URG_1: next_state = URG_2;
      URG_2: next_state = PAYLOAD_1;
      PAYLOAD_1: next_state = (!valid) ? DONE : PAYLOAD_2;
      PAYLOAD_2: next_state = (!valid) ? DONE : PAYLOAD_1;
      DONE: next_state = IDLE;
      default: next_state = IDLE;
    endcase
  end

  always @(posedge clk) begin
    case (state)
      SRC_2: source_port <= working[15:0];
      DEST_2: dest_port <= working[15:0];
      SEQ_4: sequence_num <= working;
      ACK_4: ack_num <= working;
      OFS: data_offset <= working[7:4];
      FLAGS: flags <= working[7:0];
      WNDW_2: window <= working[15:0];
      // CHECKSUM: checksum <= working[15:0];
      default: begin
      end
    endcase
  end

  always @(posedge clk) begin
    case (state)
      SRC_2, DEST_2, SEQ_2, SEQ_4, ACK_2, ACK_4, FLAGS, WNDW_2, CHECKSUM_2, URG_2:
      working_checksum <= working_checksum + {2'b0, working[15:0]};
      PAYLOAD_2: begin
        if (!valid) working_checksum <= working_checksum + {2'b0, working[15:8], 8'b0};
        else working_checksum <= working_checksum + {2'b0, working[15:0]};
      end
      PAYLOAD_1: begin
        working_checksum <= {2'b0, working_checksum[15:0]} + {16'b0, working_checksum[17:16]};
      end
      IDLE: working_checksum <= 18'd6 + {2'b0, ip_da[15:0]};
      SRC_1: working_checksum <= working_checksum + {2'b0, ip_da[31:16]};
      DEST_1: working_checksum <= working_checksum + {2'b0, ip_sa[31:16]};
      ACK_3: working_checksum <= working_checksum + {2'b0, ip_sa[15:0]};
      SEQ_3: working_checksum <= working_checksum + {2'b0, payload_size};
      SEQ_1, ACK_1, OFS, WNDW_1, CHECKSUM_1, URG_1:
      working_checksum <= {2'b0, working_checksum[15:0]} + {16'b0, working_checksum[17:16]};
      default: begin
      end
    endcase
  end

  always @(posedge clk) begin
    case (state)
      IDLE: payload_checksum <= '0;
      PAYLOAD_1:
      if (valid && prev_state == PAYLOAD_2)
        payload_checksum <= utils::ones_comp(payload_checksum, working[15:0]);
      // odd-sized payload, pad with zeroes for checksum calc
      PAYLOAD_2:
      if (!valid) payload_checksum <= utils::ones_comp(payload_checksum, {working[7:0], 8'b0});
      default: payload_checksum <= payload_checksum;
    endcase
  end

  always @(posedge clk) begin
    if (state == DONE) begin
      done <= 1'b1;
      err  <= working_checksum[15:0] != 16'hFFFF;
    end else begin
      done <= '0;
      err  <= '0;
    end
  end

  always @(posedge clk) begin
    if (prev_state == IDLE) payload_size <= ip_payload_size - (16'd4 * {12'd0, ip_ihl});
    else if (prev_state == FLAGS) payload_size <= payload_size - ({12'd0, data_offset} * 16'd4);
  end

  always @(posedge clk) begin
    case (state)
      PAYLOAD_1, PAYLOAD_2: begin
        //urg <= working[15:0];
        payload <= working[7:0];
        payload_valid <= 1'b1;
        if (!valid) begin
          payload_valid <= 1'b0;
        end
        // TODO: check overshoot MSS
        if (counter == MSS + 'd20) begin
        end
      end
      default: begin
        payload_valid <= '0;
      end
    endcase
  end

endmodule
