module rgmii_phy_if #(
  parameter [47:0] MAC_ADDR
  )(
  input wire clk,
  input wire rst,
  input wire din_done,
  input reg [47:0] mac_dest,

  output wire send_next,
  output reg [3:0] dout
);

reg [11:0] counter;
localparam [15:0] ethertype = 16'h1536;

// e.g. SELECT_NIBBLE(MAC_ADDR, 28, 16) will expand to MAC_ADDR[43:40]. This
// is for choosing the nibbles in least significant order in a byte
`define SELECT_NIBBLE(data, end_count, start_count)
   (start_count % 2 == 0) ? data[4*((end_count) - (start_count) - 1) - 1 -: 4] :
     data[4*((end_count) - (start_count)) - 1 -: 4];

reg [3:0] ipg_counter;

always @(posedge clk) begin
  if (rst) begin
    counter <= '0;
    ipg_counter <= '0;
  end else begin
    counter <= counter + 1;
    case (counter)
      // Preamble 7 bytes of b1010
      if (counter < 8'd15) dout <= 4'b1010;
      // SFD nibble of b1011
      else if (counter < 8'd16) dout <= 4'b1011;
      // MAC dest 12 nibbles
      else if (counter < 8'd28) dout <= SELECT_NIBBLE(MAC_ADDR, 28, counter);
      // MAC target 12 nibbles
      else if (counter < 8'd40) dout <= SELECT_NIBBLE(mac_dest, 40, counter);
      // Ethertype 4 nibbles
      else if (counter < 8'd44) begin
        dout <= SELECT_NIBBLE(ethertype, 44, counter);
        if (counter == 8'd43) send_next <= 1;
      end
      else if (counter < 11'd3000) begin
        if (din_done) begin
          if (counter - (7 + 1 + 6 + 6 + 2) * 2 < 84) dout <= 4'b0000;
          else dout <= fcs;
        end
      end
    endcase
  end
end

endmodule
