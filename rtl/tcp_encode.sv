`default_nettype none
`include "utils.svh"

module tcp_encode #(
    parameter logic [15:0] MY_TCP_PORT = 'd8080
) (
    input en,
    input clk,
    input rst,
    // used for IP pseudo header in TCP checksum calc
    input [31:0] ip_sa,
    input [31:0] ip_da,
    input [15:0] tcp_len,

    input [15:0] dest_port,
    input [31:0] sequence_num,
    input [31:0] ack_num,
    input [ 7:0] flags,
    input [15:0] window,
    input [15:0] initial_checksum,

    output reg done,
    output reg [7:0] dout
);

  reg [17:0] checksum = '0;
  reg [15:0] working = '0;
  reg [15:0] counter = '0;

  typedef enum {
    SRC_1,
    SRC_2,
    DEST_1,
    DEST_2,
    SEQ_1,
    SEQ_2,
    SEQ_3,
    SEQ_4,
    ACK_1,
    ACK_2,
    ACK_3,
    ACK_4,
    OFS,
    FLAGS,
    WNDW_1,
    WNDW_2,
    CHECKSUM_1,
    CHECKSUM_2,
    URG_1,
    URG_2
  } state_t;

  state_t state, next_state;
  reg [7:0] next_dout;
  reg next_done;

  always_comb begin
    next_state = state;
    next_done  = '0;
    case (state)
      SRC_1: begin
        next_state = SRC_2;
        next_dout  = MY_TCP_PORT[7:0];
      end
      SRC_2: begin
        next_state = DEST_1;
        next_dout  = dest_port[15:8];
      end
      DEST_1: begin
        next_state = DEST_2;
        next_dout  = dest_port[7:0];
      end
      DEST_2: begin
        next_state = SEQ_1;
        next_dout  = sequence_num[31:24];
      end
      SEQ_1: begin
        next_state = SEQ_2;
        next_dout  = sequence_num[23:16];
      end
      SEQ_2: begin
        next_state = SEQ_3;
        next_dout  = sequence_num[15:8];
      end
      SEQ_3: begin
        next_state = SEQ_4;
        next_dout  = sequence_num[7:0];
      end
      SEQ_4: begin
        next_state = ACK_1;
        next_dout  = ack_num[31:24];
      end
      ACK_1: begin
        next_state = ACK_2;
        next_dout  = ack_num[23:16];
      end
      ACK_2: begin
        next_state = ACK_3;
        next_dout  = ack_num[15:8];
      end
      ACK_3: begin
        next_state = ACK_4;
        next_dout  = ack_num[7:0];
      end
      ACK_4: begin
        next_state = OFS;
        next_dout  = 8'h50;
      end
      OFS: begin
        next_state = FLAGS;
        next_dout  = flags;
      end
      FLAGS: begin
        next_state = WNDW_1;
        next_dout  = window[15:8];
      end
      WNDW_1: begin
        next_state = WNDW_2;
        next_dout  = window[7:0];
      end
      WNDW_2: begin
        next_state = CHECKSUM_1;
        next_dout  = ~checksum[15:8];
      end
      CHECKSUM_1: begin
        next_state = CHECKSUM_2;
        next_dout  = ~checksum[7:0];
      end
      CHECKSUM_2: begin
        next_state = URG_1;
        next_dout  = '0;
      end
      URG_1: begin
        next_state = URG_2;
        next_dout  = '0;
      end
      URG_2: begin
        next_state = URG_2;
        next_dout  = '0;
        next_done  = 1;
      end
      default: begin
        next_state = URG_2;
        next_dout  = '0;
      end
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      state <= SRC_1;
      dout  <= '0;
    end else begin
      state <= en ? next_state : SRC_1;
      dout <= en ? next_dout : MY_TCP_PORT[15:8];
      working <= {working[7:0], next_dout};
      done <= next_done;
    end
  end

  always @(posedge clk) begin
    case (state)
      SRC_1: checksum <= en ? {2'b0, MY_TCP_PORT} : {2'b0, initial_checksum};
      DEST_2, SEQ_2, SEQ_4, ACK_2, ACK_4, FLAGS, WNDW_2: checksum <= checksum + {2'b0, working};
      DEST_1: checksum <= checksum + {2'b0, ip_da[15:0]};
      SEQ_1: checksum <= checksum + {2'b0, ip_da[31:16]};
      SEQ_3: checksum <= checksum + {2'b0, ip_sa[31:16]};
      ACK_1: checksum <= checksum + {2'b0, ip_sa[15:0]};
      ACK_3: checksum <= checksum + {2'b0, tcp_len};
      OFS: checksum <= checksum + {18'd6};
      WNDW_1: begin
        logic [17:0] sum;
        sum = {2'b0, checksum[15:0]} + {16'b0, checksum[17:16]};
        sum = {2'b0, sum[15:0]} + {16'b0, sum[17:16]};
        checksum <= {2'b0, sum[15:0]};
      end
      CHECKSUM_1, CHECKSUM_2, URG_1, URG_2: begin
      end
    endcase
  end
endmodule
