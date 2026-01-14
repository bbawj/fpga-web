module test_allocator #(
  parameter NUM_BLOCKS = 32,
  parameter NUM_BLOCKS_WIDTH = $clog2(NUM_BLOCKS)
  )(
  input clk,
  input rst,
  input en,
  input [NUM_BLOCKS_WIDTH-1:0] request_size,
  output reg [NUM_BLOCKS_WIDTH-1:0] o_addr,
  output reg o_valid,
  output reg o_err
);

allocator _allocator(
  .clk(clk), .rst(rst), .en(en), .request_size(request_size), .o_addr(o_addr),
  .o_valid(o_valid), .o_err(o_err)
  );

endmodule
