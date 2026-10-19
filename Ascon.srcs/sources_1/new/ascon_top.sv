`timescale 1ns / 1ps

module ascon_top (
    input  logic         clk,
    input  logic         rst_n,

    input  logic         start,         
    output logic         ready,      
    output logic         done,        

    input  logic [63:0]  key_0,   key_1,   
    input  logic [63:0]  nonce_0, nonce_1, 

    input  logic [63:0]  data_in,
    input  logic [3:0]   data_bytes,  
    input  logic         data_valid,
    input  logic         data_is_ad,   
    input  logic         data_last,     
    output logic         data_ready,

    output logic [63:0]  cipher_out,
    output logic         cipher_valid,
    output logic [127:0] tag_out,
    output logic         tag_valid
);

  localparam logic [63:0] ASCON_AEAD128_IV = 64'h00001000808c0001;

  typedef enum logic [3:0] {
    ST_IDLE,
    ST_INIT_START,
    ST_INIT_RUN,
    ST_AD_WORD0,
    ST_AD_WORD1,
    ST_AD_START,
    ST_AD_PERM,
    ST_AD_EXTRA_PAD,
    ST_PT_WORD0,
    ST_PT_WORD1,
    ST_PT_START,
    ST_PT_PERM,
    ST_PT_EXTRA_PAD,
    ST_FINAL_START,
    ST_FINAL_RUN,
    ST_DONE
  } state_t;

  state_t state;

  logic [4:0][63:0] s;

  logic             perm_start;
  logic             perm_is_p12;
  logic             perm_done;
  logic             perm_ready;
  logic [4:0][63:0] perm_out;

  logic [63:0]      padded_word;

  logic [1:0]       ad_boundary_mode; 
  logic             pt_needs_extra_pad;

  ascon_padder u_padder (
    .data_in     (data_in),
    .valid_bytes (data_bytes),
    .data_padded (padded_word)
  );

  ascon_permutation u_perm (
    .clk       (clk),
    .rst_a     (rst_n),
    .start     (perm_start),
    .is_p12    (perm_is_p12),
    .state_in  (s),
    .state_out (perm_out),
    .done      (perm_done),
    .ready     (perm_ready)
  );

  // Output assignments
  assign ready     = (state == ST_IDLE);
  assign tag_out   = {s[3] ^ key_0, s[4] ^ key_1};
  assign tag_valid = (state == ST_DONE);
  assign done      = (state == ST_DONE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state              <= ST_IDLE;
      s                  <= '0;
      perm_start         <= 1'b0;
      perm_is_p12        <= 1'b0;
      data_ready         <= 1'b0;
      cipher_valid       <= 1'b0;
      cipher_out         <= '0;
      ad_boundary_mode   <= 2'd0;
      pt_needs_extra_pad <= 1'b0;
    end else begin
      perm_start   <= 1'b0;
      cipher_valid <= 1'b0;

      case (state)
        ST_IDLE: begin
          data_ready         <= 1'b0;
          ad_boundary_mode   <= 2'd0;
          pt_needs_extra_pad <= 1'b0;

          if (start) begin
            s[0]  <= ASCON_AEAD128_IV;
            s[1]  <= key_0;
            s[2]  <= key_1;
            s[3]  <= nonce_0;
            s[4]  <= nonce_1;
            state <= ST_INIT_START;
          end
        end

        ST_INIT_START: begin
          perm_start  <= 1'b1;
          perm_is_p12 <= 1'b1;
          state       <= ST_INIT_RUN;
        end

        ST_INIT_RUN: begin
          if (perm_done) begin
            s[0]       <= perm_out[0];
            s[1]       <= perm_out[1];
            s[2]       <= perm_out[2];
            s[3]       <= perm_out[3] ^ key_0;
            s[4]       <= perm_out[4] ^ key_1;
            data_ready <= 1'b1;
            state      <= ST_AD_WORD0;
          end
        end

        ST_AD_WORD0: begin
          if (data_valid && data_is_ad) begin
            data_ready <= 1'b0;

            if (data_last) begin
              if (data_bytes < 4'd8) begin
                s[0]             <= s[0] ^ padded_word;
                ad_boundary_mode <= 2'd1; // Partial final
                state            <= ST_AD_START;
              end else begin
                s[0]             <= s[0] ^ data_in;
                s[1]             <= s[1] ^ 64'h0000_0000_0000_0001;
                ad_boundary_mode <= 2'd1; // Partial final
                state            <= ST_AD_START;
              end
            end else begin
              s[0]       <= s[0] ^ data_in;
              data_ready <= 1'b1;
              state      <= ST_AD_WORD1;
            end
          end else if (data_valid && !data_is_ad) begin
            s[4]       <= s[4] ^ 64'h8000_0000_0000_0000;
            data_ready <= 1'b1;
            state      <= ST_PT_WORD0;
          end
        end

        ST_AD_WORD1: begin
          if (data_valid && data_is_ad) begin
            data_ready <= 1'b0;

            if (data_last) begin
              if (data_bytes < 4'd8) begin
                s[1]             <= s[1] ^ padded_word;
                ad_boundary_mode <= 2'd1; 
                state            <= ST_AD_START;
              end else begin
                s[1]             <= s[1] ^ data_in;
                ad_boundary_mode <= 2'd2; 
                state            <= ST_AD_START;
              end
            end else begin
              s[1]             <= s[1] ^ data_in;
              ad_boundary_mode <= 2'd0;
              state            <= ST_AD_START;
            end
          end
        end

        ST_AD_START: begin
          perm_start  <= 1'b1;
          perm_is_p12 <= 1'b0; // 8 rounds
          state       <= ST_AD_PERM;
        end

        ST_AD_PERM: begin
          if (perm_done) begin
            s <= perm_out;

            case (ad_boundary_mode)
              2'd0: begin
                data_ready <= 1'b1;
                state      <= ST_AD_WORD0;
              end

              2'd1: begin
                s[4]       <= perm_out[4] ^ 64'h8000_0000_0000_0000;
                data_ready <= 1'b1;
                state      <= ST_PT_WORD0;
              end

              2'd2: begin
                state <= ST_AD_EXTRA_PAD;
              end
            endcase
          end
        end

        ST_AD_EXTRA_PAD: begin
          s[0]        <= s[0] ^ 64'h0000_0000_0000_0001; 
          perm_start  <= 1'b1;
          perm_is_p12 <= 1'b0; // 8 rounds
          ad_boundary_mode <= 2'd1;
          state            <= ST_AD_PERM;
        end

        ST_PT_WORD0: begin
          if (data_valid && !data_is_ad) begin
            data_ready   <= 1'b0;
            cipher_out   <= s[0] ^ data_in;
            cipher_valid <= 1'b1;

            if (data_last) begin
              if (data_bytes < 4'd8) begin
                s[0]  <= s[0] ^ padded_word;
                s[2]  <= s[2] ^ key_0;
                s[3]  <= s[3] ^ key_1;
                state <= ST_FINAL_START;
              end else begin
                s[0]  <= s[0] ^ data_in;
                s[1]  <= s[1] ^ 64'h0000_0000_0000_0001;
                s[2]  <= s[2] ^ key_0;
                s[3]  <= s[3] ^ key_1;
                state <= ST_FINAL_START;
              end
            end else begin
              s[0]       <= s[0] ^ data_in;
              data_ready <= 1'b1;
              state      <= ST_PT_WORD1;
            end
          end
        end

        ST_PT_WORD1: begin
          if (data_valid && !data_is_ad) begin
            data_ready   <= 1'b0;
            cipher_out   <= s[1] ^ data_in;
            cipher_valid <= 1'b1;

            if (data_last) begin
              if (data_bytes < 4'd8) begin
                s[1]  <= s[1] ^ padded_word;
                s[2]  <= s[2] ^ key_0;
                s[3]  <= s[3] ^ key_1;
                state <= ST_FINAL_START;
              end else begin
                s[1]               <= s[1] ^ data_in;
                pt_needs_extra_pad <= 1'b1;
                state              <= ST_PT_START;
              end
            end else begin
              s[1]               <= s[1] ^ data_in;
              pt_needs_extra_pad <= 1'b0;
              state              <= ST_PT_START;
            end
          end
        end

        ST_PT_START: begin
          perm_start  <= 1'b1;
          perm_is_p12 <= 1'b0; // 8 rounds
          state       <= ST_PT_PERM;
        end

        ST_PT_PERM: begin
          if (perm_done) begin
            s <= perm_out;

            if (pt_needs_extra_pad) begin
              state <= ST_PT_EXTRA_PAD;
            end else begin
              data_ready <= 1'b1;
              state      <= ST_PT_WORD0;
            end
          end
        end

        ST_PT_EXTRA_PAD: begin
          s[0]  <= s[0] ^ 64'h0000_0000_0000_0001;
          s[2]  <= s[2] ^ key_0;
          s[3]  <= s[3] ^ key_1;
          state <= ST_FINAL_START;
        end

        ST_FINAL_START: begin
          perm_start  <= 1'b1;
          perm_is_p12 <= 1'b1; // 12 rounds
          state       <= ST_FINAL_RUN;
        end

        ST_FINAL_RUN: begin
          if (perm_done) begin
            s     <= perm_out;
            state <= ST_DONE;
          end
        end

        ST_DONE: begin
          state <= ST_IDLE;
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule