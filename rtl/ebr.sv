`default_nettype none

module ebr #(
    parameter int WR_WIDTH = 8,
    parameter int RD_WIDTH = WR_WIDTH,
    parameter int SIZE = 32,  // in units of WR_WIDTH
    parameter int SIZE_WIDTH = $clog2(SIZE)
) (
    input wr_clk,
    input wr_en,
    input [SIZE_WIDTH-1:0] wr_addr,
    input [WR_WIDTH-1:0] wr_data,

    input rd_clk,
    input rd_en,
    input [SIZE_WIDTH-1:0] rd_addr,
    output reg [RD_WIDTH-1:0] rd_data
);
  reg [WR_WIDTH-1:0] mem[0:SIZE-1];

  reg [SIZE_WIDTH-1:0] wr_ptr;
  reg wr_started = '0;

  always @(posedge wr_clk) begin
    if (wr_en) begin
      if (!wr_started) begin
        wr_ptr <= wr_addr + 1;
        mem[wr_addr] <= wr_data;
        wr_started <= 1;
      end else begin
        mem[wr_ptr] <= wr_data;
        wr_ptr <= wr_ptr + 1;
      end
    end else begin
      wr_started <= 0;
      wr_ptr <= 0;
    end
  end

  // Read side - assembles 4x 8-bit words into 32-bit
  localparam logic [SIZE_WIDTH-1:0] RATIO = (SIZE_WIDTH'(RD_WIDTH / WR_WIDTH));
  reg rd_started = '0;
  reg [SIZE_WIDTH-1:0] rd_ptr;

  always @(posedge rd_clk) begin
    if (rd_en) begin
      if (!rd_started) begin
        rd_ptr <= rd_addr + 1;
        for (logic [SIZE_WIDTH-1:0] i = 0; i < RATIO; i++) begin
          rd_data[i*WR_WIDTH+:WR_WIDTH] <= mem[rd_ptr+i];
        end
        rd_ptr <= rd_ptr + RATIO;
        rd_started <= 1;
      end else begin
        for (logic [SIZE_WIDTH-1:0] i = 0; i < RATIO; i++) begin
          rd_data[i*WR_WIDTH+:WR_WIDTH] <= mem[rd_ptr+i];
        end
        rd_ptr <= rd_ptr + RATIO;
      end
    end else begin
      rd_started <= 0;
      rd_ptr <= 0;
      rd_data <= 0;
    end
  end
endmodule
