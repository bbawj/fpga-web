module mac_tx #(
    parameter [47:0] MY_MAC_ADDR = 0,
    parameter [31:0] MY_IP_ADDR  = 0
) (
    input clk,
    input sdram_clk,
    input rst,
    input reg [47:0] i_mac_da,

    input send_arp,
    input reg [47:0] i_arp_encode_tha,
    input reg [31:0] i_arp_encode_tpa,

    input tcp_empty,
    output reg pkt_rd_en,
    input tcp::packet_t pkt_external,
    // RD_EN asserted to get data from SDRAM onto tcp_payload_data
    input reg tcp_payload_rd_valid,
    input reg [31:0] tcp_payload_rd_data,
    output reg tcp_payload_rd_en,
    output reg [18:0] tcp_payload_rd_ad,

    output reg [7:0] mac_txd,
    output reg mac_txen
);

  // FIFO has 1 cycle latency between pkt_rd_en and data being available for
  // sampling so we wait for falling edge here.
  reg pkt_rd_en_q1;
  logic [18:0] pkt_payload_addr;
  logic [15:0] pkt_payload_size;

  always @(posedge clk) begin
    pkt_rd_en_q1 <= pkt_rd_en;
    if (~pkt_rd_en && pkt_rd_en_q1) begin
      pkt_payload_addr <= pkt_external.payload_addr;
      pkt_payload_size <= pkt_external.payload_size;
      ip_encode_len <= pkt_external.payload_size + 'd40;
      ip_encode_da <= pkt_external.peer_addr;
      tcp_encode_len <= pkt_external.payload_size + 'd20;
      tcp_encode_dest_port <= pkt_external.peer_port;
      tcp_encode_sequence_num <= pkt_external.sequence_num;
      tcp_encode_ack_num <= pkt_external.ack_num;
      tcp_encode_flags <= pkt_external.flags;
      tcp_encode_window <= pkt_external.window;
      tcp_encode_initial_checksum <= pkt_external.checksum;
    end
  end

  // Pull payload data into temp buffer to free up SDRAM activity
  typedef enum {
    BUFF_STATE_IDLE,
    BUFF_STATE_START,
    BUFF_STATE_MOVE_TO_LOCAL,
    BUFF_STATE_DONE
  } payload_buff_state_t;
  payload_buff_state_t payload_buff_state = BUFF_STATE_IDLE;
  reg tcp_outgoing_wr_en = 0;
  reg [31:0] tcp_outgoing_wr_data = 0;
  reg [7:0] tcp_outgoing_rd_data;
  ebr #(
      .SIZE(tcp::MSS),
      .RD_WIDTH(8),
      .WR_WIDTH(32)
  ) tcp_outgoing_buffer (
      .wr_clk(sdram_clk),
      .wr_en(tcp_outgoing_wr_en),
      .wr_addr('0),
      .wr_data(tcp_outgoing_wr_data),
      .rd_clk(clk),
      .rd_en(tcp_encode_done | tx_state == PAYLOAD),
      .rd_addr('0),
      .rd_valid(),
      .rd_data(tcp_outgoing_rd_data)
  );
  reg tcp_outgoing_buffer_start_0, tcp_outgoing_buffer_start_1, tcp_outgoing_buffer_start_rising;
  synchronizer #(
      .INPUT_WIDTH(1),
      .SYNC_WIDTH (3)
  ) _sync (
      .clk(sdram_clk),
      .sig(tx_state == IP),
      .q  (tcp_outgoing_buffer_start_0)
  );
  reg [15:0] payload_counter = '0;

  always @(posedge sdram_clk) begin
    tcp_outgoing_buffer_start_1 <= tcp_outgoing_buffer_start_0;
    tcp_outgoing_buffer_start_rising <= ~tcp_outgoing_buffer_start_1 & tcp_outgoing_buffer_start_0;
    tcp_outgoing_wr_data <= tcp_payload_rd_data;
    case (payload_buff_state)
      BUFF_STATE_IDLE: begin
        payload_counter <= '0;
        tcp_payload_rd_en <= '0;
        tcp_outgoing_wr_en <= '0;
        // Assume pkt.payload_size > 0
        if (tcp_outgoing_buffer_start_rising && pkt_payload_size > 0) begin
          tcp_payload_rd_en <= 1'b1;
          tcp_payload_rd_ad <= pkt_payload_addr;
          payload_buff_state <= BUFF_STATE_START;
          // RD_WIDTH is 32 whereas WR_WIDTH is 8
          payload_counter <= pkt_payload_size >> 2;
        end
      end
      BUFF_STATE_START: begin
        if (tcp_payload_rd_valid) begin
          tcp_outgoing_wr_en <= 1'b1;
          payload_buff_state <= BUFF_STATE_MOVE_TO_LOCAL;
        end
      end
      BUFF_STATE_MOVE_TO_LOCAL: begin
        tcp_outgoing_wr_en <= 1'b1;
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

  reg ip_encode_en, ip_encode_done;
  reg [31:0] ip_encode_sa = MY_IP_ADDR;
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
  reg [15:0] tcp_encode_dest_port;
  reg [31:0] tcp_encode_sequence_num;
  reg [31:0] tcp_encode_ack_num;
  reg [ 7:0] tcp_encode_flags;
  reg [15:0] tcp_encode_window;
  reg [15:0] tcp_encode_len;
  reg [15:0] tcp_encode_initial_checksum;
  reg [ 7:0] tcp_encode_dout;
  tcp_encode tcp_enc (
      .clk(clk),
      .rst(rst),
      .en(tcp_encode_en),
      .ip_sa(ip_encode_sa),
      .ip_da(ip_encode_da),
      .tcp_len(tcp_encode_len),

      .dest_port(tcp_encode_dest_port),
      .sequence_num(tcp_encode_sequence_num),
      .ack_num(tcp_encode_ack_num),
      .flags(tcp_encode_flags),
      .window(tcp_encode_window),
      .initial_checksum(tcp_encode_initial_checksum),
      // ebr has 1 cycle read latency so "pre_done_1" is required to meet
      // timing and ensure payload from ebr is ready
      .pre_done_2(),
      .pre_done_1(tcp_encode_done),
      .done(),
      .dout(tcp_encode_dout)
  );
  typedef enum {
    IDLE,
    ARP,
    IP_PKT_WAIT,
    IP,
    TCP,
    PAYLOAD
  } tx_state_t;
  tx_state_t tx_state = IDLE;
  reg [15:0] payload_counter_2;
  always @(posedge clk) begin
    if (rst) begin
      tx_state  <= IDLE;
      pkt_rd_en <= 0;
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
            tx_state <= IP_PKT_WAIT;
            pkt_rd_en <= 1;
            mac_encode_en <= 1;
            mac_dest <= i_mac_da;
            ethertype <= 16'h0800;
          end
        end
        ARP: begin
          if (arp_encode_done) tx_state <= IDLE;
        end
        IP_PKT_WAIT: begin
          pkt_rd_en <= 0;
          tx_state  <= IP;
        end
        IP: begin
          if (ip_encode_done) begin
            tx_state <= TCP;
            payload_counter_2 <= pkt_external.payload_size;
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

  always_comb begin
    ip_encode_en  = '0;
    tcp_encode_en = '0;
    arp_encode_en = '0;
    case (tx_state)
      ARP: arp_encode_en = mac_send_payload;
      IP: ip_encode_en = mac_send_payload;
      TCP: tcp_encode_en = mac_send_payload;
      default: arp_encode_en = 0;
    endcase
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
