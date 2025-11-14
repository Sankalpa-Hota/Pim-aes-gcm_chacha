`timescale 1ns/1ps
`default_nettype none

module tb_chacha20_poly1305_core;

    // ------------------------
    // Clock & reset
    // ------------------------
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk; // 100 MHz clock

    integer cycle_count = 0;
    always @(posedge clk) cycle_count = cycle_count + 1;

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
    // DUT
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
    // Step tracking
    // ------------------------
    typedef enum logic [2:0] {
        STEP_IDLE       = 3'd0,
        STEP_CFG        = 3'd1,
        STEP_KEYSTREAM  = 3'd2,
        STEP_AAD        = 3'd3,
        STEP_PAYLOAD    = 3'd4,
        STEP_LENGTH     = 3'd5,
        STEP_TAG        = 3'd6,
        STEP_DONE       = 3'd7
    } step_t;

    step_t step = STEP_IDLE;

    // ------------------------
    // Payload array
    // ------------------------
    reg [127:0] payload[0:3]; // 512-bit payload as 4 x 128-bit
    integer pld_idx;

    // ------------------------
    // Stimulus
    // ------------------------
    initial begin
        // Reset
        rst_n = 0;
        cfg_we = 0; ks_req = 0;
        aad_valid = 0; pld_valid = 0; len_valid = 0;
        algo_sel = 1; // ChaCha only
        cycle_count = 0;
        step = STEP_IDLE;

        key      = 256'h00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff;
        nonce    = 96'h0102030405060708090a0b0c;
        ctr_init = 32'h00000001;

        // 512-bit payload
        payload[0] = 128'h11111111_22222222_33333333_44444444;
        payload[1] = 128'h55555555_66666666_77777777_88888888;
        payload[2] = 128'h99999999_aaaaaaaa_bbbbbbbb_cccccccc;
        payload[3] = 128'hdddddddd_eeeeeeee_ffffffff_00000000;

        #20;
        rst_n = 1;

        $display("Starting 512-bit ChaCha20-Poly1305 testbench...");
        $display("Key: %h", key);
        $display("Nonce: %h", nonce);
        $display("Ctr init: %h", ctr_init);

        // ------------------------
        // Step 1: CONFIG write
        // ------------------------
        step = STEP_CFG;
        cfg_we = 1;
        #10;
        cfg_we = 0;

        // ------------------------
        // Step 2: KEYSTREAM request
        // ------------------------
        step = STEP_KEYSTREAM;
        ks_req = 1;
        #10;
        ks_req = 0;

        // ------------------------
        // Step 3: AAD input (optional, 128-bit)
        // ------------------------
        step = STEP_AAD;
        aad_data  = 128'hdeadbeef_01234567_89abcdef_00112233;
        aad_keep  = 16'hffff;
        aad_valid = 1;
        wait(aad_ready);
        #10;
        aad_valid = 0;

        // ------------------------
        // Step 4: Payload input (4 x 128-bit)
        // ------------------------
        step = STEP_PAYLOAD;
        for (pld_idx = 0; pld_idx < 4; pld_idx = pld_idx + 1) begin
            pld_data  = payload[pld_idx];
            pld_keep  = 16'hffff;
            pld_valid = 1;
            wait(pld_ready);
            #10;
            pld_valid = 0;
        end

        // ------------------------
        // Step 5: LENGTH block
        // ------------------------
        step = STEP_LENGTH;
        len_block = 128'h00000000_00000010_00000000_00000040; // 16 bytes AAD + 64 bytes payload
        len_valid = 1;
        wait(len_ready);
        #10;
        len_valid = 0;

        // ------------------------
        // Step 6: Wait for TAG
        // ------------------------
        step = STEP_TAG;
        wait(tag_pre_xor_valid);

        // ------------------------
        // Step 7: Done
        // ------------------------
        step = STEP_DONE;
        wait(aad_done & pld_done & lens_done);
        $display("[%0t] All steps done.", $time);

        #50;
        $finish;
    end

    // ------------------------
    // Cycle-by-cycle monitor
    // ------------------------
    always @(posedge clk) begin
        case(step)
            STEP_CFG: begin
                if(cfg_we) $display("[%0t][Cycle %0d] STEP: CONFIG write active", $time, cycle_count);
            end
            STEP_KEYSTREAM: begin
                $display("[%0t][Cycle %0d] STEP: KEYSTREAM request, ks_valid=%b", $time, cycle_count, ks_valid);
                if(ks_valid) $display("Keystream data: %h", ks_data);
            end
            STEP_AAD: begin
                $display("[%0t][Cycle %0d] STEP: AAD input, valid=%b, ready=%b, data=%h", 
                         $time, cycle_count, aad_valid, aad_ready, aad_data);
            end
            STEP_PAYLOAD: begin
                $display("[%0t][Cycle %0d] STEP: PAYLOAD input, valid=%b, ready=%b, data=%h", 
                         $time, cycle_count, pld_valid, pld_ready, pld_data);
            end
            STEP_LENGTH: begin
                $display("[%0t][Cycle %0d] STEP: LENGTH block, valid=%b, ready=%b, data=%h", 
                         $time, cycle_count, len_valid, len_ready, len_block);
            end
            STEP_TAG: begin
                if(tag_pre_xor_valid) $display("[%0t][Cycle %0d] STEP: TAG ready, tag=%h, mask=%h", 
                                               $time, cycle_count, tag_pre_xor, tagmask);
            end
            STEP_DONE: begin
                if(aad_done & pld_done & lens_done)
                    $display("[%0t][Cycle %0d] STEP: DONE signals asserted", $time, cycle_count);
            end
        endcase
    end

endmodule
`default_nettype wire
