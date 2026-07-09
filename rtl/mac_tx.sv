`default_nettype none

module mac_tx #(
    parameter [47:0] MY_MAC_ADDR = 0,
    parameter [31:0] MY_IP_ADDR  = 0
) (
    input wire clk,
    input wire rst,
    input wire tcp_echo_en,
    input wire [15:0] tcp_echo_checksum,
    input reg [47:0] i_mac_da,

    input wire send_arp,
    input reg [47:0] i_arp_encode_tha,
    input reg [31:0] i_arp_encode_tpa,

    input wire send_tcp,
    input tcp::packet_t pkt_external,
    // RD_EN asserted to get data from SDRAM onto tcp_payload_data
    input reg tcp_payload_rd_valid,
    input reg [31:0] tcp_payload_rd_data,
    output reg tcp_payload_rd_en,
    output reg [18:0] tcp_payload_rd_ad,
    output reg [15:0] tcp_payload_rd_size,

    output reg [3:0] o_payload_buff_state,
    output reg [2:0] o_misc,
    output reg [7:0] mac_txd,
    output reg mac_txen
);
  typedef enum {
    IDLE,
    ARP,
    PAYLOAD_LOADING,
    IP_PKT_WAIT,
    IP,
    TCP,
    PAYLOAD
  } tx_state_t;
  tx_state_t tx_state = IDLE;

  // FIFO has 1 cycle latency between pkt_rd_en and data being available for
  // sampling so we wait for falling edge here.
  reg pkt_rd_en = 0, pkt_rd_en_q1 = 0;
  reg [18:0] pkt_payload_addr = 0;
  reg [15:0] pkt_payload_size = 0;

  reg ip_encode_en, ip_encode_done;
  reg [31:0] ip_encode_sa = MY_IP_ADDR;
  reg [31:0] ip_encode_da;
  reg [15:0] ip_encode_len;
  reg [ 7:0] ip_encode_dout;

  reg tcp_encode_en, tcp_encode_done, tcp_encode_done_pre, tcp_encode_done_pre_3;
  reg [15:0] tcp_encode_dest_port;
  reg [31:0] tcp_encode_sequence_num;
  reg [31:0] tcp_encode_ack_num;
  reg [7:0] tcp_encode_flags;
  reg [15:0] tcp_encode_window;
  reg [15:0] tcp_encode_len;
  reg [7:0] tcp_encode_dout;

  tcp::packet_t pkt;
  reg tcp_outgoing_buffer_start = 0;
  wire pkt_rd_falling;
  assign pkt_rd_falling = ~pkt_rd_en && pkt_rd_en_q1;
  always @(posedge clk) begin
    pkt_rd_en_q1 <= pkt_rd_en;
    tcp_outgoing_buffer_start <= pkt_rd_falling;
    if (pkt_rd_falling) begin
      pkt_payload_addr <= pkt.payload_addr;
      pkt_payload_size <= pkt.payload_size;
      ip_encode_da <= pkt.peer_addr;
      tcp_encode_dest_port <= pkt.peer_port;
      tcp_encode_sequence_num <= pkt.sequence_num;
      tcp_encode_ack_num <= pkt.ack_num;
      tcp_encode_flags <= pkt.flags;
      tcp_encode_window <= pkt.window;
    end
  end

  always @(posedge clk) begin
    ip_encode_len  <= pkt_payload_size + 'd40;
    tcp_encode_len <= pkt_payload_size + 'd20;
  end

  reg tcp_empty, send_tcp_q;
  always @(posedge clk) begin
    send_tcp_q <= send_tcp;
  end
  fifo #(
      .DATA_WIDTH(171),
      .DEPTH(64)
  ) outgoing_pkt_queue (
      .clk  (clk),
      .rst  (rst),
      .wr_en(send_tcp),
      .din  (pkt_external),
      .full (),
      .rd_en(pkt_rd_en),
      .dout (pkt),
      .valid(),
      .empty(tcp_empty),
      .count()
  );

  reg [15:0] tcp_payload_checksum;
  reg [7:0] tcp_outgoing_rd_data;
  reg tcp_outgoing_wr_en;
  reg [10:0] tcp_outgoing_wr_ptr;
  reg [31:0] tcp_outgoing_wr_data;
  reg tcp_outgoing_rdy;
  mac_tx_buff mac_tx_buff_ (
      .clk(clk),
      .rst(rst),
      .tcp_outgoing_buffer_start(tcp_outgoing_buffer_start),
      .i_pkt_payload_size(pkt_payload_size),
      .i_pkt_payload_addr(pkt_payload_addr),
      .tcp_payload_rd_valid(tcp_payload_rd_valid),
      .tcp_payload_rd_data(tcp_payload_rd_data),
      .tcp_payload_rd_en(tcp_payload_rd_en),
      .tcp_payload_rd_ad(tcp_payload_rd_ad),
      .tcp_payload_rd_size(tcp_payload_rd_size),
      .tcp_payload_checksum(tcp_payload_checksum),
      .tcp_outgoing_rdy(tcp_outgoing_rdy),
      .tcp_outgoing_wr_en(tcp_outgoing_wr_en),
      .tcp_outgoing_wr_ptr(tcp_outgoing_wr_ptr),
      .tcp_outgoing_wr_data(tcp_outgoing_wr_data),
      .o_payload_buff_state(o_payload_buff_state)
  );

  ebr #(
      .USE_BLOCKRAM(1),
      .REGMODE("OUTREG"),
      .ADDR_WIDTH(11),
      .RD_WIDTH(8),
      .WR_WIDTH(32)
  ) tcp_outgoing_buffer (
      .wr_clk(clk),
      .wr_en(tcp_outgoing_wr_en),
      .wr_addr(tcp_outgoing_wr_ptr),
      .wr_data(tcp_outgoing_wr_data),
      .rd_clk(clk),
      .rd_en(tcp_encode_done_pre | tcp_encode_done | tx_state == PAYLOAD),
      .rd_addr('0),
      .rd_valid(),
      .rd_data(tcp_outgoing_rd_data)
  );

  reg mac_encode_en, mac_encode_ready;
  reg [7:0] mac_payload;
  reg [47:0] mac_dest = '0;
  reg mac_send_payload;
  reg [15:0] ethertype = '0;
  mac_encode #(
      .MAC_ADDR(MY_MAC_ADDR)
  ) mac_enc (
      .clk(clk),
      .rst(rst),
      .en(mac_encode_en),
      .ready(mac_encode_ready),
      .mac_payload(mac_payload),
      .i_mac_dest(mac_dest),
      .i_ethertype(ethertype),
      .send_next(mac_send_payload),
      .mac_txen(mac_txen),
      .mac_txd(mac_txd)
  );

  reg arp_encode_en;
  reg arp_encode_done;
  reg [7:0] arp_encode_dout;
  reg [47:0] arp_encode_tha;
  reg [31:0] arp_encode_tpa;
  arp_encode #(
      .MAC_ADDR(MY_MAC_ADDR),
      .IP_ADDR (MY_IP_ADDR)
  ) arp_e (
      .clk(clk),
      .rst(rst),
      .en (arp_encode_en),
      .tha(arp_encode_tha),
      .tpa(arp_encode_tpa),

      .done(arp_encode_done),
      .dout(arp_encode_dout)
  );

  ip_encode ip_enc (
      .clk (clk),
      .rst (rst),
      .en  (ip_encode_en),
      .sa  (ip_encode_sa),
      .da  (ip_encode_da),
      .len (ip_encode_len),
      .done(ip_encode_done),
      .dout(ip_encode_dout)
  );

  tcp_encode tcp_enc (
      .clk(clk),
      .rst(rst),
      .en(tcp_encode_en),
      .i_ip_sa(ip_encode_sa),
      .i_ip_da(ip_encode_da),
      .i_tcp_len(tcp_encode_len),

      .i_dest_port(tcp_encode_dest_port),
      .i_sequence_num(tcp_encode_sequence_num),
      .i_ack_num(tcp_encode_ack_num),
      .i_flags(tcp_encode_flags),
      .i_window(tcp_encode_window),
      .initial_checksum(tcp_echo_en ? tcp_echo_checksum : tcp_payload_checksum),
      // ebr has 1 cycle read latency so "pre_done_1" is required to meet
      // timing and ensure payload from ebr is ready
      .pre_done_3(tcp_encode_done_pre_3),
      .pre_done_2(tcp_encode_done_pre),
      .pre_done_1(tcp_encode_done),
      .done(),
      .dout(tcp_encode_dout)
  );
  reg [15:0] payload_counter_2;
  always @(posedge clk) begin
    if (rst) begin
      tx_state <= IDLE;
      pkt_rd_en <= 0;
      mac_encode_en <= '0;
    end else begin
      case (tx_state)
        IDLE: begin
          mac_encode_en <= '0;
          payload_counter_2 <= '0;
          ethertype <= '0;
          if (mac_encode_ready && send_arp) begin
            tx_state <= ARP;
            arp_encode_tha <= i_arp_encode_tha;
            arp_encode_tpa <= i_arp_encode_tpa;
            mac_encode_en <= 1;
            mac_dest <= i_mac_da;
            ethertype <= 16'h0806;
          end else if (mac_encode_ready && !tcp_empty) begin
            tx_state  <= PAYLOAD_LOADING;
            pkt_rd_en <= 1;
            mac_dest  <= i_mac_da;
            ethertype <= 16'h0800;
          end
        end
        ARP: begin
          if (arp_encode_done) tx_state <= IDLE;
        end
        PAYLOAD_LOADING: begin
          pkt_rd_en <= 0;
          if (tcp_outgoing_rdy) begin
            tx_state <= IP_PKT_WAIT;
            mac_encode_en <= 1;
          end
        end
        IP_PKT_WAIT: begin
          tx_state <= IP;
        end
        IP: begin
          if (ip_encode_done) begin
            tx_state <= TCP;
            payload_counter_2 <= pkt_payload_size;
          end
        end
        TCP: begin
          if (tcp_encode_done) begin
            if (payload_counter_2 > 0) begin
              tx_state <= PAYLOAD;
            end else begin
              tx_state <= IDLE;
              mac_encode_en <= '0;
            end
          end
        end
        PAYLOAD: begin
          payload_counter_2 <= payload_counter_2 - 1;
          if (payload_counter_2 == 1) begin
            tx_state <= IDLE;
            mac_encode_en <= '0;
          end
        end
      endcase
    end
  end

  always @(posedge clk) begin
    ip_encode_en  <= mac_send_payload && tx_state == IP;
    tcp_encode_en <= mac_send_payload && (tx_state == TCP | ip_encode_done);
    arp_encode_en <= mac_send_payload && tx_state == ARP;
    // case (tx_state)
    //   ARP: arp_encode_en <= mac_send_payload;
    //   IP:  ip_encode_en <= mac_send_payload;
    //   TCP: tcp_encode_en <= mac_send_payload;
    // endcase
  end

  always @(posedge clk) begin
    case (tx_state)
      ARP: begin
        mac_payload <= arp_encode_dout;
      end
      IP: begin
        mac_payload <= ip_encode_dout;
      end
      TCP: begin
        mac_payload <= tcp_encode_dout;
      end
      PAYLOAD: begin
        mac_payload <= tcp_outgoing_rd_data;
      end
      default: mac_payload <= '0;
    endcase
  end
endmodule
