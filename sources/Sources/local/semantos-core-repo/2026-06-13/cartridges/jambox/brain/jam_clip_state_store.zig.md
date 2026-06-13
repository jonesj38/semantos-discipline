---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/brain/jam_clip_state_store.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.578010+00:00
---

# cartridges/jambox/brain/jam_clip_state_store.zig

```zig
// jam_clip_state_store — minimal state tracker for jam.clip cells.
//
// Reference:
//   docs/design/PLATFORM-WALLET-SHELL-EXPLORATION.md §18 (Phase 2 walker scaffolding)
//   apps/world-apps/jam-room/src/semantic/objects.ts (JamboxObjectKind union)
//   runtime/semantos-brain/src/jobs_store_lmdb_entity.zig (LMDB-backed reference impl)
//
// Status — Phase 2 (this iteration):
//
//   In-memory map of (clip_id → state). The API shape mirrors what an
//   LMDB-backed `jam_clip_store_lmdb_entity.zig` will eventually look
//   like (init / appendStateTransition / get / count); only the storage
//   layer differs. When that store lands the walker registration shape
//   stays the same — just point `JambokWalkerState.jam_clip_store` at
//   the LMDB-backed instance.
//
//   This proves the Phase 2 walker pattern works end-to-end: the
//   walker (jambox_walkers.launchClipWalker) reads the optional store
//   pointer from its State, calls appendStateTransition, and returns
//   a result reflecting the recorded transition. No new RPC plumbing
//   needed when the LMDB store arrives — pure store-implementation
//   swap.

const std = @import("std");

pub const ClipState = enum {
    empty,
    queued,
    playing,
    stopped,

    pub fn name(self: ClipState) []const u8 {
        return @tagName(self);
    }
};

pub const StoreError = error{
    invalid_clip_id,
    out_of_memory,
};

pub const StateRecord = struct {
    clip_id: []const u8,
    state: ClipState,
    updated_at: i64,
    /// Player that drove the transition. Empty when system-driven.
    actor_player: []const u8,
};

/// In-memory jam.clip state map. LMDB-backed implementation follows
/// the same API shape — caller writes `*Store` into the walker state
/// and the walker doesn't care which storage backend is underneath.
pub const Store = struct {
    allocator: std.mem.Allocator,
    records: std.StringHashMap(StateRecord),
    mu: std.Thread.Mutex,
    clock_fn: *const fn () i64,

    pub fn init(
        allocator: std.mem.Allocator,
        clock_fn: *const fn () i64,
    ) Store {
        return .{
            .allocator = allocator,
            .records = std.StringHashMap(StateRecord).init(allocator),
            .mu = .{},
            .clock_fn = clock_fn,
        };
    }

    pub fn deinit(self: *Store) void {
        var it = self.records.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.clip_id);
            if (entry.value_ptr.actor_player.len > 0) {
                self.allocator.free(entry.value_ptr.actor_player);
            }
        }
        self.records.deinit();
    }

    /// Record a state transition for [clip_id]. Replaces any prior
    /// state record for the same clip. Returns the recorded state.
    /// LMDB-backed impl will append a new state-transition cell on
    /// each call; this in-memory version just updates the map.
    pub fn appendStateTransition(
        self: *Store,
        clip_id: []const u8,
        new_state: ClipState,
        actor_player: []const u8,
    ) StoreError!StateRecord {
        if (clip_id.len == 0) return StoreError.invalid_clip_id;
        self.mu.lock();
        defer self.mu.unlock();

        // Free any prior record for the same clip so duplicates don't
        // leak memory.
        if (self.records.fetchRemove(clip_id)) |kv| {
            self.allocator.free(kv.key);
            self.allocator.free(kv.value.clip_id);
            if (kv.value.actor_player.len > 0) self.allocator.free(kv.value.actor_player);
        }

        const key = self.allocator.dupe(u8, clip_id) catch return StoreError.out_of_memory;
        errdefer self.allocator.free(key);
        const clip_dup = self.allocator.dupe(u8, clip_id) catch return StoreError.out_of_memory;
        errdefer self.allocator.free(clip_dup);
        const actor_dup: []const u8 = if (actor_player.len > 0)
            (self.allocator.dupe(u8, actor_player) catch return StoreError.out_of_memory)
        else
            "";

        const record: StateRecord = .{
            .clip_id = clip_dup,
            .state = new_state,
            .updated_at = self.clock_fn(),
            .actor_player = actor_dup,
        };
        self.records.put(key, record) catch return StoreError.out_of_memory;
        return record;
    }

    /// Lookup current state for [clip_id]. Null when no transition
    /// has been recorded yet.
    pub fn get(self: *Store, clip_id: []const u8) ?StateRecord {
        self.mu.lock();
        defer self.mu.unlock();
        return self.records.get(clip_id);
    }

    pub fn count(self: *Store) usize {
        self.mu.lock();
        defer self.mu.unlock();
        return self.records.count();
    }
};

// ─── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

fn fixedClock() i64 {
    return 1747300000;
}

test "Store records state transition" {
    var s = Store.init(testing.allocator, fixedClock);
    defer s.deinit();
    try testing.expectEqual(@as(usize, 0), s.count());
    const rec = try s.appendStateTransition("clip-1", .queued, "player-A");
    try testing.expectEqualStrings("clip-1", rec.clip_id);
    try testing.expectEqual(ClipState.queued, rec.state);
    try testing.expectEqual(@as(i64, 1747300000), rec.updated_at);
    try testing.expectEqual(@as(usize, 1), s.count());

    const fetched = s.get("clip-1").?;
    try testing.expectEqual(ClipState.queued, fetched.state);
}

test "Store replaces prior state for same clip" {
    var s = Store.init(testing.allocator, fixedClock);
    defer s.deinit();
    _ = try s.appendStateTransition("clip-1", .queued, "player-A");
    _ = try s.appendStateTransition("clip-1", .playing, "player-B");
    try testing.expectEqual(@as(usize, 1), s.count());
    try testing.expectEqual(ClipState.playing, s.get("clip-1").?.state);
}

test "Store rejects empty clip_id" {
    var s = Store.init(testing.allocator, fixedClock);
    defer s.deinit();
    try testing.expectError(
        StoreError.invalid_clip_id,
        s.appendStateTransition("", .queued, ""),
    );
}

test "Store get returns null for unknown clip" {
    var s = Store.init(testing.allocator, fixedClock);
    defer s.deinit();
    try testing.expect(s.get("ghost") == null);
}

test "Store handles many clips" {
    var s = Store.init(testing.allocator, fixedClock);
    defer s.deinit();
    _ = try s.appendStateTransition("clip-1", .queued, "");
    _ = try s.appendStateTransition("clip-2", .playing, "");
    _ = try s.appendStateTransition("clip-3", .stopped, "");
    try testing.expectEqual(@as(usize, 3), s.count());
    try testing.expectEqual(ClipState.queued, s.get("clip-1").?.state);
    try testing.expectEqual(ClipState.playing, s.get("clip-2").?.state);
    try testing.expectEqual(ClipState.stopped, s.get("clip-3").?.state);
}

```
