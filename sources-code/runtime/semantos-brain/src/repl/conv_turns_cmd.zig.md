---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/repl/conv_turns_cmd.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.295808+00:00
---

# runtime/semantos-brain/src/repl/conv_turns_cmd.zig

```zig
// Conversation-turns query REPL verb (`find turns job|conv <id>`).
//
// C4 PR-R3h: the ONE substrate (conversation) REPL verb that stayed in the brain
// after the oddjobz resource verbs moved to the cartridge's ReplVerbRegistry.
// Renamed from oddjobz_cmds.zig + stripped of the vestigial oddjobz store/handler
// imports (everything else that lived here is now cartridge-owned).

const std = @import("std");
const types = @import("types.zig");
const Output = @import("repl_output").Output; // C4 PR-R1 — concrete writer
const dispatcher_mod = @import("dispatcher");

const Session = types.Session;

// ─────────────────────────────────────────────────────────────────────
// D-OJ-conv-turns-query — `find turns job <id>` and `find turns conv <id>`
//
// Resolves the entity's cellId from LMDB (for job queries) and spawns
// the conversation-turns-query-script.ts bun subprocess to fetch turns
// from Postgres.  Output is the raw JSON turns array.
//
// Two forms:
//   find turns job <id_or_name>  — query by job cellHash (resolves via dispatcher)
//   find turns conv <conv_id>    — query by conversationId directly
//
// Architecture notes:
//   - Cannot call back into the brain HTTP reactor (single-threaded
//     reactor deadlock — semantos_brain_single_threaded_reactor).
//   - No AI calls (semantos_no_ai_in_substrate).
//   - When conv_turns_query_script is null, prints a hint and returns.
// ─────────────────────────────────────────────────────────────────────

/// `find turns job <id_or_name>` — resolve job cellHash then query turns.
/// `find turns conv <conv_id>`   — query turns by conversationId directly.
pub fn cmdConvTurnsFind(
    session: *Session,
    out: *const Output,
    kind: []const u8, // "job" | "conv"
    id: []const u8,
) !void {
    const script = session.conv_turns_query_script orelse {
        try out.print(
            "find turns: --oddjobz-conv-turns-query-script not configured.\n" ++
                "  Pass it at serve time to enable conversation turns queries.\n",
            .{},
        );
        return;
    };

    // Build stdin JSON based on query kind.
    var stdin_json: std.ArrayList(u8) = .{};
    defer stdin_json.deinit(session.allocator);

    if (std.mem.eql(u8, kind, "conv")) {
        // Direct conversationId query — no LMDB lookup needed.
        try stdin_json.appendSlice(session.allocator, "{\"conversationId\":");
        const enc = try std.json.Stringify.valueAlloc(session.allocator, id, .{});
        defer session.allocator.free(enc);
        try stdin_json.appendSlice(session.allocator, enc);
        try stdin_json.append(session.allocator, '}');
    } else {
        // "job" — resolve via dispatcher to get the cellHash.
        const disp = session.dispatcher orelse {
            try out.print("find turns job: no dispatcher attached to this REPL session.\n", .{});
            return;
        };

        // Dispatch jobs.find_by_id to get the job JSON.
        const ctx: dispatcher_mod.DispatchContext = .{
            .auth = .in_process_root,
            .capabilities = dispatcher_mod.CapabilitySet.empty(),
            .meta = .{ .request_id = "", .transport_label = "in_process" },
        };
        var job_result = disp.dispatch(&ctx, "jobs", "find_by_id",
            try std.fmt.allocPrint(session.allocator, "{{\"id\":\"{s}\"}}", .{id})) catch |err| {
            try out.print("find turns job: jobs.find_by_id dispatch failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer job_result.deinit();

        if (job_result.payload.len == 0) {
            try out.print("find turns job: job '{s}' not found.\n", .{id});
            return;
        }

        // Parse the cellId from the job JSON.
        const parsed = std.json.parseFromSlice(std.json.Value, session.allocator, job_result.payload, .{}) catch {
            try out.print("find turns job: could not parse job JSON.\n", .{});
            return;
        };
        defer parsed.deinit();

        const cell_id_str: ?[]const u8 = blk: {
            if (parsed.value != .object) break :blk null;
            const cid_v = parsed.value.object.get("cellId") orelse break :blk null;
            if (cid_v != .string) break :blk null;
            break :blk cid_v.string;
        };

        if (cell_id_str == null or cell_id_str.?.len == 0) {
            try out.print("find turns job: job '{s}' has no cellId — cannot query turns.\n", .{id});
            try out.print("  (Job may pre-date the entity-anchoring migration.)\n", .{});
            return;
        }

        try stdin_json.appendSlice(session.allocator, "{\"entityRef\":");
        const enc = try std.json.Stringify.valueAlloc(session.allocator, cell_id_str.?, .{});
        defer session.allocator.free(enc);
        try stdin_json.appendSlice(session.allocator, enc);
        try stdin_json.append(session.allocator, '}');
    }

    // Spawn the bun subprocess.
    var child = std.process.Child.init(&.{ "bun", "run", script }, session.allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    child.spawn() catch |err| {
        try out.print("find turns: failed to spawn bun script: {s}\n", .{@errorName(err)});
        return;
    };

    if (child.stdin) |stdin| {
        stdin.writeAll(stdin_json.items) catch {};
        stdin.close();
        child.stdin = null;
    }

    // Read stdout (up to 1 MB).
    var stdout_buf: std.ArrayList(u8) = .{};
    defer stdout_buf.deinit(session.allocator);
    if (child.stdout) |stdout| {
        const buf = session.allocator.alloc(u8, 1024 * 1024) catch {
            _ = child.wait() catch {};
            try out.print("find turns: out of memory reading subprocess output.\n", .{});
            return;
        };
        defer session.allocator.free(buf);
        var total: usize = 0;
        while (true) {
            const n = stdout.read(buf[total..]) catch break;
            if (n == 0) break;
            total += n;
            if (total >= buf.len) break;
        }
        stdout_buf.appendSlice(session.allocator, buf[0..total]) catch {};
    }
    _ = child.wait() catch {};

    if (stdout_buf.items.len == 0) {
        try out.print("find turns: subprocess produced no output.\n", .{});
        return;
    }

    // Parse and pretty-print the result.
    const parsed_out = std.json.parseFromSlice(std.json.Value, session.allocator, stdout_buf.items, .{}) catch {
        try out.print("find turns: could not parse subprocess output.\n", .{});
        return;
    };
    defer parsed_out.deinit();

    if (parsed_out.value == .object) {
        const ok_v = parsed_out.value.object.get("ok");
        if (ok_v != null and ok_v.? == .bool and !ok_v.?.bool) {
            const err_v = parsed_out.value.object.get("error");
            try out.print("find turns: error from script: {s}\n",
                .{if (err_v != null and err_v.? == .string) err_v.?.string else "unknown"});
            return;
        }
        // Print the turns array as JSON.
        const turns_v = parsed_out.value.object.get("turns");
        if (turns_v != null) {
            const turns_json = std.json.Stringify.valueAlloc(session.allocator, turns_v.?, .{ .whitespace = .indent_2 }) catch null;
            if (turns_json) |tj| {
                defer session.allocator.free(tj);
                try out.print("{s}\n", .{tj});
            } else {
                try out.print("{s}\n", .{stdout_buf.items});
            }
            return;
        }
    }
    // Fallback: print raw output.
    try out.print("{s}\n", .{stdout_buf.items});
}

// ─────────────────────────────────────────────────────────────────────
// D-W1 Phase 1 Part 2 — `device` REPL verb
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3 (identity_certs);
//            docs/design/ODDJOBZ-EXTENSION-PLAN.md §3 Phase O5p.
//
// REPL-side mirror of `brain device list|revoke` — drives the identity_
// certs resource directly (the REPL transport's auth context is
// `in_process_root`, so capability checks bypass).  When no cert store
// is attached we point the operator at the CLI form rather than
// failing silently.

```
