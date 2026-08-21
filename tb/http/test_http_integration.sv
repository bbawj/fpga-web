`default_nettype none
module test_http_integration #(
    parameter HTTP_CONTENT_FILE
) (
    input wire clk,
    input wire clk90,
    input wire rst,
    input wire tcp_echo_en,

    output reg [3:0] phy_txd,
    output reg phy_txctl,
    output wire phy_txc,
    input wire [3:0] phy_rxd,
    input wire phy_rxctl,
    input wire phy_rxc
);

  GSR GSR_INST (.GSR(1'b1));
  PUR PUR_INST (.PUR(1'b1));
  reg mem_ctrl_rd_req;
  reg [18:0] mem_ctrl_rd_ad;
  reg [15:0] mem_ctrl_rd_size;
  reg mem_ctrl_rd_valid;
  reg [31:0] mem_ctrl_rd_data;
  mac mac_instance (
      .clk(clk),
      .clk90(clk90),
      .rst(rst),
      .tcp_echo_en(tcp_echo_en),

      .mem_ctrl_rd_req(mem_ctrl_rd_req),
      .mem_ctrl_rd_size(mem_ctrl_rd_size),
      .mem_ctrl_rd_ad(mem_ctrl_rd_ad),
      .mem_ctrl_rd_valid(mem_ctrl_rd_valid),
      .mem_ctrl_rd_data(mem_ctrl_rd_data),

      .uart_tx  (),
      .uart_tx2 (),
      .uart_tx3 (),
      .phy_txc  (phy_txc),
      .phy_txd  (phy_txd),
      .phy_txctl(phy_txctl),

      .phy_rxd  (phy_rxd),
      .phy_rxctl(phy_rxctl),
      .phy_rxc  (phy_rxc)
  );

  // cache cache_ (
  //     .clk(clk),
  //     .rst(rst),
  //     .rd_en(mem_ctrl_rd_req),
  //     .rd_ad(mem_ctrl_rd_ad),
  //     .rd_size(mem_ctrl_rd_size),
  //     .rd_valid(mem_ctrl_rd_valid),
  //     .rd_data(mem_ctrl_rd_data),
  //
  //     .sdram_rd_valid(sdram_rd_valid),
  //     .sdram_rd_granted(sdram_rd_granted),
  //     .sdram_rd_data(sdram_rd_data),
  //     .sdram_rd_req(sdram_rd_req),
  //     .sdram_rd_ad(sdram_rd_ad)
  // );
  reg  sdram_wr_req;
  wire sdram_wr_granted;
  reg [18:0] sdram_wr_ad, sdram_rd_ad;
  reg [31:0] sdram_wr_data;
  wire [31:0] sdram_rd_data;
  reg sdram_rd_req;
  wire sdram_rd_valid, sdram_rd_granted;
  sdram_dummy #(
      .INIT(HTTP_CONTENT_FILE)
  ) m (
      .clk(clk),
      .rst(rst),

      .wr_req(sdram_wr_req),
      .wr_ad(sdram_wr_ad),
      .wr_data(sdram_wr_data),
      .wr_granted(sdram_wr_granted),

      .rd_req(mem_ctrl_rd_req),
      .rd_ad(mem_ctrl_rd_ad),
      .rd_valid(mem_ctrl_rd_valid),
      .rd_data(mem_ctrl_rd_data),
      .rd_granted(sdram_rd_granted),
      .boot_done()
  );

endmodule

