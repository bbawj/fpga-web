module areset (
  input wire clk,
  input wire rst_n,
  output wire rst
  );

  reg [17:0] debounce_count = '0;
  reg rst_n_debounced = 0;

  reg [2:0] sync_fifo;
  initial sync_fifo = 2'h3;

  always @(posedge clk) begin
    {sync_fifo[2:1], sync_fifo[0]} <= {sync_fifo[1:0], rst_n};

    if (sync_fifo[1] != sync_fifo[0]) debounce_count <= 0;
    else if (debounce_count != 18'd250000) begin
      debounce_count <= debounce_count + 1;
    end

    if (debounce_count == 18'd250000) begin
      rst_n_debounced <= sync_fifo[2];
    end
  end

  assign rst = !rst_n_debounced;
endmodule
