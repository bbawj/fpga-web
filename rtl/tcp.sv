module tcp_decode(
  input valid;
  input clk;
  input [3:0] din;
);

reg [15:0] checksum;
reg [31:0] working;
reg [7:0] counter;

always @(posedge clk) begin
  if (valid) begin
    working <= {working[27:0], din};
    counter <= counter + 1;

    nibble_counter <= nibble_counter + 1;
    if (nibble_counter == 3'd4) crc_calc(checksum, working[15:0]);
    
    case (counter)

    endcase
  end
end

endmodule
