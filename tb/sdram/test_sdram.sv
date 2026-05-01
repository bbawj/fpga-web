module test_sdram (
    input clk,
    input rst,
    input wr_req,
    input [18:0] wr_ad,
    input reg [31:0] wr_data,
    input rd_req,
    input [18:0] rd_ad,
    output wr_granted,
    output rd_granted,
    output rd_valid,
    output reg [31:0] rd_data,
    // SDRAM interface
    output wire [1:0] sdram_ba,
    output wire sdram_we_n,
    output wire sdram_cas_n,
    output wire sdram_ras_n,
    output wire sdram_clk,
    output wire [31:0] sdram_dq,
    output wire [10:0] sdram_addr
);
  sdram_ctrl m (
      .clk(clk),
      .rst(rst),

      .wr_req(wr_req),
      .wr_ad(wr_ad),
      .wr_data(wr_data),
      .wr_granted(wr_granted),

      .rd_req(rd_req),
      .rd_ad(rd_ad),
      .rd_valid(rd_valid),
      .rd_data(rd_data),
      .rd_granted(rd_granted),

      .sdram_ba(sdram_ba),
      .sdram_we_n(sdram_we_n),
      .sdram_cas_n(sdram_cas_n),
      .sdram_ras_n(sdram_ras_n),
      .sdram_clk(sdram_clk),
      .sdram_dq(sdram_dq),
      .sdram_addr(sdram_addr)
  );
endmodule
