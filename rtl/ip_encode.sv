`default_nettype none
/*
* When en is true, provide the IP header 1 byte per clock cycle. When done,
* ovalid is asserted.
*/
module ip_encode (
    input wire clk,
    input wire rst,
    input wire en,

    input reg [31:0] sa,
    input reg [31:0] da,
    input reg [15:0] len,
    output reg done,
    output reg [7:0] dout
);

  reg [17:0] checksum = '0;
  initial begin
    $display("Fixed fields pre-calc checksum:");
    $display(utils::ones_comp(utils::ones_comp(utils::ones_comp(
                                               utils::ones_comp(utils::ones_comp('h0, 'h0000),
                                                                'h4006), 'h4000), 'h0001), 'h4500));
  end

  typedef enum {
    DSCP,
    LEN_1,
    LEN_2,
    ID_1,
    ID_2,
    FLAGS_1,
    FLAGS_2,
    TTL,
    PROT,
    CHECKSUM_1,
    CHECKSUM_2,
    SRC_1,
    SRC_2,
    SRC_3,
    SRC_4,
    DEST_1,
    DEST_2,
    DEST_3,
    DEST_4
  } state_t;
  state_t state = DSCP, next_state;
  always_comb begin
    next_state = state;
    case (state)
      DSCP:       next_state = LEN_1;
      LEN_1:      next_state = LEN_2;
      LEN_2:      next_state = ID_1;
      ID_1:       next_state = ID_2;
      ID_2:       next_state = FLAGS_1;
      FLAGS_1:    next_state = FLAGS_2;
      FLAGS_2:    next_state = TTL;
      TTL:        next_state = PROT;
      PROT:       next_state = CHECKSUM_1;
      CHECKSUM_1: next_state = CHECKSUM_2;
      CHECKSUM_2: next_state = SRC_1;
      SRC_1:      next_state = SRC_2;
      SRC_2:      next_state = SRC_3;
      SRC_3:      next_state = SRC_4;
      SRC_4:      next_state = DEST_1;
      DEST_1:     next_state = DEST_2;
      DEST_2:     next_state = DEST_3;
      DEST_3:     next_state = DEST_4;
      DEST_4:     next_state = DEST_4;  // hold; en de-assert resets
      default:    next_state = DSCP;
    endcase
  end

  always @(posedge clk) begin
    case (state)
      DSCP: checksum <= 18'd50439;
      LEN_1: checksum <= checksum + {2'b0, len};
      LEN_2: checksum <= checksum + {2'b0, sa[31:16]};
      ID_1: checksum <= checksum + {2'b0, sa[15:0]};
      ID_2: checksum <= checksum + {2'b0, da[31:16]};
      FLAGS_1: checksum <= checksum + {2'b0, da[15:0]};
      FLAGS_2: checksum <= {2'b0, checksum[15:0]} + {16'b0, checksum[17:16]};
      TTL: checksum <= {2'b0, checksum[15:0]} + {16'b0, checksum[17:16]};
      default: checksum <= checksum;
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      done <= 0;
    end else done <= state == DEST_4;
  end

  always @(posedge clk) begin
    if (rst) begin
      dout  <= '0;
      state <= DSCP;
    end else begin
      state <= en ? next_state : DSCP;
      case (state)
        DSCP: dout <= en ? 'h00 : 'h45;
        LEN_1: dout <= len[15:8];
        LEN_2: dout <= len[7:0];
        // Identification
        ID_1: dout <= 'h00;
        ID_2: dout <= 'h01;
        // Flags + fragment offset
        FLAGS_1: dout <= 'b01000000;
        FLAGS_2: dout <= 'h00;
        TTL: dout <= 'd64;
        PROT: dout <= 'h06;
        // checksum
        CHECKSUM_1: dout <= ~checksum[15:8];
        CHECKSUM_2: dout <= ~checksum[7:0];
        // source address
        SRC_1: dout <= sa[31:24];
        SRC_2: dout <= sa[23:16];
        SRC_3: dout <= sa[15:8];
        SRC_4: dout <= sa[7:0];
        // dest address
        DEST_1: dout <= da[31:24];
        DEST_2: dout <= da[23:16];
        DEST_3: dout <= da[15:8];
        DEST_4: begin
          dout <= da[7:0];
        end
        default: begin
          // NO OP, wait for en de-assert
          dout <= '0;
        end
      endcase
    end
  end

endmodule
