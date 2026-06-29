`default_nettype none
`include "utils.svh"

module top_flash_sdram_debug (
    input wire clk_25mhz,
    input wire button,
    output wire led,
    output wire uart_tx,
    input flash_miso,
    output flash_cs,
    output flash_mosi,

    // SDRAM interface
    output wire [1:0] sdram_ba,
    output wire sdram_we_n,
    output wire sdram_cas_n,
    output wire sdram_ras_n,
    output wire sdram_clk,
    inout [31:0] sdram_dq,
    output wire [10:0] sdram_addr
);
  parameter reg [23:0] NUM_BYTES = 80;
  wire sysclk, sysclk90;
  wire spiclk, spi_clken;
  reg pll_locked;
  clk_gen #(
      .SYSCLK_DIV(5),
      .TXC_DIV(5),
      .TXC_PHASE(5),
      .SPI_DIV(5),
      .SPI_PHASE(7),
      .FB_DIV(5)
  ) clk_gen (
      .clk_in(clk_25mhz),

      .sysclk(sysclk),
      .spi_en(1'b1),
      .spi(spiclk),
      .clk_locked(pll_locked)
  );

  USRMCLK u1 (
      .USRMCLKI (spiclk),
      .USRMCLKTS(~pll_locked)
  );

  reg spi_en, spi_data_valid;
  reg [7:0] spi_data;
  localparam reg [23:0] OFFSET_IN_FLASH = 'h40000;
  spi_master spi (
      .clk(sysclk),
      .spi_sclk(spiclk),
      .spi_miso(flash_miso),
      .spi_cs(flash_cs),
      .spi_mosi(flash_mosi),
      .spi_clken(spi_clken),
      .rst(~pll_locked),
      .i_en(spi_en),
      .i_size(NUM_BYTES),
      .i_inst(8'h03),
      .i_offset(OFFSET_IN_FLASH),
      .i_addr_en('1),
      .o_data_valid(spi_data_valid),
      .o_data(spi_data)
  );

  reg lock_pulse;
  pulse_gen pulse (
      .clk(sysclk),
      .rst('0),
      .sig(pll_locked && sdram_ready),
      .q  (lock_pulse)
  );
  delay #(
      .WIDTH(1),
      .DEPTH(10)
  ) del (
      .clk(sysclk),
      .rst('0),
      .data_in(lock_pulse),
      .data_out(spi_en)
  );

  reg flash_done, spi_ready;
  reg [31:0] spi_32;
  flash2sdram #(
      .NUM_BYTES(NUM_BYTES)
  ) f2s (
      .clk(sysclk),
      .rst(~pll_locked),
      .readback(1'b1),
      .spi_data_valid(spi_data_valid),
      .spi_data(spi_data),
      .sdram_wr_granted(sdram_wr_granted),
      .sdram_wr_req(sdram_wr_req),
      .sdram_wr_ad(sdram_wr_ad),
      .sdram_wr_data(sdram_wr_data),
      .sdram_rd_granted(sdram_rd_granted),
      .sdram_rd_req(sdram_rd_req),
      .sdram_rd_ad(sdram_rd_ad),
      .spi_ready(spi_ready),
      .spi_32(spi_32),
      .done(flash_done)
  );

  reg sdram_wr_req, sdram_ready;
  wire sdram_wr_granted;
  reg [18:0] sdram_wr_ad, sdram_rd_ad;
  reg [31:0] sdram_wr_data;
  wire [31:0] sdram_rd_data;
  reg sdram_rd_req;
  wire sdram_rd_valid, sdram_rd_granted;

  sdram_ctrl #(
      .FREQ(125_000_000)
  ) m (
      .clk(sysclk),
      .rst(~pll_locked),

      .wr_req(sdram_wr_req),
      .wr_ad(sdram_wr_ad),
      .wr_data(sdram_wr_data),
      .wr_granted(sdram_wr_granted),

      .rd_req(sdram_rd_req),
      .rd_ad(sdram_rd_ad),
      .rd_valid(sdram_rd_valid),
      .rd_data(sdram_rd_data),
      .rd_granted(sdram_rd_granted),

      .boot_done(sdram_ready),

      .sdram_ba(sdram_ba),
      .sdram_we_n(sdram_we_n),
      .sdram_cas_n(sdram_cas_n),
      .sdram_ras_n(sdram_ras_n),
      .sdram_clk(sdram_clk),
      .sdram_dq(sdram_dq),
      .sdram_addr(sdram_addr)
  );

  reg sdram_rd_valid_d;
  always @(posedge sysclk) begin
    sdram_rd_valid_d <= sdram_rd_valid;
  end

  // reg uart_valid = '0;
  // reg [31:0] uart_data = '0;
  uart #(
      .FREQ(125_000_000),
      .DATA_WIDTH(32),
      .BUF_USE_BLOCKRAM(1)
  ) _uart (
      .clk(sysclk),
      .rst(~pll_locked),
      .valid(spi_ready || ((~sdram_rd_valid_d) && sdram_rd_valid)),
      .rx(spi_ready ? spi_32 : sdram_rd_data),
      .rdy(),
      .tx(uart_tx)
  );

endmodule
