---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/federation/peer_registry.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.282394+00:00
---

# runtime/semantos-brain/src/federation/peer_registry.zig

```zig
// M7.5 — PeerRegistry: federation reputation + peer onboarding.
//
// Tracks the lifecycle of each peer in the federation mesh:
//   candidate → active (on sufficient correct responses)
//   active/candidate → suspended (on reaching ≤ -50 reputation)
//   suspended → evicted (on reaching ≤ -100 reputation)
//
// Score increments:  +10 per correct response
// Score decrements:  -30 per wrong response
// Promotion threshold:  reputation_score ≥ +50 promotes candidate → active
// Suspension threshold: reputation_score ≤ -50 → suspended
// Eviction threshold:   reputation_score ≤ -100 → evicted

const std = @import("std");

pub const PeerStatus = enum(u8) {
    candidate = 0, // newly joined, not yet trusted
    active = 1, // participating peer in good standing
    suspended = 2, // temporarily suspended (bad behaviour)
    evicted = 3, // permanently removed
};

pub const PeerRecord = struct {
    peer_id: [32]u8,
    status: PeerStatus,
    reputation_score: i32, // starts at 0; positive = good; eviction at ≤ -100
    joined_at_ms: u64,
    last_seen_ms: u64,
    correct_responses: u32,
    wrong_responses: u32,
};

pub const PeerRegistry = struct {
    allocator: std.mem.Allocator,
    peers: std.AutoHashMap([32]u8, PeerRecord),

    pub fn init(allocator: std.mem.Allocator) PeerRegistry {
        return .{
            .allocator = allocator,
            .peers = std.AutoHashMap([32]u8, PeerRecord).init(allocator),
        };
    }

    pub fn deinit(self: *PeerRegistry) void {
        self.peers.deinit();
    }

    /// Add a new peer as a candidate. Returns error.AlreadyRegistered if present.
    pub fn onboard(self: *PeerRegistry, peer_id: [32]u8, now_ms: u64) !void {
        if (self.peers.contains(peer_id)) return error.AlreadyRegistered;
        try self.peers.put(peer_id, .{
            .peer_id = peer_id,
            .status = .candidate,
            .reputation_score = 0,
            .joined_at_ms = now_ms,
            .last_seen_ms = now_ms,
            .correct_responses = 0,
            .wrong_responses = 0,
        });
    }

    /// Record a correct response (+10 reputation; promotes candidate→active at ≥ +50).
    pub fn recordCorrect(self: *PeerRegistry, peer_id: [32]u8, now_ms: u64) !void {
        const entry = self.peers.getPtr(peer_id) orelse return error.NotRegistered;
        entry.reputation_score += 10;
        entry.correct_responses += 1;
        entry.last_seen_ms = now_ms;
        // Promote candidate → active when reputation reaches +50.
        if (entry.status == .candidate and entry.reputation_score >= 50) {
            entry.status = .active;
        }
    }

    /// Record a wrong response (-30 reputation; suspends at ≤ -50; evicts at ≤ -100).
    pub fn recordWrong(self: *PeerRegistry, peer_id: [32]u8, now_ms: u64) !void {
        const entry = self.peers.getPtr(peer_id) orelse return error.NotRegistered;
        entry.reputation_score -= 30;
        entry.wrong_responses += 1;
        entry.last_seen_ms = now_ms;
        // Eviction takes priority over suspension.
        if (entry.reputation_score <= -100) {
            entry.status = .evicted;
        } else if (entry.reputation_score <= -50) {
            entry.status = .suspended;
        }
    }

    /// Get peer record. Returns null if not registered.
    pub fn getPeer(self: *const PeerRegistry, peer_id: [32]u8) ?PeerRecord {
        return self.peers.get(peer_id);
    }

    /// List all active peers (status == .active).
    /// Caller owns the returned slice.
    pub fn listActive(self: *const PeerRegistry, allocator: std.mem.Allocator) ![][32]u8 {
        var list: std.ArrayList([32]u8) = .empty;
        errdefer list.deinit(allocator);
        var it = self.peers.valueIterator();
        while (it.next()) |rec| {
            if (rec.status == .active) {
                try list.append(allocator, rec.peer_id);
            }
        }
        return list.toOwnedSlice(allocator);
    }

    /// Remove all evicted peers from the registry. Returns count purged.
    pub fn purgeEvicted(self: *PeerRegistry) usize {
        var to_remove: std.ArrayList([32]u8) = .empty;
        defer to_remove.deinit(self.allocator);

        var it = self.peers.valueIterator();
        while (it.next()) |rec| {
            if (rec.status == .evicted) {
                to_remove.append(self.allocator, rec.peer_id) catch continue;
            }
        }

        for (to_remove.items) |id| {
            _ = self.peers.remove(id);
        }
        return to_remove.items.len;
    }
};

```
