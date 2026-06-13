---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/resources/headers_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.451761+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/resources/headers_handler.zig

```zig
// Phase D-W1 / Phase 2 — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md
// §3 (the `headers` row), §8 Phase 2, §10 (audit_reads opt-out).
//
// Dispatcher resource handler that fronts the file-backed
// `header_store_fs.zig`.  Every read transport (REPL / CLI verbs /
// helm SPA / future SPV peers over HTTP / SignedBundle mesh) reaches
// the verified-header chain through this handler.
//
// MVP scope (this PR):
//   • Read commands: `tip`, `byHeight`, `byHash`, `range`, `sync_state`.
//   • Mutating `append_validated` is DEFERRED — the design row says
//     "headers-verifier WASM only", and modelling that "internal
//     system caller" auth context cleanly is its own design step
//     (see BRAIN-DISPATCHER-UNIFICATION.md §3 row + §7).  The handler
//     declares the command's cap so the dispatcher knows about it,
//     but `handle_fn` returns `error.not_yet_implemented` until the
//     follow-up lands.  TODO(D-W1 P2 follow-up): wire a typed
//     `AuthContext.system_caller` variant for the headers-verifier
//     WASM module's host-imported `appendValidated`.
//
// Audit semantics (per §10):
//   • All commands here are reads.  `audit_reads = false` is set on
//     the registration so high-frequency `byHeight`/`byHash` traffic
//     from peer SPV clients doesn't flood the audit log.  Reads
//     emit a single `phase=skip kind=read_no_audit` line; mutations
//     would always emit the full pair if/when `append_validated`
//     lands.
//
// Wire shapes:
//
//   tip          — {}
//                  → {"present":bool, "height"?:N,
//                     "hash"?:"<little-endian hex>"}
//                  cap = .none
//
//   byHeight     — { height: N }
//                  → {"present":bool, "header_hex"?:"<160 chars>",
//                     "hash"?:"<little-endian hex>"}
//                  cap = .none
//
//   byHash       — { hash: "<little-endian hex (64 chars)>" }
//                  → same shape as byHeight (`hash` is the
//                    little-endian internal form, not the
//                    block-explorer reverse-byte form — callers
//                    that want the explorer convention reverse
//                    on display).
//                  cap = .none
//
//   range        — { from: N, to: M }
//                  → {"count":N, "headers":[{height, hash, header_hex}, ...]}
//                  Soft-capped at 2000 records per call so a single
//                  request can't materialise the whole chain in
//                  one allocator buffer (matches the BSV `getheaders`
//                  P2P limit).
//                  cap = .none
//
//   sync_state   — {}
//                  → {"tip_height":N, "tip_present":bool}
//                    (Phase 2 MVP — future expansions: peer status,
//                     last-sync-attempt unix-secs, reorg counters.
//                     Today `headers_sync.zig` doesn't yet expose
//                     a stable observability surface, so we ship
//                     the minimum the helm dashboard needs.)
//                  cap = .none

const std = @import("std");
const dispatcher = @import("dispatcher");
const header_store_mod = @import("header_store");
const header_store_fs_mod = @import("header_store_fs");

pub const RESOURCE_NAME = "headers";

/// Soft cap on `range` size.  Mirrors the BSV `getheaders` P2P limit
/// so peer SPV clients hitting this endpoint over HTTP get the same
/// page size they'd get over the wire protocol.
pub const MAX_RANGE: u32 = 2000;

pub const HandlerError = error{
    invalid_args,
    /// `range` from > to, or to - from > MAX_RANGE.
    range_too_large,
    /// Underlying store I/O failed.
    store_error,
    /// `append_validated` reserved for the headers-verifier WASM
    /// module — Phase 2 MVP returns this until the system-caller
    /// auth wiring lands.  See module header note.
    not_yet_implemented,
    out_of_memory,
};

pub const Handler = struct {
    allocator: std.mem.Allocator,
    /// Borrowed reference to the file-backed store (or any conforming
    /// `HeaderStore`).  Caller (cmdServe / embedded-mode / tests)
    /// owns the storage backing.
    store: *const header_store_mod.HeaderStore,
    /// All entries are reads — no concurrent-mutation worry — but we
    /// still serialise to keep the contract identical to the other
    /// handlers (and to simplify a future `append_validated` migration).
    mu: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator, store: *const header_store_mod.HeaderStore) Handler {
        return .{
            .allocator = allocator,
            .store = store,
            .mu = .{},
        };
    }

    pub fn resourceHandler(self: *Handler) dispatcher.ResourceHandler {
        return .{
            .name = RESOURCE_NAME,
            .state = self,
            .cap_for_cmd_fn = capForCmd,
            .handle_fn = handle,
            .audit_reads = false,
            .is_read_fn = isRead,
        };
    }
};

fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    if (std.mem.eql(u8, cmd, "tip")) return .none;
    if (std.mem.eql(u8, cmd, "byHeight")) return .none;
    if (std.mem.eql(u8, cmd, "byHash")) return .none;
    if (std.mem.eql(u8, cmd, "range")) return .none;
    if (std.mem.eql(u8, cmd, "sync_state")) return .none;
    if (std.mem.eql(u8, cmd, "append_validated")) return .none; // gated by handle path
    return error.unknown_command;
}

pub fn isRead(cmd: []const u8) bool {
    if (std.mem.eql(u8, cmd, "tip")) return true;
    if (std.mem.eql(u8, cmd, "byHeight")) return true;
    if (std.mem.eql(u8, cmd, "byHash")) return true;
    if (std.mem.eql(u8, cmd, "range")) return true;
    if (std.mem.eql(u8, cmd, "sync_state")) return true;
    return false;
}

fn handle(
    state: ?*anyopaque,
    _: *const dispatcher.DispatchContext,
    cmd: []const u8,
    args_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!dispatcher.Result {
    const self: *Handler = @ptrCast(@alignCast(state.?));
    self.mu.lock();
    defer self.mu.unlock();

    if (std.mem.eql(u8, cmd, "tip")) return handleTip(self, allocator);
    if (std.mem.eql(u8, cmd, "byHeight")) return handleByHeight(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "byHash")) return handleByHash(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "range")) return handleRange(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "sync_state")) return handleSyncState(self, allocator);
    if (std.mem.eql(u8, cmd, "append_validated")) return HandlerError.not_yet_implemented;
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// tip
// ─────────────────────────────────────────────────────────────────────

fn handleTip(self: *Handler, allocator: std.mem.Allocator) !dispatcher.Result {
    if (self.store.tip()) |rec| {
        var hex: [64]u8 = undefined;
        hexEncode(&rec.hash, &hex);
        const payload = try std.fmt.allocPrint(
            allocator,
            "{{\"present\":true,\"height\":{d},\"hash\":\"{s}\"}}",
            .{ rec.height, hex },
        );
        return dispatcher.Result.ownedPayload(allocator, payload);
    }
    const payload = try allocator.dupe(u8, "{\"present\":false}");
    return dispatcher.Result.ownedPayload(allocator, payload);
}

// ─────────────────────────────────────────────────────────────────────
// byHeight
// ─────────────────────────────────────────────────────────────────────

fn handleByHeight(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch return HandlerError.invalid_args;
    defer parsed.deinit();
    if (parsed.value != .object) return HandlerError.invalid_args;
    const obj = parsed.value.object;
    const h_v = obj.get("height") orelse return HandlerError.invalid_args;
    if (h_v != .integer or h_v.integer < 0) return HandlerError.invalid_args;
    const height: u32 = std.math.cast(u32, h_v.integer) orelse return HandlerError.invalid_args;

    if (self.store.getByHeight(height)) |rec| {
        return try recordPayload(allocator, rec);
    }
    const payload = try allocator.dupe(u8, "{\"present\":false}");
    return dispatcher.Result.ownedPayload(allocator, payload);
}

// ─────────────────────────────────────────────────────────────────────
// byHash
// ─────────────────────────────────────────────────────────────────────

fn handleByHash(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch return HandlerError.invalid_args;
    defer parsed.deinit();
    if (parsed.value != .object) return HandlerError.invalid_args;
    const obj = parsed.value.object;
    const hash_v = obj.get("hash") orelse return HandlerError.invalid_args;
    if (hash_v != .string or hash_v.string.len != 64) return HandlerError.invalid_args;

    var hash: [32]u8 = undefined;
    hexDecode(hash_v.string, &hash) catch return HandlerError.invalid_args;

    if (self.store.getByHash(&hash)) |rec| {
        return try recordPayload(allocator, rec);
    }
    const payload = try allocator.dupe(u8, "{\"present\":false}");
    return dispatcher.Result.ownedPayload(allocator, payload);
}

// ─────────────────────────────────────────────────────────────────────
// range
// ─────────────────────────────────────────────────────────────────────

fn handleRange(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch return HandlerError.invalid_args;
    defer parsed.deinit();
    if (parsed.value != .object) return HandlerError.invalid_args;
    const obj = parsed.value.object;
    const from_v = obj.get("from") orelse return HandlerError.invalid_args;
    const to_v = obj.get("to") orelse return HandlerError.invalid_args;
    if (from_v != .integer or to_v != .integer) return HandlerError.invalid_args;
    if (from_v.integer < 0 or to_v.integer < 0) return HandlerError.invalid_args;
    if (to_v.integer < from_v.integer) return HandlerError.invalid_args;
    if (to_v.integer - from_v.integer + 1 > @as(i64, @intCast(MAX_RANGE))) return HandlerError.range_too_large;

    const from: u32 = std.math.cast(u32, from_v.integer) orelse return HandlerError.invalid_args;
    const to: u32 = std.math.cast(u32, to_v.integer) orelse return HandlerError.invalid_args;

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    var count: u32 = 0;
    try buf.appendSlice(allocator, "{\"count\":");
    const count_placeholder_at = buf.items.len;
    // Reserve a fixed-width count placeholder; we'll overwrite it
    // post-loop.  6 chars supports counts up to 999999, which is
    // 500x our MAX_RANGE — plenty.
    try buf.appendSlice(allocator, "       ");
    try buf.appendSlice(allocator, ",\"headers\":[");
    var first = true;
    var h: u32 = from;
    while (h <= to) : (h += 1) {
        const rec_opt = self.store.getByHeight(h);
        const rec = rec_opt orelse break;
        if (!first) try buf.append(allocator, ',');
        first = false;
        var hash_hex: [64]u8 = undefined;
        hexEncode(&rec.hash, &hash_hex);
        var raw: [80]u8 = undefined;
        rec.header.serialize(&raw);
        var raw_hex: [160]u8 = undefined;
        hexEncode(&raw, &raw_hex);
        try buf.print(
            allocator,
            "{{\"height\":{d},\"hash\":\"{s}\",\"header_hex\":\"{s}\"}}",
            .{ rec.height, hash_hex, raw_hex },
        );
        count += 1;
        if (h == to) break;
    }
    try buf.appendSlice(allocator, "]}");

    // Patch the count.
    var count_buf: [8]u8 = undefined;
    const count_str = std.fmt.bufPrint(&count_buf, "{d}", .{count}) catch unreachable;
    // The placeholder is exactly 7 spaces; left-pad the count into
    // that field so the JSON shape stays valid.
    const slot = buf.items[count_placeholder_at .. count_placeholder_at + 7];
    @memset(slot, ' ');
    @memcpy(slot[0..count_str.len], count_str);

    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

// ─────────────────────────────────────────────────────────────────────
// sync_state
// ─────────────────────────────────────────────────────────────────────

fn handleSyncState(self: *Handler, allocator: std.mem.Allocator) !dispatcher.Result {
    if (self.store.tip()) |rec| {
        const payload = try std.fmt.allocPrint(
            allocator,
            "{{\"tip_present\":true,\"tip_height\":{d}}}",
            .{rec.height},
        );
        return dispatcher.Result.ownedPayload(allocator, payload);
    }
    const payload = try allocator.dupe(u8, "{\"tip_present\":false,\"tip_height\":0}");
    return dispatcher.Result.ownedPayload(allocator, payload);
}

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

fn recordPayload(allocator: std.mem.Allocator, rec: header_store_mod.HeaderRecord) !dispatcher.Result {
    var hash_hex: [64]u8 = undefined;
    hexEncode(&rec.hash, &hash_hex);
    var raw: [80]u8 = undefined;
    rec.header.serialize(&raw);
    var raw_hex: [160]u8 = undefined;
    hexEncode(&raw, &raw_hex);
    const payload = try std.fmt.allocPrint(
        allocator,
        "{{\"present\":true,\"height\":{d},\"hash\":\"{s}\",\"header_hex\":\"{s}\"}}",
        .{ rec.height, hash_hex, raw_hex },
    );
    return dispatcher.Result.ownedPayload(allocator, payload);
}

fn hexEncode(bytes: []const u8, out: []u8) void {
    const charset = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2 + 0] = charset[(b >> 4) & 0xf];
        out[i * 2 + 1] = charset[b & 0xf];
    }
}

fn hexDecode(hex: []const u8, out: []u8) !void {
    if (hex.len != out.len * 2) return error.bad_length;
    for (0..out.len) |i| {
        const hi = try nibble(hex[i * 2]);
        const lo = try nibble(hex[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
    }
}

fn nibble(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => 10 + (c - 'a'),
        'A'...'F' => 10 + (c - 'A'),
        else => error.bad_hex,
    };
}

```
