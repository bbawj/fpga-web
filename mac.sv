module mac ( 
    input wire clk,
    input wire rst,
    
    // PHY0 MII Interface
    output reg [3:0] phy_txd,
    output reg phy_txctl,
    output reg phy_txc,
    input wire [3:0] phy_rxd,
    input wire phy_rxctl,
    input wire phy_rxc
);

localparam [47:0] LOC_MAC_ADDR = 48'hDEADBEEFCAFE;
localparam [31:0] LOC_IP_ADDR = 32'h69696969;

`ifdef LOOPBACK
// RGMII requires specific setup and hold times.
// This is achieved with a 90 degree phase offset tx_clk relative to the
// sysclk used to load the tx lines
reg pll_locked;
clk_gen #(.CLKOP_FPHASE(2), .STEPS(1)) txc_phase90 (.clk_in(clk), .clk_out(phy_txc), .clk_locked(pll_locked));

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

  always @(posedge clk) begin
    phy_txd <= rxd_temp;
  end

  // RXDV RXER
  // 0    0   0 
  // 0    1   0
  // 1    0   0
  // 1    1   1
  assign phy_txctl = clk? rxdv : rxer;

`else

  assign phy_txc = clk;

reg mac_phy_txen = '0;
reg [3:0] mac_phy_txd = '0;
reg [47:0] mac_dest = '0;
reg send_next;
reg [15:0] ethertype = '0;
rgmii_tx #(.MAC_ADDR(LOC_MAC_ADDR)) tx(
  .clk(clk), .rst(rst), .mac_phy_txen(mac_phy_txen), .mac_phy_txd(mac_phy_txd),
  .mac_dest(mac_dest), .ethertype(ethertype),
  .send_next(send_next), .phy_txctl(phy_txctl), .phy_txd(phy_txd)
);

reg arp_encode_ovalid;
reg [3:0] arp_encode_dout;
reg [47:0] arp_encode_tha = '0;
reg [31:0] arp_encode_tpa = '0;
arp_encode #(.MAC_ADDR(LOC_MAC_ADDR), .IP_ADDR(LOC_IP_ADDR)) arp_e(
  .clk(clk),
  .rst(rst),
  .en(send_next),
  .tha(arp_encode_tha),
  .tpa(arp_encode_tpa),

  .ovalid(arp_encode_ovalid),
  .dout(arp_encode_dout)
  );

// RX path
reg arp_decode_valid;
reg ip_valid;
reg rgmii_rcv_busy;
reg rgmii_rcv_crc_err;
reg [47:0] mac_sa;
rgmii_rcv #(.MAC_ADDR(LOC_MAC_ADDR)) rcv (
  .clk(phy_rxc),
  .rst(rst),
  .mii_rxd(phy_rxd),
  .mii_rxctl(phy_rxctl),

  .sa(mac_sa),
  .busy(rgmii_rcv_busy),
  .crc_err(rgmii_rcv_crc_err),
  .arp_decode_valid(arp_decode_valid),
  .ip_valid(ip_valid)
  );

reg ip_err;
reg ip_dout_ready;
reg [3:0] ip_dout;
// ip_decode ip_decoder(.valid(ip_valid), .clk(clk), .din(phy_rxd), 
//   .err(ip_err), 
//   .dout_ready(ip_dout_ready),
//   .dout(ip_dout)
//   );

reg arp_err;
reg arp_done;
reg [47:0] arp_sha;
reg [31:0] arp_spa;
reg [31:0] arp_tpa;
arp_decode arp_d(
  .clk(phy_rxc),
  .rst(rst),
  .valid(arp_decode_valid),
  .din(phy_rxd),
  .sha(arp_sha),
  .spa(arp_spa),
  .tpa(arp_tpa),
  .err(arp_err),
  .done(arp_done)
  );

  reg arp_encode_handshake_complete = 0;
  always @* begin
    arp_encode_handshake_complete = send_next && arp_encode_ovalid;
  end

reg [47:0] q_arp_tha = '0;
reg [31:0] q_arp_tpa = '0;
typedef enum {IDLE, ARP_PENDING, ARP} TX_STATE;
TX_STATE tx_state = IDLE;
  always @(posedge clk or negedge clk) begin
    if (rst) begin
      tx_state <= IDLE;
    end else begin
      case (tx_state)
        IDLE: begin
          mac_phy_txen <= 0;
          mac_phy_txd <= '0;
          ethertype <= '0;
          if (arp_done) begin
            tx_state <= ARP_PENDING;
            arp_encode_tha <= arp_sha;
            arp_encode_tpa <= arp_spa;
            ethertype <= 16'h0806;
          end  
        end
        ARP_PENDING: begin
          if (~rgmii_rcv_busy) begin
            if (~rgmii_rcv_crc_err) begin
              tx_state <= ARP;
              mac_phy_txen <= 1;
            end
            else tx_state <= IDLE;
          end
        end
        ARP: begin
          if (arp_encode_handshake_complete) begin
            mac_phy_txd <= arp_encode_dout;
          end
          // TODO: done signal instead??
          else if (~arp_encode_ovalid) tx_state <= IDLE;
        end
      endcase
    end
  end

`endif

endmodule

