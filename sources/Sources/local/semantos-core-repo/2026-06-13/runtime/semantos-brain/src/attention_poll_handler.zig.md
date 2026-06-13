---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/attention_poll_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.232229+00:00
---

# runtime/semantos-brain/src/attention_poll_handler.zig

```zig
//! Generic attention poll — C4 PR-J4, the namespace-scoped attention primitive.
//!
//! The helm's attention surface is NAMESPACE-SCOPED: in a cartridge you see only
//! that cartridge's signals; at the shell you see shell-native signals plus the
//! cartridge namespaces the user opts in. The CALLER passes the in-scope
//! namespace list (in-cartridge → [that one]; shell → [shell, …opt-ins]); the
//! brain filters the registered attention sources by namespace, collects their
//! scored signals, and merges. Cross-cartridge isolation is the default — no
//! betterment signal can surface in oddjobz unless the caller lists betterment.
//!
//! Merge: each in-scope source gets `max(limit/N, 1)` (N = in-scope source
//! count); the per-source signal arrays are concatenated. (Faithful to the prior
//! oddjobz 3-bucket poll; a global re-rank-by-score is a future refinement.)
//!
//! Result: a JSON array of signal objects `[ {kind,score,ref,summary,[expiresAt],
//! raw}, … ]` — the same per-signal shape the existing oddjobz poll emits, so the
//! helm renders it unchanged.

const std = @import("std");
const attention_source_registry = @import("attention_source_registry");

pub const AttentionError = error{
    invalid_params,
    out_of_memory,
    source_error,
};

pub const Handler = struct {
    registry: *const attention_source_registry.AttentionSourceRegistry,

    /// Poll the in-scope attention sources. `namespaces` = the caller's scope
    /// (in-cartridge → one; shell → shell + opt-ins). `limit` = total signals
    /// wanted (split across the in-scope sources). Returns a JSON array string
    /// (owned; caller frees). No in-scope sources ⇒ "[]".
    pub fn poll(
        self: *const Handler,
        allocator: std.mem.Allocator,
        namespaces: []const []const u8,
        limit: usize,
    ) AttentionError![]u8 {
        const n = self.registry.countInScope(namespaces);
        if (n == 0) return allocator.dupe(u8, "[]") catch return AttentionError.out_of_memory;
        const per_source = @max(limit / n, 1);

        var buf = std.ArrayList(u8){};
        errdefer buf.deinit(allocator);
        buf.append(allocator, '[') catch return AttentionError.out_of_memory;

        var first = true;
        for (self.registry.all()) |*s| {
            if (!attention_source_registry.namespaceInList(s.namespace, namespaces)) continue;
            const arr = s.collect(s.ctx, allocator, per_source) catch return AttentionError.source_error;
            defer allocator.free(arr);
            const inner = innerOfJsonArray(arr);
            if (inner.len == 0) continue;
            if (!first) buf.append(allocator, ',') catch return AttentionError.out_of_memory;
            first = false;
            buf.appendSlice(allocator, inner) catch return AttentionError.out_of_memory;
        }

        buf.append(allocator, ']') catch return AttentionError.out_of_memory;
        return buf.toOwnedSlice(allocator) catch return AttentionError.out_of_memory;
    }
};

/// Return the contents between the outer `[` `]` of a JSON array string, trimmed.
/// `"[]"` / non-array / empty ⇒ "" (nothing to splice).
fn innerOfJsonArray(arr: []const u8) []const u8 {
    const t = std.mem.trim(u8, arr, " \t\r\n");
    if (t.len < 2 or t[0] != '[' or t[t.len - 1] != ']') return "";
    return std.mem.trim(u8, t[1 .. t.len - 1], " \t\r\n");
}

// ── inline tests ──────────────────────────────────────────────────────────

const testing = std.testing;

const FakeSource = struct {
    body: []const u8, // the "[...]" this source emits, ignoring limit
    fn collect(ctx: *anyopaque, allocator: std.mem.Allocator, _: usize) anyerror![]u8 {
        const self: *FakeSource = @ptrCast(@alignCast(ctx));
        return allocator.dupe(u8, self.body);
    }
};

test "poll: namespace scope filters sources + concatenates signals" {
    var reg: attention_source_registry.AttentionSourceRegistry = .{};
    var s_job = FakeSource{ .body = "[{\"kind\":\"job\"}]" };
    var s_msg = FakeSource{ .body = "[{\"kind\":\"message\"}]" };
    var s_bet = FakeSource{ .body = "[{\"kind\":\"nudge\"}]" };
    reg.add(.{ .namespace = "oddjobz", .label = "job", .ctx = &s_job, .collect = FakeSource.collect });
    reg.add(.{ .namespace = "oddjobz", .label = "msg", .ctx = &s_msg, .collect = FakeSource.collect });
    reg.add(.{ .namespace = "betterment", .label = "nudge", .ctx = &s_bet, .collect = FakeSource.collect });

    const h = Handler{ .registry = &reg };
    const alloc = testing.allocator;

    // oddjobz scope → only the two oddjobz signals, betterment isolated out.
    {
        const out = try h.poll(alloc, &.{"oddjobz"}, 10);
        defer alloc.free(out);
        try testing.expectEqualStrings("[{\"kind\":\"job\"},{\"kind\":\"message\"}]", out);
    }
    // shell scope incl. betterment → all three.
    {
        const out = try h.poll(alloc, &.{ "oddjobz", "betterment" }, 9);
        defer alloc.free(out);
        try testing.expectEqualStrings("[{\"kind\":\"job\"},{\"kind\":\"message\"},{\"kind\":\"nudge\"}]", out);
    }
    // out-of-scope namespace → empty.
    {
        const out = try h.poll(alloc, &.{"jambox"}, 10);
        defer alloc.free(out);
        try testing.expectEqualStrings("[]", out);
    }
}

test "innerOfJsonArray" {
    try testing.expectEqualStrings("", innerOfJsonArray("[]"));
    try testing.expectEqualStrings("a,b", innerOfJsonArray("[a,b]"));
    try testing.expectEqualStrings("", innerOfJsonArray("not-an-array"));
}

```
