module test_uart #(
    parameter DATA_WIDTH,
    parameter USE_BLOCK_RAM
) (
    input clk,
    input rst,
    input valid,
    input [DATA_WIDTH-1:0] data,
    output uart_rdy,
    output uart_tx
);
  GSR GSR_INST (.GSR(1'b1));
  PUR PUR_INST (.PUR(1'b1));
  uart #(
      .FREQ(125_000_000),
      .BAUD_RATE(460800),
      .REGMODE("OUTREG"),
      .BUF_USE_BLOCKRAM(USE_BLOCK_RAM),
      .DATA_WIDTH(DATA_WIDTH)
  ) uart (
      .clk(clk),
      .rst(rst),
      .valid(valid),
      .rx(data),
      .rdy(uart_rdy),
      .tx(uart_tx)
  );
endmodule
