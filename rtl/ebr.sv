`default_nettype	none

module ebr #(
  parameter DATA_WIDTH = 8,
  parameter SIZE = 32,
  parameter SIZE_WIDTH = $clog2(SIZE)
  )(
    input clk,
    input wr_en,
    input [SIZE_WIDTH-1:0] wr_addr,
    input [DATA_WIDTH-1:0] wr_data,

    input rd_en,
    input [SIZE_WIDTH-1:0] rd_addr,
    output [DATA_WIDTH-1:0] rd_data
  );

reg [DATA_WIDTH-1:0] mem [0:SIZE-1];

reg [SIZE_WIDTH-1:0] wr_ptr;
reg wr_started = '0;

  always @(posedge clk) begin
    if (wr_en) begin
      if (!wr_started) begin
        wr_ptr <= wr_addr + 1;
        mem[wr_addr] <= wr_data;
      end else begin
        mem[wr_ptr] <= wr_data;
        wr_ptr <= wr_ptr + 1;
      end
    end
  end

reg [SIZE_WIDTH-1:0] rd_ptr;
reg rd_started = '0;

  always @(posedge clk) begin
    if (rd_en) begin
      if (!rd_started) begin
        rd_ptr <= rd_addr + 1;
        rd_data <= mem[rd_addr];
      end else begin
        rd_data <= mem[rd_ptr];
        rd_ptr <= rd_ptr + 1;
      end
    end
  end
endmodule
