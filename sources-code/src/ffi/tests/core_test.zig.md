---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/ffi/tests/core_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.405316+00:00
---

# src/ffi/tests/core_test.zig

```zig
// Phase 30A Gate Tests — FFI Integration Test Harness
//
// Tests call exported C ABI functions as if from external code.
// No Zig error handling shortcuts. All 10 gate tests from the PRD.

const std = @import("std");
const exports = @import("exports");

// Re-export the C functions for direct calling
const semantos_init = exports.semantos_init;
const semantos_shutdown = exports.semantos_shutdown;
const semantos_cell_write = exports.semantos_cell_write;
const semantos_cell_read = exports.semantos_cell_read;
const semantos_cell_verify = exports.semantos_cell_verify;
const semantos_free = exports.semantos_free;
const semantos_version = exports.semantos_version;
const semantos_last_error = exports.semantos_last_error;

// Error codes (match semantos.h)
const SEMANTOS_OK: i32 = 0;
const SEMANTOS_ERR_NOT_FOUND: i32 = -1;
const SEMANTOS_ERR_INVALID_JSON: i32 = -2;
const SEMANTOS_ERR_ALREADY_INIT: i32 = -4;
const SEMANTOS_ERR_NOT_INIT: i32 = -5;
const SEMANTOS_ERR_BUFFER_TOO_SMALL: i32 = -6;
const SEMANTOS_ERR_INVALID_PROOF: i32 = -7;
const SEMANTOS_ERR_DENIED: i32 = -8;

// ── Test 1: semantos_init with valid JSON returns SEMANTOS_OK ──

test "30A gate test 1: semantos_init with valid JSON returns SEMANTOS_OK" {
    const config = "{\"version\":\"0.2.1\"}";
    const result = semantos_init(config.ptr, config.len);
    try std.testing.expectEqual(SEMANTOS_OK, result);

    // Cleanup
    _ = semantos_shutdown();
}

// ── Test 2: semantos_init with invalid JSON returns SEMANTOS_ERR_INVALID_JSON ──

test "30A gate test 2: semantos_init with invalid JSON returns SEMANTOS_ERR_INVALID_JSON" {
    const invalid = "{invalid json";
    const result = semantos_init(invalid.ptr, invalid.len);
    try std.testing.expectEqual(SEMANTOS_ERR_INVALID_JSON, result);

    // Verify last_error has a message
    var err_buf: [256]u8 = undefined;
    var err_len: usize = err_buf.len;
    const err_result = semantos_last_error(&err_buf, &err_len);
    try std.testing.expectEqual(SEMANTOS_OK, err_result);
    try std.testing.expect(err_len > 0);
}

// ── Test 3: write then read returns identical bytes ──

test "30A gate test 3: semantos_cell_write then semantos_cell_read returns identical bytes" {
    const config = "{\"version\":\"0.2.1\"}";
    const init_r = semantos_init(config.ptr, config.len);
    try std.testing.expectEqual(SEMANTOS_OK, init_r);

    const path = "/test/key";
    const data = "hello, world!";
    const wr = semantos_cell_write(path.ptr, path.len, data.ptr, data.len);
    try std.testing.expectEqual(SEMANTOS_OK, wr);

    var buf: [64]u8 = undefined;
    var len: usize = buf.len;
    const rd = semantos_cell_read(path.ptr, path.len, &buf, &len);
    try std.testing.expectEqual(SEMANTOS_OK, rd);
    try std.testing.expectEqual(data.len, len);
    try std.testing.expectEqualSlices(u8, data, buf[0..len]);

    _ = semantos_shutdown();
}

// ── Test 4: read non-existent path returns SEMANTOS_ERR_NOT_FOUND ──

test "30A gate test 4: semantos_cell_read on non-existent path returns SEMANTOS_ERR_NOT_FOUND" {
    const config = "{\"version\":\"0.2.1\"}";
    _ = semantos_init(config.ptr, config.len);

    const path = "/nonexistent/path";
    var buf: [64]u8 = undefined;
    var len: usize = buf.len;
    const result = semantos_cell_read(path.ptr, path.len, &buf, &len);
    try std.testing.expectEqual(SEMANTOS_ERR_NOT_FOUND, result);

    _ = semantos_shutdown();
}

// ── Test 5: semantos_free does not crash ──

test "30A gate test 5: semantos_free does not crash" {
    const config = "{\"version\":\"0.2.1\"}";
    _ = semantos_init(config.ptr, config.len);

    // Free with a valid-looking pointer — should be a no-op, no crash
    var buf: [64]u8 = undefined;
    semantos_free(&buf, 64);

    // Free with null — should be a no-op, no crash
    semantos_free(null, 0);

    // If we reach here, no crash occurred
    try std.testing.expect(true);

    _ = semantos_shutdown();
}

// ── Test 6: semantos_version returns non-null string matching build version ──

test "30A gate test 6: semantos_version returns non-null string matching build version" {
    const version: [*:0]const u8 = semantos_version();
    const ver_str = std.mem.span(version);
    try std.testing.expect(ver_str.len > 0);
    try std.testing.expect(std.mem.startsWith(u8, ver_str, "0."));
    // Must contain "phase-30" (covers 30a, 30b, 30c)
    try std.testing.expect(std.mem.indexOf(u8, ver_str, "phase-30") != null);
}

// ── Test 7: double init returns SEMANTOS_ERR_ALREADY_INIT ──

test "30A gate test 7: double semantos_init returns SEMANTOS_ERR_ALREADY_INIT" {
    const config = "{\"version\":\"0.2.1\"}";
    const r1 = semantos_init(config.ptr, config.len);
    try std.testing.expectEqual(SEMANTOS_OK, r1);

    const r2 = semantos_init(config.ptr, config.len);
    try std.testing.expectEqual(SEMANTOS_ERR_ALREADY_INIT, r2);

    _ = semantos_shutdown();
}

// ── Test 8: function before init returns SEMANTOS_ERR_NOT_INIT ──

test "30A gate test 8: any function before semantos_init returns SEMANTOS_ERR_NOT_INIT" {
    // Ensure not initialized (fresh test)
    const path = "/test";
    const data = "test";
    const wr = semantos_cell_write(path.ptr, path.len, data.ptr, data.len);
    try std.testing.expectEqual(SEMANTOS_ERR_NOT_INIT, wr);

    var buf: [64]u8 = undefined;
    var len: usize = buf.len;
    const rd = semantos_cell_read(path.ptr, path.len, &buf, &len);
    try std.testing.expectEqual(SEMANTOS_ERR_NOT_INIT, rd);

    const proof: [32]u8 = .{0} ** 32;
    const vr = semantos_cell_verify(path.ptr, path.len, &proof, 32);
    try std.testing.expectEqual(SEMANTOS_ERR_NOT_INIT, vr);

    const sd = semantos_shutdown();
    try std.testing.expectEqual(SEMANTOS_ERR_NOT_INIT, sd);
}

// ── Test 9: write with null data pointer returns error ──

test "30A gate test 9: semantos_cell_write with null data pointer returns error" {
    const config = "{\"version\":\"0.2.1\"}";
    _ = semantos_init(config.ptr, config.len);

    const path = "/test";
    const result = semantos_cell_write(path.ptr, path.len, null, 10);
    try std.testing.expectEqual(SEMANTOS_ERR_DENIED, result);

    // Also test null path
    const data = "something";
    const result2 = semantos_cell_write(null, 5, data.ptr, data.len);
    try std.testing.expectEqual(SEMANTOS_ERR_DENIED, result2);

    _ = semantos_shutdown();
}

// ── Test 10: write with zero-length data returns error ──

test "30A gate test 10: semantos_cell_write with zero-length data returns error" {
    const config = "{\"version\":\"0.2.1\"}";
    _ = semantos_init(config.ptr, config.len);

    const path = "/test";
    const data = "something";
    const result = semantos_cell_write(path.ptr, path.len, data.ptr, 0);
    try std.testing.expect(result != SEMANTOS_OK);

    // Verify it's a specific error, not a crash
    try std.testing.expectEqual(SEMANTOS_ERR_DENIED, result);

    _ = semantos_shutdown();
}

// ── Bonus: cell_verify with valid proof succeeds ──

test "30A bonus: semantos_cell_verify with valid SHA-256 proof succeeds" {
    const config = "{\"version\":\"0.2.1\"}";
    _ = semantos_init(config.ptr, config.len);

    const path = "/verified/cell";
    const data = "important data";
    _ = semantos_cell_write(path.ptr, path.len, data.ptr, data.len);

    // Compute SHA-256 of "important data"
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &hash, .{});

    const vr = semantos_cell_verify(path.ptr, path.len, &hash, 32);
    try std.testing.expectEqual(SEMANTOS_OK, vr);

    // Wrong proof should fail
    var bad_hash: [32]u8 = .{0xFF} ** 32;
    const vr2 = semantos_cell_verify(path.ptr, path.len, &bad_hash, 32);
    try std.testing.expectEqual(SEMANTOS_ERR_INVALID_PROOF, vr2);

    _ = semantos_shutdown();
}

// ── Bonus: last_error buffer too small ──

test "30A bonus: semantos_last_error reports BUFFER_TOO_SMALL correctly" {
    // Trigger an error to populate last_error
    const invalid = "not json";
    _ = semantos_init(invalid.ptr, invalid.len);

    // Try with a tiny buffer
    var tiny: [2]u8 = undefined;
    var tiny_len: usize = tiny.len;
    const result = semantos_last_error(&tiny, &tiny_len);
    try std.testing.expectEqual(SEMANTOS_ERR_BUFFER_TOO_SMALL, result);
    // tiny_len should now hold the required size
    try std.testing.expect(tiny_len > 2);
}

// ── Bonus: overwrite existing cell ──

test "30A bonus: overwriting existing cell returns new data on read" {
    const config = "{}";
    _ = semantos_init(config.ptr, config.len);

    const path = "/overwrite/test";
    const data1 = "first";
    _ = semantos_cell_write(path.ptr, path.len, data1.ptr, data1.len);

    const data2 = "second value";
    _ = semantos_cell_write(path.ptr, path.len, data2.ptr, data2.len);

    var buf: [64]u8 = undefined;
    var len: usize = buf.len;
    const rd = semantos_cell_read(path.ptr, path.len, &buf, &len);
    try std.testing.expectEqual(SEMANTOS_OK, rd);
    try std.testing.expectEqualSlices(u8, data2, buf[0..len]);

    _ = semantos_shutdown();
}

```
