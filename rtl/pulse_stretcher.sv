// takes a strobe signal d and stretches it over FACTOR cycles
module pulse_stretcher #(
    parameter FACTOR = 2
) (
    input  wire clk,
    input  wire d,
    output wire q
);
  reg [FACTOR : 0] delay = '0;
  assign q = d | delay[FACTOR-1:0] != 0;

  always @(posedge clk) begin
    delay <= {delay[FACTOR-1:0], 1'b0};
    // fluctuations in `d` ignored while stretching
    if (d && delay == '0) delay[0] <= d;
  end
endmodule
