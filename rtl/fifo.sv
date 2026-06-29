`default_nettype none
module fifo #(
    parameter DATA_WIDTH = 8,
    parameter REGMODE = "NOREG",
    parameter DEPTH = 512,
    parameter ADDR_WIDTH = $clog2(DEPTH),
    // whether to use block RAM, not supported for all data & addr widths
    parameter EBR = 0,
    parameter LOOKAHEAD = 0
) (
    input wire clk,
    input wire rst,

    // Write interface
    input wire wr_en,
    input wire [DATA_WIDTH-1:0] din,
    output reg full,

    // Read interface  
    input wire rd_en,
    output reg [DATA_WIDTH-1:0] dout,
    output reg empty,
    output reg valid,

    // Status
    output reg [ADDR_WIDTH:0] count
);
  if (EBR && LOOKAHEAD) $error("only non block RAM can support lookahead FIFO");

  // additional bit here allows to differentiate between full and empty
  reg [ADDR_WIDTH:0] wr_ptr = '0, rd_ptr = '0;
  wire [ADDR_WIDTH:0] next_wr_ptr, next_rd_ptr;
  assign next_wr_ptr = wr_ptr + 1;
  assign next_rd_ptr = rd_ptr + 1;

  always @(posedge clk) begin
    if (rst) wr_ptr <= '0;
    else if (wr_en && (!full || rd_en)) begin
      wr_ptr <= wr_ptr + 1;
    end
  end

  always @(posedge clk) begin
    if (rst) rd_ptr <= '0;
    else if (rd_en && !empty) begin
      rd_ptr <= rd_ptr + 1;
    end
  end

  generate
    if (EBR == 0) begin
      reg [DATA_WIDTH-1:0] mem[0:DEPTH-1];
      // initial begin
      //   for (int i = 0; i < DEPTH; i = i + 1) begin
      //     mem[i] = '0;
      //   end
      // end

      always @(posedge clk) begin
        if (wr_en && (!full || rd_en)) begin
          mem[wr_ptr[ADDR_WIDTH-1:0]] <= din;
        end
      end

      if (LOOKAHEAD) begin : g_lookahead
        always @(posedge clk) begin
          dout <= mem[rd_ptr[ADDR_WIDTH-1:0]];
        end
      end else begin : g_standard
        always @(posedge clk) begin
          if (rd_en && !empty) begin
            dout <= mem[rd_ptr[ADDR_WIDTH-1:0]];
          end
        end
      end
    end else begin
      ram_wrap #(
          .REGMODE(REGMODE),
          .WR_WIDTH(DATA_WIDTH),
          .RD_WIDTH(DATA_WIDTH),
          .ADDR_WIDTH(ADDR_WIDTH)
      ) mem_ (
          .wr_clk(clk),
          .rd_clk(clk),
          .wr_addr(wr_ptr[ADDR_WIDTH-1:0]),
          .rd_addr(rd_ptr[ADDR_WIDTH-1:0]),
          .din(din),
          .dout(dout),
          .wr_en(wr_en && (!full || rd_en)),
          .rd_en(rd_en && !empty),
          .rst(rst)
      );
    end
    if (REGMODE == "NOREG") begin
      always @(posedge clk) begin
        valid <= rd_en && !empty;
      end
    end else begin
      if (EBR == 0) begin
        reg rd_valid_q;
        always @(posedge clk) begin
          valid <= rd_en && !empty;
          // rd_valid_q <= rd_en && !empty;
          // valid <= rd_valid_q;
        end
      end else begin
        reg rd_valid_q, rd_valid_q2;
        always @(posedge clk) begin
          rd_valid_q <= rd_en && !empty;
          // rd_valid_q2 <= rd_valid_q;
          valid <= rd_valid_q;
        end
      end
    end
  endgenerate
  // Status flags
  // assign full = (wr_ptr - rd_ptr) == DEPTH;
  always @(posedge clk) begin
    if (rst) begin
      count <= 0;
    end else begin
      casez ({
        rd_en, wr_en, full, empty
      })
        'b10?0: begin
          count <= count - 1;
        end
        'b010?: begin
          count <= count + 1;
        end
        'b11?1: begin
          count <= count + 1;
        end
        default: begin
          count <= count;
        end
      endcase
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      full  <= 0;
      empty <= 1;
    end else begin
      casez ({
        rd_en, wr_en, full, empty
      })
        'b10?0: begin
          full  <= 0;
          empty <= next_rd_ptr == wr_ptr;
        end
        'b010?: begin
          full  <= (next_wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH] && next_wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
          empty <= 0;
        end
        'b11?1: begin
          full  <= (next_wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH] && next_wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
          empty <= 0;
        end
        default: begin
          full  <= full;
          empty <= empty;
        end
      endcase
    end
  end
  // assign empty = (wr_ptr == rd_ptr);
  // assign count = wr_ptr - rd_ptr;

`ifdef FORMAL
  // initial assume (rst);
  reg f_past_valid;
  initial f_past_valid = 1'b0;
  // reg [DATA_WIDTH-1:0] wr_target;
  // always_comb begin
  //   wr_target = mem[wr_ptr[ADDR_WIDTH-1:0]];
  // end
  reg [4:0] wr_count = 0;
  reg [4:0] rd_count = 0;
  always @(posedge clk) begin
    if (rst) begin
      wr_count <= 0;
      rd_count <= 0;
    end
    if (wr_count != 'b11111 && f_past_valid && !rst && wr_en && !full) wr_count <= wr_count + 1;
    if (rd_count != 'b11111 && f_past_valid && !rst && rd_en && !empty) rd_count <= rd_count + 1;
    if (f_past_valid && wr_count > rd_count) assert (!empty);
  end
  always @(posedge clk) begin
    if (rst) f_past_valid <= 1;
    // the data should remain the same as long as rd_en stays low
    if (f_past_valid && !$past(rd_en)) assert ($past(rst) || $stable(dout));
    // assert (~(full && empty));
    if (f_past_valid) assert (count <= DEPTH);
    if (f_past_valid && count == DEPTH) assert (full);
    if (!rst && !$past(
            rst
        ) && $stable(
            rd_ptr
        ) && rd_ptr == $past(
            wr_ptr
        ) && f_past_valid && $past(
            wr_en
        ) && $past(
            full
        ))
      assert ($stable(dout));

    if (f_past_valid && !$past(rst) && $past(wr_en) && $past(full) && !$past(rd_en))
      assert (wr_ptr == $past(wr_ptr));

    if (f_past_valid && !$past(rst) && $past(rd_en) && $past(empty))
      assert (rd_ptr == $past(rd_ptr));

    if (f_past_valid) assert ((count == 0 && empty) || (count != 0 && !empty));

    if (f_past_valid && !$past(rst) && $past(empty) && !$past(wr_en))
      assert (rd_ptr == $past(rd_ptr));

    if (f_past_valid) assert (count == wr_ptr - rd_ptr);
    // after a write with no intervening read, mem at wr_ptr-1 holds din
  end
`endif
endmodule
