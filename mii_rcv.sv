module mii_rcv (
  input wire clk,
  input wire [3:0] data,
  input wire rxctl
);
localparam [47:0] MAC_ADDR = 47'h696969696969;
localparam [31:0] IP_ADDR = 32'h69696969;

reg rx_dv;
reg rx_er;

reg [3:0] state;
localparam IDLE = 4'd0;
localparam PREAMBLE = 4'd1;
localparam DA = 4'd2;
localparam SA = 4'd3;
localparam LEN = 4'd4;
localparam IP = 4'd5;
localparam ABORT = 4'd6;

reg [47:0] da;
reg [47:0] sa;
reg [15:0] length;
reg [15:0] counter;

reg ip_valid;
reg ip_err;
reg ip_dout_ready;
reg [3:0] ip_dout;
ip_decode ip_decoder(.valid(ip_valid), .clk(clk), .din(data), 
  .err(ip_err), 
  .dout_ready(ip_dout_ready),
  .dout(ip_dout)
  );

reg arp_valid;
reg arp_err;
reg arp_done;
reg [47:0] arp_sha,
reg [31:0] arp_spa,
reg [31:0] arp_tpa,
arp_decode arp_d(
  .clk(clk),
  .rst(rst),
  .valid(arp_valid),
  .din(dout),
  .sha(arp_sha),
  .spa(arp_spa),
  .tpa(arp_tpa),
  .err(arp_err),
  .done(arp_done)
  );

reg arp_e_valid;
reg arp_e_ovalid;
reg [3:0] arp_e_dout;
arp_encode arp_e(
  .clk(clk),
  .rst(rst),
  .valid(arp_e_valid),
  .tha(arp_sha),
  .tpa(arp_spa),

  .ovalid(arp_e_ovalid),
  .dout(arp_e_dout),
  );

// Decoding the MAC frame
// Skip idle and extension, strip off preamble and sfd
always @(posedge clk) begin
    rx_dv <= rxctl;
    if (~rx_dv) begin 
      state <= IDLE;
    end else begin
      case (state)
        IDLE: begin 
          if (data == 4'b1010) state <= PREAMBLE;
          else begin
            da <= '0;
            sa <= '0;
            counter <= '0;
          end
        end
        PREAMBLE: begin
          if (data == 4'b1010)
            state <= PREAMBLE;
          // SFD detected
          else if (data == 4'b1011)
            state <= DA;
          else state <= ABORT;
        end
        DA: begin 
          if (counter == 12) begin 
            state <= SA;
            counter <= 0;
          end else begin
            counter <= counter + 1;
            da = { da[43:0] , data };
          end
        end
        SA: begin
          if (counter == 4'd12) begin 
            state <= LEN;
            counter <= 0;
          end else begin
              counter <= counter + 1;
              sa = { sa[43:0] , data };
          end
        end
        LEN: begin
          if (counter == 4'd4) begin 
            counter <= 0;
            // Only supporting IP frames
            if (length <= 16'd1500) state <= IP;
            else begin
              // clause 3.2.6
              case (length)
                // IPV4
                16'h0800: state <= IP;
                // ARP
                16'h0806: state <= ARP;
                default: state <= ABORT;
              endcase
            end
          end else begin
              counter <= counter + 1;
              length <= { length, data };
          end
        end
        IP: begin
          ip_valid <= 1;
          if (ip_err == 1) begin 
            ip_valid <= 0;
            state <= ABORT;
          end
        end
        ARP: begin
          arp_valid <= 1;
          if (arp_err == 1'b1) begin 
            arp_valid <= 0;
            state <= ABORT;
          end else if (arp_done == 1'b1) begin
            arp_valid <= 0;
            // Start our ARP reply if we are the target
            if (arp_tpa == IP_ADDR) begin
              arp_e_valid <= 1;
            end
          end
        end
        ABORT: begin
          // NOP. Wait for RX_DV deassertion to restart
        end
      endcase
    end
  end

always @(negedge clk) begin
    rx_er <= rxctl;
end

endmodule
