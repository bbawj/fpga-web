module test_mac ( 
    input wire clk,
    input wire rst,
    
    output reg [3:0] phy_txd,
    output reg phy_txctl,
    output wire phy_txc,
    input wire [3:0] phy_rxd,
    input wire phy_rxctl,
    input wire phy_rxc
);

mac mac_instance(
  .clk(clk),
  .rst(rst),
  .led(),

  .phy_txd(phy_txd),
  .phy_txctl(phy_txctl),

  .phy_rxd(phy_rxd),
  .phy_rxctl(phy_rxctl),
  .phy_rxc(phy_rxc)
  );

endmodule
