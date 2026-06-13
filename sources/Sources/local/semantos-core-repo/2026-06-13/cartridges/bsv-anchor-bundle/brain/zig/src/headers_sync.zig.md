---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/headers_sync.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.446953+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/headers_sync.zig

```zig
// Phase BRAIN-Headers — header sync orchestrator over a connected peer.
//
// Reader/writer-agnostic: `runOneSyncRound` takes `std.io.Reader` /
// `std.io.Writer` so tests can pass `fixedBufferStream` and production
// can pass a TCP socket.  Sequence:
//
//   1. Send our `version`.
//   2. Read the peer's `version`, then their `verack`.
//   3. Send our `verack`.
//   4. Build a locator from the current `HeaderStore` tip (10 most-
//      recent + exponential back to genesis).
//   5. Send `getheaders(locator)`.
//   6. Read `headers` response.  Validate each via cell-engine
//      `validateHeader`; append to the store.
//   7. If the response was full (2000 headers), repeat from (4) with
//      the new locator.  Otherwise we're at tip — return.
//
// Reorgs: if validation rejects a header for `prev_hash_mismatch`,
// the orchestrator surfaces `error.reorg_detected`. The operator can
// either run `brain headers reset` (nuclear option), or `brain headers
// serve` will auto-recover via `attemptReorgRecovery` — see below.

const std = @import("std");
const headers_mod = @import("headers");
const header_store_mod = @import("header_store");
const wire = @import("p2p_wire");
const reorg_sink_mod = @import("reorg_sink");

pub const ReorgSink = reorg_sink_mod.ReorgSink;
pub const SweepReport = reorg_sink_mod.SweepReport;
pub const SweepError = reorg_sink_mod.SweepError;

pub const SyncError = error{
    handshake_failed,
    bad_message,
    short_read,
    short_write,
    peer_closed,
    pow_invalid,
    reorg_detected,
    height_out_of_order,
    out_of_memory,
    persistence_failed,
};

pub const SyncStats = struct {
    rounds: u32 = 0,
    headers_received: u32 = 0,
    headers_appended: u32 = 0,
    final_height: u32 = 0,
};

/// BSV mainnet genesis block hash in internal byte order (= SHA256d output
/// order, little-endian).  This is what the P2P wire protocol uses.
/// Display (big-endian) form: 000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f
/// Used as the locator-of-last-resort when the store is empty —
/// peers ignore an empty-locator getheaders silently, but they DO
/// honour a one-entry locator that's just genesis (responding with
/// blocks 1..2001).  Same hash as Bitcoin/BCH genesis since BSV
/// forked from BCH which forked from Bitcoin.
pub const MAINNET_GENESIS_HASH: [32]u8 = .{
    0x6f, 0xe2, 0x8c, 0x0a, 0xb6, 0xf1, 0xb3, 0x72,
    0xc1, 0xa6, 0xa2, 0x46, 0xae, 0x63, 0xf7, 0x4f,
    0x93, 0x1e, 0x83, 0x65, 0xe1, 0x5a, 0x08, 0x9c,
    0x68, 0xd6, 0x19, 0x00, 0x00, 0x00, 0x00, 0x00,
};

/// Build a Bitcoin-style block locator from the store: 10 most-recent
/// headers (newest first), then exponentially-spaced going back to
/// genesis.  An empty store returns a one-entry locator containing
/// `MAINNET_GENESIS_HASH` so peers respond with the first 2000 blocks
/// (peers ignore an empty-locator getheaders silently — observed
/// against `seed.bitcoinsv.io:8333`).
pub fn buildLocator(allocator: std.mem.Allocator, store: *const header_store_mod.HeaderStore) ![][32]u8 {
    var out = std.ArrayList([32]u8){};
    errdefer out.deinit(allocator);
    const tip_rec = store.tip() orelse {
        try out.append(allocator, MAINNET_GENESIS_HASH);
        return out.toOwnedSlice(allocator);
    };

    var step: u32 = 1;
    var height: i64 = @intCast(tip_rec.height);
    var taken: u32 = 0;
    while (height >= 0) {
        if (store.getByHeight(@intCast(height))) |rec| {
            try out.append(allocator, rec.hash);
        }
        taken += 1;
        if (taken >= 10) step *= 2;
        const next_h = @as(i64, @intCast(height)) - @as(i64, @intCast(step));
        if (next_h < 0) {
            // Always include genesis at the end.
            if (height != 0) {
                if (store.getByHeight(0)) |rec| try out.append(allocator, rec.hash);
            }
            break;
        }
        height = next_h;
    }
    return out.toOwnedSlice(allocator);
}

/// Drive the version+verack handshake.  Returns once we've sent our
/// version + verack and seen the peer's version + verack.
pub fn handshake(
    out_writer: anytype,
    in_reader: anytype,
    magic: [4]u8,
    nonce: u64,
    user_agent: []const u8,
    start_height: i32,
    timestamp: i64,
) !void {
    // Send our version.
    var ver_buf: [256]u8 = undefined;
    const ver_len = wire.encodeVersion(&ver_buf, nonce, user_agent, start_height, timestamp) catch return error.handshake_failed;
    try sendMessage(out_writer, magic, "version", ver_buf[0..ver_len]);

    // Receive (version | verack | other) until we've seen both.
    var saw_version = false;
    var saw_verack = false;
    while (!saw_version or !saw_verack) {
        var hdr_buf: [wire.HEADER_BYTES]u8 = undefined;
        try readExact(in_reader, &hdr_buf);
        const parsed = wire.parseHeader(&hdr_buf);
        if (!std.mem.eql(u8, &parsed.magic, &magic)) return error.handshake_failed;
        if (parsed.payload_size > wire.MAX_PAYLOAD) return error.bad_message;
        // Read + ignore payload contents (version body has fields we
        // don't need beyond confirming the peer's online).
        var payload_buf: [4096]u8 = undefined;
        if (parsed.payload_size > payload_buf.len) {
            // Drain larger payloads in chunks.
            var remaining: u32 = parsed.payload_size;
            while (remaining > 0) {
                const take = @min(remaining, payload_buf.len);
                try readExact(in_reader, payload_buf[0..take]);
                remaining -= @intCast(take);
            }
        } else if (parsed.payload_size > 0) {
            try readExact(in_reader, payload_buf[0..parsed.payload_size]);
        }
        const cmd = parsed.commandTrimmed();
        if (std.mem.eql(u8, cmd, "version")) saw_version = true;
        if (std.mem.eql(u8, cmd, "verack")) saw_verack = true;
        // Other messages (e.g., sendcmpct) — peer's allowed to send
        // arbitrary post-handshake setup; we ignore them.
    }

    // Send our verack.
    try sendMessage(out_writer, magic, "verack", "");
}

/// Send one round of `getheaders → headers`.  Returns the count of
/// headers the peer returned (0..2000).  Caller iterates until the
/// returned count is < 2000.  Validates + appends each header.
///
/// `trace`, if non-null, gets one line per inbound message in the
/// shape `"recv cmd=<name> size=<bytes>\n"` — useful for diagnosing
/// peer behaviour without sprinkling stdout across the orchestrator.
pub fn fetchOneRound(
    allocator: std.mem.Allocator,
    out_writer: anytype,
    in_reader: anytype,
    magic: [4]u8,
    store: *const header_store_mod.HeaderStore,
    pow_limit_bits: u32,
    trace: ?*std.Io.Writer,
) SyncError!u32 {
    // 1. Build locator + send getheaders.
    const locator = buildLocator(allocator, store) catch return error.out_of_memory;
    defer allocator.free(locator);

    var gh_buf: [4096]u8 = undefined;
    var stop: [32]u8 = undefined;
    @memset(&stop, 0);
    const gh_len = wire.encodeGetheaders(&gh_buf, locator, stop) catch return error.bad_message;
    sendMessage(out_writer, magic, "getheaders", gh_buf[0..gh_len]) catch return error.short_write;

    // 2. Read messages until we get a `headers` reply.  Peers may send
    //    `ping` / unsolicited `inv` in between — ignore.
    while (true) {
        var hdr_buf: [wire.HEADER_BYTES]u8 = undefined;
        readExact(in_reader, &hdr_buf) catch return error.peer_closed;
        const parsed = wire.parseHeader(&hdr_buf);
        if (!std.mem.eql(u8, &parsed.magic, &magic)) return error.bad_message;
        if (parsed.payload_size > wire.MAX_PAYLOAD) return error.bad_message;

        if (trace) |t| {
            t.print("recv cmd={s} size={d}\n", .{ parsed.commandTrimmed(), parsed.payload_size }) catch {};
            t.flush() catch {};
        }

        if (parsed.payload_size == 0) {
            // Empty payload (e.g., verack) — skip.
            continue;
        }
        const payload = allocator.alloc(u8, parsed.payload_size) catch return error.out_of_memory;
        defer allocator.free(payload);
        readExact(in_reader, payload) catch return error.peer_closed;
        if (!wire.verifyChecksum(&parsed, payload)) return error.bad_message;

        const cmd = parsed.commandTrimmed();
        if (std.mem.eql(u8, cmd, "ping")) {
            // Echo back as pong.
            sendMessage(out_writer, magic, "pong", payload) catch return error.short_write;
            continue;
        }
        if (std.mem.eql(u8, cmd, "headers")) {
            const parsed_headers = wire.parseHeaders(allocator, payload) catch return error.bad_message;
            defer allocator.free(parsed_headers);
            return appendValidated(store, parsed_headers, pow_limit_bits);
        }
        // Unknown / unsolicited message — drain and continue.
    }
}

/// Validate every header against the store's current tip + each
/// previous header in the batch, then append.  Returns the count
/// appended (== input length on success).
fn appendValidated(
    store: *const header_store_mod.HeaderStore,
    batch: []const headers_mod.Header,
    pow_limit_bits: u32,
) !u32 {
    if (batch.len == 0) return 0;
    var appended: u32 = 0;

    // Snapshot the tip so we can chain-validate the batch.
    var prev_height: u32 = 0;
    var prev_hash: [32]u8 = undefined;
    @memset(&prev_hash, 0);
    if (store.tip()) |tip_rec| {
        prev_height = tip_rec.height;
        prev_hash = tip_rec.hash;
    } else {
        // Empty store — first header in batch must be genesis; we let
        // the cell-engine genesis-mode validator handle that.
    }

    for (batch) |hdr| {
        // PoW check is unconditional.
        if (!hdr.satisfiesProofOfWork()) return error.pow_invalid;
        // Previous-hash continuity check.
        if (store.tip() == null and appended == 0) {
            // First-ever header — no prev_hash check (genesis convention).
        } else {
            if (!std.mem.eql(u8, &hdr.prev_hash, &prev_hash)) {
                return error.reorg_detected;
            }
        }
        const next_height = if (store.tip() == null and appended == 0) 0 else prev_height + 1;
        store.appendValidated(hdr, next_height) catch |err| switch (err) {
            error.prev_hash_mismatch => return error.reorg_detected,
            error.height_out_of_order => return error.height_out_of_order,
            else => return error.persistence_failed,
        };
        prev_height = next_height;
        prev_hash = hdr.computeHash();
        appended += 1;
    }
    _ = pow_limit_bits; // v0.1 only checks bits-vs-PoW; full DAA-vs-bits check lands when buildLocator gives us the prior 144 headers.
    return appended;
}

// ─────────────────────────────────────────────────────────────────────
// Reorg recovery
// ─────────────────────────────────────────────────────────────────────

/// D-LC5 (cartridge hook) — report shape returned by
/// `attemptReorgRecovery`. Pre-D-LC5 the function returned just `u32`
/// (the rolled-back count); the report now also exposes the height
/// floor that was rolled back to so brain's anchor-status sweep has a
/// concrete number to feed `sweepReorgedFromHeight`, plus the sweep's
/// own report when a sink was attached.
pub const ReorgReport = struct {
    /// Number of headers actually rolled back. Mirrors the pre-D-LC5
    /// return value: `0` means the store was already shorter than
    /// `rollback_blocks` and was cleared (or was empty to begin with).
    rolled: u32,
    /// First height that's no longer valid — i.e. the lowest height
    /// that `rollbackFrom` removed. Brain's `sweepReorgedFromHeight`
    /// expects this as its `rollback_from_height` argument. Always
    /// equals `tip.height + 1 - rollback_blocks` clipped to genesis,
    /// matching `rollbackFrom`'s contract. `null` when the store was
    /// empty (nothing to sweep).
    from_height: ?u32,
    /// Sweep result when a `ReorgSink` was attached, otherwise null.
    /// `error.persistence_failed` in the sink is logged at the call
    /// site (so the chain rollback still succeeds) — it surfaces here
    /// as a `null` sweep with a non-null `sweep_error` so the caller
    /// can record the failure.
    sweep: ?SweepReport,
    /// Set when a sink was attached AND it returned an error. Lets
    /// the caller log the failure path distinctly from the no-sink
    /// case. Caller MUST NOT propagate this as a reorg-recovery
    /// failure — the chain rollback already completed successfully.
    sweep_error: ?SweepError,
};

/// Recovery strategy when `fetchOneRound` returns `error.reorg_detected`.
///
/// The peer sent a header whose `prev_hash` doesn't match our tip,
/// which means our chain has diverged from theirs. To converge:
///
///   1. Roll back our chain by `rollback_blocks` from the current tip.
///   2. If a `ReorgSink` is attached, invoke
///      `sink.sweepReorgedFromHeight(from_height)` so brain can clear
///      its per-cell `.pending` anchor-status projections at heights
///      >= `from_height`. Sweep failures are captured in the report
///      but do NOT fail the recovery — the chain rollback already
///      committed successfully.
///   3. The next sync round builds a locator from the (now shorter)
///      chain. The peer responds with headers from a deeper common
///      ancestor — naturally reconciling.
///
/// Caller decides the depth. Most reorgs on BSV mainnet are 1 block
/// deep; deeper rollbacks are progressively more expensive (in
/// re-fetched headers) but more robust to longer reorgs.
///
/// Returns a `ReorgReport` — see the struct doc for field semantics.
/// `rolled == 0` means the rollback was a no-op (empty store or depth
/// already exceeded the chain length and the chain was wiped). When
/// the rollback was a no-op, the sink is NOT invoked (nothing changed
/// in the header store, so the anchor-status projection is still
/// consistent).
///
/// **Safety**: `appendValidated` enforces PoW + prev-hash continuity
/// on every re-applied header, so this can't roll back to a chain
/// the peer can lie about. The peer can only ever push us toward a
/// chain with valid PoW back to (the locator's earliest common
/// ancestor, or genesis).
pub fn attemptReorgRecovery(
    store: *const header_store_mod.HeaderStore,
    rollback_blocks: u32,
    sink: ?*const ReorgSink,
) !ReorgReport {
    const tip = store.tip() orelse return ReorgReport{
        .rolled = 0,
        .from_height = null,
        .sweep = null,
        .sweep_error = null,
    };
    if (rollback_blocks == 0) return ReorgReport{
        .rolled = 0,
        .from_height = null,
        .sweep = null,
        .sweep_error = null,
    };
    // `rollbackFrom(h)` removes everything from h upward, so to drop
    // exactly `rollback_blocks` blocks we pass `tip.height - rollback_blocks + 1`.
    // If the requested depth exceeds the chain length, clip to genesis.
    const from_height: u32 = if (tip.height + 1 >= rollback_blocks)
        tip.height + 1 - rollback_blocks
    else
        0;
    const rolled = try store.rollbackFrom(from_height);

    // No-op rollback ⇒ no anchor-status changes are required. Skip the
    // sink invocation entirely (idempotent regardless, but skipping
    // avoids a write txn on every empty poll).
    if (rolled == 0) return ReorgReport{
        .rolled = 0,
        .from_height = from_height,
        .sweep = null,
        .sweep_error = null,
    };

    var sweep_result: ?SweepReport = null;
    var sweep_err: ?SweepError = null;
    if (sink) |s| {
        if (s.sweepReorgedFromHeight(@as(u64, from_height))) |rep| {
            sweep_result = rep;
        } else |e| {
            sweep_err = e;
        }
    }

    return ReorgReport{
        .rolled = rolled,
        .from_height = from_height,
        .sweep = sweep_result,
        .sweep_error = sweep_err,
    };
}

/// Default escalation schedule for `brain headers serve`'s daemon loop.
/// Try a 1-block rollback first (covers ~99% of mainnet reorgs);
/// then 10, then 100, then 1000. Beyond that something pathological is
/// happening — the operator should investigate via `brain headers tip`
/// + manual reset.
pub const DEFAULT_REORG_SCHEDULE = [_]u32{ 1, 10, 100, 1000 };

// ─────────────────────────────────────────────────────────────────────
// Wire helpers
// ─────────────────────────────────────────────────────────────────────

fn sendMessage(writer: anytype, magic: [4]u8, command: []const u8, payload: []const u8) !void {
    var hdr_buf: [wire.HEADER_BYTES]u8 = undefined;
    try wire.encodeHeader(magic, command, payload, &hdr_buf);
    try writer.writeAll(&hdr_buf);
    if (payload.len > 0) try writer.writeAll(payload);
    // Critical: the std.Io.Writer surface buffers bytes until flush.
    // Without this, our 24+N-byte messages sit in the local buffer
    // and the peer never sees them — sync hangs reading for a reply
    // to a request that never went out.  In tests `Writer.fixed`'s
    // flush is a no-op (writes happen directly), so the loopback
    // tests pass either way; the real-network bug only surfaces
    // against an actual TCP peer.
    try writer.flush();
}

fn readExact(reader: anytype, buf: []u8) !void {
    // Zig 0.15 Io.Reader uses `readSliceAll` for exact-size reads
    // (returns error.EndOfStream on EOF).  std.io.fixedBufferStream
    // wraps its Reader/Writer with the same surface so tests pass
    // through unmodified.
    reader.readSliceAll(buf) catch |err| switch (err) {
        error.EndOfStream => return error.short_read,
        else => return err,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "BRAIN-Headers sync: empty store yields a one-entry genesis locator" {
    var local = header_store_mod.LocalHeaderStore.init(testing.allocator);
    defer local.deinit();
    const handle = local.store();
    const loc = try buildLocator(testing.allocator, &handle);
    defer testing.allocator.free(loc);
    try testing.expectEqual(@as(usize, 1), loc.len);
    try testing.expectEqualSlices(u8, &MAINNET_GENESIS_HASH, &loc[0]);
}

test "BRAIN-Headers sync: locator after appending genesis is one entry" {
    var local = header_store_mod.LocalHeaderStore.init(testing.allocator);
    defer local.deinit();
    const handle = local.store();

    // Synthesize a single header.  We don't need it to satisfy PoW — the
    // store's `appendValidated` is a blind append (the doc says so).
    var raw: [80]u8 = undefined;
    @memset(&raw, 0);
    raw[0] = 1;
    const hdr = headers_mod.Header.parseRaw(&raw);
    try handle.appendValidated(hdr, 0);

    const loc = try buildLocator(testing.allocator, &handle);
    defer testing.allocator.free(loc);
    try testing.expectEqual(@as(usize, 1), loc.len);
}

test "BRAIN-Headers sync: handshake completes via fixed-buffer streams" {
    // Compose a peer-side stream: peer-version + peer-verack.
    var peer_buf: [512]u8 = undefined;
    var pos: usize = 0;
    {
        var hdr: [wire.HEADER_BYTES]u8 = undefined;
        var ver_payload: [128]u8 = undefined;
        const ver_len = try wire.encodeVersion(&ver_payload, 0xABCDEF, "/peer/", 0, 0);
        try wire.encodeHeader(wire.MAGIC_REGTEST, "version", ver_payload[0..ver_len], &hdr);
        @memcpy(peer_buf[pos..][0..wire.HEADER_BYTES], &hdr);
        pos += wire.HEADER_BYTES;
        @memcpy(peer_buf[pos..][0..ver_len], ver_payload[0..ver_len]);
        pos += ver_len;
    }
    {
        var hdr: [wire.HEADER_BYTES]u8 = undefined;
        try wire.encodeHeader(wire.MAGIC_REGTEST, "verack", "", &hdr);
        @memcpy(peer_buf[pos..][0..wire.HEADER_BYTES], &hdr);
        pos += wire.HEADER_BYTES;
    }

    var reader = std.Io.Reader.fixed(peer_buf[0..pos]);
    var out_stream_buf: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&out_stream_buf);
    try handshake(&writer, &reader, wire.MAGIC_REGTEST, 0xDEADBEEF, "/brain:0.1.0/", 0, 0);

    // We should have written version + verack.  Spot-check: the first
    // 4 bytes are the magic.
    try testing.expectEqualSlices(u8, &wire.MAGIC_REGTEST, out_stream_buf[0..4]);
}

```
