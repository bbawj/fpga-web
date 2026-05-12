module test_http_integration #(
    parameter string HTTP_ADDR_FILE,
    parameter string HTTP_SIZE_FILE,
    parameter string HTTP_CONTENT_FILE
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
  mac #(
      .HTTP_ADDR_FILE(HTTP_ADDR_FILE),
      .HTTP_SIZE_FILE(HTTP_SIZE_FILE)
  ) mac_instance (
      .clk(clk),
      .clk90(clk90),
      .rst(rst),
      .led(),
      .tcp_echo_en(tcp_echo_en),

      .mem_ctrl_rd_req(sdram_rd_req),
      .mem_ctrl_rd_size(),
      .mem_ctrl_rd_granted(sdram_rd_granted),
      .mem_ctrl_rd_ad(sdram_rd_ad),
      .mem_ctrl_rd_valid(sdram_rd_valid),
      .mem_ctrl_rd_data(sdram_rd_data),

      .uart_tx  (),
      .phy_txc  (phy_txc),
      .phy_txd  (phy_txd),
      .phy_txctl(phy_txctl),

      .phy_rxd  (phy_rxd),
      .phy_rxctl(phy_rxctl),
      .phy_rxc  (phy_rxc)
  );

  // reg [18:0] start_addr, counter, size_counter;
  // reg [1:0] state = 0;
  // always @(posedge clk) begin
  //   case (state)
  //     0:
  //     if (mem_ctrl_rd_req) begin
  //       state <= 1;
  //       start_addr <= mem_ctrl_rd_ad;
  //       size_counter <= mem_ctrl_rd_size;
  //       counter <= 0;
  //     end
  //     1: begin
  //       counter <= counter + 1;
  //       sdram_rd_req <= 1;
  //       sdram_rd_ad <= start_addr + counter;
  //       state <= 2;
  //     end
  //     2: begin
  //       if (sdram_rd_granted) begin
  //         sdram_rd_req <= 0;
  //         state <= (counter == size_counter) ? 3 : 1;
  //       end
  //     end
  //     default: state <= 0;
  //   endcase
  // end

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

      .rd_req(sdram_rd_req),
      .rd_ad(sdram_rd_ad),
      .rd_valid(sdram_rd_valid),
      .rd_data(sdram_rd_data),
      .rd_granted(sdram_rd_granted)
  );

endmodule

