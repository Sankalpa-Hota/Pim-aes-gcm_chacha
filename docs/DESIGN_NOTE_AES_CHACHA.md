# AES–ChaCha Keystream Merge Design Note

---

## What this change is

This change extends the original **PIM AES-GCM** engine so that the **CTR XOR datapath** can draw keystream from:

- the existing **AES-CTR** path, or  
- a new **ChaCha-based keystream unit**,

selected by a single **algorithm-select CSR**.

- `algo_sel = 0` → AES-GCM mode (original behavior)  
- `algo_sel = 1` → CTR keystream comes from ChaCha (first step toward ChaCha20-Poly1305)

AES-GCM GHASH / tag logic is left unchanged in this revision.

---

## Files touched

- `rtl/aes_gcm_top.v`
- `rtl/aes_gcm_datapath.v`
- `rtl/chacha_keystream_unit.v` (new)
- `syn/genus_compile_gcm.tcl` (flow-related changes, if any)
- `docs/DESIGN_NOTE_AES_CHACHA.md` (this document)

---

## 1. Top-level control: `aes_gcm_top.v`

### What changed

- Added a **1-bit algorithm-select CSR input**:
  - `algo_sel`
    - `0` = AES-GCM keystream (original)
    - `1` = ChaCha-based keystream

- Passed `algo_sel` down into `aes_gcm_datapath`.

### Why

- Gives the host / SSD controller a single bit to choose the keystream algorithm.
- Keeps the external interface almost unchanged (one extra CSR bit).
- Concentrates algorithm choice at the top level while leaving the detailed muxing in the datapath.

---

## 2. Datapath keystream interface: `aes_gcm_datapath.v`

### What changed

1. Introduced a **generic keystream interface** between `ctr_xor` and the keystream generator:

   - `ks_req`   – request a new 128-bit keystream block  
   - `ks_valid` – producer indicates `ks_data` is valid  
   - `ks_data`  – 128-bit keystream block  

2. Refactored AES-specific signals:

   - Added `ks_valid_aes` and `ks_data_aes` for the AES path.
   - `ctr_xor` now only sees the generic `ks_req`, `ks_valid`, `ks_data`.
   - The AES path only drives its local `ks_valid_aes` / `ks_data_aes`.

### Why

- Before, `ctr_xor` was effectively hard-wired to AES via a single register and valid signal.
- The new structure makes **keystream generation pluggable**:
  - AES becomes one producer behind the interface.
  - ChaCha can be added as another producer without modifying `ctr_xor`.

---

## 3. AES path: explicit keystream producer

### What changed

- AES result capture logic now:

  - Writes the AES CTR result into `ks_data_aes` when the CTR path is consuming AES output.
  - Asserts `ks_valid_aes` when that data is valid (typically one-cycle pulse).
  - Leaves tagmask / GHASH related uses of AES output as they were.

- The generic interface is initially driven **only** from the AES path:

  - `ks_valid = ks_valid_aes`  
  - `ks_data  = ks_data_aes`

### Why

- Makes AES CTR look like a clean **“keystream producer”** instead of directly feeding `ctr_xor`.
- Ensures that with `algo_sel = 0`, the AES-GCM behavior (timing + functionality) matches the original design.
- Prepares the datapath so a second producer (ChaCha) can be selected with a small mux instead of invasive edits.

---

## 4. New ChaCha keystream unit: `chacha_keystream_unit.v`

### What changed

- Added a new module `chacha_keystream_unit` that:

  **Configuration**

  - Latches ChaCha configuration when `cfg_we` is asserted:
    - `chacha_key`
    - `chacha_nonce`
    - `chacha_ctr_init`

  **Core interface**

  - Connects to `chacha_core` using its existing ports:
    - key, counter, IV, rounds, `ready`, `data_out_valid`, `data_out`.

  **Keystream interface**

  - Implements the same handshake as the AES keystream path:
    - Input: `ks_req`
    - Outputs: `ks_valid`, `ks_data[127:0]`

- First implementation policy (simple, functional baseline):

  - For each `ks_req` when `chacha_core` is ready:
    - Assert `next` to start one ChaCha block.
    - Wait for `data_out_valid`.
    - Take the **lower 128 bits** of the 512-bit ChaCha output as `ks_data`.
    - Pulse `ks_valid` for one cycle.
    - Increment an internal block counter for the next request.

- In `aes_gcm_datapath.v`, the unit is instantiated and wired to:

  - `chacha_key`      ← reuse the active AES key register for now.  
  - `chacha_nonce`    ← drive from `iv_in`.  
  - `chacha_ctr_init` ← set to a fixed initial counter (e.g., 1).  
  - `cfg_we`          ← currently tied low (will be controlled via CSRs in future).  
  - `ks_req`          ← generic `ks_req` gated by ChaCha mode selection.

### Why

- Encapsulates all ChaCha-specific details (key/nonce layout, counter/IV mapping, handshake with `chacha_core`) in one module.
- Presents the **same `ks_req` / `ks_valid` / `ks_data` interface** as AES, keeping the datapath mux simple.
- The “one ChaCha block → one 128-bit keystream word” policy is easy to validate and correct by construction; full 512-bit reuse is a follow-on optimization.

---

## 5. Keystream selection mux: AES vs ChaCha

### What changed

- Added ChaCha-specific keystream signals inside the datapath:

  - `ks_valid_chacha`
  - `ks_data_chacha`

- Implemented a **2-to-1 mux** that drives the generic interface:

  - If `algo_sel = 0` (AES mode):
    - `ks_valid = ks_valid_aes`
    - `ks_data  = ks_data_aes`

  - If `algo_sel = 1` (ChaCha mode):
    - `ks_valid = ks_valid_chacha`
    - `ks_data  = ks_data_chacha`

- Gated `ks_req` into the ChaCha unit:

  - ChaCha only sees `ks_req` when it is the selected algorithm.

### Why

- Centralizes algorithm selection in a single, obvious place in the datapath.
- Keeps `ctr_xor` and GHASH logic unchanged and unaware of algorithm choice.
- Ensures only one producer is active at a time, avoiding conflicting drivers on the keystream interface.

---

## 6. Algorithm select: `algo_sel`

### What changed

- In the top level (`aes_gcm_top.v`):

  - Added `algo_sel` as a new CSR bit.

- In the datapath (`aes_gcm_datapath.v`):

  - Added `algo_sel` to the datapath’s input ports.
  - Derived an internal wire (e.g., `algo_is_chacha`) directly from `algo_sel`.
  - Used `algo_is_chacha` to:
    - Gate `ks_req` into `chacha_keystream_unit`.
    - Select between AES and ChaCha outputs in the keystream mux.

### Why

- Provides a single, clear control knob for **which keystream algorithm is active**.
- Keeps the rest of the control FSM and GHASH/tag logic identical to the AES-GCM-only design.

---

## Behavior by mode

### AES-GCM mode (`algo_sel = 0`)

- Keystream is produced by the original AES CTR path.
- `ctr_xor` and GHASH see the same behavior as in the original design.
- Design remains backward-compatible with AES-GCM-only use.

### ChaCha keystream mode (`algo_sel = 1`)

- Keystream is produced by `chacha_keystream_unit` using `chacha_core`.
- AES core can still be used for other GCM functions (e.g., tagmask), but CTR keystream is ChaCha-based.
- Authentication/tag path is still GCM-style; Poly1305 is not yet implemented.

---

## Current limitations and next steps

### Limitations

- ChaCha configuration (`cfg_we`, key/nonce/counter) is still partially stubbed and not fully driven by dedicated CSRs.
- Only 128 bits of the 512-bit ChaCha result are used per block; 3/4 of the core output is currently unused.
- Full ChaCha20-Poly1305 support (Poly1305 tag, mode-specific control, tag verify) is not yet present.

### Planned follow-ups

1. Connect ChaCha configuration registers to proper CSRs when `algo_sel = 1`.
2. Extend `chacha_keystream_unit` to reuse all 512 bits from `chacha_core` (4 × 128-bit keystream outputs per block).
3. Add a Poly1305 tag pipeline and mode control to support a complete ChaCha20-Poly1305 mode alongside AES-GCM.

---
