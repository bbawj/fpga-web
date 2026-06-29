module ram_sp #(
    parameter int DATA_WIDTH = 1,
    parameter int ADDR_WIDTH = 1,
    parameter INIT = ""
) (
    input clk,
    we,
    input [ADDR_WIDTH-1:0] addr,
    input [DATA_WIDTH-1:0] di,
    output reg [DATA_WIDTH-1:0] dout
);

  localparam SIZE =
    DATA_WIDTH == 1 ? 16384 :
    DATA_WIDTH == 2 ? 8192 :
    DATA_WIDTH <= 4 ? 4096 :
    DATA_WIDTH <= 9 ? 2048 :
    DATA_WIDTH <= 18 ? 1024:
    DATA_WIDTH <= 36 ? 512: 0;

  if (SIZE == 0 || ADDR_WIDTH == 0 || DATA_WIDTH == 0) $error();

  (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem[SIZE];

  if (INIT != "") initial $readmemh(INIT, mem);

  always @(posedge clk) begin
    if (we) mem[addr] <= di;
    else dout <= mem[addr];
  end

endmodule
