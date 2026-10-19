`timescale 1ns / 1ps

module ascon_permutation (
    input  logic             clk,
    input  logic             rst_a,
    input  logic             start,
    input  logic             is_p12, 
    input  logic [4:0][63:0] state_in,
    output logic [4:0][63:0] state_out,
    output logic             done,
    output logic             ready
);

  function automatic logic [7:0] get_rc(logic [3:0] r);
    case (r)
      4'h0: get_rc = 8'h3c; 4'h1: get_rc = 8'h2d;
      4'h2: get_rc = 8'h1e; 4'h3: get_rc = 8'h0f;
      4'h4: get_rc = 8'hf0; 4'h5: get_rc = 8'he1;
      4'h6: get_rc = 8'hd2; 4'h7: get_rc = 8'hc3;
      4'h8: get_rc = 8'hb4; 4'h9: get_rc = 8'ha5;
      4'ha: get_rc = 8'h96; 4'hb: get_rc = 8'h87;
      4'hc: get_rc = 8'h78; 4'hd: get_rc = 8'h69;
      4'he: get_rc = 8'h5a; 4'hf: get_rc = 8'h4b;
      default: get_rc = 8'h00;
    endcase
  endfunction

  typedef enum logic [1:0] {
    S_IDLE     = 2'b00,
    S_PS_SHIFT = 2'b01,
    S_PL_STEP  = 2'b10, 
    S_DONE     = 2'b11
  } perm_state_t;

  perm_state_t      state;
  logic [4:0][63:0] state_reg;
  logic [3:0]       round_cnt;
  logic [2:0]       byte_cnt;   
  logic [4:0][7:0]  ps_in;
  logic [4:0][7:0]  ps_out;
  logic [4:0][63:0] pl_out;

  assign ps_in[0] = state_reg[0][7:0];
  assign ps_in[1] = state_reg[1][7:0];
  assign ps_in[2] = (byte_cnt == 3'd0) ? (state_reg[2][7:0] ^ get_rc(round_cnt)) : state_reg[2][7:0];
  assign ps_in[3] = state_reg[3][7:0];
  assign ps_in[4] = state_reg[4][7:0];

  ascon_pS u_ascon_pS (
    .S_in  (ps_in),
    .S_out (ps_out)
  );

  ascon_pL u_ascon_pL (
    .S_in  (state_reg),
    .S_out (pl_out)
  );

  assign state_out = state_reg;
  assign ready     = (state == S_IDLE);

  always_ff @(posedge clk or negedge rst_a) begin
    if (!rst_a) begin
      state     <= S_IDLE;
      state_reg <= '0;
      round_cnt <= 4'd0;
      byte_cnt  <= 3'd0;
      done      <= 1'b0;
    end else begin
      done <= 1'b0;

      case (state)
        S_IDLE: begin
          if (start) begin
            state_reg <= state_in;
            round_cnt <= is_p12 ? 4'd4 : 4'd8; 
            byte_cnt  <= 3'd0;
            state     <= S_PS_SHIFT;
          end
        end
        S_PS_SHIFT: begin
          state_reg[0] <= {ps_out[0], state_reg[0][63:8]};
          state_reg[1] <= {ps_out[1], state_reg[1][63:8]};
          state_reg[2] <= {ps_out[2], state_reg[2][63:8]};
          state_reg[3] <= {ps_out[3], state_reg[3][63:8]};
          state_reg[4] <= {ps_out[4], state_reg[4][63:8]};

          if (byte_cnt == 3'd7) begin
            byte_cnt <= 3'd0;
            state    <= S_PL_STEP;
          end else begin
            byte_cnt <= byte_cnt + 3'd1;
          end
        end

        S_PL_STEP: begin
          state_reg <= pl_out;

          if (round_cnt == 4'd15) begin
            done  <= 1'b1;
            state <= S_DONE;
          end else begin
            round_cnt <= round_cnt + 4'd1;
            state     <= S_PS_SHIFT;
          end
        end
        S_DONE: begin
          if (!start) begin
            state <= S_IDLE;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule