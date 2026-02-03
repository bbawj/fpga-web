`default_nettype none

module allocator #(
    // size of minimum allocatable unit (smallest block)
    parameter MAU = 32,
    parameter NUM_BLOCKS = 32,
    parameter NUM_BLOCKS_WIDTH = $clog2(NUM_BLOCKS)
) (
    input wire clk,
    input wire rst,
    input wire en,
    input [NUM_BLOCKS_WIDTH-1:0] request_size,
    // Allocated memory address
    output reg [NUM_BLOCKS_WIDTH-1:0] o_addr,
    // o_addr is valid
    output reg o_valid,
    // error with request. Could be the following:
    // 1. no free memory of at least request_size
    output reg o_err
);

  reg [MAU-1:0] mem[0:NUM_BLOCKS-1];
  // 1 if used, 0 if unused. Maps to "mem".
  reg [NUM_BLOCKS-1:0] used_list;
  // Construct a binary tree to represent the used_list. For NUM_BLOCKS, there 
  // will be a depth of log2(NUM_BLOCKS) with a total of NUM_BLOCKS - 1 nodes.
  // The leaf nodes are the used_list.
  wire [NUM_BLOCKS-2:0] or_tree;

  genvar i;
  genvar j;
  generate
    for (i = NUM_BLOCKS; i > 1; i = i / 2) begin
      for (j = 0; j < i; j = j + 2) begin
        if (i == NUM_BLOCKS) assign or_tree[NUM_BLOCKS-i+j/2] = used_list[j] | used_list[j+1];
        else
          assign or_tree[NUM_BLOCKS - i + j/2] = or_tree[NUM_BLOCKS - (i*2) + j] | or_tree[NUM_BLOCKS - (i*2) + j + 1];
      end
    end
  endgenerate

  // the AND-tree is used for a non-backtracking search of the first 0 in the used_list
  // A "0" means that there is a 0 from the root of this node. 
  // We can enhance this by storing the AND value of left child (also called the
  // A-bit by the paper), therby giving us a hint on which path to traverse. 
  // A "0" means that there is a 0 on the left side of the tree.
  // A bit truth-table:
  // 0 0 : 0
  // 1 1 : 0
  // 1 0 : 1
  // 0 1 : 0
  wire [NUM_BLOCKS-2:0] and_tree;
  // wire [NUM_BLOCKS-2:0] addr_tree;
  generate
    for (i = NUM_BLOCKS; i > 1; i = i / 2) begin
      for (j = 0; j < i; j = j + 2) begin
        if (i == NUM_BLOCKS) begin
          assign and_tree[NUM_BLOCKS-i+j/2] = used_list[j] & used_list[j+1];
          // assign addr_tree[NUM_BLOCKS - i + j/2] = used_list[j] & ~(used_list[j+1]); 
        end else begin
          assign and_tree[NUM_BLOCKS - i + j/2] = or_tree[NUM_BLOCKS - (i*2) + j] & or_tree[NUM_BLOCKS - (i*2) + j + 1];
          // assign addr_tree[NUM_BLOCKS - i + j/2] = and_tree[NUM_BLOCKS - (i*2) + j] & ~(and_tree[NUM_BLOCKS - (i*2) + j + 1]);
        end
      end
    end
  endgenerate


  // A block of the request_size is available if the round(request_size) to next
  // allocatable unit is available. The AU is available if one of the or-gates
  // on that AU's level is 1.
  // index 0: level 0 from bottom, etc.
  // wire [NUM_BLOCKS_WIDTH-1:0] free_level;
  // generate
  // for (i = 1, j = NUM_BLOCKS / 2; i < NUM_BLOCKS; i = i * 2, j = j ) begin
  //   assign free_level[i - 1] = |or_tree[i - 1: NUM_BLOCKS / (2];
  // end
  // endgenerate

  reg [$clog2(NUM_BLOCKS_WIDTH)-1:0] idx_msb;
  reg request_valid, more_than_one;
  reg [NUM_BLOCKS_WIDTH:0] search_idx = 0;
  reg [$clog2(NUM_BLOCKS_WIDTH)-1:0] depth = 0;
  typedef enum {
    IDLE,
    SEARCH_ADDR
  } STATE;
  STATE state = IDLE;

  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      used_list <= '0;
    end else begin
      case (state)
        IDLE: begin
          o_err <= 1'b0;
          if (en) begin
            // For a request size e.g 14 ('b1110) index msb = 3. Round up to the
            // next largest block that can hold would be 16, index msb = 4.
            // The largest msb we can support is log2(NUM_BLOCKS), so our search
            // depth for this request is log2(NUM_BLOCKS) - index msb.
            find_first_ms_bit(request_size, idx_msb, request_valid, more_than_one);
            if (request_valid) begin
              if (more_than_one) idx_msb <= idx_msb + 1;
              search_idx <= '0;
              o_addr <= '0;
              o_valid <= '0;
              depth <= '0;
              state <= SEARCH_ADDR;
            end else o_err <= 1'b1;
          end
        end
        SEARCH_ADDR: begin
          if (depth == NUM_BLOCKS_WIDTH) begin
            o_valid <= 1'b1;
            o_err   <= '0;
            state   <= IDLE;
            for (
                logic [NUM_BLOCKS_WIDTH:0] temp_idx = 0;
                temp_idx < NUM_BLOCKS;
                temp_idx = temp_idx + 1
            ) begin
              if (temp_idx >= o_addr && temp_idx < o_addr + request_size)
                used_list[temp_idx] |= 1'b1;
            end
          end else begin
            if ((depth == NUM_BLOCKS_WIDTH - idx_msb) && or_tree[NUM_BLOCKS - search_idx - 2] == 1'b1) begin
              o_err   <= 1'b1;
              o_valid <= 1'b1;
              state   <= IDLE;
            end

            depth <= depth + 1;
            // check P-bit of AND-tree, going left if value is 0 and right if value
            // is 1. However, since we are traversing from the end of the array,
            // going right means moving less than left which means a smaller search_idx
            // search_idx <= addr_tree[NUM_BLOCKS - search_idx - 2] == 1'b1 ? search_idx * 2 + 1 : search_idx * 2 + 2;
            if (search_idx < NUM_BLOCKS / 2) begin
              search_idx <= and_tree[NUM_BLOCKS - (search_idx * 2 + 2) - 2] == 1'b1 ? search_idx * 2 + 1 : search_idx * 2 + 2;
              // moving right in the tree can be visualized as having a lower
              // address, and moving left having a higher address.
              o_addr <= {
                o_addr[NUM_BLOCKS_WIDTH-2:0],
                (and_tree[NUM_BLOCKS-(search_idx*2+2)-2] == 1'b1 ? 1'b1 : 1'b0)
              };
            end else begin
              // we have come to the last level of the and_tree, we must check
              // the used_list directly for the P-bit. At this last level, index
              // 0 maps to used list index 0 and 1, index 1 maps to used list
              // 2 and 3 ... so forth. We are interested in the member to the
              // "left", i.e. index * 2.
              o_addr <= {
                o_addr[NUM_BLOCKS_WIDTH-2:0],
                (used_list[(NUM_BLOCKS-search_idx)*2] == 1'b1 ? 1'b1 : 1'b0)
              };
            end
          end
        end
      endcase
    end
  end

  task find_first_ms_bit(input logic [NUM_BLOCKS_WIDTH-1:0] bv,
                         output logic [$clog2(NUM_BLOCKS_WIDTH)-1:0] idx, output logic valid,
                         output logic more_than_one);
    logic [NUM_BLOCKS_WIDTH-1:0] temp;
    temp  = bv;
    valid = |bv;
    for (logic [NUM_BLOCKS_WIDTH:0] i = 0; i < NUM_BLOCKS_WIDTH; i = i + 1) begin
      idx  = temp[0] == 1'b1 ? i : idx;
      temp = temp >> 1;
    end
    more_than_one = (bv & ~(1 << idx)) != '0;
  endtask

endmodule
