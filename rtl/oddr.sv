module oddr #(
  parameter INPUT_WIDTH = 1
  )(
    input wire rst,
  input wire clk,
  input wire [INPUT_WIDTH - 1 : 0] d1,
  input wire [INPUT_WIDTH - 1: 0 ] d2,
  output wire [INPUT_WIDTH - 1 : 0] q
  );
`ifdef SYNTHESIS
genvar i;
generate
  for (i = 0; i < INPUT_WIDTH; i = i + 1) begin
    ODDRX1F oddr_inst(.SCLK(clk), .RST(rst), .D0(d1[i]), .D1(d2[i]), .Q(q[i]));
  end
endgenerate
`else
  reg [INPUT_WIDTH - 1: 0] d_reg_1 = '0;
  reg [INPUT_WIDTH - 1: 0] d_reg_2 = '0;

  reg [INPUT_WIDTH - 1 : 0] q_reg = '0;
  always @(negedge clk) begin
    d_reg_1 <= d1;
    d_reg_2 <= d2;
  end
/* verilator lint_off MULTIDRIVEN */
  always @(posedge clk) begin
    q_reg <= d_reg_1;
  end
  always @(negedge clk) begin
    q_reg <= d_reg_2;
  end
  assign q = q_reg;
/* verilator lint_on MULTIDRIVEN */
`endif
endmodule
