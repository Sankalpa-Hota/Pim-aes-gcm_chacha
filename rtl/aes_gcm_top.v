`default_nettype none
// aes_gcm_top_chacha.v
// Updated top-level to support ChaCha20-Poly1305 via algo_sel
// Synthesizable, minimal changes. AES path unchanged.
`default_nettype none
module aes_gcm_top_chacha (
    input  wire         clk, rst_n,
    // configuration
    input  wire [255:0] key,
    input  wire [95:0]  nonce,
    input  wire [31:0]  ctr_init,
    input  wire         cfg_we,

    // keystream request/response
    input  wire         ks_req,
    output wire         ks_valid,
    output wire [511:0] ks_data, // unified 512-bit width

    // AAD stream
    input  wire         aad_valid,
    input  wire [127:0] aad_data,
    input  wire [15:0]  aad_keep,
    output wire         aad_ready,

    // payload stream
    input  wire         pld_valid,
    input  wire [127:0] pld_data,
    input  wire [15:0]  pld_keep,
    output wire         pld_ready,

    // lengths block
    input  wire         len_valid,
    input  wire [127:0] len_block,
    output wire         len_ready,

    // tag outputs
    output wire [127:0] tag_pre_xor,
    output wire         tag_pre_xor_valid,
    output wire [127:0] tagmask,
    output wire         tagmask_valid,

    // done signals
    output wire         aad_done,
    output wire         pld_done,
    output wire         lens_done,

    input  wire         algo_sel  // 0=AES, 1=ChaCha
);

    // -------------------------------------------------
    // Internal signals
    // -------------------------------------------------
    wire        ks_valid_aes;
    wire [127:0] ks_data_aes;

    wire        ks_valid_chacha;
    wire [511:0] ks_data_chacha;

    // Done signals
    reg aad_done_reg, pld_done_reg, lens_done_reg;

    // -------------------------------------------------
    // AES-GCM datapath (unchanged)
    // -------------------------------------------------
    aes_gcm_datapath u_aes (
        .clk(clk), .rst_n(rst_n),
        .key(key[127:0]),  // AES128 subset for example
        .nonce(nonce),
        .ctr_init(ctr_init),
        .cfg_we(cfg_we),
        .ks_req(ks_req),
        .ks_valid(ks_valid_aes),
        .ks_data(ks_data_aes),
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
        .aad_done(aad_done_reg),
        .pld_done(pld_done_reg),
        .lens_done(lens_done_reg)
    );

    // -------------------------------------------------
    // ChaCha20 keystream unit
    // -------------------------------------------------
    chacha_keystream_unit u_chacha (
        .clk(clk), .rst_n(rst_n),
        .chacha_key(key), 
        .chacha_nonce(nonce), 
        .chacha_ctr_init(ctr_init), 
        .cfg_we(cfg_we),
        .ks_req(ks_req),
        .ks_valid(ks_valid_chacha),   // output valid
        .ks_data(ks_data_chacha)      // output 512-bit
    );

    // -------------------------------------------------
    // Poly1305 adapter for ChaCha
    // -------------------------------------------------
    chacha_poly1305_adapter u_poly (
        .clk(clk), .rst_n(rst_n),
        .start(cfg_we),
        .algo_sel(algo_sel),
        .key(key), .nonce(nonce), .ctr_init(ctr_init),
        .aad_valid(aad_valid), .aad_data(aad_data), .aad_keep(aad_keep), .aad_ready(aad_ready),
        .pld_valid(pld_valid), .pld_data(pld_data), .pld_keep(pld_keep), .pld_ready(pld_ready),
        .len_valid(len_valid), .len_block(len_block), .len_ready(len_ready),
        .tag_pre_xor(tag_pre_xor), .tag_pre_xor_valid(tag_pre_xor_valid),
        .tagmask(tagmask), .tagmask_valid(tagmask_valid),
        .aad_done(aad_done_reg), .pld_done(pld_done_reg), .lens_done(lens_done_reg)
    );

    // -------------------------------------------------
    // Connect done signals
    // -------------------------------------------------
    assign aad_done  = aad_done_reg;
    assign pld_done  = pld_done_reg;
    assign lens_done = lens_done_reg;

    // -------------------------------------------------
    // Keystream mux
    // -------------------------------------------------
    // Minimal changes: select between AES/ChaCha without altering existing functionality
    assign ks_valid = algo_sel ? ks_valid_chacha : ks_valid_aes;
    assign ks_data  = algo_sel ? ks_data_chacha  : {384'h0, ks_data_aes}; 
    // AES data zero-extended to 512-bit to match ChaCha output

endmodule

`default_nettype wire
