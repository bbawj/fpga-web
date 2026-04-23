`default_nettype none

module top_spi_debug (
    input wire clk_25mhz,
    input wire button,
    input flash_miso,
    output flash_cs,
    output flash_mosi,
    output wire uart_tx
);
  wire sysclk;
  wire spiclk, spi_clken;
  reg pll_locked;
  clk_gen #(
      .SYSCLK_DIV(5),
      .TXC_DIV(5),
      .TXC_PHASE(5),
      .SPI_DIV(5),
      .SPI_PHASE(5),
      .FB_DIV(5)
  ) _clk_gen (
      .clk_in(clk_25mhz),
      .spi_en(spi_clken),

      .sysclk(sysclk),
      .txc(spiclk),
      .clk_locked(pll_locked)
  );

  USRMCLK u1 (
      .USRMCLKI (spiclk),
      .USRMCLKTS(~pll_locked)
  );

  reg uart_valid;
  reg [7:0] uart_data;
  uart #(
      .DATA_WIDTH(8)
  ) _uart (
      .clk(sysclk),
      .rst(~pll_locked),
      .valid(uart_valid),
      .rx(uart_data),
      .rdy(),
      .tx(uart_tx)
  );

  reg i_en, lock_pulse;
  pulse_gen pulse (
      .clk(sysclk),
      .sig(pll_locked),
      .q  (lock_pulse)
  );
  delay #(
      .WIDTH(1),
      .DEPTH(10)
  ) del (
      .clk(sysclk),
      .rst(0),
      .data_in(lock_pulse),
      .data_out(i_en)
  );

  spi_master spi (
      .clk(sysclk),
      .spi_sclk(spiclk),
      .spi_miso(flash_miso),
      .spi_cs(flash_cs),
      .spi_mosi(flash_mosi),
      .spi_clken(spi_clken),
      .rst(~pll_locked),
      .i_en(i_en),
      .i_size(3),
      .i_addr('0),
      .o_data_valid(uart_valid),
      .o_data(uart_data)
  );
endmodule
