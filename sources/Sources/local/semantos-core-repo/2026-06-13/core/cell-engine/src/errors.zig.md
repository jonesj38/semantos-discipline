---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/src/errors.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.972989+00:00
---

# core/cell-engine/src/errors.zig

```zig
// Kernel error codes — matches KernelError enum in CORE:WASM
pub const KernelError = enum(u8) {
    success = 0,
    stack_overflow = 1,
    stack_underflow = 2,
    script_too_large = 3,
    invalid_opcode = 4,
    type_mismatch = 5,
    verify_failed = 6,
    disabled_opcode = 7,
    execution_limit = 8,
    invalid_magic = 9,
    payload_too_large = 10,
    invalid_cell_count = 11,
    buffer_too_small = 12,
    invalid_continuation_header = 13,
    invalid_sec_parameter = 14,
    bca_collision_exceeded = 15,
    // Phase 3 error codes
    invalid_script = 16,
    invalid_sighash = 17,
    no_tx_context = 18,
    nesting_depth_exceeded = 19,
    unknown_macro = 20,
    invalid_pushdata = 21,
    // Phase 4 error codes — linearity enforcement + plexus opcodes
    cannot_duplicate_linear = 22,
    cannot_discard_linear = 23,
    cannot_duplicate_affine = 24,
    cannot_discard_relevant = 25,
    invalid_linearity_type = 26,
    linearity_check_failed = 27,
    domain_flag_mismatch = 28,
    type_hash_mismatch = 29,
    owner_id_mismatch = 30,
    capability_type_mismatch = 31,
    reserved_opcode = 32,
    // Phase 5 error codes — BEEF/BUMP/SPV + capability verification
    beef_parse_error = 33,
    beef_invalid_proof = 34,
    beef_txid_not_found = 35,
    bump_invalid_proof = 36,
    bump_parse_error = 37,
    capability_script_failed = 38,
    capability_not_linear = 39,
    checksig_failed = 40,
    // Phase 6 error codes — octave memory scaling
    invalid_pointer_cell = 41,
    host_fetch_failed = 42,
    not_implemented = 255,
};

```
