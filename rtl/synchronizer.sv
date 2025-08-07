module synchronizer #(
  parameter INPUT_WIDTH = 1,
  parameter SYNC_WIDTH = 2
) (
  input wire clk,
  input wire [INPUT_WIDTH-1:0] sig,

  output reg [INPUT_WIDTH-1:0] q
);
  reg [SYNC_WIDTH * INPUT_WIDTH - 1 : 0] d;

  integer i;
  always @(posedge clk) begin
    for (i = 0; i <= SYNC_WIDTH - 2; i = i + 1) begin
      d[i] <= d[(i + 1) * INPUT_WIDTH - 1];
    end
    d[SYNC_WIDTH-1] <= sig;
    q <= d[0];
  end
endmodule
