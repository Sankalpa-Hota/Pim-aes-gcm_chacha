`default_nettype none
// chacha_keystream_unit.v
// Produces one 512-bit ChaCha block on request (ks_req). Minimal changes from Original

module chacha_keystream_unit (
    input  wire         clk,
    input  wire         rst_n,

    // Configuration (driven by AES-GCM regs in ChaCha mode)
    input  wire [255:0] chacha_key,
    input  wire [95:0]  chacha_nonce,
    input  wire [31:0]  chacha_ctr_init,
    input  wire         cfg_we,        // latch key/nonce/counter

    // Unified keystream interface for ctr_xor
    input  wire         ks_req,
    output reg          ks_valid,
    output reg  [511:0] ks_data      // CHACHA-MOD: wider to 512 bits
);

    // --------------------------------------------------------------------
    // Config registers
    // --------------------------------------------------------------------
    reg [255:0] key_reg;
    reg [95:0]  nonce_reg;
    reg [31:0]  ctr_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_reg   <= 256'h0;
            nonce_reg <= 96'h0;
            ctr_reg   <= 32'h0;
        end else if (cfg_we) begin
            key_reg   <= chacha_key;
            nonce_reg <= chacha_nonce;
            ctr_reg   <= chacha_ctr_init;
        end
    end

    // --------------------------------------------------------------------
    // Wires to chacha_core (uses your chacha_core)
    // --------------------------------------------------------------------
    wire        core_ready;
    wire        core_data_valid;
    wire [511:0] core_data_out;

    reg         core_init_reg, core_next_reg;
    reg  [31:0] ctr_next;

    // Map nonce + counter into ctr64/iv64 like your chacha_core expects
    wire [63:0] ctr64 = {nonce_reg[31:0], ctr_reg};
    wire [63:0] iv64  = nonce_reg[95:32];

    chacha_core u_chacha_core (
        .clk          (clk),
        .reset_n      (rst_n),
        .init         (core_init_reg),
        .next         (core_next_reg),
        .key          (key_reg),
        .ctr          (ctr64),
        .iv           (iv64),
        .data_in      (512'h0),
        .ready        (core_ready),
        .data_out     (core_data_out),
        .data_out_valid(core_data_valid)
    );

    // --------------------------------------------------------------------
    // Simple FSM: produce one 512-bit block per ks_req
    // --------------------------------------------------------------------
    localparam S_IDLE  = 2'd0;
    localparam S_WAIT  = 2'd1;
    localparam S_OUT   = 2'd2;

    reg [1:0] state_reg, state_next;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg     <= S_IDLE;
            core_init_reg <= 1'b0;
            core_next_reg <= 1'b0;
            ctr_reg       <= 32'h0;
        end else begin
            state_reg     <= state_next;
            core_init_reg <= 1'b0;
            core_next_reg <= 1'b0;
            ctr_reg       <= ctr_next;
        end
    end

    always @* begin
        state_next = state_reg;
        ctr_next   = ctr_reg;

        ks_valid   = 1'b0;
        ks_data    = 512'h0;

        case (state_reg)
            S_IDLE: begin
                // Accept a keystream request when core is ready
                if (ks_req && core_ready) begin
                    // request a new block
                    core_next_reg = 1'b1;
                    state_next    = S_WAIT;
                end
            end

            S_WAIT: begin
                if (core_data_valid) begin
                    // Grab entire 512-bit ChaCha output
                    ks_data    = core_data_out;
                    ks_valid   = 1'b1;
                    // Bump counter for next block
                    ctr_next   = ctr_reg + 1;
                    state_next = S_OUT;
                end
            end

            S_OUT: begin
                // One-cycle ks_valid, then go back to IDLE
                state_next = S_IDLE;
            end

            default: state_next = S_IDLE;
        endcase
    end

endmodule

`default_nettype wire


`default_nettype wire
