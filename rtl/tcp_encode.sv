`default_nettype none
`include "utils.svh"

module tcp_encode #(
    parameter logic [15:0] MY_TCP_PORT = 'd8080
) (
    input en,
    input clk,
    input rst,
    // used for IP pseudo header in TCP checksum calc
    input [31:0] ip_sa,
    input [31:0] ip_da,
    input [15:0] ip_packet_len,

    input [15:0] dest_port,
    input [31:0] sequence_num,
    input [31:0] ack_num,
    input [ 7:0] flags,
    input [15:0] window,
    input [15:0] initial_checksum,

    output reg done,
    output reg [7:0] dout
);

  reg [15:0] checksum = '0;
  reg [31:0] working = '0;
  reg [15:0] counter = '0;

  always @(posedge clk) begin
    logic [7:0] out;
    if (rst) begin
      counter <= '0;
      done <= '0;
    end else if (en) begin
      done <= '0;
      counter <= (counter < 'd19) ? counter + 1 : counter;
      case (counter)
        'd0: out = MY_TCP_PORT[15:8];
        'd1: out = MY_TCP_PORT[7:0];
        'd2: out = dest_port[15:8];
        'd3: out = dest_port[7:0];
        'd4: out = sequence_num[31:24];
        'd5: out = sequence_num[23:16];
        'd6: out = sequence_num[15:8];
        'd7: out = sequence_num[7:0];
        'd8: out = ack_num[31:24];
        'd9: out = ack_num[23:16];
        'd10: out = ack_num[15:8];
        'd11: out = ack_num[7:0];
        'd12: out = 8'h50;
        'd13: out = flags;
        'd14: out = window[15:8];
        'd15: out = window[7:0];
        'd16: out = checksum[15:8];
        'd17: out = checksum[7:0];
        'd18: out = '0;
        'd19: out = '0;
        default: out = '0;
      endcase
      done <= (counter == 'd19) ? 1'b1 : '0;
      dout <= out;
      if (counter < 'd16) checksum <= ones_comp(checksum, {8'b0, out});
      else
        checksum <= ones_comp(
            ones_comp(
                ones_comp(
                    ones_comp(
                        ones_comp(
                            ones_comp(initial_checksum, ip_da[15:0]), ip_da[31:16]
                        ),
                        ip_sa[15:0]
                    ),
                    ip_sa[31:16]
                ),
                ip_packet_len - 16'd20
            ),
            16'd6
        );
    end else begin
      dout <= MY_TCP_PORT[15:8];
      counter <= 'd1;
      done <= '0;
    end
  end

endmodule
