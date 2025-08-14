`default_nettype	none
module udp_decode(
  input wire clk,
  input wire rst,
  input valid,
  input [7:0] din,

  output reg [15:0] source,
  output reg [15:0] dest,
  output reg length,
  output reg done
  );
reg [15:0] working = '0;
reg [7:0] counter = '0;
reg [15:0] checksum = '0;

  always @(posedge clk) begin
    if (rst || ~valid) begin
      working <= '0;
      counter <= '0;
      err <= 0;
      done <= 0;
    end else if (!err) begin
      working <= {working[7:0], din};
      done <= 0;

      if (!done) counter <= counter + 1;

      case (counter)
      // Source port
      8'd2: source <= working;
      // Dest port
      8'd4: dest <= working;
      // Length of header and data
      8'd10: length <= working;
      // Checksum of header and data (optional in IPV4)
      8'd12: begin
        checksum <= working;
        done <= 1'b1;
      end
      default: begin
        // NO OP wait for valid to de-assert
      end
      endcase
    end
  end
endmodule
