module http_entry #(
    parameter HTTP_ADDR_FILE = "",
    parameter HTTP_SIZE_FILE = ""
) (
    input clk,
    input [8:0] key,

    output reg [18:0] content_addr,
    output reg [15:0] content_size,
    output reg [15:0] content_checksum
);
  // 512 entries of 18 bit data, each is an address to SDRAM
  (*keep*) reg [35:0] cam_content_addr, cam_content_meta;
  always @(posedge clk) begin
    content_addr <= cam_content_addr[18:0];
    content_size <= cam_content_meta[15:0];
    content_checksum <= 0;
  end
  ram_sp #(
      .DATA_WIDTH(36),
      .ADDR_WIDTH(9),
      .INIT(HTTP_ADDR_FILE)
  ) cam_addr (
      .clk (clk),
      .we  ('0),
      .addr(key),
      .di  ('0),
      .dout(cam_content_addr)
  );
  // 512 entries to payload size in bytes
  ram_sp #(
      .DATA_WIDTH(36),
      .ADDR_WIDTH(9),
      .INIT(HTTP_SIZE_FILE)
  ) cam_size (
      .clk (clk),
      .we  ('0),
      .addr(key),
      .di  ('0),
      .dout(cam_content_meta)
  );

endmodule
