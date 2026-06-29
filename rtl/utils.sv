package utils;

  function automatic logic [15:0] ones_comp(logic [15:0] checksum, logic [15:0] data);
    logic [16:0] sum;
    sum = data + checksum;
    ones_comp = sum[15:0] + {15'b0, sum[16]};
  endfunction

  function automatic logic [3:0] onehot_to_binary(logic [7:0] onehot_in);
    casez (onehot_in)
      8'b???????1: onehot_to_binary = 4'd1;
      8'b??????10: onehot_to_binary = 4'd2;
      8'b?????100: onehot_to_binary = 4'd3;
      8'b????1000: onehot_to_binary = 4'd4;
      8'b???10000: onehot_to_binary = 4'd5;
      8'b??100000: onehot_to_binary = 4'd6;
      8'b?1000000: onehot_to_binary = 4'd7;
      8'b10000000: onehot_to_binary = 4'd8;
      default:     onehot_to_binary = 4'd0;
    endcase
  endfunction

endpackage
