`default_nettype none

module delay #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 1
) (
    input  logic             clk,
    input  logic             rst,
    input  logic [WIDTH-1:0] data_in,
    output logic [WIDTH-1:0] data_out
);

    generate
        if (DEPTH == 0) begin : no_delay
            assign data_out = data_in;
        end else if (DEPTH == 1) begin : single_delay
            always @(posedge clk) begin
                if (rst)
                    data_out <= '0;
                else
                    data_out <= data_in;
            end
        end else begin : multi_delay
            logic [WIDTH-1:0] delay_pipe [DEPTH-1:0];
            
            always @(posedge clk) begin
                if (rst) begin
                    for (int i = 0; i < DEPTH; i++) begin
                        delay_pipe[i] <= '0;
                    end
                end else begin
                    delay_pipe[0] <= data_in;
                    for (int i = 1; i < DEPTH; i++) begin
                        delay_pipe[i] <= delay_pipe[i-1];
                    end
                end
            end
            
            assign data_out = delay_pipe[DEPTH-1];
        end
    endgenerate

endmodule
