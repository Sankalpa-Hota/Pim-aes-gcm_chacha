`timescale 1ns/1ps
`default_nettype none

module tb_chacha20_poly1305_core;

    reg clk;
    reg rst_n;
    reg [255:0] key;
    reg [95:0] nonce;
    reg [31:0] ctr_init;
    reg cfg_we;
    reg ks_req;
    reg aad_valid;
    reg [127:0] aad_data;
    reg [15:0] aad_keep;
    reg pld_valid;
    reg [127:0] pld_data;
    reg [15:0] pld_keep;
    reg len_valid;
    reg [127:0] len_block;
    reg algo_sel;

    wire ks_valid;
    wire [511:0] ks_data;
    wire aad_ready;
    wire pld_ready;
    wire len_ready;
    wire [127:0] tag_pre_xor;
    wire tag_pre_xor_valid;
    wire [127:0] tagmask;
    wire tagmask_valid;
    wire aad_done;
    wire pld_done;
    wire lens_done;

    // Cycle counter
    integer cycle_counter;

    // Index for payload encryption
    integer payload_idx;

    // Encrypted data temporary
    reg [127:0] enc_data;

    // DUT instantiation
    chacha20_poly1305_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .key(key),
        .nonce(nonce),
        .ctr_init(ctr_init),
        .cfg_we(cfg_we),
        .ks_req(ks_req),
        .ks_valid(ks_valid),
        .ks_data(ks_data),
        .aad_valid(aad_valid),
        .aad_data(aad_data),
        .aad_keep(aad_keep),
        .aad_ready(aad_ready),
        .pld_valid(pld_valid),
        .pld_data(pld_data),
        .pld_keep(pld_keep),
        .pld_ready(pld_ready),
        .len_valid(len_valid),
        .len_block(len_block),
        .len_ready(len_ready),
        .tag_pre_xor(tag_pre_xor),
        .tag_pre_xor_valid(tag_pre_xor_valid),
        .tagmask(tagmask),
        .tagmask_valid(tagmask_valid),
        .aad_done(aad_done),
        .pld_done(pld_done),
        .lens_done(lens_done),
        .algo_sel(algo_sel)
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    // VCD dump
    initial begin
        $dumpfile("chacha20_poly1305_tb.vcd");
        $dumpvars(0, tb_chacha20_poly1305_core);
    end

    // Cycle counter
    initial cycle_counter = 0;
    always @(posedge clk) cycle_counter = cycle_counter + 1;

    integer i, j;

    initial begin
        // Reset and init
        rst_n = 0; cfg_we = 0; ks_req = 0; algo_sel = 1;
        key = 256'h0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef;
        nonce = 96'habcdef1234567890abcdef12;
        ctr_init = 32'h0;
        aad_valid = 0; aad_data = 0; aad_keep = 0;
        pld_valid = 0; pld_data = 0; pld_keep = 0;
        len_valid = 0; len_block = 0;

        #20 rst_n = 1;

        // Start Poly1305 (cfg_we pulse)
        @(posedge clk); cfg_we = 1;
        @(posedge clk); cfg_we = 0;

        // Request one keystream block
        @(posedge clk); ks_req = 1;
        @(posedge clk); ks_req = 0;

        // Wait for keystream valid
        wait(ks_valid);
        $display("[Cycle %0d] Keystream generated: %h", cycle_counter, ks_data);

        // --- Feed 5 AAD blocks ---
        for (i = 0; i < 5; i = i + 1) begin
            wait(aad_ready);
            @(posedge clk);
            aad_valid <= 1;
            aad_data  <= $random;
            aad_keep  <= 16'hFFFF;
            $display("[Cycle %0d] AAD input %0d: %h", cycle_counter, i, aad_data);

            @(posedge clk);
            aad_valid <= 0;

            wait(aad_done);
            $display("[Cycle %0d] AAD block %0d processed", cycle_counter, i);
        end

        // --- Feed 5 Payload blocks ---
        payload_idx = 0;
        for (i = 0; i < 5; i = i + 1) begin
            wait(pld_ready);
            @(posedge clk);
            pld_valid <= 1;
            pld_data  <= $random;
            pld_keep  <= 16'hFFFF;
            $display("[Cycle %0d] Payload input %0d: %h", cycle_counter, i, pld_data);

            // Encrypt the payload by XOR with keystream (take 128-bit slice of 512-bit keystream)
            enc_data = pld_data ^ ks_data[127:0];  // Using lower 128 bits for example
            $display("[Cycle %0d] Encrypted payload %0d: %h", cycle_counter, i, enc_data);

            @(posedge clk);
            pld_valid <= 0;

            wait(pld_done);
            $display("[Cycle %0d] Payload block %0d processed", cycle_counter, i);
        end

        // --- Feed 1 Length block ---
        wait(len_ready);
        @(posedge clk);
        len_valid <= 1;
        len_block <= 128'h00000000000000000000000000000100; // example size 256 bytes
        $display("[Cycle %0d] LEN block: %h", cycle_counter, len_block);

        @(posedge clk);
        len_valid <= 0;

        wait(lens_done);
        $display("[Cycle %0d] LEN block processed", cycle_counter);

        // Wait for tag outputs
        wait(tag_pre_xor_valid && tagmask_valid);
        $display("[Cycle %0d] Final Tag Pre-XOR: %h", cycle_counter, tag_pre_xor);
        $display("[Cycle %0d] Final Tagmask: %h", cycle_counter, tagmask);

        // Display total cycles
        $display("Total cycles for 5 AAD + 5 Payload + 1 LEN: %0d", cycle_counter);

        $finish;
    end

endmodule

`default_nettype wire
