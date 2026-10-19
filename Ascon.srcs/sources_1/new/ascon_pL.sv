module ascon_pL(
 	input logic [4:0][63:0] S_in,
  output logic  [4:0][63:0] S_out
);
  function automatic logic [63:0] ror64(logic [63:0] val,int unsigned shift);
    return (val>>shift)|(val<<(64-shift));
  endfunction
  always_comb begin
    S_out[0]=S_in[0]^ror64(S_in[0],19)^ror64(S_in[0],28);
    S_out[1]=S_in[1]^ror64(S_in[1],61)^ror64(S_in[1],39);
    S_out[2]=S_in[2]^ror64(S_in[2],1)^ror64(S_in[2],6);
    S_out[3]=S_in[3]^ror64(S_in[3],10)^ror64(S_in[3],17);
    S_out[4]=S_in[4]^ror64(S_in[4],7)^ror64(S_in[4],41);
  end
endmodule