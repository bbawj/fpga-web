`default_nettype none

module ebr #(
    parameter WR_WIDTH = 8,
    parameter RD_WIDTH = WR_WIDTH,
    parameter int SIZE = 32,  // in units of WR_WIDTH
    parameter int SIZE_WIDTH = $clog2(SIZE)
) (
    input wr_clk,
    input wr_en,
    input [SIZE_WIDTH-1:0] wr_addr,
    input [WR_WIDTH-1:0] wr_data,

    input rd_clk,
    input rd_en,
    input [SIZE_WIDTH-1:0] rd_addr,
    output reg rd_valid,
    output reg [RD_WIDTH-1:0] rd_data
);
  reg [35:0] mem[SIZE:0];
  localparam logic SAME_WIDTH = RD_WIDTH == WR_WIDTH;
  localparam logic W_DIVS_R = WR_WIDTH > RD_WIDTH && WR_WIDTH % RD_WIDTH == 0;

  initial assert (SAME_WIDTH || W_DIVS_R);
  initial assert (RD_WIDTH <= 32);
  initial assert (RD_WIDTH <= WR_WIDTH);
  initial assert (WR_WIDTH <= 32);


  localparam WR_RATIO = 'd32 / WR_WIDTH;
  logic [SIZE_WIDTH-1:0] wr_slice_idx;
  reg   [SIZE_WIDTH-1:0] wr_ptr;
  always @(posedge wr_clk) begin
    wr_ptr <= wr_en ? ((wr_slice_idx == WR_RATIO - 'd1) ? wr_ptr + 1 : wr_ptr) : wr_addr;
    wr_slice_idx <= wr_en ? ((wr_slice_idx == WR_RATIO - 'd1) ? 0 : wr_slice_idx + 1) : 0;
    if (wr_en) begin
      mem[wr_ptr][wr_slice_idx*WR_WIDTH+:WR_WIDTH] <= wr_data;
    end
  end

  reg [SIZE_WIDTH-1:0] rd_ptr = '0;
  localparam [SIZE_WIDTH-1:0] RD_RATIO = 'd32 / RD_WIDTH;
  logic [SIZE_WIDTH-1:0] rd_slice_idx;
  always @(posedge rd_clk) begin
    if (rd_en)
      rd_data <= mem[rd_ptr][rd_slice_idx*RD_WIDTH+:RD_WIDTH];  // slice 0 of addressed word
    rd_valid <= rd_en;
    /* verilator lint_off WIDTHEXPAND */
    rd_slice_idx <= rd_en ? ((rd_slice_idx == RD_RATIO - 'd1) ? 0 : rd_slice_idx + 1) : 0;
    rd_ptr <= rd_en ? ((rd_slice_idx == RD_RATIO - 'd1) ? rd_ptr + 1 : rd_ptr) : rd_addr;
    /* verilator lint_on WIDTHEXPAND */
  end

  //   genvar i;
  //   generate
  //     if (SAME_WIDTH) begin : g_same_width
  //       // The easy case, just let the tools infer the RAM
  //       reg [WR_WIDTH-1:0] mem[0:SIZE-1];
  //
  //       always @(posedge rd_clk) begin
  //         rd_valid <= rd_en;
  //         rd_ptr   <= rd_en ? rd_ptr + 1 : rd_addr;
  //       end
  //       assign rd_mux = rd_en ? rd_ptr : rd_addr;
  //
  //       always @(posedge wr_clk) begin
  //         if (wr_en) mem[wr_ptr] <= wr_data;
  //       end
  //       always @(posedge rd_clk) begin
  //         if (rd_en) rd_data <= mem[rd_mux];
  //       end
  //     end else begin : g_diff_width
  //       // Direct instantiation of DP RAM for utilizing different widths for
  //       // reading and writing, which does not seem to be allowed by SP RAM.
  //       // Psuedo DP is used for > 18 bit data widths up till 36 max.
  //       // We use only up to 32 bits of data width
  //       initial assert (RD_WIDTH <= 32);
  //       initial assert (WR_WIDTH <= 32);
  // `ifdef SYNTHESIS
  //       always @(posedge rd_clk) begin
  //         rd_valid <= rd_en;
  //         rd_ptr   <= rd_en ? rd_ptr + 1 : rd_addr;
  //       end
  //       always_comb begin
  //         rd_mux = rd_en ? rd_ptr : rd_addr;
  //       end
  //
  //       localparam ACTUAL_WR_WIDTH = (WR_WIDTH == 1) ? 1 :
  //         (WR_WIDTH == 2) ? 2 :
  //         (WR_WIDTH <= 4) ? 4 :
  //         (WR_WIDTH <= 9) ? 9 :
  //         (WR_WIDTH <= 18) ? 18 :
  //         (WR_WIDTH <= 36) ? 36 : 0;
  //
  //       localparam ACTUAL_RD_WIDTH = (RD_WIDTH == 1) ? 1 :
  //         (RD_WIDTH == 2) ? 2 :
  //         (RD_WIDTH <= 4) ? 4 :
  //         (RD_WIDTH <= 9) ? 9 :
  //         (RD_WIDTH <= 18) ? 18 :
  //         (RD_WIDTH <= 36) ? 36 : 0;
  //
  //       reg [35:0] DO;
  //       reg [35:0] DI;
  //       reg [ 8:0] ADW;
  //       reg [14:0] ADR;
  //       assign rd_data = DO[RD_WIDTH-1:0];
  //       always_comb begin
  //         DI  = {{(36 - WR_WIDTH) {1'b0}}, wr_data};
  //         ADW = {{(9 - SIZE_WIDTH) {1'b0}}, wr_ptr};
  //         ADR = {{(15 - SIZE_WIDTH) {1'b0}}, rd_mux};
  //       end
  //
  //       PDPW16KD #(
  //           .REGMODE("OUTREG"),
  //           .DATA_WIDTH_R(ACTUAL_RD_WIDTH),
  //           .DATA_WIDTH_W(ACTUAL_WR_WIDTH)
  //       ) ebr_NOREG_NOREG (
  //           .DI0  (DI[0]),
  //           .DI1  (DI[1]),
  //           .DI2  (DI[2]),
  //           .DI3  (DI[3]),
  //           .DI4  (DI[4]),
  //           .DI5  (DI[5]),
  //           .DI6  (DI[6]),
  //           .DI7  (DI[7]),
  //           .DI8  (DI[8]),
  //           .DI9  (DI[9]),
  //           .DI10 (DI[10]),
  //           .DI11 (DI[11]),
  //           .DI12 (DI[12]),
  //           .DI13 (DI[13]),
  //           .DI14 (DI[14]),
  //           .DI15 (DI[15]),
  //           .DI16 (DI[16]),
  //           .DI17 (DI[17]),
  //           .DI18 (DI[18]),
  //           .DI19 (DI[19]),
  //           .DI20 (DI[20]),
  //           .DI21 (DI[21]),
  //           .DI22 (DI[22]),
  //           .DI23 (DI[23]),
  //           .DI24 (DI[24]),
  //           .DI25 (DI[25]),
  //           .DI26 (DI[26]),
  //           .DI27 (DI[27]),
  //           .DI28 (DI[28]),
  //           .DI29 (DI[29]),
  //           .DI30 (DI[30]),
  //           .DI31 (DI[31]),
  //           .DI32 (DI[32]),
  //           .DI33 (DI[33]),
  //           .DI34 (DI[34]),
  //           .DI35 (DI[35]),
  //           .ADW0 (ADW[0]),
  //           .ADW1 (ADW[1]),
  //           .ADW2 (ADW[2]),
  //           .ADW3 (ADW[3]),
  //           .ADW4 (ADW[4]),
  //           .ADW5 (ADW[5]),
  //           .ADW6 (ADW[6]),
  //           .ADW7 (ADW[7]),
  //           .ADW8 (ADW[8]),
  //           .ADR0 (ADR[0]),
  //           .ADR1 (ADR[1]),
  //           .ADR2 (ADR[2]),
  //           .ADR3 (ADR[3]),
  //           .ADR4 (ADR[4]),
  //           .ADR5 (ADR[5]),
  //           .ADR6 (ADR[6]),
  //           .ADR7 (ADR[7]),
  //           .ADR8 (ADR[8]),
  //           .ADR9 (ADR[9]),
  //           .ADR10(ADR[10]),
  //           .ADR11(ADR[11]),
  //           .ADR12(ADR[12]),
  //           .ADR13(ADR[13]),
  //           .DO0  (DO[0]),
  //           .DO1  (DO[1]),
  //           .DO2  (DO[2]),
  //           .DO3  (DO[3]),
  //           .DO4  (DO[4]),
  //           .DO5  (DO[5]),
  //           .DO6  (DO[6]),
  //           .DO7  (DO[7]),
  //           .DO8  (DO[8]),
  //           .DO9  (DO[9]),
  //           .DO10 (DO[10]),
  //           .DO11 (DO[11]),
  //           .DO12 (DO[12]),
  //           .DO13 (DO[13]),
  //           .DO14 (DO[14]),
  //           .DO15 (DO[15]),
  //           .DO16 (DO[16]),
  //           .DO17 (DO[17]),
  //           .DO18 (DO[18]),
  //           .DO19 (DO[19]),
  //           .DO20 (DO[20]),
  //           .DO21 (DO[21]),
  //           .DO22 (DO[22]),
  //           .DO23 (DO[23]),
  //           .DO24 (DO[24]),
  //           .DO25 (DO[25]),
  //           .DO26 (DO[26]),
  //           .DO27 (DO[27]),
  //           .DO28 (DO[28]),
  //           .DO29 (DO[29]),
  //           .DO30 (DO[30]),
  //           .DO31 (DO[31]),
  //           .DO32 (DO[32]),
  //           .DO33 (DO[33]),
  //           .DO34 (DO[34]),
  //           .DO35 (DO[35]),
  //
  //           .CEW (wr_en),
  //           .CLKW(wr_clk),
  //
  //           .CER (rd_en),
  //           .OCER(1'b1),
  //           .CLKR(rd_clk),
  //           .RST (1'b0),
  //           // Unused: bank addressing
  //           .BE3 (1'b1),
  //           .BE2 (1'b1),
  //           .BE1 (1'b1),
  //           .BE0 (1'b1),
  //           // Unused: for > 18kb of memory
  //           .CSW2(1'b0),
  //           .CSW1(1'b0),
  //           .CSW0(1'b0),
  //           .CSR2(1'b0),
  //           .CSR1(1'b0),
  //           .CSR0(1'b0)
  //       );
  // `else
  //       reg [WR_WIDTH-1:0] mem[0:SIZE-1];
  //
  //       always @(posedge wr_clk) begin
  //         if (wr_en) begin
  //           mem[wr_ptr] <= wr_data;
  //         end
  //       end
  //
  //       localparam logic WIDE_READ = RD_WIDTH >= WR_WIDTH;
  //       localparam logic [SIZE_WIDTH-1:0] RATIO = WIDE_READ ? (SIZE_WIDTH'(RD_WIDTH / WR_WIDTH)) : (SIZE_WIDTH'(WR_WIDTH / RD_WIDTH));
  //       logic [$clog2(RATIO)-1:0] slice_idx;
  //
  //       if (WIDE_READ) begin : g_wide_read
  //         // always @(posedge rd_clk) begin
  //         //   rd_data <= mem[rd_mux];
  //         // end
  //         // Otherwise, we would actually like to do this, but this adds extra
  //         // logic, failing timing closure
  //         for (i = 0; i < RATIO; i++) begin
  //           always @(posedge rd_clk) begin
  //             rd_data[i*WR_WIDTH+:WR_WIDTH] <= mem[rd_ptr+i];
  //           end
  //         end
  //       end else begin : g_narrow_read
  //         always @(posedge rd_clk) begin
  //           rd_data <= mem[rd_mux][slice_idx*RD_WIDTH+:RD_WIDTH];  // slice 0 of addressed word
  //         end
  //       end
  //
  //       if (WIDE_READ) begin : g_wide_read_ptr
  //         assign rd_mux = rd_en ? rd_ptr : rd_addr;
  //
  //         always @(posedge rd_clk) begin
  //           rd_valid <= rd_en;
  //           rd_ptr   <= rd_en ? rd_ptr + RATIO : rd_addr;
  //         end
  //       end else begin : g_narrow_read_ptr
  //         // RD_WIDTH < WR_WIDTH
  //         // Each memory word contains RATIO narrow slices.
  //         // rd_addr selects the memory word; a sub-counter selects the slice.
  //         // rd_ptr tracks the current memory word index.
  //         assign rd_mux = rd_en ? rd_ptr : rd_addr;
  //
  //         always @(posedge rd_clk) begin
  //           rd_valid <= rd_en;
  //           /* verilator lint_off WIDTHEXPAND */
  //           slice_idx <= rd_en ? ((slice_idx == RATIO - 'd1) ? 0 : slice_idx + 1) : 0;
  //           rd_ptr <= rd_en ? ((slice_idx == RATIO - 'd1) ? rd_ptr + 1 : rd_ptr) : rd_addr;
  //           /* verilator lint_on WIDTHEXPAND */
  //         end
  //       end
  // `endif
  //
  //     end
  //   endgenerate


endmodule
