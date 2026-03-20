`default_nettype none
`include "utils.svh"
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

  reg [ 4:0] counter = '0;
  reg [17:0] checksum = '0;
  initial begin
    $display("Fixed fields pre-calc checksum:");
    $display(ones_comp(ones_comp(ones_comp(ones_comp(ones_comp('h0, 'h0000), 'h4006), 'h4000),
                                 'h0001), 'h4500));
  end

  always @(posedge clk) begin
    case (counter)
      'd2:
      checksum <= 18'd50439 + {2'b0, len} + {2'b0, sa[31:16]} + {2'b0, sa[15:0]}+ {2'b0, da[31:16]}+ {2'b0, da[15:0]};
      'd3: checksum <= {2'b0, checksum[15:0]} + {16'b0, checksum[17:16]};
      'd4: checksum <= {2'b0, checksum[15:0]} + {16'b0, checksum[17:16]};
      default: checksum <= checksum;
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      dout <= '0;
      done <= '0;
      counter <= '0;
    end else if (en) begin
      done <= '0;
      counter <= counter < 'd19 ? counter + 1 : counter;
      case (counter)
        'd0:  dout <= 'h45;
        'd1:  dout <= 'h00;
        'd2:  dout <= len[15:8];
        'd3:  dout <= len[7:0];
        // Identification
        'd4:  dout <= 'h00;
        'd5:  dout <= 'h01;
        // Flags + fragment offset
        'd6:  dout <= 'b01000000;
        'd7:  dout <= 'h00;
        // TTL
        'd8:  dout <= 'd64;
        // proto
        'd9:  dout <= 'h06;
        // checksum
        'd10: dout <= ~checksum[15:8];
        'd11: dout <= ~checksum[7:0];
        // source address
        'd12: dout <= sa[31:24];
        'd13: dout <= sa[23:16];
        'd14: dout <= sa[15:8];
        'd15: dout <= sa[7:0];
        // dest address
        'd16: dout <= da[31:24];
        'd17: dout <= da[23:16];
        'd18: dout <= da[15:8];
        'd19: begin
          dout <= da[7:0];
          done <= 1'b1;
        end
        default: begin
          // NO OP, wait for en de-assert
          dout <= '0;
        end
      endcase
    end else if (!en) begin
      // since the first byte is hardcoded, we can reduce 1 cycle latency by
      // holding the first byte on dout stable at all times
      dout <= 'h45;
      done <= '0;
      counter <= 'd1;
    end
  end

endmodule
