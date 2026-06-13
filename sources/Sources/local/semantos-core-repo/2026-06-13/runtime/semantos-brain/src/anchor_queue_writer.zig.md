---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/anchor_queue_writer.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.257398+00:00
---

# runtime/semantos-brain/src/anchor_queue_writer.zig

```zig
// AnchorQueueWriter — subscribes to helm_event_broker `cell.created`
// events and appends each one to a JSON-lines file at a configured path
// so the wallet-headers cartridge runner (cartridges/wallet-headers/
// brain/scripts/anchor-runner.ts) can tail it and broadcast anchors
// asynchronously.
//
// Reference: docs/prd/ANCHOR-BACKEND-BRIDGE.md §4 (bridge architecture);
//            runtime/semantos-brain/src/anchor_emitter.zig (the
//              upstream emitBsv publishing the events we consume);
//            runtime/semantos-brain/src/helm_event_broker.zig (the
//              subscription API).
//
// Architectural choice (Todd 2026-05-26 "keep going to wrap this all
// up"): the brain does NOT spawn the bun subprocess directly.  Instead
// we use a *file-based queue*:
//
//   brain (this module)
//     → broker.subscribe("cell.created")
//       → callback writes JSON-line to anchor-queue.jsonl
//                                                ↓
//   operator runs (separately):
//     bun cartridges/wallet-headers/brain/scripts/anchor-runner.ts
//                                                ↓
//     tail anchor-queue.jsonl → handleCellCreated → real txid
//
// Why file-based vs in-brain bun-child spawning:
//   - No SIGCHLD / zombie / fork-exec dance from inside the broker
//     callback (which the broker requires to be FAST — see
//     helm_event_broker.zig:32 "callbacks MUST be fast").  A single
//     line append is microseconds.
//   - Survives brain restarts: the queue file is on disk; operator can
//     replay missed events from a known cursor position.
//   - Decouples runner lifecycle from brain lifecycle: operator can
//     stop/start the runner without touching the brain.
//   - Simpler to observe / debug: `tail -f anchor-queue.jsonl` shows
//     exactly what's queued.
//
// Recursion break belt + suspenders: events with
// `entity_tag == ANCHOR_ATTESTATION_ENTITY_TAG` already short-circuit
// in AnchorEmitter.emit() so they don't reach the broker as
// "cell.created" — this writer is the third defence layer (after Zig
// emit + TS subscriber check).  We don't repeat the filter here because
// it would mask a bug in the upstream layers.

const std = @import("std");
const helm_event_broker = @import("helm_event_broker");

/// Config for the queue writer.  Off by default — must be opted in
/// from cli/serve.zig with a non-null queue_path.
pub const Config = struct {
    /// Path of the JSON-lines file we append to.  Created on first
    /// write if absent; appended to otherwise.  Null disables the
    /// writer entirely (init still succeeds; attach is a no-op).
    queue_path: ?[]const u8 = null,
};

pub const InitError = error{
    out_of_memory,
};

pub const AttachError = error{
    out_of_memory,
};

/// One brain-process-scoped instance.  Constructed at cli/serve.zig
/// boot, attached to the helm broker once the broker is up.  Lives
/// for the duration of the brain run.
pub const AnchorQueueWriter = struct {
    allocator: std.mem.Allocator,
    config: Config,
    /// Subscriber id returned from broker.subscribe; null until
    /// attach() runs.  detach() uses it to unsubscribe at shutdown.
    sub_id: ?helm_event_broker.SubscriberId = null,

    pub fn init(
        allocator: std.mem.Allocator,
        config: Config,
    ) AnchorQueueWriter {
        return .{
            .allocator = allocator,
            .config = config,
            .sub_id = null,
        };
    }

    /// Wire the writer into the broker.  No-op when queue_path is null.
    /// Idempotent — attaching twice is a programmer error, asserted in
    /// debug builds.
    pub fn attach(
        self: *AnchorQueueWriter,
        broker: *helm_event_broker.Broker,
    ) AttachError!void {
        if (self.config.queue_path == null) return;
        std.debug.assert(self.sub_id == null);
        self.sub_id = broker.subscribe(.{
            .state = self,
            .callback = onEventCallback,
        }) catch return AttachError.out_of_memory;
    }

    /// Unsubscribe from the broker.  Safe to call without prior attach.
    pub fn detach(self: *AnchorQueueWriter, broker: *helm_event_broker.Broker) void {
        if (self.sub_id) |id| {
            broker.unsubscribe(id);
            self.sub_id = null;
        }
    }

    fn onEventCallback(state: ?*anyopaque, event: helm_event_broker.Event) void {
        const self: *AnchorQueueWriter = @ptrCast(@alignCast(state.?));
        // Filter: only `cell.created`.  Other broker events (job.
        // transitioned, lead.created, etc.) fly past this writer.
        if (!std.mem.eql(u8, event.type, "cell.created")) return;
        self.writeOneBestEffort(event);
    }

    /// Append one event as a JSON-line to the queue file.  Best-effort:
    /// on any I/O failure we drop the event (logged to audit if wired)
    /// rather than blocking the broker callback.  An operator running
    /// the runner can replay missing events from the brain's recent
    /// ring + audit log if needed.
    fn writeOneBestEffort(self: *AnchorQueueWriter, event: helm_event_broker.Event) void {
        const path = self.config.queue_path orelse return;

        // Open for append, create if absent, 0644 mode.
        var file = std.fs.cwd().createFile(path, .{
            .truncate = false,
            .read = false,
            .mode = 0o644,
        }) catch |e| {
            std.log.warn("anchor_queue_writer: open {s} failed: {s}", .{ path, @errorName(e) });
            return;
        };
        defer file.close();

        // Seek to end for append.
        file.seekFromEnd(0) catch |e| {
            std.log.warn("anchor_queue_writer: seek {s} failed: {s}", .{ path, @errorName(e) });
            return;
        };

        // Build one line: { "event_id":..., "ts":..., "type":..., "payload":<raw> }\n
        // The broker assigns event_id + ts at publish time; payload_json
        // carries the per-event fields (cell_hash, type_hash, etc.) the
        // bun runner needs.  We wrap them together so the runner can
        // dedupe by event_id without re-parsing payload_json.
        //
        // Cap line size at 8 KB — payload is bounded by
        // anchor_emitter.MAX_EVENT_PAYLOAD_BYTES (512) but we add
        // envelope fields + JSON escaping overhead.
        var heap_buf: std.ArrayList(u8) = .{};
        defer heap_buf.deinit(self.allocator);
        heap_buf.ensureTotalCapacity(self.allocator, 8 * 1024) catch return;

        const writer = heap_buf.writer(self.allocator);
        writer.print(
            "{{\"event_id\":\"{s}\",\"ts\":{d},\"type\":\"{s}\",\"payload\":{s}}}\n",
            .{
                event.event_id,
                event.ts,
                event.type,
                event.payload_json,
            },
        ) catch return;

        file.writeAll(heap_buf.items) catch |e| {
            std.log.warn("anchor_queue_writer: write {s} failed: {s}", .{ path, @errorName(e) });
            return;
        };
    }
};

// ─────────────────────────────────────────────────────────────────────
// Inline tests
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "AnchorQueueWriter: attach is no-op when queue_path is null" {
    var w = AnchorQueueWriter.init(testing.allocator, .{});
    var broker = helm_event_broker.Broker.init(testing.allocator);
    defer broker.deinit();
    try w.attach(&broker);
    // Should not have subscribed.
    try testing.expect(w.sub_id == null);
    try testing.expectEqual(@as(usize, 0), broker.subscriberCount());
}

test "AnchorQueueWriter: writes cell.created events to disk + ignores other types" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    const queue_path = try std.fs.path.join(testing.allocator, &.{ real, "queue.jsonl" });
    defer testing.allocator.free(queue_path);

    var w = AnchorQueueWriter.init(testing.allocator, .{ .queue_path = queue_path });
    var broker = helm_event_broker.Broker.init(testing.allocator);
    defer broker.deinit();
    try w.attach(&broker);
    defer w.detach(&broker);
    try testing.expect(w.sub_id != null);
    try testing.expectEqual(@as(usize, 1), broker.subscriberCount());

    // Publish a cell.created event — should land in the file.
    broker.publish(.{
        .type = "cell.created",
        .payload_json = "{\"cell_hash\":\"aa\",\"type_hash\":\"bb\"}",
    });

    // Publish a different event type — should be ignored.
    broker.publish(.{
        .type = "job.transitioned",
        .payload_json = "{\"id\":\"job-1\"}",
    });

    // Read back the queue file.
    const file_bytes = try std.fs.cwd().readFileAlloc(
        testing.allocator,
        queue_path,
        16 * 1024,
    );
    defer testing.allocator.free(file_bytes);

    // Exactly one line — the job.transitioned event was filtered out.
    var line_count: usize = 0;
    for (file_bytes) |b| {
        if (b == '\n') line_count += 1;
    }
    try testing.expectEqual(@as(usize, 1), line_count);

    // Line must contain the cell_hash from the payload.
    try testing.expect(std.mem.indexOf(u8, file_bytes, "\"cell_hash\":\"aa\"") != null);
    try testing.expect(std.mem.indexOf(u8, file_bytes, "\"type\":\"cell.created\"") != null);
    // And must NOT contain the filtered-out event.
    try testing.expect(std.mem.indexOf(u8, file_bytes, "job.transitioned") == null);
}

test "AnchorQueueWriter: appends across multiple publishes (file grows)" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    const queue_path = try std.fs.path.join(testing.allocator, &.{ real, "queue.jsonl" });
    defer testing.allocator.free(queue_path);

    var w = AnchorQueueWriter.init(testing.allocator, .{ .queue_path = queue_path });
    var broker = helm_event_broker.Broker.init(testing.allocator);
    defer broker.deinit();
    try w.attach(&broker);
    defer w.detach(&broker);

    // Three publishes — three lines in the file.
    broker.publish(.{ .type = "cell.created", .payload_json = "{\"i\":1}" });
    broker.publish(.{ .type = "cell.created", .payload_json = "{\"i\":2}" });
    broker.publish(.{ .type = "cell.created", .payload_json = "{\"i\":3}" });

    const file_bytes = try std.fs.cwd().readFileAlloc(
        testing.allocator,
        queue_path,
        16 * 1024,
    );
    defer testing.allocator.free(file_bytes);

    var line_count: usize = 0;
    for (file_bytes) |b| {
        if (b == '\n') line_count += 1;
    }
    try testing.expectEqual(@as(usize, 3), line_count);
    try testing.expect(std.mem.indexOf(u8, file_bytes, "\"i\":1") != null);
    try testing.expect(std.mem.indexOf(u8, file_bytes, "\"i\":2") != null);
    try testing.expect(std.mem.indexOf(u8, file_bytes, "\"i\":3") != null);
}

```
