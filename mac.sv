`define LOOPBACK
module mac ( 
    input wire clk_25mhz,
    input wire rst,
    
    // Shared PHY control
    output reg phy_rst_b,
    output reg mdc,
    inout wire mdio,
    
    // PHY0 MII Interface
    output reg [3:0] phy0_txd,
    output reg phy0_txctl,
    output wire phy0_txc,
    input wire [3:0] phy0_rxd,
    input wire phy0_rxctl,
    input wire phy0_rxc
);
assign phy0_txc = clk_25mhz;

`ifdef LOOPBACK
  reg [3:0] rxd_temp;
  reg rxctl_temp;
  always @(posedge phy0_rxc) begin
    rxd_temp <= phy0_rxd;
    rxctl_temp <= phy0_rxctl;
  end
  always @(posedge clk_25mhz) begin
    phy0_txd <= rxd_temp;
    phy0_txctl <= rxctl_temp;
  end
`else
clk_divider #(.RATIO(10)) clk_2p5 (.clk_in(clk_25mhz), .rst(rst), .clk_out(phy0_txc));
mii_rcv _mii_rcv(.clk(phy0_rxc), .data(phy0_rxd), .rxctl(phy0_rxctl), .ip_valid(ip_valid));
`endif

endmodule

