module rgmii_phy_if #(
  parameter [47:0] MAC_ADDR = '0
  )(
  input wire clk,
  input wire rst,
  input wire mac_phy_txen,
  input wire [3:0] mac_phy_txd,
  input reg [47:0] mac_dest,

  // send_next asserts when the MAC is ready for the next payload
  // callers should read and update mac_phy_txd whenever this is high
  output reg send_next,
  output reg phy_txctl, 
  output reg [3:0] phy_txd
);

localparam [15:0] ethertype = 16'h0800;
typedef enum {IDLE, PREAMBLE, SFD, DEST, SOURCE, TYPE, PAYLOAD, PAD, FCS, IPG} MAC_STATE;

// is for choosing the nibbles in least significant order in a byte
`define SELECT_NIBBLE(data, end_count, start_count) \
  data[4*(end_count - start_count + 1) - 1 -: 4]

reg [31:0] crc_next = 32'hFFFFFFFF;
reg [31:0] crc_out;
reg [3:0] din = '0;
crc32 crc (.din(din), .crc_next(crc_next), .crc_out(crc_out));

reg [7:0] ipg_counter = '0;
localparam [7:0] IPG_COUNT = 8'd96;

MAC_STATE cur_state = IDLE;
reg [15:0] counter = '0;
reg [2:0] fcs_counter = '0;
always @(posedge clk or negedge clk) begin
  if (rst) begin
    phy_txd <= '0;
    phy_txctl <= '0;
    send_next <= 1;

    cur_state <= IDLE;
    counter <= '0;
    fcs_counter <= '0;
    ipg_counter <= '0;
  end else begin
    case (cur_state)
      IDLE: begin
        send_next <= 1;
        fcs_counter <= '0;
        phy_txctl <= '0;
        ipg_counter <= '0;

        if (mac_phy_txen) begin 
          // tell users of this module that some delay is required for the
          // MAC header to be appended
          send_next <= 0;
          cur_state <= PREAMBLE;
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
        phy_txctl <= '1;
        if (counter == 16'd14) cur_state <= SFD;
      end
      SFD: begin
        phy_txd <= 4'b1101;
        counter <= counter + 1;
        cur_state <= DEST;
      end
      DEST: begin
        phy_txd <= `SELECT_NIBBLE(mac_dest, counter, 16);
        counter <= counter + 1;
        if (counter == 16'd27) cur_state <= SOURCE;
      end
      SOURCE: begin
        phy_txd <= `SELECT_NIBBLE(MAC_ADDR, counter, 28);
        counter <= counter + 1;
        if (counter == 16'd39) cur_state <= TYPE;
      end
      TYPE: begin
        phy_txd <= `SELECT_NIBBLE(ethertype, counter, 40);
        counter <= counter + 1;
        if (counter == 16'd43) begin 
          cur_state <= PAYLOAD;
          send_next <= 1;
        end
      end
      PAYLOAD: begin
        counter <= counter + 1;
        // TX_EN is deasserted! PAD if not MTU, otherwise FCS
        if (~mac_phy_txen) begin 
          if (counter < 16'd135) begin
            cur_state <= PAD;
            phy_txd <= '0;
          end else begin
            cur_state <= FCS;
            fcs_counter <= fcs_counter + 1;
            phy_txd <= `SELECT_NIBBLE(~crc_out, fcs_counter, 0);
          end
        end else begin
          phy_txd <= mac_phy_txd;
          if (counter == 16'd3043) cur_state <= FCS;
        end
      end
      PAD: begin
        phy_txd <= 4'b0000;
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

always @(posedge clk) begin
  if (rst) begin
    crc_next <= 32'hFFFFFFFF;
    din <= '0;
  end else begin
    case (cur_state)
      IDLE, PREAMBLE, SFD: begin
        crc_next <= 32'hFFFFFFFF;
        din <= '0;
      end
      FCS: begin
      end
      default: begin
        crc_next <= crc_out;
        din <= phy_txd;
      end
    endcase
  end
end

endmodule

