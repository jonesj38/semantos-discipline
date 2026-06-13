---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/federation/slot_router.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.281555+00:00
---

# runtime/semantos-brain/src/federation/slot_router.zig

```zig
const std = @import("std");

pub const SlotRouter = struct {
    peers: []const [32]u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, peers: []const [32]u8) SlotRouter {
        return .{
            .peers = peers,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SlotRouter) void {
        _ = self; // caller owns the peers slice
    }

    /// Deterministically maps slot → peer using rendezvous (HRW) hashing.
    /// Score = sha256(slot_as_u32_le ++ peer_id[0..32]).
    /// Returns the peer whose score is lexicographically greatest.
    /// Returns error.NoPeers if peers slice is empty.
    pub fn slotToPeer(self: SlotRouter, slot: u32) ![32]u8 {
        if (self.peers.len == 0) return error.NoPeers;
        const idx = try self.slotToPeerIndex(slot);
        return self.peers[idx];
    }

    /// Returns the index of the winning peer in self.peers.
    /// Returns error.NoPeers if peers slice is empty.
    pub fn slotToPeerIndex(self: SlotRouter, slot: u32) !usize {
        if (self.peers.len == 0) return error.NoPeers;

        // Build the 4-byte little-endian slot prefix once.
        var slot_le: [4]u8 = undefined;
        std.mem.writeInt(u32, &slot_le, slot, .little);

        var best_score: [32]u8 = undefined;
        var best_idx: usize = 0;

        for (self.peers, 0..) |peer, i| {
            // Hash 36 bytes: slot_le[0..4] ++ peer[0..32]
            var hasher = std.crypto.hash.sha2.Sha256.init(.{});
            hasher.update(&slot_le);
            hasher.update(&peer);
            var score: [32]u8 = undefined;
            hasher.final(&score);

            if (i == 0 or std.mem.order(u8, &score, &best_score) == .gt) {
                best_score = score;
                best_idx = i;
            }
        }

        return best_idx;
    }
};

```
