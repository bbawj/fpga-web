`include "utils.svh"

module arp_encode #(
  parameter [47:0] MAC_ADDR = 48'hDEADBEEFCAFE,
  parameter [31:0] IP_ADDR = 32'h69696969
  )
  (
  input clk,
  input rst,
  input en,
  input reg [47:0] tha,
  input reg [31:0] tpa,

  output reg ovalid,
  output reg [7:0] dout
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

  always @(posedge clk) begin
    if (rst) begin
      dout <= '0;
      counter <= '0;
      ovalid <= 0;
    end else begin
      if (en) begin
        if (counter == COUNT_TPA) counter <= '0;
        else counter <= counter + 1;
        // ARP Hardware Type = 1 = Ethernet
        if (counter <= COUNT_HW_TYPE - 1) begin
          dout <= `SELECT_BYTE_MSB(ARP_HW_TYPE, counter, 0);
        end
        // ARP Protocol Type = 0x0800 = IPV4
        else if (counter <= COUNT_PROT_TYPE - 1) begin
          dout <= `SELECT_BYTE_MSB(ARP_PROT_TYPE, counter, COUNT_HW_TYPE);
        end
        else if (counter <= COUNT_HW_LEN - 1) begin
          dout <= `SELECT_BYTE_MSB(ARP_HW_LEN, counter, COUNT_PROT_TYPE);
        end
        else if (counter <= COUNT_PROT_LEN - 1) begin
          dout <= `SELECT_BYTE_MSB(ARP_PROT_LEN, counter, COUNT_HW_LEN);
        end
        else if (counter <= COUNT_PROT_REPLY - 1) begin
          dout <= `SELECT_BYTE_MSB(ARP_PROT_REPLY, counter, COUNT_PROT_LEN);
        end
        // SHA, as a reply this is our device's HA
        else if (counter <= COUNT_SHA - 1) begin
          dout <= `SELECT_BYTE_MSB(MAC_ADDR, counter, COUNT_PROT_REPLY);
        end
        // SPA, our IP ADDR
        else if (counter <= COUNT_SPA - 1) begin
          dout <= `SELECT_BYTE_MSB(IP_ADDR, counter, COUNT_SHA);
        end
        else if (counter <= COUNT_THA - 1) begin
          dout <= `SELECT_BYTE_MSB(tha, counter, COUNT_SPA);
        end
        else if (counter <= COUNT_TPA - 1) begin
          dout <= `SELECT_BYTE_MSB(tpa, counter, COUNT_THA);
        end
        else begin
          dout <= '0;
        end
      end else begin
        dout <= `SELECT_BYTE_MSB(ARP_HW_TYPE, 1'b0, 0);
        counter <= 1;
      end

      if (counter == COUNT_TPA) ovalid <= 0;
      else ovalid <= 1;
    end
  end

`ifdef FORMAL
  initial	assume(rst);
  always @(posedge clk) begin
    assert (counter >= 0 && counter <= COUNT_TPA);
    if (counter == 0) assert (ovalid == 0);
    if (ovalid == 1) assert (counter != 0);
  end
`endif

endmodule
