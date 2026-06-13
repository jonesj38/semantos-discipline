---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/module_loader.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.265144+00:00
---

# runtime/semantos-brain/src/module_loader.zig

```zig
// Phase Brain 1 — Hash-pinned WASM module loader + shape validator.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 1 deliverable 2).
//
// This is the trust-anchor enforcement point. Every WASM module the shell
// loads passes through `loadAndVerify()`, which:
//
//   1. Reads the file bytes (capped at MAX_MODULE_BYTES — 64MB).
//   2. Validates the WASM magic prefix `\0asm` + version 1.
//   3. Computes SHA-256 of the bytes.
//   4. Compares against the caller-supplied `expected_sha256`.
//   5. Returns the bytes only on a clean match — otherwise an error.
//
// The "loaded module" surface here is intentionally tiny: a struct holding
// the verified bytes + the file's hash + the path. Brain 2 layers actual
// wasmtime instantiation on top by calling `instantiate(loaded)` which
// passes those verified bytes to the runtime. The verifier is reusable —
// the same logic guards both the wallet engine and the headers verifier
// modules, and any future module the substrate loads.
//
// Threat model: a malicious operator (or a compromised host) replaces
// `wallet-engine.wasm` with a different binary that exfiltrates keys. The
// hash pin in the operator-edited config catches this; startup aborts
// with a hash-mismatch error pointing at the modified file. The operator
// who *intentionally* changed the binary must also intentionally update
// the hash — there's no automatic "trust whatever's on disk" path.

const std = @import("std");

/// Sanity cap on module size — a WASM module that big is almost certainly
/// pathological. Bump if a real use case needs it.
pub const MAX_MODULE_BYTES: u64 = 64 * 1024 * 1024;

/// WASM file format magic (LE-encoded `\0asm`) + version 1.
pub const WASM_MAGIC: [8]u8 = .{ 0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00 };

pub const LoaderError = error{
    file_not_found,
    file_too_large,
    not_wasm,
    hash_mismatch,
    io_failed,
    out_of_memory,
};

/// A verified module. The `bytes` slice is owned by the caller's allocator;
/// `deinit` frees it.
pub const LoadedModule = struct {
    /// Canonical name (matches the config object key).
    name: []const u8,
    /// Filesystem path the module was read from.
    path: []const u8,
    /// Verified WASM bytes — the hash-checked artifact. Brain 2 hands these
    /// to wasmtime for instantiation.
    bytes: []u8,
    /// SHA-256 of `bytes`. Always equals the caller's expected hash on
    /// a successful load (otherwise we returned an error).
    sha256: [32]u8,
    /// Allocator that owns `name`, `path`, and `bytes`.
    allocator: std.mem.Allocator,

    pub fn deinit(self: *LoadedModule) void {
        self.allocator.free(self.bytes);
        self.allocator.free(self.name);
        self.allocator.free(self.path);
    }
};

/// Compute SHA-256 of a byte slice. Pure helper; exposed so `brain hash
/// <module>` can print it for the operator to paste into the config.
pub fn computeSha256(bytes: []const u8) [32]u8 {
    var out: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &out, .{});
    return out;
}

/// Validate WASM magic + version. Returns false for any non-WASM input
/// (e.g., the operator pasted a Linux ELF, a Go binary, a shell script).
pub fn isValidWasmShape(bytes: []const u8) bool {
    if (bytes.len < WASM_MAGIC.len) return false;
    return std.mem.eql(u8, bytes[0..WASM_MAGIC.len], &WASM_MAGIC);
}

/// Read the file at `path` and verify it matches `expected_sha256`.
/// Returns a `LoadedModule` on success; the caller owns it.
pub fn loadAndVerify(
    allocator: std.mem.Allocator,
    name: []const u8,
    path: []const u8,
    expected_sha256: *const [32]u8,
) LoaderError!LoadedModule {
    const file = std.fs.cwd().openFile(path, .{}) catch return error.file_not_found;
    defer file.close();

    const stat = file.stat() catch return error.io_failed;
    if (stat.size > MAX_MODULE_BYTES) return error.file_too_large;

    const bytes = allocator.alloc(u8, stat.size) catch return error.out_of_memory;
    errdefer allocator.free(bytes);

    _ = file.readAll(bytes) catch return error.io_failed;

    if (!isValidWasmShape(bytes)) return error.not_wasm;

    const actual = computeSha256(bytes);
    if (!std.mem.eql(u8, &actual, expected_sha256)) {
        return error.hash_mismatch;
    }

    const name_dup = allocator.dupe(u8, name) catch return error.out_of_memory;
    errdefer allocator.free(name_dup);
    const path_dup = allocator.dupe(u8, path) catch return error.out_of_memory;
    errdefer allocator.free(path_dup);

    return .{
        .name = name_dup,
        .path = path_dup,
        .bytes = bytes,
        .sha256 = actual,
        .allocator = allocator,
    };
}

/// Convenience: in-memory verification path used by tests + the broker
/// when the bytes are already in hand. Same checks as `loadAndVerify` but
/// without the file I/O.
pub fn verifyBytes(
    bytes: []const u8,
    expected_sha256: *const [32]u8,
) LoaderError!void {
    if (!isValidWasmShape(bytes)) return error.not_wasm;
    const actual = computeSha256(bytes);
    if (!std.mem.eql(u8, &actual, expected_sha256)) {
        return error.hash_mismatch;
    }
}

/// Format a SHA-256 as the lowercase hex string the config + `brain hash`
/// CLI use. Caller frees the returned buffer.
pub fn formatHashHex(allocator: std.mem.Allocator, h: *const [32]u8) ![]u8 {
    var out = try allocator.alloc(u8, 64);
    const charset = "0123456789abcdef";
    for (h, 0..) |b, i| {
        out[i * 2 + 0] = charset[(b >> 4) & 0xf];
        out[i * 2 + 1] = charset[b & 0xf];
    }
    return out;
}

```
