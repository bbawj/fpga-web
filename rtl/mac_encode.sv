`include "utils.svh"
`default_nettype none

module mac_encode #(
    parameter [47:0] MAC_ADDR = 48'hdeadbeefcafe
) (
    input wire clk,
    input wire rst,
    input wire en,
    input wire [7:0] mac_payload,
    input reg [47:0] i_mac_dest,
    input reg [15:0] i_ethertype,

    output reg ready,
    // send_next asserts when the MAC is ready for the next payload
    // callers should read and update mac_phy_txd whenever this is high
    output reg send_next,
    output reg mac_txen,
    output reg [7:0] mac_txd
);

  typedef enum {
    IDLE,
    PREAMBLE,
    SFD,
    DEST,
    SOURCE,
    TYPE,
    TYPE2,
    PAYLOAD,
    PAD,
    FCS,
    IPG
  } mac_state_t;

  reg [31:0] crc_next;
  reg [31:0] crc_out;
  reg [ 7:0] crc_din;
  crc32 #(
`ifdef SPEED_100M
      .WIDTH(4)
`else
      .WIDTH(8)
`endif
      /* verilator lint_off WIDTHTRUNC */
  ) crc (
      .din(crc_din),
      .crc_next(crc_next),
      .crc_out(crc_out)
  );
  /* verilator lint_on WIDTHTRUNC */
  typedef enum logic [5:0] {
    S_IDLE,
    // Preamble: 7 bytes of 0x55
    S_PRE_0,
    S_PRE_1,
    S_PRE_2,
    S_PRE_3,
    S_PRE_4,
    S_PRE_5,
    S_PRE_6,
    // SFD: 1 byte 0xD5
    S_SFD,
    // Dest MAC: 6 bytes
    S_DEST_0,
    S_DEST_1,
    S_DEST_2,
    S_DEST_3,
    S_DEST_4,
    S_DEST_5,
    // Source MAC: 6 bytes
    S_SRC_0,
    S_SRC_1,
    S_SRC_2,
    S_SRC_3,
    S_SRC_4,
    S_SRC_5,
    // Ethertype: 2 bytes
    S_TYPE_0,
    S_TYPE_1,
    // Variable-length states
    S_PAYLOAD,
    S_PAD,
    // FCS: 4 bytes
    S_FCS_0,
    S_FCS_1,
    S_FCS_2,
    S_FCS_3,
    // IPG
    S_IPG
  } state_t;

  state_t state, next_state;

  // Latched inputs (captured at IDLE -> PRE_0)
  logic [47:0] mac_dest;
  logic [15:0] ethertype;

  // Counter for variable-length states only
  localparam [15:0] COUNT_MIN_PAYLOAD = 16'd46;
  localparam [15:0] COUNT_MAX_PAYLOAD = 16'd1500;
  localparam [15:0] IPG_COUNT = 16'd8;
  logic [15:0] counter;

  // CRC snapshot at FCS time
  logic [31:0] crc_fcs;

  // -------------------------------------------------------------------------
  // Input latch
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    ethertype <= i_ethertype;
    mac_dest  <= i_mac_dest;
  end

  // -------------------------------------------------------------------------
  // CRC accumulation
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      crc_next <= 32'hFFFFFFFF;
    end else begin
      case (state)
        S_DEST_0: crc_next <= 32'hFFFFFFFF;  // reset at start of frame
        S_DEST_1, S_DEST_2, S_DEST_3,
        S_DEST_4, S_DEST_5,
        S_SRC_0,  S_SRC_1,  S_SRC_2,
        S_SRC_3,  S_SRC_4,  S_SRC_5,
        S_TYPE_0, S_TYPE_1,
        S_PAYLOAD, S_PAD:
        crc_next <= crc_out;
        default: crc_next <= crc_next;
      endcase
    end
  end

  // Snapshot CRC going into FCS states so it doesn't shift under us
  always_ff @(posedge clk) begin
    if (state == S_TYPE_1 || (state == S_PAYLOAD && next_state == S_FCS_0)
                           || (state == S_PAD    && next_state == S_FCS_0))
      crc_fcs <= ~crc_out;
  end

  // -------------------------------------------------------------------------
  // Counter (only meaningful in PAYLOAD / PAD / IPG)
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) counter <= '0;
    else begin
      case (state)
        S_TYPE_1: counter <= '0;  // reset before payload
        S_PAYLOAD, S_PAD, S_IPG: counter <= counter + 1;
        default: counter <= '0;
      endcase
    end
  end

  // -------------------------------------------------------------------------
  // Next-state logic
  // -------------------------------------------------------------------------
  always_comb begin
    next_state = state;
    case (state)
      S_IDLE:   next_state = en ? S_PRE_0 : S_IDLE;
      S_PRE_0:  next_state = S_PRE_1;
      S_PRE_1:  next_state = S_PRE_2;
      S_PRE_2:  next_state = S_PRE_3;
      S_PRE_3:  next_state = S_PRE_4;
      S_PRE_4:  next_state = S_PRE_5;
      S_PRE_5:  next_state = S_PRE_6;
      S_PRE_6:  next_state = S_SFD;
      S_SFD:    next_state = S_DEST_0;
      S_DEST_0: next_state = S_DEST_1;
      S_DEST_1: next_state = S_DEST_2;
      S_DEST_2: next_state = S_DEST_3;
      S_DEST_3: next_state = S_DEST_4;
      S_DEST_4: next_state = S_DEST_5;
      S_DEST_5: next_state = S_SRC_0;
      S_SRC_0:  next_state = S_SRC_1;
      S_SRC_1:  next_state = S_SRC_2;
      S_SRC_2:  next_state = S_SRC_3;
      S_SRC_3:  next_state = S_SRC_4;
      S_SRC_4:  next_state = S_SRC_5;
      S_SRC_5:  next_state = S_TYPE_0;
      S_TYPE_0: next_state = S_TYPE_1;
      S_TYPE_1: next_state = S_PAYLOAD;

      S_PAYLOAD: begin
        if (!en) next_state = (counter < COUNT_MIN_PAYLOAD - 1) ? S_PAD : S_FCS_0;
        else if (counter == COUNT_MAX_PAYLOAD - 1) next_state = S_FCS_0;
        else next_state = S_PAYLOAD;
      end

      S_PAD: next_state = (counter == COUNT_MIN_PAYLOAD - 1) ? S_FCS_0 : S_PAD;

      S_FCS_0: next_state = S_FCS_1;
      S_FCS_1: next_state = S_FCS_2;
      S_FCS_2: next_state = S_FCS_3;
      S_FCS_3: next_state = S_IPG;

      S_IPG: next_state = (counter == IPG_COUNT - 1) ? S_IDLE : S_IPG;

      default: next_state = S_IDLE;
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) state <= S_IDLE;
    else state <= next_state;
  end

  // -------------------------------------------------------------------------
  // Output + CRC input logic
  // -------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      mac_txd   <= '0;
      mac_txen  <= 1'b0;
      send_next <= 1'b0;
      ready     <= 1'b1;
      crc_din   <= '0;
    end else begin

      mac_txen <= (state != S_IDLE) && (state != S_IPG);
      ready    <= (state == S_IDLE);

      case (state)
        S_IDLE: mac_txd <= '0;

        S_PRE_0, S_PRE_1, S_PRE_2, S_PRE_3, S_PRE_4, S_PRE_5, S_PRE_6: mac_txd <= 8'h55;

        S_SFD: mac_txd <= 8'hD5;

        S_DEST_0: begin
          mac_txd <= mac_dest[47:40];
          crc_din <= mac_dest[47:40];
        end
        S_DEST_1: begin
          mac_txd <= mac_dest[39:32];
          crc_din <= mac_dest[39:32];
        end
        S_DEST_2: begin
          mac_txd <= mac_dest[31:24];
          crc_din <= mac_dest[31:24];
        end
        S_DEST_3: begin
          mac_txd <= mac_dest[23:16];
          crc_din <= mac_dest[23:16];
        end
        S_DEST_4: begin
          mac_txd <= mac_dest[15:8];
          crc_din <= mac_dest[15:8];
        end
        S_DEST_5: begin
          mac_txd <= mac_dest[7:0];
          crc_din <= mac_dest[7:0];
        end

        S_SRC_0: begin
          mac_txd <= MAC_ADDR[47:40];
          crc_din <= MAC_ADDR[47:40];
        end
        S_SRC_1: begin
          mac_txd <= MAC_ADDR[39:32];
          crc_din <= MAC_ADDR[39:32];
        end
        S_SRC_2: begin
          mac_txd <= MAC_ADDR[31:24];
          crc_din <= MAC_ADDR[31:24];
        end
        S_SRC_3: begin
          mac_txd <= MAC_ADDR[23:16];
          crc_din <= MAC_ADDR[23:16];
        end
        S_SRC_4: begin
          mac_txd <= MAC_ADDR[15:8];
          crc_din <= MAC_ADDR[15:8];
        end
        S_SRC_5: begin
          mac_txd <= MAC_ADDR[7:0];
          crc_din <= MAC_ADDR[7:0];
        end

        S_TYPE_0: begin
          mac_txd   <= ethertype[15:8];
          crc_din   <= ethertype[15:8];
          send_next <= 1'b1;
        end
        S_TYPE_1: begin
          mac_txd <= ethertype[7:0];
          crc_din <= ethertype[7:0];
        end

        S_PAYLOAD: begin
          mac_txd <= mac_payload;
          crc_din <= mac_payload;
        end

        S_PAD: begin
          send_next <= 1'b0;
          mac_txd   <= '0;
          crc_din   <= '0;
        end

        // FCS bytes are ~CRC LSB-first
        S_FCS_0: mac_txd <= ~crc_out[7:0];
        S_FCS_1: mac_txd <= ~crc_out[15:8];
        S_FCS_2: mac_txd <= ~crc_out[23:16];
        S_FCS_3: mac_txd <= ~crc_out[31:24];

        S_IPG: mac_txd <= '0;

        default: mac_txd <= '0;
      endcase
    end
  end

endmodule

