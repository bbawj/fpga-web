module arp_decode (
  input clk,
  input rst,
  input valid,
  input [7:0] din,

  output reg [47:0] sha,
  output reg [47:0] tha,
  output reg [31:0] spa,
  output reg [31:0] tpa,
  output reg err,
  output reg done
);

reg [47:0] working = '0;
reg [7:0] counter = '0;
reg op = 0;

  always @(posedge clk) begin
    if (rst || ~valid) begin
      working <= '0;
      counter <= '0;
      op <= '0;
      sha <= '0;
      spa <= '0;
      tpa <= '0;
      err <= 0;
      done <= 0;
    end else begin
      working <= {din, working[47:8]};
      counter <= counter + 1;

      case (counter)
      // ARP Hardware Type = 1 = Ethernet
      8'd2: if (working[47:32] != 1) err <= 1;
      // ARP Protocol Type = 0x0800 = IPV4
      8'd4: if (working[47:32] != 16'h0800) err <= 1;
      8'd5: if (working[47:40] != 8'd6) err <= 1;
      8'd6: if (working[47:40] != 8'd4) err <= 1;
      // Operation 1: Request, Operation 2: Reply. Ignore replies
      8'd8: if (working[47:32] == 2) err <= 1;
      8'd14: sha <= working;
      8'd18: spa <= working[47:16];
      8'd24: tha <= working;
      8'd28: begin 
        done <= 1;
        tpa <= working[47:16];
      end
      default: begin
      end
      endcase
    end
  end

endmodule
