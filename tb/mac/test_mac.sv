module test_mac (
    input wire clk,
    input wire clk90,
    input wire rst,

    output reg [3:0] phy_txd,
    output reg phy_txctl,
    output wire phy_txc,
    input wire [3:0] phy_rxd,
    input wire phy_rxctl,
    input wire phy_rxc
);

  mac mac_instance (
      .clk(clk),
      .clk90(clk90),
      .rst(rst),
      .led(),
      .tcp_echo_en(1'b0),

      .mem_ctrl_rd_req(),
      .mem_ctrl_rd_size(),
      .mem_ctrl_rd_granted(),
      .mem_ctrl_rd_ad(),
      .mem_ctrl_rd_valid(),
      .mem_ctrl_rd_data(),

      .uart_tx  (),
      .phy_txc  (phy_txc),
      .phy_txd  (phy_txd),
      .phy_txctl(phy_txctl),

      .phy_rxd  (phy_rxd),
      .phy_rxctl(phy_rxctl),
      .phy_rxc  (phy_rxc)
  );

endmodule
