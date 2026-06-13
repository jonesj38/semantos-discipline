---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/anchor_confirmation_reader.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.253418+00:00
---

# runtime/semantos-brain/src/anchor_confirmation_reader.zig

```zig
// AnchorConfirmationReader — tails the wallet-headers anchor-runner.ts
// confirmations file (<queue>.confirmations.jsonl) and surfaces each
// line as an audit-log entry, closing the L3-unwired feedback loop
// (Todd 2026-05-26 "sure close out").
//
// Reference: docs/prd/ANCHOR-BACKEND-BRIDGE.md §5 (confirmation
//            feedback architecture);
//            runtime/semantos-brain/src/anchor_queue_writer.zig (the
//            companion writer this reader mirrors);
//            cartridges/wallet-headers/brain/scripts/anchor-runner.ts
//            (the producer of the lines this reader consumes).
//
// Architectural choice (PR-3a-bridge-3, file-based):
//
//   brain (this module) ←─── tails <queue>.confirmations.jsonl ←───
//     bun anchor-runner.ts (produces one line per broadcast outcome)
//
//   For each new confirmation line:
//     - Parse the JSON
//     - Call audit_log.record() with module="anchor_emitter",
//       op="confirmed" / "failed" / "skipped", detail carrying
//       (cell_hash, txid, error_kind)
//
// Why file-based vs broker publish-back:
//   - Symmetric with AnchorQueueWriter: the brain wrote one file, the
//     runner produced another; brain reads the second.  Restart-safe
//     via the same cursor pattern.
//   - The runner doesn't need to know about the brain's broker
//     internals or RPC surface.  Decoupling is its own architectural
//     property.
//   - File durability survives brain restart without a special
//     re-sync protocol.
//
// Tick model: this reader is NOT broker-driven (the broker only sees
// brain-originated events).  It's a periodic tick called from
// cli/serve.zig's reactor loop (or a dedicated thread if the reactor
// pattern doesn't fit).  For PR-3a-bridge-3 the tick is invoked from
// a periodic timer the serve binds; future PRs may switch to
// inotify/kqueue once fs-event plumbing exists.

const std = @import("std");
const audit_log_mod = @import("audit_log");

pub const Config = struct {
    /// Path of the JSON-lines confirmations file.  Null disables the
    /// reader (poll is a no-op).
    confirmations_path: ?[]const u8 = null,
};

pub const ReadError = error{
    out_of_memory,
};

/// Per-runner-process tick-driven reader.  init(allocator, config,
/// audit) at boot; call poll(allocator) periodically (every few
/// seconds) from the reactor.  No threads created; no broker
/// subscriptions.
pub const AnchorConfirmationReader = struct {
    allocator: std.mem.Allocator,
    config: Config,
    audit: ?*audit_log_mod.AuditLog,
    /// Byte offset of the next unread byte.  Survives within the
    /// process; restarts re-read the whole file (acceptable: brain
    /// restarts are rare and the audit log already tolerates
    /// duplicate entries via the ts field).
    cursor: usize = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        config: Config,
        audit: ?*audit_log_mod.AuditLog,
    ) AnchorConfirmationReader {
        return .{
            .allocator = allocator,
            .config = config,
            .audit = audit,
            .cursor = 0,
        };
    }

    /// Read any new bytes since the last poll and emit one audit
    /// entry per complete line.  No-op when confirmations_path is
    /// null or the file doesn't exist yet.  Best-effort: I/O failures
    /// log via std.log.warn and return early (cursor stays put so
    /// next poll retries).
    pub fn poll(self: *AnchorConfirmationReader) void {
        const path = self.config.confirmations_path orelse return;
        const audit = self.audit orelse return;

        const stat = std.fs.cwd().statFile(path) catch |e| {
            // File-not-yet-created is the common case; only log
            // unexpected errors.
            if (e != error.FileNotFound) {
                std.log.warn("anchor_confirmation_reader: stat {s} failed: {s}", .{ path, @errorName(e) });
            }
            return;
        };
        if (self.cursor >= stat.size) return; // nothing new

        const file = std.fs.cwd().openFile(path, .{}) catch |e| {
            std.log.warn("anchor_confirmation_reader: open {s} failed: {s}", .{ path, @errorName(e) });
            return;
        };
        defer file.close();
        file.seekTo(self.cursor) catch |e| {
            std.log.warn("anchor_confirmation_reader: seek {s} failed: {s}", .{ path, @errorName(e) });
            return;
        };

        const to_read: usize = stat.size - self.cursor;
        const buf = self.allocator.alloc(u8, to_read) catch return;
        defer self.allocator.free(buf);
        const n_read = file.readAll(buf) catch |e| {
            std.log.warn("anchor_confirmation_reader: read {s} failed: {s}", .{ path, @errorName(e) });
            return;
        };

        // Process complete lines only — if the runner is mid-write,
        // the last line may be incomplete and we leave it for the
        // next poll.  Track offset of last \n consumed.
        var line_start: usize = 0;
        var last_newline: usize = 0;
        var emitted: usize = 0;
        for (buf[0..n_read], 0..) |b, i| {
            if (b == '\n') {
                self.emitOne(audit, buf[line_start..i]);
                last_newline = i + 1;
                line_start = i + 1;
                emitted += 1;
            }
        }
        // Advance cursor past the last complete line.  If no complete
        // line was found, cursor stays put — next poll re-reads from
        // the same place.
        if (last_newline > 0) {
            self.cursor += last_newline;
        }
    }

    fn emitOne(self: *AnchorConfirmationReader, audit: *audit_log_mod.AuditLog, line: []const u8) void {
        if (line.len == 0) return;
        // Parse just enough to fill audit log fields.  We DON'T fully
        // validate — the runner is trusted to write well-formed lines.
        // Bad lines surface as audit "parse_failed" entries so an
        // operator can investigate.
        const parsed = std.json.parseFromSlice(
            ConfirmationLine,
            self.allocator,
            line,
            .{ .ignore_unknown_fields = true },
        ) catch {
            audit.record(self.allocator, .{
                .module = "anchor_emitter",
                .op = "parse_failed",
                .result = .err,
                .detail = "anchor_confirmation_reader: failed to parse confirmation line",
            }) catch {};
            return;
        };
        defer parsed.deinit();
        const c = parsed.value;

        // Map status → audit-log op + result.
        const op: []const u8 = if (std.mem.eql(u8, c.status, "broadcast"))
            "confirmed"
        else if (std.mem.eql(u8, c.status, "skipped"))
            "skipped"
        else
            "failed";
        const result: audit_log_mod.Result = if (std.mem.eql(u8, c.status, "broadcast"))
            .ok
        else if (std.mem.eql(u8, c.status, "skipped"))
            .ok // skipped is benign (recursion break)
        else
            .err;

        // Compose detail as a flat JSON string suitable for the audit
        // log's `detail` field.  Includes cell_hash + txid + any
        // error context the runner provided.
        var detail_buf: [512]u8 = undefined;
        const detail = std.fmt.bufPrint(
            &detail_buf,
            "{{\"event_id\":\"{s}\",\"cell_hash\":\"{s}\",\"type_hash\":\"{s}\",\"txid\":\"{s}\",\"error_kind\":\"{s}\"}}",
            .{
                c.event_id,
                c.cell_hash,
                c.type_hash,
                c.txid orelse "",
                c.error_kind orelse "",
            },
        ) catch return;

        audit.record(self.allocator, .{
            .module = "anchor_emitter",
            .op = op,
            .result = result,
            .detail = detail,
        }) catch |e| {
            std.log.warn("anchor_confirmation_reader: audit record failed: {s}", .{@errorName(e)});
        };
    }
};

/// JSON shape the runner writes — must stay in sync with
/// `ConfirmationLine` in scripts/anchor-runner.ts.
const ConfirmationLine = struct {
    event_id: []const u8,
    cell_hash: []const u8,
    type_hash: []const u8,
    status: []const u8, // "broadcast" | "failed" | "skipped"
    txid: ?[]const u8 = null,
    error_kind: ?[]const u8 = null,
    detail: ?[]const u8 = null,
    processed_at_ms: i64 = 0,
};

// ─────────────────────────────────────────────────────────────────────
// Inline tests
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "AnchorConfirmationReader: poll is no-op when confirmations_path is null" {
    var r = AnchorConfirmationReader.init(testing.allocator, .{}, null);
    r.poll(); // should not crash
    try testing.expectEqual(@as(usize, 0), r.cursor);
}

test "AnchorConfirmationReader: poll is no-op when audit is null" {
    var r = AnchorConfirmationReader.init(testing.allocator, .{ .confirmations_path = "/tmp/never-exists.jsonl" }, null);
    r.poll();
    try testing.expectEqual(@as(usize, 0), r.cursor);
}

test "AnchorConfirmationReader: reads broadcast lines + records audit entries" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    const conf_path = try std.fs.path.join(testing.allocator, &.{ real, "confirmations.jsonl" });
    defer testing.allocator.free(conf_path);
    const audit_path = try std.fs.path.join(testing.allocator, &.{ real, "audit.log" });
    defer testing.allocator.free(audit_path);

    // Write a couple of confirmation lines.
    {
        const f = try std.fs.cwd().createFile(conf_path, .{});
        defer f.close();
        try f.writeAll(
            \\{"event_id":"e1","cell_hash":"aa","type_hash":"bb","status":"broadcast","txid":"deadbeef","processed_at_ms":1}
            \\{"event_id":"e2","cell_hash":"cc","type_hash":"dd","status":"failed","error_kind":"broadcast_failed","detail":"arc 503","processed_at_ms":2}
            \\
        );
    }

    // Boot audit log.
    var audit = audit_log_mod.AuditLog.init();
    try audit.open(audit_path);
    defer audit.close();

    var r = AnchorConfirmationReader.init(
        testing.allocator,
        .{ .confirmations_path = conf_path },
        &audit,
    );
    r.poll();
    // Cursor should have advanced past both lines.
    try testing.expect(r.cursor > 0);

    // Audit log should contain at least two entries — confirmed + failed.
    const audit_bytes = try std.fs.cwd().readFileAlloc(testing.allocator, audit_path, 8 * 1024);
    defer testing.allocator.free(audit_bytes);
    try testing.expect(std.mem.indexOf(u8, audit_bytes, "anchor_emitter") != null);
    try testing.expect(std.mem.indexOf(u8, audit_bytes, "confirmed") != null);
    try testing.expect(std.mem.indexOf(u8, audit_bytes, "deadbeef") != null);
    try testing.expect(std.mem.indexOf(u8, audit_bytes, "broadcast_failed") != null);
}

test "AnchorConfirmationReader: idempotent across polls (cursor advances; no duplicate records)" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    const conf_path = try std.fs.path.join(testing.allocator, &.{ real, "confirmations.jsonl" });
    defer testing.allocator.free(conf_path);
    const audit_path = try std.fs.path.join(testing.allocator, &.{ real, "audit.log" });
    defer testing.allocator.free(audit_path);

    {
        const f = try std.fs.cwd().createFile(conf_path, .{});
        defer f.close();
        try f.writeAll(
            \\{"event_id":"e1","cell_hash":"aa","type_hash":"bb","status":"broadcast","txid":"once","processed_at_ms":1}
            \\
        );
    }

    var audit = audit_log_mod.AuditLog.init();
    try audit.open(audit_path);
    defer audit.close();

    var r = AnchorConfirmationReader.init(
        testing.allocator,
        .{ .confirmations_path = conf_path },
        &audit,
    );
    r.poll();
    const cursor_after_first = r.cursor;
    try testing.expect(cursor_after_first > 0);

    r.poll(); // second poll on unchanged file
    try testing.expectEqual(cursor_after_first, r.cursor); // cursor stable

    // Count occurrences of "once" — should be exactly 1.
    const audit_bytes = try std.fs.cwd().readFileAlloc(testing.allocator, audit_path, 8 * 1024);
    defer testing.allocator.free(audit_bytes);
    var count: usize = 0;
    var i: usize = 0;
    while (std.mem.indexOf(u8, audit_bytes[i..], "once")) |found| {
        count += 1;
        i += found + 1;
    }
    try testing.expectEqual(@as(usize, 1), count);
}

test "AnchorConfirmationReader: incomplete trailing line (no \\n) is held until next poll" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    const conf_path = try std.fs.path.join(testing.allocator, &.{ real, "confirmations.jsonl" });
    defer testing.allocator.free(conf_path);
    const audit_path = try std.fs.path.join(testing.allocator, &.{ real, "audit.log" });
    defer testing.allocator.free(audit_path);

    // Write one complete line + an incomplete one (no trailing \n).
    {
        const f = try std.fs.cwd().createFile(conf_path, .{});
        defer f.close();
        try f.writeAll(
            "{\"event_id\":\"complete\",\"cell_hash\":\"aa\",\"type_hash\":\"bb\",\"status\":\"broadcast\",\"txid\":\"good\",\"processed_at_ms\":1}\n" ++
                "{\"event_id\":\"incomplete\",\"cell_hash\":\"cc\",\"type_hash\":\"dd\",\"status\":\"broad",
        );
    }

    var audit = audit_log_mod.AuditLog.init();
    try audit.open(audit_path);
    defer audit.close();

    var r = AnchorConfirmationReader.init(
        testing.allocator,
        .{ .confirmations_path = conf_path },
        &audit,
    );
    r.poll();
    // Cursor advanced past complete line only (the incomplete one
    // stays available for the next poll once it's flushed).
    const audit_bytes = try std.fs.cwd().readFileAlloc(testing.allocator, audit_path, 8 * 1024);
    defer testing.allocator.free(audit_bytes);
    try testing.expect(std.mem.indexOf(u8, audit_bytes, "good") != null);
    try testing.expect(std.mem.indexOf(u8, audit_bytes, "incomplete") == null);
}

```
