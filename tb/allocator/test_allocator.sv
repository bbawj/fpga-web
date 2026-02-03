module test_allocator #(
    parameter MAU = 32,
    parameter NUM_BLOCKS = 32,
    parameter NUM_BLOCKS_WIDTH = $clog2(NUM_BLOCKS)
) (
    input clk,
    input rst,
    input alloc_en,
    input rd_en,
    input [NUM_BLOCKS_WIDTH-1:0] i_addr,
    input wr_en,
    input [MAU-1:0] wr_data,
    input [NUM_BLOCKS_WIDTH-1:0] request_size,

    output reg [MAU-1:0] o_rd_data,
    output reg [NUM_BLOCKS_WIDTH-1:0] o_addr,
    output reg o_valid,
    output reg o_err
);

  allocator #(
      .MAU(MAU),
      .NUM_BLOCKS(NUM_BLOCKS)
  ) _allocator (
      .clk(clk),
      .rst(rst),
      .en(alloc_en),
      .request_size(request_size),
      .o_addr(o_addr),
      .o_valid(o_valid),
      .o_err(o_err)
  );

  ebr #(
      .DATA_WIDTH(MAU),
      .SIZE(NUM_BLOCKS)
  ) _blockmem (
      .clk(clk),
      .wr_en(wr_en),
      .wr_addr(i_addr),
      .wr_data(wr_data),
      .rd_en(rd_en),
      .rd_addr(i_addr),
      .rd_data(o_rd_data)
  );

endmodule
