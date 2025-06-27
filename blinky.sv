module blinky(
    input  wire         clk_25mhz,
    input  wire         button,
    output wire         led,
);

    reg [25:0] cntr = 0;

    always @(posedge clk_25mhz)
    begin
        cntr    <= cntr + 1;
    end

    assign led = cntr[23] ^ button;

endmodule
