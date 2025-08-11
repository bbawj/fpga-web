module blinky(
    input  wire         sysclk,
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
        cntr    <= cntr + 1;
        if (cntr == count_1s) begin
          en <= ~en;
          cntr <= 0;
        end
    end

    assign led_n = en;

endmodule
