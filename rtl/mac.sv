`default_nettype none
`include "utils.svh"

module mac (
    input  wire clk,
    input  wire rst,
    output wire led,
    output wire uart_tx,

    // PHY0 MII Interface
    output reg [3:0] phy_txd,
    output reg phy_txctl,
    input wire [3:0] phy_rxd,
    input wire phy_rxctl,
    input wire phy_rxc
);

  localparam [47:0] LOC_MAC_ADDR = 48'hDEADBEEFCAFE;
  localparam [31:0] LOC_IP_ADDR = 32'h69696969;

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
    else rxer <= phy_rxctl;
  end

  always @(posedge clk) begin
    phy_txd <= rxd_temp;
  end

  // RXDV RXER
  // 0    0   0 
  // 0    1   0
  // 1    0   0
  // 1    1   1
  assign phy_txctl = clk ? rxdv : rxer;

`else

  reg send_arp, send_tcp;
  mac_tx #(
      .MY_MAC_ADDR(LOC_MAC_ADDR),
      .MY_IP_ADDR (LOC_IP_ADDR)
  ) tx (
      .clk(clk),
      .sdram_clk(),
      .rst(rst),
      .i_mac_da(mac_sa),

      .send_arp(send_arp),
      .i_arp_encode_tha(arp_encode_tha),
      .i_arp_encode_tpa(arp_encode_tpa),

      .send_tcp(),
      .pkt(),
      .tcp_payload_rd_valid(),
      .tcp_payload_rd_data(),
      .tcp_payload_rd_en(),
      .tcp_payload_rd_ad(),

      .phy_txd  (phy_txd),
      .phy_txctl(phy_txctl)
  );
  // RX path
  reg [7:0] rxd;
  wire rxc, rx_dv, rx_er;
  rgmii_rcv rcv (
      .rst(rst),
      .mii_rxc(phy_rxc),
      .mii_rxd(phy_rxd),
      .mii_rxctl(phy_rxctl),

      .rxc  (rxc),
      .rxd  (rxd),
      .rx_dv(rx_dv),
      .rx_er(rx_er)
  );

  reg arp_decode_valid;
  reg ip_valid;
  reg rgmii_rcv_busy;
  reg rgmii_rcv_crc_err;
  reg [47:0] mac_sa;
  mac_decode #(
      .MAC_ADDR(LOC_MAC_ADDR)
  ) _mac_decode (
      .clk  (rxc),
      .rst  (rst),
      .rxd  (rxd),
      .rx_dv(rx_dv),

      .sa(mac_sa),
      .busy(rgmii_rcv_busy),
      .crc_err(rgmii_rcv_crc_err),
      .arp_decode_valid(arp_decode_valid),
      .ip_valid(ip_valid)
  );

  reg ip_err;
  reg ip_done;
  reg [31:0] ip_sa;
  reg [31:0] ip_da;
  ip_decode ip_decoder (
      .clk  (rxc),
      .rst  (rst),
      .valid(ip_valid),
      .din  (rxd),

      .sa  (ip_sa),
      .da  (ip_da),
      .err (ip_err),
      .done(ip_done)
  );

  reg arp_err;
  reg arp_done;
  reg [47:0] arp_sha, arp_tha, arp_encode_tha;
  reg [31:0] arp_spa, arp_tpa, arp_encode_tpa;
  arp_decode arp_d (
      .clk  (rxc),
      .rst  (rst),
      .valid(arp_decode_valid),
      .din  (rxd),
      .sha  (arp_sha),
      .tha  (arp_tha),
      .spa  (arp_spa),
      .tpa  (arp_tpa),
      .err  (arp_err),
      .done (arp_done)
  );

`ifdef DEBUG
  reg uart_valid = '0;
  reg [7:0] uart_data = '0;
  uart _uart (
      .clk(clk),
      .rst(rst),
      .valid(uart_valid),
      .rx(uart_data),
      .rdy(),
      .tx(uart_tx)
  );
`endif

  always @(posedge clk) begin
    send_arp <= 0;
    if (arp_done && arp_tpa == LOC_IP_ADDR) begin
      send_arp <= 1;
      arp_encode_tpa <= arp_spa;
      arp_encode_tha <= arp_sha;
    end
  end

`endif

endmodule

