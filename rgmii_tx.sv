`include "utils.svh"

module rgmii_tx #(
  parameter [47:0] MAC_ADDR = '0
  )(
  input wire clk,
  input wire rst,
  input wire mac_phy_txen,
  input wire [7:0] mac_phy_txd,
  input reg [47:0] mac_dest,
  input reg [15:0] ethertype,

  // send_next asserts when the MAC is ready for the next payload
  // callers should read and update mac_phy_txd whenever this is high
  output reg send_next,
  output reg phy_txc, 
  output reg phy_txctl, 
  output reg [3:0] phy_txd
);
// RGMII requires specific setup and hold times.
// This is achieved with a 90 degree phase offset tx_clk relative to the
// sysclk used to load the tx lines
reg pll_locked;
clk_gen #(.CLKOP_FPHASE(2), .STEPS(1)) txc_phase90 (.clk_in(clk), .clk_out(phy_txc), .clk_locked(pll_locked));


reg [3:0] txd_1 = '0, txd_2 = '0;
oddr #(.INPUT_WIDTH(4)) _oddr(.rst(rst), .clk(clk), .d1(txd_1), .d2(txd_2), .q(phy_txd));
reg phy_txen = 0;
wire phy_txer;
assign phy_txer = 0 ^ phy_txen;
oddr #(.INPUT_WIDTH(1)) txctl_oddr(.rst(rst), .clk(clk), .d1(phy_txen), .d2(phy_txer), .q(phy_txctl));
typedef enum {IDLE, PREAMBLE, SFD, DEST, SOURCE, TYPE, PAYLOAD, PAD, FCS, IPG} MAC_STATE;

reg [31:0] crc_next;
reg [31:0] crc_out;
reg [7:0] crc_din;
crc32 #(.WIDTH(8)) crc (.din(crc_din), .crc_next(crc_next), .crc_out(crc_out));

reg [7:0] ipg_counter = '0;
localparam [7:0] IPG_COUNT = 8'd96;

MAC_STATE cur_state = IDLE;
reg [15:0] counter = '0;
reg [2:0] fcs_counter = '0;

always @(posedge clk) begin
  if (rst) begin
    crc_next <= 32'hFFFFFFFF;
    crc_din <= '0;

    txd_1 <= '0;
    txd_2 <= '0;
    phy_txen <= 0;
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

        if (mac_phy_txen) begin 
          cur_state <= PREAMBLE;
          phy_txen <= '1;
          txd_1 <= 4'b0101;
          txd_2 <= 4'b0101;
          counter <= 1;
        end else begin
          counter <= '0;
          phy_txen <= '0;
          txd_1 <= '0;
          txd_2 <= '0;
        end
      end
      PREAMBLE: begin
        txd_1 <= 4'b0101;
        txd_2 <= 4'b0101;
        counter <= counter + 1;
        // DV asserted to signify start of frame
        if (counter == 16'd6) cur_state <= SFD;
      end
      SFD: begin
        txd_1 <= 4'b0101;
        txd_2 <= 4'b1101;
        counter <= counter + 1;
        cur_state <= DEST;
      end
      DEST: begin
        txd_1 <= `SELECT_BYTE_NIBBLE(mac_dest, counter, 8, 0);
        txd_2 <= `SELECT_BYTE_NIBBLE(mac_dest, counter, 8, 1);
        crc_din <= `SELECT_BYTE(mac_dest, counter, 8);
        if (counter == 16'd8) crc_next <= 32'hFFFFFFFF;
        else crc_next <= crc_out;
        counter <= counter + 1;
        if (counter == 16'd13) cur_state <= SOURCE;
      end
      SOURCE: begin
        txd_1 <= `SELECT_BYTE_NIBBLE(MAC_ADDR, counter, 14, 0);
        txd_2 <= `SELECT_BYTE_NIBBLE(MAC_ADDR, counter, 14, 1);
        crc_din <= `SELECT_BYTE(MAC_ADDR, counter, 14);
        crc_next <= crc_out;
        counter <= counter + 1;
        if (counter == 16'd19) cur_state <= TYPE;
      end
      TYPE: begin
        txd_1 <= `SELECT_BYTE_NIBBLE(ethertype, counter, 20, 0);
        txd_2 <= `SELECT_BYTE_NIBBLE(ethertype, counter, 20, 1);
        crc_din <= `SELECT_BYTE(ethertype, counter, 20);
        crc_next <= crc_out;
        counter <= counter + 1;
        if (counter == 16'd20) begin
          // tell users of this module that mac header is done
          // the next cycle is the last nibble of type, so upper layers are
          // required to make sure that mac_phy_txd is updated by the next
          // cycle for payload to sample on the following cycle
          send_next <= 1;
        end
        if (counter == 16'd21) begin 
          cur_state <= PAYLOAD;
        end
      end
      PAYLOAD: begin
        counter <= counter + 1;
        // TX_EN is deasserted! PAD if not MTU, otherwise FCS
        if (~mac_phy_txen) begin 
          send_next <= 0;
          if (counter < 16'd68) begin
            cur_state <= PAD;
            txd_1 <= '0;
            txd_2 <= '0;
            crc_din <= '0;
            crc_next <= crc_out;
          end else begin
            cur_state <= FCS;
            fcs_counter <= fcs_counter + 1;
            txd_1 <= `SELECT_BYTE_NIBBLE(~crc_out, fcs_counter, 0, 0);
            txd_2 <= `SELECT_BYTE_NIBBLE(~crc_out, fcs_counter, 0, 1);
          end
        end else begin
          txd_1 <= mac_phy_txd[3:0];
          txd_2 <= mac_phy_txd[7:4];
          crc_din <= mac_phy_txd;
          crc_next <= crc_out;
          if (counter == 16'd1525) begin
            cur_state <= FCS;
            send_next <= 0;
          end
        end
      end
      PAD: begin
        txd_1 <= '0;
        txd_2 <= '0;
        crc_din <= '0;
        crc_next <= crc_out;
        if (counter == 16'd67) cur_state <= FCS;
        counter <= counter + 1;
      end
      FCS: begin
        fcs_counter <= fcs_counter + 1;
        txd_1 <= `SELECT_BYTE_NIBBLE(~crc_out, fcs_counter, 0, 0);
        txd_2 <= `SELECT_BYTE_NIBBLE(~crc_out, fcs_counter, 0, 1);
        // TODO: IPG
        counter <= counter + 1;
        if (fcs_counter == 3) cur_state <= IPG;
      end
      IPG: begin
        ipg_counter <= ipg_counter + 1;
        counter <= '0;
        fcs_counter <= '0;
        phy_txen <= '0;
        txd_1 <= '0;
        txd_2 <= '0;
        
        if (ipg_counter == IPG_COUNT - 1) cur_state <= IDLE;
      end
    endcase
  end
end

endmodule

