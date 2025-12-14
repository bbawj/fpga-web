`default_nettype	none
/*
* Strips out the IPV4 header and reports done, otherwise err is raised if the
* header is malformed.
*/
module ip_decode (
  input wire clk,
  input wire rst,
  input valid,
  input [7:0] din,

  output reg [31:0] sa,
  output reg [31:0] da,
  output reg err,
  output reg done
  );
reg [31:0] working = '0;
reg [7:0] counter = '0;
reg [15:0] packet_size = '0;
reg [15:0] checksum = '0;
reg [15:0] working_checksum = '0;
reg [7:0] ihl = '0;

  always @(posedge clk) begin
    if (rst || ~valid) begin
      working <= '0;
      counter <= '0;
      err <= 0;
      done <= 0;
    end else if (!err) begin
      if (counter != '0 && !counter[0]) 
        working_checksum <= ones_comp(working_checksum, working[15:0]);

      working <= {working[23:0], din};
      done <= 0;

      if (!done) counter <= counter + 1;

      case (counter)
      // IP Version = 4
      8'd1: begin
        if (working[7:4] != 4'h4) err <= 1;
        // Internet header length represents number of 4 byte words in header
        ihl <= 8'd4 * working[3:0];
      end
      // Total length
      8'd4: packet_size <= working[15:0];
      // Protocol: 6 = TCP
      // Protocol: 17 = UDP
      8'd10: if (working[7:0] != 8'd6) err <= 1;
      // Header Checksum
      8'd12: checksum <= working[15:0];
      8'd16: sa <= working;
      8'd20: begin
        da <= working;
        done <= 1;
        err <= ~ones_comp(working_checksum, working) != '0;
      end
      default: begin
        // NO OP, wait for valid de-assert
      end
      endcase
    end
  end

function automatic logic [15:0] ones_comp(logic [15:0] checksum, logic [15:0] data);
  reg [16:0] sum = 0;
  reg [15:0] temp = ~data;
  sum = temp + checksum;
  if (sum[16] == 1'b1)
    ones_comp = sum[15:0] + 1;
  else
    ones_comp = sum[15:0];
endfunction

endmodule
