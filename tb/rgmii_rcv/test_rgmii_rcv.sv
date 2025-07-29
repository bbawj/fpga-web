`default_nettype none

module test_rgmii_rcv(
    input wire clk,
    input wire rst,
    input wire [3:0] phy_rxd,
    input wire phy_rxctl,
    input wire phy_rxc,

    output reg rgmii_rcv_crc_err,
    output reg arp_decode_valid,
    output reg ip_valid
);

localparam [47:0] LOC_MAC_ADDR = 48'hDEADBEEFCAFE;

reg [7:0] rxd;
wire rxc, rx_dv, rx_er;
rgmii_rcv rcv (
  .rst(rst),
  .mii_rxc(phy_rxc),
  .mii_rxd(phy_rxd),
  .mii_rxctl(phy_rxctl),

  .rxc(rxc),
  .rxd(rxd),
  .rx_dv(rx_dv),
  .rx_er(rx_er)
  );

reg rgmii_rcv_busy;
reg [47:0] mac_sa;
mac_decode #(.MAC_ADDR(LOC_MAC_ADDR)) _mac_decode (
  .clk(rxc),
  .rst(rst),
  .rxd(rxd),
  .rx_dv(rx_dv),

  .sa(mac_sa),
  .busy(rgmii_rcv_busy),
  .crc_err(rgmii_rcv_crc_err),
  .arp_decode_valid(arp_decode_valid),
  .ip_valid(ip_valid)
  );

endmodule
