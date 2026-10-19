module ascon_pS(
  input logic [4:0][7:0] S_in,
  output logic [4:0][7:0] S_out
);
  logic [4:0][7:0] x;
  logic [4:0][7:0] t;
  always_comb begin
    x[0]=S_in[0]^S_in[4];
    x[4]=S_in[4]^S_in[3];
    x[2]=S_in[2]^S_in[1];
    x[1]=S_in[1];
    x[3]=S_in[3];
    
    t[0]=(~x[0])&x[1];
    t[1]=(~x[1])&x[2];
    t[2]=(~x[2])&x[3];
    t[3]=(~x[3])&x[4];
    t[4]=(~x[4])&x[0];
    
    x[0]=x[0]^t[1];
    x[1]=x[1]^t[2];
    x[2]=x[2]^t[3];
    x[3]=x[3]^t[4];
    x[4]=x[4]^t[0];
    
    S_out[1]=x[1]^x[0];
    S_out[0]=x[0]^x[4];
    S_out[3]=x[3]^x[2];
    S_out[4]=x[4];
    S_out[2] = ~x[2];
  end
endmodule