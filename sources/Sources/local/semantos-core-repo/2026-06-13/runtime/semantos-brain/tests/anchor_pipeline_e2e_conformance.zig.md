---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/anchor_pipeline_e2e_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.204251+00:00
---

# runtime/semantos-brain/tests/anchor_pipeline_e2e_conformance.zig

```zig
// Anchor pipeline end-to-end conformance.
//
// Exercises the full simple-anchor chain in-process:
//
//   AnchorEmitter.emit (.bsv mode)
//     → broker.publish("cell.created")
//       → AnchorQueueWriter (subscribed)
//         → JSONL line appended to queue file
//
// Existing unit tests cover each link in isolation:
//   - anchor_emitter.zig — emitter logic + EVENT_TYPE_CELL_CREATED shape
//   - anchor_queue_writer.zig — broker subscribe + file append + filter
//   - anchor_runner_supervisor.zig — supervisor lifecycle
//
// This test catches a regression class the unit tests can't: drift
// between the event TYPE/PAYLOAD shape the emitter publishes and the
// shape the queue writer (and downstream runner) expect. If any link
// in the chain changes its wire shape, this test fails loudly with
// the JSONL bytes that actually landed on disk.
//
// What's deliberately NOT covered here:
//
//   - The bun runner subprocess. PR #799 wired the supervisor; a
//     follow-on focused PR adds a mock-bun harness that proves the
//     supervised child actually processes queue lines + calls the
//     ARC adapter. That belongs in a separate test file with its
//     own harness — wiring it here would couple the in-process
//     chain test to subprocess timing.
//
//   - HTTP layer. cells_mint_handler.handleMint → cell_store.put →
//     AnchorEmitter is exercised by cells_mint_handler's own
//     integration tests. The link THIS test catches is the
//     AnchorEmitter → JSONL bytes one — independent.

const std = @import("std");
const anchor_emitter = @import("anchor_emitter");
const anchor_queue_writer = @import("anchor_queue_writer");
const helm_event_broker = @import("helm_event_broker");

const testing = std.testing;

/// Build an AnchorContext suitable for a happy-path emit. Caller can
/// mutate the returned value before passing to emitter.emit().
fn makeContext(byte: u8) anchor_emitter.AnchorContext {
    var ch: [32]u8 = undefined;
    @memset(&ch, byte);
    var th: [32]u8 = undefined;
    // Use a non-zero type_hash; emitBsv rejects all-zeros with
    // .failed / type_hash_missing.
    @memset(&th, byte ^ 0x55);
    return .{
        .cell_hash = ch,
        .type_hash = th,
        // 0x10 = generic entity tag (not the anchor-attestation
        // recursion-break tag).
        .entity_tag = 0x10,
    };
}

/// Count newline-terminated lines in the queue file. Returns 0 if
/// the file doesn't exist (writer skipped because emit returned a
/// no-write status like .skipped or .failed).
fn countLines(allocator: std.mem.Allocator, path: []const u8) !usize {
    const bytes = std.fs.cwd().readFileAlloc(
        allocator,
        path,
        64 * 1024,
    ) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => return err,
    };
    defer allocator.free(bytes);

    var n: usize = 0;
    for (bytes) |b| {
        if (b == '\n') n += 1;
    }
    return n;
}

// ─────────────────────────────────────────────────────────────────────
// Pillar 1 — Happy path: one emit lands one JSONL line.
// ─────────────────────────────────────────────────────────────────────

test "AnchorEmitter.emit → broker → AnchorQueueWriter writes one JSONL line" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    const queue_path = try std.fs.path.join(testing.allocator, &.{ real, "queue.jsonl" });
    defer testing.allocator.free(queue_path);

    var broker = helm_event_broker.Broker.init(testing.allocator);
    defer broker.deinit();
    var writer = anchor_queue_writer.AnchorQueueWriter.init(
        testing.allocator,
        .{ .queue_path = queue_path },
    );
    try writer.attach(&broker);
    defer writer.detach(&broker);

    var emitter = anchor_emitter.AnchorEmitter.initWithBroker(
        testing.allocator,
        .bsv,
        &broker,
    );

    const result = emitter.emit(makeContext(0xAA));

    // Emitter accepted the request (.bsv publishes immediately +
    // returns .pending — actual broadcast happens downstream).
    try testing.expectEqual(anchor_emitter.AnchorStatus.pending, result.status);
    try testing.expect(result.enqueued);

    // Queue file has exactly one line.
    try testing.expectEqual(@as(usize, 1), try countLines(testing.allocator, queue_path));

    // Line content carries the cell_hash (lowercase hex) + event type.
    const bytes = try std.fs.cwd().readFileAlloc(testing.allocator, queue_path, 64 * 1024);
    defer testing.allocator.free(bytes);
    try testing.expect(std.mem.indexOf(u8, bytes, "\"type\":\"cell.created\"") != null);
    // cell_hash = 0xAA repeated 32 times → 64 'a' chars in hex.
    try testing.expect(std.mem.indexOf(u8, bytes, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") != null);
}

// ─────────────────────────────────────────────────────────────────────
// Pillar 2 — Multiple emits append (file grows).
// ─────────────────────────────────────────────────────────────────────

test "AnchorEmitter.emit ×N → N JSONL lines in queue file" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    const queue_path = try std.fs.path.join(testing.allocator, &.{ real, "queue.jsonl" });
    defer testing.allocator.free(queue_path);

    var broker = helm_event_broker.Broker.init(testing.allocator);
    defer broker.deinit();
    var writer = anchor_queue_writer.AnchorQueueWriter.init(
        testing.allocator,
        .{ .queue_path = queue_path },
    );
    try writer.attach(&broker);
    defer writer.detach(&broker);

    var emitter = anchor_emitter.AnchorEmitter.initWithBroker(
        testing.allocator,
        .bsv,
        &broker,
    );

    const N: usize = 5;
    var i: usize = 0;
    while (i < N) : (i += 1) {
        const ctx = makeContext(@intCast(0x10 + i));
        const result = emitter.emit(ctx);
        try testing.expectEqual(anchor_emitter.AnchorStatus.pending, result.status);
    }

    try testing.expectEqual(N, try countLines(testing.allocator, queue_path));
}

// ─────────────────────────────────────────────────────────────────────
// Pillar 3 — Recursion break: emit on an ANCHOR_ATTESTATION cell
// returns .skipped + writes NOTHING.
// ─────────────────────────────────────────────────────────────────────

test "AnchorEmitter recursion break: ANCHOR_ATTESTATION_ENTITY_TAG skips file write" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    const queue_path = try std.fs.path.join(testing.allocator, &.{ real, "queue.jsonl" });
    defer testing.allocator.free(queue_path);

    var broker = helm_event_broker.Broker.init(testing.allocator);
    defer broker.deinit();
    var writer = anchor_queue_writer.AnchorQueueWriter.init(
        testing.allocator,
        .{ .queue_path = queue_path },
    );
    try writer.attach(&broker);
    defer writer.detach(&broker);

    var emitter = anchor_emitter.AnchorEmitter.initWithBroker(
        testing.allocator,
        .bsv,
        &broker,
    );

    var ctx = makeContext(0xCC);
    ctx.entity_tag = anchor_emitter.ANCHOR_ATTESTATION_ENTITY_TAG;

    const result = emitter.emit(ctx);

    try testing.expectEqual(anchor_emitter.AnchorStatus.skipped, result.status);
    try testing.expect(!result.enqueued);

    // Recursion break short-circuits BEFORE broker.publish → no file.
    try testing.expectEqual(@as(usize, 0), try countLines(testing.allocator, queue_path));
}

// ─────────────────────────────────────────────────────────────────────
// Pillar 4 — Defensive check: emit with all-zeros type_hash returns
// .failed + writes NOTHING (would publish a useless event the
// runner couldn't BRC-42 derive against).
// ─────────────────────────────────────────────────────────────────────

test "AnchorEmitter.emit with zero type_hash fails fast + writes nothing" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    const queue_path = try std.fs.path.join(testing.allocator, &.{ real, "queue.jsonl" });
    defer testing.allocator.free(queue_path);

    var broker = helm_event_broker.Broker.init(testing.allocator);
    defer broker.deinit();
    var writer = anchor_queue_writer.AnchorQueueWriter.init(
        testing.allocator,
        .{ .queue_path = queue_path },
    );
    try writer.attach(&broker);
    defer writer.detach(&broker);

    var emitter = anchor_emitter.AnchorEmitter.initWithBroker(
        testing.allocator,
        .bsv,
        &broker,
    );

    var ctx = makeContext(0xDD);
    @memset(&ctx.type_hash, 0); // sentinel — emitter rejects this.

    const result = emitter.emit(ctx);

    try testing.expectEqual(anchor_emitter.AnchorStatus.failed, result.status);
    try testing.expect(!result.enqueued);
    try testing.expect(result.error_kind != null);

    // No file because broker.publish never fired.
    try testing.expectEqual(@as(usize, 0), try countLines(testing.allocator, queue_path));
}

// ─────────────────────────────────────────────────────────────────────
// Pillar 5 — Mixed batch: happy path + recursion break + happy path
// — only the two happy-path emits land in the file, in order.
// ─────────────────────────────────────────────────────────────────────

test "AnchorEmitter.emit batch interleaves happy + skipped — only happy land" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    const queue_path = try std.fs.path.join(testing.allocator, &.{ real, "queue.jsonl" });
    defer testing.allocator.free(queue_path);

    var broker = helm_event_broker.Broker.init(testing.allocator);
    defer broker.deinit();
    var writer = anchor_queue_writer.AnchorQueueWriter.init(
        testing.allocator,
        .{ .queue_path = queue_path },
    );
    try writer.attach(&broker);
    defer writer.detach(&broker);

    var emitter = anchor_emitter.AnchorEmitter.initWithBroker(
        testing.allocator,
        .bsv,
        &broker,
    );

    // Emit #1 — happy
    _ = emitter.emit(makeContext(0x11));
    // Emit #2 — recursion break
    {
        var ctx = makeContext(0x22);
        ctx.entity_tag = anchor_emitter.ANCHOR_ATTESTATION_ENTITY_TAG;
        _ = emitter.emit(ctx);
    }
    // Emit #3 — happy
    _ = emitter.emit(makeContext(0x33));

    try testing.expectEqual(@as(usize, 2), try countLines(testing.allocator, queue_path));

    const bytes = try std.fs.cwd().readFileAlloc(testing.allocator, queue_path, 64 * 1024);
    defer testing.allocator.free(bytes);

    // Line 1 carries cell_hash 0x11 × 32; line 2 carries 0x33 × 32.
    const c11 = "1111111111111111111111111111111111111111111111111111111111111111";
    const c33 = "3333333333333333333333333333333333333333333333333333333333333333";
    try testing.expect(std.mem.indexOf(u8, bytes, c11) != null);
    try testing.expect(std.mem.indexOf(u8, bytes, c33) != null);

    // Order matters: 0x11 line appears BEFORE 0x33 line.
    const idx_11 = std.mem.indexOf(u8, bytes, c11).?;
    const idx_33 = std.mem.indexOf(u8, bytes, c33).?;
    try testing.expect(idx_11 < idx_33);
}

```
