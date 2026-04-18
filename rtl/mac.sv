`default_nettype none
`include "utils.svh"

module mac (
    input wire clk,
    // for TXC
    input wire clk90,
    input wire rst,
    input tcp_echo_en,
    output wire led,
    output wire uart_tx,

    // PHY0 MII Interface
    output wire phy_txc,
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

  reg mac_txen;
  reg [7:0] mac_txd;
  rgmii_tx _rgmii_tx (
      .clk(clk),
      .clk90(clk90),
      .rst(rst),
      .mac_phy_txen(mac_txen),
      .mac_phy_txd(mac_txd),
      .phy_txc(phy_txc),
      .phy_txctl(phy_txctl),
      .phy_txd(phy_txd)
  );

  reg send_arp, send_tcp, tcp_empty;
  reg pkt_rd_en, tcp_tx_payload_rd_en, tcp_tx_payload_rd_valid;
  reg [18:0] tcp_tx_payload_rd_ad;
  tcp::packet_t tcp_tx_packet;
  tcp::packet_t tcp_tx_packet_pending;

  mac_tx #(
      .MY_MAC_ADDR(LOC_MAC_ADDR),
      .MY_IP_ADDR (LOC_IP_ADDR)
  ) tx (
      .clk(clk),
      .sdram_clk(clk),
      .rst(rst),
      .i_mac_da(mac_sa),

      .send_arp(send_arp),
      .i_arp_encode_tha(arp_encode_tha),
      .i_arp_encode_tpa(arp_encode_tpa),

      .tcp_empty(tcp_empty),
      .pkt_rd_en(pkt_rd_en),
      .pkt_external(tcp_tx_packet),
      .tcp_payload_rd_valid(tcp_tx_payload_rd_valid),
      .tcp_payload_rd_data(tcp_tx_payload_rd_data),
      .tcp_payload_rd_en(tcp_tx_payload_rd_en),
      .tcp_payload_rd_ad(tcp_tx_payload_rd_ad),

      .mac_txd (mac_txd),
      .mac_txen(mac_txen)
  );
  // RX path
  reg [7:0] rxd;
  wire rx_dv, rx_er;
  rgmii_rcv rcv (
      .rst(rst),
      .mii_rxc(phy_rxc),
      .mii_rxd(phy_rxd),
      .mii_rxctl(phy_rxctl),

      // .rxc  (rxc),
      .rxd  (rxd),
      .rx_dv(rx_dv),
      .rx_er(rx_er)
  );


  reg [7:0] rxd_delayed;
  reg rx_dv_delayed;
  delay #(
      .WIDTH(9),
      .DEPTH(4)
  ) _delay (
      .clk(phy_rxc),
      .rst(rst),
      .data_in({rxd, rx_dv}),
      .data_out({rxd_delayed, rx_dv_delayed})
  );
  reg arp_decode_valid;
  reg ip_valid;
  reg other_err;
  reg rgmii_rcv_busy;
  reg rgmii_rcv_crc_err;
  // NOTE: since the use case is behind a reverse proxy, there is only ever
  // 1 MAC_SA we will receive, no need for fancy mac address storage
  reg [47:0] mac_sa;
  mac_decode #(
      .MAC_ADDR(LOC_MAC_ADDR)
  ) _mac_decode (
      .clk(phy_rxc),
      .rst(rst),
      .rxd_realtime(rxd),
      .rx_dv_realtime(rx_dv),
      .rxd(rxd_delayed),
      .rx_dv(rx_dv_delayed),

      .sa(mac_sa),
      .busy(rgmii_rcv_busy),
      .crc_err(rgmii_rcv_crc_err),
      .other_err(other_err),
      .arp_decode_valid(arp_decode_valid),
      .ip_valid(ip_valid)
  );

  reg ip_err;
  reg ip_done;
  reg [3:0] ip_ihl;
  // reg [31:0] ip_sa;
  reg [31:0] ip_da, ip_sa;
  reg [15:0] ip_payload_size;
  ip_decode ip_decoder (
      .clk(phy_rxc),
      .rst(rst),
      .valid(ip_valid),
      .din(rxd_delayed),
      .packet_size(ip_payload_size),
      .sa(ip_sa),
      .da(ip_da),
      .ihl(ip_ihl),
      .err(ip_err),
      .done(ip_done)
  );

  tcp::packet_t packet;
  reg [7:0] tcp_payload;
  reg tcp_decode_payload_valid, tcp_decode_done, tcp_decode_err;
  reg [15:0] tcp_decode_peer_port;
  reg [31:0] tcp_decode_sequence_num, tcp_decode_ack_num;
  reg [7:0] tcp_decode_flags;
  reg [15:0] tcp_decode_payload_size, tcp_decode_window, tcp_decode_payload_checksum;
  tcp_decode tcp_dec (
      .clk(phy_rxc),
      .rst(rst),
      .valid(ip_done),
      .din(rxd_delayed),
      .ip_sa(ip_sa),
      .ip_da(ip_da),
      .ip_ihl(ip_ihl),
      .ip_payload_size(ip_payload_size),

      .source_port(tcp_decode_peer_port),
      .dest_port(),
      .sequence_num(tcp_decode_sequence_num),
      .flags(tcp_decode_flags),
      .ack_num(tcp_decode_ack_num),
      .window(tcp_decode_window),
      .payload(tcp_payload),
      .payload_valid(tcp_decode_payload_valid),
      .payload_size(tcp_decode_payload_size),
      .payload_checksum(tcp_decode_payload_checksum),

      .done(tcp_decode_done),
      // TODO: use this err
      .err (tcp_decode_err)
  );

  reg incoming_tcp;
  always @(posedge clk) begin
    incoming_tcp <= tcp_decode_done;
    if (tcp_decode_done) begin
      packet.peer_addr <= ip_sa;
      packet.peer_port <= tcp_decode_peer_port;
      packet.payload_addr <= '0;
      packet.payload_size <= tcp_decode_payload_size;
      packet.flags <= tcp_decode_flags;
      packet.ack_num <= tcp_decode_ack_num;
      packet.sequence_num <= tcp_decode_sequence_num;
      packet.checksum <= tcp_decode_payload_checksum;
    end
  end

  reg tcp_arb_rdy, tcp_payload_valid;
  reg [31:0] tcp_tx_payload_rd_data;
  tcp_arbiter arb (
      .clk(clk),
      .rst(rst),
      .rxc(phy_rxc),
      .tcp_rx_payload_valid(tcp_decode_payload_valid),
      .tcp_rx_payload_data(tcp_payload),
      .tcp_rx_payload_rd_en(tcp_tx_payload_rd_en),
      .tcp_rx_payload_rd_valid(tcp_tx_payload_rd_valid),
      .tcp_rx_payload_rd_data(tcp_tx_payload_rd_data),
      .rdy(tcp_arb_rdy),
      .tcp_echo_en(tcp_echo_en),
      .is_tx(),
      .to_send_peer_addr(),
      .to_send_peer_port(),
      .to_send_payload_addr(),
      .to_send_payload_size(),
      .is_rx(incoming_tcp),
      .packet(packet),

      .tcp_payload_valid(tcp_payload_valid),
      .send_tcp(send_tcp),
      .o_pkt_to_send(tcp_tx_packet_pending)
      // .tcp_payload_addr(),
  );

  // Handle up to 2 in flight outgoing packets since we do not implement any
  // delayed ACK, every received packet will have 1 ACK reply and if the
  // response from our application is too quick there needs to be a buffer
  fifo #(
      .DATA_WIDTH(187),
      .DEPTH(2)
  ) outgoing_pkt_queue (
      .clk  (clk),
      .rst  (rst),
      .wr_en(send_tcp),
      .din  (tcp_tx_packet_pending),
      .full (),
      .rd_en(pkt_rd_en),
      .dout (tcp_tx_packet),
      .empty(tcp_empty),
      .count()
  );
  reg arp_err;
  reg arp_done;
  reg [47:0] arp_sha, arp_tha, arp_encode_tha;
  reg [31:0] arp_spa, arp_tpa, arp_encode_tpa;
  arp_decode arp_d (
      .clk  (phy_rxc),
      .rst  (rst),
      .valid(arp_decode_valid),
      .din  (rxd_delayed),
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
  always @(posedge clk) begin
    uart_valid <= rx_dv_delayed;
    uart_data  <= rxd_delayed;
  end
  uart _uart (
      .clk(clk),
      .rst(rst),
      .valid(uart_valid),
      .rx(uart_data),
      .rdy(),
      .tx(uart_tx)
  );
`endif

  reg arp_done_strectched;
  pulse_stretcher stretcher (
      .clk(phy_rxc),
      .d  (arp_done),
      .q  (arp_done_strectched)
  );
  synchronizer sync (
      .clk(clk),
      .sig(arp_done),
      .q  (arp_done_sync)
  );
  reg arp_done_sync;
  reg arp_done_prev;
  always @(posedge clk) begin : generate_send_pulse
    send_arp <= '0;
    arp_done_prev <= arp_done_sync;
    if (!arp_done_prev && arp_done_sync && arp_tpa == LOC_IP_ADDR) begin
      arp_encode_tpa <= arp_spa;
      arp_encode_tha <= arp_sha;
      send_arp <= 1;
    end
  end

`endif

endmodule

