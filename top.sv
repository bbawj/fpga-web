`default_nettype	none
module top(
    input wire clk_25mhz,
    input wire button,
    output wire led,
    output wire uart_tx,
    // Shared PHY control
    output wire mdc,
    output wire mdio,
    // PHY0 MII Interface
    output wire [3:0] phy0_txd,
    output wire phy0_txctl,
    output wire phy0_txc,
    input wire [3:0] phy0_rxd,
    input wire phy0_rxctl,
    input wire phy0_rxc
);

// RGMII requires specific setup and hold times.
// This is achieved with a 90 degree phase offset tx_clk relative to the
// sysclk used to load the tx lines
reg pll_locked;
wire sysclk;
`ifdef SPEED_100M
// Phase range from 0 to 46, 0 phase is 23. Each division is 1/24 degrees
clk_gen #(.SYSCLK_DIV(24), .TXC_DIV(24), .TXC_PHASE(29), .MDC_DIV(240), .FB_DIV(1))
`else
// Phase range from 0 to 8, 0 phase is 4. Each division is 1/5 degrees
clk_gen #(.SYSCLK_DIV(5), .TXC_DIV(5), .TXC_PHASE(5), .MDC_DIV(250), .FB_DIV(5))
`endif
  _clk_gen (.clk_in(clk_25mhz), .sysclk(sysclk), .txc(phy0_txc), .mdc(mdc), .clk_locked(pll_locked));

wire rst;
areset _areset(.clk(sysclk), .rst_n(button), .rst(rst));

// wire [15:0] mdio_data;
// wire mdio_valid;

  // mdio mdio_instance(
  //   .clk(sysclk),
  //   .mdc(mdc),
  //   .en(),
  //   .op(),
  //   .phyad(),
  //   .regad(),
  //
  //   .mdio(mdio),
  //
  //   .valid(),
  //   .o_data(),
  //   );

mac mac_instance(
  .clk(sysclk),
  .rst(rst),
  .led(),

  .phy_txd(phy0_txd),
  .phy_txctl(phy0_txctl),

  .phy_rxd(phy0_rxd),
  .phy_rxctl(phy0_rxctl),
  .phy_rxc(phy0_rxc)
  );

  // blinky _blinky(.sysclk(sysclk), .led_n(led));

endmodule

