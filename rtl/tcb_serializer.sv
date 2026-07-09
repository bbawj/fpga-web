`default_nettype none
module tcb_serializer (
    input wire clk,
    input wire rst,
    input wire [18:0] i_to_send_payload_addr,
    input wire [15:0] i_to_send_payload_size,
    input wire upper_pending,
    input wire pkt_pending,
    input wire echo_pending,
    input wire [18:0] echo_payload_addr,
    input wire [15:0] echo_payload_size,

    output reg [1:0] tcb_tx_sel,
    output reg to_send_wr_en,
    output reg o_send_tcp,
    output reg [18:0] mux_to_send_payload_addr,
    output reg [15:0] mux_to_send_payload_size,

    output reg upper_granted,
    output reg pkt_granted,
    output reg echo_granted,
    output reg [7:0] o_grant_state
);
  typedef enum reg [7:0] {
    GRANT_IDLE,
    GRANT_BREAK,
    GRANT_UPPER,
    GRANT_UPPER_WAIT,
    GRANT_PENDING,
    WAIT_PKT,
    SEND_PKT,
    GRANT_ECHO
  } grant_state_t;
  grant_state_t grant_state;
`ifdef DEBUG
  always @(posedge clk) begin
    case (grant_state)
      GRANT_IDLE: o_grant_state <= 0;
      GRANT_BREAK: o_grant_state <= 'd1;
      GRANT_UPPER: o_grant_state <= 'd2;
      GRANT_UPPER_WAIT: o_grant_state <= 'd3;
      GRANT_PENDING: o_grant_state <= 'd4;
      WAIT_PKT: o_grant_state <= 'd5;
      SEND_PKT: o_grant_state <= 'd6;
      GRANT_ECHO: o_grant_state <= 'd7;
      default: begin
      end
    endcase
  end
`endif
  reg [18:0] remaining_payload_addr;
  reg [15:0] remaining_payload_size;
  reg [18:0] to_send_payload_addr;
  reg [15:0] to_send_payload_size;
  always @(posedge clk) begin
    if (upper_pending) begin
      to_send_payload_size <= i_to_send_payload_size;
      to_send_payload_addr <= i_to_send_payload_addr;
    end
  end

  always @(posedge clk) begin
    if (rst) upper_granted <= 0;
    else upper_granted <= grant_state == GRANT_UPPER;
  end

  always @(posedge clk) begin
    if (rst) to_send_wr_en <= 0;
    else
      to_send_wr_en <= grant_state == GRANT_UPPER || grant_state == GRANT_BREAK || grant_state == GRANT_ECHO;
  end

  always @(posedge clk) begin
    if (rst) pkt_granted <= 0;
    else pkt_granted <= grant_state == GRANT_PENDING;
  end

  reg send_tcp, send_tcp_q;
  always @(posedge clk) begin
    if (rst) send_tcp <= 0;
    else send_tcp <= grant_state == SEND_PKT;

    send_tcp_q <= send_tcp;
    o_send_tcp <= send_tcp_q;
  end

  always @(posedge clk) begin
    if (rst) tcb_tx_sel <= 0;
    else
      tcb_tx_sel <= (grant_state == GRANT_UPPER || grant_state == GRANT_BREAK ||
        grant_state == GRANT_PENDING || grant_state == WAIT_PKT ||
        grant_state == SEND_PKT || grant_state == GRANT_ECHO) ? 1 : 0;
  end

  always @(posedge clk) begin
    if (rst) begin
      grant_state <= GRANT_IDLE;
      remaining_payload_size <= 0;
      remaining_payload_addr <= 0;
      mux_to_send_payload_size <= 0;
      mux_to_send_payload_addr <= 0;
    end else
      case (grant_state)
        GRANT_IDLE: begin
          remaining_payload_size   <= 0;
          remaining_payload_addr   <= 0;
          mux_to_send_payload_size <= 0;
          mux_to_send_payload_addr <= 0;

          if (upper_pending) begin
            grant_state <= GRANT_UPPER;
          end else if (pkt_pending) begin
            grant_state <= GRANT_PENDING;
          end else if (echo_pending) begin
            grant_state <= GRANT_ECHO;
          end
        end
        GRANT_UPPER: begin
          // 1440 is chosen as a multiple of 32 that is smaller than MSS of 1460
          if (to_send_payload_size <= 1440) begin
            mux_to_send_payload_size <= to_send_payload_size;
            mux_to_send_payload_addr <= to_send_payload_addr;
            grant_state <= GRANT_UPPER_WAIT;
          end else begin
            mux_to_send_payload_size <= 1440;
            remaining_payload_size <= to_send_payload_size - 1440;
            remaining_payload_addr <= to_send_payload_addr + (1440 / 4);
            mux_to_send_payload_addr <= to_send_payload_addr;
            grant_state <= GRANT_BREAK;
          end
        end
        GRANT_UPPER_WAIT: begin
          // for upper_pending to transition
          if (!upper_pending) grant_state <= GRANT_IDLE;
          mux_to_send_payload_size <= 0;
          mux_to_send_payload_addr <= 0;
        end
        GRANT_BREAK: begin
          remaining_payload_size   <= remaining_payload_size - 1440;
          remaining_payload_addr   <= remaining_payload_addr + (1440 / 4);
          mux_to_send_payload_addr <= remaining_payload_addr;
          if (remaining_payload_size <= 1440) begin
            mux_to_send_payload_size <= remaining_payload_size;
            grant_state <= GRANT_UPPER_WAIT;
          end else begin
            mux_to_send_payload_size <= 1440;
            grant_state <= GRANT_BREAK;
          end
        end
        GRANT_PENDING: begin
          // 1 cyle stall due to latency for pkt to return after granted
          grant_state <= WAIT_PKT;
          mux_to_send_payload_size <= 0;
          mux_to_send_payload_addr <= 0;
        end
        WAIT_PKT: begin
          // 1 cyle stall due to latency for tcb to update with pkt_to_send
          grant_state <= SEND_PKT;
        end
        SEND_PKT: begin
          grant_state <= GRANT_IDLE;
        end
        GRANT_ECHO: begin
          if (!echo_pending) grant_state <= GRANT_IDLE;
          if (echo_payload_size <= 1440) mux_to_send_payload_size <= echo_payload_size;
          else mux_to_send_payload_size <= 1440;
          mux_to_send_payload_addr <= echo_payload_addr;
        end
        default: begin
          grant_state <= GRANT_IDLE;
        end
      endcase
  end

  always @(posedge clk) begin
    if (rst) echo_granted <= 0;
    else echo_granted <= grant_state == GRANT_ECHO;
  end

`ifdef FORMAL
  reg f_past_valid;
  initial f_past_valid = 1'b0;
  always_comb begin
    // not testing the echo path for now
    assume (!echo_pending);
  end
  always @($global_clock) begin
    if (upper_pending) assume ($stable(upper_pending));
    if (upper_pending) assume ($stable(i_to_send_payload_size));
    if ($fell(upper_granted)) assume ($fell(upper_pending));
  end
  always @(posedge clk) begin
    if (rst) f_past_valid <= 1;
    // pkt and upper grants are 1 pulse
    if (f_past_valid) assert (pkt_granted == 0 || !$stable(pkt_granted));
    if (f_past_valid) assert (upper_granted == 0 || !$stable(upper_granted));
    if (f_past_valid && to_send_payload_size <= 1440)
      assert (to_send_wr_en == 0 || !$stable(to_send_wr_en));
    if (f_past_valid) assert (mux_to_send_payload_size <= 1440);
    // to_send_wr_en and pkt_granted should not be both 1
    if (f_past_valid && tcb_tx_sel) assert (!(to_send_wr_en && pkt_granted));
    if (f_past_valid && send_tcp) assert (tcb_tx_sel);
    if (f_past_valid && !$past(rst) && $past(pkt_granted)) assert (send_tcp);
  end
`endif
endmodule
