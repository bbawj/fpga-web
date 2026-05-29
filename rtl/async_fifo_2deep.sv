`default_nettype none

module async_fifo_2deep #(
    parameter DATA_WIDTH = 8
) (
    input wr_clk,
    input wr_rst,
    input wr_en,
    input [DATA_WIDTH-1:0] wr_data,
    output wr_full,

    input rd_clk,
    input rd_rst,
    input rd_en,
    output rd_empty,
    output reg [DATA_WIDTH-1:0] rd_data
);

  reg [DATA_WIDTH-1:0] mem[2];

  reg wr_ptr, rd_ptr;
  reg wr_ptr_rq1, wr_ptr_rq2;
  reg rd_ptr_wq1, rd_ptr_wq2;

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

endmodule
