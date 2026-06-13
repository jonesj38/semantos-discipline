---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/resources/llm_embed_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.293917+00:00
---

# runtime/semantos-brain/src/resources/llm_embed_handler.zig

```zig
// Phase D-W1 / Phase 1 follow-up — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3
// (the `llm.embed` row, line 184) and §8 Phase 1 follow-up.
//
// Stub dispatcher resource handler for `llm.embed`.  Same architectural
// shape as `llm_transcribe_audio_handler.zig` — registers the resource
// + command at dispatcher boot so extensions declaring a dependency
// on `llm.embed` don't fall over before the backend is wired.
//
// Capability: `cap.llm.embed:<scope>`.

const std = @import("std");
const dispatcher = @import("dispatcher");

pub const RESOURCE_NAME = "llm.embed";

pub const HandlerError = error{
    not_yet_implemented,
};

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
    if (std.mem.eql(u8, cmd, "embed")) return .{ .require = "cap.llm.embed:_" };
    return error.unknown_command;
}

fn handle(
    _: ?*anyopaque,
    _: *const dispatcher.DispatchContext,
    cmd: []const u8,
    _: []const u8,
    _: std.mem.Allocator,
) anyerror!dispatcher.Result {
    if (std.mem.eql(u8, cmd, "embed")) {
        return HandlerError.not_yet_implemented;
    }
    return error.unknown_command;
}

test "embed: capForCmd accepts embed, rejects others" {
    try std.testing.expect((try capForCmd(null, "embed")) == .require);
    try std.testing.expectError(error.unknown_command, capForCmd(null, "bogus"));
}

```
