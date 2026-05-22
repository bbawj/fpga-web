module sdram_dummy #(
    parameter INIT = ""
) (
    input clk,
    input rst,

    input wr_req,
    input [18:0] wr_ad,
    input [31:0] wr_data,
    output reg wr_granted,

    input rd_req,
    input [18:0] rd_ad,
    output reg rd_valid,
    output reg [31:0] rd_data,
    output reg rd_granted
);
  reg [31:0] mem[270000];
  if (INIT != "") initial $readmemh(INIT, mem);

  reg [1:0] state = 0;
  always @(posedge clk) begin
    case (state)
      0: begin
        rd_granted <= 0;
        wr_granted <= 0;
        rd_valid <= 0;
        state <= wr_req ? 1 : (rd_req ? 2 : 0);
      end
      1: begin
        wr_granted <= 1;
        mem[wr_ad] <= wr_data;
        state <= 0;
      end
      2: begin
        rd_granted <= 1;
        rd_data <= mem[rd_ad];
        rd_valid <= 1;
        state <= 0;
      end
      default: state <= 0;
    endcase
  end
endmodule
