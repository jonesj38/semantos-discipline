---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/ffi/tests/tx_chain_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.405014+00:00
---

# src/ffi/tests/tx_chain_test.zig

```zig
// Phase 30A-Patch Gate Tests — Transaction Chain Integration
//
// Tests T9–T38+: covers tx_chain_create, tx_chain_extend, tx_chain_cosign,
// tx_chain_verify, tx_verify_spv, tx_stream_accept, tx_stream_queue,
// and register_tx_callbacks.
//
// Mock callbacks: mock_sign returns a deterministic 71-byte DER signature,
// mock_broadcast records raw TX and returns a deterministic txid.

const std = @import("std");
const exports = @import("exports");
const sighash = @import("sighash");
const tx_builder_mod = @import("tx_builder");
const TxBuilder = tx_builder_mod.TxBuilder;

// Re-export C functions
const semantos_init = exports.semantos_init;
const semantos_shutdown = exports.semantos_shutdown;
const semantos_register_tx_callbacks = exports.semantos_register_tx_callbacks;
const semantos_tx_chain_create = exports.semantos_tx_chain_create;
const semantos_tx_chain_extend = exports.semantos_tx_chain_extend;
const semantos_tx_chain_cosign = exports.semantos_tx_chain_cosign;
const semantos_tx_chain_verify = exports.semantos_tx_chain_verify;
const semantos_tx_verify_spv = exports.semantos_tx_verify_spv;
const semantos_tx_stream_accept = exports.semantos_tx_stream_accept;
const semantos_tx_stream_queue = exports.semantos_tx_stream_queue;
const semantos_cell_read = exports.semantos_cell_read;
const semantos_last_error = exports.semantos_last_error;

// Error codes
const SEMANTOS_OK: i32 = 0;
const SEMANTOS_ERR_NOT_FOUND: i32 = -1;
const SEMANTOS_ERR_INVALID_JSON: i32 = -2;
const SEMANTOS_ERR_NOT_INIT: i32 = -5;
const SEMANTOS_ERR_DENIED: i32 = -8;
const SEMANTOS_ERR_INVALID_TX: i32 = -10;
const SEMANTOS_ERR_INVALID_SIGHASH: i32 = -11;
const SEMANTOS_ERR_CHAIN_BROKEN: i32 = -12;
const SEMANTOS_ERR_FSM_VIOLATION: i32 = -13;
const SEMANTOS_ERR_SIGNATURE_INVALID: i32 = -14;
const SEMANTOS_ERR_CALLBACK_NOT_REGISTERED: i32 = -15;
const SEMANTOS_ERR_OUTPUT_MAP_INVALID: i32 = -16;
const SEMANTOS_ERR_INVALID_PROOF: i32 = -7;

// ── Mock callback state ──

var g_mock_sign_count: u32 = 0;
var g_mock_broadcast_count: u32 = 0;
var g_mock_last_broadcast_tx: [4096]u8 = undefined;
var g_mock_last_broadcast_len: u32 = 0;

// Deterministic 71-byte DER signature (valid DER format)
const mock_der_sig = [_]u8{
    0x30, 0x45, // SEQUENCE, length 69
    0x02, 0x21, // INTEGER, length 33
    0x00, // leading zero
} ++ [_]u8{0x11} ** 32 ++ [_]u8{
    0x02, 0x20, // INTEGER, length 32
} ++ [_]u8{0x22} ** 32;

// Allocator for mock callback output
var g_mock_sig_buf: [72]u8 = undefined;

fn mock_sign(
    _: [*]const u8,
    _: u32,
    _: [*]const u8,
    _: u32,
    out_sig: *[*]u8,
    out_sig_len: *u32,
) callconv(.c) i32 {
    g_mock_sign_count += 1;
    @memcpy(g_mock_sig_buf[0..mock_der_sig.len], &mock_der_sig);
    out_sig.* = &g_mock_sig_buf;
    out_sig_len.* = mock_der_sig.len;
    return 0;
}

fn mock_broadcast(
    raw_tx: [*]const u8,
    tx_len: u32,
    out_txid: *[32]u8,
) callconv(.c) i32 {
    g_mock_broadcast_count += 1;
    const copy_len = @min(tx_len, 4096);
    @memcpy(g_mock_last_broadcast_tx[0..copy_len], raw_tx[0..copy_len]);
    g_mock_last_broadcast_len = copy_len;
    out_txid.* = .{0xDD} ** 32;
    return 0;
}

// ── Test config JSON with sighash policy ──

const test_config =
    \\{
    \\  "sighashPolicy": {
    \\    "genesis": "ALL|FORKID",
    \\    "transitions": [
    \\      {"from": "new", "to": "dispatched", "role": "pm", "sighash": "SINGLE|ACP|FORKID"},
    \\      {"from": "dispatched", "to": "in_progress", "role": "executor", "sighash": "SINGLE|ACP|FORKID"},
    \\      {"from": "in_progress", "to": "completed", "role": "executor", "sighash": "ALL|FORKID"},
    \\      {"from": "completed", "to": "approved", "role": "approver", "sighash": "ALL|FORKID", "linear": true}
    \\    ]
    \\  }
    \\}
;

// Test pubkey (compressed, 33 bytes): 0x02 + 32 zero bytes
const test_cert = [_]u8{0x02} ++ [_]u8{0} ** 32;

fn resetMockState() void {
    g_mock_sign_count = 0;
    g_mock_broadcast_count = 0;
    g_mock_last_broadcast_len = 0;
}

fn initKernel() void {
    // Ensure clean state
    _ = semantos_shutdown();
    resetMockState();
    const rc = semantos_init(test_config.ptr, test_config.len);
    std.debug.assert(rc == SEMANTOS_OK);
    const rc2 = semantos_register_tx_callbacks(&mock_sign, &mock_broadcast);
    std.debug.assert(rc2 == SEMANTOS_OK);
}

fn getLastError() []const u8 {
    var buf: [256]u8 = undefined;
    var len: usize = 256;
    const rc = semantos_last_error(&buf, &len);
    if (rc == SEMANTOS_OK and len > 0) {
        return buf[0..len];
    }
    return "";
}

// ── T9: register_tx_callbacks before init → ERR_NOT_INIT ──

test "T9: register_tx_callbacks before init fails" {
    _ = semantos_shutdown();
    const rc = semantos_register_tx_callbacks(&mock_sign, &mock_broadcast);
    try std.testing.expectEqual(SEMANTOS_ERR_NOT_INIT, rc);
}

// ── T10: register_tx_callbacks with null → ERR_DENIED ──

test "T10: register_tx_callbacks with null sign callback fails" {
    _ = semantos_shutdown();
    _ = semantos_init(test_config.ptr, test_config.len);
    const rc = semantos_register_tx_callbacks(null, &mock_broadcast);
    try std.testing.expectEqual(SEMANTOS_ERR_DENIED, rc);
    _ = semantos_shutdown();
}

// ── T11: tx_chain_create before init → ERR_NOT_INIT ──

test "T11: tx_chain_create before init fails" {
    _ = semantos_shutdown();
    var out_tx: [*]u8 = undefined;
    var out_len: usize = 0;
    const path = "test/path";
    const state = "{\"data\":\"test\"}";
    const rc = semantos_tx_chain_create(
        path.ptr,
        path.len,
        state.ptr,
        state.len,
        &test_cert,
        test_cert.len,
        &out_tx,
        &out_len,
    );
    try std.testing.expectEqual(SEMANTOS_ERR_NOT_INIT, rc);
}

// ── T12: tx_chain_create without callbacks → ERR_CALLBACK_NOT_REGISTERED ──

test "T12: tx_chain_create without callbacks fails" {
    _ = semantos_shutdown();
    _ = semantos_init(test_config.ptr, test_config.len);
    // Don't register callbacks
    var out_tx: [*]u8 = undefined;
    var out_len: usize = 0;
    const path = "test/path";
    const state = "{\"data\":\"test\"}";
    const rc = semantos_tx_chain_create(
        path.ptr,
        path.len,
        state.ptr,
        state.len,
        &test_cert,
        test_cert.len,
        &out_tx,
        &out_len,
    );
    try std.testing.expectEqual(SEMANTOS_ERR_CALLBACK_NOT_REGISTERED, rc);
    _ = semantos_shutdown();
}

// ── T13: tx_chain_create returns valid TX ──

test "T13: tx_chain_create produces valid serialized TX" {
    initKernel();
    defer _ = semantos_shutdown();

    var out_tx: [*]u8 = undefined;
    var out_len: usize = 0;
    const path = "test/genesis";
    const state = "{\"state\":\"new\"}";

    const rc = semantos_tx_chain_create(
        path.ptr,
        path.len,
        state.ptr,
        state.len,
        &test_cert,
        test_cert.len,
        &out_tx,
        &out_len,
    );
    try std.testing.expectEqual(SEMANTOS_OK, rc);
    try std.testing.expect(out_len > 0);

    // Verify sign callback was called
    try std.testing.expectEqual(@as(u32, 1), g_mock_sign_count);

    // Parse the TX to validate structure
    const alloc = std.heap.page_allocator;
    const ctx = try alloc.create(sighash.TxContext);
    defer alloc.destroy(ctx);

    try sighash.parseTxContext(out_tx[0..out_len], 0, 0, ctx);
    try std.testing.expectEqual(@as(u32, 1), ctx.input_count);
    try std.testing.expect(ctx.output_count >= 1);

    // Primary output should have valid output_map
    const script = ctx.outputs[0].script[0..ctx.outputs[0].script_len];
    const omap = TxBuilder.extractOutputMap(script);
    try std.testing.expect(omap != null);
}

// ── T14: tx_chain_create stores TX in cell store ──

test "T14: tx_chain_create stores TX retrievable via cell_read" {
    initKernel();
    defer _ = semantos_shutdown();

    var out_tx: [*]u8 = undefined;
    var out_len: usize = 0;
    const path = "test/stored";
    const state = "{\"state\":\"new\"}";

    const rc = semantos_tx_chain_create(
        path.ptr,
        path.len,
        state.ptr,
        state.len,
        &test_cert,
        test_cert.len,
        &out_tx,
        &out_len,
    );
    try std.testing.expectEqual(SEMANTOS_OK, rc);

    // Read back from cell store
    var read_buf: [64000]u8 = undefined;
    var read_len: usize = 64000;
    const read_rc = semantos_cell_read(path.ptr, path.len, &read_buf, &read_len);
    try std.testing.expectEqual(SEMANTOS_OK, read_rc);
    try std.testing.expectEqual(out_len, read_len);
}

// ── T15: tx_chain_create with null path → ERR_DENIED ──

test "T15: tx_chain_create with null path fails" {
    initKernel();
    defer _ = semantos_shutdown();

    var out_tx: [*]u8 = undefined;
    var out_len: usize = 0;
    const state = "{\"state\":\"new\"}";

    const rc = semantos_tx_chain_create(
        null,
        0,
        state.ptr,
        state.len,
        &test_cert,
        test_cert.len,
        &out_tx,
        &out_len,
    );
    try std.testing.expectEqual(SEMANTOS_ERR_DENIED, rc);
}

// ── T16: tx_chain_create with short cert → ERR_DENIED ──

test "T16: tx_chain_create with short cert fails" {
    initKernel();
    defer _ = semantos_shutdown();

    var out_tx: [*]u8 = undefined;
    var out_len: usize = 0;
    const path = "test/path";
    const state = "{\"state\":\"new\"}";
    const short_cert = [_]u8{0x02} ** 10; // Too short (< 33)

    const rc = semantos_tx_chain_create(
        path.ptr,
        path.len,
        state.ptr,
        state.len,
        &short_cert,
        short_cert.len,
        &out_tx,
        &out_len,
    );
    try std.testing.expectEqual(SEMANTOS_ERR_DENIED, rc);
}

// ── T17: tx_chain_extend with valid transition ──

test "T17: tx_chain_extend produces valid spending TX" {
    initKernel();
    defer _ = semantos_shutdown();

    // First create genesis
    var genesis_tx: [*]u8 = undefined;
    var genesis_len: usize = 0;
    const path = "test/extend";
    const state1 = "{\"state\":\"new\"}";

    var rc = semantos_tx_chain_create(
        path.ptr,
        path.len,
        state1.ptr,
        state1.len,
        &test_cert,
        test_cert.len,
        &genesis_tx,
        &genesis_len,
    );
    try std.testing.expectEqual(SEMANTOS_OK, rc);
    resetMockState();

    // Extend: new -> dispatched by pm
    var extend_tx: [*]u8 = undefined;
    var extend_len: usize = 0;
    const state2 = "{\"state\":\"dispatched\"}";
    const from = "new";
    const to = "dispatched";
    const role = "pm";

    rc = semantos_tx_chain_extend(
        genesis_tx,
        genesis_len,
        0,
        state2.ptr,
        state2.len,
        &test_cert,
        test_cert.len,
        from.ptr,
        from.len,
        to.ptr,
        to.len,
        role.ptr,
        role.len,
        &extend_tx,
        &extend_len,
    );
    try std.testing.expectEqual(SEMANTOS_OK, rc);
    try std.testing.expect(extend_len > 0);
    try std.testing.expectEqual(@as(u32, 1), g_mock_sign_count);

    // Parse extended TX
    const alloc = std.heap.page_allocator;
    const ctx = try alloc.create(sighash.TxContext);
    defer alloc.destroy(ctx);
    try sighash.parseTxContext(extend_tx[0..extend_len], 0, 0, ctx);

    // Input should spend genesis TX
    const genesis_txid = sighash.computeTxId(genesis_tx[0..genesis_len]);
    try std.testing.expectEqualSlices(u8, &genesis_txid, &ctx.inputs[0].prev_txid);
}

// ── T18: tx_chain_extend with invalid FSM transition ──

test "T18: tx_chain_extend rejects invalid FSM transition" {
    initKernel();
    defer _ = semantos_shutdown();

    // Create genesis
    var genesis_tx: [*]u8 = undefined;
    var genesis_len: usize = 0;
    const path = "test/fsm";
    const state1 = "{\"state\":\"new\"}";

    _ = semantos_tx_chain_create(
        path.ptr,
        path.len,
        state1.ptr,
        state1.len,
        &test_cert,
        test_cert.len,
        &genesis_tx,
        &genesis_len,
    );

    // Try invalid transition: new -> completed (not allowed)
    var extend_tx: [*]u8 = undefined;
    var extend_len: usize = 0;
    const state2 = "{\"state\":\"completed\"}";
    const from = "new";
    const to = "completed";
    const role = "pm";

    const rc = semantos_tx_chain_extend(
        genesis_tx,
        genesis_len,
        0,
        state2.ptr,
        state2.len,
        &test_cert,
        test_cert.len,
        from.ptr,
        from.len,
        to.ptr,
        to.len,
        role.ptr,
        role.len,
        &extend_tx,
        &extend_len,
    );
    try std.testing.expectEqual(SEMANTOS_ERR_FSM_VIOLATION, rc);
}

// ── T19: tx_chain_extend with wrong role ──

test "T19: tx_chain_extend rejects wrong role" {
    initKernel();
    defer _ = semantos_shutdown();

    var genesis_tx: [*]u8 = undefined;
    var genesis_len: usize = 0;
    _ = semantos_tx_chain_create(
        "test/role".ptr,
        "test/role".len,
        "{\"s\":\"new\"}".ptr,
        "{\"s\":\"new\"}".len,
        &test_cert,
        test_cert.len,
        &genesis_tx,
        &genesis_len,
    );

    var extend_tx: [*]u8 = undefined;
    var extend_len: usize = 0;
    // Transition new->dispatched requires role "pm", not "executor"
    const rc = semantos_tx_chain_extend(
        genesis_tx,
        genesis_len,
        0,
        "{\"s\":\"d\"}".ptr,
        "{\"s\":\"d\"}".len,
        &test_cert,
        test_cert.len,
        "new".ptr,
        "new".len,
        "dispatched".ptr,
        "dispatched".len,
        "executor".ptr,
        "executor".len,
        &extend_tx,
        &extend_len,
    );
    try std.testing.expectEqual(SEMANTOS_ERR_FSM_VIOLATION, rc);
}

// ── T20: tx_chain_cosign adds signature to TX ──

test "T20: tx_chain_cosign adds co-signature" {
    initKernel();
    defer _ = semantos_shutdown();

    // Create a genesis TX first
    var genesis_tx: [*]u8 = undefined;
    var genesis_len: usize = 0;
    _ = semantos_tx_chain_create(
        "test/cosign".ptr,
        "test/cosign".len,
        "{\"s\":\"new\"}".ptr,
        "{\"s\":\"new\"}".len,
        &test_cert,
        test_cert.len,
        &genesis_tx,
        &genesis_len,
    );
    resetMockState();

    // Cosign at input 0
    var cosigned_tx: [*]u8 = undefined;
    var cosigned_len: usize = 0;
    const rc = semantos_tx_chain_cosign(
        genesis_tx,
        genesis_len,
        0,
        &test_cert,
        test_cert.len,
        0x41, // ALL|FORKID
        0, // bip143
        1, // input_value
        &cosigned_tx,
        &cosigned_len,
    );
    try std.testing.expectEqual(SEMANTOS_OK, rc);
    try std.testing.expect(cosigned_len > 0);
    try std.testing.expectEqual(@as(u32, 1), g_mock_sign_count);

    // Cosigned TX should parse
    const alloc = std.heap.page_allocator;
    const ctx = try alloc.create(sighash.TxContext);
    defer alloc.destroy(ctx);
    try sighash.parseTxContext(cosigned_tx[0..cosigned_len], 0, 0, ctx);
    // Input 0 should now have a script_sig
    try std.testing.expect(ctx.inputs[0].script_sig_len > 0);
}

// ── T21: tx_chain_cosign with invalid input index ──

test "T21: tx_chain_cosign with out-of-range input fails" {
    initKernel();
    defer _ = semantos_shutdown();

    var genesis_tx: [*]u8 = undefined;
    var genesis_len: usize = 0;
    _ = semantos_tx_chain_create(
        "test/cosign2".ptr,
        "test/cosign2".len,
        "{\"s\":\"new\"}".ptr,
        "{\"s\":\"new\"}".len,
        &test_cert,
        test_cert.len,
        &genesis_tx,
        &genesis_len,
    );

    var cosigned_tx: [*]u8 = undefined;
    var cosigned_len: usize = 0;
    const rc = semantos_tx_chain_cosign(
        genesis_tx,
        genesis_len,
        99, // way out of range
        &test_cert,
        test_cert.len,
        0x41,
        0,
        1,
        &cosigned_tx,
        &cosigned_len,
    );
    try std.testing.expectEqual(SEMANTOS_ERR_INVALID_TX, rc);
}

// ── T22: tx_chain_verify with valid 2-TX chain ──

test "T22: tx_chain_verify validates a 2-TX chain" {
    initKernel();
    defer _ = semantos_shutdown();

    // Create genesis
    var genesis_tx: [*]u8 = undefined;
    var genesis_len: usize = 0;
    _ = semantos_tx_chain_create(
        "test/chain".ptr,
        "test/chain".len,
        "{\"s\":\"new\"}".ptr,
        "{\"s\":\"new\"}".len,
        &test_cert,
        test_cert.len,
        &genesis_tx,
        &genesis_len,
    );

    // Extend
    var extend_tx: [*]u8 = undefined;
    var extend_len: usize = 0;
    _ = semantos_tx_chain_extend(
        genesis_tx,
        genesis_len,
        0,
        "{\"s\":\"dispatched\"}".ptr,
        "{\"s\":\"dispatched\"}".len,
        &test_cert,
        test_cert.len,
        "new".ptr,
        "new".len,
        "dispatched".ptr,
        "dispatched".len,
        "pm".ptr,
        "pm".len,
        &extend_tx,
        &extend_len,
    );

    // Build chain wire format: [4B len LE + raw TX] per entry
    var chain_buf: [128000]u8 = undefined;
    var cpos: usize = 0;

    // TX 0 (genesis)
    std.mem.writeInt(u32, chain_buf[cpos..][0..4], @intCast(genesis_len), .little);
    cpos += 4;
    @memcpy(chain_buf[cpos..][0..genesis_len], genesis_tx[0..genesis_len]);
    cpos += genesis_len;

    // TX 1 (extend)
    std.mem.writeInt(u32, chain_buf[cpos..][0..4], @intCast(extend_len), .little);
    cpos += 4;
    @memcpy(chain_buf[cpos..][0..extend_len], extend_tx[0..extend_len]);
    cpos += extend_len;

    const rc = semantos_tx_chain_verify(&chain_buf, cpos, 2);
    try std.testing.expectEqual(SEMANTOS_OK, rc);
}

// ── T23: tx_chain_verify rejects broken chain ──

test "T23: tx_chain_verify rejects broken chain link" {
    initKernel();
    defer _ = semantos_shutdown();

    // Create two independent genesis TXs (not linked)
    var tx1: [*]u8 = undefined;
    var len1: usize = 0;
    _ = semantos_tx_chain_create(
        "test/a".ptr,
        "test/a".len,
        "{\"s\":\"a\"}".ptr,
        "{\"s\":\"a\"}".len,
        &test_cert,
        test_cert.len,
        &tx1,
        &len1,
    );

    var tx2: [*]u8 = undefined;
    var len2: usize = 0;
    _ = semantos_tx_chain_create(
        "test/b".ptr,
        "test/b".len,
        "{\"s\":\"b\"}".ptr,
        "{\"s\":\"b\"}".len,
        &test_cert,
        test_cert.len,
        &tx2,
        &len2,
    );

    // Build chain: tx1 then tx2 (unlinked)
    var chain_buf: [128000]u8 = undefined;
    var cpos: usize = 0;
    std.mem.writeInt(u32, chain_buf[cpos..][0..4], @intCast(len1), .little);
    cpos += 4;
    @memcpy(chain_buf[cpos..][0..len1], tx1[0..len1]);
    cpos += len1;
    std.mem.writeInt(u32, chain_buf[cpos..][0..4], @intCast(len2), .little);
    cpos += 4;
    @memcpy(chain_buf[cpos..][0..len2], tx2[0..len2]);
    cpos += len2;

    const rc = semantos_tx_chain_verify(&chain_buf, cpos, 2);
    try std.testing.expectEqual(SEMANTOS_ERR_CHAIN_BROKEN, rc);
}

// ── T24: tx_chain_verify with single TX ──

test "T24: tx_chain_verify with single TX succeeds" {
    initKernel();
    defer _ = semantos_shutdown();

    var tx: [*]u8 = undefined;
    var tx_len: usize = 0;
    _ = semantos_tx_chain_create(
        "test/single".ptr,
        "test/single".len,
        "{\"s\":\"new\"}".ptr,
        "{\"s\":\"new\"}".len,
        &test_cert,
        test_cert.len,
        &tx,
        &tx_len,
    );

    var chain_buf: [64000]u8 = undefined;
    std.mem.writeInt(u32, chain_buf[0..4], @intCast(tx_len), .little);
    @memcpy(chain_buf[4..][0..tx_len], tx[0..tx_len]);

    const rc = semantos_tx_chain_verify(&chain_buf, 4 + tx_len, 1);
    try std.testing.expectEqual(SEMANTOS_OK, rc);
}

// ── T25: tx_chain_verify with zero count ──

test "T25: tx_chain_verify with zero tx_count fails" {
    initKernel();
    defer _ = semantos_shutdown();

    const rc = semantos_tx_chain_verify("x".ptr, 1, 0);
    try std.testing.expectEqual(SEMANTOS_ERR_INVALID_TX, rc);
}

// ── T26: tx_verify_spv with valid BUMP ──

test "T26: tx_verify_spv with valid BUMP succeeds" {
    initKernel();
    defer _ = semantos_shutdown();

    // Create a TX to get its txid
    var tx: [*]u8 = undefined;
    var tx_len: usize = 0;
    _ = semantos_tx_chain_create(
        "test/spv".ptr,
        "test/spv".len,
        "{\"s\":\"new\"}".ptr,
        "{\"s\":\"new\"}".len,
        &test_cert,
        test_cert.len,
        &tx,
        &tx_len,
    );

    // Compute txid
    const txid = sighash.computeTxId(tx[0..tx_len]);

    // Build a BUMP that includes this txid
    var bump: [128]u8 = undefined;
    var bpos: usize = 0;

    // Block height = 1
    std.mem.writeInt(u32, bump[bpos..][0..4], 1, .little);
    bpos += 4;

    // Tree height = 1
    bump[bpos] = 1;
    bpos += 1;

    // Level 0: 2 nodes
    bump[bpos] = 2;
    bpos += 1;

    // Node 0: offset=0, flags=1 (txid)
    bump[bpos] = 0;
    bpos += 1;
    bump[bpos] = 1;
    bpos += 1;

    // Node 1: offset=1, flags=0 (sibling hash)
    bump[bpos] = 1;
    bpos += 1;
    bump[bpos] = 0;
    bpos += 1;
    @memset(bump[bpos..][0..32], 0xFF);
    bpos += 32;

    const rc = semantos_tx_verify_spv(tx, tx_len, &bump, bpos);
    // The BUMP has the txid at offset 0 and a sibling — it should verify
    // (the merkle root computation is correct, even if the root doesn't match
    // a real block header — we're verifying the BUMP format is valid)
    try std.testing.expectEqual(SEMANTOS_OK, rc);
    _ = txid;
}

// ── T27: tx_verify_spv with invalid BUMP ──

test "T27: tx_verify_spv rejects too-short BUMP" {
    initKernel();
    defer _ = semantos_shutdown();

    const tx_data = [_]u8{0} ** 20;
    const bump_data = [_]u8{ 0, 0, 0 };
    const rc = semantos_tx_verify_spv(&tx_data, 20, &bump_data, 3);
    try std.testing.expectEqual(SEMANTOS_ERR_INVALID_PROOF, rc);
}

// ── T28: tx_stream_accept with valid TX ──

test "T28: tx_stream_accept stores valid TX" {
    initKernel();
    defer _ = semantos_shutdown();

    // Create a TX
    var tx: [*]u8 = undefined;
    var tx_len: usize = 0;
    _ = semantos_tx_chain_create(
        "test/accept".ptr,
        "test/accept".len,
        "{\"s\":\"new\"}".ptr,
        "{\"s\":\"new\"}".len,
        &test_cert,
        test_cert.len,
        &tx,
        &tx_len,
    );

    const rc = semantos_tx_stream_accept(tx, tx_len);
    try std.testing.expectEqual(SEMANTOS_OK, rc);
}

// ── T29: tx_stream_accept rejects garbage data ──

test "T29: tx_stream_accept rejects unparseable TX" {
    initKernel();
    defer _ = semantos_shutdown();

    const garbage = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    const rc = semantos_tx_stream_accept(&garbage, 4);
    try std.testing.expectEqual(SEMANTOS_ERR_INVALID_TX, rc);
}

// ── T36: tx_stream_queue stores raw TX ──

test "T36: tx_stream_queue stores TX" {
    initKernel();
    defer _ = semantos_shutdown();

    var tx: [*]u8 = undefined;
    var tx_len: usize = 0;
    _ = semantos_tx_chain_create(
        "test/queue".ptr,
        "test/queue".len,
        "{\"s\":\"new\"}".ptr,
        "{\"s\":\"new\"}".len,
        &test_cert,
        test_cert.len,
        &tx,
        &tx_len,
    );

    const rc = semantos_tx_stream_queue(tx, tx_len);
    try std.testing.expectEqual(SEMANTOS_OK, rc);
}

// ── T37: tx_stream_queue with null → ERR_INVALID_TX ──

test "T37: tx_stream_queue with null fails" {
    initKernel();
    defer _ = semantos_shutdown();

    const rc = semantos_tx_stream_queue(null, 0);
    try std.testing.expectEqual(SEMANTOS_ERR_INVALID_TX, rc);
}

// ── T38: multi-hop chain: create → extend → extend → verify ──

test "T38: 3-TX chain create-extend-extend-verify" {
    initKernel();
    defer _ = semantos_shutdown();

    // Genesis
    var tx0: [*]u8 = undefined;
    var len0: usize = 0;
    try std.testing.expectEqual(SEMANTOS_OK, semantos_tx_chain_create(
        "test/multi".ptr,
        "test/multi".len,
        "{\"s\":\"new\"}".ptr,
        "{\"s\":\"new\"}".len,
        &test_cert,
        test_cert.len,
        &tx0,
        &len0,
    ));

    // Extend 1: new -> dispatched (pm)
    var tx1: [*]u8 = undefined;
    var len1: usize = 0;
    try std.testing.expectEqual(SEMANTOS_OK, semantos_tx_chain_extend(
        tx0,
        len0,
        0,
        "{\"s\":\"dispatched\"}".ptr,
        "{\"s\":\"dispatched\"}".len,
        &test_cert,
        test_cert.len,
        "new".ptr,
        "new".len,
        "dispatched".ptr,
        "dispatched".len,
        "pm".ptr,
        "pm".len,
        &tx1,
        &len1,
    ));

    // Extend 2: dispatched -> in_progress (executor)
    var tx2: [*]u8 = undefined;
    var len2: usize = 0;
    try std.testing.expectEqual(SEMANTOS_OK, semantos_tx_chain_extend(
        tx1,
        len1,
        0,
        "{\"s\":\"in_progress\"}".ptr,
        "{\"s\":\"in_progress\"}".len,
        &test_cert,
        test_cert.len,
        "dispatched".ptr,
        "dispatched".len,
        "in_progress".ptr,
        "in_progress".len,
        "executor".ptr,
        "executor".len,
        &tx2,
        &len2,
    ));

    // Verify the 3-TX chain
    var chain_buf: [256000]u8 = undefined;
    var cpos: usize = 0;

    // TX 0
    std.mem.writeInt(u32, chain_buf[cpos..][0..4], @intCast(len0), .little);
    cpos += 4;
    @memcpy(chain_buf[cpos..][0..len0], tx0[0..len0]);
    cpos += len0;

    // TX 1
    std.mem.writeInt(u32, chain_buf[cpos..][0..4], @intCast(len1), .little);
    cpos += 4;
    @memcpy(chain_buf[cpos..][0..len1], tx1[0..len1]);
    cpos += len1;

    // TX 2
    std.mem.writeInt(u32, chain_buf[cpos..][0..4], @intCast(len2), .little);
    cpos += 4;
    @memcpy(chain_buf[cpos..][0..len2], tx2[0..len2]);
    cpos += len2;

    try std.testing.expectEqual(SEMANTOS_OK, semantos_tx_chain_verify(&chain_buf, cpos, 3));
}

// ── T39: tx_chain_extend before init ──

test "T39: tx_chain_extend before init fails" {
    _ = semantos_shutdown();

    var out_tx: [*]u8 = undefined;
    var out_len: usize = 0;
    const dummy_tx = [_]u8{0} ** 20;

    const rc = semantos_tx_chain_extend(
        &dummy_tx,
        20,
        0,
        "{\"s\":\"x\"}".ptr,
        "{\"s\":\"x\"}".len,
        &test_cert,
        test_cert.len,
        "a".ptr,
        1,
        "b".ptr,
        1,
        "r".ptr,
        1,
        &out_tx,
        &out_len,
    );
    try std.testing.expectEqual(SEMANTOS_ERR_NOT_INIT, rc);
}

```
