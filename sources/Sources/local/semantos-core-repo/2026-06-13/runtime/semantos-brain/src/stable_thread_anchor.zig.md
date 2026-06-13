---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/stable_thread_anchor.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.255251+00:00
---

# runtime/semantos-brain/src/stable_thread_anchor.zig

```zig
// WI-D1 — Stable-thread Merkle anchor.
//
// When the local kernel's stable-thread set has been identical (no churn in
// the top-K stable cells) for N consecutive snapshots, this module computes
// a Merkle root over the stable cell IDs and records the anchor data.
//
// "Publishing" the Merkle root to chain (via a stateful sCrypt cell) is the
// caller's responsibility — this module only produces the data structure and
// decides when the threshold is crossed.
//
// Usage:
//   var anchor: StableThreadAnchor = undefined;
//   anchor.init(cfg);
//   // After each pask_interact cycle:
//   anchor.recordSnapshot(stable_cells_slice, seq, now_ms);
//   if (anchor.shouldAnchor()) {
//       const root = anchor.merkleRoot();
//       // → mint the sCrypt cell with (kernel_id, seq, root, now_ms)
//       anchor.markAnchored(); // resets churn counter
//   }
//
// Anchor data:
//   kernel_id     — external (passed to markAnchored)
//   snapshot_seq  — monotonically increasing snapshot sequence number
//   merkle_root   — SHA-256 binary Merkle root of the stable cell IDs
//   timestamp_ms  — caller-supplied clock
//
// Tests (inline):
//   WI-D1-T-anchor-on-threshold
//   WI-D1-T-merkle-roundtrip
//
// See research/cognition-implementation-plan.md §WI-D1.

const std = @import("std");

pub const MAX_STABLE_CELLS = 128;
pub const MAX_CELL_ID = 64;
pub const HASH_LEN = 32; // SHA-256

pub const AnchorConfig = struct {
    /// Number of consecutive stable-identical snapshots required before anchoring.
    confirmation_threshold: u32,
    /// Top-K stable cells tracked (must be ≤ MAX_STABLE_CELLS).
    top_k: u32,
};

pub const DEFAULT_ANCHOR_CONFIG = AnchorConfig{
    .confirmation_threshold = 3,
    .top_k = 10,
};

/// Represents one stable thread for Merkle hashing.
pub const StableCell = struct {
    cell_id: [MAX_CELL_ID]u8,
    cell_id_len: u32,

    pub fn slice(self: *const StableCell) []const u8 {
        return self.cell_id[0..self.cell_id_len];
    }
};

pub const AnchorRecord = struct {
    snapshot_seq: u64,
    merkle_root: [HASH_LEN]u8,
    timestamp_ms: u64,
    cells_count: u32,
};

pub const StableThreadAnchor = struct {
    cfg: AnchorConfig,
    /// Consecutive snapshots with no churn in top-K.
    consecutive_stable: u32,
    /// Snapshot sequence counter.
    seq: u64,
    /// Whether an anchor is ready.
    anchor_pending: bool,
    /// The anchor data once `shouldAnchor` is true.
    pending: AnchorRecord,
    /// Previous snapshot fingerprint for churn detection (SHA-256 of cell-id list).
    prev_fingerprint: [HASH_LEN]u8,
    prev_fingerprint_valid: bool,

    pub fn init(self: *StableThreadAnchor, cfg: AnchorConfig) void {
        self.cfg = cfg;
        self.consecutive_stable = 0;
        self.seq = 0;
        self.anchor_pending = false;
        self.prev_fingerprint_valid = false;
        @memset(&self.prev_fingerprint, 0);
        self.pending = std.mem.zeroes(AnchorRecord);
    }

    /// Record a snapshot of the current stable-thread set.
    /// `cells` should be the top-K stable cells in descending h_state order.
    pub fn recordSnapshot(
        self: *StableThreadAnchor,
        cells: []const StableCell,
        now_ms: u64,
    ) void {
        self.seq += 1;
        const fp = fingerprintCells(cells);
        if (self.prev_fingerprint_valid and
            std.mem.eql(u8, &fp, &self.prev_fingerprint))
        {
            self.consecutive_stable += 1;
        } else {
            self.consecutive_stable = 1;
            self.prev_fingerprint = fp;
            self.prev_fingerprint_valid = true;
        }

        if (self.consecutive_stable >= self.cfg.confirmation_threshold and
            !self.anchor_pending)
        {
            self.anchor_pending = true;
            self.pending = .{
                .snapshot_seq = self.seq,
                .merkle_root = merkleRoot(cells),
                .timestamp_ms = now_ms,
                .cells_count = @intCast(@min(cells.len, MAX_STABLE_CELLS)),
            };
        }
    }

    pub fn shouldAnchor(self: *const StableThreadAnchor) bool {
        return self.anchor_pending;
    }

    /// Returns the pending anchor record. Only valid when `shouldAnchor()` is true.
    pub fn getAnchorRecord(self: *const StableThreadAnchor) AnchorRecord {
        return self.pending;
    }

    /// Call after publishing the anchor to chain — resets the pending flag.
    pub fn markAnchored(self: *StableThreadAnchor) void {
        self.anchor_pending = false;
        self.consecutive_stable = 0;
    }
};

// ── Merkle / fingerprint helpers ──────────────────────────────────────────────

/// Fingerprint the cell-id list (order-sensitive) so we can detect churn.
fn fingerprintCells(cells: []const StableCell) [HASH_LEN]u8 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    for (cells) |*c| {
        h.update(c.slice());
        h.update("\x00"); // separator
    }
    var out: [HASH_LEN]u8 = undefined;
    h.final(&out);
    return out;
}

/// Binary Merkle tree root over the cell IDs.
/// Leaf = SHA-256("\x00" || cell_id).
/// Parent = SHA-256("\x01" || left_hash || right_hash).
/// Odd leaf duplicated (standard BSV Merkle).
pub fn merkleRoot(cells: []const StableCell) [HASH_LEN]u8 {
    if (cells.len == 0) {
        return std.mem.zeroes([HASH_LEN]u8);
    }

    var hashes: [MAX_STABLE_CELLS][HASH_LEN]u8 = undefined;
    const n = @min(cells.len, MAX_STABLE_CELLS);

    // Compute leaf hashes.
    var i: usize = 0;
    while (i < n) : (i += 1) {
        var h = std.crypto.hash.sha2.Sha256.init(.{});
        h.update("\x00");
        h.update(cells[i].slice());
        h.final(&hashes[i]);
    }

    var count: usize = n;
    while (count > 1) {
        var j: usize = 0;
        var out_count: usize = 0;
        while (j < count) : (j += 2) {
            const left = &hashes[j];
            const right = if (j + 1 < count) &hashes[j + 1] else left; // duplicate odd
            var ph = std.crypto.hash.sha2.Sha256.init(.{});
            ph.update("\x01");
            ph.update(left);
            ph.update(right);
            ph.final(&hashes[out_count]);
            out_count += 1;
        }
        count = out_count;
    }
    return hashes[0];
}

// ── Inline tests ──────────────────────────────────────────────────────────────

const testing = std.testing;

fn makeCell(id: []const u8) StableCell {
    var c: StableCell = undefined;
    @memcpy(c.cell_id[0..id.len], id);
    c.cell_id_len = @intCast(id.len);
    return c;
}

test "WI-D1-T-anchor-on-threshold" {
    var anchor: StableThreadAnchor = undefined;
    anchor.init(.{ .confirmation_threshold = 3, .top_k = 4 });

    const cells = [_]StableCell{
        makeCell("cell-a"),
        makeCell("cell-b"),
        makeCell("cell-c"),
    };

    // First snapshot — not anchored yet (consecutive=1 < 3).
    anchor.recordSnapshot(&cells, 100);
    try testing.expect(!anchor.shouldAnchor());

    // Second snapshot — same set, consecutive=2 < 3.
    anchor.recordSnapshot(&cells, 200);
    try testing.expect(!anchor.shouldAnchor());

    // Third snapshot — consecutive=3 == threshold → anchor fires.
    anchor.recordSnapshot(&cells, 300);
    try testing.expect(anchor.shouldAnchor());
    try testing.expectEqual(@as(u64, 3), anchor.getAnchorRecord().snapshot_seq);
    try testing.expectEqual(@as(u64, 300), anchor.getAnchorRecord().timestamp_ms);
    try testing.expectEqual(@as(u32, 3), anchor.getAnchorRecord().cells_count);

    // After markAnchored, anchor_pending resets.
    anchor.markAnchored();
    try testing.expect(!anchor.shouldAnchor());
}

test "WI-D1-T-merkle-roundtrip" {
    const cells = [_]StableCell{
        makeCell("alpha"),
        makeCell("beta"),
        makeCell("gamma"),
    };

    // Same inputs must produce the same root (deterministic).
    const root1 = merkleRoot(&cells);
    const root2 = merkleRoot(&cells);
    try testing.expectEqualSlices(u8, &root1, &root2);

    // Different inputs must produce a different root.
    const cells2 = [_]StableCell{
        makeCell("alpha"),
        makeCell("DIFFERENT"),
        makeCell("gamma"),
    };
    const root3 = merkleRoot(&cells2);
    try testing.expect(!std.mem.eql(u8, &root1, &root3));
}

test "churn resets consecutive count" {
    var anchor: StableThreadAnchor = undefined;
    anchor.init(.{ .confirmation_threshold = 3, .top_k = 4 });

    const cells_a = [_]StableCell{ makeCell("a"), makeCell("b") };
    const cells_b = [_]StableCell{ makeCell("a"), makeCell("c") }; // different

    anchor.recordSnapshot(&cells_a, 1);
    anchor.recordSnapshot(&cells_a, 2); // consecutive=2
    anchor.recordSnapshot(&cells_b, 3); // churn → reset to 1
    anchor.recordSnapshot(&cells_b, 4); // consecutive=2
    try testing.expect(!anchor.shouldAnchor()); // not yet at 3

    anchor.recordSnapshot(&cells_b, 5); // consecutive=3 → anchor
    try testing.expect(anchor.shouldAnchor());
}

test "empty cell list produces zero root" {
    const root = merkleRoot(&.{});
    const zero = std.mem.zeroes([HASH_LEN]u8);
    try testing.expectEqualSlices(u8, &zero, &root);
}

```
