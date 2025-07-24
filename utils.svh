`ifndef utils_svh_
`define utils_svh_

`ifdef SPEED_100M
  // 100M works on 1 nibble per cycle, but our interfaces are all 8 bit. Since
  // only the nibble matters, we can still select 1 byte but only shift by
  // 4 bits on count increasing
`define SELECT_BYTE(data, end_count, start_count) \
  data[4*(end_count - start_count + 1) - 1 -: 4]
`else
`define SELECT_BYTE(data, end_count, start_count) \
  data[8*(end_count - start_count + 1) - 1 -: 8]
`endif

`endif
