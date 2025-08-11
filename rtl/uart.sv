`default_nettype	none
module uart #(
  parameter [2:0] BAUD_RATE = '0
)(
  input wire clk,
  input wire rst,
  input wire valid,
  input wire [7:0] rx,
  output wire rdy,
  output wire tx
);

reg fifo_rd_en = 0;
wire fifo_empty, fifo_full;
reg [7:0] fifo_dout;
fifo _fifo (.clk(clk), .rst(rst), .wr_en(valid), .din(rx), .full(fifo_full),
  .rd_en(fifo_rd_en), .dout(fifo_dout), .empty(fifo_empty), .count());

typedef enum {IDLE, START, DATA, STOP} UART_STATE;
UART_STATE uart_state = IDLE;

`ifdef SPEED_100M
localparam CLOCKS_PER_BAUD = 25_000_000 / 9600;
`else
localparam CLOCKS_PER_BAUD = 125_000_000 / 9600;
`endif
reg [31:0] counter = CLOCKS_PER_BAUD;
always @(posedge clk) begin
  if (rst || counter == 0) counter <= CLOCKS_PER_BAUD - 1;
  else if (uart_state > IDLE) counter <= counter - 1;
end

reg [2:0] bit_counter = '0;
reg [8:0] shift_dout = '1;
assign tx = shift_dout[0];

always @(posedge clk) begin
  if (rst) begin
    uart_state <= IDLE;
    bit_counter <= '0;
    fifo_rd_en <= 0;
    shift_dout <= '1;
  end else begin
    case (uart_state)
      IDLE: begin
        fifo_rd_en <= 0;
        if (!fifo_empty) begin
          uart_state <= START;
          fifo_rd_en <= 1;
          shift_dout <= {shift_dout[8:1], 1'b0};
        end
      end
      START: begin
        fifo_rd_en <= 0;
        if (counter == 0) begin
          uart_state <= DATA;
          shift_dout <= {1'b1, fifo_dout};
        end
      end
      DATA: begin
        fifo_rd_en <= 0;
        if (counter == 0) begin
          bit_counter <= bit_counter + 1;
          shift_dout <= {1'b1, shift_dout[8:1]};
          if (bit_counter == 3'd7) begin
            uart_state <= STOP;
            shift_dout <= '1;
          end
        end
      end
      // technically same as IDLE since we are only 1 STOP bit
      STOP: begin
        fifo_rd_en <= 0;
        if (counter == 0) begin
          if (fifo_empty) begin
            uart_state <= IDLE;
          end else begin
            uart_state <= START;
            fifo_rd_en <= 1;
            shift_dout <= 9'b111111110;
          end
        end
      end
      default: begin
        uart_state <= IDLE;
        shift_dout <= '1;
        fifo_rd_en <= 0;
      end
    endcase
  end
end

`ifdef FORMAL
logic f_past_valid;
initial f_past_valid = 0;
initial assume(valid == 1'b0);
wire [8:0] temp;


always @(posedge clk) begin
  f_past_valid <= 1'b1;
  if (f_past_valid) begin
    if 
    if (fifo_empty) assert(!fifo_rd_en);
  end
end

always @* begin
  temp = {9'('1), fifo_dout[7:bit_counter]};
  assume (!rst);
  if (f_past_valid) begin
    case(uart_state)
      IDLE: begin
        assert(shift_dout == '1);
        assert(tx == 1);
      end
      START: begin
        assert(shift_dout == 9'b111111110);
        assert(tx == 0);
      end
      DATA: begin 
        assert(fifo_rd_en == 0);
      end
      STOP: begin
        assert(shift_dout == '1);
        assert(tx == 1);
      end
    endcase
  end
end
`endif


endmodule
