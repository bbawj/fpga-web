module mii_rcv (
  input wire clk,
  input wire [3:0] data,
  input wire rxctl,
  input wire ip_err,
  output reg ip_valid
);
reg rx_dv;
reg rx_er;

reg [3:0] state;
localparam IDLE = 4'd0;
localparam PREAMBLE = 4'd1;
localparam DA = 4'd2;
localparam SA = 4'd3;
localparam LEN = 4'd4;
localparam DATA = 4'd5;
localparam FCS = 4'd6;

reg [47:0] da;
reg [47:0] sa;
reg [15:0] length;
reg [15:0] counter;

wire ip_valid;
wire ip_err;
wire ip_dout_ready;
reg [3:0] ip_dout;
ip_decode ip_decoder(.valid(ip_valid), .clk(clk), .din(data), 
  .err(ip_err), 
  .dout_ready(ip_dout_ready),
  .dout(ip_dout)
  );

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
          else state <= IDLE;
        end
        DA: begin 
          if (counter == 12) begin 
            state <= SA;
            counter <= 0;
          end else begin
            counter <= counter + 1;
            da = da | (data << (counter * 4));
          end
        end
        SA: begin
          if (counter == 4'd12) begin 
            state <= LEN;
            counter <= 0;
          end else begin
              counter <= counter + 1;
              sa = sa | (data << (counter * 4));
          end
        end
        LEN: begin
          if (counter == 4'd4) begin 
            counter <= 0;
            // clause 3.2.6
            if (length <= 16'd1500) state <= DATA;
            else begin
              case (len)
                // IPV4
                16'h0800: state <= IP;
              endcase
            end
          end else begin
              counter <= counter + 1;
              length = length | (data << (counter * 4));
          end
        end
        DATA: begin
          if (counter == length) state <= FCS;
          else begin

          end
        end
        IP: begin
          ip_valid <= 1;
          if (ip_err == 1) begin 
            ip_valid <= 0;
            state <= ABORT;
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
