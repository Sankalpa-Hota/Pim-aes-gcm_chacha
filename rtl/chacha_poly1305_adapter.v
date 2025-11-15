`timescale 1ns/1ps
`default_nettype none

// ChaCha20-Poly1305 adapter (A1 flow: single AAD block -> N payload blocks -> single LEN block)
// Proper registered handshake and pipelining: accumulator update is applied, then multiplier is started
// on the following cycle so the multiplier always sees the updated accumulator.
module chacha_poly1305_adapter (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,       // start flow (from cfg write)
    input  wire         algo_sel,
    input  wire [255:0] key,
    input  wire [95:0]  nonce,
    input  wire [31:0]  ctr_init,

    // AAD path (one or more 128-bit blocks allowed; A1 testbench sends 1)
    input  wire         aad_valid,
    input  wire [127:0] aad_data,
    input  wire [15:0]  aad_keep,
    output reg          aad_ready,

    // Payload path (multiple 128-bit blocks)
    input  wire         pld_valid,
    input  wire [127:0] pld_data,
    input  wire [15:0]  pld_keep,
    output reg          pld_ready,

    // Length block (single 128-bit)
    input  wire         len_valid,
    input  wire [127:0] len_block,
    output reg          len_ready,

    // Outputs
    output reg  [127:0] tag_pre_xor,
    output reg          tag_pre_xor_valid,
    output reg  [127:0] tagmask,
    output reg          tagmask_valid,

    // Done signals
    output reg          aad_done,
    output reg          pld_done,
    output reg          lens_done
);

    // States (A1 flow)
    localparam IDLE   = 4'd0;
    localparam AAD    = 4'd1;
    localparam MUL_WAIT = 4'd2;  // after accepting block, wait one cycle to start mult
    localparam MUL    = 4'd3;    // multiplier running
    localparam REDUCE_WAIT = 4'd4; // after mul_done, start reducer next cycle
    localparam REDUCE = 4'd5;
    localparam PAYLD  = 4'd6;
    localparam LEN    = 4'd7;
    localparam FINAL  = 4'd8;
    localparam DONE   = 4'd9;

    localparam ST_AAD   = 3'd0;
    localparam ST_PAYLD = 3'd1;
    localparam ST_LEN   = 3'd2;

    reg [3:0] state, next_state;
    reg [2:0] prev_stage;

    // accumulator: 130 bits used in lower bits, we store full 258 to allow adds
    reg [257:0] acc;
    reg [257:0] acc_next;        // temp after adding block
    reg         acc_next_valid;

    // captured block (129 bits: 1||data)
    reg [129:0] block_reg;
    reg         block_reg_valid;

    // keys
    reg [127:0] r_key, s_key;

    // registered pulses to mult/reduce
    reg start_mul_r;   // pulse asserted for one cycle to multiplier
    reg start_reduce_r;

    // wires from submodules
    wire [257:0] mul_out;
    wire         mul_done;
    wire [129:0] reduce_out;
    wire         reduce_done;

    // instantiate multiplier & reducer (done pulses 1 cycle)
    mult_130x128_limb mul_unit(
        .clk(clk), .reset_n(rst_n),
        .start(start_mul_r),
        .a_in(acc[129:0]),
        .b_in(r_key),
        .product_out(mul_out),
        .busy(),
        .done(mul_done)
    );

    reduce_mod_poly1305 reduce_unit(
        .clk(clk), .reset_n(rst_n),
        .start(start_reduce_r),
        .value_in(mul_out),
        .value_out(reduce_out),
        .busy(),
        .done(reduce_done)
    );

    // Sequential: registers, pulses, accumulator updates
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            acc <= 258'b0;
            acc_next <= 258'b0;
            acc_next_valid <= 1'b0;
            block_reg <= 130'b0;
            block_reg_valid <= 1'b0;
            r_key <= 128'b0;
            s_key <= 128'b0;
            start_mul_r <= 1'b0;
            start_reduce_r <= 1'b0;
            tag_pre_xor <= 128'b0;
            tag_pre_xor_valid <= 1'b0;
            tagmask <= 128'b0;
            tagmask_valid <= 1'b0;
            aad_ready <= 1'b0;
            pld_ready <= 1'b0;
            len_ready <= 1'b0;
            aad_done <= 1'b0;
            pld_done <= 1'b0;
            lens_done <= 1'b0;
            prev_stage <= ST_AAD;
        end else begin
            // clear single-cycle pulses / outputs by default
            start_mul_r <= 1'b0;
            start_reduce_r <= 1'b0;
            tag_pre_xor_valid <= 1'b0;
            tagmask_valid <= 1'b0;
            aad_done <= 1'b0;
            pld_done <= 1'b0;
            lens_done <= 1'b0;

            // update state
            state <= next_state;

            // On IDLE + start: latch keys and clear accumulator
            if (state == IDLE && start && algo_sel) begin
                r_key <= key[127:0];
                s_key <= key[255:128];
                acc <= 258'b0;
                acc_next <= 258'b0;
                acc_next_valid <= 1'b0;
                block_reg_valid <= 1'b0;
            end

            // Accept block (AAD)
            if (state == AAD) begin
                aad_ready <= 1'b1;
                if (aad_valid && !block_reg_valid) begin
                    // capture block encoding: append 1 bit per Poly1305 spec
                    block_reg <= {1'b1, aad_data}; // 129 bits -> stored in 130 bits
                    block_reg_valid <= 1'b1;
                    // create acc_next (acc + block) — do not overwrite acc yet
                    acc_next <= acc + {128'b0, block_reg[129:0]}; // careful: block_reg will be used next cycle
                    acc_next_valid <= 1'b1;
                    prev_stage <= ST_AAD;
                end
            end else begin
                aad_ready <= 1'b0;
            end

            // Accept block (PAYLOAD)
            if (state == PAYLD) begin
                pld_ready <= 1'b1;
                if (pld_valid && !block_reg_valid) begin
                    block_reg <= {1'b1, pld_data};
                    block_reg_valid <= 1'b1;
                    acc_next <= acc + {128'b0, block_reg[129:0]};
                    acc_next_valid <= 1'b1;
                    prev_stage <= ST_PAYLD;
                end
            end else begin
                pld_ready <= 1'b0;
            end

            // Accept block (LEN)
            if (state == LEN) begin
                len_ready <= 1'b1;
                if (len_valid && !block_reg_valid) begin
                    block_reg <= {1'b1, len_block};
                    block_reg_valid <= 1'b1;
                    acc_next <= acc + {128'b0, block_reg[129:0]};
                    acc_next_valid <= 1'b1;
                    prev_stage <= ST_LEN;
                end
            end else begin
                len_ready <= 1'b0;
            end

            // MUL_WAIT: when acc_next_valid was produced in previous cycle, update acc and start multiplier
            if (state == MUL_WAIT) begin
                if (acc_next_valid) begin
                    acc <= acc_next;           // apply the add result
                    acc_next_valid <= 1'b0;
                    block_reg_valid <= 1'b0;  // block consumed
                    // pulse multiplier start (registered single-cycle)
                    start_mul_r <= 1'b1;
                end
            end

            // MUL: wait for mul_done; nothing to do here except hold busy until done
            if (state == MUL) begin
                // nothing — mul_done will be observed combinationally in next_state logic,
                // but we don't create pulses here.
            end

            // REDUCE_WAIT: when mul_done observed, start reducer next cycle
            if (state == REDUCE_WAIT) begin
                // pulse reducer start
                start_reduce_r <= 1'b1;
            end

            // REDUCE: when reduce_done, latch reduced result into acc and assert done-pulse for stage
            if (state == REDUCE) begin
                if (reduce_done) begin
                    acc[129:0] <= reduce_out; // update lower 130 bits from reducer
                    // assert done pulse for the sub-stage
                    case (prev_stage)
                        ST_AAD: begin aad_done <= 1'b1; end
                        ST_PAYLD: begin pld_done <= 1'b1; end
                        ST_LEN: begin lens_done <= 1'b1; end
                    endcase
                end
            end

            // FINAL: produce tag (registered)
            if (state == FINAL) begin
                tag_pre_xor <= acc[127:0] + s_key;
                tag_pre_xor_valid <= 1'b1;
                tagmask <= {r_key, 32'h0};
                tagmask_valid <= 1'b1;
            end
        end
    end

    // Combinational next-state logic (observes mul_done/reduce_done)
    always @* begin
        next_state = state;

        case (state)
            IDLE: begin
                if (start && algo_sel) next_state = AAD;
            end

            AAD: begin
                // wait until block is captured; then go to MUL_WAIT for pipeline
                if (block_reg_valid) next_state = MUL_WAIT;
            end

            MUL_WAIT: begin
                // when we asserted start_mul_r (in sequential block) the multiplier will begin
                // transit to MUL to wait for mul_done
                next_state = MUL;
            end

            MUL: begin
                if (mul_done) next_state = REDUCE_WAIT;
            end

            REDUCE_WAIT: begin
                next_state = REDUCE;
            end

            REDUCE: begin
                if (reduce_done) begin
                    // after reduce, choose next stage based on prev_stage
                    if (prev_stage == ST_AAD) next_state = PAYLD;
                    else if (prev_stage == ST_PAYLD) next_state = PAYLD; // stay in PAYLD to accept more blocks
                    else if (prev_stage == ST_LEN) next_state = FINAL;
                    else next_state = IDLE;
                end
            end

            PAYLD: begin
                // Accept multiple payload blocks: once block_reg_valid moves to MUL_WAIT flow will continue
                // Transition to LEN if testbench asserts len_valid while not accepting payload
                if (block_reg_valid) next_state = MUL_WAIT;
                else if (len_valid) next_state = LEN; // allow early switch if TB sets len_valid
            end

            LEN: begin
                if (block_reg_valid) next_state = MUL_WAIT;
            end

            FINAL: begin
                next_state = DONE;
            end

            DONE: begin
                next_state = DONE;
            end

            default: next_state = IDLE;
        endcase
    end

endmodule

`default_nettype wire
