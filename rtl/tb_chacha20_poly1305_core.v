`timescale 1ns/1ps
`default_nettype none

module tb_chacha20_poly1305_core;

    // ------------------------
    // Clock & reset
    // ------------------------
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk; // 100 MHz clock

    // ------------------------
    // Inputs
    // ------------------------
    reg [255:0] key;
    reg [95:0]  nonce;
    reg [31:0]  ctr_init;
    reg cfg_we;
    reg ks_req;
    reg aad_valid;
    reg [127:0] aad_data;
    reg [15:0]  aad_keep;
    reg pld_valid;
    reg [127:0] pld_data;
    reg [15:0]  pld_keep;
    reg len_valid;
    reg [127:0] len_block;
    reg algo_sel;

    // ------------------------
    // Outputs
    // ------------------------
    wire ks_valid;
    wire [511:0] ks_data;
    wire aad_ready, pld_ready, len_ready;
    wire [127:0] tag_pre_xor;
    wire tag_pre_xor_valid;
    wire [127:0] tagmask;
    wire tagmask_valid;
    wire aad_done, pld_done, lens_done;

    // ------------------------
    // DUT instantiation
    // ------------------------
    chacha20_poly1305_core dut (
        .clk(clk), .rst_n(rst_n),
        .key(key), .nonce(nonce), .ctr_init(ctr_init),
        .cfg_we(cfg_we), .ks_req(ks_req),
        .ks_valid(ks_valid), .ks_data(ks_data),
        .aad_valid(aad_valid), .aad_data(aad_data), .aad_keep(aad_keep), .aad_ready(aad_ready),
        .pld_valid(pld_valid), .pld_data(pld_data), .pld_keep(pld_keep), .pld_ready(pld_ready),
        .len_valid(len_valid), .len_block(len_block), .len_ready(len_ready),
        .tag_pre_xor(tag_pre_xor), .tag_pre_xor_valid(tag_pre_xor_valid),
        .tagmask(tagmask), .tagmask_valid(tagmask_valid),
        .aad_done(aad_done), .pld_done(pld_done), .lens_done(lens_done),
        .algo_sel(algo_sel)
    );

    // ------------------------
    // Payload array (4 blocks)
    // ------------------------
    reg [127:0] payload [0:3];
    integer i;

    // ------------------------
    // Stimulus
    // ------------------------
    initial begin
        // Reset
        rst_n = 0;
        cfg_we = 0; ks_req = 0;
        aad_valid = 0; pld_valid = 0; len_valid = 0;
        algo_sel = 1; // ChaCha mode

        key      = 256'h00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff;
        nonce    = 96'h0102030405060708090a0b0c;
        ctr_init = 32'h00000001;

        // 4 payload blocks (512 bits total)
        payload[0] = 128'h11111111_22222222_33333333_44444444;
        payload[1] = 128'h55555555_66666666_77777777_88888888;
        payload[2] = 128'h99999999_aaaaaaaa_bbbbbbbb_cccccccc;
        payload[3] = 128'hdddddddd_eeeeeeee_ffffffff_00000000;

        #20;
        rst_n = 1;

        // ------------------------
        // Step 1: CONFIG write
        // ------------------------
        cfg_we = 1;
        #10;
        cfg_we = 0;

        // ------------------------
        // Step 2: KEYSTREAM request
        // ------------------------
        ks_req = 1;
        #10;
        ks_req = 0;

        // ------------------------
        // Step 3: AAD input
        // ------------------------
        aad_data = 128'hdeadbeef_01234567_89abcdef_00112233;
        aad_keep = 16'hffff;
        aad_valid = 1;
        wait(aad_ready);
        #10;
        aad_valid = 0;

        // ------------------------
        // Step 4: Payload input (4 blocks)
        // ------------------------
        for(i = 0; i < 4; i = i + 1) begin
            pld_data  = payload[i];
            pld_keep  = 16'hffff;
            pld_valid = 1;
            wait(pld_ready);
            #10;
            pld_valid = 0;
        end

        // ------------------------
        // Step 5: Length block
        // ------------------------
        len_block = 128'h00000000_00000010_00000000_00000040; // Example: 16B AAD + 64B payload
        len_valid = 1;
        wait(len_ready);
        #10;
        len_valid = 0;

        // ------------------------
        // Step 6: Wait for outputs
        // ------------------------
        wait(tag_pre_xor_valid);
        wait(aad_done & pld_done & lens_done);

        $display("[%0t] Testbench completed", $time);
        $finish;
    end

    // ------------------------
    // Monitor
    // ------------------------
    always @(posedge clk) begin
        if(ks_valid) $display("[%0t] Keystream: %h", $time, ks_data);
        if(tag_pre_xor_valid) $display("[%0t] Tag: %h, Mask: %h", $time, tag_pre_xor, tagmask);
    end

endmodule
`default_nettype wire
