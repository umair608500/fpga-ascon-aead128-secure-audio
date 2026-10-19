`timescale 1ns / 1ps

module tb_ascon;

  logic        clk;
  logic        rst_n;

  // --- Top-level signals ---
  logic        start;
  logic        ready;
  logic        done;

  logic [63:0] key_0, key_1;
  logic [63:0] nonce_0, nonce_1;

  logic [63:0] data_in;
  logic [3:0]  data_bytes;
  logic        data_valid;
  logic        data_is_ad;
  logic        data_last;
  logic        data_ready;

  logic [63:0]  cipher_out;
  logic         cipher_valid;
  logic [127:0] tag_out;
  logic         tag_valid;

  // Captured RTL outputs
  logic [63:0] ct_w0, ct_w1;
  int          ct_count;

  // ============================================================
  // ASCON REFERENCE MODEL IN TESTBENCH (Matches C Code)
  // ============================================================
  localparam [63:0] RC [0:15] = '{
    64'h000000000000003c, 64'h000000000000002d,
    64'h000000000000001e, 64'h000000000000000f,
    64'h00000000000000f0, 64'h00000000000000e1,
    64'h00000000000000d2, 64'h00000000000000c3,
    64'h00000000000000b4, 64'h00000000000000a5,
    64'h0000000000000096, 64'h0000000000000087,
    64'h0000000000000078, 64'h0000000000000069,
    64'h000000000000005a, 64'h000000000000004b
  };

  function automatic logic [63:0] ror64(input logic [63:0] x, input int n);
    return (x >> n) | (x << (64 - n));
  endfunction

  task automatic ascon_pS(inout logic [63:0] S[0:4]);
    logic [63:0] t0, t1, t2, t3, t4;
    begin
      S[0] ^= S[4];
      S[4] ^= S[3];
      S[2] ^= S[1];

      t0 = ~S[0] & S[1];
      t1 = ~S[1] & S[2];
      t2 = ~S[2] & S[3];
      t3 = ~S[3] & S[4];
      t4 = ~S[4] & S[0];

      S[0] ^= t1;
      S[1] ^= t2;
      S[2] ^= t3;
      S[3] ^= t4;
      S[4] ^= t0;

      S[1] ^= S[0];
      S[0] ^= S[4];
      S[3] ^= S[2];
      S[2] = ~S[2];
    end
  endtask

  task automatic ascon_pL(inout logic [63:0] S[0:4]);
    begin
      S[0] ^= ror64(S[0], 19) ^ ror64(S[0], 28);
      S[1] ^= ror64(S[1], 61) ^ ror64(S[1], 39);
      S[2] ^= ror64(S[2], 1)  ^ ror64(S[2], 6);
      S[3] ^= ror64(S[3], 10) ^ ror64(S[3], 17);
      S[4] ^= ror64(S[4], 7)  ^ ror64(S[4], 41);
    end
  endtask

  task automatic ascon_p(inout logic [63:0] S[0:4], input int rounds);
    int r;
    begin
      for (r = 16 - rounds; r < 16; r = r + 1) begin
        S[2] ^= RC[r];
        ascon_pS(S);
        ascon_pL(S);
        $display("p%0d round %2d: %016h %016h %016h %016h %016h",
                 rounds, r, S[0], S[1], S[2], S[3], S[4]);
      end
      $display("");
    end
  endtask

  // Golden reference state
  logic [63:0] S_ref [0:4];
  logic [63:0] exp_ct_0, exp_ct_1;
  logic [63:0] exp_tag_0, exp_tag_1;

  // Clock generation: 100 MHz (10ns period)
  always #5 clk = ~clk;

  // Instantiate Top Module
  ascon_top u_top (
    .clk          (clk),
    .rst_n        (rst_n),
    .start        (start),
    .ready        (ready),
    .done         (done),

    .key_0        (key_0),
    .key_1        (key_1),
    .nonce_0      (nonce_0),
    .nonce_1      (nonce_1),

    .data_in      (data_in),
    .data_bytes   (data_bytes),
    .data_valid   (data_valid),
    .data_is_ad   (data_is_ad),
    .data_last    (data_last),
    .data_ready   (data_ready),

    .cipher_out   (cipher_out),
    .cipher_valid (cipher_valid),

    .tag_out      (tag_out),
    .tag_valid    (tag_valid)
  );

  // Capture RTL Ciphertext
  always @(posedge clk) begin
    if (cipher_valid) begin
      if (ct_count == 0) ct_w0 <= cipher_out;
      if (ct_count == 1) ct_w1 <= cipher_out;
      ct_count <= ct_count + 1;
    end
  end

  // ============================================================
  // TEST SEQUENCE
  // ============================================================
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb_ascon);

    clk        = 0;
    rst_n      = 0;
    start      = 0;
    data_valid = 0;
    data_in    = 0;
    data_bytes = 0;
    data_is_ad = 0;
    data_last  = 0;
    ct_count   = 0;

    // Test Vectors
    key_0   = 64'h0706050403020100;
    key_1   = 64'h0f0e0d0c0b0a0908;
    nonce_0 = 64'h1716151413121110;
    nonce_1 = 64'h1f1e1d1c1b1a1918;

    #20;
    rst_n = 1;
    #20;

    // ------------------------------------------------------------
    // 1. Initialization (p12)
    // ------------------------------------------------------------
    $display("--- [Initialization p12] ---");
    S_ref[0] = 64'h00001000808c0001;
    S_ref[1] = key_0;
    S_ref[2] = key_1;
    S_ref[3] = nonce_0;
    S_ref[4] = nonce_1;

    // Print all 12 rounds of initialization
    ascon_p(S_ref, 12);
    S_ref[3] ^= key_0;
    S_ref[4] ^= key_1;

    @(negedge clk);
    start = 1;
    @(negedge clk);
    start = 0;

    // ------------------------------------------------------------
    // 2. Associated Data (p8)
    // ------------------------------------------------------------
    wait (data_ready == 1'b1);
    @(negedge clk);

    $display("--- [Associated Data p8] ---");
    // AD block = 8 bytes (padded with 0x01 in next word)
    S_ref[0] ^= 64'h3736353433323130;
    S_ref[1] ^= 64'h0000000000000001;

    // Print all 8 rounds of AD permutation
    ascon_p(S_ref, 8);
    S_ref[4] ^= 64'h8000000000000000; // Domain separation

    data_in    = 64'h3736353433323130;
    data_bytes = 4'd8;
    data_is_ad = 1'b1;
    data_last  = 1'b1;
    data_valid = 1'b1;
    @(negedge clk);
    data_valid = 1'b0;

    // ------------------------------------------------------------
    // 3. Plaintext Processing (p8)
    // ------------------------------------------------------------
    wait (data_ready == 1'b1);
    @(negedge clk);

    $display("--- [Plaintext Processing p8] ---");
    S_ref[0] ^= 64'h2726252423222120;
    S_ref[1] ^= 64'h2f2e2d2c2b2a2928;
    exp_ct_0  = S_ref[0];
    exp_ct_1  = S_ref[1];

    // Print all 8 rounds of PT permutation
    ascon_p(S_ref, 8);

    // Final padding and key addition
    S_ref[0] ^= 64'h0000000000000001;
    S_ref[2] ^= key_0;
    S_ref[3] ^= key_1;

    // Plaintext Block 0
    data_in    = 64'h2726252423222120;
    data_bytes = 4'd8;
    data_is_ad = 1'b0;
    data_last  = 1'b0;
    data_valid = 1'b1;
    @(negedge clk);

    // Plaintext Block 1
    data_in    = 64'h2f2e2d2c2b2a2928;
    data_bytes = 4'd8;
    data_is_ad = 1'b0;
    data_last  = 1'b1;
    data_valid = 1'b1;
    @(negedge clk);
    data_valid = 1'b0;

    // ------------------------------------------------------------
    // 4. Finalization (p12) & Tag Generation
    // ------------------------------------------------------------
    $display("--- [Finalization p12] ---");
    // Print all 12 rounds of Finalization permutation
    ascon_p(S_ref, 12);
    exp_tag_0 = S_ref[3] ^ key_0;
    exp_tag_1 = S_ref[4] ^ key_1;

    wait (done == 1'b1);
    @(posedge clk);

    $display("================ EXPECTED OUTPUTS ================");
    $display("Expected CT Word 0 : 0x%016h", exp_ct_0);
    $display("Hardware CT Word 0 : 0x%016h", ct_w0);
    $display("Expected CT Word 1 : 0x%016h", exp_ct_1);
    $display("Hardware CT Word 1 : 0x%016h", ct_w1);
    $display("Expected Tag       : 0x%016h%016h", exp_tag_0, exp_tag_1);
    $display("Hardware Tag       : 0x%032h", tag_out);
    $display("==================================================");

    #50;
    $finish;
  end

endmodule