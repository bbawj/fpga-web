`ifndef COCOTB_SIM
`default_nettype	none
`endif
module top(
    input wire clk_25mhz,
    input wire rst,
    // Shared PHY control
    output reg mdc,
    inout wire mdio,
    // PHY0 MII Interface
    output wire [3:0] phy0_txd,
    output wire phy0_txctl,
    output wire phy0_txc,
    input wire [3:0] phy0_rxd,
    input wire phy0_rxctl,
    input wire phy0_rxc
);

mac mac_instance(
  .clk(clk_25mhz),
  .rst(rst),

  .phy_txd(phy0_txd),
  .phy_txctl(phy0_txctl),
  .phy_txc(phy0_txc),

  .phy_rxd(phy0_rxd),
  .phy_rxctl(phy0_rxctl),
  .phy_rxc(phy0_rxc),
  );

endmodule

