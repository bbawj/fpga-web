`ifndef COCOTB_SIM
`default_nettype	none
`endif
module top(
    input wire clk_25mhz,
    input wire button,
    output wire led,
    output wire uart_tx,
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

wire rst;
areset _areset(.clk(clk_25mhz), .rst_n(button), .rst(rst));

uart uart_instance(
  .clk(clk_25mhz),
  .rst(rst),
  .valid(1'b1),
  .rx(8'h97),
  .rdy(),
  .tx(uart_tx)
  );

mac mac_instance(
  .clk(clk_25mhz),
  .rst(rst),
  .led(led),

  .phy_txd(phy0_txd),
  .phy_txctl(phy0_txctl),
  .phy_txc(phy0_txc),

  .phy_rxd(phy0_rxd),
  .phy_rxctl(phy0_rxctl),
  .phy_rxc(phy0_rxc),
  );

endmodule

