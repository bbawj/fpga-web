/**
* Pseudo Random Number Generator using LFSR and specific taps
*/
module lfsr_rng #(
  parameter DATA_WIDTH = 8
  )(
  input clk,
  input rst,
  input [DATA_WIDTH-1:0] seed,
  output reg [DATA_WIDTH-1:0] dout
  );

  wire feedback;
  generate
    if (DATA_WIDTH == 8)
      assign feedback = dout[0] ^ dout[2] ^ dout[3] ^ dout[4];
    else if (DATA_WIDTH == 16)
      assign feedback = dout[0] ^ dout[2] ^ dout[3] ^ dout[5];
    else if (DATA_WIDTH == 32)
      assign feedback = dout[0] ^ dout[10] ^ dout[30] ^ dout[31];
    else
      assign feedback = dout[0] ^ dout[1];
  endgenerate

  reg init = '0;

  always @(posedge clk) begin
    if (rst) begin
      dout <= seed;
    end else begin
      dout <= {feedback, dout[DATA_WIDTH-1:1]};
    end
  end
endmodule
