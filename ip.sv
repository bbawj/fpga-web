module ip_decode (
  input valid;
  input clk;
  input [3:0] din;

  output reg err;
  output reg dout_ready; // data is ready
  output reg [3:0] dout; // stripped IPV4 data
);
reg [15:0] checksum;
reg [31:0] working;
reg [7:0] counter;
reg [2:0] nibble_counter;
reg [3:0] header_len;
reg [15:0] total_len;
reg [7:0] protocol;

always @(posedge clk) begin
  if (valid) begin
    working <= {working[27:0], din};
    counter <= counter + 1;

    nibble_counter <= nibble_counter + 1;
    if (nibble_counter == 3'd4) crc_calc(checksum, working[15:0]);

    case (counter)
      // IPV4 Version MUST BE 4
      7'd0: if (din != 4) err <= 1;
      7'd1: header_len <= din;
      // ignored DSCP and ECN
      7'd8: total_len <= working;
      // ignored ID, Flags, Fragment Offset, ttl
      7'd20: protocol <= working[7:0];
      7'd24: begin
        if (checksum != 0) err <= 1;
      end
      7'd32: sa <= working;
      7'd40: da <= working;
      default: begin
        // ignore counter < header_len (options not supported)
        // passthrough data until total_len
        if (counter > header_len * 4 && counter * 4 <= total_len) begin
          dout_ready <= 1'b1;
          dout <= working[3:0];
        end else begin
          dout_ready <= 1'b0;
          dout <= 4'b0;
        end
      end
    endcase
  end else begin
    dout_ready <= 1'b0;
    dout <= '0;
    err <= 0;
    checksum <= '0;
    working <= '0;
    counter <= '0;
    nibble_counter <= '0;
  end
end

endmodule

function automatic logic [15:0] crc_calc(logic [15:0] checksum, logic [15:0] data);
  integer one_complement = ~data;
  integer sum = one_complement + checksum[15:0];
  if (sum[16])
    crc_calc = sum[15:0] + 1;
  else
    crc_calc = sum[15:0];
endfunction
