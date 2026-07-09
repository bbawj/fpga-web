`default_nettype none

module mac_tx_buff (
    input wire clk,
    input wire rst,
    input wire tcp_outgoing_buffer_start,
    input wire [15:0] i_pkt_payload_size,
    input wire [18:0] i_pkt_payload_addr,
    input wire tcp_payload_rd_valid,
    input wire [31:0] tcp_payload_rd_data,

    output reg tcp_payload_rd_en,
    output reg [15:0] tcp_payload_checksum,
    output reg [18:0] tcp_payload_rd_ad,
    output reg [15:0] tcp_payload_rd_size,

    output reg [3:0] o_payload_buff_state,
    output reg tcp_outgoing_wr_en = 0,
    output reg [10:0] tcp_outgoing_wr_ptr = 0,
    output reg [31:0] tcp_outgoing_wr_data = 0,
    output reg tcp_outgoing_rdy = 0
);
  reg [15:0] payload_counter = '0;
  reg [15:0] payload_size;
  always @(posedge clk) begin
    tcp_outgoing_wr_data <= tcp_payload_rd_data;
    // reading in 32 bit blocks
    if (rst) begin
      payload_size <= 0;
    end else if (tcp_outgoing_buffer_start) begin
      payload_size <= (i_pkt_payload_size >> 2) + ((|i_pkt_payload_size[1:0]) ? 16'd1 : 16'd0);
      tcp_payload_rd_size <= i_pkt_payload_size;
    end
  end
  // Pull payload data into temp buffer to free up SDRAM activity
  typedef enum reg [7:0] {
    BUFF_STATE_IDLE,
    BUFF_STATE_START,
    BUFF_STATE_MOVE_TO_LOCAL,
    BUFF_STATE_DONE
  } payload_buff_state_t;
  payload_buff_state_t payload_buff_state = BUFF_STATE_IDLE;
  always @(posedge clk) begin
    case (payload_buff_state)
      BUFF_STATE_IDLE: o_payload_buff_state <= 'd0;
      BUFF_STATE_START: o_payload_buff_state <= 'd1;
      BUFF_STATE_MOVE_TO_LOCAL: o_payload_buff_state <= 'd2;
      BUFF_STATE_DONE: o_payload_buff_state <= 'd3;
      default: begin
      end
    endcase
  end
  always @(posedge clk) begin
    if (rst) begin
      payload_counter <= '0;
      tcp_payload_rd_en <= '0;
      tcp_outgoing_wr_en <= '0;
      tcp_outgoing_wr_ptr <= '0;
      tcp_outgoing_rdy <= 0;
      payload_buff_state <= BUFF_STATE_IDLE;
    end else
      case (payload_buff_state)
        BUFF_STATE_IDLE: begin
          tcp_payload_rd_en <= '0;
          tcp_outgoing_wr_en <= '0;
          tcp_outgoing_wr_ptr <= '0;
          tcp_outgoing_rdy <= 0;
          payload_counter <= 0;
          tcp_payload_rd_ad <= i_pkt_payload_addr;
          // Assume pkt.payload_size > 0
          if (tcp_outgoing_buffer_start && i_pkt_payload_size > 0) begin
            payload_buff_state <= BUFF_STATE_START;
          end else if (tcp_outgoing_buffer_start && i_pkt_payload_size == 0) begin
            payload_buff_state <= BUFF_STATE_MOVE_TO_LOCAL;
          end
        end
        BUFF_STATE_START: begin
          tcp_payload_rd_en  <= payload_counter != payload_size;
          tcp_outgoing_wr_en <= tcp_payload_rd_valid;
          if (tcp_payload_rd_valid) begin
            tcp_payload_rd_ad <= tcp_payload_rd_ad + 1;
            tcp_outgoing_wr_ptr <= tcp_outgoing_wr_ptr + 1;
            payload_counter <= payload_counter + 1;
          end
          if (payload_counter == payload_size) payload_buff_state <= BUFF_STATE_MOVE_TO_LOCAL;
        end
        BUFF_STATE_MOVE_TO_LOCAL: begin
          tcp_outgoing_wr_en <= 1'b0;
          tcp_outgoing_rdy   <= 1;
          payload_buff_state <= BUFF_STATE_IDLE;
        end
        default: begin
          payload_buff_state <= BUFF_STATE_IDLE;
        end
      endcase
  end

  reg [15:0] checksum_stage1 = '0;
  reg checksum_stage_valid;
  always @(posedge clk) begin
    checksum_stage_valid <= tcp_outgoing_wr_en;
    if (tcp_outgoing_wr_en) begin
      // wr_data is in LE order not network transmit order
      checksum_stage1 <= utils::ones_comp(
          {
            tcp_outgoing_wr_data[7:0], tcp_outgoing_wr_data[15:8]
          },
          {
            tcp_outgoing_wr_data[23:16], tcp_outgoing_wr_data[31:24]
          }
      );
    end else if (tcp_outgoing_buffer_start) checksum_stage1 <= '0;
  end
  always @(posedge clk) begin
    if (checksum_stage_valid) begin
      tcp_payload_checksum <= utils::ones_comp(checksum_stage1[15:0], tcp_payload_checksum);
    end else if (tcp_outgoing_buffer_start) tcp_payload_checksum <= '0;
  end

`ifdef FORMAL
  reg f_past_valid;
  initial f_past_valid = 1'b0;
  always @(posedge clk) begin
    if (rst) f_past_valid <= 1;
    // outgoing rdy is a single pulse
    if (f_past_valid) begin
      assert (tcp_outgoing_rdy == 0 || !$stable(tcp_outgoing_rdy));
      assert (payload_buff_state <= BUFF_STATE_DONE);
      assert (payload_counter == tcp_outgoing_wr_ptr);
      assert (tcp_outgoing_wr_ptr <= i_pkt_payload_size);
    end
  end
`endif

endmodule
