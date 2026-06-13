---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/attention_source_registry.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.229096+00:00
---

# runtime/semantos-brain/src/attention_source_registry.zig

```zig
//! Attention-source registry — C4 PR-J4, the generic attention-signal seam.
//!
//! The helm's attention surface is NAMESPACE-SCOPED: in a cartridge you see only
//! that cartridge's signals; at the shell you see shell-native signals plus the
//! cartridge namespaces the user opts in. The brain is pure mechanism — the
//! CALLER passes which namespaces are in scope (in-cartridge → just that one;
//! shell → shell + opt-ins), so cross-cartridge isolation is the default and the
//! brain owns no policy.
//!
//! A cartridge registers, in registerInto, one or more attention SOURCES, each
//! tagged with its namespace. The generic poll (cell_attention_handler) includes
//! only in-scope sources, collects their scored signals, and merges. This is the
//! attention analog of route/mint/store/cell-decoder registries.
//!
//! The signal wire shape is owned by each source (it emits the JSON array of
//! `{kind, score, ref, summary, [expiresAt], raw}` objects the helm already
//! renders); the poll concatenates the in-scope sources' arrays.
//!
//! Leaf deps: std only — so cartridge_seam can expose it on CartridgeDeps without
//! pulling in serve/reactor (#847). Sources carry an opaque ctx + a collect fn;
//! the registry never frees them (cartridge owns them, brain-lifetime).

const std = @import("std");

/// Collect up to `limit` scored attention signals from this source, as a
/// JSON ARRAY string `[ {kind,score,ref,summary,[expiresAt],raw}, … ]`
/// allocated with `allocator` (caller frees). Empty source ⇒ "[]".
pub const CollectFn = *const fn (
    ctx: *anyopaque,
    allocator: std.mem.Allocator,
    limit: usize,
) anyerror![]u8;

/// One registered attention source.
pub const AttentionSource = struct {
    /// The namespace this source's signals belong to (e.g. "oddjobz"). Matched
    /// against the caller's in-scope namespace list. Borrowed (usually literal).
    namespace: []const u8,
    /// Short kind label for diagnostics/logging (e.g. "dispatch"). Borrowed.
    label: []const u8,
    /// Caller-owned state (the cartridge's handler/store pointer).
    ctx: *anyopaque,
    collect: CollectFn,
};

/// Growable, bounded registry. Default-constructable (`.{}`); cartridges append
/// via `add`. The poll handler iterates `inScope`.
pub const AttentionSourceRegistry = struct {
    pub const MAX = 64;
    entries: [MAX]AttentionSource = undefined,
    len: usize = 0,

    pub fn add(self: *AttentionSourceRegistry, source: AttentionSource) void {
        if (self.len >= MAX) {
            std.log.warn("attention_source_registry: MAX ({d}) reached; dropping source {s}/{s}", .{ MAX, source.namespace, source.label });
            return;
        }
        self.entries[self.len] = source;
        self.len += 1;
    }

    /// Count of registered sources whose namespace is in `namespaces`.
    pub fn countInScope(self: *const AttentionSourceRegistry, namespaces: []const []const u8) usize {
        var n: usize = 0;
        for (self.entries[0..self.len]) |*s| {
            if (namespaceInList(s.namespace, namespaces)) n += 1;
        }
        return n;
    }

    /// Iterate the registered sources (slice). The poll filters by namespace.
    pub fn all(self: *const AttentionSourceRegistry) []const AttentionSource {
        return self.entries[0..self.len];
    }
};

/// True if `ns` equals any entry in `namespaces`.
pub fn namespaceInList(ns: []const u8, namespaces: []const []const u8) bool {
    for (namespaces) |want| {
        if (std.mem.eql(u8, ns, want)) return true;
    }
    return false;
}

// ── inline tests ──────────────────────────────────────────────────────────

const testing = std.testing;

fn emptyCollect(_: *anyopaque, allocator: std.mem.Allocator, _: usize) anyerror![]u8 {
    return allocator.dupe(u8, "[]");
}

test "registry: add + countInScope filters by namespace" {
    var reg: AttentionSourceRegistry = .{};
    var c0: u8 = 0;
    reg.add(.{ .namespace = "oddjobz", .label = "dispatch", .ctx = &c0, .collect = emptyCollect });
    reg.add(.{ .namespace = "oddjobz", .label = "message", .ctx = &c0, .collect = emptyCollect });
    reg.add(.{ .namespace = "betterment", .label = "nudge", .ctx = &c0, .collect = emptyCollect });

    try testing.expectEqual(@as(usize, 2), reg.countInScope(&.{"oddjobz"}));
    try testing.expectEqual(@as(usize, 1), reg.countInScope(&.{"betterment"}));
    try testing.expectEqual(@as(usize, 3), reg.countInScope(&.{ "oddjobz", "betterment" }));
    try testing.expectEqual(@as(usize, 0), reg.countInScope(&.{"jambox"}));
    try testing.expectEqual(@as(usize, 3), reg.all().len);
}

test "namespaceInList" {
    try testing.expect(namespaceInList("oddjobz", &.{ "shell", "oddjobz" }));
    try testing.expect(!namespaceInList("betterment", &.{ "shell", "oddjobz" }));
}

```
