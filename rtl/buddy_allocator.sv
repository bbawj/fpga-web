`default_nettype none
/**
* A binary buddy memory allocator based on https://ieeexplore.ieee.org/document/485574
* Referencing slides from: https://www.eecg.utoronto.ca/~jzhu/publications/doc/ksjtalk.pdf
*
* The allocator has a fixed latency of NUM_BLOCKS_WIDTH + 1 to find a free
* block.
*/
module buddy_allocator #(
    // size of minimum allocatable unit (smallest block)
    parameter MAU = 32,
    parameter NUM_BLOCKS = 32,
    // Also the number of levels in the tree used to find a free block
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
  localparam LEVELS = NUM_BLOCKS_WIDTH;

  // reg [MAU-1:0] mem[0:NUM_BLOCKS-1];
  // 1 if used, 0 if unused. Maps to "mem".
  reg  [NUM_BLOCKS-1:0] used_list;
  // Construct a binary tree to represent the used_list. For NUM_BLOCKS, there
  // will be a depth of log2(NUM_BLOCKS) with a total of NUM_BLOCKS - 1 nodes.
  // The leaf nodes are the used_list.
  /* verilator lint_off UNOPTFLAT */
  wire [NUM_BLOCKS-2:0] or_tree;
  /* verilator lint_on UNOPTFLAT */

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
  reg [LEVELS-1:0] level_sel;
  /* verilator lint_off UNOPTFLAT */
  logic [NUM_BLOCKS-2:0] and_tree;
  /* verilator lint_on UNOPTFLAT */
  logic [NUM_BLOCKS-2:0] addr_tree;
  generate
    logic [NUM_BLOCKS-1:0] connections;
    // This first part is to create the mapping from or_tree to and_tree,
    // which depensd on whether the leaf node is divisible by the depth that
    // we are evaluating. This explanation is quite bad. Refer to Section 3.2:
    // https://lup.lub.lu.se/luur/download?func=downloadFile&recordOId=9203188&fileOId=9203204
    // ck = bklS + M1lS−1 + M2lS−2 + · · · + MS−1l1 + MSl0
    // Mi = ( 1, if (k mod 2i) ̸= 0,
    //        n2S−i+k/2 i , if (k mod 2i) = 0
    for (i = 0; i < NUM_BLOCKS; i = i+1) begin
      logic [LEVELS-1:0] comb;
      for (j = 0; j < LEVELS; j = j + 1) begin
        if (j == 0) assign comb[j] = used_list[i] & level_sel[j];
        else begin
          // logic or_val = or_tree[NUM_BLOCKS - (NUM_BLOCKS / (1<< (j-1))) + (i/(1<<j))];
          localparam [NUM_BLOCKS_WIDTH-1:0]odd = (i >> (j-1));
          assign comb[j] = (odd[0] | or_tree[NUM_BLOCKS - (NUM_BLOCKS >> (j-1)) + (i>>j)]) & level_sel[j];
        end
      end
      assign connections[i] = |comb;
    end
    for (i = NUM_BLOCKS; i > 1; i = i / 2) begin
      for (j = 0; j < i; j = j + 2) begin
        if (i == NUM_BLOCKS) begin
          assign and_tree[NUM_BLOCKS - i + j/2] = connections[j] & connections[j+1];
          assign addr_tree[NUM_BLOCKS - i + j/2] = connections[j];
        end else begin
          assign and_tree[NUM_BLOCKS - i + j/2] = and_tree[NUM_BLOCKS - (i*2) + j] & and_tree[NUM_BLOCKS - (i*2) + j + 1];
          assign addr_tree[NUM_BLOCKS - i + j/2] = and_tree[NUM_BLOCKS - (i*2) + j];
        end
        end
      end
  endgenerate

  reg [$clog2(NUM_BLOCKS_WIDTH):0] idx_msb;
  reg request_valid, request_valid_comb, more_than_one;
  reg [NUM_BLOCKS_WIDTH:0] search_idx = 0, search_idx_left, search_idx_right, idx, idx_left, idx_right;
  reg [$clog2(NUM_BLOCKS_WIDTH)-1:0] depth = 0;
  typedef enum {
    IDLE,
    CALC_SEARCH_DEPTH,
    SEARCH_STALL,
    SEARCH_STALL2,
    SEARCH_LAST,
    SEARCH_ADDR,
    SEARCH_FAIL,
    SEARCH_DONE
  } state_t;
  state_t state = IDLE, next_state;

  always_comb begin
    next_state = state;
    case (state)
      IDLE: if (en) next_state = CALC_SEARCH_DEPTH;
      CALC_SEARCH_DEPTH: begin
        if (request_valid) next_state = SEARCH_STALL;
        else next_state = SEARCH_FAIL;
      end
      SEARCH_STALL: next_state = SEARCH_STALL2;
      SEARCH_STALL2: next_state = SEARCH_ADDR;
      SEARCH_ADDR: begin
        if (search_idx>= NUM_BLOCKS / 2) next_state = SEARCH_LAST;
      end
      SEARCH_LAST: next_state = (&o_addr)? SEARCH_FAIL: SEARCH_DONE;
      SEARCH_DONE: next_state = IDLE;
      SEARCH_FAIL: next_state = IDLE;
      default: next_state = IDLE;
    endcase
  end

  always @(posedge clk) begin
    if (rst) begin
      state <= IDLE;
      used_list <= '0;
    end else begin
      state <= next_state;
      case (state)
        IDLE: begin
          o_err <= 1'b0;
          search_idx <= '0;
          search_idx_left <= 'd2;
          search_idx_right <= 'd1;
          idx <= NUM_BLOCKS-2;
          idx_left <= NUM_BLOCKS-4;
          idx_right <= NUM_BLOCKS-3;
          o_addr <= '0;
          o_valid <= '0;
          depth <= '0;
          request_valid <= |request_size;
          idx_msb       <= find_first_ms_bit(request_size);
        end
        CALC_SEARCH_DEPTH: begin
          for (int i = 0; i < LEVELS; i = i + 1) begin
            level_sel[i] <= i[$clog2(NUM_BLOCKS_WIDTH):0] == (idx_msb-1);
          end
          depth <= NUM_BLOCKS_WIDTH;
          // idx_msb       <= find_first_ms_bit(request_size);
          // search_idx_right <= search_idx * 2 + 1;
          // search_idx_left <= search_idx * 2 + 2;
        end
        SEARCH_FAIL: begin
          o_err   <= 1'b1;
          o_valid <= 1'b1;
        end
        SEARCH_DONE: begin
          o_err   <= 1'b0;
          o_valid <= 1'b1;
          for (
              logic [NUM_BLOCKS_WIDTH:0] temp_idx = 0;
              temp_idx < NUM_BLOCKS;
              temp_idx = temp_idx + 1
          ) begin
            if (temp_idx[NUM_BLOCKS_WIDTH-1:0] >= o_addr && temp_idx[NUM_BLOCKS_WIDTH-1:0] < o_addr + request_size)
              used_list[temp_idx[NUM_BLOCKS_WIDTH-1:0]] |= 1'b1;
          end
        end
        SEARCH_STALL: begin
          search_idx <= addr_tree[idx[NUM_BLOCKS_WIDTH-1:0]] ? search_idx_right : search_idx_left;
          idx <= addr_tree[idx[NUM_BLOCKS_WIDTH-1:0]] ? idx_right : idx_left;
          o_addr <= {o_addr[NUM_BLOCKS_WIDTH-2:0], addr_tree[idx[NUM_BLOCKS_WIDTH-1:0]]};
          depth <= depth - 1;
        end
        SEARCH_STALL2: begin
          search_idx_left <= search_idx * 2 + 2;
          search_idx_right <= search_idx * 2 + 1;
          idx_left <=  NUM_BLOCKS - 2 - (search_idx * 2 + 2);
          idx_right <=  NUM_BLOCKS - 2 - (search_idx * 2 + 1);
          // idx <= addr_tree[idx[NUM_BLOCKS_WIDTH-1:0]] ? idx_right : idx_left;
          // search_idx <= addr_tree[idx[NUM_BLOCKS_WIDTH-1:0]] ? search_idx_right : search_idx_left;
        end
        SEARCH_ADDR: begin
          depth <= depth - 1;
          search_idx_left <= search_idx * 2 + 2;
          search_idx_right <= search_idx * 2 + 1;
          idx_left <=  NUM_BLOCKS - 2 - (search_idx * 2 + 2);
          idx_right <=  NUM_BLOCKS - 2 - (search_idx * 2 + 1);
          idx <= addr_tree[idx[NUM_BLOCKS_WIDTH-1:0]] ? idx_right : idx_left;
          search_idx <= addr_tree[idx[NUM_BLOCKS_WIDTH-1:0]] ? search_idx_right : search_idx_left;
          o_addr <= {o_addr[NUM_BLOCKS_WIDTH-2:0], addr_tree[idx[NUM_BLOCKS_WIDTH-1:0]]};
        end
      endcase
    end
  end

  function automatic logic [$clog2(NUM_BLOCKS_WIDTH):0] find_first_ms_bit(input logic [NUM_BLOCKS_WIDTH-1:0] bv);
    logic [NUM_BLOCKS_WIDTH-1:0] temp;
    logic [$clog2(NUM_BLOCKS_WIDTH):0] idx;
    logic more_than_one;
    temp = bv;
    for (int i = 0; i < NUM_BLOCKS_WIDTH; i = i + 1) begin
        if (temp[0]) idx = $clog2(NUM_BLOCKS_WIDTH+1)'(i);
        temp = temp >> 1;
    end
    // For a request size e.g 14 ('b1110) index msb = 3. Round up to the
    // next largest block that can hold would be 16, index msb = 4.
    // The largest msb we can support is log2(NUM_BLOCKS), so our search
    // depth for this request is log2(NUM_BLOCKS) - index msb.
    more_than_one = (bv & ~(1 << idx)) != '0;
    idx = idx + (more_than_one ? 1 : 0);
    find_first_ms_bit = idx;
  endfunction

endmodule
