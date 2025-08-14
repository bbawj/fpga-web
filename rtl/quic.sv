module quic (
  input wire clk,
  input wire rst,
  input valid,
  input [7:0] din,
  );

  typedef enum logic {LONG, SHORT} HEADER_FORM;
  typedef enum logic {INITIAL, RTT_0, HANDSHAKE, RETRY} LONG_TYPES;

  // max size of any header field is 160 bytes. Version negotiation can go
  // larger but is unsupported by this implementation.
  reg [159:0] working = '0;
  reg [7:0] counter = '0;
  reg [31:0] dest_cid_len;
  always @(posedge clk) begin
    HEADER_FORM header_form;
    LONG_TYPES pkt_type;
    if (rst || !valid || err) begin
      working <= '0;
      counter <= '0;
      err <= 0;
      done <= 0;
    end else begin
      working <= {working[7:0], din};
      done <= 0;

      if (!done) counter <= counter + 1;

      if (counter == 8'd1) begin
        // Header form (0x8 = long header)
        case (working[7:6])
          2'b11: header_form = LONG;
          2'b01: header_form = SHORT;
          default:
            err <= 1;
        endcase
        case (working[5:4]) 
          2'b00: begin
            pkt_type <= INITIAL;
            if (working[3:2] != 2'b00) err <= 1'b1;
            pkt_num_len <= working[1:0];
          end
          2'b01: pkt_type <= RTT_0;
          2'b10: pkt_type <= HANDSHAKE;
          2'b11: pkt_type <= RETRY;
        endcase
      end

      if (counter > 0 && header_form == LONG) begin
        if (counter == 8'd5) begin
          if (working[31:0] != 32'd1) err <= 1'b1;
        end else if (counter == 8'd6) begin
          dest_cid_len <= working[7:0];
          // in QUICv1 this must not exceed 20 bytes
          if (working[7:0] > 8'd20) err <= 1'b1;
        end else if (counter == dest_cid_len + 32'd6) begin
          dest_cid <= working[dest_cid_len*8:0];
        end else if (counter == dest_cid_len + 32'd6 + 32'd8) begin
          src_cid_len <= working[7:0];
          // in QUICv1 this must not exceed 20 bytes
          if (working[7:0] > 8'd20) err <= 1'b1;
        end else if (counter == dest_cid_len + 32'd6 + 32'd8 + src_cid_len) begin
          src_cid <= working[src_cid_len*8:0];
        end else begin
          case (pkt_type)
            INITIAL: begin
              if (counter == 
            end
          endcase
        end
      end
    end
  end
  
  var_int_decoder _vid(.clk(clk), .rst(rst), .valid(vid_valid), .din(rxd), .len(vid_len), .value(vid_val));

  endmodule
