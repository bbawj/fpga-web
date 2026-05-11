module test_ebr_debug #(
    parameter WIDE_READ = 0,
    parameter USE_BLOCK_RAM = 0
) (
    input  clk,
    input  button,
    output uart_tx
);
  reg button_q;
  reg wr_en = 0, wr_started, rd_en = 0;
  logic [7:0] counter = 0;
  logic [1:0] state = 0;
  localparam [31:0] PAYLOAD = 'hDEADBEEF;

  GSR GSR_INST (.GSR(1'b1));
  PUR PUR_INST (.PUR(1'b1));

  generate
    if (WIDE_READ) begin
      reg [7:0] wr_data;
      always @(posedge clk) begin
        button_q <= button;
        counter  <= '0;
        case (state)
          0: if (button_q && !button) state <= 2'd1;
          2'd1: begin
            wr_en   <= 1'b1;
            rd_en   <= 1'b0;
            wr_data <= counter;
            if (counter == 8'd3) begin
              state <= 2'd2;
              wr_en <= 1'b0;
              rd_en <= 1'b1;
            end
            counter <= counter + 1;
          end
          2'd2: begin
            // if (counter == 0) begin
            state <= 0;
            rd_en <= 0;
            // end
            // counter <= counter - 4;
          end
          default: state <= 0;
        endcase
      end

      ebr #(
          .USE_BLOCKRAM(1),
          .RD_WIDTH(32),
          .ADDR_WIDTH(11)
      ) tcp_incoming_buffer (
          .wr_clk(clk),
          .wr_en(wr_en),
          .wr_addr('0),
          .wr_data(wr_data),
          .rd_clk(clk),
          .rd_en(rd_en),
          .rd_addr('0),
          .rd_valid(uart_valid),
          .rd_data(uart_data)
      );

      reg uart_valid;
      reg [31:0] uart_data;
      uart #(
          .DATA_WIDTH(32),
          .BUF_USE_BLOCKRAM(USE_BLOCK_RAM)
      ) _uart (
          .clk(clk),
          .rst(1'b0),
          .valid(uart_valid),
          .rx(uart_data),
          .rdy(),
          .tx(uart_tx)
      );
    end else begin
      reg [31:0] wr_data;
      always @(posedge clk) begin
        wr_data  <= 'h12341234;
        button_q <= button;
        case (state)
          0:
          if (button_q && !button) begin
            state   <= 2'd1;
            counter <= '0;
          end
          2'd1: begin
            wr_en <= 1'b1;
            rd_en <= 1'b0;
            if (counter == 'd8) begin
              state <= 'd2;
              wr_en <= 1'b0;
              rd_en <= 1'b1;
            end
            counter <= counter + 4;
          end
          2'd2: begin
            rd_en <= 1'b1;
            wr_en <= '0;
            if (counter == 'd0) begin
              state <= 0;
              rd_en <= 0;
            end
            counter <= counter - 1;
          end
          default: state <= 0;
        endcase
      end

      ebr #(
          .REGMODE("OUTREG"),
          .USE_BLOCKRAM(1),
          .RD_WIDTH(32),
          .WR_WIDTH(32),
          .ADDR_WIDTH(11)
      ) tcp_incoming_buffer (
          .wr_clk(clk),
          .wr_en(wr_en),
          .wr_addr('0),
          .wr_data(wr_data),
          .rd_clk(clk),
          .rd_en(rd_en),
          .rd_addr('0),
          .rd_valid(uart_valid),
          .rd_data(uart_data)
      );

      reg uart_valid;
      reg [31:0] uart_data;
      uart #(
          .BUF_USE_BLOCKRAM(0),
          .DATA_WIDTH(31),
      ) _uart (
          .clk(clk),
          .rst(1'b0),
          .valid(uart_valid),
          .rx(uart_data),
          .rdy(),
          .tx(uart_tx)
      );
    end
  endgenerate
endmodule


