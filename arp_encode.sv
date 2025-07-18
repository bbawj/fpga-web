`include "utils.svh"

module arp_encode #(
  parameter [47:0] MAC_ADDR = '0,
  parameter [31:0] IP_ADDR = '0
  )
  (
  input clk,
  input rst,
  input en,
  input reg [47:0] tha,
  input reg [31:0] tpa,

  output reg ovalid,
  output reg [3:0] dout
);

localparam ARP_HW_TYPE = 16'h0001;
localparam ARP_PROT_TYPE = 16'h0800;
localparam ARP_HW_LEN = 8'h06;
localparam ARP_PROT_LEN = 8'h04;
localparam ARP_PROT_REPLY = 16'h0002;
reg [7:0] counter;

  always @(posedge clk or negedge clk) begin
    if (rst) begin
      dout <= '0;
      counter <= '0;
      ovalid <= 0;
    end else begin
      if (en) begin
        if (counter == 8'd56) counter <= '0;
        else counter <= counter + 1;
        // ARP Hardware Type = 1 = Ethernet
        if (counter <= 8'd3) begin
          dout <= `SELECT_NIBBLE(ARP_HW_TYPE, counter, 0);
        end
        // ARP Protocol Type = 0x0800 = IPV4
        else if (counter <= 8'd7) begin
          dout <= `SELECT_NIBBLE(ARP_PROT_TYPE, counter, 4);
        end
        else if (counter <= 8'd9) begin
          dout <= `SELECT_NIBBLE(ARP_HW_LEN, counter, 8);
        end
        else if (counter <= 8'd11) begin
          dout <= `SELECT_NIBBLE(ARP_PROT_LEN, counter, 10);
        end
        else if (counter <= 8'd15) begin
          dout <= `SELECT_NIBBLE(ARP_PROT_REPLY, counter, 12);
        end
        // SHA, as a reply this is our device's HA
        else if (counter <= 8'd27) begin
          dout <= `SELECT_NIBBLE(MAC_ADDR, counter, 16);
        end
        // SPA, our IP ADDR
        else if (counter <= 8'd35) begin
          dout <= `SELECT_NIBBLE(IP_ADDR, counter, 28);
        end
        else if (counter <= 8'd47) begin
          dout <= `SELECT_NIBBLE(tha, counter, 36);
        end
        else if (counter <= 8'd55) begin
          dout <= `SELECT_NIBBLE(tpa, counter, 48);
        end
        else begin
          dout <= '0;
        end
      end else begin
        dout <= `SELECT_NIBBLE(ARP_HW_TYPE, 0, 0);
        counter <= 1;
      end

      if (counter == 8'd56) ovalid <= 0;
      else ovalid <= 1;
    end
  end

endmodule
