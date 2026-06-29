/**
* Parses TCP payload for a HTTP request. At the moment we support matching
* a bare minimum "GET <TARGET>\r\n" payload. TARGET should only be 1 byte for
* now.
*
* Response is asserted 3 cycles after i_payload_valid is de-asserted. Response
* is asserted for only 1 cycle with no handshaking.
*/
module http_decode #(
    parameter HTTP_ADDR_FILE = "",
    parameter HTTP_SIZE_FILE = ""
) (
    input clk,
    input rst,
    input tcp_payload_valid,
    input i_payload_valid,
    input [31:0] i_payload_data,
    // Asserted to ask for the payload
    output reg payload_rd_en,
    output reg res_valid,
    output reg res_err,
    output reg [15:0] res_payload_size,
    output reg [18:0] res_payload_addr
);

  typedef enum {
    IDLE,
    GET_PAYLOAD,
    METHOD,
    TARGET,
    MATCH,
    // FIXME: might not need extra stall here
    WAIT_CAM1,
    WAIT_CAM2,
    ABORT
  } state_t;

  state_t state, next_state;
  reg [ 8:0] key;
  reg [31:0] working;
  reg [ 2:0] method_counter;
  always_ff @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      method_counter <= '0;
      res_valid <= 0;
      res_err <= 0;
      payload_rd_en <= 0;
    end else begin
      state <= next_state;
      working <= i_payload_valid ? i_payload_data : working;
      method_counter <= state != METHOD ? 0 : method_counter + 'd1;

      // For now we only support ascii [0-7] and [a-z|A-Z]
      // working contains {X,X,0,\}: X = dont-care
      // -48: convert to ascii
      // +1: 0 index is 404
      if (state == TARGET) key <= {1'b0, working[15:8]} - 'd47;

      case (state)
        IDLE: begin
          res_valid <= 1'b0;
          res_err <= 0;
          payload_rd_en <= 0;
        end
        METHOD: begin
          payload_rd_en <= 1;
        end
        TARGET, GET_PAYLOAD: begin
          payload_rd_en <= 1;
        end
        WAIT_CAM2: begin
          res_valid <= 1'b1;
          res_err <= res_payload_size == '0;
          payload_rd_en <= 0;
        end
        ABORT: begin
          res_valid <= 1'b0;
          res_err <= 1'b0;
          payload_rd_en <= 0;
        end
        default: begin
          res_valid <= res_valid;
          res_err <= res_err;
          payload_rd_en <= 0;
        end
      endcase
    end
  end

  always_comb begin
    next_state = state;
    case (state)
      IDLE: if (tcp_payload_valid) next_state = GET_PAYLOAD;
      GET_PAYLOAD: if (i_payload_valid) next_state = METHOD;
      METHOD: begin
        // LSB order
        if (" TEG" == working) next_state = TARGET;
        else next_state = ABORT;
      end
      TARGET: begin
        // take only the first byte as target endpoint
        next_state = MATCH;
      end
      MATCH: begin
        next_state = WAIT_CAM1;
      end
      WAIT_CAM1: next_state = WAIT_CAM2;
      WAIT_CAM2: begin
        next_state = IDLE;
      end
      ABORT: if (!tcp_payload_valid) next_state = IDLE;
      default: next_state = IDLE;
    endcase
  end

  http_entry #(
      .HTTP_ADDR_FILE(HTTP_ADDR_FILE),
      .HTTP_SIZE_FILE(HTTP_SIZE_FILE)
  ) cam (
      .clk(clk),
      .key(key),
      .content_addr(res_payload_addr),
      .content_size(res_payload_size),
      .content_checksum()
  );
endmodule
