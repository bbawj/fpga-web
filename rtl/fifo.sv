module fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 64,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    // whether to use block RAM, not supported for all data & addr widths
    parameter EBR = 0
) (
    input wire clk,
    input wire rst,

    // Write interface
    input wire wr_en,
    input wire [DATA_WIDTH-1:0] din,
    output wire full,

    // Read interface  
    input rd_en,
    output reg [DATA_WIDTH-1:0] dout,
    output wire empty,

    // Status
    output wire [ADDR_WIDTH:0] count
);

  always @(posedge clk) begin
    if (rst) wr_ptr <= '0;
    else if (wr_en && !full) begin
      wr_ptr <= wr_ptr + 1;
    end
  end

  always @(posedge clk) begin
    if (rst) rd_ptr <= '0;
    else if (rd_en) begin
      rd_ptr <= rd_ptr + (empty ? 0 : 1);
    end
  end

  generate
    if (EBR == 0) begin
      reg [DATA_WIDTH-1:0] mem[0:DEPTH-1];

      always @(posedge clk) begin
        if (wr_en && !full) begin
          mem[wr_ptr[ADDR_WIDTH-1:0]] <= din;
        end
        if (rd_en && !empty) begin
          dout <= mem[rd_ptr[ADDR_WIDTH-1:0]];
        end
      end
    end else begin
      ram_wrap #(
          .DATA_WIDTH(DATA_WIDTH),
          .ADDR_WIDTH(ADDR_WIDTH)
      ) mem (
          .clk(clk),
          .wr_addr(wr_ptr[ADDR_WIDTH-1:0]),
          .rd_addr(rd_ptr[ADDR_WIDTH-1:0]),
          .din(din),
          .dout(dout),
          .wr_en(wr_en),
          .rd_en(rd_en),
          .rst(rst)
      );
    end
  endgenerate
  // additional bit here allows to differentiate between full and empty
  reg [ADDR_WIDTH:0] wr_ptr = '0, rd_ptr = '0;

  // Status flags
  assign full  = (wr_ptr - rd_ptr) == DEPTH;
  assign empty = (wr_ptr == rd_ptr);
  assign count = wr_ptr - rd_ptr;

`ifdef FORMAL
  initial assume (rst);
  initial f_past_valid = 1'b0;
  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    // expected ways to use this FIFO
    assume (~rd_en || (rd_en && ~empty));
    assume (~wr_en || (wr_en && ~full));
    // the data should remain the same as long as rd_en stays low
    if (f_past_valid && !$past(rd_en)) assert ($past(rst) || $stable(dout));
    assert (~(full && empty));
  end
`endif
endmodule
