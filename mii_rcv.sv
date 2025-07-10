module mii_rcv #(
  parameter [47:0] MAC_ADDR = '0
  )(
  input wire clk,
  input wire rst,
  input wire [3:0] mii_rxd,
  input wire mii_rxctl,

  output reg crc_err,
  output reg arp_valid,
  output reg ip_valid
);
localparam [31:0] IP_ADDR = 32'h69696969;

typedef enum {IDLE, PREAMBLE, DEST, SOURCE, TYPE, PAYLOAD, ABORT} MAC_STATE;
MAC_STATE state = IDLE;

reg [31:0] crc_next = 32'hFFFFFFFF;
reg [31:0] crc_out;
reg [3:0] din = '0;
crc32 crc (.din(din), .crc_next(crc_next), .crc_out(crc_out));
always @(posedge clk) begin
  if (rst) begin
    crc_next <= 32'hFFFFFFFF;
    din <= '0;
    crc_err <= '0;
  end else begin
    case (state)
      IDLE, PREAMBLE, ABORT: begin
        crc_next <= 32'hFFFFFFFF;
        din <= '0;
      end
      default: begin
        if (rxctl) begin
          crc_next <= crc_out;
          din <= mii_rxd;
        // not in IDLE states and RX_DV dropped, verify checksum valid
        else if (crc_out != 32'h2144DF1C) begin
          crc_err <= 1;
        end
      end
    endcase
  end
end

reg [47:0] da = '0;
reg [47:0] sa = '0;
reg [15:0] ether_type = '0;
reg [15:0] counter = '0;

// Decoding the MAC frame
// Skip idle and extension, strip off preamble and sfd
always @(posedge clk) begin
    if (reset || ~rxctl) begin 
      state <= IDLE;
      da <= '0;
      sa <= '0;
      ether_type <= '0;
      counter <= '0;

      ip_valid <= 0;
      arp_valid <= 0;
    end else begin
      case (state)
        IDLE: begin 
          if (mii_rxd == 4'0101) state <= PREAMBLE;
          else begin
            da <= '0;
            sa <= '0;
            counter <= '0;
          end
        end
        PREAMBLE: begin
          if (mii_rxd == 4'0101)
            state <= PREAMBLE;
          // SFD detected
          else if (mii_rxd == 4'b1011)
            state <= DA;
          else state <= ABORT;
        end
        DA: begin 
          if (counter == 16'd11) begin 
            state <= SA;
            counter <= '0;
          end else begin
            counter <= counter + 1;
            da = { mii_rxd, da[47:4] };
          end
        end
        SA: begin
          if (counter == 16'd11) begin 
            state <= LEN;
            counter <= '0;
          end else begin
              counter <= counter + 1;
              sa = { mii_rxd, sa[47:4] };
          end
        end
        TYPE: begin
          ether_type <= { mii_rxd, ether_type[15:4] };
          if (counter == 16'd3) begin 
            counter <= '0;
            state <= PAYLOAD;
            if ({mii_rxd, ether_type[15:4]} <= 16'd1500) begin
              ip_valid <= 1;
            end else begin 
              case ({mii_rxd, ether_type[15:4]})
                16'h0800: begin
                  ip_valid <= 1;
                end
                16'h0806: begin
                  arp_valid <= 1;
                end
                default: state <= ABORT;
              endcase
          end else begin
              counter <= counter + 1;
          end
        end
        PAYLOAD: begin
          counter <= counter + 1;
          if (counter >= 1504) begin
            state <= ABORT;
          end
        end
        ABORT: begin
          // NOP. Wait for RX_DV deassertion to restart
          ip_valid <= 0;
          arp_valid <= 0;
        end
      endcase
    end
  end

endmodule
