/**
* Parses TCP payload for a HTTP request. At the moment we support matching
* a bare minimum "GET <TARGET>\r\n" payload. TARGET should only be 1 byte for
* now.
*
* If the TCP engine has validated the request to be OK, pull the payload data
*/
module http_decode #(
    parameter string CAM_ADDR_FILE,
    parameter string CAM_SIZE_FILE
) (
    input clk,
    input rst,
    input i_payload_valid,
    input [7:0] i_payload_data,
    output reg res_valid,
    output reg res_err,
    output reg [15:0] res_payload_size,
    output reg [18:0] res_payload_addr
);

  typedef enum {
    IDLE,
    METHOD,
    TARGET,
    MATCH,
    WAIT_CAM,
    ABORT
  } state_t;

  state_t state, next_state;
  reg [ 8:0] key;
  reg [31:0] working;
  reg [2:0] method_counter, target_counter;
  always_ff @(posedge clk) begin
    state <= next_state;
    working <= {working[23:0], i_payload_data};
    method_counter <= state != METHOD ? 0 : method_counter + 'd1;
    target_counter <= state != TARGET ? 0 : target_counter + 'd1;

    // For now we only support ascii [0-7] and [a-z|A-Z]
    if (state == MATCH) key <= {1'b0, working[7:0]} - 'd48;

    case (state)
      METHOD: res_valid <= 1'b0;
      WAIT_CAM: begin
        res_valid <= 1'b1;
        res_err   <= res_payload_addr == '0 || res_payload_size == '0;
      end
      ABORT: begin
        res_valid <= 1'b1;
        res_err   <= 1'b1;
      end
      default: begin
        res_valid <= res_valid;
        res_err   <= res_err;
      end
    endcase
  end

  always_comb begin
    next_state = state;
    case (state)
      IDLE: if (i_payload_valid) next_state = METHOD;
      METHOD:
      if (method_counter == 'd3) begin
        if ("GET " == working) next_state = TARGET;
        else next_state = ABORT;
      end
      TARGET: begin
        // more than 2 byte in the target, invalid
        if (target_counter >= 'd2) next_state = ABORT;
        if (!i_payload_valid) next_state = MATCH;
      end
      MATCH: begin
        next_state = WAIT_CAM;
      end
      WAIT_CAM: begin
        next_state = IDLE;
      end
      ABORT: if (!i_payload_valid) next_state = IDLE;
      default: next_state = IDLE;
    endcase
  end

  http_entry #(
      .CAM_ADDR_FILE(CAM_ADDR_FILE),
      .CAM_SIZE_FILE(CAM_SIZE_FILE)
  ) cam (
      .clk(clk),
      .key(key),
      .content_addr(res_payload_addr),
      .content_size(res_payload_size)
  );
endmodule
