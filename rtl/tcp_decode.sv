/**
* Shall extract the what we need from the TCP header. Asserts done when
* finished with TCP header and payload starts
*/
`default_nettype none
`include "utils.svh"

module tcp_decode #(
    parameter MSS = 1460 + 4
) (
    input valid,
    input clk,
    input rst,
    input [7:0] din,
    // used for IP pseudo header in TCP checksum calc
    input [31:0] ip_sa,
    input [31:0] ip_da,
    input [3:0] ip_ihl,
    input [15:0] ip_payload_size,

    output reg [15:0] source_port,
    output reg [15:0] dest_port,
    output reg [31:0] sequence_num,
    output reg [31:0] ack_num,
    output reg [7:0] flags,
    output reg [15:0] window,
    // Asserted when a valid payload is on the line. Tie to a buffer for writing
    output reg payload_valid,
    output reg [7:0] payload,
    output reg [15:0] payload_size,
    output reg err,
    output reg done
);

  reg [15:0] working_checksum = '0;
  reg [15:0] checksum = '0;
  reg [31:0] working = '0;
  reg [15:0] counter = '0;
  reg [ 3:0] data_offset;

  typedef enum {
    IDLE,
    BUSY,
    DONE
  } STATE;
  STATE state = IDLE;

  always @(posedge clk) begin
    if (rst) begin
      counter <= '0;
      done <= '0;
      err <= '0;
      working <= '0;
      working_checksum <= '0;
      state <= IDLE;
    end else begin
      if (valid) begin
        working <= {working[23:0], din};
        counter <= counter + 'd1;
      end
      case (state)
        IDLE: begin
          counter <= '0;
          done <= '0;
          err <= '0;
          payload_valid <= '0;
          if (valid) begin
            state <= BUSY;
            counter <= counter + 'd1;
            payload_size <= ip_payload_size - (4'd4 * ip_ihl);
            working_checksum <= ones_comp(
                ones_comp(
                    ones_comp(
                        ones_comp(
                            ones_comp(
                                ones_comp(working_checksum, ip_da[15:0]), ip_da[31:16]
                            ),
                            ip_sa[15:0]
                        ),
                        ip_sa[31:16]
                    ),
                    ip_payload_size - (4'd4 * ip_ihl)
                ),
                16'd6
            );
          end
        end
        BUSY: begin
          if (valid) begin
            done <= '0;
            if (counter != '0 && !counter[0])
              working_checksum <= ones_comp(working_checksum, working[15:0]);
            case (counter)
              'd2:  source_port <= working[15:0];
              'd4:  dest_port <= working[15:0];
              'd8:  sequence_num <= working;
              'd12: ack_num <= working;
              'd13: data_offset <= working[7:4];
              'd14: flags <= working[7:0];
              'd16: window <= working[15:0];
              'd18: checksum <= working[15:0];
              'd20: begin
                //urg <= working[15:0];
              end
            endcase
            // send out payload
            payload_valid <= '0;
            if (counter > data_offset * 4) begin
              payload <= working[7:0];
              payload_valid <= 1'b1;
            end
            // TODO: check overshoot MSS
            if (counter == MSS + 'd20) begin
            end
          end else begin
            done <= 1'b1;
            // checksum field = ~(a+b...)
            // working_checksum = a+b...+ checksum_field
            err <= !(working_checksum == '1);
            payload_valid <= '0;
            state <= DONE;
          end
        end
        DONE: begin
          if (valid == 1'b0) state <= IDLE;
        end
      endcase
    end
  end

endmodule
