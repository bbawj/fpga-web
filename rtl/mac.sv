`default_nettype none
`include "utils.svh"

module mac #(
    parameter HTTP_ADDR_FILE = "",
    parameter HTTP_SIZE_FILE = ""
) (
    input wire clk,
    // for TXC
    input wire clk90,
    input wire rst,
    input tcp_echo_en,
    output wire led,
    output wire uart_tx,
    // Connect to external memory controller
    output reg mem_ctrl_rd_req,
    output reg [18:0] mem_ctrl_rd_ad,
    output reg [15:0] mem_ctrl_rd_size,
    input reg mem_ctrl_rd_valid,
    input reg mem_ctrl_rd_granted,
    input reg [31:0] mem_ctrl_rd_data,
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

  logic tcp_buff_rd_en, tcp_buff_rd_valid;
  logic [31:0] tcp_buff_rd_data;

  // Short circuit read to the incoming buffer.
  // If tcp_echo_en is asserted, there is no need to go to cache, just use 
  // incoming buffer payload.
  assign tcp_buff_rd_en = tcp_echo_en ? tcp_tx_payload_rd_en : http_req_payload;
  assign tcp_tx_payload_rd_data = tcp_echo_en ? tcp_buff_rd_data : mem_ctrl_rd_data;
  assign tcp_tx_payload_rd_valid = tcp_echo_en ? tcp_buff_rd_valid : mem_ctrl_rd_valid;

  ebr #(
      .USE_BLOCKRAM(0),
      .REGMODE("OUTREG"),
      .ADDR_WIDTH(11),
      .WR_WIDTH(8),
      .RD_WIDTH(32)
  ) tcp_incoming_buffer (
      .wr_clk(phy_rxc),
      .wr_en(tcp_decode_payload_valid),
      .wr_addr('0),
      .wr_data(tcp_decode_payload),
      .rd_clk(clk),
      .rd_en(tcp_buff_rd_en),
      .rd_addr('0),
      .rd_valid(tcp_buff_rd_valid),
      .rd_data(tcp_buff_rd_data)
  );

  assign mem_ctrl_rd_req = tcp_tx_payload_rd_en && !tcp_echo_en;

  reg send_arp, send_tcp;
  logic tcp_tx_payload_rd_en, tcp_tx_payload_rd_valid;
  tcp::packet_t tcp_tx_packet_pending;

  mac_tx #(
      .MY_MAC_ADDR(LOC_MAC_ADDR),
      .MY_IP_ADDR (LOC_IP_ADDR)
  ) tx (
      .clk(clk),
      .rst(rst),
      .i_mac_da(mac_sa),
      .tcp_echo_en(tcp_echo_en),
      .tcp_echo_checksum(tcp_decode_payload_checksum_sync),

      .send_arp(send_arp),
      .i_arp_encode_tha(arp_encode_tha),
      .i_arp_encode_tpa(arp_encode_tpa),

      .send_tcp(send_tcp),
      .pkt_external(tcp_tx_packet_pending),
      .tcp_payload_rd_valid(tcp_tx_payload_rd_valid),
      .tcp_payload_rd_data(tcp_tx_payload_rd_data),
      .tcp_payload_rd_en(tcp_tx_payload_rd_en),
      .tcp_payload_rd_ad(mem_ctrl_rd_ad),
      .tcp_payload_rd_size(mem_ctrl_rd_size),

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
  ) mac_decode_ (
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
  assign packet.payload_addr = '0;
  assign packet.window = '0;
  reg [7:0] tcp_decode_payload;
  reg tcp_decode_payload_valid, tcp_decode_done, tcp_decode_err;
  reg [15:0] tcp_decode_peer_port;
  reg [31:0] tcp_decode_sequence_num, tcp_decode_ack_num;
  reg [7:0] tcp_decode_flags;
  reg [15:0]
      tcp_decode_payload_size,
      tcp_decode_window,
      tcp_decode_payload_checksum,
      tcp_decode_payload_checksum_sync;
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
      .payload(tcp_decode_payload),
      .payload_valid(tcp_decode_payload_valid),
      .payload_size(tcp_decode_payload_size),
      .payload_checksum(tcp_decode_payload_checksum),

      .done(tcp_decode_done),
      // TODO: use this err
      .err (tcp_decode_err)
  );

  reg incoming_tcp = 0, incoming_tcp_q = 0;
  reg tcp_decode_done_stretched, tcp_decode_done_sync, tcp_decode_done_q1;
  always @(posedge clk) begin
    tcp_decode_done_q1 <= tcp_decode_done_sync;
    incoming_tcp <= !tcp_decode_done_q1 && tcp_decode_done_sync;
    incoming_tcp_q <= incoming_tcp;
  end
  pulse_stretcher tcpdecodedonestretcher (
      .clk(phy_rxc),
      .d  (tcp_decode_done),
      .q  (tcp_decode_done_stretched)
  );
  synchronizer sync2 (
      .clk(clk),
      .sig(tcp_decode_done_stretched),
      .q  (tcp_decode_done_sync)
  );
  async_fifo_2deep #(
      .DATA_WIDTH(152)
  ) sync_fifo (
      .wr_clk(phy_rxc),
      .wr_rst(rst),
      .wr_en(tcp_decode_done),
      .wr_data({
        ip_sa,
        tcp_decode_peer_port,
        tcp_decode_payload_size,
        tcp_decode_flags,
        tcp_decode_ack_num,
        tcp_decode_sequence_num,
        tcp_decode_payload_checksum
      }),
      .wr_full(),
      .rd_clk(clk),
      .rd_rst(rst),
      .rd_en(incoming_tcp),
      .rd_empty(),
      .rd_data({
        packet.peer_addr,
        packet.peer_port,
        packet.payload_size,
        packet.flags,
        packet.ack_num,
        packet.sequence_num,
        tcp_decode_payload_checksum_sync
      })
  );

  reg tcp_arb_rdy, tcp_payload_valid, tcp_payload_err;
  wire [31:0] tcp_tx_payload_rd_data;
  reg [18:0] to_send_payload_addr;
  reg [15:0] to_send_payload_size;
  reg arb_upper_granted;
  tcp_arbiter arb (
      .clk(clk),
      .rst(rst),
      .rxc(phy_rxc),
      .rdy(tcp_arb_rdy),
      // TODO: provide as parameter
      .tcp_echo_en(tcp_echo_en),

      .is_tx(outgoing_tcp),
      .upper_granted(arb_upper_granted),
      .to_send_payload_addr(to_send_payload_addr),
      .to_send_payload_size(to_send_payload_size),

      .is_rx(incoming_tcp_q),
      .rx_packet(packet),
      .tcp_payload_valid(tcp_payload_valid),
      .tcp_payload_err(tcp_payload_err),
      .send_tcp(send_tcp),
      .o_pkt_to_send(tcp_tx_packet_pending)
      // .tcp_payload_addr(),
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
    uart_valid <= mac_txen;
    uart_data  <= mac_txd;
  end
  uart #(
      .BUF_USE_BLOCKRAM(1),
      .DEPTH(1028)
  ) _uart (
      .clk(clk),
      .rst(rst),
      .valid(uart_valid),
      .rx(uart_data),
      .rdy(),
      .tx(uart_tx)
  );
`endif

  reg arp_done_strectched, arp_done_sync, arp_done_prev;
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
  always @(posedge clk) begin : generate_send_pulse
    // FIXME: send_arp should be passed to a FIFO similar to send_tcp in case
    // send_arp is asserted when TX path is already busy
    send_arp <= '0;
    arp_done_prev <= arp_done_sync;
    if (!arp_done_prev && arp_done_sync && arp_tpa == LOC_IP_ADDR) begin
      arp_encode_tpa <= arp_spa;
      arp_encode_tha <= arp_sha;
      send_arp <= 1;
    end
  end

  // Handles outgoing_tcp
  // Checks for HTTP decode OK, waits for SM approval, fire off outgoing_tcp.
  // SM responds a few cycles after HTTP decode validates.
  reg outgoing_tcp = 0;
  logic [1:0] http_state = 0;
  always @(posedge clk) begin
    case (http_state)
      0: begin
        outgoing_tcp <= 1'b0;
        if (http_res_valid) begin
          // an error in http decoding always sends the 404 page hard coded at
          // endpoint 0.
          to_send_payload_addr <= http_res_err ? 0 : http_payload_addr;
          to_send_payload_size <= http_res_err ? 'h294 : http_payload_size;
          outgoing_tcp <= 1;
          http_state <= 1;
        end
      end
      1: begin
        if (arb_upper_granted) begin
          http_state   <= 0;
          outgoing_tcp <= 0;
        end
      end
      default: begin
        http_state   <= 0;
        outgoing_tcp <= 0;
      end
    endcase
  end


  reg http_res_valid, http_res_err, http_req_payload;
  reg [18:0] http_payload_addr;
  reg [15:0] http_payload_size;
  http_decode #(
      .HTTP_ADDR_FILE(HTTP_ADDR_FILE),
      .HTTP_SIZE_FILE(HTTP_SIZE_FILE)
  ) http_dec (
      // FIXME: decode payload is off from phy_rxc
      .clk(clk),
      .rst(rst),
      .tcp_payload_valid(tcp_payload_valid && !tcp_payload_err),
      .i_payload_valid(tcp_buff_rd_valid),
      .i_payload_data(tcp_buff_rd_data),
      .payload_rd_en(http_req_payload),

      .res_valid(http_res_valid),
      .res_err(http_res_err),
      .res_payload_size(http_payload_size),
      .res_payload_addr(http_payload_addr)
  );

`endif

endmodule

