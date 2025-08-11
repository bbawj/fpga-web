module clk_gen #(
  parameter SYSCLK_DIV,
  parameter TXC_DIV,
  parameter TXC_PHASE,
  parameter MDC_DIV,
  parameter FB_DIV
  )(
    input  wire clk_in,     // input clock
    output wire sysclk,
    output wire txc,
    output wire mdc,
    output reg  clk_locked  // clock locked?
    );

    wire locked;  // unsynced lock signal
    reg phase_step;

    // HDL attributes (values are from Project Trellis)
    (* ICP_CURRENT="12" *)
    (* LPF_RESISTOR="8" *)
    (* MFG_ENABLE_FILTEROPAMP="1" *)
    (* MFG_GMCREF_SEL="2" *)

    EHXPLLL #(
        .PLLRST_ENA("DISABLED"),
        .INTFB_WAKE("DISABLED"),
        .STDBY_ENABLE("DISABLED"),
        .DPHASE_SOURCE("ENABLED"),
        .OUTDIVIDER_MUXA("DIVA"),
        .OUTDIVIDER_MUXB("DIVB"),
        .OUTDIVIDER_MUXC("DIVC"),
        .OUTDIVIDER_MUXD("DIVD"),
        .CLKI_DIV(1),
        .CLKOP_ENABLE("ENABLED"),
        .CLKOS_ENABLE("ENABLED"),
        .CLKOS2_ENABLE("ENABLED"),
        // When using 25mhz SYSCLK, pass through the sysclk for use as feedback
        // because phased clock (clkos) and clock lower than 10mhz (clkos2) is
        // not recommeded for feedback. Otherwise, if generating 125mhz sysclk
        // ignore this note.
        .CLKOP_DIV(SYSCLK_DIV),
        .CLKOP_CPHASE(0),
        .CLKOP_FPHASE(0),
        // 25 mhz clock with 90 degree offset used primarily for RGMII TX
        .CLKOS_DIV(TXC_DIV),
        // each value represents 1/CLKOP_DIV turn of phase
        // 6 * 1/24 = 1/4 = 90 degree
        .CLKOS_CPHASE(TXC_PHASE),
        .CLKOS_FPHASE(0),
        // 2.5mhz used primarily for MDIO
        .CLKOS2_DIV(MDC_DIV),
        .CLKOS2_CPHASE(0),
        .CLKOS2_FPHASE(0),

        .FEEDBK_PATH("CLKOP"),
        .CLKFB_DIV(FB_DIV)
    ) pll_i (
        .RST(1'b0),
        .STDBY(1'b0),
        .CLKI(clk_in),
        .CLKOP(sysclk),
        .CLKFB(sysclk),
        .CLKOS(txc),
        .CLKOS2(mdc),
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
        .LOCK(locked)
    );

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
    reg locked_sync;
    always @(posedge sysclk) begin
        locked_sync <= locked;
        clk_locked <= locked_sync;
    end

endmodule
