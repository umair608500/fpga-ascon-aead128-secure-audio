`timescale 1ns / 1ps

module ascon_padder (
    input  logic [63:0] data_in,     
    input  logic [3:0]  valid_bytes,  
    output logic [63:0] data_padded  
);

  always_comb begin
    case (valid_bytes)
      4'd0: data_padded = 64'h0000_0000_0000_0001;
      4'd1: data_padded = {48'h0, 8'h01, data_in[7:0]};
      4'd2: data_padded = {40'h0, 8'h01, data_in[15:0]};
      4'd3: data_padded = {32'h0, 8'h01, data_in[23:0]};
      4'd4: data_padded = {24'h0, 8'h01, data_in[31:0]};
      4'd5: data_padded = {16'h0, 8'h01, data_in[39:0]};
      4'd6: data_padded = { 8'h0, 8'h01, data_in[47:0]};
      4'd7: data_padded = {       8'h01, data_in[55:0]};
      4'd8: data_padded = data_in;

      default: data_padded = data_in;
    endcase
  end
endmodule