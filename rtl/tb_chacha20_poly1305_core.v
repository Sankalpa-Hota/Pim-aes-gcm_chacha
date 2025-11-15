`timescale 1ns/1ps
`default_nettype none

module tb_chacha20_poly1305_core_enhanced;

    reg clk, rst_n;
    reg [255:0] key;
    reg [95:0] nonce;
    reg [31:0] ctr_init;
    reg cfg_we, ks_req;
    reg aad_valid; reg [127:0] aad_data; reg [15:0] aad_keep;
    reg pld_valid; reg [127:0] pld_data; reg [15:0] pld_keep;
    reg len_valid; reg [127:0] len_block;
    reg algo_sel;

    wire ks_valid; wire [511:0] ks_data;
    wire aad_ready; wire pld_ready; wire len_ready;
    wire [127:0] tag_pre_xor; wire tag_pre_xor_valid;
    wire [127:0] tagmask; wire tagmask_valid;
    wire aad_done; wire pld_done; wire lens_done;

    integer cycle_counter;

    // DUT
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

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Cycle counter
    initial cycle_counter = 0;
    always @(posedge clk) cycle_counter = cycle_counter + 1;

    // Testbench procedure
    initial begin
        rst_n = 0; cfg_we = 0; ks_req = 0; algo_sel = 1;
        key = 256'h0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef;
        nonce = 96'habcdef1234567890abcdef12;
        ctr_init = 32'h0;
        aad_valid=0; aad_data=0; aad_keep=0;
        pld_valid=0; pld_data=0; pld_keep=0;
        len_valid=0; len_block=0;

        #20 rst_n = 1;

        // Configure keys
        @(posedge clk); cfg_we = 1;
        @(posedge clk); cfg_we = 0;

        // Request one keystream block
        @(posedge clk); ks_req = 1;
        @(posedge clk); ks_req = 0;

        // --- Feed 5 AAD blocks ---
        integer i;
        for (i=0; i<5; i=i+1) begin
            @(posedge clk);
            while (!aad_ready) @(posedge clk);
            aad_valid <= 1;
            aad_data <= $random;
            aad_keep <= 16'hFFFF;
            @(posedge clk);
            aad_valid <= 0;

            // Wait for done signal per AAD
            while (!aad_done) @(posedge clk);
            $display("[Cycle %0d] AAD block %0d processed: data=%h", cycle_counter, i, aad_data);
        end

        // --- Feed 5 Payload blocks ---
        for (i=0; i<5; i=i+1) begin
            @(posedge clk);
            while (!pld_ready) @(posedge clk);
            pld_valid <= 1;
            pld_data <= $random;
            pld_keep <= 16'hFFFF;
            @(posedge clk);
            pld_valid <= 0;

            // Wait for done signal per payload
            while (!pld_done) @(posedge clk);
            $display("[Cycle %0d] Payload block %0d processed: data=%h", cycle_counter, i, pld_data);
        end

        // --- Feed 1 LEN block ---
        @(posedge clk);
        while (!len_ready) @(posedge clk);
        len_valid <= 1;
        len_block <= 128'h00000000000000000000000000000100;
        @(posedge clk); len_valid <= 0;

        while (!lens_done) @(posedge clk);
        $display("[Cycle %0d] LEN block processed: data=%h", cycle_counter, len_block);

        // Wait for tag outputs
        wait(tag_pre_xor_valid && tagmask_valid);
        $display("Final Tag Pre-XOR: %h", tag_pre_xor);
        $display("Final Tagmask: %h", tagmask);

        $finish;
    end

    // Monitor keystream, data_in, encrypted
    always @(posedge clk) begin
        if(ks_valid) begin
            $display("[Cycle %0d] Keystream block: %h", cycle_counter, ks_data);
        end
    end

endmodule
`default_nettype wire
