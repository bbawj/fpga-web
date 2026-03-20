`default_nettype none
module mac_decode #(
    parameter [47:0] MAC_ADDR = '0
) (
    input wire clk,
    input wire rst,
    input reg [7:0] rxd_realtime,
    input reg rx_dv_realtime,
    // These are delayed 4 cycles in order to let us pre-empt the 32 bit FCS 
    input reg [7:0] rxd,
    input reg rx_dv,

    output reg [47:0] sa,
    output reg busy,
    output reg other_err,
    output reg crc_err,
    output reg arp_decode_valid,
    output reg ip_valid
);

  typedef enum {
    IDLE,
    PREAMBLE,
    DEST,
    SOURCE,
    TYPE,
    PAYLOAD,
    ABORT
  } mac_state_t;
  mac_state_t state = IDLE;

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
  crc32 #(
      .WIDTH(8)
  ) crc (
      .din(din),
      .crc_next(crc_next),
      .crc_out(crc_out)
  );
  always @(posedge clk) begin
    if (rst) begin
      crc_next <= 32'hFFFFFFFF;
      din <= '0;
      crc_err <= '0;
      start_crc_flag <= 0;
    end else begin
      case (state)
        IDLE, PREAMBLE, ABORT: begin
          crc_next <= 32'hFFFFFFFF;
          crc_err <= '0;
          din <= '0;
          start_crc_flag <= 1'b0;
        end
        default: begin
          if (rx_dv) begin
            din <= rxd_realtime;
            if (~start_crc_flag) begin
              crc_next <= 32'hFFFFFFFF;
              start_crc_flag <= 1'b1;
            end else begin
              crc_next <= crc_out;
            end
            // not in IDLE states and RX_DV dropped, verify checksum valid
          end else begin
            if (~crc_out != 32'h2144DF1C) crc_err <= 1;
            start_crc_flag <= 1'b0;
          end
        end
      endcase
    end
  end

  reg [47:0] da;
  reg [15:0] ether_type = '0;
  reg [15:0] counter = '0;
  reg [47:0] working;

  mac_state_t next_state;
  always @(posedge clk) begin
    if (rst) begin
      state   <= IDLE;
      counter <= '0;
    end else begin
      prev_state <= state;
      state <= next_state;
      working <= {working[39:0], rxd};
      counter <= (prev_state != state) ? 'd1 : counter + 1;
    end
  end

  mac_state_t prev_state;
  always @(posedge clk) begin
    case (state)
      SOURCE: if (prev_state != state) da <= working;
      TYPE: begin
        if (prev_state != state) sa <= working;
        else begin
          ether_type <= {working[7:0], rxd};
          arp_decode_valid <= {working[7:0], rxd} == 16'h0806;
          ip_valid <= {working[7:0], rxd} == 16'h0800;
        end
      end
      IDLE: begin
        ip_valid <= 0;
        arp_decode_valid <= 0;
        other_err <= '0;
      end
      ABORT: begin
        ip_valid <= 0;
        arp_decode_valid <= 0;
        other_err <= 1'b1;
      end
      // PAYLOAD: if (prev_state != state) ether_type <= working[15:0];
      default: begin
      end
    endcase
  end

  always_comb begin
    next_state = state;
    case (state)
      IDLE: begin
        // Decoding the MAC frame
        // Skip idle and extension, strip off preamble and sfd
        if (rxd == 8'h55) next_state = PREAMBLE;
      end
      DEST: begin
        if (counter == 16'd5) begin
          // ABORT if we are not the intended receiver or if not a broadcast
          if ({working[39:0], rxd} == MAC_ADDR || {working[39:0], rxd} == 48'hFFFFFFFFFFFF)
            next_state = SOURCE;
          else next_state = ABORT;
        end
      end
      PREAMBLE: begin
        if (rxd == 8'h55) next_state = PREAMBLE;
        // SFD detected
        else if (rxd == 8'hD5) next_state = DEST;
        else next_state = ABORT;
      end
      SOURCE: begin
        if (counter == 16'd5) begin
          next_state = TYPE;
        end
      end
      TYPE: begin
        if (counter == 16'd1) begin
          next_state = PAYLOAD;
        end
      end
      PAYLOAD: begin
        if (counter == 1500) begin
          next_state = ABORT;
        end
        // Falling edge of phy rx_dv. This means the last 4 bytes were FCS,
        // transition to abort to prevent downstream receivers from
        // processing FCS.
        if (!rx_dv_realtime && rx_dv) begin
          next_state = IDLE;
        end
      end
      ABORT: begin
        // NOP. Wait for RX_DV deassertion to restart
        if (!rx_dv) next_state = IDLE;
      end
      default: next_state = IDLE;
    endcase
  end

endmodule

