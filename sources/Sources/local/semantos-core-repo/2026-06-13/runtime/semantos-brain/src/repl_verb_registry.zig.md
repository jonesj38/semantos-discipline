---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/repl_verb_registry.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.216307+00:00
---

# runtime/semantos-brain/src/repl_verb_registry.zig

```zig
//! REPL verb registry — C4 PR-R3, the cartridge-owned REPL verb seam.
//!
//! The brain REPL's `handleLine` is a thin shell: substrate verbs (help/status/
//! call/…) + the generic `<resource> <verb>` path (R2) + this registry. A
//! cartridge registers its bespoke verb forms here in `registerInto` — both the
//! ergonomic aliases (`find jobs`, `add customer`) and the sugar transitions
//! (`jobs quote <id>`, `quotes accept <id>`) — so the brain ships ZERO
//! cartridge verb code. Each entry matches a two-token line `<cmd> <resource>`
//! and runs its handler over the remaining args.
//!
//! Handler signature is lean — `(allocator, *Dispatcher, *const Output, args)` —
//! the only things the oddjobz cmds actually use (allocator + dispatcher). That
//! keeps the cartridge's moved cmd code decoupled from the brain's Session type.
//!
//! Leaf deps: dispatcher + repl_output (for the handler signature) — no cycle.

const std = @import("std");
const dispatcher = @import("dispatcher");
const Output = @import("repl_output").Output;

pub const ReplVerbHandler = *const fn (
    allocator: std.mem.Allocator,
    disp: *dispatcher.Dispatcher,
    out: *const Output,
    args: []const []const u8,
) anyerror!void;

/// One registered REPL verb form `<cmd> <resource> [args…]`.
pub const ReplVerb = struct {
    cmd: []const u8, // first token, e.g. "find" or "jobs"
    resource: []const u8, // second token, e.g. "jobs" or "quote"
    handler: ReplVerbHandler,
};

pub const ReplVerbRegistry = struct {
    pub const MAX = 128;
    entries: [MAX]ReplVerb = undefined,
    len: usize = 0,

    pub fn add(self: *ReplVerbRegistry, verb: ReplVerb) void {
        if (self.len >= MAX) {
            std.log.warn("repl_verb_registry: MAX ({d}) reached; dropping {s} {s}", .{ MAX, verb.cmd, verb.resource });
            return;
        }
        self.entries[self.len] = verb;
        self.len += 1;
    }

    /// First registration for a `<cmd> <resource>` pair wins.
    pub fn find(self: *const ReplVerbRegistry, cmd: []const u8, resource: []const u8) ?ReplVerb {
        for (self.entries[0..self.len]) |v| {
            if (std.mem.eql(u8, v.cmd, cmd) and std.mem.eql(u8, v.resource, resource)) return v;
        }
        return null;
    }

    /// All registered verbs (for derived help — C4 PR-R4).
    pub fn all(self: *const ReplVerbRegistry) []const ReplVerb {
        return self.entries[0..self.len];
    }
};

// ── inline tests ──────────────────────────────────────────────────────────

const testing = std.testing;

fn noopHandler(_: std.mem.Allocator, _: *dispatcher.Dispatcher, _: *const Output, _: []const []const u8) anyerror!void {}

test "registry: add + find by (cmd, resource)" {
    var reg: ReplVerbRegistry = .{};
    reg.add(.{ .cmd = "find", .resource = "jobs", .handler = noopHandler });
    reg.add(.{ .cmd = "jobs", .resource = "quote", .handler = noopHandler });
    try testing.expect(reg.find("find", "jobs") != null);
    try testing.expect(reg.find("jobs", "quote") != null);
    try testing.expect(reg.find("find", "customers") == null);
    try testing.expect(reg.find("quote", "jobs") == null); // order matters
}

```
