`default_nettype none
module uart #(
    parameter DATA_WIDTH = 8,
    parameter BAUD_RATE  = 38400
) (
    input wire clk,
    input wire rst,
    input wire valid,
    input wire [DATA_WIDTH-1:0] rx,
    output wire rdy,
    output wire tx
);

  reg fifo_rd_en = 0;
  wire fifo_empty, fifo_full;
  reg [DATA_WIDTH - 1:0] fifo_dout, fifo_dout_q;
  fifo #(
      .DATA_WIDTH(DATA_WIDTH),
      .DEPTH(128)
  ) _fifo (
      .clk  (clk),
      .rst  (rst),
      .wr_en(valid),
      .din  (rx),
      .full (fifo_full),
      .rd_en(fifo_rd_en),
      .dout (fifo_dout),
      .empty(fifo_empty),
      .count()
  );

  typedef enum {
    IDLE,
    START,
    DATA0,
    DATA1,
    DATA2,
    DATA3,
    DATA4,
    DATA5,
    DATA6,
    DATA7,
    STOP
  } uart_state_t;
  uart_state_t uart_state = IDLE, prev_uart_state;

`ifdef SPEED_100M
  localparam CLOCKS_PER_BAUD = 25_000_000 / BAUD_RATE;
`else
  localparam CLOCKS_PER_BAUD = 125_000_000 / BAUD_RATE;
`endif
  reg [31:0] counter = CLOCKS_PER_BAUD;
  always @(posedge clk) begin
    if (rst || counter == 0) counter <= CLOCKS_PER_BAUD - 1;
    else if (uart_state > IDLE) counter <= counter - 1;
  end

  reg [7:0] byte_counter = '0, prev_byte_counter = '0;
  reg [8:0] shift_dout = '1;
  assign tx = shift_dout[0];
  reg [31:0] working;

  always @(posedge clk) begin
    case (uart_state)
      IDLE: shift_dout <= '1;
      START: shift_dout <= '0;
      DATA0: begin
        shift_dout <= {1'b1, working[7:0]};
        if (counter == 0) shift_dout <= {1'b1, shift_dout[8:1]};
      end
      STOP, DATA1, DATA2, DATA3, DATA4, DATA5, DATA6, DATA7: begin
        if (counter == 0) shift_dout <= {1'b1, shift_dout[8:1]};
      end
      default: shift_dout <= '1;
    endcase
  end

  always @(posedge clk) begin
    prev_byte_counter <= byte_counter;
    if (byte_counter == 0) working <= fifo_dout_q;
    else if (prev_byte_counter != byte_counter) working <= working >> 8;
  end

  always @(posedge clk) begin
    prev_uart_state <= uart_state;
    fifo_rd_en <= 0;
    if (uart_state == START && prev_uart_state != START) begin
      fifo_rd_en <= 1;
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      uart_state   <= IDLE;
      byte_counter <= 0;
    end else begin
      case (uart_state)
        IDLE: begin
          if (!fifo_empty) begin
            uart_state <= START;
          end
        end
        START: begin
          fifo_dout_q <= fifo_dout;
          if (counter == 0) begin
            uart_state <= DATA0;
          end
        end
        DATA0: begin
          if (counter == 0) uart_state <= DATA1;
        end
        DATA1: begin
          if (counter == 0) uart_state <= DATA2;
        end
        DATA2: begin
          if (counter == 0) uart_state <= DATA3;
        end
        DATA3: begin
          if (counter == 0) uart_state <= DATA4;
        end
        DATA4: begin
          if (counter == 0) uart_state <= DATA5;
        end
        DATA5: begin
          if (counter == 0) uart_state <= DATA6;
        end
        DATA6: begin
          if (counter == 0) uart_state <= DATA7;
        end
        DATA7: begin
          if (counter == 0) begin
            uart_state   <= STOP;
            byte_counter <= byte_counter + 'b1;
          end
        end
        // technically same as IDLE since we are only 1 STOP bit
        STOP: begin
          if (counter == 0) begin
            if (byte_counter < DATA_WIDTH / 8) begin
              uart_state <= START;
            end else begin
              byte_counter <= '0;

              if (fifo_empty) begin
                uart_state <= IDLE;
              end else begin
                uart_state <= START;
              end
            end
          end
        end
        default: begin
          uart_state <= IDLE;
        end
      endcase
    end
  end

`ifdef FORMAL
  logic f_past_valid;
  initial f_past_valid = 0;
  initial assume (valid == 1'b0);


  always @(posedge clk) begin
    f_past_valid <= 1'b1;
    if (f_past_valid) begin
      if (fifo_empty) assert (!fifo_rd_en);
    end
  end

  always @* begin
    assume (!rst);
    if (f_past_valid) begin
      case (uart_state)
        IDLE: begin
          assert (shift_dout == '1);
          assert (tx == 1);
        end
        START: begin
          assert (shift_dout == 9'b111111110);
          assert (tx == 0);
        end
        DATA: begin
          assert (fifo_rd_en == 0);
        end
        STOP: begin
          assert (shift_dout == '1);
          assert (tx == 1);
        end
      endcase
    end
  end
`endif


endmodule
