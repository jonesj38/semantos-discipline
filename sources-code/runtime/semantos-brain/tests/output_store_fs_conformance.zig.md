---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/output_store_fs_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.186038+00:00
---

# runtime/semantos-brain/tests/output_store_fs_conformance.zig

```zig
// Phase WSITE4.6 — FsOutputStore conformance tests.
//
// Exercises the same vtable surface LocalOutputStore tests cover, plus the
// disk-persistence behaviours unique to the FS backing:
//   • events written on add / mark_spent / prune_confirmed / replay
//   • replay across reopens preserves state (the Brain 4.6 contract)
//   • malformed log lines are skipped, not fatal

const std = @import("std");
const output_store = @import("output_store");
const output_store_fs = @import("output_store_fs");

const OutputRecord = output_store.OutputRecord;
const Outpoint = output_store.Outpoint;

fn tempDir(allocator: std.mem.Allocator) ![]u8 {
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try dir.dir.realpath(".", &buf);
    return allocator.dupe(u8, real);
}

fn cleanupDir(path: []const u8) void {
    const log = std.fmt.allocPrint(std.testing.allocator, "{s}/outputs.log", .{path}) catch return;
    defer std.testing.allocator.free(log);
    std.fs.cwd().deleteFile(log) catch {};
}

fn sampleRecord(vout: u32) OutputRecord {
    return .{
        .outpoint = .{ .txid = [_]u8{@intCast(vout)} ** 32, .vout = vout },
        .satoshis = 1000 + @as(u64, vout),
        .locking_script = &[_]u8{ 0x76, 0xa9, 0x14 },
        .derived_key_hash = [_]u8{0x55} ** 32,
        .derivation_protocol_hash = [_]u8{0x33} ** 16,
        .derivation_counterparty = [_]u8{0x44} ** 33,
        .derivation_index = vout,
        .beef = &[_]u8{ 0xef, 0xbe },
        .basket = "default",
        .tags = &[_]u8{},
        .custom_instructions = &[_]u8{},
        .confirmations = 1,
        .status = .unspent,
        .spending_txid = [_]u8{0} ** 32,
    };
}

test "WSITE4.6 fs: add + get round-trip in same process" {
    const dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    defer cleanupDir(dir);

    var fs = try output_store_fs.FsOutputStore.init(std.testing.allocator, dir);
    defer fs.deinit();
    const s = fs.store();

    const rec = sampleRecord(0);
    try s.addOutput(rec);
    const got = s.getOutput(rec.outpoint).?;
    try std.testing.expectEqual(rec.satoshis, got.satoshis);
    try std.testing.expectEqualStrings("default", got.basket);
}

test "WSITE4.6 fs: persistence across reopens" {
    const dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    defer cleanupDir(dir);

    {
        var fs = try output_store_fs.FsOutputStore.init(std.testing.allocator, dir);
        defer fs.deinit();
        const s = fs.store();
        try s.addOutput(sampleRecord(0));
        try s.addOutput(sampleRecord(1));
        try s.markSpent(.{ .txid = [_]u8{1} ** 32, .vout = 1 }, [_]u8{0xaa} ** 32);
    }

    var fs2 = try output_store_fs.FsOutputStore.init(std.testing.allocator, dir);
    defer fs2.deinit();
    const s2 = fs2.store();

    const op0: Outpoint = .{ .txid = [_]u8{0} ** 32, .vout = 0 };
    const op1: Outpoint = .{ .txid = [_]u8{1} ** 32, .vout = 1 };

    const r0 = s2.getOutput(op0).?;
    try std.testing.expectEqual(@as(u64, 1000), r0.satoshis);
    try std.testing.expectEqual(output_store.OutputStatus.unspent, r0.status);

    const r1 = s2.getOutput(op1).?;
    try std.testing.expectEqual(output_store.OutputStatus.spent, r1.status);
    try std.testing.expectEqualSlices(u8, &[_]u8{0xaa} ** 32, &r1.spending_txid);
}

test "WSITE4.6 fs: listOutputs filters spent + basket" {
    const dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    defer cleanupDir(dir);

    var fs = try output_store_fs.FsOutputStore.init(std.testing.allocator, dir);
    defer fs.deinit();
    const s = fs.store();

    var rec_a0 = sampleRecord(0);
    rec_a0.basket = "a";
    var rec_a1 = sampleRecord(1);
    rec_a1.basket = "a";
    var rec_b = sampleRecord(2);
    rec_b.basket = "b";

    try s.addOutput(rec_a0);
    try s.addOutput(rec_a1);
    try s.addOutput(rec_b);
    try s.markSpent(rec_a1.outpoint, [_]u8{0xff} ** 32);

    const all = try s.listOutputs(null, null, std.testing.allocator);
    defer std.testing.allocator.free(all);
    try std.testing.expectEqual(@as(usize, 2), all.len); // a0 + b unspent

    const a_only = try s.listOutputs("a", null, std.testing.allocator);
    defer std.testing.allocator.free(a_only);
    try std.testing.expectEqual(@as(usize, 1), a_only.len); // a0 unspent
    try std.testing.expectEqualStrings("a", a_only[0].basket);
}

test "WSITE4.6 fs: pruneConfirmed drops BEEF + persists across reopen" {
    const dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    defer cleanupDir(dir);

    {
        var fs = try output_store_fs.FsOutputStore.init(std.testing.allocator, dir);
        defer fs.deinit();
        const s = fs.store();

        var rec = sampleRecord(0);
        rec.confirmations = 200;
        try s.addOutput(rec);

        const pruned = try s.pruneConfirmed(100);
        try std.testing.expectEqual(@as(u64, 1), pruned);
    }

    var fs2 = try output_store_fs.FsOutputStore.init(std.testing.allocator, dir);
    defer fs2.deinit();
    const s2 = fs2.store();
    const r = s2.getOutput(.{ .txid = [_]u8{0} ** 32, .vout = 0 }).?;
    try std.testing.expectEqual(@as(usize, 0), r.beef.len);
}

test "WSITE4.6 fs: rejects duplicate outpoint" {
    const dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    defer cleanupDir(dir);

    var fs = try output_store_fs.FsOutputStore.init(std.testing.allocator, dir);
    defer fs.deinit();
    const s = fs.store();
    const rec = sampleRecord(0);
    try s.addOutput(rec);
    try std.testing.expectError(error.duplicate_outpoint, s.addOutput(rec));
}

test "WSITE4.6 fs: malformed log lines are skipped" {
    const dir = try tempDir(std.testing.allocator);
    defer std.testing.allocator.free(dir);
    defer cleanupDir(dir);

    // Pre-populate the log with a malformed line + a valid one.
    const log_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/outputs.log", .{dir});
    defer std.testing.allocator.free(log_path);
    {
        const f = try std.fs.cwd().createFile(log_path, .{});
        defer f.close();
        try f.writeAll("not json\n");
    }

    // Open + add one good record on top of the garbage, then close.
    {
        var fs = try output_store_fs.FsOutputStore.init(std.testing.allocator, dir);
        defer fs.deinit();
        const s = fs.store();
        try s.addOutput(sampleRecord(0));
    }

    // Reopen — replay should skip the bad line + load the good one.
    var fs2 = try output_store_fs.FsOutputStore.init(std.testing.allocator, dir);
    defer fs2.deinit();
    const s2 = fs2.store();
    const r = s2.getOutput(.{ .txid = [_]u8{0} ** 32, .vout = 0 });
    try std.testing.expect(r != null);
}

```
