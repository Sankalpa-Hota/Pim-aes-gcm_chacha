`default_nettype none
// aes_gcm_top_chacha.v
// Updated top-level to support ChaCha20-Poly1305 via algo_sel
// Synthesizable, minimal changes. AES path unchanged.

module aes_gcm_top_chacha (
    input  wire         clk, rst_n,
    // AAD stream in
    input  wire         aad_valid, input  wire aad_last, output wire aad_ready,
    input  wire [127:0] aad_data,  input  wire [15:0] aad_keep,
    // Payload in
    input  wire         din_valid, input  wire din_last, output wire din_ready,
    input  wire [127:0] din_data,  input  wire [15:0] din_keep,
    // Payload out
    output wire         dout_valid, output wire dout_last, input  wire dout_ready,
    output wire [127:0] dout_data,  output wire [15:0] dout_keep,
    // CSRs (simplified for bring-up)
    input  wire [255:0] key_in,   input  wire key_we, input wire aes256_en,
    input  wire [95:0]  iv_in,    input  wire iv_we,
    input  wire [63:0]  len_aad_bits, len_pld_bits,
    input  wire         start,    input  wire enc_mode, input wire framed_mode,
    input  wire [127:0] tag_in,   input  wire tag_in_we,
    output wire [127:0] tag_out,  output wire tag_out_valid,
    output wire         auth_fail,
    input  wire         algo_sel   // 0 = AES-GCM, 1 = ChaCha20-Poly1305
);

    // ----------------------------------------------------------------
    // Internal wires for datapath connection
    // ----------------------------------------------------------------
    wire [127:0] tag_pre_xor_w;
    wire         tag_pre_xor_valid_w;
    wire [127:0] tagmask_w;
    wire         tagmask_valid_w;
    wire         aad_done_w, pld_done_w, lens_done_w;

    // ----------------------------------------------------------------
    // Mux between AES/GCM datapath and ChaCha20-Poly1305 core
    // ----------------------------------------------------------------
    // Using generate block to safely select which datapath is active
    wire ks_ready_dummy; // placeholder for ks_ready if needed

    // AES path (original) - only active if algo_sel = 0
    wire aes_active = (algo_sel == 1'b0);
    wire chacha_active = (algo_sel == 1'b1);

    // ------------------- AES Datapath -----------------------------
    aes_gcm_datapath u_aes_datapath (
        .clk           (clk),
        .rst_n         (rst_n),
        .key_in        (key_in),
        .key_we        (key_we),
        .aes256_en     (aes256_en),
        .iv_in         (iv_in),
        .iv_we         (iv_we),
        .len_aad_bits  (len_aad_bits),
        .len_pld_bits  (len_pld_bits),
        .start         (start & aes_active),
        .enc_mode      (enc_mode),
        .algo_sel      (algo_sel),   // keep for internal muxing

        // AAD
        .aad_valid     (aad_valid & aes_active),
        .aad_ready     (aad_ready),
        .aad_last      (aad_last),
        .aad_data      (aad_data),
        .aad_keep      (aad_keep),
        // Payload in/out
        .din_valid     (din_valid & aes_active),
        .din_ready     (din_ready),
        .din_last      (din_last),
        .din_data      (din_data),
        .din_keep      (din_keep),
        .dout_valid    (dout_valid),
        .dout_ready    (dout_ready),
        .dout_last     (dout_last),
        .dout_data     (dout_data),
        .dout_keep     (dout_keep),
        // Tag components
        .tag_pre_xor        (tag_pre_xor_w),
        .tag_pre_xor_valid  (tag_pre_xor_valid_w),
        .tagmask            (tagmask_w),
        .tagmask_valid      (tagmask_valid_w),
        .aad_done           (aad_done_w),
        .pld_done           (pld_done_w),
        .lens_done          (lens_done_w)
    );

    // ------------------- ChaCha20-Poly1305 Datapath ----------------
    chacha20_poly1305_core u_chacha_core (
        .clk(clk),
        .rst_n(rst_n),
        .key(key_in),
        .nonce(iv_in),
        .ctr_init(32'h0),        // always 0 for Poly1305
        .cfg_we(start & chacha_active),

        .ks_req(start & chacha_active), // request first block at start
        .ks_valid(), .ks_data(),        // internal keystream not exposed

        // Streams
        .aad_valid(aad_valid & chacha_active),
        .aad_data(aad_data),
        .aad_keep(aad_keep),
        .aad_ready(aad_ready),

        .pld_valid(din_valid & chacha_active),
        .pld_data(din_data),
        .pld_keep(din_keep),
        .pld_ready(din_ready),

        .len_valid(1'b1 & chacha_active),             // always ready
        .len_block({len_aad_bits, len_pld_bits}),
        .len_ready(),

        .tag_pre_xor(tag_pre_xor_w),
        .tag_pre_xor_valid(tag_pre_xor_valid_w),
        .tagmask(tagmask_w),
        .tagmask_valid(tagmask_valid_w)
    );

    // ------------------- Controller -----------------------------
    aes_gcm_ctrl u_ctrl (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (start),
        .enc_mode       (enc_mode),
        .len_aad_bits   (len_aad_bits),
        .len_pld_bits   (len_pld_bits),
        .iv_we          (iv_we),
        // AAD handshake
        .aad_valid      (aad_valid),
        .aad_ready      (aad_ready),
        .aad_last       (aad_last),
        .aad_keep       (aad_keep),
        // Payload handshakes
        .din_valid      (din_valid),
        .din_ready      (din_ready),
        .din_last       (din_last),
        .din_keep       (din_keep),
        .dout_valid     (dout_valid),
        .dout_ready     (dout_ready),
        .dout_last      (dout_last),
        .dout_keep      (dout_keep),
        // Framing / ext tag input
        .tag_in         (tag_in),
        .tag_in_we      (tag_in_we),
        // From datapath (muxed for AES/ChaCha)
        .tag_pre_xor        (tag_pre_xor_w),
        .tag_pre_xor_valid  (tag_pre_xor_valid_w),
        .tagmask            (tagmask_w),
        .tagmask_valid      (tagmask_valid_w),
        .aad_done           (aad_done_w),
        .pld_done           (pld_done_w),
        .lens_done          (lens_done_w),
        // Control outputs (not consumed at this top level)
        .ctr_load_iv    (/* unused */),
        .ghash_init     (/* unused */),
        .tagmask_start  (/* unused */),
        .phase          (/* unused */),
        // Outputs to top
        .tag_out        (tag_out),
        .tag_out_valid  (tag_out_valid),
        .auth_fail      (auth_fail)
    );

endmodule

`default_nettype wire
