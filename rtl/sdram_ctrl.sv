`default_nettype none
/**
* Dual port SDRAM interface to a single port memory. Prioritizes writes.
*
* When rd_granted, rd_ad, rd_data is latched into the state machine.
* When wr_granted, wr_ad, wr_data is latched into the state machine.
*
* Granted signals are pulsed for 1 cycle. Users should check this pulse and 
* change state if needed (e.g. de-assert rd_req).
*/
module sdram_ctrl #(
    parameter int FREQ = 125_000_000
) (
    input clk,
    input rst,

    input wr_req,
    // 18:8 is the row address, 7:0 is column address
    input [18:0] wr_ad,
    input [31:0] wr_data,
    output reg wr_granted,

    input rd_req,
    input [18:0] rd_ad,
    output reg rd_valid,
    output reg [31:0] rd_data,
    output reg rd_granted,

    output reg [1:0] sdram_ba,
    output reg sdram_we_n,
    output reg sdram_cas_n,
    output reg sdram_ras_n,
    output wire sdram_clk,
    inout [31:0] sdram_dq,
    output reg [10:0] sdram_addr
);

  localparam int CYCLE_TIME_NS = (1_000_000_000 / FREQ);
  // Maintain for 200us min
  localparam int POWER_UP_DELAY = 200_000 / CYCLE_TIME_NS;
  // auto refresh can be performed once in 15.6us
  localparam int REFRESH_CYCLE = 16000 / CYCLE_TIME_NS;
  // t_rfc (55ns)
  localparam int ROW_CYCLE_TIME = 55 / CYCLE_TIME_NS;
  // tRP (min) ~ 20ns
  localparam int PRECHARGE_MIN = 20 / CYCLE_TIME_NS;
  // tRAS (min) 42ns
  localparam int ROW_ACTIVE_TIME_MIN = 42 / CYCLE_TIME_NS;
  // 2 cyles min to complete write
  localparam int MRS_DELAY = 2;
  // Programmed during MRS
  localparam int CAS_LATENCY = 2;

  assign sdram_clk = clk;

  reg sdram_dq_oe = 0;
  assign sdram_dq = sdram_dq_oe ? wr_data : 32'hzzzzzzzz;

  typedef enum {
    BOOT,
    NOOP,
    PRECHARGE,
    AUTOREFRESH_START,
    AUTOREFRESH_WAIT,
    AUTOREFRESH_DONE,
    GRANT,
    ACTIVATE,
    MRS,
    READ_WAIT,
    READ,
    WRITE
  } sram_state_t;
  sram_state_t state = BOOT, prev_state, next_state;
  reg [31:0] cycle_counter = '0;
  reg [31:0] refresh_counter = '0;
  reg [ 7:0] idle_cycles = '0;
  reg [10:0] ra = '0;
  reg [ 7:0] ca = '0;
  // 0 = read, 1 = write
  reg mrs_done = 0, boot = 0;
  reg op = '0;
  reg refresh_pending = '1;

  always @(posedge clk) begin
    refresh_pending <= refresh_counter == REFRESH_CYCLE;
    if (state == AUTOREFRESH_WAIT || state == AUTOREFRESH_DONE) refresh_counter <= '0;
    else
      refresh_counter <= refresh_counter == REFRESH_CYCLE ? refresh_counter : refresh_counter + 'd1;
  end

  always @(posedge clk) begin
    prev_state <= state;
    state <= next_state;
    cycle_counter <= (state != prev_state) ? '0 : cycle_counter + 'd1;
  end

  always_comb begin
    next_state = state;
    case (state)
      BOOT: if (cycle_counter == POWER_UP_DELAY) next_state = NOOP;
      NOOP: begin
        if (idle_cycles > 0) next_state = NOOP;
        else if (refresh_pending || wr_req == 'b1 || rd_req == 'b1) next_state = PRECHARGE;
      end
      PRECHARGE: begin
        if (cycle_counter < PRECHARGE_MIN) next_state = PRECHARGE;
        else if (refresh_pending) next_state = AUTOREFRESH_START;
        else if (wr_req == 'b1 || rd_req == 'b1) next_state = GRANT;
      end
      AUTOREFRESH_START: begin
        next_state = AUTOREFRESH_WAIT;
      end
      AUTOREFRESH_WAIT: begin
        // t_rfc (55ns) cycles for AUTOREFRESH to complete, during this time no new
        // commands
        if (cycle_counter == ROW_CYCLE_TIME) next_state = AUTOREFRESH_DONE;
      end
      AUTOREFRESH_DONE: begin
        if (boot == '0) next_state = AUTOREFRESH_START;
        else if (mrs_done == '0) next_state = MRS;
        else if (wr_req == 'b1 || rd_req == 'b1) next_state = GRANT;
        else next_state = NOOP;
      end
      MRS: begin
        if (cycle_counter == MRS_DELAY) next_state = NOOP;
      end
      GRANT: begin
        next_state = ACTIVATE;
      end
      ACTIVATE: begin
        // min tRAS
        // need to wait t_rcd delay which is round(10ns/40ns) = 1 cycle at
        // 25Mhz
        if (cycle_counter == ROW_ACTIVE_TIME_MIN) next_state = op ? WRITE : READ_WAIT;
      end
      WRITE: begin
        next_state = NOOP;
      end
      READ_WAIT: begin
        if (cycle_counter == CAS_LATENCY - 1) next_state = READ;
      end
      READ: begin
        next_state = NOOP;
      end
      default: next_state = NOOP;
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      wr_granted <= '0;
      rd_granted <= '0;
      rd_valid   <= '0;
    end else begin
      wr_granted  <= '0;
      rd_granted  <= '0;
      sdram_dq_oe <= '0;
      case (state)
        BOOT, NOOP, AUTOREFRESH_WAIT: begin
          sdram_ras_n <= 1;
          sdram_cas_n <= 1;
          sdram_we_n <= 1;
          rd_valid <= '0;
        end
        GRANT: begin
          op <= wr_req;
          ra <= wr_req ? wr_ad[18:8] : rd_ad[18:8];
          ca <= wr_req ? wr_ad[7:0] : rd_ad[7:0];
          wr_granted <= wr_req;
          rd_granted <= ~wr_req;
          rd_valid <= '0;
        end
        PRECHARGE: begin
          sdram_ras_n <= 1'b0;
          sdram_cas_n <= 1'b1;
          sdram_we_n <= 1'b0;
          // precharge all banks with A10 high but we only use 1 bank for now
          sdram_ba <= '0;
          sdram_addr <= '0;
        end
        AUTOREFRESH_START: begin
          sdram_ras_n <= 1'b0;
          sdram_cas_n <= 1'b0;
          sdram_we_n  <= 1'b1;
        end
        AUTOREFRESH_DONE: begin
          sdram_ras_n <= 1'b0;
          sdram_cas_n <= 1'b0;
          sdram_we_n <= 1'b1;
          boot <= 1'b1;
        end
        ACTIVATE: begin
          sdram_ras_n <= 1'b0;
          sdram_cas_n <= 1'b1;
          sdram_we_n <= 1'b1;
          // TODO: use more than 1 bank
          sdram_ba <= '0;
          // if we reached ACTIVATE, assume that rd_req || wr_req
          sdram_addr <= ra;
        end
        MRS: begin
          mrs_done <= 1;
          sdram_ras_n <= 1'b0;
          sdram_cas_n <= 1'b0;
          sdram_we_n <= 1'b0;
          // BA0-BA1: reserved = 0
          // BA0-BA1: reserved = 0
          sdram_ba <= '0;
          // A10: reserved = 0
          // A9 write burst: no burst = 1
          // A8-A7 test mode 'b00 = MRS
          // A6-A4 CAS latency 'b010 = 2
          // A3 burst type sequential = 0
          // A2-A0 burst length 'b000 = 1
          sdram_addr <= 11'b01000100000;
        end
        READ_WAIT: begin
          sdram_ras_n <= 1'b1;
          sdram_cas_n <= 1'b0;
          sdram_we_n  <= 1'b1;
          sdram_addr  <= {3'b0, ca};
        end
        READ: begin
          rd_data  <= sdram_dq;
          rd_valid <= '1;
        end
        WRITE: begin
          sdram_ras_n <= 1'b1;
          sdram_cas_n <= 1'b0;
          sdram_we_n  <= 1'b0;
          sdram_dq_oe <= 1'b1;
          sdram_addr  <= {3'b0, ca};
        end
      endcase
    end
  end

`ifdef FORMAL
  logic f_past_valid;
  initial f_past_valid = 0;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
  end

  always_comb begin
    assume (!rst);
    if (f_past_valid) begin
      // check that we GRANT before activating
      if (state == ACTIVATE) assert (prev_state == GRANT);
      // check that read is granted
      if (state == READ) assert (prev_state == READ || prev_state == GRANT);
      // READ stays for 2 cycles
      if (prev_state == READ && state != READ) assert (cycle_counter == CAS_LATENCY);
      // check that write is granted
      if (state == WRITE) assert (prev_state == GRANT);
      // precharge before AUTOREFRESH
      if (state == AUTOREFRESH_START) assert (prev_state == PRECHARGE);
      // refresh before MRS
      if (state == MRS) assert (prev_state == AUTOREFRESH_DONE);
    end
  end
`endif

endmodule

