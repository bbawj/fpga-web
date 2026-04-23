module spi_master (
    input  clk,
    input  spi_sclk,
    input  spi_miso,
    output spi_cs,
    output spi_mosi,
    output spi_clken,

    input rst,
    input i_en,
    input [23:0] i_size,
    input [23:0] i_addr,

    output reg o_data_valid,
    output reg [7:0] o_data
);

  reg [23:0] payload_counter;
  reg [ 2:0] state_counter;
  reg [ 7:0] shift;
  assign spi_mosi = shift[7];
  reg cs, clken;
  assign spi_cs = cs;
  assign spi_clken = clken;

  reg byte_valid, next_byte_valid;
  reg reload_en, next_reload_en;
  reg next_cs, next_clken;
  reg counter_reset, next_counter_reset;
  always @(posedge clk) begin
    if (rst) begin
      reload_en <= 1'b1;
      state <= IDLE;
      cs <= 1'b1;
      state_counter <= '0;
      clken <= '0;
    end else begin
      cs <= next_cs;
      clken <= next_clken;
      reload_en <= next_reload_en;
      counter_reset <= next_counter_reset;
      state <= next_state;
      state_counter <= (state != IDLE && !counter_reset) ? state_counter + 'd1 : '0;
      payload_counter <= (state == IDLE) ? '0 : (state == DATA && state_counter == 'd7) ? payload_counter + 'd1 : payload_counter;

      if (reload_en) begin
        case (state)
          IDLE: shift <= 0;
          // TODO: based on OP
          INST: shift <= 8'h9f;
          ADDR1: shift <= i_addr[23:16];
          ADDR2: shift <= i_addr[15:8];
          ADDR3: shift <= i_addr[7:0];
          default: shift <= '0;
        endcase
      end else begin
        shift <= {shift[6:0], 1'b0};
      end
    end
  end

  // MISO data input handling
  reg [7:0] working;
  reg sclk_miso, miso_sync;
  always @(posedge spi_sclk) begin
    sclk_miso <= spi_miso;
  end

  synchronizer sync1 (
      .clk(clk),
      .sig(sclk_miso),
      .q  (miso_sync)
  );
  always @(posedge clk) begin
    working <= {working[6:0], miso_sync};
    o_data_valid <= 1'b0;
    byte_valid <= next_byte_valid;
    if (byte_valid) begin
      o_data_valid <= 1'b1;
      o_data <= working;
    end
  end

  typedef enum {
    IDLE,
    INST,
    ADDR1,
    ADDR2,
    ADDR3,
    WAIT_SYNC,
    DATA
  } state_t;
  state_t state, next_state;
  always_comb begin
    next_reload_en = 0;
    next_state = state;
    next_cs = 1'b1;
    next_byte_valid = 0;
    next_clken = 0;
    next_counter_reset = 0;
    case (state)
      IDLE: begin
        next_reload_en = 1;
        if (i_en) begin
          next_state = INST;
          next_clken = 1;
        end
      end
      INST: begin
        next_cs = 0;
        next_clken = 1;
        if (state_counter == 'd7) begin
          next_state = ADDR1;
          next_reload_en = 1;
        end
      end
      ADDR1: begin
        next_cs = 0;
        next_clken = 1;
        if (state_counter == 'd7) begin
          next_state = ADDR2;
          next_reload_en = 1;
        end
      end
      ADDR2: begin
        next_cs = 0;
        next_clken = 1;
        if (state_counter == 'd7) begin
          next_state = ADDR3;
          next_reload_en = 1;
        end
      end
      ADDR3: begin
        next_cs = 0;
        next_clken = 1;
        if (state_counter == 'd7) begin
          next_state = WAIT_SYNC;
        end
      end
      WAIT_SYNC: begin
        next_cs = 0;
        next_clken = 1;
        if (state_counter == 'd3) begin
          next_state = DATA;
          next_counter_reset = 1;
        end
      end
      DATA: begin
        next_cs = 0;
        next_clken = 1;
        if (state_counter == 'd7) next_byte_valid = 1'b1;
        if (payload_counter == i_size) begin
          next_state = IDLE;
          next_cs = 1;
          next_clken = 0;
        end
      end
    endcase
  end

endmodule
