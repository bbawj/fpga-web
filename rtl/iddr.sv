module iddr #(
  parameter INPUT_WIDTH = 1
  )(
  input wire clk,
  input wire [INPUT_WIDTH - 1 : 0] d,
  output reg [INPUT_WIDTH - 1: 0 ] q1,
  output reg [INPUT_WIDTH - 1 : 0] q2
  );
  reg [INPUT_WIDTH - 1: 0] d_reg_1 = '0;
  reg [INPUT_WIDTH - 1: 0] d_reg_2 = '0;
  always @(posedge clk) begin
    d_reg_1 <= d;
  end
  always @(negedge clk) begin
    d_reg_2 <= d;
  end

  always @(posedge clk) begin
    q1 <= d_reg_1;
    q2 <= d_reg_2;
  end
endmodule
