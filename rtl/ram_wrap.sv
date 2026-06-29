module ram_wrap #(
    parameter USE_BLOCKRAM = 1,
    parameter RD_WIDTH = 18,  // 1, 2, 4, 9, 18, 36
    parameter WR_WIDTH = 18,  // 1, 2, 4, 9, 18, 36
    parameter REGMODE = "NOREG",
    parameter ADDR_WIDTH = 10  // must match depth: 14,13,12,11,10,9 respectively
) (
    input  wire                  wr_clk,
    input  wire                  wr_en,
    input  wire [ADDR_WIDTH-1:0] wr_addr,
    input  wire [  WR_WIDTH-1:0] din,
    input  wire                  rd_clk,
    input  wire                  rd_en,
    input  wire [ADDR_WIDTH-1:0] rd_addr,
    output wire [  RD_WIDTH-1:0] dout,
    input  wire                  rst
);
  // localparam int EXPECTED_ADDR_WIDTH =
  //   (EBR_WIDTH_A < EBR_WIDTH_B ? EBR_WIDTH_A : EBR_WIDTH_B) == 1  ? 14 :
  //   (EBR_WIDTH_A < EBR_WIDTH_B ? EBR_WIDTH_A : EBR_WIDTH_B) == 2  ? 13 :
  //   (EBR_WIDTH_A < EBR_WIDTH_B ? EBR_WIDTH_A : EBR_WIDTH_B) <= 4  ? 12 :
  //   (EBR_WIDTH_A < EBR_WIDTH_B ? EBR_WIDTH_A : EBR_WIDTH_B) <= 9  ? 11 :
  //   (EBR_WIDTH_A < EBR_WIDTH_B ? EBR_WIDTH_A : EBR_WIDTH_B) <= 18 ? 10 :
  //   (EBR_WIDTH_A < EBR_WIDTH_B ? EBR_WIDTH_A : EBR_WIDTH_B) <= 36 ? 9  :
  //   -1;
  //
  // if (ADDR_WIDTH != EXPECTED_ADDR_WIDTH)
  //   $error(
  //       "ADDR_WIDTH=%0d does not match required %0d for wider port width=%0d",
  //       ADDR_WIDTH,
  //       EXPECTED_ADDR_WIDTH,
  //       (EBR_WIDTH_A > EBR_WIDTH_B ? EBR_WIDTH_A : EBR_WIDTH_B)
  //   );
  // ---------------------------------------------------------------------------
  // Per-port EBR width (rounded up to supported primitive width)
  // ---------------------------------------------------------------------------
  localparam int EBR_WIDTH_A =
    (WR_WIDTH == 1 ) ? 1  :
    (WR_WIDTH == 2 ) ? 2  :
    (WR_WIDTH <= 4 ) ? 4  :
    (WR_WIDTH <= 9 ) ? 9  :
    (WR_WIDTH <= 18) ? 18 :
    (WR_WIDTH <= 36) ? 36 :
    -1;

  localparam int EBR_WIDTH_B =
    (RD_WIDTH == 1 ) ? 1  :
    (RD_WIDTH == 2 ) ? 2  :
    (RD_WIDTH <= 4 ) ? 4  :
    (RD_WIDTH <= 9 ) ? 9  :
    (RD_WIDTH <= 18) ? 18 :
    (RD_WIDTH <= 36) ? 36 :
    -1;

  wire [35:0] dia = {{(36 - WR_WIDTH) {1'b0}}, din};

  wire [35:0] dob;
  assign dout = dob[RD_WIDTH-1:0];
  // Address bit offset into ADA/ADB: low bits are implicit byte-lane selects
  // within the wider word, so the user address starts at bit offset = log2(width/1)
  // which equals: 0,1,2,3,4,5 for widths 1,2,4,9,18,36
  localparam int ADA_OFFSET =
  (EBR_WIDTH_A == 1 ) ? 0 :
  (EBR_WIDTH_A == 2 ) ? 1 :
  (EBR_WIDTH_A == 4 ) ? 2 :
  (EBR_WIDTH_A == 9 ) ? 3 :
  (EBR_WIDTH_A == 18) ? 4 :
  (EBR_WIDTH_A == 36) ? 5 : 0;

  localparam int ADB_OFFSET =
  (EBR_WIDTH_B == 1 ) ? 0 :
  (EBR_WIDTH_B == 2 ) ? 1 :
  (EBR_WIDTH_B == 4 ) ? 2 :
  (EBR_WIDTH_B == 9 ) ? 3 :
  (EBR_WIDTH_B == 18) ? 4 :
  (EBR_WIDTH_B == 36) ? 5 : 0;

  if (EBR_WIDTH_A == -1 || EBR_WIDTH_B == -1) $error("unsupported width");

  wire [13:0] ada_w = {{(14 - ADDR_WIDTH) {1'b0}}, wr_addr};
  wire [13:0] adb_r = {{(14 - ADDR_WIDTH) {1'b0}}, rd_addr};
  wire [13:0] ada_w_shifted = ada_w << ADA_OFFSET;
  // {
  //   {(14 - ADDR_WIDTH - ADA_OFFSET) {1'b0}}, wr_addr, {(ADA_OFFSET) {1'b0}}
  // };
  wire [13:0] adb_r_shifted = adb_r << ADB_OFFSET;
  // {
  //   {(14 - ADDR_WIDTH - ADB_OFFSET) {1'b0}}, rd_addr, {(ADB_OFFSET) {1'b0}}
  // };

  // -----------------------------------------------------------------------
  // Primitive instantiation
  // -----------------------------------------------------------------------
`ifndef SYNTHESIS
  ram_dp #(
      .REGMODE (REGMODE),
      .WR_WIDTH(WR_WIDTH),
      .RD_WIDTH(RD_WIDTH)
  ) mem (
      .clk_a(wr_clk),
      .we_a(wr_en),
      .addr_a(wr_addr),
      .dia(dia[WR_WIDTH-1:0]),
      .doa(),
      .clk_b(rd_clk),
      .we_b(1'b0),
      .addr_b(rd_addr),
      .dib('0),
      .dob(dob[RD_WIDTH-1:0])
  );
`else
  generate

    if (USE_BLOCKRAM == 0) begin
      ram_dp #(
          .REGMODE (REGMODE),
          .WR_WIDTH(WR_WIDTH),
          .RD_WIDTH(RD_WIDTH)
      ) mem (
          .clk_a(wr_clk),
          .we_a(wr_en),
          .addr_a(wr_addr),
          .dia(dia[WR_WIDTH-1:0]),
          .doa(),
          .clk_b(rd_clk),
          .we_b(1'b0),
          .addr_b(rd_addr),
          .dib('0),
          .dob(dob[RD_WIDTH-1:0])
      );
      /* verilator lint_off PINMISSING */
      /* verilator lint_off IMPLICIT */
    end else if (EBR_WIDTH_A == 36 && EBR_WIDTH_B == 36) begin
      PDPW16KD #(
          .REGMODE(REGMODE),
          .DATA_WIDTH_R(EBR_WIDTH_B),
          .DATA_WIDTH_W(EBR_WIDTH_A)
      ) pdp3636 (
          .DI0  (dia[0]),
          .DI1  (dia[1]),
          .DI2  (dia[2]),
          .DI3  (dia[3]),
          .DI4  (dia[4]),
          .DI5  (dia[5]),
          .DI6  (dia[6]),
          .DI7  (dia[7]),
          .DI8  ('0),
          .DI9  (dia[8]),
          .DI10 (dia[9]),
          .DI11 (dia[10]),
          .DI12 (dia[11]),
          .DI13 (dia[12]),
          .DI14 (dia[13]),
          .DI15 (dia[14]),
          .DI16 (dia[15]),
          .DI17 ('0),
          .DI18 (dia[16]),
          .DI19 (dia[17]),
          .DI20 (dia[18]),
          .DI21 (dia[19]),
          .DI22 (dia[20]),
          .DI23 (dia[21]),
          .DI24 (dia[22]),
          .DI25 (dia[23]),
          .DI26 ('0),
          .DI27 (dia[24]),
          .DI28 (dia[25]),
          .DI29 (dia[26]),
          .DI30 (dia[27]),
          .DI31 (dia[28]),
          .DI32 (dia[29]),
          .DI33 (dia[30]),
          .DI34 (dia[31]),
          .DI35 ('0),
          .ADW0 (ada_w[0]),
          .ADW1 (ada_w[1]),
          .ADW2 (ada_w[2]),
          .ADW3 (ada_w[3]),
          .ADW4 (ada_w[4]),
          .ADW5 (ada_w[5]),
          .ADW6 (ada_w[6]),
          .ADW7 (ada_w[7]),
          .ADW8 (ada_w[8]),
          .ADR0 (adb_r_shifted[0]),
          .ADR1 (adb_r_shifted[1]),
          .ADR2 (adb_r_shifted[2]),
          .ADR3 (adb_r_shifted[3]),
          .ADR4 (adb_r_shifted[4]),
          .ADR5 (adb_r_shifted[5]),
          .ADR6 (adb_r_shifted[6]),
          .ADR7 (adb_r_shifted[7]),
          .ADR8 (adb_r_shifted[8]),
          .ADR9 (adb_r_shifted[9]),
          .ADR10(adb_r_shifted[10]),
          .ADR11(adb_r_shifted[11]),
          .ADR12(adb_r_shifted[12]),
          .ADR13(adb_r_shifted[13]),
          // DO0 is from DI18
          .DO0  (dob[16]),
          .DO1  (dob[17]),
          .DO2  (dob[18]),
          .DO3  (dob[19]),
          .DO4  (dob[20]),
          .DO5  (dob[21]),
          .DO6  (dob[22]),
          .DO7  (dob[23]),
          .DO8  (),
          .DO9  (dob[24]),
          .DO10 (dob[25]),
          .DO11 (dob[26]),
          .DO12 (dob[27]),
          .DO13 (dob[28]),
          .DO14 (dob[29]),
          .DO15 (dob[30]),
          .DO16 (dob[31]),
          .DO17 (),
          .DO18 (dob[0]),
          .DO19 (dob[1]),
          .DO20 (dob[2]),
          .DO21 (dob[3]),
          .DO22 (dob[4]),
          .DO23 (dob[5]),
          .DO24 (dob[6]),
          .DO25 (dob[7]),
          .DO26 (),
          .DO27 (dob[8]),
          .DO28 (dob[9]),
          .DO29 (dob[10]),
          .DO30 (dob[11]),
          .DO31 (dob[12]),
          .DO32 (dob[13]),
          .DO33 (dob[14]),
          .DO34 (dob[15]),
          .DO35 (),

          .CEW (wr_en),
          .CLKW(wr_clk),

          .CER (rd_en),
          .OCER(1'b1),
          .CLKR(rd_clk),
          .RST (rst),
          // Unused: bank addressing
          .BE3 (1'b1),
          .BE2 (1'b1),
          .BE1 (1'b1),
          .BE0 (1'b1),
          // Unused: for > 18kb of memory
          .CSW2(1'b0),
          .CSW1(1'b0),
          .CSW0(1'b0),
          .CSR2(1'b0),
          .CSR1(1'b0),
          .CSR0(1'b0)
      );
    end else if (EBR_WIDTH_A == 36) begin
      PDPW16KD #(
          .REGMODE(REGMODE),
          .DATA_WIDTH_R(EBR_WIDTH_B),
          .DATA_WIDTH_W(EBR_WIDTH_A)
      ) ebr_NOREG_NOREG (
          .DI0  (dia[0]),
          .DI1  (dia[1]),
          .DI2  (dia[2]),
          .DI3  (dia[3]),
          .DI4  (dia[4]),
          .DI5  (dia[5]),
          .DI6  (dia[6]),
          .DI7  (dia[7]),
          .DI8  ('0),
          .DI9  (dia[8]),
          .DI10 (dia[9]),
          .DI11 (dia[10]),
          .DI12 (dia[11]),
          .DI13 (dia[12]),
          .DI14 (dia[13]),
          .DI15 (dia[14]),
          .DI16 (dia[15]),
          .DI17 ('0),
          .DI18 (dia[16]),
          .DI19 (dia[17]),
          .DI20 (dia[18]),
          .DI21 (dia[19]),
          .DI22 (dia[20]),
          .DI23 (dia[21]),
          .DI24 (dia[22]),
          .DI25 (dia[23]),
          .DI26 ('0),
          .DI27 (dia[24]),
          .DI28 (dia[25]),
          .DI29 (dia[26]),
          .DI30 (dia[27]),
          .DI31 (dia[28]),
          .DI32 (dia[29]),
          .DI33 (dia[30]),
          .DI34 (dia[31]),
          .DI35 ('0),
          .ADW0 (ada_w[0]),
          .ADW1 (ada_w[1]),
          .ADW2 (ada_w[2]),
          .ADW3 (ada_w[3]),
          .ADW4 (ada_w[4]),
          .ADW5 (ada_w[5]),
          .ADW6 (ada_w[6]),
          .ADW7 (ada_w[7]),
          .ADW8 (ada_w[8]),
          .ADR0 (adb_r_shifted[0]),
          .ADR1 (adb_r_shifted[1]),
          .ADR2 (adb_r_shifted[2]),
          .ADR3 (adb_r_shifted[3]),
          .ADR4 (adb_r_shifted[4]),
          .ADR5 (adb_r_shifted[5]),
          .ADR6 (adb_r_shifted[6]),
          .ADR7 (adb_r_shifted[7]),
          .ADR8 (adb_r_shifted[8]),
          .ADR9 (adb_r_shifted[9]),
          .ADR10(adb_r_shifted[10]),
          .ADR11(adb_r_shifted[11]),
          .ADR12(adb_r_shifted[12]),
          .ADR13(adb_r_shifted[13]),

          .DO0 (dob[0]),
          .DO1 (dob[1]),
          .DO2 (dob[2]),
          .DO3 (dob[3]),
          .DO4 (dob[4]),
          .DO5 (dob[5]),
          .DO6 (dob[6]),
          .DO7 (dob[7]),
          .DO8 (dob[8]),
          .DO9 (dob[9]),
          .DO10(dob[10]),
          .DO11(dob[11]),
          .DO12(dob[12]),
          .DO13(dob[13]),
          .DO14(dob[14]),
          .DO15(dob[15]),
          .DO16(dob[16]),
          .DO17(dob[17]),
          .DO18(dob[18]),
          .DO19(dob[19]),
          .DO20(dob[20]),
          .DO21(dob[21]),
          .DO22(dob[22]),
          .DO23(dob[23]),
          .DO24(dob[24]),
          .DO25(dob[25]),
          .DO26(dob[26]),
          .DO27(dob[27]),
          .DO28(dob[28]),
          .DO29(dob[29]),
          .DO30(dob[30]),
          .DO31(dob[31]),
          .DO32(dob[32]),
          .DO33(dob[33]),
          .DO34(dob[34]),
          .DO35(dob[35]),

          .CEW (wr_en),
          .CLKW(wr_clk),

          .CER (rd_en),
          .OCER(1'b1),
          .CLKR(rd_clk),
          .RST (rst),
          // Unused: bank addressing
          .BE3 (1'b1),
          .BE2 (1'b1),
          .BE1 (1'b1),
          .BE0 (1'b1),
          // Unused: for > 18kb of memory
          .CSW2(1'b0),
          .CSW1(1'b0),
          .CSW0(1'b0),
          .CSR2(1'b0),
          .CSR1(1'b0),
          .CSR0(1'b0)
      );
    end else if (EBR_WIDTH_A < 36 && EBR_WIDTH_B < 36) begin
      DP16KD #(
          .DATA_WIDTH_A(EBR_WIDTH_A),
          .DATA_WIDTH_B(EBR_WIDTH_B),
          .REGMODE_A   (REGMODE),
          .REGMODE_B   (REGMODE),
          .RESETMODE   ("SYNC"),
          .GSR         ("ENABLED")
      ) EBR_INST (
          .DIA0 (dia[0]),
          .DIA1 (dia[1]),
          .DIA2 (dia[2]),
          .DIA3 (dia[3]),
          .DIA4 (dia[4]),
          .DIA5 (dia[5]),
          .DIA6 (dia[6]),
          .DIA7 (dia[7]),
          .DIA8 (dia[8]),
          .DIA9 (dia[9]),
          .DIA10(dia[10]),
          .DIA11(dia[11]),
          .DIA12(dia[12]),
          .DIA13(dia[13]),
          .DIA14(dia[14]),
          .DIA15(dia[15]),
          .DIA16(dia[16]),
          .DIA17(dia[17]),
          .ADA0 (ada_w_shifted[0]),
          .ADA1 (ada_w_shifted[1]),
          .ADA2 (ada_w_shifted[2]),
          .ADA3 (ada_w_shifted[3]),
          .ADA4 (ada_w_shifted[4]),
          .ADA5 (ada_w_shifted[5]),
          .ADA6 (ada_w_shifted[6]),
          .ADA7 (ada_w_shifted[7]),
          .ADA8 (ada_w_shifted[8]),
          .ADA9 (ada_w_shifted[9]),
          .ADA10(ada_w_shifted[10]),
          .ADA11(ada_w_shifted[11]),
          .ADA12(ada_w_shifted[12]),
          .ADA13(ada_w_shifted[13]),
          .ADB0 (adb_r_shifted[0]),
          .ADB1 (adb_r_shifted[1]),
          .ADB2 (adb_r_shifted[2]),
          .ADB3 (adb_r_shifted[3]),
          .ADB4 (adb_r_shifted[4]),
          .ADB5 (adb_r_shifted[5]),
          .ADB6 (adb_r_shifted[6]),
          .ADB7 (adb_r_shifted[7]),
          .ADB8 (adb_r_shifted[8]),
          .ADB9 (adb_r_shifted[9]),
          .ADB10(adb_r_shifted[10]),
          .ADB11(adb_r_shifted[11]),
          .ADB12(adb_r_shifted[12]),
          .ADB13(adb_r_shifted[13]),
          .CEA  (1'b1),
          .CLKA (wr_clk),
          .WEA  (wr_en),
          .CSA0 (1'b0),
          .CSA1 (1'b0),
          .CSA2 (1'b0),
          .RSTA (rst),
          .OCEA (1'b0),

          .CEB (rd_en),
          .CLKB(rd_clk),
          .WEB (1'b0),
          .CSB0(1'b0),
          .CSB1(1'b0),
          .CSB2(1'b0),
          .RSTB(rst),
          .OCEB(1'b1),

          .DIB0 ('0),
          .DIB1 ('0),
          .DIB2 ('0),
          .DIB3 ('0),
          .DIB4 ('0),
          .DIB5 ('0),
          .DIB6 ('0),
          .DIB7 ('0),
          .DIB8 ('0),
          .DIB9 ('0),
          .DIB10('0),
          .DIB11('0),
          .DIB12('0),
          .DIB13('0),
          .DIB14('0),
          .DIB15('0),
          .DIB16('0),
          .DIB17('0),

          .DOB0 (dob[0]),
          .DOB1 (dob[1]),
          .DOB2 (dob[2]),
          .DOB3 (dob[3]),
          .DOB4 (dob[4]),
          .DOB5 (dob[5]),
          .DOB6 (dob[6]),
          .DOB7 (dob[7]),
          .DOB8 (dob[8]),
          .DOB9 (dob[9]),
          .DOB10(dob[10]),
          .DOB11(dob[11]),
          .DOB12(dob[12]),
          .DOB13(dob[13]),
          .DOB14(dob[14]),
          .DOB15(dob[15]),
          .DOB16(dob[16]),
          .DOB17(dob[17])
      );
    end else if (EBR_WIDTH_A == 9 && EBR_WIDTH_B == 36) begin
      `ifdef LATTICE
      ram_w8r32 w8r32 (
          .WrAddress(ada_w[10:0]),
          .RdAddress(adb_r[8:0]),
          .Data(dia[8:0]),
          .WE(wr_en),
          .RdClock(rd_clk),
          .RdClockEn(rd_en),
          .Reset(rst),
          .WrClock(wr_clk),
          .WrClockEn(wr_en),
          .Q(dob)
      );
      `else
        reg [31:0] dia_shifted;
        always_comb begin
          case (ada_w[1:0])
            2'b00: dia_shifted = {24'b0, dia[7:0]};
            2'b01: dia_shifted = {16'b0, dia[7:0], 8'b0};
            2'b10: dia_shifted = {8'b0, dia[7:0], 16'b0};
            2'b11: dia_shifted = {dia[7:0], 24'b0};
          endcase
        end
      PDPW16KD #(
          .REGMODE(REGMODE),
          .DATA_WIDTH_R(EBR_WIDTH_B),
          .DATA_WIDTH_W(EBR_WIDTH_B)
      ) ebr_NOREG_NOREG (
          .DI0  (dia_shifted[0]),
          .DI1  (dia_shifted[1]),
          .DI2  (dia_shifted[2]),
          .DI3  (dia_shifted[3]),
          .DI4  (dia_shifted[4]),
          .DI5  (dia_shifted[5]),
          .DI6  (dia_shifted[6]),
          .DI7  (dia_shifted[7]),
          .DI8  ('0),
          .DI9  (dia_shifted[8]),
          .DI10 (dia_shifted[9]),
          .DI11 (dia_shifted[10]),
          .DI12 (dia_shifted[11]),
          .DI13 (dia_shifted[12]),
          .DI14 (dia_shifted[13]),
          .DI15 (dia_shifted[14]),
          .DI16 (dia_shifted[15]),
          .DI17 ('0),
          .DI18 (dia_shifted[16]),
          .DI19 (dia_shifted[17]),
          .DI20 (dia_shifted[18]),
          .DI21 (dia_shifted[19]),
          .DI22 (dia_shifted[20]),
          .DI23 (dia_shifted[21]),
          .DI24 (dia_shifted[22]),
          .DI25 (dia_shifted[23]),
          .DI26 ('0),
          .DI27 (dia_shifted[24]),
          .DI28 (dia_shifted[25]),
          .DI29 (dia_shifted[26]),
          .DI30 (dia_shifted[27]),
          .DI31 (dia_shifted[28]),
          .DI32 (dia_shifted[29]),
          .DI33 (dia_shifted[30]),
          .DI34 (dia_shifted[31]),
          .DI35 ('0),
          .ADW0 (ada_w[2]),
          .ADW1 (ada_w[3]),
          .ADW2 (ada_w[4]),
          .ADW3 (ada_w[5]),
          .ADW4 (ada_w[6]),
          .ADW5 (ada_w[7]),
          .ADW6 (ada_w[8]),
          .ADW7 ('0),
          .ADW8 ('0),
          .ADR0 (adb_r_shifted[0]),
          .ADR1 (adb_r_shifted[1]),
          .ADR2 (adb_r_shifted[2]),
          .ADR3 (adb_r_shifted[3]),
          .ADR4 (adb_r_shifted[4]),
          .ADR5 (adb_r_shifted[5]),
          .ADR6 (adb_r_shifted[6]),
          .ADR7 (adb_r_shifted[7]),
          .ADR8 (adb_r_shifted[8]),
          .ADR9 (adb_r_shifted[9]),
          .ADR10(adb_r_shifted[10]),
          .ADR11(adb_r_shifted[11]),
          .ADR12(adb_r_shifted[12]),
          .ADR13(adb_r_shifted[13]),

          .DO0  (dob[16]),
          .DO1  (dob[17]),
          .DO2  (dob[18]),
          .DO3  (dob[19]),
          .DO4  (dob[20]),
          .DO5  (dob[21]),
          .DO6  (dob[22]),
          .DO7  (dob[23]),
          .DO8  (),
          .DO9  (dob[24]),
          .DO10 (dob[25]),
          .DO11 (dob[26]),
          .DO12 (dob[27]),
          .DO13 (dob[28]),
          .DO14 (dob[29]),
          .DO15 (dob[30]),
          .DO16 (dob[31]),
          .DO17 (),
          .DO18 (dob[0]),
          .DO19 (dob[1]),
          .DO20 (dob[2]),
          .DO21 (dob[3]),
          .DO22 (dob[4]),
          .DO23 (dob[5]),
          .DO24 (dob[6]),
          .DO25 (dob[7]),
          .DO26 (),
          .DO27 (dob[8]),
          .DO28 (dob[9]),
          .DO29 (dob[10]),
          .DO30 (dob[11]),
          .DO31 (dob[12]),
          .DO32 (dob[13]),
          .DO33 (dob[14]),
          .DO34 (dob[15]),
          .DO35 (),

          .CEW (wr_en),
          .CLKW(wr_clk),

          .CER (rd_en),
          .OCER(1'b1),
          .CLKR(rd_clk),
          .RST (rst),
          // Unused: bank addressing
          .BE3 (ada_w[1] & ada_w[0]),
          .BE2 (ada_w[1] & !ada_w[0]),
          .BE1 (ada_w[0] & !ada_w[1]),
          .BE0 (!ada_w[0] & !ada_w[1]),
          // Unused: for > 18kb of memory
          .CSW2(1'b0),
          .CSW1(1'b0),
          .CSW0(1'b0),
          .CSR2(1'b0),
          .CSR1(1'b0),
          .CSR0(1'b0)
      );
      `endif
    end else begin
      // $error("36bit read port only not supported");
      PDPW16KD #(
          .REGMODE(REGMODE),
          .DATA_WIDTH_R(EBR_WIDTH_B),
          .DATA_WIDTH_W(EBR_WIDTH_A)
      ) ebr_NOREG_NOREG (
          .DI0  (dia[0]),
          .DI1  (dia[1]),
          .DI2  (dia[2]),
          .DI3  (dia[3]),
          .DI4  (dia[4]),
          .DI5  (dia[5]),
          .DI6  (dia[6]),
          .DI7  (dia[7]),
          .DI8  (dia[8]),
          .DI9  (dia[9]),
          .DI10 (dia[10]),
          .DI11 (dia[11]),
          .DI12 (dia[12]),
          .DI13 (dia[13]),
          .DI14 (dia[14]),
          .DI15 (dia[15]),
          .DI16 (dia[16]),
          .DI17 (dia[17]),
          .DI18 (dia[18]),
          .DI19 (dia[19]),
          .DI20 (dia[20]),
          .DI21 (dia[21]),
          .DI22 (dia[22]),
          .DI23 (dia[23]),
          .DI24 (dia[24]),
          .DI25 (dia[25]),
          .DI26 (dia[26]),
          .DI27 (dia[27]),
          .DI28 (dia[28]),
          .DI29 (dia[29]),
          .DI30 (dia[30]),
          .DI31 (dia[31]),
          .DI32 (dia[32]),
          .DI33 (dia[33]),
          .DI34 (dia[34]),
          .DI35 (dia[35]),
          .ADW0 (ada_w[0]),
          .ADW1 (ada_w[1]),
          .ADW2 (ada_w[2]),
          .ADW3 (ada_w[3]),
          .ADW4 (ada_w[4]),
          .ADW5 (ada_w[5]),
          .ADW6 (ada_w[6]),
          .ADW7 (ada_w[7]),
          .ADW8 (ada_w[8]),
          .ADR0 (adb_r_shifted[0]),
          .ADR1 (adb_r_shifted[1]),
          .ADR2 (adb_r_shifted[2]),
          .ADR3 (adb_r_shifted[3]),
          .ADR4 (adb_r_shifted[4]),
          .ADR5 (adb_r_shifted[5]),
          .ADR6 (adb_r_shifted[6]),
          .ADR7 (adb_r_shifted[7]),
          .ADR8 (adb_r_shifted[8]),
          .ADR9 (adb_r_shifted[9]),
          .ADR10(adb_r_shifted[10]),
          .ADR11(adb_r_shifted[11]),
          .ADR12(adb_r_shifted[12]),
          .ADR13(adb_r_shifted[13]),

          .DO0 (dob[0]),
          .DO1 (dob[1]),
          .DO2 (dob[2]),
          .DO3 (dob[3]),
          .DO4 (dob[4]),
          .DO5 (dob[5]),
          .DO6 (dob[6]),
          .DO7 (dob[7]),
          .DO8 (dob[8]),
          .DO9 (dob[9]),
          .DO10(dob[10]),
          .DO11(dob[11]),
          .DO12(dob[12]),
          .DO13(dob[13]),
          .DO14(dob[14]),
          .DO15(dob[15]),
          .DO16(dob[16]),
          .DO17(dob[17]),
          .DO18(dob[18]),
          .DO19(dob[19]),
          .DO20(dob[20]),
          .DO21(dob[21]),
          .DO22(dob[22]),
          .DO23(dob[23]),
          .DO24(dob[24]),
          .DO25(dob[25]),
          .DO26(dob[26]),
          .DO27(dob[27]),
          .DO28(dob[28]),
          .DO29(dob[29]),
          .DO30(dob[30]),
          .DO31(dob[31]),
          .DO32(dob[32]),
          .DO33(dob[33]),
          .DO34(dob[34]),
          .DO35(dob[35]),

          .CEW (wr_en),
          .CLKW(wr_clk),

          .CER (rd_en),
          .OCER(1'b1),
          .CLKR(rd_clk),
          .RST (rst),
          // Unused: bank addressing
          .BE3 (1'b1),
          .BE2 (1'b1),
          .BE1 (1'b1),
          .BE0 (1'b1),
          // Unused: for > 18kb of memory
          .CSW2(1'b0),
          .CSW1(1'b0),
          .CSW0(1'b0),
          .CSR2(1'b0),
          .CSR1(1'b0),
          .CSR0(1'b0)
      );
    end

    /* verilator lint_on PINMISSING */
    /* verilator lint_on IMPLICIT */
  endgenerate
`endif
endmodule

