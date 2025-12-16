/**
* Shall extract the what we need from the TCP header. Asserts done when
* finished with TCP header and payload starts
*/
`default_nettype	none
`include "utils.svh"

module tcp_decode(
  input valid,
  input clk,
  input rst,
  input [7:0] din,

  output reg [15:0] source_port,
  output reg [15:0] dest_port,
  output reg [31:0] sequence_num,
  output reg [31:0] ack_num,
  output reg err,
  output reg done
);

reg [15:0] working_checksum;
reg [15:0] checksum;
reg [31:0] working;
reg [15:0] counter;
reg [3:0] data_offset;
reg [7:0] flags;
reg [31:0] window;
reg [15:0] urg;

always @(posedge clk) begin
  if (rst || !valid) begin
    counter <= '0;
    done <= '0;
    err <= '0;
  end else if (valid) begin
    if (counter != '0 && !counter[0]) 
      working_checksum <= ones_comp(working_checksum, working[15:0]);
    working <= {working[23:0], din};
    counter <= counter + 1;

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
    end else if (counter > 'd20) begin
      if (data_offset == 'd5 || counter == data_offset + 'd21)
        done <= 1'b1;
    end
  end
end

endmodule
