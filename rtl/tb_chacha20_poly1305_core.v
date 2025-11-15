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

    // Dummy keystream counter for simulation
    reg [511:0] ks_counter;
    assign ks_valid = ks_req;
    assign ks_data = ks_counter;

    // DUT instantiation
    chacha_poly1305_adapter dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(cfg_we),
        .algo_sel(algo_sel),
        .key(key),
        .nonce(nonce),
        .ctr_init(ctr_init),
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
        .lens_done(lens_done)
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
    integer cycle;
    initial cycle = 0;
    always @(posedge clk) cycle = cycle + 1;

    // Keystream counter
    always @(posedge clk) if (ks_req) ks_counter <= ks_counter + 1;

    // Test procedure
    initial begin
        rst_n = 0; cfg_we = 0; ks_req = 0; algo_sel = 1;
        key = 256'h0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef;
        nonce = 96'habcdef1234567890abcdef12;
        ctr_init = 32'h0;
        aad_valid = 0; aad_data = 0; aad_keep = 0;
        pld_valid = 0; pld_data = 0; pld_keep = 0;
        len_valid = 0; len_block = 0;

        #20 rst_n = 1;  // Release reset

        @(posedge clk); cfg_we = 1;
        @(posedge clk); cfg_we = 0;

        @(posedge clk); ks_req = 1;
        @(posedge clk); ks_req = 0;

        // Feed AAD
        while(!aad_done) begin
            @(posedge clk);
            if(aad_ready) begin
                aad_valid <= 1;
                aad_data <= $random;
                aad_keep <= 16'hFFFF;
            end else begin
                aad_valid <= 0;
            end
        end
        aad_valid <= 0;

        // Feed Payload
        while(!pld_done) begin
            @(posedge clk);
            if(pld_ready) begin
                pld_valid <= 1;
                pld_data <= $random;
                pld_keep <= 16'hFFFF;
            end else begin
                pld_valid <= 0;
            end
        end
        pld_valid <= 0;

        // Feed LEN block
        while(!lens_done) begin
            @(posedge clk);
            if(len_ready) begin
                len_valid <= 1;
                len_block <= 128'h00000000000000000000000000000100;
            end else begin
                len_valid <= 0;
            end
        end
        len_valid <= 0;

        // Wait for tag outputs
        wait(tag_pre_xor_valid && tagmask_valid);
        $display("Final Tag Pre-XOR: %h", tag_pre_xor);
        $display("Final Tagmask: %h", tagmask);

        #50 $finish;
    end

    // Cycle monitor
    always @(posedge clk) begin
        $display("Cycle: %0d | ks_valid: %b | aad_ready: %b | pld_ready: %b | len_ready: %b | aad_done: %b | pld_done: %b | lens_done: %b",
                 cycle, ks_valid, aad_ready, pld_ready, len_ready, aad_done, pld_done, lens_done);
        if(ks_valid) $display("   ks_data[127:0]: %h ...", ks_data[127:0]);
    end

endmodule

