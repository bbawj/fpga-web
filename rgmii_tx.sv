`include "utils.svh"

module rgmii_tx #(
  parameter [47:0] MAC_ADDR = '0
  )(
  input wire clk,
  input wire rst,
  input wire mac_phy_txen,
  input wire [3:0] mac_phy_txd,
  input reg [47:0] mac_dest,
  input reg [15:0] ethertype,

  // send_next asserts when the MAC is ready for the next payload
  // callers should read and update mac_phy_txd whenever this is high
  output reg send_next,
  output reg phy_txctl, 
  output reg [3:0] phy_txd
);

typedef enum {IDLE, PREAMBLE, SFD, DEST, SOURCE, TYPE, PAYLOAD, PAD, FCS, IPG} MAC_STATE;

reg [31:0] crc_next;
reg [31:0] crc_out;
reg [3:0] crc_din;
crc32 crc (.din(crc_din), .crc_next(crc_next), .crc_out(crc_out));

reg [7:0] ipg_counter = '0;
localparam [7:0] IPG_COUNT = 8'd96;

MAC_STATE cur_state = IDLE;
reg [15:0] counter = '0;
reg [2:0] fcs_counter = '0;

always @(posedge clk or negedge clk) begin
  if (rst) begin
    crc_next <= 32'hFFFFFFFF;
    crc_din <= '0;

    phy_txd <= '0;
    phy_txctl <= '0;
    send_next <= 0;

    cur_state <= IDLE;
    counter <= '0;
    fcs_counter <= '0;
    ipg_counter <= '0;
  end else begin
    case (cur_state)
      IDLE: begin
        fcs_counter <= '0;
        phy_txctl <= '0;
        ipg_counter <= '0;

        if (mac_phy_txen) begin 
          cur_state <= PREAMBLE;
          phy_txctl <= '1;
          phy_txd <= 4'b0101;
          counter <= 1;
        end else begin
          counter <= '0;
          phy_txd <= '0;
        end
      end
      PREAMBLE: begin
        phy_txd <= 4'b0101;
        counter <= counter + 1;
        // DV asserted to signify start of frame
        if (counter == 16'd14) cur_state <= SFD;
      end
      SFD: begin
        phy_txd <= 4'b1101;
        counter <= counter + 1;
        cur_state <= DEST;
      end
      DEST: begin
        phy_txd <= `SELECT_NIBBLE(mac_dest, counter, 16);
        crc_din <= `SELECT_NIBBLE(mac_dest, counter, 16);
        if (counter == 16) crc_next <= 32'hFFFFFFFF;
        else crc_next <= crc_out;
        counter <= counter + 1;
        if (counter == 16'd27) cur_state <= SOURCE;
      end
      SOURCE: begin
        phy_txd <= `SELECT_NIBBLE(MAC_ADDR, counter, 28);
        crc_din <= `SELECT_NIBBLE(MAC_ADDR, counter, 28);
        crc_next <= crc_out;
        counter <= counter + 1;
        if (counter == 16'd39) cur_state <= TYPE;
      end
      TYPE: begin
        phy_txd <= `SELECT_NIBBLE(ethertype, counter, 40);
        crc_din <= `SELECT_NIBBLE(ethertype, counter, 40);
        crc_next <= crc_out;
        counter <= counter + 1;
        if (counter == 16'd42) begin
          // tell users of this module that mac header is done
          // the next cycle is the last nibble of type, so upper layers are
          // required to make sure that mac_phy_txd is updated by the next
          // cycle for payload to sample on the following cycle
          send_next <= 1;
        end
        if (counter == 16'd43) begin 
          cur_state <= PAYLOAD;
        end
      end
      PAYLOAD: begin
        counter <= counter + 1;
        // TX_EN is deasserted! PAD if not MTU, otherwise FCS
        if (~mac_phy_txen) begin 
          send_next <= 0;
          if (counter < 16'd135) begin
            cur_state <= PAD;
            phy_txd <= '0;
            crc_din <= '0;
            crc_next <= crc_out;
          end else begin
            cur_state <= FCS;
            fcs_counter <= fcs_counter + 1;
            phy_txd <= `SELECT_NIBBLE(~crc_out, fcs_counter, 0);
          end
        end else begin
          phy_txd <= mac_phy_txd;
          crc_din <= mac_phy_txd;
          crc_next <= crc_out;
          if (counter == 16'd3043) begin
            cur_state <= FCS;
            send_next <= 0;
          end
        end
      end
      PAD: begin
        phy_txd <= 4'b0000;
        crc_din <= 4'b0000;
        crc_next <= crc_out;
        if (counter == 16'd135) cur_state <= FCS;
        counter <= counter + 1;
      end
      FCS: begin
        fcs_counter <= fcs_counter + 1;
        phy_txd <= `SELECT_NIBBLE(~crc_out, fcs_counter, 0);
        // TODO: IPG
        counter <= counter + 1;
        if (fcs_counter == 7) cur_state <= IPG;
      end
      IPG: begin
        ipg_counter <= ipg_counter + 1;
        counter <= '0;
        fcs_counter <= '0;
        phy_txctl <= '0;
        phy_txd <= '0;
        
        if (ipg_counter == IPG_COUNT - 1) cur_state <= IDLE;
      end
    endcase
  end
end

endmodule

