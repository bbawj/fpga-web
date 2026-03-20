/**
* Shall extract the what we need from the TCP header. Asserts done when
* finished with TCP header and payload starts
*/
`default_nettype none
`include "utils.svh"

module tcp_decode #(
    parameter MSS = 1460 + 4
) (
    input valid,
    input clk,
    input rst,
    input [7:0] din,
    // used for IP pseudo header in TCP checksum calc
    input [31:0] ip_sa,
    input [31:0] ip_da,
    input [3:0] ip_ihl,
    input [15:0] ip_payload_size,

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
    output reg err,
    output reg done
);

  reg [15:0] working_checksum = '0;
  reg [15:0] checksum = '0;
  reg [31:0] working = '0;
  reg [15:0] counter = '0;
  reg [ 3:0] data_offset;

  typedef enum {
    IDLE,
    SA,
    DA,
    SEQ,
    ACK,
    OFS,
    FLAGS,
    WNDW,
    CHECKSUM,
    PAYLOAD,
    DONE
  } state_t;
  state_t state = IDLE;
  state_t next_state;
  state_t prev_state = IDLE;

  always @(posedge clk) begin
    if (rst) begin
      state   <= IDLE;
      counter <= '0;
    end else begin
      counter <= (state == IDLE) ? 'd1 : counter + 'd1;
      working <= {working[23:0], din};
      state   <= next_state;
    end
  end

  always_comb begin
    next_state = state;
    case (state)
      IDLE: if (valid) next_state = SA;
      SA: if (counter == 'd1) next_state = DA;
      DA: if (counter == 'd3) next_state = SEQ;
      SEQ: if (counter == 'd7) next_state = ACK;
      ACK: if (counter == 'd11) next_state = OFS;
      OFS: if (counter == 'd12) next_state = FLAGS;
      FLAGS: if (counter == 'd13) next_state = WNDW;
      WNDW: if (counter == 'd15) next_state = CHECKSUM;
      CHECKSUM: if (counter == 'd17) next_state = PAYLOAD;
      PAYLOAD: if (!valid) next_state = DONE;
      DONE: next_state = IDLE;
      default: next_state = IDLE;
    endcase
  end

  always @(posedge clk) begin
    prev_state <= state;
    if (prev_state != state) begin
      case (prev_state)
        SA: source_port <= working[15:0];
        DA: dest_port <= working[15:0];
        SEQ: sequence_num <= working;
        ACK: ack_num <= working;
        OFS: data_offset <= working[7:4];
        FLAGS: flags <= working[7:0];
        WNDW: window <= working[15:0];
        CHECKSUM: checksum <= working[15:0];
        default: begin
        end
      endcase
    end
  end

  always @(posedge clk) begin
    if (!valid) working_checksum <= '0;
    else if (counter != '0 && !counter[0])
      working_checksum <= ones_comp(working_checksum, working[15:0]);
  end

  always @(posedge clk) begin
    case (state)
      IDLE: begin
        done <= '0;
        err <= '0;
        payload_valid <= '0;
        if (valid) begin
          logic [17:0] sum;
          payload_size <= ip_payload_size - (4'd4 * ip_ihl);
          sum = 18'd6 + {2'b0, ip_da[15:0]} + {2'b0, ip_da[31:16]} + {2'b0, ip_sa[15:0]} + {2'b0, ip_sa[31:16]}
          + {2'b0, (ip_payload_size - 4'd4 * ip_ihl)};
          sum = {2'b0, sum[15:0]} + {16'b0, sum[17:16]};
          sum = {2'b0, sum[15:0]} + {16'b0, sum[17:16]};
          working_checksum <= sum[15:0];
        end
      end
      FLAGS: payload_size <= payload_size - data_offset * 4;
      PAYLOAD: begin
        //urg <= working[15:0];
        payload <= working[7:0];
        payload_valid <= 1'b1;
        // TODO: check overshoot MSS
        if (counter == MSS + 'd20) begin
        end
      end
      DONE: begin
        done <= 1'b1;
        err  <= !(working_checksum == '1);
      end
      default: begin
      end
    endcase
  end

endmodule
