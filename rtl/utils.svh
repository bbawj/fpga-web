`ifndef utils_svh_
`define utils_svh_

`ifdef SPEED_100M
  // 100M works on 1 nibble per cycle, but our interfaces are all 8 bit. Since
  // only the nibble matters, we can still select 1 byte but only shift by
  // 4 bits on count increasing
`define SELECT_BYTE_LSB(data, end_count, start_count) \
  data[4*(end_count - start_count + 1) - 1 -: 4]
  // data = [31:0], end_count = 0, start_count = 0
  // data[32 - 4*(1) + 8*0 - 1 -: 4] = data[27:24]
  // end_count = 1, start_count = 0
  // data[32 - 4*(2) + 8*1 - 1 -: 4] = data[31:28]
  // end_count = 2, start_count = 0
  // data[32 - 4*(3) + 8*0 - 1 -: 4] = data[19:16]
`define SELECT_BYTE_MSB(data, end_count, start_count) \
  data[$bits(data) - 4*(end_count - start_count + 1) + 8 * (end_count & 1'b1 ? 1 : 0) - 1 -: 4]
`else
`define SELECT_BYTE_LSB(data, end_count, start_count) \
  data[8*(end_count - start_count + 1) - 1 -: 8]
`define SELECT_BYTE_MSB(data, end_count, start_count) \
  data[$bits(data) - 8*(end_count - start_count) - 1 -: 8]
`endif

`endif
