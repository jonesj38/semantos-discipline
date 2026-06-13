---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/wrapped_dek_store.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.226859+00:00
---

# runtime/semantos-brain/src/wrapped_dek_store.zig

```zig
// W7.5 — Per-operator wrapped DEK storage.
//
// The brain holds the wrapped Data Encryption Key (DEK) as an opaque hex
// blob. The device generates a random DEK at provisioning time, derives a
// Key Encryption Key (KEK) from its BRC-42 universe, and wraps:
//
//   wrapped_dek = AES-256-GCM(key=KEK, plaintext=DEK)
//              = nonce(12 B) || ciphertext(32 B) || tag(16 B)  → 60 B → 120 hex chars
//
// The brain never sees the plaintext KEK or DEK. It stores the opaque blob
// and returns it to the device over the authenticated WSS channel (W7.4) so
// the device can unwrap locally.
//
// File: $data_dir/operators/<op_pkh16>/wrapped_dek
// Format: lowercase hex, no newline. Any even-length all-hex string accepted
//         (length is not enforced here — the device specifies it).
//
// PRD: docs/prd/ODDJOBZ-HOSTED-OPERATOR-STANDUP.md W7.5

const std = @import("std");

pub const DekError = error{
    /// Wrapped DEK file not found for this operator.
    not_found,
    /// File I/O error (read, write, or create).
    file_io,
    /// Stored content is not valid lowercase hex.
    bad_format,
    out_of_memory,
};

/// Canonical wrapped-DEK size in bytes: nonce(12) + ciphertext(32) + tag(16).
/// This is informational; the store does not enforce it to stay future-proof.
pub const WRAPPED_DEK_BYTES: usize = 60;
/// Hex-encoded length of the canonical wrapped DEK.
pub const WRAPPED_DEK_HEX_LEN: usize = WRAPPED_DEK_BYTES * 2;

/// Return the path to the operator's wrapped-dek file.
/// Caller frees the returned slice.
fn dekPath(allocator: std.mem.Allocator, data_dir: []const u8, op_pkh16: [16]u8) DekError![]u8 {
    return std.fs.path.join(
        allocator,
        &.{ data_dir, "operators", &op_pkh16, "wrapped_dek" },
    ) catch return DekError.out_of_memory;
}

/// Load the wrapped DEK for an operator.
/// Returns an owned hex string; caller frees it.
/// Returns `not_found` if no wrapped DEK has been stored yet.
pub fn load(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    op_pkh16: [16]u8,
) DekError![]u8 {
    const path = try dekPath(allocator, data_dir, op_pkh16);
    defer allocator.free(path);

    const file = std.fs.cwd().openFile(path, .{}) catch |e| switch (e) {
        error.FileNotFound => return DekError.not_found,
        else => return DekError.file_io,
    };
    defer file.close();

    const content = file.readToEndAlloc(allocator, 4096) catch return DekError.file_io;
    errdefer allocator.free(content);

    // Trim trailing whitespace (newline safety).
    const trimmed = std.mem.trim(u8, content, " \t\r\n");
    if (trimmed.len == 0 or trimmed.len % 2 != 0) {
        allocator.free(content);
        return DekError.bad_format;
    }
    for (trimmed) |c| {
        if (!isHexChar(c)) {
            allocator.free(content);
            return DekError.bad_format;
        }
    }

    // Shrink to trimmed length (re-slice of existing allocation is fine for
    // the caller's purposes — we dupe so the slice is independently owned).
    const owned = allocator.dupe(u8, trimmed) catch {
        allocator.free(content);
        return DekError.out_of_memory;
    };
    allocator.free(content);
    return owned;
}

/// Store the wrapped DEK for an operator.  Overwrites any existing value.
/// `wrapped_dek_hex` must be a non-empty even-length all-hex string.
pub fn save(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    op_pkh16: [16]u8,
    wrapped_dek_hex: []const u8,
) DekError!void {
    if (wrapped_dek_hex.len == 0 or wrapped_dek_hex.len % 2 != 0) return DekError.bad_format;
    for (wrapped_dek_hex) |c| {
        if (!isHexChar(c)) return DekError.bad_format;
    }

    // Ensure operator directory exists.
    const op_dir = std.fs.path.join(
        allocator,
        &.{ data_dir, "operators", &op_pkh16 },
    ) catch return DekError.out_of_memory;
    defer allocator.free(op_dir);

    std.fs.cwd().makePath(op_dir) catch return DekError.file_io;

    const path = try dekPath(allocator, data_dir, op_pkh16);
    defer allocator.free(path);

    const file = std.fs.cwd().createFile(path, .{ .truncate = true }) catch
        return DekError.file_io;
    defer file.close();
    file.writeAll(wrapped_dek_hex) catch return DekError.file_io;
}

/// Delete the wrapped DEK file for an operator (called on exit).
/// No-op if the file does not exist.
pub fn delete(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    op_pkh16: [16]u8,
) DekError!void {
    const path = try dekPath(allocator, data_dir, op_pkh16);
    defer allocator.free(path);

    std.fs.cwd().deleteFile(path) catch |e| switch (e) {
        error.FileNotFound => {},
        else => return DekError.file_io,
    };
}

fn isHexChar(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

// ── Inline tests ──────────────────────────────────────────────────────────

test "save and load round-trip" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    const allocator = std.testing.allocator;

    const op_pkh16: [16]u8 = "a3f7b2c1d4e5f6a7".*;
    const hex = "0102030405060708090a0b0c" ++ // nonce  12 B = 24 hex
        "deadbeefcafefed0" ** 4 ++ // ciphertext 32 B = 64 hex
        "11223344556677889900aabbccddeeff"; // tag   16 B = 32 hex
    // total: 24 + 64 + 32 = 120 hex chars (60 bytes)
    comptime std.debug.assert(hex.len == 120);

    try save(allocator, data_dir, op_pkh16, hex);
    const got = try load(allocator, data_dir, op_pkh16);
    defer allocator.free(got);
    try std.testing.expectEqualStrings(hex, got);
}

test "load returns not_found when file absent" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    const op_pkh16: [16]u8 = "a3f7b2c1d4e5f6a7".*;
    try std.testing.expectError(
        DekError.not_found,
        load(std.testing.allocator, data_dir, op_pkh16),
    );
}

test "save rejects odd-length hex" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    const op_pkh16: [16]u8 = "a3f7b2c1d4e5f6a7".*;
    try std.testing.expectError(
        DekError.bad_format,
        save(std.testing.allocator, data_dir, op_pkh16, "abc"), // odd length
    );
}

test "save rejects non-hex chars" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    const op_pkh16: [16]u8 = "a3f7b2c1d4e5f6a7".*;
    try std.testing.expectError(
        DekError.bad_format,
        save(std.testing.allocator, data_dir, op_pkh16, "zz"), // not hex
    );
}

test "delete is no-op when file absent" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    const op_pkh16: [16]u8 = "a3f7b2c1d4e5f6a7".*;
    try delete(std.testing.allocator, data_dir, op_pkh16); // must not error
}

test "save overwrites previous value" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);
    const allocator = std.testing.allocator;

    const op_pkh16: [16]u8 = "a3f7b2c1d4e5f6a7".*;
    try save(allocator, data_dir, op_pkh16, "aabb");
    try save(allocator, data_dir, op_pkh16, "ccdd");
    const got = try load(allocator, data_dir, op_pkh16);
    defer allocator.free(got);
    try std.testing.expectEqualStrings("ccdd", got);
}

```
