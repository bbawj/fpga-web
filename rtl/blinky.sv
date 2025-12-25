module blinky(
    input  wire         sysclk,
    input wire rst,
    output wire         led_n,
);

    reg [31:0] cntr = 0;
    reg en = 0;

    `ifdef SPEED_100M
      localparam count_1s = 32'h17d7840;
    `else
      localparam count_1s = 32'h7735940;
    `endif

    always @(posedge sysclk)
    begin
      if (rst) cntr <= 0;
      else begin
        cntr    <= cntr + 1;
        if (cntr == count_1s) begin
          en <= ~en;
          cntr <= 0;
        end
      end
    end

    assign led_n = en;

endmodule
