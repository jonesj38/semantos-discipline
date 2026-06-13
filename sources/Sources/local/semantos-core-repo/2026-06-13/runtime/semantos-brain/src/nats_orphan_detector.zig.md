---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/nats_orphan_detector.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.243315+00:00
---

# runtime/semantos-brain/src/nats_orphan_detector.zig

```zig
// W7.13 — NATS orphan stream detection.
//
// An "orphan" stream is a JetStream stream whose name follows the
// `op_<op_pkh16>` convention but whose op_pkh16 does not appear in the
// caller-supplied set of known active operators.  Orphans arise when an
// operator exit loses its NATS step (e.g. brain crash after LMDB delete but
// before deleteStream, or a manual Postgres cleanup without a brain exit).
//
// This module is intentionally zero-Postgres: the caller queries Postgres for
// active op_pkhs and passes them in.  The brain has no libpq dependency and
// should not grow one; the orphan detection script (tools/deploy/) is the
// integration point between the two.
//
// Public API:
//   detectOrphans(allocator, client, known_op_pkh16s) !OrphanList
//   purgeOrphans(allocator, client, known_op_pkh16s)  !OrphanReport
//
// W7.13 acceptance: streams created and torn down idempotently; orphan
// detection runs nightly via systemd timer (tools/deploy/).

const std = @import("std");
const nats_client = @import("nats_client");
const NatsClient = nats_client.NatsClient;

// Stream names we create follow: op_<op_pkh16>  (18 chars: "op_" + 16 hex).
const STREAM_PREFIX = "op_";
const OP_PKH16_LEN = 16;
const STREAM_NAME_LEN = STREAM_PREFIX.len + OP_PKH16_LEN; // 19

pub const OrphanList = struct {
    /// Caller owns both the slice and each name string.
    names: [][]u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: OrphanList) void {
        for (self.names) |n| self.allocator.free(n);
        self.allocator.free(self.names);
    }
};

pub const OrphanReport = struct {
    detected: u32,
    purged: u32,
    failed: u32,
};

/// Return all JetStream streams that follow the `op_<op_pkh16>` naming
/// convention but whose op_pkh16 is not in `known_op_pkh16s`.
///
/// `known_op_pkh16s`: slice of 16-char hex strings (one per active operator).
/// Caller retains ownership of these strings; they are not freed here.
pub fn detectOrphans(
    allocator: std.mem.Allocator,
    client: *NatsClient,
    known_op_pkh16s: []const []const u8,
) !OrphanList {
    const all_names = try client.streamNames(allocator);
    defer {
        for (all_names) |n| allocator.free(n);
        allocator.free(all_names);
    }

    var orphans: std.ArrayList([]u8) = .{};
    errdefer {
        for (orphans.items) |n| allocator.free(n);
        orphans.deinit(allocator);
    }

    for (all_names) |name| {
        if (!isOperatorStream(name)) continue;
        const pkh16 = name[STREAM_PREFIX.len..];
        if (!isKnown(pkh16, known_op_pkh16s)) {
            try orphans.append(allocator, try allocator.dupe(u8, name));
        }
    }

    return OrphanList{
        .names = try orphans.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

/// Detect and delete all orphan streams.  Returns counts.
/// Each deletion is attempted independently; a failed deletion increments
/// `failed` but does not abort the rest.
pub fn purgeOrphans(
    allocator: std.mem.Allocator,
    client: *NatsClient,
    known_op_pkh16s: []const []const u8,
) !OrphanReport {
    const orphan_list = try detectOrphans(allocator, client, known_op_pkh16s);
    defer orphan_list.deinit();

    var purged: u32 = 0;
    var failed: u32 = 0;

    for (orphan_list.names) |name| {
        client.streamDelete(name) catch {
            failed += 1;
            continue;
        };
        purged += 1;
    }

    return OrphanReport{
        .detected = @intCast(orphan_list.names.len),
        .purged = purged,
        .failed = failed,
    };
}

// ── Internal helpers ──────────────────────────────────────────────────────

fn isOperatorStream(name: []const u8) bool {
    if (name.len != STREAM_NAME_LEN) return false;
    if (!std.mem.startsWith(u8, name, STREAM_PREFIX)) return false;
    for (name[STREAM_PREFIX.len..]) |c| {
        const valid = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f');
        if (!valid) return false;
    }
    return true;
}

fn isKnown(pkh16: []const u8, known: []const []const u8) bool {
    for (known) |k| {
        if (std.mem.eql(u8, pkh16, k)) return true;
    }
    return false;
}

// ── Inline tests ──────────────────────────────────────────────────────────

test "isOperatorStream: accepts valid op_ stream names" {
    try std.testing.expect(isOperatorStream("op_a3f7b2c1d4e5f6a7"));
    try std.testing.expect(isOperatorStream("op_0000000000000000"));
    try std.testing.expect(isOperatorStream("op_deadbeefcafefed0"));
}

test "isOperatorStream: rejects non-operator streams" {
    // Wrong prefix
    try std.testing.expect(!isOperatorStream("brain_a3f7b2c1d4e5f6a7"));
    // Too short
    try std.testing.expect(!isOperatorStream("op_a3f7b2c1"));
    // Too long
    try std.testing.expect(!isOperatorStream("op_a3f7b2c1d4e5f6a7ff"));
    // Non-hex suffix
    try std.testing.expect(!isOperatorStream("op_a3f7b2c1d4e5f6zz"));
    // Uppercase hex (we use lowercase only)
    try std.testing.expect(!isOperatorStream("op_A3F7B2C1D4E5F6A7"));
}

test "isKnown: finds match" {
    const known = [_][]const u8{ "a3f7b2c1d4e5f6a7", "deadbeefcafefed0" };
    try std.testing.expect(isKnown("a3f7b2c1d4e5f6a7", &known));
    try std.testing.expect(isKnown("deadbeefcafefed0", &known));
    try std.testing.expect(!isKnown("0000000000000000", &known));
}

test "isKnown: empty known list" {
    const known = [_][]const u8{};
    try std.testing.expect(!isKnown("a3f7b2c1d4e5f6a7", &known));
}

test "detectOrphans: filters out known operators" {
    // Pure logic test: if a stream name is known, it should not appear in orphans.
    // isOperatorStream + isKnown together implement the filter.
    const candidates = [_][]const u8{
        "op_a3f7b2c1d4e5f6a7", // known → not orphan
        "op_deadbeefcafefed0", // unknown → orphan
        "brain_metrics",       // wrong prefix → not an op stream
    };
    const known = [_][]const u8{"a3f7b2c1d4e5f6a7"};

    var orphan_count: u32 = 0;
    for (candidates) |name| {
        if (!isOperatorStream(name)) continue;
        const pkh16 = name[STREAM_PREFIX.len..];
        if (!isKnown(pkh16, &known)) orphan_count += 1;
    }
    try std.testing.expectEqual(@as(u32, 1), orphan_count);
}

```
