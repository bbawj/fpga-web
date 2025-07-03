module mac ( 
    input wire clk_25mhz,
    input wire rst,
    
    // PHY0 MII Interface
    output reg [3:0] phy_txd,
    output reg phy_txctl,
    output reg phy_txc,
    input wire [3:0] phy_rxd,
    input wire phy_rxctl,
    input wire phy_rxc
);

// RGMII requires specific setup and hold times.
// This is achieved with a 90 degree phase offset tx_clk relative to the
// sysclk used to load the tx lines
reg pll_locked;
clk_gen #(.CLKOP_FPHASE(2), .STEPS(1)) txc_phase90 (.clk_in(clk_25mhz), .clk_out(phy_txc), .clk_locked(pll_locked));

`ifdef LOOPBACK
  reg [3:0] rxd_temp = '0;
  reg rxdv = 0, rxer = 0;
  always @(posedge phy_rxc) begin
    if (rst) begin
      rxd_temp <= '0;
      rxdv <= '0;
    end else begin
      rxd_temp <= phy_rxd;
      rxdv <= phy_rxctl;
    end
  end
  always @(negedge phy_rxc) begin
    if (rst) rxer <= '0;
    else
    rxer <= phy_rxctl;
  end

  always @(posedge clk_25mhz) begin
    phy_txd <= rxd_temp;
  end

  // RXDV RXER
  // 0    0   0 
  // 0    1   0
  // 1    0   0
  // 1    1   1
  assign phy_txctl = clk_25mhz ? rxdv : rxer;

`else

mii_rcv _mii_rcv(.clk(phy_rxc), .data(phy_rxd), .rxctl(phy_rxctl));
rgmii_phy_if (.clk(clk), .mac_gmii_txd(

reg [7:0] send_data;
always @(posedge clk) begin

end

`endif

endmodule

