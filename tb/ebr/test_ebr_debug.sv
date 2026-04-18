module test_ebr_debug (
    input  clk,
    input  button,
    output uart_tx
);
  reg button_q;
  reg wr_en, wr_started, rd_en;
  reg   [7:0] wr_data;

  logic [7:0] counter = 0;
  logic [1:0] state = 0;
  always @(posedge clk) begin
    button_q <= button;
    counter <= '0;
    rd_en <= '0;
    if (button_q && !button) begin
      wr_en   <= 1'b1;
      wr_data <= 8'hDE;
    end
    case (state)
      0: if (wr_en) state <= 2'd1;
      2'd1: begin
        if (counter == 8'd11) begin
          state <= 2'd2;
          wr_en <= 1'b0;
          rd_en <= 1'b1;
        end
        counter <= counter + 1;
      end
      2'd2: begin
        if (counter == 0) state <= 0;
        counter <= counter - 4;
      end
      default: state <= 0;
    endcase
  end

  reg uart_valid;
  reg [31:0] uart_data;
  ebr #(
      .SIZE(100),
      .RD_WIDTH(32)
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

  uart #(
      .DATA_WIDTH(32)
  ) _uart (
      .clk(clk),
      .rst(1'b0),
      .valid(uart_valid),
      .rx(uart_data),
      .rdy(),
      .tx(uart_tx)
  );
endmodule


