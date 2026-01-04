/**
* Shall extract the what we need from the TCP header. Asserts done when
* finished with TCP header and payload starts
*/
`default_nettype	none
`include "utils.svh"

module tcp_decode #(
  parameter MSS = 1460 + 4
  )(
  input valid,
  input clk,
  input rst,
  input [7:0] din,
  // used for IP pseudo header in TCP checksum calc
  input [31:0] ip_sa,
  input [31:0] ip_da,
  input [7:0] ip_ihl,
  input [15:0] ip_payload_size,

  output reg [15:0] source_port,
  output reg [15:0] dest_port,
  output reg [31:0] sequence_num,
  output reg [31:0] ack_num,
  output reg [7:0] flags,
  output reg [15:0] window,
  output reg [15:0] urg,
  output reg [MSS-1:0] payload[7:0],
  output reg err,
  output reg done
);

reg [15:0] working_checksum = '0;
reg [15:0] checksum = '0;
reg [31:0] working = '0;
reg [15:0] counter = '0;
reg [3:0] data_offset;

typedef enum {IDLE, BUSY, DONE} STATE;
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
        if (valid) begin
          state <= BUSY;
          counter <= counter + 'd1;
          working_checksum <= 
            ones_comp(ones_comp(ones_comp(ones_comp(
            ones_comp(ones_comp(working_checksum, ip_da[15:0]), ip_da[31:16]), 
            ip_sa[15:0]), ip_sa[31:16]), ip_payload_size - (15'd4*ip_ihl)),15'd6);
        end
      end
      BUSY: begin
        if (valid) begin
          done <= '0;
          if (counter != '0 && !counter[0]) 
            working_checksum <= ones_comp(working_checksum, working[15:0]);

          if (counter == 'd2) begin
            source_port <= working[15:0];
          end else if (counter == 'd4) begin
            dest_port <= working[15:0];
          end else if (counter == 'd8) begin
            sequence_num <= working;
          end else if (counter == 'd12) begin
            ack_num <= working;
          end else if (counter == 'd13) begin
            data_offset <= working[7:4];
          end else if (counter == 'd14) begin
            flags <= working[7:0];
          end else if (counter == 'd16) begin
            window <= working[15:0];
          end else if (counter == 'd18) begin
            checksum <= working[15:0];
          end else if (counter == 'd20) begin
            urg <= working[15:0];
          end else if (counter > 'd20 + data_offset) begin
            if (counter - data_offset - 1 < MSS)
              payload[counter - data_offset - 1] <= working[7:0];
          end
        end else begin
          done <= 1'b1;
          // checksum field = ~(a+b...)
          // working_checksum = a+b...+ checksum_field
          err <= !(working_checksum == '1);
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
