/**
* Takes a input signal and converts it to a pulse on an positive edge transition
*/
module pulse_gen (
  input clk,
  input sig,
  output reg q
  );

  reg [1:0] state;
  always @(posedge clk) begin
    state <= {state[0], sig};
  end

  always @* begin
    q = state[0] == '0 && sig == 1'b1;
  end

endmodule
