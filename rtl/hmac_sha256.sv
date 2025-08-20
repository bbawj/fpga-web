module hmac_sha256 (
  input clk,
  input rst,
  // HMAC SHA256 requires key length 64 bytes, assumed that input will pad
  // 0s to the right of the actual key if actual length is smaller.
  // K is also assumed to be stable until is_last is raised
  input [511:0] K,
  // message input is streamed in 512 bit blocks
  input [511:0] message,
  // if message_length is not 512, it is passed according to SHA256 rules
  input [9:0] message_length,

  input valid,
  input is_last_message,

  output hmac_ready,
  output hmac_valid,
  output [511:0] digest
  );

  localparam [511:0] opad = 64{8'h5c};
  localparam [511:0] ipad = 64{8'h36};

  reg is_last_sha = '0;
  reg [511:0] next = '0;
  reg sha_valid_i = '0;
  reg sha_digest_valid = '0;
  reg [511:0] sha_digest = '0;
  reg [511:0] sha_in = '0;
  sha256_stream _sha256 (.clk(clk), .rst(rst), .mode(1'b1),
   .s_tdata_i(sha_in),
   .s_tlast_i(is_last_sha),
   .s_tvalid_i(sha_valid_i),

   .s_tready_o(hmac_ready),
   .digest_o(sha_digest),
   .digest_valid_o(sha_digest_valid));

   typedef enum logic {IDLE, INNER, STALL1, STALL2, OUTER, DONE} STATE;
   STATE state = IDLE;
   always @(posedge clk) begin
     if (rst) begin
       sha_valid_i <= 1'b0;
       is_last_sha <= 1'b0;
       hmac_valid <= 1'b0;
     end else begin
       case (state)
         IDLE: begin
           sha_valid_i <= 1'b0;
           is_last_sha <= 1'b0;
           hmac_valid <= 1'b0;

           if (valid && hmac_ready) begin
            sha_valid_i <= 1'b1;
            sha_in <= K ^ ipad;
            next <= pad(message);
            is_last_sha <= 1'b0;
            state <= INNER;
          end
         end
         INNER: begin
           is_last_sha <= 1'b0;
           next <= message;
           sha_in <= next;
           if (is_last_message) state <= STALL1;
         end
         STALL1: begin
           is_last_sha <= 1'b1;
           sha_in <= next;
           state <= STALL2;
         end
         STALL2: begin
           if (digest_valid) begin
             state <= OUTER;
             next <= sha_digest;
             sha_in <= K ^ opad;
             is_last_sha <= 1'b0;
           end
         end
         OUTER: begin
           sha_in <= next;
           state <= DONE;
           is_last_sha <= 1'b1;
         end
         DONE: begin
           hmac_valid <= 1'b1;
           if (!valid) state <= IDLE;
         end
       endcase
     end
   end

   function automatic logic [511:0] pad (logic [511:0] in, logic [9:0] length);
      pad = {in[length - 1:0], 1'b1, (512-length-64-1){'h0},64'h20};
   endfunction

endmodule
