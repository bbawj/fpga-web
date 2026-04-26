module http_entry #(
    parameter string CAM_ADDR_FILE = "",
    parameter string CAM_SIZE_FILE = ""
) (
    input clk,
    input [8:0] key,

    output reg [18:0] content_addr,
    output reg [15:0] content_size
);
  // 512 entries of 18 bit data, each is an address to SDRAM
  reg [35:0] cam_content_addr, cam_content_size;
  assign content_addr = cam_content_addr[18:0];
  assign content_size = cam_content_size[15:0];
  ram_sp #(
      .DATA_WIDTH(36),
      .ADDR_WIDTH(9),
      .INIT(CAM_ADDR_FILE)
  ) cam_addr (
      .clk (clk),
      .we  ('0),
      .addr(key),
      .di  (),
      .dout(cam_content_addr)
  );
  // 512 entries to payload size in bytes
  ram_sp #(
      .DATA_WIDTH(36),
      .ADDR_WIDTH(9),
      .INIT(CAM_SIZE_FILE)
  ) cam_size (
      .clk (clk),
      .we  ('0),
      .addr(key),
      .di  (),
      .dout(cam_content_size)
  );

endmodule
