module fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 64,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input wire clk,
    input wire rst,
    
    // Write interface
    input wire wr_en,
    input wire [DATA_WIDTH-1:0] din,
    output wire full,
    
    // Read interface  
    input wire rd_en,
    output reg [DATA_WIDTH-1:0] dout,
    output wire empty,
    
    // Status
    output wire [ADDR_WIDTH:0] count
);

reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
// additional bit here allows to differentiate between full and empty
reg [ADDR_WIDTH:0] wr_ptr, rd_ptr;

// Pointer management
always @(posedge clk) begin
    if (rst) begin
        wr_ptr <= 0;
        rd_ptr <= 0;
    end else begin
        if (wr_en && !full)
            wr_ptr <= wr_ptr + 1;
        if (rd_en && !empty)
            rd_ptr <= rd_ptr + 1;
    end
end

// Memory write
always @(posedge clk) begin
    if (wr_en && !full)
        mem[wr_ptr[ADDR_WIDTH-1:0]] <= din;
end

// Memory read
always @(posedge clk) begin
    if (rd_en && !empty)
        dout <= mem[rd_ptr[ADDR_WIDTH-1:0]];
end

// Status flags
assign full = (wr_ptr - rd_ptr) == DEPTH;
assign empty = (wr_ptr == rd_ptr);
assign count = wr_ptr - rd_ptr;

endmodule
