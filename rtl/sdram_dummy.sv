`default_nettype none

module sdram_dummy #(
    parameter INIT = ""
) (
    input wire clk,
    input wire rst,

    input wire wr_req,
    input wire [18:0] wr_ad,
    input wire [31:0] wr_data,
    output reg wr_granted,

    input wire rd_req,
    input wire [18:0] rd_ad,
    output reg rd_valid,
    output reg [31:0] rd_data,
    output reg rd_granted,
    output reg boot_done
);
`ifdef SYNTHESIS
  ram_wrap #(
      .REGMODE("OUTREG"),
      .USE_BLOCKRAM(1),
      .WR_WIDTH(32),
      .RD_WIDTH(32),
      .ADDR_WIDTH(9)
  ) mem_ (
      .wr_clk(clk),
      .rd_clk(clk),
      .wr_addr(wr_ad[8:0]),
      .rd_addr(rd_ad[8:0]),
      .din(wr_data),
      .dout(rd_data),
      .wr_en(wr_granted),
      .rd_en(rd_granted),
      .rst(rst)
  );
  reg [1:0] state = 0;
  always @(posedge clk) begin
    case (state)
      0: begin
        rd_granted <= 0;
        wr_granted <= 0;
        state <= wr_req ? 1 : (rd_req ? 2 : 0);
      end
      1: begin
        wr_granted <= 1;
        state <= 0;
      end
      2: begin
        rd_granted <= 1;
        state <= 0;
      end
      default: state <= 0;
    endcase
  end
  reg rd_valid_q;
  always @(posedge clk) begin
    rd_valid_q <= rd_granted;
    rd_valid   <= rd_valid_q;
  end
`else
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
`endif

  always @(posedge clk) begin
    boot_done <= 1;
  end
endmodule
