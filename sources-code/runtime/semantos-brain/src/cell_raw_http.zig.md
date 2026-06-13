---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cell_raw_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.247082+00:00
---

# runtime/semantos-brain/src/cell_raw_http.zig

```zig
// D-LC1 — Raw cell-over-HTTP endpoint.
//
// Layer-collapse read path: the on-disk format (LmdbCellStore) equals the
// wire format equals the in-memory format. This endpoint serves the raw
// 1024-byte cell straight out of LMDB with no envelope.
//
// Wire shape:
//
//     GET /api/v1/cell/<sha256hex>
//     Authorization: Bearer <hex64>
//
//     200 → 1024 raw cell bytes, Content-Type: application/x-semantos-cell
//     400 → {"error":"bad_request"}        // hex parse failed / length wrong
//     401 → {"error":"bearer_invalid"}
//     404 → {"error":"not_found"}          // hash unknown
//     405 → {"error":"method_not_allowed"}
//
// The acceptor module owns the path-parse + hash-decode helpers as pub fns
// so the reactor-shape variant in site_server/reactor.zig can call them
// directly. The std.http.Server-shape maybeHandle is kept for inline tests
// only — the live brain runs the reactor variant.

const std = @import("std");

const cell_store_mod = @import("cell_store");
const bearer_tokens = @import("bearer_tokens");

pub const CELL_BYTES: usize = 1024;
pub const HASH_HEX_LEN: usize = 64;

pub const Error = error{
    out_of_memory,
    write_failed,
};

pub const ROUTE_PREFIX: []const u8 = "/api/v1/cell/";
/// D-LC4 — `GET /api/v1/cell/since/<prev_hash_hex>` returns every cell
/// whose header `prev_state_hash` equals the given hash, back-to-back as
/// `application/x-semantos-cells` (plural). Empty body when no forward
/// children exist for the given prev hash.
pub const SINCE_PREFIX: []const u8 = "/api/v1/cell/since/";

pub const Acceptor = struct {
    /// CellStore vtable wrapper. The acceptor borrows the wrapper for the
    /// lifetime of the server; the underlying LmdbCellStore (or any other
    /// backing) outlives both. Holding `*const CellStore` instead of the
    /// concrete impl lets the read-path callers (reactor handlers in
    /// site_server/reactor.zig) depend on the seam, not the impl module.
    cell_store: *const cell_store_mod.CellStore,
    bearer_tokens: *bearer_tokens.TokenStore,
};

/// Decode 64 hex chars into a 32-byte hash. Returns null on bad input.
pub fn decodeHashHex(hex_in: []const u8) ?[32]u8 {
    if (hex_in.len != HASH_HEX_LEN) return null;
    var out: [32]u8 = undefined;
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        const hi: u8 = nibble(hex_in[i * 2]) orelse return null;
        const lo: u8 = nibble(hex_in[i * 2 + 1]) orelse return null;
        out[i] = (hi << 4) | lo;
    }
    return out;
}

fn nibble(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

/// Match a path of shape `/api/v1/cell/<64hex>` (NOT the `/since/` variant)
/// and decode the hash. Returns null when the path doesn't match or the hex
/// segment is malformed.
pub fn parsePath(path: []const u8) ?[32]u8 {
    if (!std.mem.startsWith(u8, path, ROUTE_PREFIX)) return null;
    const tail = path[ROUTE_PREFIX.len..];
    // The `/since/...` route is owned by parseSincePath, not this one.
    if (std.mem.startsWith(u8, tail, "since/")) return null;
    return decodeHashHex(tail);
}

/// D-LC4 — match `/api/v1/cell/since/<64hex>` and decode the prev_state_hash.
///
/// Tolerates an optional `?...` query-string tail (consumed by the
/// D-LC4-pagination follow-up: the handler parses `?after=`/`?limit=`
/// separately via `splitPathQuery`). Without a `?`, the entire tail must
/// be exactly 64 hex chars.
pub fn parseSincePath(path: []const u8) ?[32]u8 {
    if (!std.mem.startsWith(u8, path, SINCE_PREFIX)) return null;
    const tail_full = path[SINCE_PREFIX.len..];
    const q = std.mem.indexOfScalar(u8, tail_full, '?');
    const tail = if (q) |idx| tail_full[0..idx] else tail_full;
    return decodeHashHex(tail);
}

/// D-LC4 follow-up — split a URL path at its `?` separator. Returns the
/// path-prefix and the (possibly-empty) query string AFTER the `?`. If
/// no `?` is present, the entire input is the path and the query is empty.
///
/// Cheap byte-search; no allocation, no validation of the query content
/// (`parseSinceQuery` does that against the keys it understands).
pub fn splitPathQuery(path: []const u8) struct { path: []const u8, query: []const u8 } {
    if (std.mem.indexOfScalar(u8, path, '?')) |idx| {
        return .{ .path = path[0..idx], .query = path[idx + 1 ..] };
    }
    return .{ .path = path, .query = "" };
}

/// D-LC4 follow-up — strongly-typed parse of the query parameters the since
/// endpoint accepts. Returns `.invalid` on any malformed input (unknown
/// keys are ignored — the handler is tolerant of e.g. tracking params).
///
/// Keys understood:
///   - `limit=<positive int>` — clamped to [1, MAX] by the caller.
///   - `after=<64hex>` — decoded to a 32-byte hash.
///
/// Validation rules:
///   - `limit` must parse as a non-negative integer; the value 0 is
///     surfaced (caller decides if 0 → 400). Out-of-range u32 → invalid.
///   - `after` must decode cleanly to 32 bytes — wrong length / non-hex
///     → invalid.
///   - Empty query (`""`) → ok with both fields null. Trailing-`?` case.
pub const SinceQuery = struct {
    limit: ?u32,
    after: ?[32]u8,
};

pub const SinceQueryError = error{
    invalid_limit,
    invalid_after,
};

pub fn parseSinceQuery(query: []const u8) SinceQueryError!SinceQuery {
    var out: SinceQuery = .{ .limit = null, .after = null };
    if (query.len == 0) return out;

    var it = std.mem.splitScalar(u8, query, '&');
    while (it.next()) |kv| {
        if (kv.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, kv, '=') orelse continue;
        const key = kv[0..eq];
        const val = kv[eq + 1 ..];

        if (std.mem.eql(u8, key, "limit")) {
            const n = std.fmt.parseInt(u32, val, 10) catch return error.invalid_limit;
            out.limit = n;
        } else if (std.mem.eql(u8, key, "after")) {
            out.after = decodeHashHex(val) orelse return error.invalid_after;
        }
        // Unknown keys: silently ignored.
    }
    return out;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure path matching + hex decoding. Conformance against
// a live LMDB store lives in tests/cell_raw_http_conformance.zig.
// ─────────────────────────────────────────────────────────────────────

test "decodeHashHex round-trip" {
    const hex = "0011223344556677889900aabbccddeeff00112233445566778899aabbccddee";
    const got = decodeHashHex(hex) orelse @panic("expected Some");
    try std.testing.expectEqual(@as(u8, 0x00), got[0]);
    try std.testing.expectEqual(@as(u8, 0x11), got[1]);
    try std.testing.expectEqual(@as(u8, 0xff), got[16]);
    try std.testing.expectEqual(@as(u8, 0xee), got[31]);
}

test "decodeHashHex rejects wrong length" {
    try std.testing.expectEqual(@as(?[32]u8, null), decodeHashHex("abc"));
    try std.testing.expectEqual(@as(?[32]u8, null), decodeHashHex(""));
}

test "decodeHashHex rejects non-hex chars" {
    const bad = "g0" ** 32;
    try std.testing.expectEqual(@as(?[32]u8, null), decodeHashHex(bad));
}

test "parsePath rejects wrong prefix" {
    try std.testing.expectEqual(@as(?[32]u8, null), parsePath("/api/v1/attachments/foo"));
    try std.testing.expectEqual(@as(?[32]u8, null), parsePath("/api/v1/cell/"));
}

test "parsePath accepts well-formed cell path" {
    const path = "/api/v1/cell/" ++ ("ab" ** 32);
    const got = parsePath(path) orelse @panic("expected Some");
    try std.testing.expectEqual(@as(u8, 0xab), got[0]);
    try std.testing.expectEqual(@as(u8, 0xab), got[31]);
}

test "parsePath rejects /since/ form (owned by parseSincePath)" {
    const path = "/api/v1/cell/since/" ++ ("ab" ** 32);
    try std.testing.expectEqual(@as(?[32]u8, null), parsePath(path));
}

test "parseSincePath accepts well-formed since path" {
    const path = "/api/v1/cell/since/" ++ ("cd" ** 32);
    const got = parseSincePath(path) orelse @panic("expected Some");
    try std.testing.expectEqual(@as(u8, 0xcd), got[0]);
    try std.testing.expectEqual(@as(u8, 0xcd), got[31]);
}

test "parseSincePath rejects non-since cell path" {
    try std.testing.expectEqual(@as(?[32]u8, null),
        parseSincePath("/api/v1/cell/" ++ ("ab" ** 32)));
}

test "parseSincePath strips ?query tail before hex decode" {
    const path = "/api/v1/cell/since/" ++ ("cd" ** 32) ++ "?limit=10";
    const got = parseSincePath(path) orelse @panic("expected Some");
    try std.testing.expectEqual(@as(u8, 0xcd), got[0]);
    try std.testing.expectEqual(@as(u8, 0xcd), got[31]);
}

test "parseSincePath tolerates trailing-? (empty query)" {
    const path = "/api/v1/cell/since/" ++ ("ef" ** 32) ++ "?";
    const got = parseSincePath(path) orelse @panic("expected Some");
    try std.testing.expectEqual(@as(u8, 0xef), got[0]);
}

test "parseSincePath rejects malformed hex even with query" {
    const path = "/api/v1/cell/since/notHex?limit=10";
    try std.testing.expectEqual(@as(?[32]u8, null), parseSincePath(path));
}

test "splitPathQuery — no ?" {
    const r = splitPathQuery("/api/v1/cell/since/abc");
    try std.testing.expectEqualStrings("/api/v1/cell/since/abc", r.path);
    try std.testing.expectEqualStrings("", r.query);
}

test "splitPathQuery — with ?" {
    const r = splitPathQuery("/api/v1/cell/since/abc?limit=5&after=xx");
    try std.testing.expectEqualStrings("/api/v1/cell/since/abc", r.path);
    try std.testing.expectEqualStrings("limit=5&after=xx", r.query);
}

test "splitPathQuery — trailing ?" {
    const r = splitPathQuery("/foo?");
    try std.testing.expectEqualStrings("/foo", r.path);
    try std.testing.expectEqualStrings("", r.query);
}

test "parseSinceQuery — empty returns nulls" {
    const q = try parseSinceQuery("");
    try std.testing.expectEqual(@as(?u32, null), q.limit);
    try std.testing.expectEqual(@as(?[32]u8, null), q.after);
}

test "parseSinceQuery — limit only" {
    const q = try parseSinceQuery("limit=42");
    try std.testing.expectEqual(@as(?u32, 42), q.limit);
    try std.testing.expectEqual(@as(?[32]u8, null), q.after);
}

test "parseSinceQuery — after only" {
    const after_hex = "ab" ** 32;
    var buf: [80]u8 = undefined;
    const q_str = try std.fmt.bufPrint(&buf, "after={s}", .{after_hex});
    const q = try parseSinceQuery(q_str);
    try std.testing.expectEqual(@as(?u32, null), q.limit);
    const got = q.after orelse @panic("expected Some");
    try std.testing.expectEqual(@as(u8, 0xab), got[0]);
    try std.testing.expectEqual(@as(u8, 0xab), got[31]);
}

test "parseSinceQuery — both" {
    const after_hex = "11" ** 32;
    var buf: [128]u8 = undefined;
    const q_str = try std.fmt.bufPrint(&buf, "limit=7&after={s}", .{after_hex});
    const q = try parseSinceQuery(q_str);
    try std.testing.expectEqual(@as(?u32, 7), q.limit);
    const got = q.after orelse @panic("expected Some");
    try std.testing.expectEqual(@as(u8, 0x11), got[0]);
}

test "parseSinceQuery — limit non-numeric → invalid_limit" {
    try std.testing.expectError(error.invalid_limit, parseSinceQuery("limit=foo"));
}

test "parseSinceQuery — after wrong length → invalid_after" {
    try std.testing.expectError(error.invalid_after, parseSinceQuery("after=abcd"));
}

test "parseSinceQuery — after non-hex → invalid_after" {
    const bad = "g0" ** 32;
    var buf: [80]u8 = undefined;
    const q_str = try std.fmt.bufPrint(&buf, "after={s}", .{bad});
    try std.testing.expectError(error.invalid_after, parseSinceQuery(q_str));
}

test "parseSinceQuery — unknown keys silently ignored" {
    const q = try parseSinceQuery("utm_source=x&limit=3");
    try std.testing.expectEqual(@as(?u32, 3), q.limit);
}

```
