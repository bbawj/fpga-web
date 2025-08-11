`include "utils.svh"

module rgmii_tx (
  input wire clk,
  input wire rst,
  input wire mac_phy_txen,
  input wire [7:0] mac_phy_txd,

  output wire phy_txctl, 
  output wire [3:0] phy_txd
);
reg [3:0] txd_1 = '0, txd_2 = '0;
wire mac_phy_txer;
assign mac_phy_txer = 0 ^ mac_phy_txen;
oddr #(.INPUT_WIDTH(1)) txctl_oddr(.rst(rst), .clk(clk), .d1(mac_phy_txen), .d2(mac_phy_txer), .q(phy_txctl));

always @* begin
  `ifdef SPEED_100M
    txd_1 = mac_phy_txd[3:0];
    txd_2 = mac_phy_txd[3:0];
  `else
    txd_1 = mac_phy_txd[3:0];
    txd_2 = mac_phy_txd[7:4];
  `endif
end

oddr #(.INPUT_WIDTH(4)) _oddr(.rst(rst), .clk(clk), .d1(txd_1), .d2(txd_2), .q(phy_txd));

endmodule

