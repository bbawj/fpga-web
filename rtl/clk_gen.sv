module clk_gen #(
    parameter SYSCLK_DIV,
    parameter TXC_DIV,
    parameter TXC_PHASE,
    parameter SPI_DIV,
    parameter SPI_PHASE,
    parameter FB_DIV
) (
    input  wire clk_in,     // input clock
    input wire spi_en,
    output wire sysclk,
    output wire sysclk90,
    output wire spiclk,
    output wire spiclk90,
    output reg  clk_locked = 0  // clock locked?
)  /* synthesis NGD_DRC_MASK=1 */;

  wire locked;  // unsynced lock signal
  // reg  phase_step;

  // HDL attributes (values are from Project Trellis)
  // (* ICP_CURRENT="5" *)
  // (* LPF_RESISTOR="16" *)
  // (* MFG_ENABLE_FILTEROPAMP="1" *)
  // (* MFG_GMCREF_SEL="2" *)
  // (* FREQUENCY_PIN_CLKOS2="125.000000" *)
  // (* FREQUENCY_PIN_CLKOS="125.000000" *)
  // (* FREQUENCY_PIN_CLKOP="125.000000" *)
  // (* FREQUENCY_PIN_CLKI="25.000000" *)
  wire buf_CLKI;
  IB Inst1_IB (
      .I(clk_in),
      .O(buf_CLKI)
  );

  wire sysclk_t, sysclk90_t, spiclk_t, spiclk90_t;
  EHXPLLL #(
      .PLLRST_ENA("DISABLED"),
      .INTFB_WAKE("DISABLED"),
      .STDBY_ENABLE("DISABLED"),
      .DPHASE_SOURCE("DISABLED"),
      .OUTDIVIDER_MUXA("DIVA"),
      .OUTDIVIDER_MUXB("DIVB"),
      .OUTDIVIDER_MUXC("DIVC"),
      .OUTDIVIDER_MUXD("DIVD"),
      .CLKI_DIV(1),
      .CLKOP_ENABLE("ENABLED"),
      .CLKOS_ENABLE("ENABLED"),
      .CLKOS2_ENABLE("ENABLED"),
      .CLKOS3_ENABLE("ENABLED"),
      // When using 25mhz SYSCLK, pass through the sysclk for use as feedback
      // because phased clock (clkos) and clock lower than 10mhz (clkos2) is
      // not recommeded for feedback. Otherwise, if generating 125mhz sysclk
      // ignore this note.
      .CLKOP_DIV(5),
      .CLKOP_CPHASE(4),
      .CLKOP_FPHASE(0),
      // 25 mhz clock with 90 degree offset used primarily for RGMII TX
      // each value represents 1/CLKOP_DIV turn of phase
      // 6 * 1/24 = 1/4 = 90 degree
      .CLKOS_DIV(5),
      .CLKOS_CPHASE(6),
      .CLKOS_FPHASE(2),

      .CLKOS2_DIV(12),
      .CLKOS2_CPHASE(11),
      .CLKOS2_FPHASE(0),

      .CLKOS3_DIV(12),
      .CLKOS3_CPHASE(15),
      .CLKOS3_FPHASE(0),

      .FEEDBK_PATH("CLKOP"),
      .CLKFB_DIV  (5)
  )
      pll_i (
          .RST(1'b0),
          .STDBY(1'b0),
          .CLKI(buf_CLKI),
          .CLKOP(sysclk_t),
          .CLKFB(sysclk_t),
          .CLKOS(sysclk90_t),
          .CLKOS2(spiclk_t),
          .CLKOS3(spiclk90_t),
          .CLKINTFB(),

          .PHASESEL0(1'b0),
          .PHASESEL1(1'b0),
          .PHASEDIR(1'b0),
          .PHASESTEP(1'b0),
          .PHASELOADREG(1'b0),
          .PLLWAKESYNC(1'b0),
          .ENCLKOP(1'b0),
          .ENCLKOS(1'b0),
          .ENCLKOS2(1'b0),
          .ENCLKOS3(1'b0),
          .INTLOCK(),
          .REFCLK(),
          .LOCK(locked)
      )
  /* synthesis FREQUENCY_PIN_CLKOS2="125.000000" */
  /* synthesis FREQUENCY_PIN_CLKOS="125.000000" */
  /* synthesis FREQUENCY_PIN_CLKOP="125.000000" */
  /* synthesis FREQUENCY_PIN_CLKI="25.000000" */
  /* synthesis ICP_CURRENT="5" */
/* synthesis LPF_RESISTOR="16" */
;
  assign sysclk   = sysclk_t;
  assign sysclk90 = sysclk90_t;
  assign spiclk   = spiclk_t;
  assign spiclk90 = spiclk90_t;

  // Provide the minimum 4 VCO cycles setup and hold time for phase_step
  // reg [3:0] steps_done = '0;
  // reg [3:0] counter = '0;
  // always @(posedge clk_in) begin
  //   if (steps_done != STEPS) begin
  //     counter <= counter + 1;
  //     if (counter == 5) begin
  //       phase_step <= ~phase_step;
  //     end else if (counter == 10) begin
  //       phase_step <= ~phase_step;
  //       counter <= '0;
  //       steps_done <= steps_done + 1;
  //     end
  //   end
  // end

  // ensure clock lock is synced with output clock
  reg locked_sync = 0;
  always @(posedge sysclk) begin
    locked_sync <= locked;
    clk_locked  <= locked_sync;
  end

  // exemplar begin
  // exemplar attribute pll_i FREQUENCY_PIN_CLKOS2 125.000000
  // exemplar attribute pll_i FREQUENCY_PIN_CLKOS 125.000000
  // exemplar attribute pll_i FREQUENCY_PIN_CLKOP 125.000000
  // exemplar attribute pll_i FREQUENCY_PIN_CLKI 25.000000
  // exemplar attribute pll_i ICP_CURRENT 5
  // exemplar attribute pll_i LPF_RESISTOR 16
  // exemplar end
endmodule
