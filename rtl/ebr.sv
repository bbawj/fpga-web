`default_nettype none

module ebr #(
    parameter int WR_WIDTH = 8,
    parameter int RD_WIDTH = WR_WIDTH,
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
    output reg rd_valid_q1,
    output reg [RD_WIDTH-1:0] rd_data,
    output reg [RD_WIDTH-1:0] rd_data_q1
);
  reg [WR_WIDTH-1:0] mem[0:SIZE-1];

  reg [SIZE_WIDTH-1:0] wr_ptr;
  reg wr_started = '0;

  always @(posedge wr_clk) begin
    if (wr_en) begin
      if (!wr_started) begin
        wr_ptr <= wr_addr + 1;
        mem[wr_addr] <= wr_data;
        wr_started <= 1;
      end else begin
        mem[wr_ptr] <= wr_data;
        wr_ptr <= wr_ptr + 1;
      end
    end else begin
      wr_started <= 0;
      wr_ptr <= 0;
    end
  end

  always @(posedge rd_clk) begin
    rd_valid <= rd_en;
    rd_valid_q1 <= rd_valid;
    rd_data_q1 <= rd_data;
  end

  // Read side - assembles 4x 8-bit words into 32-bit
  localparam logic WIDE_READ = RD_WIDTH >= WR_WIDTH;
  localparam logic [SIZE_WIDTH-1:0] RATIO = WIDE_READ ? (SIZE_WIDTH'(RD_WIDTH / WR_WIDTH)) : (SIZE_WIDTH'(WR_WIDTH / RD_WIDTH));
  reg rd_started = '0;
  reg [SIZE_WIDTH-1:0] rd_ptr = '0;
  logic [$clog2(RATIO)-1:0] slice_idx;

  logic [SIZE_WIDTH-1:0] rd_mux = '0;
  assign rd_mux = rd_started ? rd_ptr : rd_addr;
  genvar i;
  generate
    if (WIDE_READ) begin : g_wide_read
      // always @(posedge rd_clk) begin
      //   rd_data <= mem[rd_mux];
      // end
      for (i = 0; i < RATIO; i++) begin
        always @(posedge rd_clk) begin
          rd_data[i*WR_WIDTH+:WR_WIDTH] <= mem[rd_ptr+i];
        end
      end
    end else begin : g_narrow_read
      always @(posedge rd_clk) begin
        rd_data <= mem[rd_mux][slice_idx*RD_WIDTH+:RD_WIDTH];  // slice 0 of addressed word
      end
    end
  endgenerate

  generate
    if (WIDE_READ) begin : g_wide_read_ptr
      always @(posedge rd_clk) begin
        rd_started <= rd_en;
        rd_ptr <= rd_started ? rd_ptr + RATIO : rd_addr;
      end
    end else begin : g_narrow_read_ptr
      // RD_WIDTH < WR_WIDTH
      // Each memory word contains RATIO narrow slices.
      // rd_addr selects the memory word; a sub-counter selects the slice.
      // rd_ptr tracks the current memory word index.

      always @(posedge rd_clk) begin
        if (rd_en) begin
          if (!rd_started) begin
            slice_idx  <= 1;
            rd_ptr     <= rd_addr;
            rd_started <= 1;
          end else begin
            /* verilator lint_off WIDTHEXPAND */
            if (slice_idx == RATIO - 'd1) begin
              /* verilator lint_on WIDTHEXPAND */
              // Last slice of current word — move to next word, reset slice
              rd_ptr    <= rd_ptr + 1;
              slice_idx <= 0;
            end else begin
              slice_idx <= slice_idx + 1;
            end
          end
        end else begin
          rd_started <= 0;
          rd_ptr     <= 0;
          slice_idx  <= 0;
        end
      end
    end
  endgenerate
endmodule
