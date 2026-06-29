`default_nettype none

module ebr #(
    parameter USE_BLOCKRAM = 1,
    parameter REGMODE = "NOREG",
    parameter WR_WIDTH = 8,
    parameter RD_WIDTH = WR_WIDTH,
    parameter int ADDR_WIDTH
) (
    input wire wr_clk,
    input wire wr_en,
    input wire [ADDR_WIDTH-1:0] wr_addr,
    input wire [WR_WIDTH-1:0] wr_data,

    input wire rd_clk,
    input wire rd_en,
    input wire [ADDR_WIDTH-1:0] rd_addr,
    output reg rd_valid,
    output reg [RD_WIDTH-1:0] rd_data
);

  reg [ADDR_WIDTH-1:0] wr_ptr, rd_ptr;
  ram_wrap #(
      .USE_BLOCKRAM(USE_BLOCKRAM),
      .REGMODE(REGMODE),
      .ADDR_WIDTH(ADDR_WIDTH),
      .WR_WIDTH(WR_WIDTH),
      .RD_WIDTH(RD_WIDTH)
  ) mem (
      .wr_clk(wr_clk),
      .wr_en(wr_en),
      .wr_addr(wr_ptr),
      .din(wr_data),
      .rst(1'b0),
      .rd_clk(rd_clk),
      .rd_en(rd_en),
      .rd_addr(rd_ptr),
      .dout(rd_data)
  );
  always @(posedge wr_clk) begin
    wr_ptr <= wr_en ? wr_ptr + 1 : wr_addr;
  end
  always @(posedge rd_clk) begin
    rd_ptr <= rd_en ? rd_ptr + 1 : rd_addr;
  end

  generate
    if (USE_BLOCKRAM == 0) begin
      // reg rd_valid_q;
      always @(posedge rd_clk) begin
        rd_valid <= rd_en;
        // rd_valid   <= rd_valid_q;
      end
    end else begin
      if (REGMODE == "NOREG") begin
        reg rd_valid_q;
        always @(posedge rd_clk) begin
          rd_valid <= rd_en;
        end
      end else begin
        // if (USE_BLOCKRAM == 0) begin
        reg rd_valid_q, rd_valid_q2;
        // always @(posedge rd_clk) begin
        //   rd_valid_q <= rd_en;
        //   rd_valid <= rd_valid_q;
        // end
        // end else begin
        always @(posedge rd_clk) begin
          rd_valid_q <= rd_en;
          rd_valid   <= rd_valid_q;
        end
        // end
      end
    end
  endgenerate

endmodule
