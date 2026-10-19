`timescale 1ns / 1ps
module tb_kat;
  parameter bit STRICT   = 0;   // require unused ciphertext bytes == 0
  parameter bit SCRAMBLE = 0;   // change key/nonce buses after start
  localparam int NVEC = 1089;
  localparam int TIMEOUT_NS = 30000;

  logic clk=0, rst_n=0, start=0, ready, done;
  logic [63:0] key_0=64'h0706050403020100, key_1=64'h0f0e0d0c0b0a0908;
  logic [63:0] nonce_0=64'h1716151413121110, nonce_1=64'h1f1e1d1c1b1a1918;
  logic [63:0] data_in=0; logic [3:0] data_bytes=0;
  logic data_valid=0, data_is_ad=0, data_last=0, data_ready;
  logic [63:0] cipher_out; logic cipher_valid;
  logic [127:0] tag_out; logic tag_valid;
  always #5 clk = ~clk;

  ascon_top u_top(.clk(clk),.rst_n(rst_n),.start(start),.ready(ready),.done(done),
    .key_0(key_0),.key_1(key_1),.nonce_0(nonce_0),.nonce_1(nonce_1),
    .data_in(data_in),.data_bytes(data_bytes),.data_valid(data_valid),.data_is_ad(data_is_ad),
    .data_last(data_last),.data_ready(data_ready),
    .cipher_out(cipher_out),.cipher_valid(cipher_valid),.tag_out(tag_out),.tag_valid(tag_valid));

  reg [7:0] mem [0:NVEC*128-1];
  logic [63:0] ct_words [0:15]; integer ct_cnt; logic collect;
  always @(posedge clk) if (collect && cipher_valid) begin
    if (ct_cnt<16) ct_words[ct_cnt] = cipher_out; ct_cnt = ct_cnt+1; end

  logic timed_out;
  task automatic wait_ready; integer n; begin n=0;
    while (data_ready!==1'b1 && n<TIMEOUT_NS) begin #1; n=n+1; end
    if (n>=TIMEOUT_NS) timed_out=1; end endtask
  task automatic wait_done; integer n; begin n=0;
    while (done!==1'b1 && n<TIMEOUT_NS) begin #1; n=n+1; end
    if (n>=TIMEOUT_NS) timed_out=1; end endtask

  integer v, base, adl, ptl, n_ad, n_pt, n_ct, i, b, nb, fails, bad_ct, bad_tag, bad_to, bad_cnt, npass;
  logic [63:0] w, exp_t0, exp_t1, got, expw;
  logic ok_ct, ok_tag, ok_cnt;
  logic [127:0] ea, eb;
  integer fail_ad [0:NVEC-1]; integer fail_pt [0:NVEC-1]; integer fail_kind [0:NVEC-1]; integer nf;

  initial begin
    $readmemh("kat.mem", mem);
    fails=0; nf=0; npass=0; bad_ct=0; bad_tag=0; bad_to=0; bad_cnt=0; collect=0; ct_cnt=0;
    #20;
    for (v=0; v<NVEC; v=v+1) begin
      base=v*128; adl=mem[base]; ptl=mem[base+1];
      n_ad=(adl+7)/8; n_pt=(ptl==0)?1:(ptl+7)/8; n_ct=(ptl+7)/8;
      timed_out=0; ct_cnt=0; collect=0;
      rst_n=0; start=0; data_valid=0; data_in=0; data_bytes=0; data_is_ad=0; data_last=0;
      key_0=64'h0706050403020100; key_1=64'h0f0e0d0c0b0a0908;
      nonce_0=64'h1716151413121110; nonce_1=64'h1f1e1d1c1b1a1918;
      #20; rst_n=1; #20; collect=1;
      @(negedge clk); start=1; @(negedge clk); start=0;
      if (SCRAMBLE) begin key_0=64'hDEADBEEFDEADBEEF; key_1=64'hBAADF00DBAADF00D;
                          nonce_0=64'h0123456789ABCDEF; nonce_1=64'hFEDCBA9876543210; end
      wait_ready(); @(negedge clk);
      for (i=0;i<n_ad;i=i+1) begin
        nb=(adl-8*i>8)?8:(adl-8*i); w=0;
        for (b=0;b<nb;b=b+1) w[8*b+:8]=mem[base+2+8*i+b];
        data_in=w; data_bytes=nb; data_is_ad=1; data_last=(i==n_ad-1); data_valid=1;
        @(negedge clk);
        if ((i==n_ad-1)||(i%2==1)) begin data_valid=0; wait_ready(); @(negedge clk); end
      end
      for (i=0;i<n_pt;i=i+1) begin
        nb=(ptl==0)?0:((ptl-8*i>8)?8:(ptl-8*i)); w=0;
        for (b=0;b<nb;b=b+1) w[8*b+:8]=mem[base+34+8*i+b];
        data_in=w; data_bytes=nb; data_is_ad=0; data_last=(i==n_pt-1); data_valid=1;
        @(negedge clk);
        if ((i==n_pt-1)) data_valid=0;
        else if (i%2==1) begin data_valid=0; wait_ready(); @(negedge clk); end
      end
      data_valid=0;
      wait_done(); @(posedge clk); #1; #40; collect=0;
      // checks
      ok_cnt=(ct_cnt==n_ct); ok_ct=1;
      for (i=0;i<n_ct && i<ct_cnt;i=i+1) begin
        nb=(ptl-8*i>8)?8:(ptl-8*i); expw=0;
        for (b=0;b<nb;b=b+1) expw[8*b+:8]=mem[base+66+8*i+b];
        got=ct_words[i];
        if (!STRICT) got = got & ((nb>=8)?64'hFFFFFFFFFFFFFFFF:((64'h1<<(8*nb))-1));
        if (got!==expw) ok_ct=0;
      end
      exp_t0=0; exp_t1=0;
      for (b=0;b<8;b=b+1) begin exp_t0[8*b+:8]=mem[base+66+ptl+b]; exp_t1[8*b+:8]=mem[base+66+ptl+8+b]; end
      ea={exp_t1,exp_t0}; eb={exp_t0,exp_t1};
      ok_tag=(tag_out===ea)||(tag_out===eb);
      if (timed_out||!ok_cnt||!ok_ct||!ok_tag) begin
        fails=fails+1; fail_ad[nf]=adl; fail_pt[nf]=ptl;
        fail_kind[nf]= timed_out ? 1 : (!ok_cnt ? 2 : (!ok_tag ? 3 : 4)); nf=nf+1;
        if (timed_out) bad_to=bad_to+1; else if (!ok_cnt) bad_cnt=bad_cnt+1;
        else if (!ok_tag) bad_tag=bad_tag+1; else bad_ct=bad_ct+1;
      end else npass=npass+1;
    end
    $display("RESULT passed=%0d failed=%0d  (timeout=%0d ctcount=%0d tag=%0d ct=%0d)", npass, fails, bad_to, bad_cnt, bad_tag, bad_ct);
    for (i=0;i<nf;i=i+1) $display("FAILLIST ad=%0d pt=%0d kind=%0d", fail_ad[i], fail_pt[i], fail_kind[i]);
    $finish;
  end
endmodule