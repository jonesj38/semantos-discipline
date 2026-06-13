---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/ffi/tests/callback_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.404439+00:00
---

# src/ffi/tests/callback_test.zig

```zig
// Phase 30B Gate Tests — Callback Round-Trip Tests
//
// Mock C callbacks verify the full round-trip: host registers callback →
// kernel calls through function pointer → host receives correct args →
// host returns data → kernel propagates result.

const std = @import("std");
const exports = @import("exports");
const callbacks = @import("callbacks");

// Re-export C functions for direct calling
const semantos_init = exports.semantos_init;
const semantos_shutdown = exports.semantos_shutdown;
const semantos_cell_write = exports.semantos_cell_write;
const semantos_cell_read = exports.semantos_cell_read;
const semantos_register_callbacks = callbacks.semantos_register_callbacks;

// Error codes (match semantos.h)
const SEMANTOS_OK: i32 = 0;
const SEMANTOS_ERR_ALREADY_INIT: i32 = -4;
const SEMANTOS_ERR_DENIED: i32 = -8;

// ── Mock storage backing ──
// Simple static buffers that mock callbacks read/write into.

var mock_store_key: [256]u8 = undefined;
var mock_store_key_len: usize = 0;
var mock_store_value: [256]u8 = undefined;
var mock_store_value_len: usize = 0;
var mock_write_called: bool = false;
var mock_read_called: bool = false;

fn resetMockState() void {
    mock_write_called = false;
    mock_read_called = false;
    mock_store_key_len = 0;
    mock_store_value_len = 0;
}

// ── Mock callbacks (callconv(.c), real work) ──

fn mock_storage_write(
    path: [*]const u8,
    path_len: usize,
    data: [*]const u8,
    data_len: usize,
) callconv(.c) i32 {
    mock_write_called = true;
    if (path_len > mock_store_key.len or data_len > mock_store_value.len) {
        return SEMANTOS_ERR_DENIED;
    }
    @memcpy(mock_store_key[0..path_len], path[0..path_len]);
    mock_store_key_len = path_len;
    @memcpy(mock_store_value[0..data_len], data[0..data_len]);
    mock_store_value_len = data_len;
    return SEMANTOS_OK;
}

fn mock_storage_read(
    path: [*]const u8,
    path_len: usize,
    out_data: [*]u8,
    inout_len: *usize,
) callconv(.c) i32 {
    mock_read_called = true;
    // Verify the key matches what was stored
    if (path_len != mock_store_key_len or
        !std.mem.eql(u8, path[0..path_len], mock_store_key[0..mock_store_key_len]))
    {
        return -1; // NOT_FOUND
    }
    if (inout_len.* < mock_store_value_len) {
        inout_len.* = mock_store_value_len;
        return -6; // BUFFER_TOO_SMALL
    }
    @memcpy(out_data[0..mock_store_value_len], mock_store_value[0..mock_store_value_len]);
    inout_len.* = mock_store_value_len;
    return SEMANTOS_OK;
}

fn mock_storage_write_fail(
    _: [*]const u8,
    _: usize,
    _: [*]const u8,
    _: usize,
) callconv(.c) i32 {
    return -42; // Custom error code for propagation test
}

// ── Stub callbacks for non-storage adapters (Test 6) ──

fn stub_identity_resolve(_: [*]const u8, _: usize, _: [*]u8, _: *usize) callconv(.c) i32 {
    return 0;
}

fn stub_identity_derive(_: [*]const u8, _: usize, _: [*]const u8, _: usize, _: u32, _: [*]u8, _: *usize) callconv(.c) i32 {
    return 0;
}

fn stub_anchor_submit(_: [*]const u8, _: usize, _: [*]const u8, _: usize, _: [*]u8, _: *usize) callconv(.c) i32 {
    return 0;
}

fn stub_network_publish(_: [*]const u8, _: usize) callconv(.c) i32 {
    return 0;
}

fn stub_network_resolve(_: [*]const u8, _: usize, _: [*]u8, _: *usize) callconv(.c) i32 {
    return 0;
}

// ── Helper: init kernel with valid config ──

fn initKernel() void {
    const config = "{\"version\":\"0.2.1\"}";
    _ = semantos_init(config.ptr, config.len);
}

// ── Test 1: Register callbacks successfully ──

test "30B gate test 1: register callbacks stores them" {
    resetMockState();
    initKernel();

    const result = semantos_register_callbacks(
        @ptrCast(&mock_storage_read),
        @ptrCast(&mock_storage_write),
        null,
        null,
        null,
        null,
        null,
    );
    try std.testing.expectEqual(SEMANTOS_OK, result);

    _ = semantos_shutdown();
}

// ── Test 2: cell_write triggers host_storage_write ──

test "30B gate test 2: semantos_cell_write triggers callback" {
    resetMockState();
    initKernel();

    _ = semantos_register_callbacks(
        @ptrCast(&mock_storage_read),
        @ptrCast(&mock_storage_write),
        null,
        null,
        null,
        null,
        null,
    );

    const path = "/test/key";
    const data = "hello, world!";
    const result = semantos_cell_write(path.ptr, path.len, data.ptr, data.len);

    try std.testing.expectEqual(SEMANTOS_OK, result);
    try std.testing.expect(mock_write_called);
    try std.testing.expectEqualSlices(u8, path, mock_store_key[0..mock_store_key_len]);
    try std.testing.expectEqualSlices(u8, data, mock_store_value[0..mock_store_value_len]);

    _ = semantos_shutdown();
}

// ── Test 3: cell_read returns host-provided data ──

test "30B gate test 3: semantos_cell_read calls callback and returns data" {
    resetMockState();
    initKernel();

    _ = semantos_register_callbacks(
        @ptrCast(&mock_storage_read),
        @ptrCast(&mock_storage_write),
        null,
        null,
        null,
        null,
        null,
    );

    // Write first to populate mock storage
    const path = "/test/key";
    const data = "hello, world!";
    _ = semantos_cell_write(path.ptr, path.len, data.ptr, data.len);

    // Now read it back
    mock_read_called = false;
    var buf: [64]u8 = undefined;
    var len: usize = buf.len;
    const result = semantos_cell_read(path.ptr, path.len, &buf, &len);

    try std.testing.expectEqual(SEMANTOS_OK, result);
    try std.testing.expect(mock_read_called);
    try std.testing.expectEqual(data.len, len);
    try std.testing.expectEqualSlices(u8, data, buf[0..len]);

    _ = semantos_shutdown();
}

// ── Test 4: Null storage_write callback returns error ──

test "30B gate test 4: null storage_write callback returns error" {
    resetMockState();
    initKernel();

    _ = semantos_register_callbacks(
        @ptrCast(&mock_storage_read),
        null, // storage_write is null
        null,
        null,
        null,
        null,
        null,
    );

    const path = "/test";
    const data = "test";
    const result = semantos_cell_write(path.ptr, path.len, data.ptr, data.len);

    try std.testing.expectEqual(SEMANTOS_ERR_DENIED, result);
    try std.testing.expect(!mock_write_called);

    _ = semantos_shutdown();
}

// ── Test 5: Null storage_read callback returns error ──

test "30B gate test 5: null storage_read callback returns error" {
    resetMockState();
    initKernel();

    _ = semantos_register_callbacks(
        null, // storage_read is null
        @ptrCast(&mock_storage_write),
        null,
        null,
        null,
        null,
        null,
    );

    const path = "/test";
    var buf: [64]u8 = undefined;
    var len: usize = buf.len;
    const result = semantos_cell_read(path.ptr, path.len, &buf, &len);

    try std.testing.expectEqual(SEMANTOS_ERR_DENIED, result);
    try std.testing.expect(!mock_read_called);

    _ = semantos_shutdown();
}

// ── Test 6: All 7 callback types can be registered ──

test "30B gate test 6: all callback types can be registered" {
    resetMockState();
    initKernel();

    const result = semantos_register_callbacks(
        @ptrCast(&mock_storage_read),
        @ptrCast(&mock_storage_write),
        @ptrCast(&stub_identity_resolve),
        @ptrCast(&stub_identity_derive),
        @ptrCast(&stub_anchor_submit),
        @ptrCast(&stub_network_publish),
        @ptrCast(&stub_network_resolve),
    );
    try std.testing.expectEqual(SEMANTOS_OK, result);

    _ = semantos_shutdown();
}

// ── Test 7: Re-registration returns error ──

test "30B gate test 7: re-registration returns error" {
    resetMockState();
    initKernel();

    const r1 = semantos_register_callbacks(
        @ptrCast(&mock_storage_read),
        @ptrCast(&mock_storage_write),
        null,
        null,
        null,
        null,
        null,
    );
    try std.testing.expectEqual(SEMANTOS_OK, r1);

    const r2 = semantos_register_callbacks(
        @ptrCast(&mock_storage_read),
        @ptrCast(&mock_storage_write),
        null,
        null,
        null,
        null,
        null,
    );
    try std.testing.expectEqual(SEMANTOS_ERR_ALREADY_INIT, r2);

    _ = semantos_shutdown();
}

// ── Test 8: Callback error code propagates ──

test "30B gate test 8: callback error propagates" {
    resetMockState();
    initKernel();

    _ = semantos_register_callbacks(
        @ptrCast(&mock_storage_read),
        @ptrCast(&mock_storage_write_fail), // returns -42
        null,
        null,
        null,
        null,
        null,
    );

    const path = "/test";
    const data = "test";
    const result = semantos_cell_write(path.ptr, path.len, data.ptr, data.len);

    try std.testing.expectEqual(@as(i32, -42), result);

    _ = semantos_shutdown();
}

// ── Test 9: Null key pointer returns error (caught by exports.zig) ──

test "30B gate test 9: callback null-safety" {
    resetMockState();
    initKernel();

    _ = semantos_register_callbacks(
        @ptrCast(&mock_storage_read),
        @ptrCast(&mock_storage_write),
        null,
        null,
        null,
        null,
        null,
    );

    // Null path — should be caught by exports.zig before reaching callback
    const result = semantos_cell_write(null, 5, "test".ptr, 4);
    try std.testing.expectEqual(SEMANTOS_ERR_DENIED, result);
    try std.testing.expect(!mock_write_called);

    _ = semantos_shutdown();
}

// ── Test 10: Callbacks reset after shutdown, can re-register ──

test "30B gate test 10: callbacks reset after shutdown" {
    resetMockState();
    initKernel();

    _ = semantos_register_callbacks(
        @ptrCast(&mock_storage_read),
        @ptrCast(&mock_storage_write),
        null,
        null,
        null,
        null,
        null,
    );

    _ = semantos_shutdown();

    // Re-init and re-register should succeed
    initKernel();
    const result = semantos_register_callbacks(
        @ptrCast(&mock_storage_read),
        @ptrCast(&mock_storage_write),
        null,
        null,
        null,
        null,
        null,
    );
    try std.testing.expectEqual(SEMANTOS_OK, result);

    _ = semantos_shutdown();
}

```
