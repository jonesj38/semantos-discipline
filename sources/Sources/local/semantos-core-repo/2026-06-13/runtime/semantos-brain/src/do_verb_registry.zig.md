---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/do_verb_registry.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.254584+00:00
---

# runtime/semantos-brain/src/do_verb_registry.zig

```zig
//! `do` verb registry — the first-class operator-action grammar seam.
//!
//! The `do` grammar is `do <verb> <resource> <target> [k=v…]` — the operator's
//! ACTION surface (vs `talk` = conversation, `find`/`<resource> <verb>` = query).
//! Today `do` is only an LLM-extracted modal (llm_adapter.zig); this makes it a
//! real dispatch grammar. Each registered verb maps a (verb, resource, target)
//! tuple onto a normal `dispatcher.dispatch(dispatch_resource, command, …)` call,
//! so `do` verbs inherit the dispatcher's capability-gating + audit for free.
//!
//! First verb (substrate): `do manage site widget` → the `site` resource's
//! `widget_get` (read; `widget_set` write lands in DO-2). Cartridges register
//! their own `do` verbs later (the do→betterment→release slice) via
//! `CartridgeDeps.do_verb_registry`.
//!
//! Mirrors the repl_verb_registry / http_route_registry shape: a fixed-capacity
//! array + add/find/all. Leaf module — std only, no cycle.

const std = @import("std");

/// One registered `do` verb form `do <verb> <resource> <target>`.
pub const DoVerb = struct {
    verb: []const u8, // e.g. "manage"
    resource: []const u8, // e.g. "site"
    target: []const u8, // e.g. "widget"
    /// The dispatcher resource this verb routes to (e.g. "site").
    dispatch_resource: []const u8,
    /// The dispatcher command run when invoked with no k=v args (the read/show
    /// form).
    read_command: []const u8,
    /// DO-2 — the dispatcher command run when k=v args are present (the write
    /// form). Empty string = writes unsupported for this verb.
    write_command: []const u8 = "",
    /// One-line summary for derived help / helm surfacing.
    summary: []const u8,
};

pub const DoVerbRegistry = struct {
    pub const MAX = 64;
    entries: [MAX]DoVerb = undefined,
    len: usize = 0,

    pub fn add(self: *DoVerbRegistry, verb: DoVerb) void {
        if (self.len >= MAX) {
            std.log.warn("do_verb_registry: MAX ({d}) reached; dropping do {s} {s} {s}", .{ MAX, verb.verb, verb.resource, verb.target });
            return;
        }
        self.entries[self.len] = verb;
        self.len += 1;
    }

    /// First registration for a `(verb, resource, target)` triple wins.
    pub fn find(self: *const DoVerbRegistry, verb: []const u8, resource: []const u8, target: []const u8) ?DoVerb {
        for (self.entries[0..self.len]) |v| {
            if (std.mem.eql(u8, v.verb, verb) and
                std.mem.eql(u8, v.resource, resource) and
                std.mem.eql(u8, v.target, target)) return v;
        }
        return null;
    }

    /// All registered verbs (for derived help + helm surfacing).
    pub fn all(self: *const DoVerbRegistry) []const DoVerb {
        return self.entries[0..self.len];
    }
};

// ── inline tests ──────────────────────────────────────────────────────────

const testing = std.testing;

test "do_verb_registry: add + find by (verb, resource, target)" {
    var reg: DoVerbRegistry = .{};
    reg.add(.{
        .verb = "manage",
        .resource = "site",
        .target = "widget",
        .dispatch_resource = "site",
        .read_command = "widget_get",
        .summary = "manage the chat widget policy",
    });
    try testing.expect(reg.find("manage", "site", "widget") != null);
    try testing.expectEqualStrings("widget_get", reg.find("manage", "site", "widget").?.read_command);
    try testing.expect(reg.find("manage", "site", "job") == null);
    try testing.expect(reg.find("inspect", "site", "widget") == null);
    try testing.expectEqual(@as(usize, 1), reg.all().len);
}

```
