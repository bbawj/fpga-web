module mac_tx #(
    parameter [47:0] MY_MAC_ADDR = 0,
    parameter [31:0] MY_IP_ADDR  = 0,
    parameter [15:0] MY_TCP_PORT = 0
) (
    input clk,
    input sdram_clk,
    input rst,
    input reg [47:0] i_mac_da,

    input send_arp,
    input reg [47:0] i_arp_encode_tha,
    input reg [31:0] i_arp_encode_tpa,

    input send_tcp,
    input tcp::packet_t pkt,
    // RD_EN asserted to get data from SDRAM onto tcp_payload_data
    input reg tcp_payload_rd_valid,
    input reg [31:0] tcp_payload_rd_data,
    output reg [31:0] tcp_payload_rd_en,
    output reg [18:0] tcp_payload_rd_ad,

    output reg [3:0] phy_txd,
    output reg phy_txctl
);

  // Pull payload data into temp buffer to free up SDRAM activity
  typedef enum {
    BUFF_STATE_IDLE,
    BUFF_STATE_START,
    BUFF_STATE_MOVE_TO_LOCAL,
    BUFF_STATE_DONE
  } payload_buff_state_t;
  payload_buff_state_t payload_buff_state = BUFF_STATE_IDLE;
  reg tcp_outgoing_wr_en, tcp_outgoing_rd_en = 0;
  reg [31:0] tcp_outgoing_wr_data = 0;
  reg [ 7:0] tcp_outgoing_rd_data;
  ebr #(
      .SIZE(tcp::MSS),
      .RD_WIDTH(8),
      .WR_WIDTH(32)
  ) tcp_outgoing_buffer (
      .wr_clk (sdram_clk),
      .wr_en  (tcp_outgoing_wr_en),
      .wr_addr('0),
      .wr_data(tcp_outgoing_wr_data),
      .rd_clk (clk),
      .rd_en  (tcp_outgoing_rd_en),
      .rd_addr('0),
      .rd_data(tcp_outgoing_rd_data)
  );
  reg tcp_outgoing_buffer_start_0, tcp_outgoing_buffer_start_1, tcp_outgoing_buffer_start_rising;
  reg [15:0] pkt_payload_size;
  synchronizer #(
      .INPUT_WIDTH(17)
  ) _sync (
      .clk(sdram_clk),
      .sig({send_tcp, pkt.payload_size}),
      .q  ({tcp_outgoing_buffer_start_0, pkt_payload_size})
  );
  reg [15:0] payload_counter = '0;
  always @(posedge sdram_clk) begin
    tcp_outgoing_buffer_start_1 <= tcp_outgoing_buffer_start_0;
    tcp_outgoing_buffer_start_rising <= ~tcp_outgoing_buffer_start_1 & tcp_outgoing_buffer_start_0;

    case (payload_buff_state)
      BUFF_STATE_IDLE: begin
        payload_counter <= '0;
        tcp_payload_rd_en <= '0;
        tcp_outgoing_wr_en <= '0;
        // Assume pkt.payload_size > 0
        if (tcp_outgoing_buffer_start_rising) begin
          tcp_payload_rd_en <= 1'b1;
          tcp_payload_rd_ad <= pkt.payload_addr;
          payload_buff_state <= BUFF_STATE_START;
          payload_counter <= pkt_payload_size;
        end
      end
      BUFF_STATE_START: begin
        if (tcp_payload_rd_valid) begin
          tcp_outgoing_wr_en   <= 1'b1;
          tcp_outgoing_wr_data <= tcp_payload_rd_data;
          payload_buff_state   <= BUFF_STATE_MOVE_TO_LOCAL;
        end
      end
      BUFF_STATE_MOVE_TO_LOCAL: begin
        tcp_outgoing_wr_en <= 1'b1;
        tcp_outgoing_wr_data <= tcp_payload_rd_data;
        payload_counter <= payload_counter - 1;
        if (payload_counter == 1) begin
          tcp_outgoing_wr_en <= '0;
          payload_buff_state <= BUFF_STATE_IDLE;
        end
      end
      default: begin
        payload_buff_state <= BUFF_STATE_IDLE;
      end
    endcase
  end


  reg mac_encode_en = '0;
  reg [7:0] mac_payload = '0;
  reg [47:0] mac_dest = '0;
  reg mac_send_payload;
  reg [15:0] ethertype = '0;
  mac_encode #(
      .MAC_ADDR(MY_MAC_ADDR)
  ) _mac_encode (
      .clk(clk),
      .rst(rst),
      .en(mac_encode_en),
      .mac_payload(mac_payload),
      .mac_dest(mac_dest),
      .ethertype(ethertype),
      .send_next(mac_send_payload),
      .phy_txctl(phy_txctl),
      .phy_txd(phy_txd)
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

  reg ip_encode_en, ip_encode_done;
  reg [31:0] ip_encode_sa;
  reg [31:0] ip_encode_da;
  reg [15:0] ip_encode_len;
  reg [ 7:0] ip_encode_dout;
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

  reg tcp_encode_en, tcp_encode_done;
  reg [15:0] tcp_encode_source_port;
  reg [15:0] tcp_encode_dest_port;
  reg [31:0] tcp_encode_sequence_num;
  reg [31:0] tcp_encode_ack_num;
  reg [ 7:0] tcp_encode_flags;
  reg [15:0] tcp_encode_window;
  reg [15:0] tcp_encode_initial_checksum;
  reg [ 7:0] tcp_encode_dout;
  tcp_encode tcp_enc (
      .clk(clk),
      .rst(rst),
      .en(tcp_encode_en),
      .ip_sa(ip_encode_sa),
      .ip_da(ip_encode_da),
      .ip_packet_len(ip_encode_len),

      .source_port(tcp_encode_source_port),
      .dest_port(tcp_encode_dest_port),
      .sequence_num(tcp_encode_sequence_num),
      .ack_num(tcp_encode_ack_num),
      .flags(tcp_encode_flags),
      .window(tcp_encode_window),
      .initial_checksum(),
      .done(tcp_encode_done),
      .dout(tcp_encode_dout)
  );
  typedef enum {
    IDLE,
    ARP,
    IP,
    TCP,
    PAYLOAD
  } tx_state_t;
  tx_state_t tx_state = IDLE;
  reg [15:0] payload_counter_2;
  always @(posedge clk) begin
    if (rst) begin
      tx_state <= IDLE;
    end else begin
      case (tx_state)
        IDLE: begin
          mac_encode_en <= '0;
          arp_encode_en <= '0;
          ip_encode_en <= '0;
          tcp_encode_en <= '0;
          payload_counter_2 <= '0;
          ethertype <= '0;
          if (send_arp) begin
            tx_state <= ARP;
            mac_encode_en <= 1;
            mac_dest <= i_mac_da;
            ethertype <= 16'h0806;
          end else if (send_tcp) begin
            tx_state <= IP;
            payload_counter_2 <= pkt.payload_size;
            mac_encode_en <= 1;
            mac_dest <= i_mac_da;
            ethertype <= 16'h0800;
          end
        end
        ARP: begin
          if (mac_send_payload) begin
            arp_encode_en  <= 1'b1;
            arp_encode_tha <= i_arp_encode_tha;
            arp_encode_tpa <= i_arp_encode_tpa;
          end
          if (arp_encode_done) tx_state <= IDLE;
        end
        IP: begin
          if (mac_send_payload) begin
            ip_encode_en  <= 1'b1;
            ip_encode_len <= pkt.payload_size + 'd20;
            ip_encode_sa  <= MY_IP_ADDR;
            ip_encode_da  <= pkt.peer_addr;
          end
          if (ip_encode_done) begin
            tcp_encode_en <= 1'b1;
            tcp_encode_source_port <= MY_TCP_PORT;
            tcp_encode_dest_port <= pkt.peer_port;
            tcp_encode_sequence_num <= pkt.sequence_num;
            tcp_encode_ack_num <= pkt.ack_num;
            tcp_encode_flags <= pkt.flags;
            tcp_encode_window <= pkt.window;

            tx_state <= TCP;
          end
        end
        TCP: begin
          if (tcp_encode_done) begin
            if (payload_counter_2 > 0) begin
              tx_state <= PAYLOAD;
              tcp_outgoing_rd_en <= 1'b1;
            end else tx_state <= IDLE;
          end
        end
        PAYLOAD: begin
          payload_counter_2 <= payload_counter_2 - 1;
          if (payload_counter_2 == 1) tx_state <= IDLE;
        end
      endcase
    end
  end

  always @* begin
    mac_payload = '0;
    if (mac_send_payload) begin
      case (tx_state)
        ARP: begin
          mac_payload = arp_encode_dout;
        end
        IP: begin
          mac_payload = ip_encode_dout;
        end
        TCP: begin
          mac_payload = tcp_encode_dout;
        end
        PAYLOAD: begin
          mac_payload = tcp_outgoing_rd_data;
        end
      endcase
    end
  end
endmodule
