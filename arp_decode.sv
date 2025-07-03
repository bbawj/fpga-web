module arp_decode (
  input clk,
  input rst,
  input valid,
  input [3:0] din,

  output reg [47:0] sha,
  output reg [31:0] spa,
  output reg [31:0] tpa,
  output reg err,
  output reg done
);

reg [47:0] working;
reg [7:0] counter;
reg op;

  always @(posedge clk) begin
    if (rst || ~valid) begin
      working <= '0;
      counter <= '0;
      sha <= '0;
      spa <= '0;
      done <= 0;
      err <= 0;
    end else begin
      working <= {working[27:0], din};
      counter <= counter + 1;

      case (counter)
      // ARP Hardware Type = 1 = Ethernet
      7'd4: if (working[15:0] != 1) err <= 1;
      // ARP Protocol Type = 0x0800 = IPV4
      7'd8: if (working[15:0] != 16'h0800) err <= 1;
      7'd10: if (working[7:0] != 7'd6) err <= 1;
      7'd12: if (working[7:0] != 7'd4) err <= 1;
      // Operation 1: Request, Operation 2: Reply. Ignore replies
      7'd16: if (working[15:0] == 2) err <= 1;
      7'd26: sha <= working;
      7'd34: spa <= working[31:0];
      // Target addresses ignored
      7'd54: begin 
        done <= 1;
        tpa <= working[31:0];
      end
      endcase
    end
  end

endmodule
