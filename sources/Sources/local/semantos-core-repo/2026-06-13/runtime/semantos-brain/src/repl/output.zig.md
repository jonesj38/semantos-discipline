---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/repl/output.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.297255+00:00
---

# runtime/semantos-brain/src/repl/output.zig

```zig
//! REPL output sink — C4 PR-R1 (verb-seam prereq).
//!
//! A tiny concrete writer the REPL command layer writes through. Extracted to a
//! std-only leaf so BOTH the cli layer (cli/common.zig re-exports it as
//! `cli.Output`) and the repl layer (handleLine + every `cmd*`) share ONE
//! nominal type. That concrete type is what lets a runtime ReplVerbRegistry hold
//! `*const fn(*Session, *const Output, [][]const u8)` function pointers (a
//! generic `out: anytype` has no concrete type until comptime-resolved, so it
//! can't live in a runtime table). The command layer previously took
//! `out: anytype`; R1 makes it `*const Output` everywhere with no behaviour
//! change (every caller already passes this exact shape).

const std = @import("std");

pub const Output = struct {
    buffer: *std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn print(self: *const Output, comptime fmt: []const u8, args: anytype) !void {
        try self.buffer.print(self.allocator, fmt, args);
    }
};

```
