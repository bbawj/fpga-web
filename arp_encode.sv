module arp_encode #(
  parameter [47:0] MAC_ADDR = '0
  parameter [31:0] IP_ADDR = '0
  )
  (
  input clk,
  input rst,
  input valid,
  input reg [47:0] tha,
  input reg [31:0] tpa,

  output reg ovalid,
  output reg [3:0] dout,
);

reg [7:0] counter;

  always @(posedge clk) begin
    if (rst || ~valid) begin
      counter <= '0;
      dout <= '0;
      ovalid <= 0;
    end else begin
      working <= {working[27:0], din};
      counter <= counter + 1;
      ovalid <= 1;

      case (counter)
      // ARP Hardware Type = 1 = Ethernet
      8'd0: dout <= 4'h0;
      8'd1: dout <= 4'h0;
      8'd2: dout <= 4'h0;
      8'd3: dout <= 4'h1;
      // ARP Protocol Type = 0x0800 = IPV4
      8'd4: dout <= 4'h0;
      8'd5: dout <= 4'h8;
      8'd6: dout <= 4'h0;
      8'd7: dout <= 4'h0;
      // Hardware len
      8'd8: dout <= 4'h0;
      8'd9: dout <= 4'h6;
      // Protocol len
      8'd10: dout <= 4'h0;
      8'd11: dout <= 4'h4;
      // Op = reply
      8'd12: dout <= 4'h0;
      8'd13: dout <= 4'h0;
      8'd14: dout <= 4'h0;
      8'd15: dout <= 4'h2;
      // SHA, as a reply this is our device's HA
      8'd16: dout <= MAC_ADDR[47:44];
      8'd17: dout <= MAC_ADDR[43:40];
      8'd18: dout <= MAC_ADDR[39:36];
      8'd19: dout <= MAC_ADDR[35:32];
      8'd20: dout <= MAC_ADDR[31:28];
      8'd21: dout <= MAC_ADDR[27:24];
      8'd22: dout <= MAC_ADDR[23:20];
      8'd23: dout <= MAC_ADDR[19:16];
      8'd24: dout <= MAC_ADDR[15:12];
      8'd25: dout <= MAC_ADDR[11:8];
      8'd26: dout <= MAC_ADDR[7:4];
      8'd27: dout <= MAC_ADDR[3:0];
      // SPA, our IP ADDR
      8'd28: dout <= IP_ADDR[31:28];
      8'd29: dout <= IP_ADDR[27:24];
      8'd30: dout <= IP_ADDR[23:20];
      8'd31: dout <= IP_ADDR[19:16];
      8'd32: dout <= IP_ADDR[15:12];
      8'd33: dout <= IP_ADDR[11:8];
      8'd34: dout <= IP_ADDR[7:4];
      8'd35: dout <= IP_ADDR[3:0];
      // THA
      8'd36: dout <= tha[47:44];
      8'd37: dout <= tha[43:40];
      8'd38: dout <= tha[39:36];
      8'd39: dout <= tha[35:32];
      8'd40: dout <= tha[31:28];
      8'd41: dout <= tha[27:24];
      8'd42: dout <= tha[23:20];
      8'd43: dout <= tha[19:16];
      8'd44: dout <= tha[15:12];
      8'd45: dout <= tha[11:8];
      8'd46: dout <= tha[7:4];
      8'd47: dout <= tha[3:0];
      // TPA
      8'd48: dout <= tpa[31:28];
      8'd49: dout <= tpa[27:24];
      8'd50: dout <= tpa[23:20];
      8'd51: dout <= tpa[19:16];
      8'd52: dout <= tpa[15:12];
      8'd53: dout <= tpa[11:8];
      8'd54: dout <= tpa[7:4];
      8'd55: dout <= tpa[3:0];
      default: begin
        counter <= '0;
        dout <= '0;
        ovalid <= 0;
      end
      endcase
    end
  end

endmodule
