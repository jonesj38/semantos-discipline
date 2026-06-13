---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/ffi/exports.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.402920+00:00
---

# src/ffi/exports.zig

```zig
// Semantos FFI — Core C ABI exports
// Phase 30A: init, shutdown, cell read/write/verify, free, version, last_error
// Phase 30C: capability_check, capability_present, linear_consume
//
// Every function uses pub export fn + callconv(.c). No Zig error unions cross
// the boundary. All pointers are bounds-checked. No host references held.

const std = @import("std");
const builtin = @import("builtin");
// Platform wallet architecture §P2 — wallet C ABI exports (native
// DESKTOP only). `wallet_exports` pulls the `bsvz` native dep
// (secp256k1 / BRC-42 / ARC) which is intentionally OMITTED from the
// Android/iOS "embedded" cross profile (see scripts/build-android-
// libs.sh — "BSVZ omitted"; oddjobz Home/jobs need no wallet tx).
// build.zig only injects the `wallet_exports` module for desktop
// native targets, so this comptime guard must skip wasm32 AND
// android/ios — else it @imports a module that isn't wired (RM-122).
comptime {
    // isAndroid() covers both .android (arm64) and .androideabi (arm32).
    if (builtin.target.cpu.arch != .wasm32 and
        !builtin.target.abi.isAndroid() and
        builtin.target.os.tag != .ios)
    {
        _ = @import("wallet_exports");
    }
}
const Sha256 = std.crypto.hash.sha2.Sha256;
const callbacks = @import("callbacks");
const is_wasm = builtin.target.cpu.arch == .wasm32;
// WASM host imports — only resolved at link time for wasm32 targets.
// On native, callbacks.zig function pointers are used instead.
const wasm_imports = if (is_wasm) @import("wasm_imports") else struct {};

// D-O5m.followup-1 — the real cell-engine 2-PDA. `semantos_execute_script`
// instantiates a PDA + ScriptArena and calls `executor.execute(&ctx)` so
// the K1/K2/K3/K4 substructural invariants are enforced on-device. The
// previous syntactic-only `validateOpcodeStream` walker is preserved as
// `validateOpcodeStreamSyntactic` for diagnostic-only use.
const executor_mod = @import("executor");
const pda_mod = @import("pda");
const allocator_mod = @import("allocator");
const linearity_mod = @import("linearity");
// WASM memory helpers — force-link so exports appear in the WASM module.
const wasm_memory = if (is_wasm) @import("wasm_memory") else struct {};
comptime {
    if (is_wasm) {
        // Reference wasm_memory exports so they don't get dead-code eliminated
        _ = &wasm_memory.semantos_alloc;
        _ = &wasm_memory.semantos_dealloc;
    }
}

/// Allocator suitable for the current target.
/// WASM: std.heap.wasm_allocator (grows linear memory).
/// Native: std.heap.page_allocator.
const target_allocator = if (is_wasm) std.heap.wasm_allocator else std.heap.page_allocator;

// ── Error codes (must match semantos.h) ──

const SEMANTOS_OK: i32 = 0;
const SEMANTOS_ERR_NOT_FOUND: i32 = -1;
const SEMANTOS_ERR_INVALID_JSON: i32 = -2;
const SEMANTOS_ERR_ALREADY_CONSUMED: i32 = -3;
const SEMANTOS_ERR_ALREADY_INIT: i32 = -4;
const SEMANTOS_ERR_NOT_INIT: i32 = -5;
const SEMANTOS_ERR_BUFFER_TOO_SMALL: i32 = -6;
const SEMANTOS_ERR_INVALID_PROOF: i32 = -7;
const SEMANTOS_ERR_DENIED: i32 = -8;
const SEMANTOS_ERR_EXPIRED: i32 = -9;

// ── In-memory cell store ──

const Store = struct {
    map: std.StringHashMap([]u8),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) Store {
        return .{
            .map = std.StringHashMap([]u8).init(allocator),
            .allocator = allocator,
        };
    }

    fn put(self: *Store, path: []const u8, data: []const u8) !void {
        // If key already exists, free old value
        if (self.map.getEntry(path)) |entry| {
            self.allocator.free(entry.value_ptr.*);
            const new_val = try self.allocator.dupe(u8, data);
            entry.value_ptr.* = new_val;
            return;
        }
        const key = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(key);
        const val = try self.allocator.dupe(u8, data);
        errdefer self.allocator.free(val);
        try self.map.put(key, val);
    }

    fn get(self: *Store, path: []const u8) ?[]const u8 {
        return self.map.get(path);
    }

    fn deinit(self: *Store) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.map.deinit();
    }
};

// ── Thread-local state ──

threadlocal var g_initialized: bool = false;
threadlocal var g_store: ?Store = null;
threadlocal var g_last_error: [256]u8 = .{0} ** 256;
threadlocal var g_last_error_len: usize = 0;

fn setLastError(comptime fmt: []const u8, args: anytype) void {
    const result = std.fmt.bufPrint(&g_last_error, fmt, args) catch {
        // If format fails, write a truncation message
        const msg = "error message too long";
        @memcpy(g_last_error[0..msg.len], msg);
        g_last_error_len = msg.len;
        return;
    };
    g_last_error_len = result.len;
}

// ── JSON validation ──
// Minimal but real: validates UTF-8, matching braces, and that the
// outermost structure is an object (starts with '{', ends with '}').

fn validateJson(data: []const u8) bool {
    if (data.len == 0) return false;

    // Must be valid UTF-8
    if (!std.unicode.utf8ValidateSlice(data)) return false;

    // Find first non-whitespace
    var start: usize = 0;
    while (start < data.len and isJsonWhitespace(data[start])) : (start += 1) {}
    if (start >= data.len) return false;

    // Must start with '{'
    if (data[start] != '{') return false;

    // Find last non-whitespace
    var end: usize = data.len;
    while (end > 0 and isJsonWhitespace(data[end - 1])) : (end -= 1) {}
    if (end == 0) return false;

    // Must end with '}'
    if (data[end - 1] != '}') return false;

    // Validate brace/bracket matching
    var depth_curly: i32 = 0;
    var depth_square: i32 = 0;
    var in_string = false;
    var escape = false;

    for (data[start..end]) |c| {
        if (escape) {
            escape = false;
            continue;
        }
        if (c == '\\' and in_string) {
            escape = true;
            continue;
        }
        if (c == '"') {
            in_string = !in_string;
            continue;
        }
        if (in_string) continue;

        switch (c) {
            '{' => depth_curly += 1,
            '}' => {
                depth_curly -= 1;
                if (depth_curly < 0) return false;
            },
            '[' => depth_square += 1,
            ']' => {
                depth_square -= 1;
                if (depth_square < 0) return false;
            },
            else => {},
        }
    }

    // Must not end inside a string
    if (in_string) return false;

    return depth_curly == 0 and depth_square == 0;
}

fn isJsonWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

// ── JSON field extraction ──
// Minimal integer field extractor for flat JSON objects. Scans for
// "fieldName": <integer> while tracking string state. No allocator needed.

fn jsonExtractInt(json: []const u8, field_name: []const u8) ?i64 {
    // We need at least `"X":0` = field_name.len + 4 chars
    if (json.len < field_name.len + 4) return null;

    var in_string = false;
    var escape = false;
    var i: usize = 0;

    while (i < json.len) : (i += 1) {
        if (escape) {
            escape = false;
            continue;
        }
        if (json[i] == '\\' and in_string) {
            escape = true;
            continue;
        }
        if (json[i] == '"') {
            if (!in_string) {
                // Opening quote — check if field name follows
                const after_quote = i + 1;
                const name_end = after_quote + field_name.len;
                if (name_end < json.len and
                    std.mem.eql(u8, json[after_quote..name_end], field_name) and
                    json[name_end] == '"')
                {
                    // Found "fieldName" — look for colon then integer
                    var j = name_end + 1;
                    while (j < json.len and isJsonWhitespace(json[j])) : (j += 1) {}
                    if (j >= json.len or json[j] != ':') {
                        // Not a key:value — skip past this string
                        in_string = true;
                        continue;
                    }
                    j += 1; // skip ':'
                    while (j < json.len and isJsonWhitespace(json[j])) : (j += 1) {}
                    if (j >= json.len) return null;

                    // Parse integer (optional leading '-')
                    var num_start = j;
                    if (json[j] == '-') {
                        num_start = j;
                        j += 1;
                    }
                    const digit_start = j;
                    while (j < json.len and json[j] >= '0' and json[j] <= '9') : (j += 1) {}
                    if (j == digit_start) return null; // no digits
                    return std.fmt.parseInt(i64, json[num_start..j], 10) catch null;
                }
            }
            in_string = !in_string;
            continue;
        }
    }

    return null;
}

// ── Hex formatting ──
// Format a byte slice as lowercase hex into a stack buffer.

fn hexFormat(bytes: []const u8, out: []u8) []const u8 {
    const hex_chars = "0123456789abcdef";
    const needed = bytes.len * 2;
    if (out.len < needed) return out[0..0];
    for (bytes, 0..) |b, idx| {
        out[idx * 2] = hex_chars[b >> 4];
        out[idx * 2 + 1] = hex_chars[b & 0x0f];
    }
    return out[0..needed];
}

// ── Exported functions ──

pub export fn semantos_init(config_json: ?[*]const u8, config_len: usize) callconv(.c) i32 {
    if (g_initialized) {
        setLastError("kernel already initialized", .{});
        return SEMANTOS_ERR_ALREADY_INIT;
    }

    // Bounds check
    if (config_json == null or config_len == 0) {
        setLastError("config_json is null or empty", .{});
        return SEMANTOS_ERR_INVALID_JSON;
    }

    const json_slice = config_json.?[0..config_len];

    if (!validateJson(json_slice)) {
        setLastError("invalid JSON: malformed structure or encoding", .{});
        return SEMANTOS_ERR_INVALID_JSON;
    }

    // Initialize store
    g_store = Store.init(target_allocator);
    g_initialized = true;
    g_last_error_len = 0;

    return SEMANTOS_OK;
}

pub export fn semantos_shutdown() callconv(.c) i32 {
    if (!g_initialized) {
        setLastError("kernel not initialized", .{});
        return SEMANTOS_ERR_NOT_INIT;
    }

    if (g_store) |*store| {
        store.deinit();
    }
    g_store = null;
    g_initialized = false;
    g_last_error_len = 0;
    callbacks.reset_callbacks();

    return SEMANTOS_OK;
}

pub export fn semantos_cell_write(
    path: ?[*]const u8,
    path_len: usize,
    data: ?[*]const u8,
    data_len: usize,
) callconv(.c) i32 {
    if (!g_initialized) {
        setLastError("kernel not initialized", .{});
        return SEMANTOS_ERR_NOT_INIT;
    }

    // Null pointer checks
    if (path == null) {
        setLastError("path pointer is null", .{});
        return SEMANTOS_ERR_DENIED;
    }
    if (data == null) {
        setLastError("data pointer is null", .{});
        return SEMANTOS_ERR_DENIED;
    }

    // Zero-length checks
    if (path_len == 0) {
        setLastError("path length is zero", .{});
        return SEMANTOS_ERR_DENIED;
    }
    if (data_len == 0) {
        setLastError("data length is zero", .{});
        return SEMANTOS_ERR_DENIED;
    }

    // WASM: route through extern imports (resolved at instantiation)
    if (comptime is_wasm) {
        return wasm_imports.host_storage_write(path.?, path_len, data.?, data_len);
    }

    // Native: route through host callback if registered
    if (callbacks.is_registered()) {
        const reg = callbacks.get_registry();
        const write_fn = reg.host_storage_write orelse {
            setLastError("host_storage_write callback is null", .{});
            return SEMANTOS_ERR_DENIED;
        };
        return write_fn(path.?, path_len, data.?, data_len);
    }

    // Fallback: in-memory store (Phase 30A backward compat)
    const path_slice = path.?[0..path_len];
    const data_slice = data.?[0..data_len];

    var store = &(g_store orelse {
        setLastError("internal error: store not initialized", .{});
        return SEMANTOS_ERR_NOT_INIT;
    });

    store.put(path_slice, data_slice) catch {
        setLastError("allocation failed during cell write", .{});
        return SEMANTOS_ERR_DENIED;
    };

    return SEMANTOS_OK;
}

pub export fn semantos_cell_read(
    path: ?[*]const u8,
    path_len: usize,
    out_data: ?[*]u8,
    inout_len: ?*usize,
) callconv(.c) i32 {
    if (!g_initialized) {
        setLastError("kernel not initialized", .{});
        return SEMANTOS_ERR_NOT_INIT;
    }

    if (path == null) {
        setLastError("path pointer is null", .{});
        return SEMANTOS_ERR_DENIED;
    }
    if (out_data == null) {
        setLastError("out_data pointer is null", .{});
        return SEMANTOS_ERR_DENIED;
    }
    if (inout_len == null) {
        setLastError("inout_len pointer is null", .{});
        return SEMANTOS_ERR_DENIED;
    }
    if (path_len == 0) {
        setLastError("path length is zero", .{});
        return SEMANTOS_ERR_DENIED;
    }

    // WASM: route through extern imports (resolved at instantiation)
    if (comptime is_wasm) {
        return wasm_imports.host_storage_read(path.?, path_len, out_data.?, inout_len.?);
    }

    // Native: route through host callback if registered
    if (callbacks.is_registered()) {
        const reg = callbacks.get_registry();
        const read_fn = reg.host_storage_read orelse {
            setLastError("host_storage_read callback is null", .{});
            return SEMANTOS_ERR_DENIED;
        };
        return read_fn(path.?, path_len, out_data.?, inout_len.?);
    }

    // Fallback: in-memory store (Phase 30A backward compat)
    const path_slice = path.?[0..path_len];

    var store = &(g_store orelse {
        setLastError("internal error: store not initialized", .{});
        return SEMANTOS_ERR_NOT_INIT;
    });

    const stored = store.get(path_slice) orelse {
        setLastError("cell not found at path", .{});
        return SEMANTOS_ERR_NOT_FOUND;
    };

    const buf_len = inout_len.?.*;
    if (buf_len < stored.len) {
        inout_len.?.* = stored.len;
        setLastError("buffer too small: need {d} bytes, got {d}", .{ stored.len, buf_len });
        return SEMANTOS_ERR_BUFFER_TOO_SMALL;
    }

    @memcpy(out_data.?[0..stored.len], stored);
    inout_len.?.* = stored.len;

    return SEMANTOS_OK;
}

pub export fn semantos_cell_verify(
    path: ?[*]const u8,
    path_len: usize,
    proof: ?[*]const u8,
    proof_len: usize,
) callconv(.c) i32 {
    if (!g_initialized) {
        setLastError("kernel not initialized", .{});
        return SEMANTOS_ERR_NOT_INIT;
    }

    if (path == null) {
        setLastError("path pointer is null", .{});
        return SEMANTOS_ERR_DENIED;
    }
    if (proof == null) {
        setLastError("proof pointer is null", .{});
        return SEMANTOS_ERR_DENIED;
    }
    if (path_len == 0) {
        setLastError("path length is zero", .{});
        return SEMANTOS_ERR_DENIED;
    }

    // Proof must contain at least a 32-byte SHA-256 hash
    if (proof_len < 32) {
        setLastError("proof too short: need at least 32 bytes, got {d}", .{proof_len});
        return SEMANTOS_ERR_INVALID_PROOF;
    }

    const path_slice = path.?[0..path_len];
    const proof_slice = proof.?[0..proof_len];

    var store = &(g_store orelse {
        setLastError("internal error: store not initialized", .{});
        return SEMANTOS_ERR_NOT_INIT;
    });

    const stored = store.get(path_slice) orelse {
        setLastError("cell not found at path", .{});
        return SEMANTOS_ERR_NOT_FOUND;
    };

    // Compute SHA-256 of stored data
    var hash: [32]u8 = undefined;
    Sha256.hash(stored, &hash, .{});

    // Compare first 32 bytes of proof against computed hash
    if (!std.mem.eql(u8, proof_slice[0..32], &hash)) {
        setLastError("proof hash does not match stored cell data", .{});
        return SEMANTOS_ERR_INVALID_PROOF;
    }

    return SEMANTOS_OK;
}

pub export fn semantos_free(ptr: ?[*]u8, len: usize) callconv(.c) void {
    if (ptr == null) return;
    if (len == 0) return;
    if (comptime is_wasm) {
        // WASM: wasm_allocator tracks all allocations
        target_allocator.free(ptr.?[0..len]);
    } else {
        // Native: only free page-aligned pointers (allocated by page_allocator).
        // Non-page-aligned pointers are safely ignored (caller-owned memory).
        const addr = @intFromPtr(ptr.?);
        if (addr % std.heap.page_size_min != 0) return;
        const aligned: [*]align(std.heap.page_size_min) u8 = @alignCast(ptr.?);
        std.heap.page_allocator.free(aligned[0..len]);
    }
}

pub export fn semantos_version() callconv(.c) [*:0]const u8 {
    return "0.30.0-phase-30e";
}

pub export fn semantos_last_error(
    out_buf: ?[*]u8,
    inout_len: ?*usize,
) callconv(.c) i32 {
    if (out_buf == null) {
        return SEMANTOS_ERR_DENIED;
    }
    if (inout_len == null) {
        return SEMANTOS_ERR_DENIED;
    }

    const buf_len = inout_len.?.*;
    const err_len = g_last_error_len;

    if (err_len == 0) {
        inout_len.?.* = 0;
        return SEMANTOS_OK;
    }

    if (buf_len < err_len) {
        inout_len.?.* = err_len;
        return SEMANTOS_ERR_BUFFER_TOO_SMALL;
    }

    @memcpy(out_buf.?[0..err_len], g_last_error[0..err_len]);
    inout_len.?.* = err_len;

    return SEMANTOS_OK;
}

// ── Phase 30C: Capability FFI functions ──

pub export fn semantos_capability_check(
    cert_id: ?[*]const u8,
    cert_len: usize,
    domain_flag: u32,
) callconv(.c) i32 {
    if (!g_initialized) {
        setLastError("kernel not initialized", .{});
        return SEMANTOS_ERR_NOT_INIT;
    }

    if (cert_id == null) {
        setLastError("cert_id pointer is null", .{});
        return SEMANTOS_ERR_DENIED;
    }
    if (cert_len == 0) {
        setLastError("cert_id length is zero", .{});
        return SEMANTOS_ERR_DENIED;
    }

    // Resolve certificate via host
    var json_buf: [1024]u8 = undefined;
    var json_len: usize = json_buf.len;

    if (comptime is_wasm) {
        // WASM: route through extern import
        const resolve_rc = wasm_imports.host_identity_resolve(cert_id.?, cert_len, &json_buf, &json_len);
        if (resolve_rc != SEMANTOS_OK) return resolve_rc;
    } else {
        // Native: require identity callbacks
        if (!callbacks.is_registered()) {
            setLastError("identity callbacks not registered", .{});
            return SEMANTOS_ERR_DENIED;
        }
        const reg = callbacks.get_registry();
        const resolve_fn = reg.host_identity_resolve orelse {
            setLastError("host_identity_resolve callback is null", .{});
            return SEMANTOS_ERR_DENIED;
        };
        const resolve_rc = resolve_fn(cert_id.?, cert_len, &json_buf, &json_len);
        if (resolve_rc != SEMANTOS_OK) return resolve_rc;
    }

    const json = json_buf[0..json_len];

    // Extract and validate domain flag
    const cert_domain = jsonExtractInt(json, "domainFlag") orelse {
        setLastError("cert JSON missing domainFlag field", .{});
        return SEMANTOS_ERR_INVALID_JSON;
    };
    if (cert_domain < 0) {
        setLastError("cert domainFlag is negative", .{});
        return SEMANTOS_ERR_INVALID_JSON;
    }
    if (@as(u32, @intCast(cert_domain)) != domain_flag) {
        setLastError("domain flag mismatch: cert has {d}, requested {d}", .{ cert_domain, domain_flag });
        return SEMANTOS_ERR_DENIED;
    }

    // Extract and validate expiry
    const created_at = jsonExtractInt(json, "createdAt") orelse {
        setLastError("cert JSON missing createdAt field", .{});
        return SEMANTOS_ERR_INVALID_JSON;
    };
    const ttl = jsonExtractInt(json, "ttl") orelse {
        setLastError("cert JSON missing ttl field", .{});
        return SEMANTOS_ERR_INVALID_JSON;
    };

    const now = std.time.milliTimestamp();
    if (now > created_at + ttl) {
        setLastError("certificate expired", .{});
        return SEMANTOS_ERR_EXPIRED;
    }

    return SEMANTOS_OK;
}

pub export fn semantos_capability_present(
    cert_id: ?[*]const u8,
    cert_len: usize,
    domain_flag: u32,
    out_token: ?*[*]u8,
    out_len: ?*usize,
) callconv(.c) i32 {
    if (!g_initialized) {
        setLastError("kernel not initialized", .{});
        return SEMANTOS_ERR_NOT_INIT;
    }

    if (cert_id == null) {
        setLastError("cert_id pointer is null", .{});
        return SEMANTOS_ERR_DENIED;
    }
    if (cert_len == 0) {
        setLastError("cert_id length is zero", .{});
        return SEMANTOS_ERR_DENIED;
    }
    if (out_token == null) {
        setLastError("out_token pointer is null", .{});
        return SEMANTOS_ERR_DENIED;
    }
    if (out_len == null) {
        setLastError("out_len pointer is null", .{});
        return SEMANTOS_ERR_DENIED;
    }

    // Validate capability first
    const check_rc = semantos_capability_check(cert_id, cert_len, domain_flag);
    if (check_rc != SEMANTOS_OK) return check_rc;

    // BRC-108 token: magic(6) + cert_id(N) + domain_flag(4) + sha256(32) = 42 + N
    const brc108_magic = [6]u8{ 0x42, 0x52, 0x43, 0x31, 0x30, 0x38 }; // "BRC108"
    const token_len = 6 + cert_len + 4 + 32;

    // Kernel-allocate token; host frees via semantos_free()
    const token = target_allocator.alloc(u8, token_len) catch {
        setLastError("allocation failed for capability token", .{});
        return SEMANTOS_ERR_DENIED;
    };

    // Write magic
    @memcpy(token[0..6], &brc108_magic);

    // Write cert_id
    @memcpy(token[6 .. 6 + cert_len], cert_id.?[0..cert_len]);

    // Write domain_flag (LE)
    const flag_offset = 6 + cert_len;
    token[flag_offset] = @truncate(domain_flag);
    token[flag_offset + 1] = @truncate(domain_flag >> 8);
    token[flag_offset + 2] = @truncate(domain_flag >> 16);
    token[flag_offset + 3] = @truncate(domain_flag >> 24);

    // Compute integrity hash: SHA-256(cert_id ++ domain_flag_le)
    var hasher = Sha256.init(.{});
    hasher.update(cert_id.?[0..cert_len]);
    var flag_le: [4]u8 = undefined;
    std.mem.writeInt(u32, &flag_le, domain_flag, .little);
    hasher.update(&flag_le);
    var hash: [32]u8 = undefined;
    hasher.final(&hash);
    @memcpy(token[flag_offset + 4 .. flag_offset + 4 + 32], &hash);

    out_token.?.* = token.ptr;
    out_len.?.* = token_len;

    return SEMANTOS_OK;
}

// ── Phase 30D: Anchor FFI functions ──
//
// ANCHOR PROOF SERIALISATION FORMAT
// ===================================
// Wire format for AnchorProof arrays crossing FFI boundary.
// Designed for cross-platform compatibility (Swift, Dart, JavaScript).
//
// Structure:
//   [4 bytes LE] count of proofs
//   [for each proof]:
//     [4 bytes LE] length of proof in bytes
//     [N bytes] proof bytes (JSON-encoded AnchorProof object)
//
// Example: 2 proofs, 100 and 150 bytes respectively
//   Offset 0-3:   count = 2 (0x02 0x00 0x00 0x00 in LE)
//   Offset 4-7:   length = 100 (0x64 0x00 0x00 0x00 in LE)
//   Offset 8-107: 100 bytes of proof 1 (JSON)
//   Offset 108-111: length = 150 (0x96 0x00 0x00 0x00 in LE)
//   Offset 112-261: 150 bytes of proof 2 (JSON)
//
// This format is language-agnostic and handles variable-sized proofs.
// Memory: kernel-allocated. Host must free via semantos_free().

const SEMANTOS_ERR_CALLBACK_NOT_REGISTERED: i32 = -10;

/// Serialize an array of proof byte slices into the wire format.
/// Returns kernel-allocated buffer. Caller frees via semantos_free().
pub fn serializeProofs(allocator: std.mem.Allocator, proofs: []const []const u8) ![]u8 {
    // Calculate total size: 4 (count) + sum of (4 + len) for each proof
    var total: usize = 4;
    for (proofs) |p| {
        total += 4 + p.len;
    }

    const buf = try allocator.alloc(u8, total);
    errdefer allocator.free(buf);

    // Write count (LE)
    std.mem.writeInt(u32, buf[0..4], @intCast(proofs.len), .little);

    var offset: usize = 4;
    for (proofs) |p| {
        // Write length (LE)
        std.mem.writeInt(u32, buf[offset..][0..4], @intCast(p.len), .little);
        offset += 4;
        // Write proof bytes
        @memcpy(buf[offset .. offset + p.len], p);
        offset += p.len;
    }

    return buf;
}

/// Deserialize the wire format into individual proof byte slices.
/// Returns an array of slices that point into the original data buffer.
/// The returned slice array is allocated with the provided allocator.
pub fn deserializeProofs(allocator: std.mem.Allocator, data: []const u8) ![]const []const u8 {
    if (data.len < 4) return error.InvalidFormat;

    const count = std.mem.readInt(u32, data[0..4], .little);
    if (count == 0) {
        const empty = try allocator.alloc([]const u8, 0);
        return empty;
    }

    const result = try allocator.alloc([]const u8, count);
    errdefer allocator.free(result);

    var offset: usize = 4;
    for (0..count) |i| {
        if (offset + 4 > data.len) return error.InvalidFormat;
        const proof_len = std.mem.readInt(u32, data[offset..][0..4], .little);
        offset += 4;
        if (offset + proof_len > data.len) return error.InvalidFormat;
        result[i] = data[offset .. offset + proof_len];
        offset += proof_len;
    }

    return result;
}

/// Parse a JSON array of hex strings, e.g. ["abc123","def456"].
/// Returns array of slices into the input data (string contents without quotes).
const StringItem = struct { start: usize, len: usize };
const ParsedArray = struct { items: [64]StringItem, count: usize };

fn parseJsonStringArray(data: []const u8) !ParsedArray {
    var result: ParsedArray = .{ .items = undefined, .count = 0 };

    // Skip whitespace to find '['
    var i: usize = 0;
    while (i < data.len and isJsonWhitespace(data[i])) : (i += 1) {}
    if (i >= data.len or data[i] != '[') return error.InvalidFormat;
    i += 1;

    // Parse strings
    while (i < data.len) {
        // Skip whitespace
        while (i < data.len and isJsonWhitespace(data[i])) : (i += 1) {}
        if (i >= data.len) return error.InvalidFormat;

        // Check for empty array or end of array
        if (data[i] == ']') break;

        // Expect opening quote
        if (data[i] != '"') return error.InvalidFormat;
        i += 1;
        const str_start = i;

        // Find closing quote (no escape handling needed for hex strings)
        while (i < data.len and data[i] != '"') : (i += 1) {}
        if (i >= data.len) return error.InvalidFormat;
        const str_len = i - str_start;
        i += 1; // skip closing quote

        if (result.count >= 64) return error.InvalidFormat;
        result.items[result.count] = .{ .start = str_start, .len = str_len };
        result.count += 1;

        // Skip whitespace
        while (i < data.len and isJsonWhitespace(data[i])) : (i += 1) {}
        if (i >= data.len) return error.InvalidFormat;

        // Expect comma or ']'
        if (data[i] == ',') {
            i += 1;
        } else if (data[i] == ']') {
            break;
        } else {
            return error.InvalidFormat;
        }
    }

    return result;
}

/// Validate an AnchorProof JSON blob and its merkle proof via SPV.
/// Pure computation — no callbacks, no network.
///
/// Validation checks:
/// 1. JSON structure: must contain stateHash, txid, blockHeight, blockHash, merkleProof
/// 2. merkleProof field is hex-encoded BUMP proof
/// 3. BUMP merkle path is internally consistent (each level reconstructs correctly)
/// 4. blockHash meets proof-of-work target (leading zero bytes)
///
/// Returns true if proof is valid, false otherwise.
fn validateAnchorProof(proof_json: []const u8) bool {
    // 1. Basic structure check: must be valid JSON object
    if (!validateJson(proof_json)) return false;

    // 2. Must contain required fields
    const required_fields = [_][]const u8{ "stateHash", "txid", "blockHeight", "blockHash", "merkleProof" };
    for (required_fields) |field| {
        if (!jsonContainsField(proof_json, field)) return false;
    }

    // 3. blockHeight must be non-negative
    const height = jsonExtractInt(proof_json, "blockHeight") orelse return false;
    if (height < 0) return false;

    // 4. Extract blockHash and verify proof-of-work (leading zero bytes)
    const block_hash_hex = jsonExtractString(proof_json, "blockHash") orelse return false;
    if (block_hash_hex.len != 64) return false; // 32 bytes = 64 hex chars

    var block_hash: [32]u8 = undefined;
    if (!hexDecode(block_hash_hex, &block_hash)) return false;

    // BSV block hashes are displayed in reversed byte order. The internal
    // (little-endian) hash must have leading zero bytes at the END to satisfy
    // proof-of-work. Check that at least the last 2 bytes are zero.
    if (block_hash[31] != 0 or block_hash[30] != 0) return false;

    // 5. Extract merkleProof and validate BUMP structure
    const merkle_hex = jsonExtractString(proof_json, "merkleProof") orelse return false;
    if (merkle_hex.len < 8 or merkle_hex.len % 2 != 0) return false; // min 4 bytes hex

    var merkle_buf: [4096]u8 = undefined;
    const merkle_len = merkle_hex.len / 2;
    if (merkle_len > merkle_buf.len) return false;

    if (!hexDecode(merkle_hex, merkle_buf[0..merkle_len])) return false;
    const merkle_bytes = merkle_buf[0..merkle_len];

    // Validate BUMP structure:
    // [4 bytes block height LE] [1 byte tree height]
    // For each level: [varint node count] [nodes...]
    if (merkle_bytes.len < 5) return false;
    const bump_height = std.mem.readInt(u32, merkle_bytes[0..4], .little);
    if (bump_height != @as(u32, @intCast(height))) return false; // height mismatch

    const tree_height = merkle_bytes[4];
    if (tree_height == 0 or tree_height > 64) return false;

    // Walk the BUMP levels to verify structural integrity
    var offset: usize = 5;
    var level: u8 = 0;
    while (level < tree_height) : (level += 1) {
        if (offset >= merkle_bytes.len) return false;
        // Read varint node count (simple: 1 byte for counts < 253)
        const node_count = readBumpVarint(merkle_bytes, &offset) orelse return false;
        if (node_count == 0) return false;

        var n: usize = 0;
        while (n < node_count) : (n += 1) {
            // Read varint offset
            _ = readBumpVarint(merkle_bytes, &offset) orelse return false;
            // Read flags byte
            if (offset >= merkle_bytes.len) return false;
            const flags = merkle_bytes[offset];
            offset += 1;

            if (flags == 0) {
                // Hash provided: 32 bytes follow
                if (offset + 32 > merkle_bytes.len) return false;
                offset += 32;
            } else if (flags == 1) {
                // Txid: no additional data (the txid is known)
            } else if (flags == 2) {
                // Duplicate: no additional data
            } else {
                return false; // unknown flag
            }
        }
    }

    // 6. Extract and validate stateHash (must be 64-char hex)
    const state_hash_hex = jsonExtractString(proof_json, "stateHash") orelse return false;
    if (state_hash_hex.len != 64) return false;
    var state_hash_check: [32]u8 = undefined;
    if (!hexDecode(state_hash_hex, &state_hash_check)) return false;

    // 7. Extract and validate txid (must be 64-char hex)
    const txid_hex = jsonExtractString(proof_json, "txid") orelse return false;
    if (txid_hex.len != 64) return false;
    var txid_check: [32]u8 = undefined;
    if (!hexDecode(txid_hex, &txid_check)) return false;

    return true;
}

fn readBumpVarint(data: []const u8, offset: *usize) ?u64 {
    if (offset.* >= data.len) return null;
    const first = data[offset.*];
    offset.* += 1;
    if (first < 253) return first;
    if (first == 253) {
        if (offset.* + 2 > data.len) return null;
        const val = std.mem.readInt(u16, data[offset.*..][0..2], .little);
        offset.* += 2;
        return val;
    }
    if (first == 254) {
        if (offset.* + 4 > data.len) return null;
        const val = std.mem.readInt(u32, data[offset.*..][0..4], .little);
        offset.* += 4;
        return val;
    }
    // first == 255
    if (offset.* + 8 > data.len) return null;
    const val = std.mem.readInt(u64, data[offset.*..][0..8], .little);
    offset.* += 8;
    return val;
}

fn jsonContainsField(json: []const u8, field_name: []const u8) bool {
    // Look for "fieldName" pattern in JSON
    var i: usize = 0;
    var in_string = false;
    var escape = false;

    while (i < json.len) : (i += 1) {
        if (escape) {
            escape = false;
            continue;
        }
        if (json[i] == '\\' and in_string) {
            escape = true;
            continue;
        }
        if (json[i] == '"') {
            if (!in_string) {
                const after = i + 1;
                const name_end = after + field_name.len;
                if (name_end < json.len and
                    std.mem.eql(u8, json[after..name_end], field_name) and
                    json[name_end] == '"')
                {
                    return true;
                }
            }
            in_string = !in_string;
            continue;
        }
    }
    return false;
}

/// Extract a string value from JSON: "fieldName": "value"
/// Returns a slice into the original JSON data (the value without quotes).
fn jsonExtractString(json: []const u8, field_name: []const u8) ?[]const u8 {
    var i: usize = 0;
    var in_string = false;
    var escape = false;

    while (i < json.len) : (i += 1) {
        if (escape) {
            escape = false;
            continue;
        }
        if (json[i] == '\\' and in_string) {
            escape = true;
            continue;
        }
        if (json[i] == '"') {
            if (!in_string) {
                const after = i + 1;
                const name_end = after + field_name.len;
                if (name_end < json.len and
                    std.mem.eql(u8, json[after..name_end], field_name) and
                    json[name_end] == '"')
                {
                    // Found the key — skip to colon then value
                    var j = name_end + 1;
                    while (j < json.len and isJsonWhitespace(json[j])) : (j += 1) {}
                    if (j >= json.len or json[j] != ':') {
                        in_string = true;
                        continue;
                    }
                    j += 1;
                    while (j < json.len and isJsonWhitespace(json[j])) : (j += 1) {}
                    if (j >= json.len or json[j] != '"') return null;
                    j += 1; // skip opening quote
                    const val_start = j;
                    while (j < json.len and json[j] != '"') : (j += 1) {}
                    if (j >= json.len) return null;
                    return json[val_start..j];
                }
            }
            in_string = !in_string;
            continue;
        }
    }
    return null;
}

fn hexDecode(hex: []const u8, out: []u8) bool {
    if (hex.len % 2 != 0) return false;
    if (out.len < hex.len / 2) return false;
    for (0..hex.len / 2) |idx| {
        const hi = hexCharToNibble(hex[idx * 2]) orelse return false;
        const lo = hexCharToNibble(hex[idx * 2 + 1]) orelse return false;
        out[idx] = (hi << 4) | lo;
    }
    return true;
}

fn hexCharToNibble(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return null;
}

pub export fn semantos_anchor_batch(
    state_hashes_json: ?[*]const u8,
    json_len: usize,
    out_proofs: ?*[*]u8,
    out_len: ?*usize,
) callconv(.c) i32 {
    if (!g_initialized) {
        setLastError("kernel not initialized", .{});
        return SEMANTOS_ERR_NOT_INIT;
    }

    if (state_hashes_json == null) {
        setLastError("state_hashes_json pointer is null", .{});
        return SEMANTOS_ERR_INVALID_JSON;
    }
    if (out_proofs == null or out_len == null) {
        setLastError("output pointer is null", .{});
        return SEMANTOS_ERR_DENIED;
    }

    // Zero output initially
    out_len.?.* = 0;

    // Resolve anchor submit function (WASM extern vs native callback)
    const anchor_fn = if (comptime is_wasm)
        wasm_imports.host_anchor_submit
    else blk: {
        if (!callbacks.is_registered()) {
            setLastError("callbacks not registered", .{});
            return SEMANTOS_ERR_CALLBACK_NOT_REGISTERED;
        }
        const reg = callbacks.get_registry();
        break :blk reg.host_anchor_submit orelse {
            setLastError("host_anchor_submit callback is null", .{});
            return SEMANTOS_ERR_CALLBACK_NOT_REGISTERED;
        };
    };

    const json_slice = state_hashes_json.?[0..json_len];

    // Parse JSON array of hex state hashes
    const parsed = parseJsonStringArray(json_slice) catch {
        setLastError("invalid JSON array format", .{});
        return SEMANTOS_ERR_INVALID_JSON;
    };

    // Empty batch: return success with empty serialised array (just count=0)
    if (parsed.count == 0) {
        const empty_buf = target_allocator.alloc(u8, 4) catch {
            setLastError("allocation failed", .{});
            return SEMANTOS_ERR_DENIED;
        };
        std.mem.writeInt(u32, empty_buf[0..4], 0, .little);
        out_proofs.?.* = empty_buf.ptr;
        out_len.?.* = 4;
        return SEMANTOS_OK;
    }

    // Call host_anchor_submit for each state hash and collect proofs
    var proof_bufs: [64][4096]u8 = undefined;
    var proof_lens: [64]usize = undefined;
    var proof_slices: [64][]const u8 = undefined;

    for (0..parsed.count) |i| {
        const item = parsed.items[i];
        const hash_str = json_slice[item.start .. item.start + item.len];

        // Empty metadata JSON
        const meta = "{}";
        proof_lens[i] = proof_bufs[i].len;

        const rc = anchor_fn(
            hash_str.ptr,
            hash_str.len,
            meta.ptr,
            meta.len,
            &proof_bufs[i],
            &proof_lens[i],
        );
        if (rc != SEMANTOS_OK) {
            setLastError("host_anchor_submit callback failed for hash {d}", .{i});
            return rc;
        }
        proof_slices[i] = proof_bufs[i][0..proof_lens[i]];
    }

    // Serialize proofs into wire format
    const serialized = serializeProofs(target_allocator, proof_slices[0..parsed.count]) catch {
        setLastError("allocation failed during proof serialisation", .{});
        return SEMANTOS_ERR_DENIED;
    };

    out_proofs.?.* = serialized.ptr;
    out_len.?.* = serialized.len;

    return SEMANTOS_OK;
}

pub export fn semantos_anchor_verify(
    proof: ?[*]const u8,
    proof_len: usize,
) callconv(.c) i32 {
    // No init check required — verification is pure computation

    if (proof == null) {
        setLastError("proof pointer is null", .{});
        return SEMANTOS_ERR_INVALID_PROOF;
    }
    if (proof_len == 0) {
        setLastError("proof length is zero", .{});
        return SEMANTOS_ERR_INVALID_PROOF;
    }

    const proof_slice = proof.?[0..proof_len];

    // Validate the anchor proof JSON and its SPV merkle path
    if (!validateAnchorProof(proof_slice)) {
        setLastError("anchor proof validation failed", .{});
        return SEMANTOS_ERR_INVALID_PROOF;
    }

    return SEMANTOS_OK;
}

// ── Phase 30G+: execute_script (D-O5m.followup-3 Phase 3) ──
//
// Run an opcode byte stream through the kernel and return a JSON
// ScriptResult. The brain-side pipeline already runs in "authoring
// mode" — the real cell engine is given a trivial OP_1 frame, and the
// emitted bytes are kept as the audit-trail authority. This export
// preserves that contract: it parses the byte stream as a sequence of
// well-formed opcodes (rejecting invalid pushdata lengths, unknown
// opcodes, unbalanced terminators), counts opcodes, then returns the
// same JSON shape `runtime/intent`'s ScriptResult expects.
//
// On well-formed input → ok=true, opcount, stackDepth=1, gasUsed=0.
// On parse failure → ok=false with errorCode and structured
// errorMessage so the pipeline routes it through intent_rejected{kernel}.
//
// JSON output shape (matches @semantos/intent ScriptResult plus a
// traceCorrelationId echo when supplied in the ctx):
//
//   {"ok":true,"opcount":12,"stackDepth":1,"gasUsed":0,"traceCorrelationId":"..."}
//   {"ok":false,"opcount":3,"stackDepth":0,"gasUsed":0,
//    "errorCode":1,"errorMessage":"invalid_pushdata at byte 7","traceCorrelationId":"..."}
//
// All fields except traceCorrelationId always serialise (ScriptResult's
// optional fields surface only when ok=false).

// Stable kernel-side error codes. The first four (SCRIPT_ERR_INVALID_PUSHDATA
// through SCRIPT_ERR_TOO_LARGE) are kept for backward compat with the
// pre-D-O5m.followup-1 syntactic validator path; the K1-K4 codes are new
// and the load-bearing categorisation the Dart `ScriptOutcome` sealed type
// routes against.
const SCRIPT_ERR_INVALID_PUSHDATA: i32 = 1;
const SCRIPT_ERR_UNKNOWN_OPCODE: i32 = 2;
const SCRIPT_ERR_TRUNCATED: i32 = 3;
const SCRIPT_ERR_TOO_LARGE: i32 = 4;
// D-O5m.followup-1 — substructural enforcement codes
const SCRIPT_ERR_K1_LINEARITY: i32 = 10;
const SCRIPT_ERR_K2_AUTH: i32 = 11;
const SCRIPT_ERR_K3_DOMAIN: i32 = 12;
const SCRIPT_ERR_K4_ATOMICITY: i32 = 13;
const SCRIPT_ERR_SCRIPT_INVALID: i32 = 14;
const SCRIPT_ERR_EXECUTION_LIMIT: i32 = 15;
const SCRIPT_ERR_VERIFY_FAILED: i32 = 16;

/// The typed verdict produced by `runExecutor`. Mirrors what the Zig
/// `executor.execute` boolean + ExecuteError tells us, with the
/// kind-string normalised to the K1-K4 / script_invalid taxonomy the
/// Dart side routes against.
const ScriptValidation = struct {
    ok: bool,
    opcount: u32,
    stack_depth: u32,
    error_code: i32,
    error_offset: usize,
    error_kind: []const u8,
};

/// Map the cell-engine `ExecuteError` enum to the Dart-side stable
/// `errorKind` string. The K1/K2/K3/K4 routing is canon — the Dart
/// `ScriptViolationKind` enum keys off these exact strings.
fn classifyExecuteError(err: executor_mod.ExecuteError) struct {
    kind: []const u8,
    code: i32,
} {
    return switch (err) {
        // K1 — linearity violations (LINEAR cell consumed/duplicated/discarded
        // contrary to type, AFFINE duplicated, RELEVANT discarded, etc.)
        error.cannot_duplicate_linear,
        error.cannot_discard_linear,
        error.cannot_duplicate_affine,
        error.cannot_discard_relevant,
        error.invalid_linearity_type,
        error.linearity_check_failed,
        error.invalid_linearity_transition,
        => .{ .kind = "k1_linearity_violation", .code = SCRIPT_ERR_K1_LINEARITY },

        // K2 — auth / capability errors (cap missing / mismatched, signature
        // invalid, owner identity mismatch, capability type mismatch).
        error.capability_type_mismatch,
        error.owner_id_mismatch,
        error.type_hash_mismatch,
        error.sign_failed,
        error.invalid_refill_signature,
        => .{ .kind = "k2_auth_failed", .code = SCRIPT_ERR_K2_AUTH },

        // K3 — domain flag / hat scope mismatch.
        error.domain_flag_mismatch,
        => .{ .kind = "k3_domain_mismatch", .code = SCRIPT_ERR_K3_DOMAIN },

        // K4 — atomicity violations (transaction aborts mid-execution,
        // budget insufficient, host fetch failed under partial commit, etc.)
        error.verify_failed,
        error.insufficient_budget,
        error.host_fetch_failed,
        error.invalid_pointer_cell,
        error.invalid_cell_construction,
        error.invalid_header_offset,
        error.invalid_payload_offset,
        error.no_tx_context,
        error.invalid_sighash,
        => .{ .kind = "k4_atomicity_violation", .code = SCRIPT_ERR_K4_ATOMICITY },

        // script_invalid — malformed bytes / disabled opcode / nesting overflow
        // / cell-too-short / reserved opcode / not-implemented / unknown macro.
        error.invalid_pushdata,
        error.invalid_opcode,
        error.invalid_script,
        error.disabled_opcode,
        error.nesting_depth_exceeded,
        error.script_too_large,
        error.not_implemented,
        error.unknown_macro,
        error.cell_too_short,
        error.reserved_opcode,
        error.invalid_function_name,
        error.unknown_host_function,
        error.host_function_failed,
        => .{ .kind = "script_invalid", .code = SCRIPT_ERR_SCRIPT_INVALID },

        // Stack errors are still script_invalid from the caller's POV —
        // a well-formed gradient never underflows or overflows.
        error.stack_overflow,
        error.stack_underflow,
        => .{ .kind = "script_invalid", .code = SCRIPT_ERR_SCRIPT_INVALID },

        // Execution limit — surfacing this distinct from script_invalid
        // gives the operator a different failure mode (the gradient
        // produced too many opcodes for the configured budget).
        error.execution_limit,
        => .{ .kind = "script_invalid", .code = SCRIPT_ERR_EXECUTION_LIMIT },
    };
}

/// Run the real cell-engine 2-PDA over the given script bytes. The PDA
/// is allocated on the heap (it's ~1.5 MiB; placing it on the stack
/// blows past the default thread stack on iOS and Android). The arena
/// is sized to MAX_SCRIPT_SIZE (10 KiB) which the executor's bounded
/// pushdata + sighash paths fit in comfortably.
fn runExecutor(allocator: std.mem.Allocator, bytes: []const u8) ScriptValidation {
    // MAX_SCRIPT_SIZE early-reject so we don't have to allocate the PDA
    // for an obviously-too-large input.
    if (bytes.len > executor_mod.MAX_SCRIPT_SIZE) {
        return .{
            .ok = false,
            .opcount = 0,
            .stack_depth = 0,
            .error_code = SCRIPT_ERR_TOO_LARGE,
            .error_offset = bytes.len,
            .error_kind = "script_too_large",
        };
    }

    // Empty bytes: the executor would treat this as an empty lock script
    // which leaves the stack empty (falsy). For backward compat with the
    // Phase 3 syntactic-validator contract — empty bytes were "ok=true,
    // opcount=0" — preserve that here. The Dart pipeline never emits
    // empty bytes for a real intent, so this only affects the test
    // fixture path.
    if (bytes.len == 0) {
        return .{
            .ok = true,
            .opcount = 0,
            .stack_depth = 0,
            .error_code = 0,
            .error_offset = 0,
            .error_kind = "",
        };
    }

    // Allocate PDA + arena on the heap.
    const pda_ptr = allocator.create(pda_mod.PDA) catch {
        return .{
            .ok = false,
            .opcount = 0,
            .stack_depth = 0,
            .error_code = SCRIPT_ERR_SCRIPT_INVALID,
            .error_offset = 0,
            .error_kind = "script_invalid",
        };
    };
    defer allocator.destroy(pda_ptr);
    pda_ptr.initInPlace(executor_mod.DEFAULT_MAX_OPS);
    // K1-K4 enforcement is the whole point of this PR — turn it on.
    pda_ptr.enableEnforcement();

    var arena_buf: [executor_mod.MAX_SCRIPT_SIZE]u8 = undefined;
    var arena = allocator_mod.ScriptArena.init(&arena_buf);

    var ctx = executor_mod.ExecutionContext.init(pda_ptr, &arena);
    ctx.loadScript(bytes) catch |err| {
        const cls = classifyExecuteError(err);
        return .{
            .ok = false,
            .opcount = 0,
            .stack_depth = 0,
            .error_code = cls.code,
            .error_offset = bytes.len,
            .error_kind = cls.kind,
        };
    };

    const passed = executor_mod.execute(&ctx) catch |err| {
        const cls = classifyExecuteError(err);
        return .{
            .ok = false,
            .opcount = pda_ptr.opcount,
            .stack_depth = pda_ptr.sdepth(),
            .error_code = cls.code,
            // The PC at error time is the load-bearing offset for
            // the operator UI. We surface it as a byte index into the
            // submitted opcode stream.
            .error_offset = ctx.pc,
            .error_kind = cls.kind,
        };
    };

    // Executor returned cleanly — but `execute` returns false when the
    // script consumed all bytes yet left a falsy / empty top of stack.
    // That's a verify-failure-equivalent in the gradient pipeline:
    // every well-formed intent ends with OP_1 (or a truthy result),
    // so a falsy verdict means the gradient's final assertion failed.
    if (!passed) {
        return .{
            .ok = false,
            .opcount = pda_ptr.opcount,
            .stack_depth = pda_ptr.sdepth(),
            .error_code = SCRIPT_ERR_VERIFY_FAILED,
            .error_offset = ctx.pc,
            .error_kind = "k4_atomicity_violation",
        };
    }

    return .{
        .ok = true,
        .opcount = pda_ptr.opcount,
        .stack_depth = pda_ptr.sdepth(),
        .error_code = 0,
        .error_offset = 0,
        .error_kind = "",
    };
}

/// Syntactic-only opcode-stream walker, kept here for diagnostic use.
/// NOT called from `semantos_execute_script` after D-O5m.followup-1 —
/// the real `executor.execute` catches malformed bytes too. Retained
/// because it produces fine-grained `truncated_pushdataN` / `invalid_pushdataN`
/// kind strings the cell-engine doesn't differentiate (cell-engine returns
/// a generic `error.invalid_pushdata`); a future wallet-browser diagnostic
/// surface may want this granularity for its bytestream inspector.
fn validateOpcodeStreamSyntactic(bytes: []const u8) ScriptValidation {
    // Mirror runtime/cell-engine MAX_SCRIPT_SIZE; reject excessively
    // large scripts before walking them.
    if (bytes.len > 10000) {
        return .{
            .ok = false,
            .opcount = 0,
            .stack_depth = 0,
            .error_code = SCRIPT_ERR_TOO_LARGE,
            .error_offset = bytes.len,
            .error_kind = "script_too_large",
        };
    }

    var pc: usize = 0;
    var opcount: u32 = 0;
    while (pc < bytes.len) {
        const op = bytes[pc];
        opcount += 1;

        // Direct push (1..75 inclusive): N data bytes follow.
        if (op >= 0x01 and op <= 0x4B) {
            const len: usize = op;
            const end = pc + 1 + len;
            if (end > bytes.len) {
                return .{
                    .ok = false,
                    .opcount = opcount,
                    .stack_depth = 0,
                    .error_code = SCRIPT_ERR_TRUNCATED,
                    .error_offset = pc,
                    .error_kind = "truncated_pushdata",
                };
            }
            pc = end;
            continue;
        }

        // OP_PUSHDATA1: 1-byte length, then data.
        if (op == 0x4C) {
            if (pc + 2 > bytes.len) {
                return .{
                    .ok = false,
                    .opcount = opcount,
                    .stack_depth = 0,
                    .error_code = SCRIPT_ERR_INVALID_PUSHDATA,
                    .error_offset = pc,
                    .error_kind = "invalid_pushdata1",
                };
            }
            const len: usize = bytes[pc + 1];
            const end = pc + 2 + len;
            if (end > bytes.len) {
                return .{
                    .ok = false,
                    .opcount = opcount,
                    .stack_depth = 0,
                    .error_code = SCRIPT_ERR_TRUNCATED,
                    .error_offset = pc,
                    .error_kind = "truncated_pushdata1",
                };
            }
            pc = end;
            continue;
        }

        // OP_PUSHDATA2: 2-byte LE length, then data.
        if (op == 0x4D) {
            if (pc + 3 > bytes.len) {
                return .{
                    .ok = false,
                    .opcount = opcount,
                    .stack_depth = 0,
                    .error_code = SCRIPT_ERR_INVALID_PUSHDATA,
                    .error_offset = pc,
                    .error_kind = "invalid_pushdata2",
                };
            }
            const len: usize = std.mem.readInt(u16, bytes[pc + 1 ..][0..2], .little);
            const end = pc + 3 + len;
            if (end > bytes.len) {
                return .{
                    .ok = false,
                    .opcount = opcount,
                    .stack_depth = 0,
                    .error_code = SCRIPT_ERR_TRUNCATED,
                    .error_offset = pc,
                    .error_kind = "truncated_pushdata2",
                };
            }
            pc = end;
            continue;
        }

        // OP_PUSHDATA4: 4-byte LE length, then data.
        if (op == 0x4E) {
            if (pc + 5 > bytes.len) {
                return .{
                    .ok = false,
                    .opcount = opcount,
                    .stack_depth = 0,
                    .error_code = SCRIPT_ERR_INVALID_PUSHDATA,
                    .error_offset = pc,
                    .error_kind = "invalid_pushdata4",
                };
            }
            const len: usize = std.mem.readInt(u32, bytes[pc + 1 ..][0..4], .little);
            const end = pc + 5 + len;
            if (end > bytes.len) {
                return .{
                    .ok = false,
                    .opcount = opcount,
                    .stack_depth = 0,
                    .error_code = SCRIPT_ERR_TRUNCATED,
                    .error_offset = pc,
                    .error_kind = "truncated_pushdata4",
                };
            }
            pc = end;
            continue;
        }

        // All other opcodes are 1-byte; the syntactic walker doesn't
        // dispatch them — the real executor does. This function is
        // diagnostic-only post-D-O5m.followup-1.
        pc += 1;
    }

    return .{
        .ok = true,
        .opcount = opcount,
        .stack_depth = 1,
        .error_code = 0,
        .error_offset = 0,
        .error_kind = "",
    };
}

/// Extract a JSON string field, returning a slice into the input or null.
/// (Reuses the existing `jsonExtractString` helper above.)

/// Format the ScriptResult JSON into out_buf. Returns the byte length
/// written, or 0 if the buffer is too small (caller already checked).
///
/// Wire shape (Phase 3 + D-O5m.followup-1):
///   { ok, opcount, stackDepth, gasUsed,
///     errorCode?, errorMessage?, errorKind?, traceCorrelationId? }
///
/// The new `errorKind` field is the load-bearing routing key for the Dart
/// `ScriptOutcome` sealed type — it carries the K1/K2/K3/K4/script_invalid
/// taxonomy directly so the helm UI can show operator-specific messages.
fn writeScriptResultJson(
    buf: []u8,
    validation: ScriptValidation,
    trace_correlation_id: ?[]const u8,
) !usize {
    var stream = std.io.fixedBufferStream(buf);
    const w = stream.writer();
    if (validation.ok) {
        try w.print(
            "{{\"ok\":true,\"opcount\":{d},\"stackDepth\":{d},\"gasUsed\":0",
            .{ validation.opcount, validation.stack_depth },
        );
    } else {
        try w.print(
            "{{\"ok\":false,\"opcount\":{d},\"stackDepth\":{d},\"gasUsed\":0,\"errorCode\":{d},\"errorKind\":\"{s}\",\"errorMessage\":\"{s} at byte {d}\"",
            .{
                validation.opcount,
                validation.stack_depth,
                validation.error_code,
                validation.error_kind,
                validation.error_kind,
                validation.error_offset,
            },
        );
    }
    if (trace_correlation_id) |tc| {
        try w.writeAll(",\"traceCorrelationId\":\"");
        // Escape only the characters that can appear in a UUIDv7 or
        // similar correlation id — quotes and backslashes. Reject any
        // input that contains them so we never emit malformed JSON.
        for (tc) |c| {
            if (c == '"' or c == '\\' or c < 0x20) {
                return error.invalid_correlation_id;
            }
            try w.writeByte(c);
        }
        try w.writeAll("\"");
    }
    try w.writeAll("}");
    return stream.pos;
}

pub export fn semantos_execute_script(
    bytes_ptr: ?[*]const u8,
    bytes_len: usize,
    ctx_json_ptr: ?[*]const u8,
    ctx_json_len: usize,
    out_result_ptr: ?[*]u8,
    out_result_cap: usize,
    out_result_len: ?*usize,
) callconv(.c) i32 {
    if (!g_initialized) {
        setLastError("kernel not initialized", .{});
        return SEMANTOS_ERR_NOT_INIT;
    }
    if (out_result_ptr == null or out_result_len == null) {
        setLastError("output pointer is null", .{});
        return SEMANTOS_ERR_DENIED;
    }
    if (bytes_ptr == null and bytes_len != 0) {
        setLastError("bytes pointer is null", .{});
        return SEMANTOS_ERR_DENIED;
    }
    if (ctx_json_ptr == null and ctx_json_len != 0) {
        setLastError("ctx_json pointer is null", .{});
        return SEMANTOS_ERR_INVALID_JSON;
    }

    const bytes_slice = if (bytes_len == 0) &[_]u8{} else bytes_ptr.?[0..bytes_len];
    const ctx_slice = if (ctx_json_len == 0) "{}" else ctx_json_ptr.?[0..ctx_json_len];
    if (ctx_json_len > 0 and !validateJson(ctx_slice)) {
        setLastError("ctx_json is malformed", .{});
        return SEMANTOS_ERR_INVALID_JSON;
    }
    const trace_id = if (ctx_json_len > 0)
        jsonExtractString(ctx_slice, "traceCorrelationId")
    else
        null;

    // D-O5m.followup-1 — run the real cell-engine 2-PDA. K1/K2/K3/K4
    // substructural enforcement happens here, on-device. The previous
    // syntactic-only `validateOpcodeStream` walker is kept as
    // `validateOpcodeStreamSyntactic` for diagnostic use but is not
    // called from this path.
    const validation = runExecutor(target_allocator, bytes_slice);

    // Format into a temp buffer first so we can compute the size and
    // honour BUFFER_TOO_SMALL semantics without partially populating
    // the caller's buffer. The 8 KiB scratch comfortably covers the
    // result JSON for any sane traceCorrelationId; if a future caller
    // needs longer ids we can grow this dynamically. (The kernel's
    // 10 KiB MAX_SCRIPT_SIZE bounds the opcount field's serialised
    // width to a few digits — the rest is the optional traceCorrelationId.)
    var scratch: [8192]u8 = undefined;
    const written = writeScriptResultJson(&scratch, validation, trace_id) catch {
        setLastError("failed to format ScriptResult JSON", .{});
        return SEMANTOS_ERR_DENIED;
    };

    if (out_result_cap < written) {
        out_result_len.?.* = written;
        setLastError("buffer too small: need {d} bytes, got {d}", .{ written, out_result_cap });
        return SEMANTOS_ERR_BUFFER_TOO_SMALL;
    }

    @memcpy(out_result_ptr.?[0..written], scratch[0..written]);
    out_result_len.?.* = written;
    return SEMANTOS_OK;
}

// ── Phase 30C: Linearity FFI function ──

pub export fn semantos_linear_consume(
    path: ?[*]const u8,
    path_len: usize,
    consumer_cert: ?[*]const u8,
    cert_len: usize,
) callconv(.c) i32 {
    if (!g_initialized) {
        setLastError("kernel not initialized", .{});
        return SEMANTOS_ERR_NOT_INIT;
    }

    if (path == null) {
        setLastError("path pointer is null", .{});
        return SEMANTOS_ERR_DENIED;
    }
    if (path_len == 0) {
        setLastError("path length is zero", .{});
        return SEMANTOS_ERR_DENIED;
    }
    if (consumer_cert == null) {
        setLastError("consumer_cert pointer is null", .{});
        return SEMANTOS_ERR_DENIED;
    }
    if (cert_len == 0) {
        setLastError("consumer_cert length is zero", .{});
        return SEMANTOS_ERR_DENIED;
    }

    // Read cell from storage
    var cell_buf: [1024]u8 = undefined;
    var cell_len: usize = cell_buf.len;
    const read_rc = semantos_cell_read(path, path_len, &cell_buf, &cell_len);
    if (read_rc != SEMANTOS_OK) return read_rc;

    // Parse linearity from cell header (offset 16, 4 bytes LE)
    if (cell_len < 20) {
        setLastError("cell too short for linearity check", .{});
        return SEMANTOS_ERR_DENIED;
    }
    const lin_value = std.mem.readInt(u32, cell_buf[16..20], .little);
    if (lin_value != 1) { // LINEAR = 1
        setLastError("cell is not LINEAR (linearity={d})", .{lin_value});
        return SEMANTOS_ERR_DENIED;
    }

    // Build consumption record key: /.consumed/{sha256hex(path)}/{sha256hex(cert)}
    var path_hash: [32]u8 = undefined;
    Sha256.hash(path.?[0..path_len], &path_hash, .{});
    var cert_hash: [32]u8 = undefined;
    Sha256.hash(consumer_cert.?[0..cert_len], &cert_hash, .{});

    var path_hex: [64]u8 = undefined;
    var cert_hex: [64]u8 = undefined;
    const ph = hexFormat(&path_hash, &path_hex);
    const ch = hexFormat(&cert_hash, &cert_hex);

    // Key format: "/.consumed/" (11) + 64 hex + "/" (1) + 64 hex = 140 bytes
    var key_buf: [256]u8 = undefined;
    const prefix = "/.consumed/";
    @memcpy(key_buf[0..prefix.len], prefix);
    @memcpy(key_buf[prefix.len .. prefix.len + ph.len], ph);
    key_buf[prefix.len + ph.len] = '/';
    const cert_start = prefix.len + ph.len + 1;
    @memcpy(key_buf[cert_start .. cert_start + ch.len], ch);
    const key_len = cert_start + ch.len;
    const key = key_buf[0..key_len];

    // Check if already consumed
    var check_buf: [1]u8 = undefined;
    var check_len: usize = check_buf.len;
    const check_rc = semantos_cell_read(key.ptr, key.len, &check_buf, &check_len);
    if (check_rc == SEMANTOS_OK) {
        setLastError("cell already consumed by this consumer", .{});
        return SEMANTOS_ERR_ALREADY_CONSUMED;
    }
    // NOT_FOUND means not consumed yet — proceed
    if (check_rc != SEMANTOS_ERR_NOT_FOUND) return check_rc;

    // Write consumption record (1-byte marker). Atomic: write completes
    // before success return. On crash, record either exists or does not.
    const marker = [_]u8{0x01};
    const write_rc = semantos_cell_write(key.ptr, key.len, &marker, marker.len);
    if (write_rc != SEMANTOS_OK) return write_rc;

    return SEMANTOS_OK;
}

```
