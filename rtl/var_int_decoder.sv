/**
* QUIC variable integer decoder
* RFC 9000 A.1
*/
module var_int_decoder(
  input wire clk,
  input wire rst,
  input wire valid,
  input [7:0] din,

  output reg done,
  output reg [7:0] len,
  output reg [63:0] value,
  );
  reg [7:0] counter = '0;
  always @(posedge clk) begin
    if (!valid || rst) begin
      len <= '0;
      value <= '0;
      done <= '0;
    end else begin
      len <= 1 << din[7:6];
      counter <= counter + 1;
      if (counter == 8'd0) value <= din[5:0];
      else if (counter < len) begin
        value <= {value[7:0], din};
        if (counter == len - 8'd1) done <= 1'b1;
      end
    end
  end
endmodule
