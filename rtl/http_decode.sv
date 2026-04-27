/**
* Parses TCP payload for a HTTP request. At the moment we support matching
* a bare minimum "GET <TARGET>\r\n" payload. TARGET should only be 1 byte for
* now.
*
* Response is asserted 3 cycles after i_payload_valid is de-asserted. Response
* is asserted for only 1 cycle with no handshaking.
*/
module http_decode #(
    parameter CAM_ADDR_FILE,
    parameter CAM_SIZE_FILE
) (
    input clk,
    input rst,
    input i_payload_valid,
    input [7:0] i_payload_data,
    output reg res_valid,
    output reg res_err,
    output reg [15:0] res_payload_size,
    output reg [15:0] res_payload_checksum,
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
    working <= i_payload_valid ? {working[23:0], i_payload_data} : working;
    method_counter <= state != METHOD ? 0 : method_counter + 'd1;
    target_counter <= state != TARGET ? 0 : target_counter + 'd1;

    // For now we only support ascii [0-7] and [a-z|A-Z]
    if (state == TARGET) key <= {1'b0, working[7:0]} - 'd48;

    case (state)
      IDLE: res_valid <= 1'b0;
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
        // take only the first byte as target endpoint
        next_state = MATCH;
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
      .content_size(res_payload_size),
      .content_checksum(res_payload_checksum)
  );
endmodule
