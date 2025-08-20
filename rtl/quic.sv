module quic (
  input wire clk,
  input wire rst,
  input valid,
  input [7:0] din,
  );
  localparam initial_salt = 160'h38762cf7f55934b34d179ae6a4c80cadccbb7f0a;
  localparam [511:0] initial_hmac_key = {initial_salt, (512-160){'h0}};

  typedef enum logic {INVALID, LONG, SHORT} HEADER_FORM;
  typedef enum logic {INITIAL, RTT_0, HANDSHAKE, RETRY} LONG_TYPES;
  typedef enum logic {IDLE, META, VERSION, DEST_LEN, DEST_CID, SRC_LEN, SRC_CID, TOKEN_LEN, TOKEN, ERR} STATE;
  STATE state;

  // max size of any header field is 160 bytes. Version negotiation can go
  // larger but is unsupported by this implementation.
  reg [159:0] working = '0;
  reg [7:0] counter = '0;
  reg [7:0] num_to_read = '0;
  HEADER_FORM header_form = INVALID;
  reg [1:0] pkt_num_len = '0;
  
  reg vid_done = 0, vid_valid = 0;
  reg [7:0] vid_len = '0;
  reg [63:0] vid_val = '0;
  var_int_decoder _vid(.clk(clk), .rst(rst), .valid(vid_valid), .din(rxd),
    .len(vid_len), .value(vid_val));

	reg [511:0] hmac_key = initial_hmac_key;
	reg [511:0] hmac_message = '0;
	reg [9:0] hmac_message_length = '0;
  reg hmac_valid = '0;
  reg hmac_last = '0;
  wire hmac_ready;
  wire hmac_digest_valid;
  reg [511:0] hmac_digest = '0;
  hmac_sha256 hmac(.clk(clk), .rst(rst), .K(hmac_key),
  .message(hmac_message), .message_length(hmac_message_length),
  .valid(hmac_valid), .is_last_message(hmac_last), .hmac_ready(hmac_ready)
  .hmac_valid(hmac_digest_valid), .digest(hmac_digest));

  always @(posedge clk) begin
    LONG_TYPES pkt_type;
    if (rst || !valid || err) begin
      working <= '0;
      counter <= '0;
      err <= 0;
      done <= 0;
      header_form <= INVALID;
      vid_valid <= 0;
    end else begin
      working <= {working[151:0], din};
      done <= 0;

      if (!done) counter <= counter + 1;
      case(state)
        IDLE: begin
          if (valid) state <= META;
        end
        ERR: begin
          err <= 1;
          if (!valid) state <= IDLE;
        end
        META: begin
          // Header form (0x8 = long header)
          case (working[7:6])
            2'b11: state <= VERSION;
            2'b01: state <= SHORT;
            default:
              state <= ERR;
          endcase
          case (working[5:4]) 
            2'b00: begin
              pkt_type <= INITIAL;
              if (working[3:2] != 2'b00) err <= 1'b1;
              pkt_num_len <= working[1:0];
            end
            2'b01: pkt_type <= RTT_0;
            2'b10: pkt_type <= HANDSHAKE;
            2'b11: pkt_type <= RETRY;
          endcase
        end
        VERSION: begin
          counter <= counter + 1;
          if (counter == 8'd3) begin 
            counter <= '0;
            if (working[31:0] != 32'd1) state <= ERR;
            else state <= DEST_LEN;
          end
        end
        DEST_LEN: begin
          counter <= '0;
          num_to_read <= working[7:0];
          // in QUICv1 this must not exceed 20 bytes
          if (working[7:0] > 8'd20) state <= ERR;
          else state <= DEST_CID;
        end
        DEST_CID: begin
          counter <= counter + 1;
          if (counter == num_to_read - 8'd1) begin
            dest_cid <= working[dest_cid_len*8:0];
            state <= SRC_LEN;
            counter <= '0;
          end
        end
        SRC_LEN: begin
          counter <= '0;
          num_to_read <= working[7:0];
          // in QUICv1 this must not exceed 20 bytes
          if (working[7:0] > 8'd20) state <= ERR;
          else state <= SRC_CID;
        end
        SRC_CID: begin
          counter <= counter + 1;
          if (counter == num_to_read - 8'd1) begin
            dest_cid <= working[dest_cid_len*8:0];
            counter <= '0;
            if (pkt_type == INITIAL) begin
              vid_valid <= 1'b1;
              state <= TOKEN_LEN;
            end
          end
        end
        TOKEN_LEN: begin
          counter <= '0;
          num_to_read <= vid_val;
          if (vid_done) begin
            vid_valid <= 1'b0;
            if (vid_val == '0) state <= LENGTH;
            else state <= TOKEN;
          end
        end
        TOKEN: begin
          counter <= counter + 8'd1;
          if (counter == num_to_read - 8'd1) begin
            vid_valid <= 1'b1;
            state <= LENGTH;
          end
        end
        LENGTH: begin
          counter <= '0;
          length <= vid_val;
          if (vid_done) begin
            vid_valid <= 1'b0;
            state <= PKT_NUM;
          end
        end
        PKT_NUM: begin
          counter <= counter + 8'd1;
          // pkt_num_len + 1 is the length of the pkt num in bytes
          if (counter == pkt_num_len) begin
            pkt_num <= working[(pkt_num_len+1)*8 : 0];
            state <= PAYLOAD;
          end
        end
      endcase

    end
  end

  typedef enum logic {IDLE, INIT_SECRET, INIT_SECRET_DONE, SERVER_SECRET} INITIAL_KEY_STATES;
  INITIAL_KEY_STATES initial_key_states = IDLE;
  always @(posedge clk) begin
    case (initial_key_states)
      IDLE: begin
        if (state == SRC_LEN && pkt_type == INITIAL) initial_key_states <= INIT_SECRET;
      end
      INIT_SECRET: begin
        hmac_key <= initial_hmac_key;
        hmac_valid <= 1'b1;
        hmac_last <= 1'b1;
        hmac_message <= dest_cid[dest_cid_len - 1:0];
        hmac_message_length <= dest_cid_len;
        state <= INIT_SECRET_DONE;
      end
      INIT_SECRET_DONE: begin
        if (hmac_digest_valid) begin
          hmac_last  <= hmac_digest;
        end
      end
    endcase
    // start derive initial secret
    if (state == SRC_LEN && pkt_type == INITIAL) begin
    end else begin
    end
  end

  endmodule
