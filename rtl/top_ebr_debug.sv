
module top_ebr_debug (
    input  wire clk_25mhz,
    input  wire button,
    output wire uart_tx
);
  wire sysclk;
  clk_gen #(
      .SYSCLK_DIV(5),
      .TXC_DIV(5),
      .TXC_PHASE(5),
      .SPI_DIV(5),
      .SPI_PHASE(5),
      .FB_DIV(5)
  ) _clk_gen (
      .clk_in(clk_25mhz),
      .sysclk(sysclk),
      .spi_en(1'b1),
      .txc(),
      .clk_locked()
  );

  test_ebr_debug debug (
      .clk(sysclk),
      .button(button),
      .uart_tx(uart_tx)
  );
endmodule
