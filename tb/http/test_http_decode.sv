module test_http #(
    parameter string HTTP_ADDR_FILE,
    parameter string HTTP_SIZE_FILE
) (
    input clk,
    input rst,
    input i_payload_valid,
    input [7:0] i_payload_data,
    output reg res_valid,
    output reg res_err,
    output reg [15:0] res_payload_size,
    output reg [18:0] res_payload_addr
);
  http_decode #(
      .HTTP_ADDR_FILE(HTTP_ADDR_FILE),
      .HTTP_SIZE_FILE(HTTP_SIZE_FILE)
  ) http_dec (
      .clk(clk),
      .rst(rst),
      .i_payload_valid(i_payload_valid),
      .i_payload_data(i_payload_data),

      .res_valid(res_valid),
      .res_err(res_err),
      .res_payload_size(res_payload_size),
      .res_payload_addr(res_payload_addr)
  );
endmodule
