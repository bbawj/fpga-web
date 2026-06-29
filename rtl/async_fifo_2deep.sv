`default_nettype none

module async_fifo_2deep #(
    parameter DATA_WIDTH = 8
) (
    input wire wr_clk,
    input wire wr_rst,
    input wire wr_en,
    input wire [DATA_WIDTH-1:0] wr_data,
    output wire wr_full,

    input wire rd_clk,
    input wire rd_rst,
    input wire rd_en,
    output wire rd_empty,
    output reg [DATA_WIDTH-1:0] rd_data
);

  reg [DATA_WIDTH-1:0] mem[2];

  reg wr_ptr = 0, rd_ptr = 0;
  reg wr_ptr_rq1 = 0, wr_ptr_rq2 = 0;
  reg rd_ptr_wq1 = 0, rd_ptr_wq2 = 0;

  wire wr_do = wr_en & ~wr_full;
  assign wr_full = wr_ptr ^ rd_ptr_wq2;

  wire rd_do = rd_en & ~rd_empty;
  assign rd_empty = ~(rd_ptr ^ wr_ptr_rq2);

  always @(posedge wr_clk) begin
    if (wr_rst) begin
      wr_ptr <= 0;
      rd_ptr_wq1 <= '0;
      rd_ptr_wq2 <= '0;
    end else begin
      if (wr_do) begin
        wr_ptr <= wr_ptr + wr_do;
        mem[wr_ptr] <= wr_data;
      end
      rd_ptr_wq1 <= rd_ptr;
      rd_ptr_wq2 <= rd_ptr_wq1;
    end
  end

  always @(posedge rd_clk) begin
    if (rd_rst) begin
      rd_ptr <= 0;
      rd_data <= '0;
      wr_ptr_rq1 <= '0;
      wr_ptr_rq2 <= '0;
    end else begin
      if (rd_do) begin
        rd_ptr  <= rd_ptr + rd_do;
        rd_data <= mem[rd_ptr];
      end
      wr_ptr_rq1 <= wr_ptr;
      wr_ptr_rq2 <= wr_ptr_rq1;
    end
  end

`ifdef FORMAL
  localparam F_CLKBITS = 5;
  (* anyconst *) wire [F_CLKBITS-1:0] f_wclk_step, f_rclk_step;
  always_comb assume (f_wclk_step != 0);
  always_comb assume (f_rclk_step != 0);

  reg [F_CLKBITS-1:0] f_wclk_count, f_rclk_count;
  always @($global_clock) f_wclk_count <= f_wclk_count + f_wclk_step;
  always @($global_clock) f_rclk_count <= f_rclk_count + f_rclk_step;
  always_comb begin
    assume (wr_clk == f_wclk_count[F_CLKBITS-1]);
    assume (rd_clk == f_rclk_count[F_CLKBITS-1]);
  end

  initial assume (rd_rst);
  initial assume (wr_rst);

  always @($global_clock) begin
    assume ($rose(wr_rst) == $rose(rd_rst));
    if (!$rose(wr_clk)) assume (!$fell(wr_rst));
    if (!$rose(rd_clk)) assume (!$fell(rd_rst));
  end

  reg f_past_valid, w_f_past_valid, r_f_past_valid;
  reg [DATA_WIDTH-1:0] w_input;
  initial f_past_valid = 1'b0;
  always @(posedge wr_clk) begin
    if (wr_rst) w_f_past_valid <= 1;
  end
  always @(posedge rd_clk) begin
    if (rd_rst) r_f_past_valid <= 1;
  end
  initial assume (w_input == 0);
  always @($global_clock) begin
    if (!$rose(wr_clk)) begin
      assume ($stable(wr_en));
      assume ($stable(wr_data));
    end
    if (!$rose(rd_clk)) begin
      assume ($stable(rd_en));
    end

    if (w_f_past_valid && r_f_past_valid) f_past_valid <= 1;
    if (!wr_rst && !$past(wr_rst) && wr_do && $rose(wr_clk)) w_input <= wr_data;
    if (f_past_valid) begin
      if (!rd_rst && !$past(rd_rst) && $past(rd_do) && $rose(rd_clk)) assert (rd_data == w_input);
    end
  end
`endif
endmodule
