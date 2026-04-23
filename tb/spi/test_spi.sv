module test_spi (
    input  wire clk,
    input  wire sclk,
    input  wire miso,
    output wire cs,
    output wire mosi,
    output wire clken,

    input rst,
    input i_en,
    input [23:0] i_size,
    input [23:0] i_addr,
    output reg [7:0] o_data,
    output reg o_valid
);
  spi_master master (
      .clk(clk),
      .spi_sclk(sclk),
      .spi_miso(miso),
      .spi_cs(cs),
      .spi_mosi(mosi),
      .spi_clken(clken),

      .rst(rst),
      .i_en(i_en),
      .i_size(i_size),
      .i_addr(i_addr),

      .o_data_valid(o_valid),
      .o_data(o_data)
  );
endmodule
