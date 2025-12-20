`default_nettype	none
module mem (
  input clk,
  input rst,

  input wr_req, 
  input [18:0] wr_ad,
  input [31:0] wr_data,

  input rd_req, 
  input [18:0] rd_ad,
  output reg rd_valid,
  output reg [31:0] rd_data,

  output wire [1:0] sdram_ba,
  output wire sdram_we_n,
  output wire sdram_cas_n,
  output wire sdram_ras_n,
  output wire sdram_clk,
  output wire [31:0] sdram_dq,
  output wire [10:0] sdram_addr,
  );

  typedef enum {IDLE, PRECHARGE, AUTOREFRESH, ACTIVATE, MRS, READ, WRITE} SRAM_STATE;
  SRAM_STATE state = IDLE;
  SRAM_STATE state_before_idle = IDLE;
  reg normal = 1'b0;
  reg [7:0] cycle_counter = '0;
  reg [7:0] refresh_counter = '0;
  reg [7:0] idle_cycles = '0;
  // 0 = read, 1 = write
  reg op = '0;
  reg refresh_pending = '1;

  always @(posedge clk) begin
    // auto refresh can be performed once in 15.6us
    refresh_counter <= refresh_pending ? 'd400 : (refresh_counter > 0 ? refresh_counter - 1 : refresh_counter);
    if (refresh_counter == '0) refresh_pending <= 'd1;
    else if (state == AUTOREFRESH) refresh_pending <= 'd0;
  end

  always @(posedge clk) begin
    case (state)
      IDLE: begin
        if (idle_cycles > '0) begin
          idle_cycles <= idle_cycles - 'd1;
          state <= IDLE;
        end
        else if (normal == '0) state <= PRECHARGE;
        else if (refresh_pending == '1) state <= AUTOREFRESH;
        else if (normal == '0 && refresh_pending == '0) state <= MRS;
        else if (normal == 'd1 && (wr_req || rd_req)) begin
          state <= ACTIVATE;
          op <= wr_req;
        end
      end
      PRECHARGE: begin
        sdram_ras_n <= 1'b0;
        sdram_cas_n <= 1'b1;
        sdram_we_n <= 1'b0;
        // precharge all banks with A10 high but we only use 1 bank for now
        sdram_ba <= '0;
        sdram_addr <= 32'h00000000;
        // takes t_rp(15ns) to complete precharge which is just 1 cycle
        // short circuit here if need to do other OPs
        if (refresh_pending == '1) state <= AUTOREFRESH;
        else if (wr_req || rd_req) begin
          state <= ACTIVATE;
          op <= wr_req;
        end
        else state <= IDLE;
      end
      AUTOREFRESH: begin
        sdram_ras_n <= 1'b0;
        sdram_cas_n <= 1'b0;
        sdram_we_n <= 1'b1;
        state_before_idle <= AUTOREFRESH;
        // t_rfc (55ns) cycles for AUTOREFRESH to complete, during this time no new
        // commands and must be NO-OP
        idle_cycles <= 'd2;
        state <= IDLE;
      end
      ACTIVATE: begin
        sdram_ras_n <= 1'b0;
        sdram_cas_n <= 1'b1;
        sdram_we_n <= 1'b1;
        // TODO: use more than 1 bank
        sdram_ba <= '0;
        // if we reached ACTIVATE, assume that rd_req || wr_req
        sdram_addr <= op ? wr_ad : rd_ad;
        // need to wait t_rcd delay which is round(10ns/40ns) = 1 cycle at
        // 25Mhz
        if (cycle_counter == 'd1) begin
          cycle_counter <= '0;
          state <= op ? WRITE : READ;
        end else begin
          cycle_counter <= cycle_counter + 1;
          state <= ACTIVATE;
        end
      end
      MRS: begin
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

        if (cycle_counter == 'd2) begin
          cycle_counter <= '0;
          state <= IDLE;
          normal <= 1'b1;
        end else begin
          cycle_counter <= cycle_counter + 1;
          state <= MRS;
        end
      end
      READ: begin
        sdram_ras_n <= 1'b1;
        sdram_cas_n <= 1'b0;
        sdram_we_n <= 1'b1;
        // wait for CAS latency which we programmed to 2 in MRS
        if (cycle_counter == 'd2) begin
          cycle_counter <= '0;
          rd_data <= sdram_dq;
          rd_valid <= '1;
          state <= PRECHARGE;
        end else begin
          cycle_counter <= cycle_counter + 1;
          state <= READ;
        end
      end
      WRITE: begin
        sdram_ras_n <= 1'b1;
        sdram_cas_n <= 1'b0;
        sdram_we_n <= 1'b0;
        sdram_dq <= wr_data;
        state <= PRECHARGE;
      end
    endcase
  end

logic f_past_valid;
initial f_past_valid = 0;
SRAM_STATE prev_state = IDLE;
always @(posedge clk) begin
  f_past_valid <= 1'b1;
  prev_state <= state;

end

always @* begin
  assume(!rst);
  if (f_past_valid) begin
    // check that we ACTIVATE before READ
    // READ stays for 2 cycles
    if (state == READ)
      assert ((prev_state == READ && cycle_counter <= 'd2) || prev_state == ACTIVATE);
    // check that we ACTIVATE before WRITE
    if (state == WRITE)
      assert (prev_state == ACTIVATE);
    if (state == AUTOREFRESH)
      assert (prev_state == IDLE || prev_state == PRECHARGE);
    if (state == MRS)
      assert (prev_state == IDLE);
    // bank idle only from precharge
    if (state == IDLE)
      assert (prev_state == IDLE || prev_state == PRECHARGE || prev_state == MRS || prev_state == AUTOREFRESH);
  end
end

endmodule

