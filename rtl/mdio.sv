module mdio(
  input wire clk,
  input wire en,
  input wire op,
  input wire [4:0] phyad,
  input wire [4:0] regad,
  input wire [15:0] regdata,

  output wire mdc,
  output mdio,

  output reg valid,
  output reg [15:0] data
  );

clk_gen #(.CLKI_DIV(10)) _clk_gen(
  .clk_in(clk),
  .clk_out(mdc),
  .clk_locked()
  );

  localparam READ = 1'b0;
  localparam WRITE = 1'b1;
  typedef enum {IN, OUT} DIR;
  reg direction = IN;
  reg out = 1;
  assign mdio = direction == OUT ? out : 1'bz;

  reg [7:0] counter = '0;

  reg start_flag = 0;
  always @(posedge clk) begin
    if (en && !start_flag) start_flag <= 1'b1;
    else if (valid) start_flag <= 0;
  end

  reg valid_slow = 1'b1;
  synchronizer _sync (.clk(clk), .sig(valid_slow), .q(valid));
  reg start_flag_slow;
  synchronizer _sync_1 (.clk(mdc), .sig(start_flag), .q(start_flag_slow));

  // The logic here is that enable triggers start_flag which triggers an up
  // counter. Once all bits are written/read valid_slow is triggered. This
  // de-asserts start_flag. This resets the counter and the cycle repeats.
always @(posedge mdc) begin
  if (start_flag_slow) begin
    if (counter <= 8'd64)
      counter <= counter + 1;
  end else counter <= '0;

  if (counter <= 8'd64) valid_slow <= 1'b0;
  else valid_slow <= 1'b1;

  // IDLE
  if (counter == 8'd0) begin
    direction <= IN;
    out <= 1'b1;
  // PREAMBLE
  end
  else if (counter <= 8'd32) begin
    direction <= OUT;
    out <= 1'b1;
  // START
  end
  else if (counter == 8'd33) begin
    out <= 1'b0;
  end
  else if (counter == 8'd34) begin
    out <= 1'b1;
  // OP
  end
  else if (counter == 8'd35) begin
    out <= op == READ ? 1'b1 : 1'b0;
  end
  else if (counter == 8'd36) begin
    out <= op == READ ? 1'b0 : 1'b1;
  // PHYAD
  end
  else if (counter <= 8'd41) begin
    out <= phyad[41-counter];
  // REGAD
  end
  else if (counter <= 8'd46) begin
    out <= regad[46-counter];
  // TA
  end 
  else if (counter == 8'd47) begin
    direction <= op == READ ? IN : OUT;
    out <= 1'b1;
  end 
  else if (counter == 8'd48)  begin
    direction <= op == READ ? IN : OUT;
    out <= 1'b0;
  // DATA
  end 
  else if (counter <= 8'd64) begin
    direction <= op == READ ? IN : OUT;
    if (op == READ) data <= {data[14:0], mdio};
    else out <= regdata[64-counter];
  end else begin
    direction <= IN;
  end
end

`ifdef FORMAL
  initial assume(counter == 8'd0);
  initial assume (direction == IN);
  reg f_past_valid = 0;
  initial assume (f_past_valid == 0);
  reg [31:0] mdc_cycles = 0;

  (*anyconst*) reg [4:0] f_phyad;
  (*anyconst*) reg [4:0] f_regad;
  reg [64:0] f_line_data = '0;
  reg [64:0] f_line_flag = '0;
  initial assume(f_line_flag == '0);
  initial assume(f_line_data == '0);

  wire [63:0] write_expected;

  (*gclk*) wire gbl_clk;
  always @(posedge gbl_clk) begin
    // these signals from the MAC update on rising edge of tx_clk
    f_past_valid <= 1'b1;
    if (!$initstate && !$rose(mdc)) begin
      assume($stable(counter));
    end
    if ($rose(mdc)) begin
      // counter does not change if it reaches 65 (anything above 65 is
      // unreachable)
      if ($past(counter) <= 8'd65) assert(counter <= 8'd65);
      if (counter == 1) assert(direction == IN);
      if (f_past_valid && op == READ && counter > 8'd47) assert(direction == IN);
    end

    assume(phyad == f_phyad);
    assume(regad == f_regad);
    // input signals stable
    assume($stable(op));
    assume($stable(regdata));
    assume($stable(phyad));
    assume($stable(regad));
    if (counter == 0) begin
      f_line_data <= '0;
      f_line_flag <= '0;
    end else if (f_past_valid && $changed(counter)) begin
      f_line_data <= {f_line_data[64:0], out};
      f_line_flag <= {f_line_flag[64:0], 1'b1};
    end else begin
      f_line_data <= f_line_data;
      f_line_flag <= f_line_flag;
    end

    assume (write_expected == {32'hFFFFFFFF, 2'b01, 2'b01, phyad, regad, 2'b10, regdata});
    if (op == WRITE && f_line_flag[64:0] == '1)
      assert(f_line_data[63:0] == write_expected);
  end

  always @(posedge mdc) begin
    if (f_past_valid && !$initstate) begin
      // if (start_flag) assert($past(en) || counter <= 54);
    end
  end

`endif

endmodule
