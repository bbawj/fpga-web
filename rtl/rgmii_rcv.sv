module rgmii_rcv #(
  parameter [47:0] MAC_ADDR = '0
  )(
  input wire clk,
  input wire rst,
  input wire [3:0] mii_rxd,
  input wire mii_rxctl,

  output reg [7:0] rxd,
  output reg [47:0] sa,
  output reg busy,
  output reg crc_err,
  output reg arp_decode_valid,
  output reg ip_valid
);

reg [3:0] rxd_1, rxd_2;
iddr #(.INPUT_WIDTH(4)) rxd_iddr(.clk(clk), .d(mii_rxd), .q1(rxd_1), .q2(rxd_2));
// TODO: deal with rx_er
reg rx_dv, rx_er;
iddr #(.INPUT_WIDTH(1)) rxctl_iddr(.clk(clk), .d(mii_rxctl), .q1(rx_dv), .q2(rx_er));

typedef enum {IDLE, PREAMBLE, DEST, SOURCE, TYPE, PAYLOAD, ABORT} MAC_STATE;
MAC_STATE state = IDLE;

assign rxd = {rxd_2, rxd_1};
always @(posedge clk) begin
  if (rx_dv) begin
    busy <= 1;
  end else begin
    busy <= 0;
  end
end

reg [31:0] crc_next = 32'hFFFFFFFF;
reg [31:0] crc_out;
reg [7:0] din = '0;
reg start_crc_flag = 0;
crc32 #(.WIDTH(8)) crc (.din(din), .crc_next(crc_next), .crc_out(crc_out));
always @(posedge clk) begin
  if (rst) begin
    crc_next <= 32'hFFFFFFFF;
    din <= '0;
    crc_err <= '0;
    start_crc_flag <= 0;
  end else begin
    case (state)
      IDLE, PREAMBLE, ABORT: begin
        crc_next <= '0;
        din <= '0;
      end
      default: begin
        if (rx_dv) begin
          din <= {rxd_2, rxd_1};
          if (~start_crc_flag) begin
            crc_next <= 32'hFFFFFFFF;
            start_crc_flag <= 1;
          end else begin
            crc_next <= crc_out;
          end
        // not in IDLE states and RX_DV dropped, verify checksum valid
        end else if (~crc_out != 32'h2144DF1C) begin
          crc_err <= 1;
        end 
      end
    endcase
  end
end

reg [47:0] da;
reg [15:0] ether_type = '0;
reg [15:0] counter = '0;

// Decoding the MAC frame
// Skip idle and extension, strip off preamble and sfd
always @(posedge clk) begin
    if (rst || ~rx_dv) begin 
      state <= IDLE;
      da <= '0;
      sa <= '0;
      ether_type <= '0;
      counter <= '0;

      ip_valid <= 0;
      arp_decode_valid <= 0;
    end else begin
      case (state)
        IDLE: begin 
          if (rxd_1 == 4'b0101) state <= PREAMBLE;
          else begin
            da <= '0;
            sa <= '0;
            counter <= '0;
          end
        end
        PREAMBLE: begin
          if (rxd_1 == 4'b0101 && rxd_2 == 4'b0101)
            state <= PREAMBLE;
          // SFD detected
          else if (rxd_1 == 4'b0101 && rxd_2 == 4'b1101)
            state <= DEST;
          else state <= ABORT;
        end
        DEST: begin 
          da <= { rxd_2, rxd_1, da[47:8] };
          if (counter == 16'd5) begin 
            counter <= '0;
            // ABORT if we are not the intended receiver
            if ({ rxd_2, rxd_1, da[47:8] } == MAC_ADDR) state <= SOURCE;
            else state <= ABORT;
          end else begin
            counter <= counter + 1;
          end
        end
        SOURCE: begin
          sa <= { rxd_2, rxd_1, sa[47:8] };
          if (counter == 16'd5) begin 
            state <= TYPE;
            counter <= '0;
          end else begin
            counter <= counter + 1;
          end
        end
        TYPE: begin
          ether_type <= { rxd_2, rxd_1, ether_type[15:8] };
          if (counter == 16'd1) begin 
            counter <= '0;
            if ({rxd_2, rxd_1, ether_type[15:8]} <= 16'd1500) begin
              ip_valid <= 1;
              state <= PAYLOAD;
            end else begin 
              case ({rxd_2, rxd_1, ether_type[15:8]})
                16'h0800: begin
                  ip_valid <= 1;
                  state <= PAYLOAD;
                end
                16'h0806: begin
                  arp_decode_valid <= 1;
                  state <= PAYLOAD;
                end
                default: state <= ABORT;
              endcase
            end
          end else begin
              counter <= counter + 1;
          end
        end
        PAYLOAD: begin
          counter <= counter + 1;
          if (counter >= 1503) begin
            state <= ABORT;
          end
        end
        ABORT: begin
          // NOP. Wait for RX_DV deassertion to restart
          ip_valid <= 0;
          arp_decode_valid <= 0;
        end
      endcase
    end
  end

endmodule
