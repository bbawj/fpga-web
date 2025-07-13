`ifndef utils_svh_
`define utils_svh_
// is for choosing the nibbles in least significant order in a byte
`define SELECT_NIBBLE(data, end_count, start_count) \
  data[4*(end_count - start_count + 1) - 1 -: 4]

`endif
