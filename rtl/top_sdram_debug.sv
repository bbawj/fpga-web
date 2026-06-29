`default_nettype none
`include "utils.svh"

module top_sdram_debug (
    input  wire clk_25mhz,
    input  wire button,
    output wire led,
    output wire uart_tx,

    // SDRAM interface
    output wire [1:0] sdram_ba,
    output wire sdram_we_n,
    output wire sdram_cas_n,
    output wire sdram_ras_n,
    output wire sdram_clk,
    inout wire [31:0] sdram_dq,
    output wire [10:0] sdram_addr
);
  wire rst, sysclk, pll_locked;
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
      .spi(),
      .clk_locked(pll_locked)
  );

  reg  sdram_wr_req = '0;
  wire sdram_wr_granted;
  reg [18:0] sdram_wr_ad, sdram_rd_ad;
  reg [31:0] sdram_wr_data;
  wire [31:0] sdram_rd_data;
  reg sdram_rd_req = '0;
  wire sdram_rd_valid, sdram_rd_granted;

  sdram_ctrl m (
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

      .sdram_ba(sdram_ba),
      .sdram_we_n(sdram_we_n),
      .sdram_cas_n(sdram_cas_n),
      .sdram_ras_n(sdram_ras_n),
      .sdram_clk(sdram_clk),
      .sdram_dq(sdram_dq),
      .sdram_addr(sdram_addr)
  );

  reg uart_valid, uart_rdy;
  reg [31:0] uart_data = '0;
  uart #(
      .FREQ(125_000_000),
      .BUF_USE_BLOCKRAM(1),
      .DATA_WIDTH(32)
  ) _uart (
      .clk(sysclk),
      .rst(~pll_locked),
      .valid(uart_valid),
      .rx(uart_data),
      .rdy(uart_rdy),
      .tx(uart_tx)
  );

  reg init = 1'b0;
  reg [31:0] counter, read_counter;
  reg [ 1:0] state;

  reg [31:0] random;
  lfsr_rng #(
      .DATA_WIDTH(32)
  ) rng (
      .clk (sysclk),
      .rst (~pll_locked),
      .seed(32'hCAFEBABE),
      .dout(random)
  );

  always @(posedge sysclk) begin
    uart_valid <= 0;
    if (~pll_locked) begin
      counter <= 0;
      read_counter <= 0;
      sdram_rd_ad <= 0;
      sdram_wr_ad <= 0;
      state <= 0;
    end else begin
      case (state)
        0: begin
          sdram_wr_req  <= counter < 'd20;
          sdram_wr_data <= counter;
          if (sdram_wr_granted) begin
            sdram_wr_req <= 0;
            sdram_wr_ad <= sdram_wr_ad + 1'b1;
            counter <= counter + 1;
            // uart_valid <= 1;
            // uart_data <= sdram_wr_data;
          end else if (read_counter < 'd20 && counter == 'd20) begin
            state <= 1;
          end
        end
        1: begin
          sdram_rd_req <= 1;
          if (sdram_rd_granted) begin
            sdram_rd_req <= 0;
            state <= 2;
            read_counter <= read_counter + 1;
          end
        end
        2: begin
          if (sdram_rd_valid) begin
            uart_valid <= 1;
            uart_data <= sdram_rd_data;
            sdram_rd_ad <= sdram_rd_ad + 1'b1;
            state <= (read_counter >= 'd20) ? 0 : 1;
          end
        end
        default: state <= 0;
      endcase
    end
  end

endmodule
