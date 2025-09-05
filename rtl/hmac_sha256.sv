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
  input [63:0] message_length,

  input valid,
  input is_last_message,

  output hmac_ready,
  output reg hmac_valid,
  output reg [255:0] digest
  );

  localparam [511:0] opad = {64{8'h5c}};
  localparam [511:0] ipad = {64{8'h36}};

  reg is_first_sha = '0;
  reg [63:0] accum_length = '0;
  reg [511:0] next = '0;
  reg sha_valid_i = '0;
  reg [511:0] sha_in = '0;
  wire sha_digest_valid;
  wire [255:0] sha_digest;
  sha256_stream _sha256 (.clk(clk), .rst(rst), .mode(1'b1),
   .s_tdata_i(sha_in),
   .s_tfirst_i(is_first_sha),
   .s_tvalid_i(sha_valid_i),

   .s_tready_o(hmac_ready),
   .digest_o(sha_digest),
   .digest_valid_o(sha_digest_valid));

   typedef enum {IDLE, STALL0, INNER, STALL1, STALL2, STALL3, OUTER, STALL4, DONE} STATE;
   STATE state = IDLE;
   always @(posedge clk) begin
     if (rst) begin
       sha_valid_i <= 1'b0;
       is_first_sha <= 1'b0;
       hmac_valid <= 1'b0;
     end else begin
       case (state)
         IDLE: begin
           sha_valid_i <= 1'b0;
           is_first_sha <= 1'b0;
           hmac_valid <= 1'b0;

           if (valid && hmac_ready) begin
             // first step is to hash the key
            sha_in <= K ^ ipad;
            sha_valid_i <= 1'b1;
            is_first_sha <= 1'b1;

            state <= STALL0;
          end
         end
         STALL0: begin
           // wait for SHA core to start processing
           if (!hmac_ready) state <= INNER; 
         end
         INNER: begin
           sha_valid_i <= 1'b0;
           is_first_sha <= 1'b0;
           // TODO check input valid
           if (hmac_ready) begin
             sha_valid_i <= 1'b1;
             if (!is_last_message) begin
               sha_in <= message;
               accum_length <= accum_length + message_length;
               state <= STALL0;
             end else begin
               pad(message, message_length, sha_in);
               accum_length <= '0;
               state <= STALL1;
             end
           end
         end
         STALL1: begin
           sha_valid_i <= 1'b1;
           is_first_sha <= 1'b0;
           // sha_in <= next;

           if (!hmac_ready) begin
             state <= STALL2;
           end
         end
         STALL2: begin
           sha_valid_i <= 1'b0;
           is_first_sha <= 1'b0;
           if (hmac_ready && sha_digest_valid) begin
             sha_valid_i <= 1'b1;
             is_first_sha <= 1'b1;
             sha_in <= K ^ opad;
             pad({sha_digest, 256'h0}, 256, next);
             state <= STALL3;
           end
         end
         STALL3: begin
           if (!hmac_ready) state <= OUTER;
         end
         OUTER: begin
           sha_valid_i <= 1'b0;
           is_first_sha <= 1'b0;
           if (hmac_ready) begin
             sha_valid_i <= 1'b1;
             is_first_sha <= 1'b0;
             sha_in <= next;
             state <= STALL4;
           end
         end
         STALL4: begin
           if (!hmac_ready) state <= DONE;
         end
         DONE: begin
           sha_valid_i <= 1'b0;
           is_first_sha <= 1'b1;
           if (sha_digest_valid) begin
             digest <= sha_digest;
             hmac_valid <= 1'b1;
           end
           if (!valid) state <= IDLE;
         end
       endcase
     end
   end

   // padding only needs to be done on the last message, where the additonal
   // bit is added. for HMAC use case, padding the last message will always
   // require a final block of 0s plus the length bits as the length is always
   // larger than 512 due to the 512 bit key
   task pad (input [511:0] in, input [63:0] length, output [511:0] out1);
     reg [63:0] message_length_with_key;
     out1 = in;
     // out2 = 512'd0;
     if (length < 64'd512) out1[511-length] = 1'b1;
     // else out2[511] = 1'b1;
     if (length + 64 + 1 <= 512) out1[63:0] = 64'd512 + length;
     // else out2[63:0] = message_length_with_key;
   endtask

endmodule
