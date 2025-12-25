`default_nettype	none
`include "utils.svh"

module top_sdram_debug(
  input wire clk_25mhz,
  input wire button,
  output wire led,
  output wire uart_tx,

    // SDRAM interface
  output wire [1:0] sdram_ba,
  output wire sdram_we_n,
  output wire sdram_cas_n,
  output wire sdram_ras_n,
  output wire sdram_clk,
  output wire [31:0] sdram_dq,
  output wire [10:0] sdram_addr
);
  wire rst;
  areset _areset(.clk(clk_25mhz), .rst_n(button), .rst(rst));

  blinky _blinky(.sysclk(clk_25mhz), .led_n(led), .rst(rst));

  reg sdram_wr_req = '0;
  wire sdram_wr_granted;
  reg [18:0] sdram_wr_ad, sdram_rd_ad;
  reg [31:0] sdram_wr_data;
  wire [31:0] sdram_rd_data;
  reg sdram_rd_req = '0;
  wire sdram_rd_valid, sdram_rd_granted;

  mem m(
    .clk(clk_25mhz),
    .rst(rst),

    .wr_req(sdram_wr_req),
    .wr_ad(sdram_wr_ad),
    .wr_data(sdram_wr_data),
    .wr_granted(sdram_wr_granted),

    .rd_req(sdram_rd_req),
    .rd_ad(sdram_rd_ad),
    .rd_valid(sdram_rd_valid),
    .rd_data(sdram_rd_data),
    .rd_granted(sdram_rd_granted),

  .sdram_ba(sdram_ba),
  .sdram_we_n(sdram_we_n),
  .sdram_cas_n(sdram_cas_n),
  .sdram_ras_n(sdram_ras_n),
  .sdram_clk(sdram_clk),
  .sdram_dq(sdram_dq),
  .sdram_addr(sdram_addr)
    );

reg uart_valid = '0;
reg [31:0] uart_data = '0;
uart #(.DATA_WIDTH(32)) _uart(
  .clk(clk_25mhz),
  .rst(rst),
  .valid(uart_valid),
  .rx(uart_data),
  .rdy(),
  .tx(uart_tx)
  );

  wire [31:0] random;

  lfsr_rng #(.DATA_WIDTH(32)) _rng(
    .clk(clk_25mhz),
    .rst(rst),
    .seed(32'hDEADBEEFCAFE),
    .dout(random)
    );

  reg init = 1'b0;
  reg [7:0] counter = 'd1;
  always @(posedge clk_25mhz) begin
    `LOG_END;
    if (rst) begin
      init <= 1'b1;
    end else begin
      if (init == 1'b1) begin
        `LOG(random);
        init <= 1'b0;
        sdram_wr_req <= 'd1;
        sdram_wr_ad <= '0;
        sdram_wr_data <= random;
        counter <= 'd1;
      end
      if (sdram_wr_granted == 'd1) begin
        sdram_rd_req <= 'd1;
        sdram_rd_ad <= '0;
        sdram_wr_req <= '0;
      end
      if (sdram_rd_granted == 'd1) begin
        sdram_rd_req <= '0;
      end
      if (sdram_rd_valid == 'd1 && counter > 'd0) begin
        `LOG(sdram_rd_data);
        counter <= counter - 1;
      end
    end
  end

endmodule
