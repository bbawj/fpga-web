module test_sdram_debug (
    input clk,
    input rst,
    output sdram_rd_granted,
    output sdram_rd_valid,
    output sdram_wr_granted,
    // SDRAM interface
    output wire [1:0] sdram_ba,
    output wire sdram_we_n,
    output wire sdram_cas_n,
    output wire sdram_ras_n,
    output wire sdram_clk,
    inout [31:0] sdram_dq,
    output wire [10:0] sdram_addr,

    output uart_tx
);

  reg sdram_wr_req = '0;
  reg [18:0] sdram_wr_ad, sdram_rd_ad;
  reg [31:0] sdram_wr_data;
  wire [31:0] sdram_rd_data;
  reg sdram_rd_req = '0;
  sdram_ctrl m (
      .clk(clk),
      .rst(rst),

      .wr_req(sdram_wr_req),
      .wr_ad(sdram_wr_ad),
      .wr_data(sdram_wr_data),
      .wr_granted(sdram_wr_granted),

      .rd_req(sdram_rd_req),
      .rd_ad(sdram_rd_ad),
      .rd_valid(sdram_rd_valid),
      .rd_data(sdram_rd_data),
      .rd_granted(sdram_rd_granted),

      .sdram_ba(sdram_ba),
      .sdram_we_n(sdram_we_n),
      .sdram_cas_n(sdram_cas_n),
      .sdram_ras_n(sdram_ras_n),
      .sdram_clk(sdram_clk),
      .sdram_dq(sdram_dq),
      .sdram_addr(sdram_addr)
  );

  reg uart_valid, uart_rdy;
  reg [31:0] uart_data = '0;
  uart #(
      .FREQ(125_000_000),
      .BUF_USE_BLOCKRAM(0),
      .DATA_WIDTH(32)
  ) uart (
      .clk(clk),
      .rst(rst),
      .valid(uart_valid),
      .rx(uart_data),
      .rdy(uart_rdy),
      .tx(uart_tx)
  );

  reg init = 1'b0;
  reg [31:0] counter;
  reg [1:0] state;

  always @(posedge clk) begin
    uart_valid <= 0;
    if (rst) begin
      counter <= 0;
      sdram_rd_ad <= 0;
      sdram_wr_ad <= 0;
      state <= 0;
    end else begin
      case (state)
        0: begin
          sdram_wr_req  <= counter < 'd8;
          sdram_wr_data <= counter;
          if (sdram_wr_granted) begin
            state <= 1;
            sdram_wr_req <= 0;
            sdram_wr_ad <= sdram_wr_ad + 1;
          end
        end
        1: begin
          sdram_rd_req <= 1;
          if (sdram_rd_granted) begin
            sdram_rd_req <= 0;
            state <= 2;
          end
        end
        2: begin
          if (sdram_rd_valid) begin
            uart_valid <= 1;
            uart_data <= counter;
            sdram_rd_ad <= sdram_rd_ad + 1;
            state <= 0;
            counter <= counter + 1;
          end
        end
        default: state <= 0;
      endcase
    end
  end
endmodule
