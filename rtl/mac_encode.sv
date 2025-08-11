`include "utils.svh"

module mac_encode #(
  parameter [47:0] MAC_ADDR = 48'hdeadbeefcafe
  )(
  input wire clk,
  input wire rst,
  input wire en,
  input wire [7:0] mac_payload,
  input reg [47:0] mac_dest,
  input reg [15:0] ethertype,

  // send_next asserts when the MAC is ready for the next payload
  // callers should read and update mac_phy_txd whenever this is high
  output reg send_next,
  output reg phy_txctl, 
  output reg [3:0] phy_txd
);

reg mac_phy_txen;
reg [7:0] mac_phy_txd;
rgmii_tx _rgmii_tx(.clk(clk), .rst(rst), .mac_phy_txen(mac_phy_txen), 
  .mac_phy_txd(mac_phy_txd), .phy_txctl(phy_txctl),
  .phy_txd(phy_txd));

typedef enum {IDLE, PREAMBLE, SFD, DEST, SOURCE, TYPE, PAYLOAD, PAD, FCS, IPG} MAC_STATE;

reg [31:0] crc_next;
reg [31:0] crc_out;
reg [7:0] crc_din;
crc32 #(
  `ifdef SPEED_100M
  .WIDTH(4)
`else
  .WIDTH(8)
`endif
  ) crc (.din(crc_din), .crc_next(crc_next), .crc_out(crc_out));

reg [7:0] ipg_counter = '0;
// Rather than creating separate modules for different speeds, i thought that
// using an ifdef would be better. 100M outputs 4 bits per cycle but the
// output interface is still 8 bits, only that every cycle, the output is
// shifted by 4 bits. This is okay as the RGMII interface will only read from
// the first 4 bits of mac_phy_txd. Hence, the counts are doubled for 100M,
// since 2 cycles are required to go through the 1 byte as compared to 1000M.
`ifdef SPEED_100M
localparam [7:0] IPG_COUNT = 8'd192;
localparam [15:0] COUNT_PREAMBLE = 16'd14;
localparam [15:0] COUNT_SFD = 16'd16;
localparam [15:0] COUNT_DEST = 16'd28;
localparam [15:0] COUNT_SOURCE = 16'd40;
localparam [15:0] COUNT_TYPE = 16'd44;
localparam [15:0] COUNT_MIN_PAYLOAD = 16'd136;
localparam [15:0] COUNT_MAX_PAYLOAD = 16'd3052;
localparam [3:0] COUNT_FCS = 4'd8;
`else
localparam [7:0] IPG_COUNT = 8'd96;
localparam [15:0] COUNT_PREAMBLE = 16'd7;
localparam [15:0] COUNT_SFD = 16'd8;
localparam [15:0] COUNT_DEST = 16'd14;
localparam [15:0] COUNT_SOURCE = 16'd20;
localparam [15:0] COUNT_TYPE = 16'd22;
localparam [15:0] COUNT_MIN_PAYLOAD = 16'd68;
localparam [15:0] COUNT_MAX_PAYLOAD = 16'd1526;
localparam [3:0] COUNT_FCS = 4'd4;
`endif
localparam [7:0] sfd = 8'b11010101;

MAC_STATE cur_state = IDLE;
reg [15:0] counter = '0;
reg [3:0] fcs_counter = '0;

always @(posedge clk) begin
  if (rst) begin
    crc_next <= 32'hFFFFFFFF;
    crc_din <= '0;

    mac_phy_txd <= '0;
    mac_phy_txen <= 0;
    send_next <= 0;

    cur_state <= IDLE;
    counter <= '0;
    fcs_counter <= '0;
    ipg_counter <= '0;
  end else begin
    case (cur_state)
      IDLE: begin
        fcs_counter <= '0;
        ipg_counter <= '0;

        if (en) begin 
          cur_state <= PREAMBLE;
          mac_phy_txen <= '1;
          mac_phy_txd <= 8'b01010101;
          counter <= 1;
        end else begin
          counter <= '0;
          mac_phy_txen <= '0;
          mac_phy_txd <= '0;
        end
      end
      PREAMBLE: begin
        mac_phy_txd <= 8'b01010101;
        counter <= counter + 1;
        // DV asserted to signify start of frame
        if (counter == COUNT_PREAMBLE - 1) cur_state <= SFD;
      end
      SFD: begin
        mac_phy_txd <= `SELECT_BYTE_MSB(sfd, counter, COUNT_PREAMBLE);
        counter <= counter + 1;
        if (counter == COUNT_SFD - 1) cur_state <= DEST;
      end
      DEST: begin
        mac_phy_txd <= `SELECT_BYTE_MSB(mac_dest, counter, COUNT_SFD);
        crc_din <= `SELECT_BYTE_MSB(mac_dest, counter, COUNT_SFD);

        if (counter == COUNT_SFD) crc_next <= 32'hFFFFFFFF;
        else crc_next <= crc_out;

        counter <= counter + 1;
        if (counter == COUNT_DEST - 1) cur_state <= SOURCE;
      end
      SOURCE: begin
        mac_phy_txd <= `SELECT_BYTE_MSB(MAC_ADDR, counter, COUNT_DEST);
        crc_din <= `SELECT_BYTE_MSB(MAC_ADDR, counter, COUNT_DEST);
        crc_next <= crc_out;
        counter <= counter + 1;
        if (counter == COUNT_SOURCE - 1) cur_state <= TYPE;
      end
      TYPE: begin
        mac_phy_txd <= `SELECT_BYTE_MSB(ethertype, counter, COUNT_SOURCE);
        crc_din <= `SELECT_BYTE_MSB(ethertype, counter, COUNT_SOURCE);
        crc_next <= crc_out;
        counter <= counter + 1;
        if (counter == COUNT_TYPE - 1) begin 
          // Tell users of this module that mac header is done.
          send_next <= 1;
          cur_state <= PAYLOAD;
        end
      end
      PAYLOAD: begin
        counter <= counter + 1;
        // TX_EN is deasserted! PAD if not MTU, otherwise FCS
        if (~en) begin 
          send_next <= 0;
          if (counter < COUNT_MIN_PAYLOAD) begin
            cur_state <= PAD;
            mac_phy_txd <= '0;
            crc_din <= '0;
            crc_next <= crc_out;
          end else begin
            cur_state <= FCS;
            fcs_counter <= fcs_counter + 1;
            mac_phy_txd <= `SELECT_BYTE_LSB(~crc_out, fcs_counter, 0);
          end
        end else begin
          mac_phy_txd <= mac_payload;
          crc_din <= mac_payload;
          crc_next <= crc_out;
          if (counter == COUNT_MAX_PAYLOAD - 1) begin
            cur_state <= FCS;
            send_next <= 0;
          end
        end
      end
      PAD: begin
        counter <= counter + 1;
        mac_phy_txd <= '0;
        crc_din <= '0;
        crc_next <= crc_out;
        if (counter == COUNT_MIN_PAYLOAD - 1) cur_state <= FCS;
      end
      FCS: begin
        fcs_counter <= fcs_counter + 1;
        mac_phy_txd <= `SELECT_BYTE_LSB(~crc_out, fcs_counter, 0);
        // TODO: IPG
        counter <= counter + 1;
        if (fcs_counter == COUNT_FCS - 1) cur_state <= IPG;
      end
      IPG: begin
        ipg_counter <= ipg_counter + 1;
        counter <= '0;
        fcs_counter <= '0;
        mac_phy_txen <= '0;
        mac_phy_txd <= '0;
        
        if (ipg_counter == IPG_COUNT - 1) cur_state <= IDLE;
      end
    endcase
  end
end

endmodule

