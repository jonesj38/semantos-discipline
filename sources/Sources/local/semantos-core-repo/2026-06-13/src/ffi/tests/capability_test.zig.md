---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/ffi/tests/capability_test.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.405902+00:00
---

# src/ffi/tests/capability_test.zig

```zig
// Phase 30C Gate Tests — Capability & Linearity FFI
//
// 10 tests covering: capability_check (domain grant, denial, expiry),
// capability_present (BRC-108 token generation, structure validation),
// linear_consume (exactly-once, double-consume rejection, non-LINEAR rejection),
// and null-pointer safety.

const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;
const exports = @import("exports");
const callbacks = @import("callbacks");

// Re-export C functions for direct calling
const semantos_init = exports.semantos_init;
const semantos_shutdown = exports.semantos_shutdown;
const semantos_cell_write = exports.semantos_cell_write;
const semantos_cell_read = exports.semantos_cell_read;
const semantos_capability_check = exports.semantos_capability_check;
const semantos_capability_present = exports.semantos_capability_present;
const semantos_linear_consume = exports.semantos_linear_consume;
const semantos_free = exports.semantos_free;
const semantos_register_callbacks = callbacks.semantos_register_callbacks;

// Error codes (match semantos.h)
const SEMANTOS_OK: i32 = 0;
const SEMANTOS_ERR_NOT_FOUND: i32 = -1;
const SEMANTOS_ERR_ALREADY_CONSUMED: i32 = -3;
const SEMANTOS_ERR_DENIED: i32 = -8;
const SEMANTOS_ERR_EXPIRED: i32 = -9;

// ── Multi-key mock storage ──
// Supports multiple key-value pairs for linear_consume tests
// (needs to read cells AND write/read consumption records).

const MAX_MOCK_ENTRIES = 16;

var mock_kv_keys: [MAX_MOCK_ENTRIES][256]u8 = undefined;
var mock_kv_key_lens: [MAX_MOCK_ENTRIES]usize = [_]usize{0} ** MAX_MOCK_ENTRIES;
var mock_kv_values: [MAX_MOCK_ENTRIES][1024]u8 = undefined;
var mock_kv_value_lens: [MAX_MOCK_ENTRIES]usize = [_]usize{0} ** MAX_MOCK_ENTRIES;
var mock_kv_count: usize = 0;

fn findMockEntry(key: []const u8) ?usize {
    for (0..mock_kv_count) |i| {
        if (mock_kv_key_lens[i] == key.len and
            std.mem.eql(u8, mock_kv_keys[i][0..mock_kv_key_lens[i]], key))
        {
            return i;
        }
    }
    return null;
}

fn mock_storage_write(
    path: [*]const u8,
    path_len: usize,
    data: [*]const u8,
    data_len: usize,
) callconv(.c) i32 {
    const key = path[0..path_len];

    // Update existing entry
    if (findMockEntry(key)) |idx| {
        if (data_len > 1024) return SEMANTOS_ERR_DENIED;
        @memcpy(mock_kv_values[idx][0..data_len], data[0..data_len]);
        mock_kv_value_lens[idx] = data_len;
        return SEMANTOS_OK;
    }

    // New entry
    if (mock_kv_count >= MAX_MOCK_ENTRIES) return SEMANTOS_ERR_DENIED;
    if (path_len > 256 or data_len > 1024) return SEMANTOS_ERR_DENIED;

    const idx = mock_kv_count;
    @memcpy(mock_kv_keys[idx][0..path_len], key);
    mock_kv_key_lens[idx] = path_len;
    @memcpy(mock_kv_values[idx][0..data_len], data[0..data_len]);
    mock_kv_value_lens[idx] = data_len;
    mock_kv_count += 1;
    return SEMANTOS_OK;
}

fn mock_storage_read(
    path: [*]const u8,
    path_len: usize,
    out_data: [*]u8,
    inout_len: *usize,
) callconv(.c) i32 {
    const key = path[0..path_len];

    const idx = findMockEntry(key) orelse return SEMANTOS_ERR_NOT_FOUND;
    const val_len = mock_kv_value_lens[idx];

    if (inout_len.* < val_len) {
        inout_len.* = val_len;
        return -6; // BUFFER_TOO_SMALL
    }
    @memcpy(out_data[0..val_len], mock_kv_values[idx][0..val_len]);
    inout_len.* = val_len;
    return SEMANTOS_OK;
}

// ── Configurable identity mock ──

var mock_cert_json_buf: [512]u8 = undefined;
var mock_cert_json_len: usize = 0;
var mock_identity_resolve_called: bool = false;

fn setMockCertJson(json: []const u8) void {
    @memcpy(mock_cert_json_buf[0..json.len], json);
    mock_cert_json_len = json.len;
}

fn mock_identity_resolve(
    _: [*]const u8,
    _: usize,
    out_json: [*]u8,
    inout_len: *usize,
) callconv(.c) i32 {
    mock_identity_resolve_called = true;
    if (inout_len.* < mock_cert_json_len) {
        inout_len.* = mock_cert_json_len;
        return -6; // BUFFER_TOO_SMALL
    }
    @memcpy(out_json[0..mock_cert_json_len], mock_cert_json_buf[0..mock_cert_json_len]);
    inout_len.* = mock_cert_json_len;
    return SEMANTOS_OK;
}

// ── Cell builder helpers ──

fn makeCell(linearity: u32) [1024]u8 {
    var cell: [1024]u8 = [_]u8{0} ** 1024;
    // Magic bytes at offset 0
    cell[0] = 0xEF;
    cell[1] = 0xBE;
    cell[2] = 0xAD;
    cell[3] = 0xDE;
    cell[4] = 0xBE;
    cell[5] = 0xBA;
    cell[6] = 0xFE;
    cell[7] = 0xCA;
    // Linearity at offset 16 (4 bytes LE)
    std.mem.writeInt(u32, cell[16..20], linearity, .little);
    // Domain flag at offset 24
    std.mem.writeInt(u32, cell[24..28], 5, .little);
    return cell;
}

// ── Reset and init helpers ──

fn resetMockState() void {
    mock_kv_count = 0;
    for (0..MAX_MOCK_ENTRIES) |i| {
        mock_kv_key_lens[i] = 0;
        mock_kv_value_lens[i] = 0;
    }
    mock_cert_json_len = 0;
    mock_identity_resolve_called = false;
}

fn initKernel() void {
    const config = "{\"version\":\"0.30.0\"}";
    _ = semantos_init(config.ptr, config.len);
}

fn registerAllCallbacks() void {
    _ = semantos_register_callbacks(
        @ptrCast(&mock_storage_read),
        @ptrCast(&mock_storage_write),
        @ptrCast(&mock_identity_resolve),
        null, // identity_derive not needed
        null,
        null,
        null,
    );
}

fn storeMockCell(path: []const u8, cell: []const u8) void {
    _ = mock_storage_write(path.ptr, path.len, cell.ptr, cell.len);
}

// ── T1: capability_check returns 0 for granted domain flag ──

test "30C-T1: capability_check returns OK for granted domain" {
    resetMockState();
    initKernel();
    registerAllCallbacks();

    // Certificate valid for 24 hours, domain flag = 5
    const now = std.time.milliTimestamp();
    var json_buf: [256]u8 = undefined;
    const json = std.fmt.bufPrint(&json_buf, "{{\"certId\":\"abc123\",\"domainFlag\":5,\"createdAt\":{d},\"ttl\":86400000}}", .{now - 1000}) catch unreachable;
    setMockCertJson(json);

    const cert = "test-cert-id";
    const result = semantos_capability_check(cert.ptr, cert.len, 5);
    try std.testing.expectEqual(SEMANTOS_OK, result);
    try std.testing.expect(mock_identity_resolve_called);

    _ = semantos_shutdown();
}

// ── T2: capability_check returns DENIED for ungranted domain flag ──

test "30C-T2: capability_check returns DENIED for domain mismatch" {
    resetMockState();
    initKernel();
    registerAllCallbacks();

    const now = std.time.milliTimestamp();
    var json_buf: [256]u8 = undefined;
    const json = std.fmt.bufPrint(&json_buf, "{{\"certId\":\"abc123\",\"domainFlag\":5,\"createdAt\":{d},\"ttl\":86400000}}", .{now - 1000}) catch unreachable;
    setMockCertJson(json);

    const cert = "test-cert-id";
    // Request domain 7 but cert has domain 5
    const result = semantos_capability_check(cert.ptr, cert.len, 7);
    try std.testing.expectEqual(SEMANTOS_ERR_DENIED, result);

    _ = semantos_shutdown();
}

// ── T3: capability_check returns EXPIRED for expired cert ──

test "30C-T3: capability_check returns EXPIRED for expired cert" {
    resetMockState();
    initKernel();
    registerAllCallbacks();

    // createdAt=0, ttl=1 → expired since Unix epoch + 1ms
    const json = "{\"certId\":\"abc123\",\"domainFlag\":5,\"createdAt\":0,\"ttl\":1}";
    setMockCertJson(json);

    const cert = "test-cert-id";
    const result = semantos_capability_check(cert.ptr, cert.len, 5);
    try std.testing.expectEqual(SEMANTOS_ERR_EXPIRED, result);

    _ = semantos_shutdown();
}

// ── T4: capability_present returns valid BRC-108 token bytes ──

test "30C-T4: capability_present returns non-empty kernel-allocated token" {
    resetMockState();
    initKernel();
    registerAllCallbacks();

    const now = std.time.milliTimestamp();
    var json_buf: [256]u8 = undefined;
    const json = std.fmt.bufPrint(&json_buf, "{{\"certId\":\"abc123\",\"domainFlag\":5,\"createdAt\":{d},\"ttl\":86400000}}", .{now - 1000}) catch unreachable;
    setMockCertJson(json);

    const cert = "test-cert-id";
    var token_ptr: [*]u8 = undefined;
    var token_len: usize = 0;
    const result = semantos_capability_present(cert.ptr, cert.len, 5, &token_ptr, &token_len);

    try std.testing.expectEqual(SEMANTOS_OK, result);
    try std.testing.expect(token_len > 0);
    // Expected: 6 (magic) + 12 (cert) + 4 (flag) + 32 (hash) = 54
    try std.testing.expectEqual(@as(usize, 54), token_len);

    // Verify BRC-108 magic
    const magic = "BRC108";
    try std.testing.expectEqualSlices(u8, magic, token_ptr[0..6]);

    // Free kernel-allocated memory
    semantos_free(token_ptr, token_len);

    _ = semantos_shutdown();
}

// ── T5: Token structure can be verified externally ──

test "30C-T5: capability_present token has valid BRC-108 structure" {
    resetMockState();
    initKernel();
    registerAllCallbacks();

    const now = std.time.milliTimestamp();
    var json_buf: [256]u8 = undefined;
    const json = std.fmt.bufPrint(&json_buf, "{{\"certId\":\"abc123\",\"domainFlag\":5,\"createdAt\":{d},\"ttl\":86400000}}", .{now - 1000}) catch unreachable;
    setMockCertJson(json);

    const cert = "test-cert-id";
    const cert_len = cert.len;
    const domain_flag: u32 = 5;

    var token_ptr: [*]u8 = undefined;
    var token_len: usize = 0;
    const result = semantos_capability_present(cert.ptr, cert_len, domain_flag, &token_ptr, &token_len);
    try std.testing.expectEqual(SEMANTOS_OK, result);

    const token = token_ptr[0..token_len];

    // Verify cert_id bytes at offset 6
    try std.testing.expectEqualSlices(u8, cert, token[6 .. 6 + cert_len]);

    // Verify domain_flag LE at offset 6 + cert_len
    const flag_offset = 6 + cert_len;
    const extracted_flag = std.mem.readInt(u32, token[flag_offset..][0..4], .little);
    try std.testing.expectEqual(domain_flag, extracted_flag);

    // Recompute SHA-256(cert_id ++ domain_flag_le) and verify integrity hash
    var hasher = Sha256.init(.{});
    hasher.update(cert);
    var flag_le: [4]u8 = undefined;
    std.mem.writeInt(u32, &flag_le, domain_flag, .little);
    hasher.update(&flag_le);
    var expected_hash: [32]u8 = undefined;
    hasher.final(&expected_hash);

    const hash_offset = flag_offset + 4;
    try std.testing.expectEqualSlices(u8, &expected_hash, token[hash_offset .. hash_offset + 32]);

    semantos_free(token_ptr, token_len);
    _ = semantos_shutdown();
}

// ── T6: linear_consume returns 0 on first call ──

test "30C-T6: linear_consume succeeds on first consumption" {
    resetMockState();
    initKernel();
    registerAllCallbacks();

    // Store a LINEAR cell (linearity=1)
    const cell = makeCell(1);
    storeMockCell("/test/linear-cell", &cell);

    const cert = "consumer-cert-abc";
    const result = semantos_linear_consume("/test/linear-cell".ptr, "/test/linear-cell".len, cert.ptr, cert.len);
    try std.testing.expectEqual(SEMANTOS_OK, result);

    _ = semantos_shutdown();
}

// ── T7: linear_consume returns ALREADY_CONSUMED on second call ──

test "30C-T7: linear_consume returns ALREADY_CONSUMED on double consume" {
    resetMockState();
    initKernel();
    registerAllCallbacks();

    const cell = makeCell(1);
    storeMockCell("/test/linear-cell", &cell);

    const cert = "consumer-cert-abc";
    const path = "/test/linear-cell";

    // First consume succeeds
    const r1 = semantos_linear_consume(path.ptr, path.len, cert.ptr, cert.len);
    try std.testing.expectEqual(SEMANTOS_OK, r1);

    // Second consume rejected
    const r2 = semantos_linear_consume(path.ptr, path.len, cert.ptr, cert.len);
    try std.testing.expectEqual(SEMANTOS_ERR_ALREADY_CONSUMED, r2);

    _ = semantos_shutdown();
}

// ── T8: Atomicity — consumption record exists in storage after consume ──

test "30C-T8: linear consumption record persists in storage" {
    resetMockState();
    initKernel();
    registerAllCallbacks();

    const cell = makeCell(1);
    storeMockCell("/test/atomic-cell", &cell);

    const cert = "consumer-cert-xyz";
    const path = "/test/atomic-cell";

    // Consume
    const r = semantos_linear_consume(path.ptr, path.len, cert.ptr, cert.len);
    try std.testing.expectEqual(SEMANTOS_OK, r);

    // Verify consumption record was written to mock storage.
    // The key is /.consumed/{sha256hex(path)}/{sha256hex(cert)}.
    // We verify by checking mock_kv_count increased (cell + record = 2 entries).
    // The consumption record should be findable.
    var path_hash: [32]u8 = undefined;
    Sha256.hash(path, &path_hash, .{});
    var cert_hash: [32]u8 = undefined;
    Sha256.hash(cert, &cert_hash, .{});

    // Build expected consumption key
    const hex_chars = "0123456789abcdef";
    var expected_key: [140]u8 = undefined;
    const prefix = "/.consumed/";
    @memcpy(expected_key[0..prefix.len], prefix);
    for (path_hash, 0..) |b, idx| {
        expected_key[prefix.len + idx * 2] = hex_chars[b >> 4];
        expected_key[prefix.len + idx * 2 + 1] = hex_chars[b & 0x0f];
    }
    expected_key[prefix.len + 64] = '/';
    for (cert_hash, 0..) |b, idx| {
        expected_key[prefix.len + 65 + idx * 2] = hex_chars[b >> 4];
        expected_key[prefix.len + 65 + idx * 2 + 1] = hex_chars[b & 0x0f];
    }

    // Look up consumption record in mock storage
    const idx = findMockEntry(&expected_key);
    try std.testing.expect(idx != null);
    // Marker byte should be 0x01
    try std.testing.expectEqual(@as(u8, 0x01), mock_kv_values[idx.?][0]);

    _ = semantos_shutdown();
}

// ── T9: capability_check with null cert_id returns error (not crash) ──

test "30C-T9: capability_check with null cert_id returns DENIED" {
    resetMockState();
    initKernel();
    registerAllCallbacks();

    const result = semantos_capability_check(null, 10, 5);
    try std.testing.expectEqual(SEMANTOS_ERR_DENIED, result);

    _ = semantos_shutdown();
}

// ── T10: linear_consume with non-LINEAR cell returns error ──

test "30C-T10: linear_consume rejects AFFINE cell" {
    resetMockState();
    initKernel();
    registerAllCallbacks();

    // Store an AFFINE cell (linearity=2)
    const cell = makeCell(2);
    storeMockCell("/test/affine-cell", &cell);

    const cert = "consumer-cert-abc";
    const result = semantos_linear_consume("/test/affine-cell".ptr, "/test/affine-cell".len, cert.ptr, cert.len);
    try std.testing.expectEqual(SEMANTOS_ERR_DENIED, result);

    _ = semantos_shutdown();
}

```
