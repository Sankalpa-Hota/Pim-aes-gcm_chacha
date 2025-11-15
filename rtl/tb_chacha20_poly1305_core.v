`timescale 1ns/1ps

module tb_chacha20_poly1305_core;

    reg clk, rst;
    reg cs, we;
    reg [7:0] addr;
    reg [511:0] wdata;
    wire [511:0] rdata;

    integer cycles;
    integer last_progress_cycle;

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    // DUT
    chacha20_poly1305_bus dut(
        .clk(clk),
        .rst(rst),
        .cs(cs),
        .we(we),
        .addr(addr),
        .wdata(wdata),
        .rdata(rdata)
    );


    // ================================
    // Reset + Initialization
    // ================================
    initial begin
        cycles = 0;
        last_progress_cycle = 0;

        rst = 1;
        cs = 0;
        we = 0;
        addr = 0;
        wdata = 0;

        repeat(10) @(posedge clk);
        rst = 0;
        repeat(10) @(posedge clk);

        $display("[TB] Starting ChaCha20-Poly1305 test...");
        
        send_aad(128'hdeadbeef0123456789abcdef00112233);
        send_payload(128'h11111111222222223333333344444444);
    end


    // ================================
    // Global cycle counter + timeout
    // ================================
    always @(posedge clk) begin
        cycles <= cycles + 1;

        // Every 5000 cycles dump heartbeat
        if (cycles % 5000 == 0) begin
            $display("\n--- HEARTBEAT cycle=%0d ---", cycles);
            dump_state();
            $display("---------------------------------\n");
        end

        // Hard timeout
        if (cycles > 2_000_000) begin
            $display("[TB] TIMEOUT at cycle=%0d", cycles);
            dump_state();
            $finish;
        end
    end


    // ================================
    // TASK: Send AAD block
    // ================================
    task send_aad(input [127:0] aad);
        begin
            @(posedge clk);
            $display("[TB] Sending AAD: %h", aad);

            cs = 1;
            we = 1;
            addr = 8'h10;    // example AAD address
            wdata = {384'd0, aad};
            last_progress_cycle = cycles;

            @(posedge clk);
            cs = 0; we = 0;

            wait_for_progress("AAD");
        end
    endtask


    // ================================
    // TASK: Send Payload
    // ================================
    task send_payload(input [127:0] p);
        begin
            @(posedge clk);
            $display("[TB] Sending Payload block: %h", p);

            cs = 1;
            we = 1;
            addr = 8'h20;   // example payload address
            wdata = {384'd0, p};
            last_progress_cycle = cycles;

            @(posedge clk);
            cs = 0; we = 0;

            wait_for_progress("PAYLOAD");
        end
    endtask



    // ================================
    // TASK: Wait for progress
    // ================================
    task wait_for_progress(input [32*8-1:0] name);
        begin
            fork
                begin : timeout_block
                    repeat(20000) @(posedge clk);
                    $display("[TB][ERROR] %s processing STUCK for 20000 cycles!", name);
                    dump_state();
                    disable wait_block;
                end

                begin : wait_block
                    wait (dut.core_inst.ks_valid || dut.core_inst.tag_valid);
                    $display("[TB] %s processed OK at cycle %0d", name, cycles);
                    disable timeout_block;
                end
            join
        end
    endtask


    // ================================
    // Dump internal DUT state
    // ================================
    task dump_state;
        begin
            $display("DUT STATE DUMP @ cycle=%0d", cycles);

            $display("ChaCha core:");
            $display("  ready        = %b", dut.core_inst.ready);
            $display("  ks_valid     = %b", dut.core_inst.ks_valid);
            $display("  ks_data[...] = %h", dut.core_inst.ks_data[511:480]);

            $display("Poly1305 adapter:");
            $display("  aad_busy     = %b", dut.core_inst.poly_adapter.aad_busy);
            $display("  msg_busy     = %b", dut.core_inst.poly_adapter.msg_busy);
            $display("  tag_pre_xor_valid = %b", dut.core_inst.poly_adapter.tag_pre_xor_valid);

            $display("Multiplier:");
            $display("  mult_busy    = %b", dut.core_inst.poly_adapter.mul_inst.busy);
            $display("  mult_valid   = %b", dut.core_inst.poly_adapter.mul_inst.valid);

            $display("Reducer:");
            $display("  red_busy     = %b", dut.core_inst.poly_adapter.red_inst.busy);
            $display("  red_valid    = %b", dut.core_inst.poly_adapter.red_inst.valid);

            $display("Tag unit:");
            $display("  tag_valid    = %b", dut.core_inst.tag_valid);
            $display("  tag_output   = %h", dut.core_inst.tag_output);

        end
    endtask

endmodule
