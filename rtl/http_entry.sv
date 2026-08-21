module http_entry #(
    parameter MAX_ENTRIES = 512
) (
    input clk,
    input rst,
    input [8:0] key,
    input reg mem_rd_valid,
    input reg [31:0] mem_rd_data,

    output rdy,
    output reg mem_rd_en,
    output reg [18:0] mem_rd_ad,
    output reg [18:0] content_addr,
    output reg [15:0] content_size,
    output reg [15:0] content_checksum
);
  // 512 entries of 18 bit data, each is an address to SDRAM
  (*keep*) reg [31:0] cam_content_addr, cam_content_meta;
  always @(posedge clk) begin
    content_addr <= cam_content_addr[18:0];
    content_size <= cam_content_meta[15:0];
    content_checksum <= 0;
  end

  typedef enum {
    IDLE,
    INIT,
    LOAD_ADDR,
    LOAD_SIZE
  } state_t;
  state_t state, next_state;
  reg [9:0] counter;
  always @(posedge clk) begin
    if (rst) begin
      state <= INIT;
      rdy   <= 0;
    end else begin
      state <= next_state;
      rdy   <= state == IDLE;
    end
  end

  always @(posedge clk) begin
    case (state)
      LOAD_ADDR, LOAD_SIZE: begin
        mem_rd_en <= 1;
        mem_rd_ad <= {9'b0, counter};
        if (mem_rd_valid) counter <= counter + 'd1;
      end
      default: begin
        mem_rd_ad <= '0;
        counter   <= '0;
      end
    endcase
  end

  always_comb begin
    next_state = state;
    case (state)
      IDLE: begin
      end
      INIT: next_state = LOAD_ADDR;
      LOAD_ADDR: if (mem_rd_valid && counter == MAX_ENTRIES - 1) next_state = LOAD_SIZE;
      LOAD_SIZE: if (mem_rd_valid && counter == (MAX_ENTRIES * 2) - 1) next_state = IDLE;
      default: begin
      end
    endcase
  end

  ram_sp #(
      .DATA_WIDTH(32),
      .ADDR_WIDTH(9)
  ) cam_addr (
      .clk (clk),
      .we  (mem_rd_valid && state == LOAD_ADDR),
      .addr(state == IDLE ? key : counter[8:0]),
      .di  (mem_rd_data),
      .dout(cam_content_addr)
  );
  // 512 entries to payload size in bytes
  ram_sp #(
      .DATA_WIDTH(32),
      .ADDR_WIDTH(9)
  ) cam_size (
      .clk (clk),
      .we  (mem_rd_valid && state == LOAD_SIZE),
      .addr(state == IDLE ? key : counter[8:0]),
      .di  (mem_rd_data),
      .dout(cam_content_meta)
  );

endmodule
