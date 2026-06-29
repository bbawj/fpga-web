`default_nettype none

module iddr #(
    parameter INPUT_WIDTH = 1
) (
    input wire clk,
    input wire [INPUT_WIDTH - 1 : 0] d,
    output wire [INPUT_WIDTH - 1:0] q1,
    output wire [INPUT_WIDTH - 1 : 0] q2
);
`ifdef SYNTHESIS
  genvar i;
  generate
    wire [INPUT_WIDTH-1:0] d_q;
    for (i = 0; i < INPUT_WIDTH; i = i + 1) begin
      // obtained from: https://github.com/jfrohnhofen/LiME/blob/5496e6c3390ac5efe244243c2c9bf33784a81c77/src/lime/net/Rgmii.scala#L55
      // Section 5.2 in CrossLink High-Speed I/O MIPI D-PHY and DDR Interfaces Technical Note
      // Compensate for clock injection delay
      DELAYG #(
          .DEL_MODE("SCLK_ALIGNED"),
          .DEL_VALUE(80)  // i think that only static value supported
      ) delay_inst (
          .A(d[i]),
          .Z(d_q[i])
      );
      IDDRX1F iddr_inst (
          .D(d_q[i]),
          .SCLK(clk),
          .RST(1'b0),
          .Q0(q1[i]),
          .Q1(q2[i])
      );
    end
  endgenerate
`else
  reg [INPUT_WIDTH - 1:0] d_reg_1 = '0;
  reg [INPUT_WIDTH - 1:0] d_reg_2 = '0;
  always @(posedge clk) begin
    d_reg_1 <= d;
  end
  always @(negedge clk) begin
    d_reg_2 <= d;
  end

  assign q1 = d_reg_1;
  assign q2 = d_reg_2;
`endif
endmodule
