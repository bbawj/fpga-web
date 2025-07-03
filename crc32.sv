module crc32 # (
  CRC_POLY = 32'hEDB88320
)
(
  input wire clk,
  input wire rst,
  input wire en,
  input wire [3:0] din,
  output reg [31:0] crc_out
);

reg [31:0] crc_next = 32'hFFFFFFFF;
reg [31:0] crc_reg = 32'hFFFFFFFF;

integer i;
always @(*) begin
  crc_next = crc_reg;
  for (i = 0; i < 4; i = i + 1) begin
    if (crc_next[0] ^ din[i]) begin
      crc_next = {1'b0, crc_next[31:1]} ^ CRC_POLY;
    end else begin
      crc_next = {1'b0, crc_next[31:1]};
    end
  end
end

always @(posedge clk) begin
  if (rst) begin
    crc_out <= '0;
    crc_next <= 32'hFFFFFFFF;
  end else begin
    if (en) begin
      crc_reg <= crc_next;
      crc_out <= ~crc_next;
    end
  end
end

endmodule
