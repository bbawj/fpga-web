module ram_dp #(
    parameter REGMODE = "NOREG",
    parameter int WR_WIDTH = 1,
    parameter int RD_WIDTH = 1,
    localparam int WIDER = WR_WIDTH > RD_WIDTH ? WR_WIDTH : RD_WIDTH,
    localparam int NARROWER = WR_WIDTH < RD_WIDTH ? WR_WIDTH : RD_WIDTH,
    parameter int ADDR_WIDTH = (NARROWER == 1) ? 14 :
          (NARROWER == 2) ? 13 :
          (NARROWER <= 4) ? 12 :
          (NARROWER <= 9) ? 11 :
          (NARROWER <= 18) ? 10 :
          (NARROWER <= 36) ? 9 : 0
) (
    input clk_a,
    we_a,
    input [ADDR_WIDTH-1:0] addr_a,
    addr_b,
    input clk_b,
    we_b,
    input [WR_WIDTH-1:0] dia,
    output reg [WR_WIDTH-1:0] doa,

    input [RD_WIDTH-1:0] dib,
    (*keep*) output reg [RD_WIDTH-1:0] dob
);


  localparam logic SAME_WIDTH = RD_WIDTH == WR_WIDTH;
  localparam logic W_DIVS_R = WR_WIDTH > RD_WIDTH && WR_WIDTH % RD_WIDTH == 0;
  localparam logic R_DIVS_W = RD_WIDTH > WR_WIDTH && RD_WIDTH % WR_WIDTH == 0;
  initial assert (SAME_WIDTH || W_DIVS_R || R_DIVS_W);
  initial assert (RD_WIDTH <= 32);
  initial assert (WR_WIDTH <= 32);
  initial assert (ADDR_WIDTH != 0);
  initial assert (WR_WIDTH != 0 && RD_WIDTH != 0);

  parameter int SIZE = (NARROWER == 1) ? 16384 :
          (NARROWER == 2) ? 8192 :
          (NARROWER <= 4) ? 4096 :
          (NARROWER <= 9) ? 2048 :
          (NARROWER <= 18) ? 1024 :
          (NARROWER <= 36) ? 512 : 0;
  /* verilator lint_off MULTIDRIVEN */
  reg [NARROWER-1:0] mem[SIZE];
  /* verilator lint_on MULTIDRIVEN */
  initial begin
    for (int i = 0; i < SIZE; i = i + 1) begin
      mem[i] = '0;
    end
  end

  genvar i;
  generate
    if (WIDER == WR_WIDTH) begin : g_wide_write
      localparam int RATIO = WR_WIDTH / RD_WIDTH;
      wire [ADDR_WIDTH-1:0] addr_a_base = addr_a << $clog2(RATIO);
      if (REGMODE != "NOREG") begin : g_no_reg_wide_write
        reg [WR_WIDTH-1:0] doa_q;
        always @(posedge clk_a) begin
          doa <= doa_q;
        end
        for (i = 0; i < RATIO; i = i + 1) begin : g_clk_a
          always @(posedge clk_a) begin
            if (we_a) mem[addr_a_base+i] <= dia[(i+1)*RD_WIDTH-1-:RD_WIDTH];
          end
          always @(posedge clk_a) begin
            if (!we_a) doa_q[(i+1)*RD_WIDTH-1-:RD_WIDTH] <= mem[addr_a_base+i];
          end
        end
      end else begin
        for (i = 0; i < RATIO; i = i + 1) begin : g_clk_a
          always @(posedge clk_a) begin
            if (we_a) mem[addr_a_base+i] <= dia[(i+1)*RD_WIDTH-1-:RD_WIDTH];
          end
          always @(posedge clk_a) begin
            if (!we_a) doa[(i+1)*RD_WIDTH-1-:RD_WIDTH] <= mem[addr_a_base+i];
          end
        end
      end

      always @(posedge clk_b) begin
        if (we_b) mem[addr_b] <= dib;
      end
      if (REGMODE == "NOREG") begin
        always @(posedge clk_b) begin
          if (!we_b) dob <= mem[addr_b];
        end
      end else begin
        (*keep*) reg [RD_WIDTH-1:0] dob_q;
        always @(posedge clk_b) begin
          dob <= dob_q;
          if (!we_b) dob_q <= mem[addr_b];
        end
      end
    end else begin : g_wide_read
      localparam int RATIO = RD_WIDTH / WR_WIDTH;
      wire [ADDR_WIDTH-1:0] addr_b_base = addr_b << $clog2(RATIO);
      if (REGMODE != "NOREG") begin : g_rd_pipelined
        reg [RD_WIDTH-1:0] dob_q;
        always @(posedge clk_b) begin
          dob <= dob_q;
        end
        for (i = 0; i < RATIO; i = i + 1) begin
          always @(posedge clk_b) begin
            if (we_b) mem[addr_b_base+i] <= dib[(i+1)*WR_WIDTH-1-:WR_WIDTH];
          end
          always @(posedge clk_b) begin
            if (!we_b) dob_q[(i+1)*WR_WIDTH-1-:WR_WIDTH] <= mem[addr_b_base+i];
          end
        end
      end else begin
        for (i = 0; i < RATIO; i = i + 1) begin
          always @(posedge clk_b) begin
            if (we_b) mem[addr_b_base+i] <= dib[(i+1)*WR_WIDTH-1-:WR_WIDTH];
          end
          always @(posedge clk_b) begin
            if (!we_b) dob[(i+1)*WR_WIDTH-1-:WR_WIDTH] <= mem[addr_b_base+i];
          end
        end
      end

      always @(posedge clk_a) begin
        if (we_a) mem[addr_a] <= dia;
      end
      if (REGMODE == "NOREG") begin
        always @(posedge clk_a) begin
          if (!we_a) doa <= mem[addr_a];
        end
      end else begin
        reg [WR_WIDTH-1:0] doa_q;
        always @(posedge clk_a) begin
          doa <= doa_q;
          if (!we_a) doa_q <= mem[addr_a];
        end
      end
    end
  endgenerate

endmodule
