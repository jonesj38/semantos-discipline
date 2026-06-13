---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/federation_prune_guard.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.219346+00:00
---

# runtime/semantos-brain/src/federation_prune_guard.zig

```zig
// WI-C2 — Federation-aware pruning guard.
//
// Before the host calls pask_finalize for a prune-eligible node, it consults
// this guard. If any peer kernel has emitted a `keep_alive` signal for that
// cell within the configured window, pruning is suppressed at the host level.
// The kernel itself remains unchanged — its prune rule stays local.
//
// Integration contract (host side):
//   1. Subscribe to the `federation_keep_alive` NATS subject.
//   2. On each message, call recordKeepAlive(cell_id, timestamp_ms).
//   3. Before calling pask_finalize for a node, call:
//        if (guard.shouldSuppressPrune(cell_id, now_ms, window_ms)) continue;
//
// The guard is a plain fixed-size value (no allocator) suitable for stack or
// static allocation. MAX_ENTRIES cap covers federation pools up to 256 cells
// with active peer watchers — scale by adjusting the constant if needed.
//
// Tests (inline — no live NATS):
//   WI-C2-T-prune-suppressed-by-peer-signal
//   WI-C2-T-prune-proceeds-without-peer-signal
//
// See research/cognition-implementation-plan.md §WI-C2.

const std = @import("std");

pub const MAX_ENTRIES = 256;
pub const MAX_CELL_ID = 64;

pub const KeepAliveEntry = struct {
    cell_id_buf: [MAX_CELL_ID]u8,
    cell_id_len: u32,
    timestamp_ms: u64,
};

pub const FederationPruneGuard = struct {
    entries: [MAX_ENTRIES]KeepAliveEntry,
    count: u32,

    pub fn init(self: *FederationPruneGuard) void {
        self.count = 0;
        @memset(std.mem.asBytes(&self.entries), 0);
    }

    /// Record a keep_alive signal from a peer kernel for the given cell.
    /// If the cell is already tracked, the timestamp is bumped to max(old, new).
    /// If MAX_ENTRIES is reached, the oldest entry is overwritten (ring eviction).
    pub fn recordKeepAlive(
        self: *FederationPruneGuard,
        cell_id: []const u8,
        timestamp_ms: u64,
    ) void {
        if (cell_id.len == 0 or cell_id.len > MAX_CELL_ID) return;

        // Update existing entry.
        var i: u32 = 0;
        while (i < self.count) : (i += 1) {
            const e = &self.entries[i];
            if (e.cell_id_len == cell_id.len and
                std.mem.eql(u8, cell_id, e.cell_id_buf[0..e.cell_id_len]))
            {
                e.timestamp_ms = @max(e.timestamp_ms, timestamp_ms);
                return;
            }
        }

        // Append or overwrite oldest (simple linear eviction when full).
        const slot: u32 = if (self.count < MAX_ENTRIES) blk: {
            const s = self.count;
            self.count += 1;
            break :blk s;
        } else blk: {
            // Find oldest
            var oldest: u32 = 0;
            var oldest_ts: u64 = self.entries[0].timestamp_ms;
            var j: u32 = 1;
            while (j < MAX_ENTRIES) : (j += 1) {
                if (self.entries[j].timestamp_ms < oldest_ts) {
                    oldest_ts = self.entries[j].timestamp_ms;
                    oldest = j;
                }
            }
            break :blk oldest;
        };

        const e = &self.entries[slot];
        @memcpy(e.cell_id_buf[0..cell_id.len], cell_id);
        e.cell_id_len = @intCast(cell_id.len);
        e.timestamp_ms = timestamp_ms;
    }

    /// Returns true if the cell has a recent peer keep_alive within the window.
    /// `window_ms` is the look-back duration (e.g. 30_000 ms).
    pub fn shouldSuppressPrune(
        self: *const FederationPruneGuard,
        cell_id: []const u8,
        now_ms: u64,
        window_ms: u64,
    ) bool {
        const since: u64 = if (now_ms > window_ms) now_ms - window_ms else 0;
        var i: u32 = 0;
        while (i < self.count) : (i += 1) {
            const e = &self.entries[i];
            if (e.cell_id_len == cell_id.len and
                std.mem.eql(u8, cell_id, e.cell_id_buf[0..e.cell_id_len]))
            {
                return e.timestamp_ms >= since;
            }
        }
        return false;
    }
};

// ── Inline tests ──────────────────────────────────────────────────────────────

const testing = std.testing;

test "WI-C2-T-prune-suppressed-by-peer-signal" {
    var guard: FederationPruneGuard = undefined;
    guard.init();

    // Peer emits keep_alive for "cell-alpha" at t=500ms.
    guard.recordKeepAlive("cell-alpha", 500);

    // At t=1000ms with a 1000ms window, 500 >= 0 → suppress.
    try testing.expect(guard.shouldSuppressPrune("cell-alpha", 1000, 1000));
}

test "WI-C2-T-prune-proceeds-without-peer-signal" {
    var guard: FederationPruneGuard = undefined;
    guard.init();

    // No keep_alive recorded for "cell-beta".
    try testing.expect(!guard.shouldSuppressPrune("cell-beta", 1000, 1000));
}

test "expired keep_alive does not suppress prune" {
    var guard: FederationPruneGuard = undefined;
    guard.init();

    // Signal was at t=100ms; now=2000ms, window=1000ms → since=1000, 100 < 1000 → expired.
    guard.recordKeepAlive("cell-gamma", 100);
    try testing.expect(!guard.shouldSuppressPrune("cell-gamma", 2000, 1000));
}

test "second recordKeepAlive bumps timestamp" {
    var guard: FederationPruneGuard = undefined;
    guard.init();

    guard.recordKeepAlive("cell-delta", 200);
    guard.recordKeepAlive("cell-delta", 1500); // newer signal

    // now=2000, window=1000 → since=1000, 1500 >= 1000 → suppress
    try testing.expect(guard.shouldSuppressPrune("cell-delta", 2000, 1000));
}

test "MAX_ENTRIES eviction preserves most recent signals" {
    var guard: FederationPruneGuard = undefined;
    guard.init();

    // Fill all slots with old signals (ts=1).
    var buf: [8]u8 = undefined;
    var i: u32 = 0;
    while (i < MAX_ENTRIES) : (i += 1) {
        const name = std.fmt.bufPrint(&buf, "c{d}", .{i}) catch unreachable;
        guard.recordKeepAlive(name, 1);
    }
    // Add one more with a fresh timestamp — evicts the oldest.
    guard.recordKeepAlive("fresh-cell", 9999);
    // The fresh cell is recent → suppressed.
    try testing.expect(guard.shouldSuppressPrune("fresh-cell", 10000, 1000));
}

```
