`default_nettype none
/**
* Pulls flash memory into SDRAM
*/
module flash2sdram #(
    parameter NUM_BYTES = 64
) (
    input wire clk,
    input wire rst,
    input wire readback,
    input wire spi_data_valid,
    input wire [7:0] spi_data,
    input wire sdram_wr_granted,
    output reg sdram_wr_req,
    output reg [18:0] sdram_wr_ad,
    output reg [31:0] sdram_wr_data,

    input wire sdram_rd_granted,
    output reg sdram_rd_req,
    output reg [18:0] sdram_rd_ad,

    output reg spi_ready,
    output reg [31:0] spi_32,
    output reg done = 0
);
  // 32-bit words
  localparam NUM_WORD = NUM_BYTES / 4;

  reg [15:0] write_counter = 0, read_counter = 0;
  reg [1:0] spi_counter = 0;
  reg [1:0] state = 0;
  // reg spi_ready = 0;
  always @(posedge clk) begin
    if (rst) begin
      state <= 0;
      done <= 0;
      spi_counter <= 0;
      spi_ready <= 0;
      write_counter <= 0;
      read_counter <= 0;
      sdram_wr_ad <= 0;
      sdram_wr_req <= 0;
      sdram_rd_req <= 0;
      sdram_rd_ad <= 0;
    end else begin
      spi_counter <= spi_counter + (spi_data_valid ? 1 : 0);
      spi_ready <= spi_counter == 'd3 && spi_data_valid;
      spi_32 <= spi_data_valid ? {spi_data, spi_32[31:8]} : spi_32;
      write_counter <= write_counter + (sdram_wr_granted ? 1 : 0);
      read_counter <= read_counter + (sdram_rd_granted ? 1 : 0);
      case (state)
        0: begin
          sdram_rd_req <= '0;
          sdram_wr_req <= '0;
          if (spi_ready) begin
            sdram_wr_req <= 1'b1;
            sdram_wr_data <= spi_32;
            state <= 1;
          end else if (write_counter == NUM_WORD) begin
            state <= readback ? 2 : 3;
          end
        end
        1: begin
          if (sdram_wr_granted) begin
            sdram_wr_req <= 1'b0;
            sdram_wr_ad <= sdram_wr_ad + 'd1;
            state <= 0;
          end
        end
        2: begin
          sdram_rd_req <= read_counter < NUM_BYTES / 4;
          sdram_rd_ad  <= sdram_rd_ad + (sdram_rd_granted ? 'd1 : 0);
          if (read_counter == NUM_BYTES / 4) state <= 3;
        end
        3: begin
          sdram_rd_req <= '0;
          sdram_wr_req <= '0;
          done <= 1'b1;
        end
        default: state <= 0;
      endcase
    end
  end
endmodule
