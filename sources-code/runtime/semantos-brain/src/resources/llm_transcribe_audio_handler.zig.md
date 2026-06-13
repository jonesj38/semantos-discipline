---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/resources/llm_transcribe_audio_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.293645+00:00
---

# runtime/semantos-brain/src/resources/llm_transcribe_audio_handler.zig

```zig
// Phase D-W1 / Phase 1 follow-up — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3
// (the `llm.transcribe_audio` row, line 183) and §8 Phase 1 follow-up.
//
// Stub dispatcher resource handler for `llm.transcribe_audio`.  The
// resource + command are registered NOW so extensions targeting
// future audio flows can declare a resource dependency on
// `llm.transcribe_audio` without breaking the dispatcher graph when
// the backend isn't yet wired.
//
// On dispatch the handler returns `error.not_yet_implemented` — note
// the distinction: the resource and command exist (so neither
// `unknown_resource` nor `unknown_command` fires); the BACKEND
// doesn't.  When D-O5m / D-O5p / a follow-up wires a real backend,
// this file's `handle_fn` swaps in the actual implementation; the
// dispatcher registration call site doesn't change.
//
// Capability: `cap.llm.transcribe:<scope>`.  See the per-scope
// rationale in `llm_complete_handler.zig`.

const std = @import("std");
const dispatcher = @import("dispatcher");

pub const RESOURCE_NAME = "llm.transcribe_audio";

pub const HandlerError = error{
    /// Backend is not yet wired.  The resource + command exist; only
    /// the implementation is missing.  Distinct from
    /// `unknown_resource` / `unknown_command`, which the dispatcher
    /// surfaces when the resource / command don't even exist.
    not_yet_implemented,
};

/// Stateless handler — no fields.  Caller heap-allocates the struct
/// only to satisfy the dispatcher's `*anyopaque` state slot.
pub const Handler = struct {
    pub fn init() Handler {
        return .{};
    }

    pub fn resourceHandler(self: *Handler) dispatcher.ResourceHandler {
        return .{
            .name = RESOURCE_NAME,
            .state = self,
            .cap_for_cmd_fn = capForCmd,
            .handle_fn = handle,
        };
    }
};

fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    if (std.mem.eql(u8, cmd, "transcribe")) return .{ .require = "cap.llm.transcribe:_" };
    return error.unknown_command;
}

fn handle(
    _: ?*anyopaque,
    _: *const dispatcher.DispatchContext,
    cmd: []const u8,
    _: []const u8,
    _: std.mem.Allocator,
) anyerror!dispatcher.Result {
    if (std.mem.eql(u8, cmd, "transcribe")) {
        return HandlerError.not_yet_implemented;
    }
    return error.unknown_command;
}

test "transcribe_audio: capForCmd accepts transcribe, rejects others" {
    try std.testing.expect((try capForCmd(null, "transcribe")) == .require);
    try std.testing.expectError(error.unknown_command, capForCmd(null, "bogus"));
}

```
