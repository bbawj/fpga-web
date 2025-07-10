module crc32 # (
  CRC_POLY = 32'hEDB88320
)
(
  input wire [3:0] din,
  input wire [31:0] crc_next,
  output reg [31:0] crc_out
);

integer i;
always @(*) begin
  crc_out = crc_next;
  for (i = 0; i < 4; i = i + 1) begin
    if (crc_out[0] ^ din[i]) begin
      crc_out = {1'b0, crc_out[31:1]} ^ CRC_POLY;
    end else begin
      crc_out = {1'b0, crc_out[31:1]};
    end
  end
end

endmodule
