// Provides a classic integer divided clock that does not have 50% duty cycle
module clk_divider #(parameter RATIO = 2) (
  input clk_in,
  input rst,
  output wire clk_out
);
reg [31:0] counter;

always @(posedge clk_in) begin
  if (rst || counter == RATIO - 1) begin
    counter <= 0;
  end else begin
    counter <= counter + 1;
  end
end

assign clk_out = counter != 0;

endmodule

