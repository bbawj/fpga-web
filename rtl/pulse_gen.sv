`default_nettype none
/**
* Takes a input signal and converts it to a pulse on an positive edge transition
*/
module pulse_gen (
    input  wire clk,
    input  wire rst,
    input  wire sig,
    output reg  q = 0
);

  reg [1:0] state = '0;
  always @(posedge clk) begin
    if (rst) state <= '0;
    else state <= {state[0], sig};
  end

  always @* begin
    q = state[0] == '0 && sig == 1'b1;
  end

endmodule
