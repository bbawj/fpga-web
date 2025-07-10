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

reg arp_e_valid;
reg arp_e_ovalid;
reg [3:0] arp_e_dout;
arp_encode arp_e(
  .clk(clk),
  .rst(rst),
  .valid(arp_e_valid),
  .tha(arp_sha),
  .tpa(arp_spa),

  .ovalid(arp_e_ovalid),
  .dout(arp_e_dout),
  );

reg txen = '0;
reg [3:0] txd = '0;
reg send_next;
rgmii_phy_if #(.MAC_ADDR('0)) phy(
  .clk(clk), .rst(rst), .mac_phy_txen(txen), .mac_phy_txd(txd),
  .mac_dest('0), .send_next(send_next), .txctl(phy_txctl), .dout(phy_txd)
);

// RX path
reg arp_valid = 0;
reg ip_valid = 0;
mii_rcv rcv (
  .clk(clk),
  .rst(rst),
  .mii_rxd(phy_rxd),
  .mii_rxctl(phy_rxctl),
  .crc_err(),
  .arp_valid(arp_valid),
  .ip_valid(ip_valid)
  );

reg ip_err = 0;
reg ip_dout_ready = 0;
reg [3:0] ip_dout;
ip_decode ip_decoder(.valid(ip_valid), .clk(clk), .din(phy_txd), 
  .err(ip_err), 
  .dout_ready(ip_dout_ready),
  .dout(ip_dout)
  );

reg arp_err = 0;
reg arp_done = 0;
reg [47:0] arp_sha = '0;
reg [31:0] arp_spa = '0;
reg [31:0] arp_tpa = '0;
arp_decode arp_d(
  .clk(clk),
  .rst(rst),
  .valid(arp_valid),
  .din(phy_rxd),
  .sha(arp_sha),
  .spa(arp_spa),
  .tpa(arp_tpa),
  .err(arp_err),
  .done(arp_done)
  );

`endif

endmodule

