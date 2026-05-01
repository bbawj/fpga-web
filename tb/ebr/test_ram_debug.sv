module test_ram_debug #(
    parameter DATA_WIDTH = 8,
    parameter BUF_USE_BLOCKRAM
) (
    input wire clk,
    input wire rst,
    input valid,
    input [DATA_WIDTH-1:0] din,
    input fifo_rd_en,
    output [DATA_WIDTH-1:0] fifo_dout
);
  GSR GSR_INST (.GSR(1'b1));
  PUR PUR_INST (.PUR(1'b1));
  fifo #(
      .DATA_WIDTH(DATA_WIDTH),
      .DEPTH(128),
      .EBR(BUF_USE_BLOCKRAM)
  ) fifo_ (
      .clk  (clk),
      .rst  (rst),
      .wr_en(valid),
      .din  (din),
      .full (fifo_full),
      .rd_en(fifo_rd_en),
      .dout (fifo_dout),
      .empty(),
      .count()
  );
endmodule


