module clk_gen #(
    parameter CLKI_DIV  = 1,    // input clock divider
    parameter CLKFB_DIV = 1,    // feedback divider
    parameter CLKOP_DIV = 1,    // primary output clock divider
    parameter CLKOP_FPHASE = 0,  // output clock VCO phase
    parameter CLKOP_CPHASE = 0,  // output clock divider phase
    parameter STEPS = 0  // number of times PHASESTEP should pulse
    ) (
    input  wire clk_in,     // input clock
    output wire clk_out,    // output clock
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
        .CLKI_DIV(CLKI_DIV),
        .CLKOP_ENABLE("ENABLED"),
        .CLKOP_DIV(CLKOP_DIV),
        .CLKOP_CPHASE(CLKOP_CPHASE),
        .CLKOP_FPHASE(CLKOP_FPHASE),
        .FEEDBK_PATH("CLKOP"),
        .CLKFB_DIV(CLKFB_DIV)
    ) pll_i (
        .RST(1'b0),
        .STDBY(1'b0),
        .CLKI(clk_in),
        .CLKOP(clk_out),
        .CLKFB(clk_out),
        .CLKINTFB(),
        .PHASESEL0(1'b1),
        .PHASESEL1(1'b1),
        .PHASEDIR(1'b0),
        .PHASESTEP(phase_step),
        .PHASELOADREG(1'b1),
        .PLLWAKESYNC(1'b0),
        .ENCLKOP(1'b0),
        .LOCK(locked)
    );

    // Provide the minimum 4 VCO cycles setup and hold time for phase_step
    reg [3:0] steps_done = '0;
    reg [3:0] counter = '0;
    always @(posedge clk_in) begin
      if (steps_done != STEPS) begin
        counter <= counter + 1;
        if (counter == 5) begin
          phase_step <= ~phase_step;
        end else if (counter == 10) begin
          phase_step <= ~phase_step;
          counter <= '0;
          steps_done <= steps_done + 1;
        end
      end
    end

    // ensure clock lock is synced with output clock
    reg locked_sync;
    always @(posedge clk_out) begin
        locked_sync <= locked;
        clk_locked <= locked_sync;
    end
endmodule
