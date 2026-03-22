`include "utils.svh"

module arp_encode #(
    parameter [47:0] MAC_ADDR = 48'hDEADBEEFCAFE,
    parameter [31:0] IP_ADDR  = 32'h69696969
) (
    input clk,
    input rst,
    input en,
    input reg [47:0] tha,
    input reg [31:0] tpa,

    output reg done,
    /* verilator lint_off WIDTHTRUNC */
    output reg [7:0] dout
    /* verilator lint_on WIDTHEXPAND */
    /* verilator lint_on WIDTHTRUNC */
);

  localparam ARP_HW_TYPE = 16'h0001;
  localparam ARP_PROT_TYPE = 16'h0800;
  localparam ARP_HW_LEN = 8'h06;
  localparam ARP_PROT_LEN = 8'h04;
  localparam ARP_PROT_REPLY = 16'h0002;
  reg [7:0] counter;

`ifdef SPEED_100M
  localparam [7:0] COUNT_HW_TYPE = 8'd4;
  localparam [7:0] COUNT_PROT_TYPE = 8'd8;
  localparam [7:0] COUNT_HW_LEN = 8'd10;
  localparam [7:0] COUNT_PROT_LEN = 8'd12;
  localparam [7:0] COUNT_PROT_REPLY = 8'd16;
  localparam [7:0] COUNT_SHA = 8'd28;
  localparam [7:0] COUNT_SPA = 8'd36;
  localparam [7:0] COUNT_THA = 8'd48;
  localparam [7:0] COUNT_TPA = 8'd56;
`else
  localparam [7:0] COUNT_HW_TYPE = 8'd2;
  localparam [7:0] COUNT_PROT_TYPE = 8'd4;
  localparam [7:0] COUNT_HW_LEN = 8'd5;
  localparam [7:0] COUNT_PROT_LEN = 8'd6;
  localparam [7:0] COUNT_PROT_REPLY = 8'd8;
  localparam [7:0] COUNT_SHA = 8'd14;
  localparam [7:0] COUNT_SPA = 8'd18;
  localparam [7:0] COUNT_THA = 8'd24;
  localparam [7:0] COUNT_TPA = 8'd28;
`endif

  typedef enum logic [7:0] {
    S_IDLE,
    S_HW_TYPE_0,    // 0x00
    S_HW_TYPE_1,    // 0x01
    S_PROT_TYPE_0,  // 0x08
    S_PROT_TYPE_1,  // 0x00
    S_HW_LEN,       // 0x06
    S_PROT_LEN,     // 0x04
    S_OP_0,         // 0x00
    S_OP_1,         // 0x02
    S_SHA_0,
    S_SHA_1,
    S_SHA_2,
    S_SHA_3,
    S_SHA_4,
    S_SHA_5,
    S_SPA_0,
    S_SPA_1,
    S_SPA_2,
    S_SPA_3,
    S_THA_0,
    S_THA_1,
    S_THA_2,
    S_THA_3,
    S_THA_4,
    S_THA_5,
    S_TPA_0,
    S_TPA_1,
    S_TPA_2,
    S_TPA_3
  } state_t;

  state_t       state;
  state_t       next_state;
  logic   [7:0] next_dout;
  logic         next_done;

  always_comb begin
    next_state = state;

    case (state)
      S_HW_TYPE_1: begin
        next_state = S_PROT_TYPE_0;
        next_dout  = ARP_HW_TYPE[7:0];
      end
      S_PROT_TYPE_0: begin
        next_state = S_PROT_TYPE_1;
        next_dout  = ARP_PROT_TYPE[15:8];
      end
      S_PROT_TYPE_1: begin
        next_state = S_HW_LEN;
        next_dout  = ARP_PROT_TYPE[7:0];
      end
      S_HW_LEN: begin
        next_state = S_PROT_LEN;
        next_dout  = ARP_HW_LEN;
      end
      S_PROT_LEN: begin
        next_state = S_OP_0;
        next_dout  = ARP_PROT_LEN;
      end
      S_OP_0: begin
        next_state = S_OP_1;
        next_dout  = ARP_PROT_REPLY[15:8];
      end
      S_OP_1: begin
        next_state = S_SHA_0;
        next_dout  = ARP_PROT_REPLY[7:0];
      end
      S_SHA_0: begin
        next_state = S_SHA_1;
        next_dout  = MAC_ADDR[47:40];
      end
      S_SHA_1: begin
        next_state = S_SHA_2;
        next_dout  = MAC_ADDR[39:32];
      end
      S_SHA_2: begin
        next_state = S_SHA_3;
        next_dout  = MAC_ADDR[31:24];
      end
      S_SHA_3: begin
        next_state = S_SHA_4;
        next_dout  = MAC_ADDR[23:16];
      end
      S_SHA_4: begin
        next_state = S_SHA_5;
        next_dout  = MAC_ADDR[15:8];
      end
      S_SHA_5: begin
        next_state = S_SPA_0;
        next_dout  = MAC_ADDR[7:0];
      end
      S_SPA_0: begin
        next_state = S_SPA_1;
        next_dout  = IP_ADDR[31:24];
      end
      S_SPA_1: begin
        next_state = S_SPA_2;
        next_dout  = IP_ADDR[23:16];
      end
      S_SPA_2: begin
        next_state = S_SPA_3;
        next_dout  = IP_ADDR[15:8];
      end
      S_SPA_3: begin
        next_state = S_THA_0;
        next_dout  = IP_ADDR[7:0];
      end
      S_THA_0: begin
        next_state = S_THA_1;
        next_dout  = tha[47:40];
      end
      S_THA_1: begin
        next_state = S_THA_2;
        next_dout  = tha[39:32];
      end
      S_THA_2: begin
        next_state = S_THA_3;
        next_dout  = tha[31:24];
      end
      S_THA_3: begin
        next_state = S_THA_4;
        next_dout  = tha[23:16];
      end
      S_THA_4: begin
        next_state = S_THA_5;
        next_dout  = tha[15:8];
      end
      S_THA_5: begin
        next_state = S_TPA_0;
        next_dout  = tha[7:0];
      end
      S_TPA_0: begin
        next_state = S_TPA_1;
        next_dout  = tpa[31:24];
      end
      S_TPA_1: begin
        next_state = S_TPA_2;
        next_dout  = tpa[23:16];
      end
      S_TPA_2: begin
        next_state = S_TPA_3;
        next_dout  = tpa[15:8];
      end
      S_TPA_3: begin
        next_state = S_HW_TYPE_1;
        next_dout  = tpa[7:0];
      end
      default: begin
        next_state = S_HW_TYPE_1;
        next_dout  = 8'h00;
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= S_HW_TYPE_1;
      dout  <= '0;
      done  <= 1'b0;
    end else begin
      state <= en ? next_state : S_HW_TYPE_1;
      dout  <= en ? next_dout : ARP_HW_TYPE[15:8];
      done  <= state == S_TPA_3;
    end
  end


`ifdef FORMAL
  initial assume (rst);
  always @(posedge clk) begin
    assert (counter >= 0 && counter <= COUNT_TPA);
    if (counter == 0) assert (done == 0);
    if (done == 1) assert (counter != 0);
  end
`endif

endmodule
