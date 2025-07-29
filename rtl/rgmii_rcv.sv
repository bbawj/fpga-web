module rgmii_rcv (
  input wire rst,
  input wire mii_rxc,
  input wire [3:0] mii_rxd,
  input wire mii_rxctl,

  output reg rxc,
  output reg rx_dv,
  output reg rx_er,
  output reg test,
  output reg [7:0] rxd
);

`ifdef SPEED_100M
reg counter = 0;
assign test = 1;
clk_divider _div(.clk_in(mii_rxc), .rst(rst), .clk_out(rxc));
always @(posedge mii_rxc) begin
  if (rst) begin
    rxd <= '0;
  end
  rxd <= {mii_rxd, rxd[7:4]};
end
`else
reg [3:0] rxd_1, rxd_2;
assign rxd = {rxd_2, rxd_1};

iddr #(.INPUT_WIDTH(4)) rxd_iddr(.clk(mii_rxc), .d(mii_rxd), .q1(rxd_1), .q2(rxd_2));
assign test = 0;
assign rxc = mii_rxc;
`endif
// TODO: deal with rx_er
iddr #(.INPUT_WIDTH(1)) rxctl_iddr(.clk(mii_rxc), .d(mii_rxctl), .q1(rx_dv), .q2(rx_er));

endmodule
