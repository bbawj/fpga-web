`default_nettype	none
module top #(
  parameter TCP_ECHO_EN = 0,
  parameter reg [23:0] OFFSET_IN_FLASH = 'h40000,
  parameter HTTP_ADDR_FILE = "",
  parameter HTTP_SIZE_FILE = ""
  )(
    input wire clk_25mhz,
    input wire button,
    output wire led,
    output wire gpio_0,
    output wire gpio_1,
    output wire gpio_2,
    output wire gpio_3,
    // Shared PHY control
    // output wire mdc,
    output wire mdio,
    // PHY0 MII Interface
    output wire [3:0] phy0_txd,
    output wire phy0_txctl,
    output wire phy0_txc,
    input wire [3:0] phy0_rxd,
    input wire phy0_rxctl,
    input wire phy0_rxc,
    // SPI flash
    input wire flash_miso,
    output wire flash_cs,
    output wire flash_mosi,
    // SDRAM interface
    output wire [1:0] sdram_ba,
    output wire sdram_we_n,
    output wire sdram_cas_n,
    output wire sdram_ras_n,
    output wire sdram_clk,
    inout wire [31:0] sdram_dq,
    output wire [10:0] sdram_addr
);
assign mdio = 1;
localparam reg [23:0] NUM_BYTES = 30000;

// RGMII requires specific setup and hold times.
// This is achieved with a 90 degree phase offset tx_clk relative to the
// sysclk used to load the tx lines
reg pll_locked;
wire sysclk;
wire sysclk90;
wire spiclk, spi_clken;
`ifdef SPEED_100M
// Phase range from 0 to 46, 0 phase is 23. Each division is 1/24 degrees
clk_gen #(.SYSCLK_DIV(24), .TXC_DIV(24), .TXC_PHASE(29), .MDC_DIV(240), .FB_DIV(1))
`else
// Phase range from 0 to 8, 0 phase is 4. Each division is 1/5 degrees
clk_gen #(.SYSCLK_DIV(5), .TXC_DIV(5), .TXC_PHASE(5), .SPI_DIV(5), .SPI_PHASE(7), .FB_DIV(5))
`endif
  _clk_gen (.clk_in(clk_25mhz), .sysclk(sysclk),
    .sysclk90(sysclk90), .spi_en(1'b1), .spiclk(spiclk), .clk_locked(pll_locked));

USRMCLK u1(.USRMCLKI(spiclk), .USRMCLKTS(~pll_locked)) /* synthesis syn_noprune=1 */;

wire rst;
assign led = ~rst && (flash_done ? blinking : 1'b1);

// Force a minimum reset pulse width regardless of pll_locked behavior
reg [15:0] init_counter = '0;  // initialised in bitstream
reg init_wait_done = 0;
always @(posedge sysclk) begin
    if (!pll_locked) begin
        init_counter  <= '0;
        init_wait_done <= 0;
    end else if (init_counter != 16'hFFFF) begin
        init_counter  <= init_counter + 1;
        init_wait_done <= 0;
    end else begin
        init_wait_done <= 1;
    end
end
areset _areset(.clk(sysclk), .rst_n(button & init_wait_done), .rst(rst));

  logic sdram_wr_req, sdram_ready;
  wire sdram_wr_granted;
  logic [18:0] sdram_wr_ad, sdram_rd_ad;
  logic [31:0] sdram_wr_data;
  logic [31:0] sdram_rd_data;
  logic [31:0] sdram_dq_in;
  logic sdram_rd_req, sdram_dq_oe;
  logic sdram_rd_valid, sdram_rd_granted;
  sdram_ctrl #(
      .FREQ(125_000_000)
  ) m (
      .clk(sysclk),
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

      .boot_done(sdram_ready),

      .sdram_ba(sdram_ba),
      .sdram_we_n(sdram_we_n),
      .sdram_cas_n(sdram_cas_n),
      .sdram_ras_n(sdram_ras_n),
      .sdram_clk(sdram_clk),
      .sdram_dq(sdram_dq),
      .sdram_addr(sdram_addr)
  );
  // `ifdef LATTICE
    // b__wrapper #(.DATA_WIDTH(32)) bb_(.T(~sdram_dq_oe), .I(sdram_wr_data), .O(sdram_dq_in), .B(sdram_dq));
  // `else
  //   assign sdram_dq = sdram_dq_oe ? sdram_wr_data : 32'hzzzzzzzz;
  // `endif

  reg init_pulse;
  pulse_gen pulse (
      .clk(sysclk),
      .rst(rst),
      .sig(~rst && sdram_ready),
      .q  (init_pulse)
  );
  wire spi_en;
  delay #(
      .WIDTH(1),
      .DEPTH(10)
  ) del (
      .clk(sysclk),
      .rst(rst),
      .data_in(init_pulse),
      .data_out(spi_en)
  );

  logic spi_data_valid;
  logic [7:0] spi_data;
  spi_master spi (
      .clk(sysclk),
      .spi_sclk(spiclk),
      .spi_miso(flash_miso),
      .spi_cs(flash_cs),
      .spi_mosi(flash_mosi),
      .spi_clken(spi_clken),
      .rst(rst),
      .i_en(spi_en),
      .i_size(NUM_BYTES),
      .i_inst(8'h03),
      .i_offset(OFFSET_IN_FLASH),
      .i_addr_en('1),
      .o_data_valid(spi_data_valid),
      .o_data(spi_data)
  );

  logic flash_done;
  logic sdram_rd_req_unused;
  logic [18:0] sdram_rd_ad_unused;
  logic spi_ready;
  logic [31:0] spi_32;
  flash2sdram #(
      .NUM_BYTES(NUM_BYTES)
  ) f2s (
      .clk(sysclk),
      .rst(rst),
      .readback(1'b0),
      .spi_data_valid(spi_data_valid),
      .spi_data(spi_data),
      .sdram_wr_granted(sdram_wr_granted),
      .sdram_wr_req(sdram_wr_req),
      .sdram_wr_ad(sdram_wr_ad),
      .sdram_wr_data(sdram_wr_data),
      .sdram_rd_granted(1'b0),
      .sdram_rd_req(sdram_rd_req_unused),
      .sdram_rd_ad(sdram_rd_ad_unused),
      .spi_ready(spi_ready),
      .spi_32(spi_32),
      .done(flash_done)
  );
  uart #(
      .FREQ(125_000_000),
      .DATA_WIDTH(32),
      .BUF_USE_BLOCKRAM(1),
      .REGMODE("OUTREG"),
      .BAUD_RATE(921600)
  ) uart_spi (
      .clk(sysclk),
      .rst(rst),
      .valid(spi_ready),
      .rx(spi_32),
      .rdy(),
      .tx(gpio_3)
  );

mac #(.HTTP_ADDR_FILE(HTTP_ADDR_FILE), .HTTP_SIZE_FILE(HTTP_SIZE_FILE)) mac_instance(
  // We use base clock here instead of PHY_TXC as we purposely hold the data
  // 90 degrees before TXC edge
  .clk(sysclk),
  .clk90(sysclk90),
  .rst(rst),
  .tcp_echo_en(TCP_ECHO_EN == 0 ? 1'b0 : 1'b1),
  .uart_tx(gpio_0),
  .uart_tx2(gpio_1),
  .uart_tx3(gpio_2),

  .mem_ctrl_rd_req(sdram_rd_req),
  .mem_ctrl_rd_ad(sdram_rd_ad),
  .mem_ctrl_rd_size(),
  .mem_ctrl_rd_valid(sdram_rd_valid),
  .mem_ctrl_rd_granted(sdram_rd_granted),
  .mem_ctrl_rd_data(sdram_rd_data),

  .phy_txc(phy0_txc),
  .phy_txd(phy0_txd),
  .phy_txctl(phy0_txctl),

  .phy_rxd(phy0_rxd),
  .phy_rxctl(phy0_rxctl),
  .phy_rxc(phy0_rxc)
  );

  reg blinking;
  blinky _blinky(.clk_25mhz(sysclk), .button(button), .led(blinking));

endmodule

