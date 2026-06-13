---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/llm_stub_handlers_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.171982+00:00
---

# runtime/semantos-brain/tests/llm_stub_handlers_conformance.zig

```zig
// Phase D-W1 / Phase 1 follow-up — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3
// (the `llm.transcribe_audio` + `llm.embed` rows, lines 183-184), §8
// Phase 1 follow-up.
//
// Conformance suite for the two stub handlers — `llm.transcribe_audio`
// and `llm.embed`.  These resources are registered NOW so extensions
// targeting future audio / embedding flows can declare a resource
// dependency without breaking the dispatcher graph when the backend
// isn't yet wired.
//
// What the suite asserts:
//
//   • Dispatcher.dispatch on a known command returns
//     `not_yet_implemented` — distinct from `unknown_resource` and
//     `unknown_command`, both of which would fire if the dispatcher
//     didn't know about the resource at all.
//   • Dispatcher.dispatch on an unknown command returns
//     `unknown_command` (the cap_for_cmd_fn rejects).
//   • Audit-pair invariant fires for every dispatch (start + end).

const std = @import("std");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const transcribe_mod = @import("llm_transcribe_audio_handler");
const embed_mod = @import("llm_embed_handler");

const Fixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    transcribe: transcribe_mod.Handler,
    embed: embed_mod.Handler,
    disp: dispatcher.Dispatcher,

    fn init(allocator: std.mem.Allocator) !*Fixture {
        const self = try allocator.create(Fixture);
        errdefer allocator.destroy(self);
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        const audit_path = try std.fs.path.join(allocator, &.{ real, "audit.log" });
        errdefer allocator.free(audit_path);

        self.* = .{
            .allocator = allocator,
            .tmp_dir = tmp,
            .audit_path = audit_path,
            .audit = audit_log.AuditLog.init(),
            .transcribe = transcribe_mod.Handler.init(),
            .embed = embed_mod.Handler.init(),
            .disp = undefined,
        };
        try self.audit.open(audit_path);
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.transcribe.resourceHandler());
        try self.disp.register(self.embed.resourceHandler());
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.disp.deinit();
        self.audit.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.audit_path);
        self.allocator.destroy(self);
    }

    fn dumpAudit(self: *Fixture) ![]u8 {
        const f = try std.fs.cwd().openFile(self.audit_path, .{});
        defer f.close();
        const stat = try f.stat();
        const buf = try self.allocator.alloc(u8, stat.size);
        errdefer self.allocator.free(buf);
        const n = try f.readAll(buf);
        return buf[0..n];
    }
};

fn rootCtx() dispatcher.DispatchContext {
    return .{
        .auth = .in_process_root,
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{ .request_id = "test", .transport_label = "test" },
    };
}

test "D-W1 P1.followup llm.transcribe_audio: registered + transcribe returns not_yet_implemented" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    const err = fx.disp.dispatch(&ctx, "llm.transcribe_audio", "transcribe", "{}");
    try std.testing.expectError(transcribe_mod.HandlerError.not_yet_implemented, err);
}

test "D-W1 P1.followup llm.embed: registered + embed returns not_yet_implemented" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    const err = fx.disp.dispatch(&ctx, "llm.embed", "embed", "{}");
    try std.testing.expectError(embed_mod.HandlerError.not_yet_implemented, err);
}

test "D-W1 P1.followup llm.transcribe_audio: unknown command returns unknown_command" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    const err = fx.disp.dispatch(&ctx, "llm.transcribe_audio", "bogus", "{}");
    try std.testing.expectError(dispatcher.DispatchError.unknown_command, err);
}

test "D-W1 P1.followup llm.embed: unknown command returns unknown_command" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    const err = fx.disp.dispatch(&ctx, "llm.embed", "bogus", "{}");
    try std.testing.expectError(dispatcher.DispatchError.unknown_command, err);
}

test "D-W1 P1.followup llm stubs: not_yet_implemented dispatch records start + end audit pair" {
    const allocator = std.testing.allocator;
    var fx = try Fixture.init(allocator);
    defer fx.deinit();

    var ctx = rootCtx();
    const err = fx.disp.dispatch(&ctx, "llm.transcribe_audio", "transcribe", "{}");
    try std.testing.expectError(transcribe_mod.HandlerError.not_yet_implemented, err);

    const audit_text = try fx.dumpAudit();
    defer allocator.free(audit_text);

    var start_count: usize = 0;
    var end_count: usize = 0;
    var line_it = std.mem.splitSequence(u8, audit_text, "\n");
    while (line_it.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.indexOf(u8, line, "phase=start") != null) start_count += 1;
        if (std.mem.indexOf(u8, line, "phase=end") != null) end_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), start_count);
    try std.testing.expectEqual(@as(usize, 1), end_count);
}

```
