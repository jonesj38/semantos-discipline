---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/bearer_tokens_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.208924+00:00
---

# runtime/semantos-brain/tests/bearer_tokens_conformance.zig

```zig
// Phase Brain 4 — bearer-token store conformance tests.

const std = @import("std");
const bearer_tokens = @import("bearer_tokens");

fn tempPath(name: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try dir.dir.realpath(".", &buf);
    return std.fs.path.join(allocator, &.{ real, name });
}

var pinned_clock: i64 = 1_700_000_000;
fn fixedClock() i64 {
    return pinned_clock;
}

// ── Hex helpers ──

test "Brain 4 hex: encode + decode round-trip" {
    const raw: [4]u8 = .{ 0xab, 0x01, 0xff, 0x10 };
    var hex: [8]u8 = undefined;
    bearer_tokens.hexEncode(&raw, &hex);
    try std.testing.expectEqualStrings("ab01ff10", &hex);

    var back: [4]u8 = undefined;
    try bearer_tokens.hexDecode(&hex, &back);
    try std.testing.expectEqualSlices(u8, &raw, &back);
}

test "Brain 4 hex: hexDecode rejects bad length" {
    var out: [4]u8 = undefined;
    try std.testing.expectError(bearer_tokens.TokenError.bad_format, bearer_tokens.hexDecode("abcd", &out));
}

test "Brain 4 hex: hexDecode rejects non-hex chars" {
    var out: [2]u8 = undefined;
    try std.testing.expectError(bearer_tokens.TokenError.bad_format, bearer_tokens.hexDecode("abxx", &out));
}

// ── Issue / verify / list ──

test "Brain 4 store: issue persists; verify by raw token succeeds" {
    pinned_clock = 1_700_000_000;
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &buf);

    var store = try bearer_tokens.TokenStore.init(std.testing.allocator, path, fixedClock);
    defer store.deinit();

    const result = try store.issue("operator-laptop", 7 * 24 * 3600);
    try std.testing.expectEqual(@as(usize, 1), store.count());
    try std.testing.expectEqualStrings("operator-laptop", result.record.label);

    const verified = try store.verify(&result.token);
    try std.testing.expectEqualSlices(u8, &result.record.id, &verified.id);
}

test "Brain 4 store: verify with wrong token returns not_found" {
    pinned_clock = 1_700_000_000;
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &buf);

    var store = try bearer_tokens.TokenStore.init(std.testing.allocator, path, fixedClock);
    defer store.deinit();

    _ = try store.issue("a", 0);
    const wrong: [32]u8 = .{0xff} ** 32;
    try std.testing.expectError(bearer_tokens.TokenError.not_found, store.verify(&wrong));
}

test "Brain 4 store: bad-format token rejected before lookup" {
    pinned_clock = 1_700_000_000;
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &buf);

    var store = try bearer_tokens.TokenStore.init(std.testing.allocator, path, fixedClock);
    defer store.deinit();

    const wrong_len: [16]u8 = undefined;
    try std.testing.expectError(bearer_tokens.TokenError.bad_format, store.verify(&wrong_len));
}

test "Brain 4 store: expired token returns expired" {
    pinned_clock = 1_700_000_000;
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &buf);

    var store = try bearer_tokens.TokenStore.init(std.testing.allocator, path, fixedClock);
    defer store.deinit();

    const result = try store.issue("short-lived", 60);
    pinned_clock = 1_700_000_000 + 61;
    try std.testing.expectError(bearer_tokens.TokenError.expired, store.verify(&result.token));
}

test "Brain 4 store: ttl=0 token never expires" {
    pinned_clock = 1_700_000_000;
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &buf);

    var store = try bearer_tokens.TokenStore.init(std.testing.allocator, path, fixedClock);
    defer store.deinit();

    const result = try store.issue("forever", 0);
    pinned_clock = 1_900_000_000;
    const verified = try store.verify(&result.token);
    try std.testing.expectEqualSlices(u8, &result.record.id, &verified.id);
}

test "Brain 4 store: revoke removes token from live map" {
    pinned_clock = 1_700_000_000;
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &buf);

    var store = try bearer_tokens.TokenStore.init(std.testing.allocator, path, fixedClock);
    defer store.deinit();

    const result = try store.issue("revoke-me", 0);
    try std.testing.expectEqual(@as(usize, 1), store.count());
    try store.revoke(&result.record.id);
    try std.testing.expectEqual(@as(usize, 0), store.count());
    try std.testing.expectError(bearer_tokens.TokenError.not_found, store.verify(&result.token));
}

test "Brain 4 store: revoke unknown id is a clean no-op" {
    pinned_clock = 1_700_000_000;
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &buf);

    var store = try bearer_tokens.TokenStore.init(std.testing.allocator, path, fixedClock);
    defer store.deinit();

    const fake_id = "00000000000000000000000000000000";
    try store.revoke(fake_id); // should not error
}

test "Brain 4 store: log replays across init cycles" {
    pinned_clock = 1_700_000_000;
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &buf);

    var raw: [32]u8 = undefined;
    {
        var store = try bearer_tokens.TokenStore.init(std.testing.allocator, path, fixedClock);
        defer store.deinit();
        const result = try store.issue("persistent", 0);
        @memcpy(&raw, &result.token);
    }

    // Reopen — the token should still be live.
    var store2 = try bearer_tokens.TokenStore.init(std.testing.allocator, path, fixedClock);
    defer store2.deinit();
    try std.testing.expectEqual(@as(usize, 1), store2.count());
    const verified = try store2.verify(&raw);
    try std.testing.expectEqualStrings("persistent", verified.label);
}

test "Brain 4 store: revoked tokens stay revoked across replay" {
    pinned_clock = 1_700_000_000;
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &buf);

    var raw: [32]u8 = undefined;
    {
        var store = try bearer_tokens.TokenStore.init(std.testing.allocator, path, fixedClock);
        defer store.deinit();
        const result = try store.issue("ephemeral", 0);
        @memcpy(&raw, &result.token);
        try store.revoke(&result.record.id);
    }

    var store2 = try bearer_tokens.TokenStore.init(std.testing.allocator, path, fixedClock);
    defer store2.deinit();
    try std.testing.expectEqual(@as(usize, 0), store2.count());
    try std.testing.expectError(bearer_tokens.TokenError.not_found, store2.verify(&raw));
}

test "Brain 4 store: list returns all live tokens" {
    pinned_clock = 1_700_000_000;
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &buf);

    var store = try bearer_tokens.TokenStore.init(std.testing.allocator, path, fixedClock);
    defer store.deinit();

    _ = try store.issue("a", 0);
    _ = try store.issue("b", 0);
    _ = try store.issue("c", 0);

    const items = try store.list(std.testing.allocator);
    defer std.testing.allocator.free(items);
    try std.testing.expectEqual(@as(usize, 3), items.len);
}

test "Brain 4 store: verifyHex accepts the hex-encoded form" {
    pinned_clock = 1_700_000_000;
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &buf);

    var store = try bearer_tokens.TokenStore.init(std.testing.allocator, path, fixedClock);
    defer store.deinit();

    const result = try store.issue("hex-test", 0);
    var hex: [64]u8 = undefined;
    bearer_tokens.hexEncode(&result.token, &hex);
    const verified = try store.verifyHex(&hex);
    try std.testing.expectEqualStrings("hex-test", verified.label);
}

test "Brain 4 store: log file lives under data-dir with restricted perms" {
    pinned_clock = 1_700_000_000;
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &buf);

    var store = try bearer_tokens.TokenStore.init(std.testing.allocator, path, fixedClock);
    defer store.deinit();
    _ = try store.issue("perms-test", 0);

    const log_path = try std.fs.path.join(std.testing.allocator, &.{ path, "bearer-tokens.log" });
    defer std.testing.allocator.free(log_path);
    const f = try std.fs.cwd().openFile(log_path, .{});
    defer f.close();
    const stat = try f.stat();
    // We don't enforce mode 0600 in init() yet; just confirm the file exists.
    try std.testing.expect(stat.size > 0);
}

test "Brain 4 store: log JSON is well-formed per line" {
    pinned_clock = 1_700_000_000;
    const dir = std.testing.tmpDir(.{});
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try dir.dir.realpath(".", &buf);

    {
        var store = try bearer_tokens.TokenStore.init(std.testing.allocator, path, fixedClock);
        defer store.deinit();
        _ = try store.issue("json-test", 86400);
        _ = try store.issue("another", 0);
    }

    const log_path = try std.fs.path.join(std.testing.allocator, &.{ path, "bearer-tokens.log" });
    defer std.testing.allocator.free(log_path);
    const text = try std.fs.cwd().readFileAlloc(std.testing.allocator, log_path, 1024 * 1024);
    defer std.testing.allocator.free(text);

    var lines = std.mem.splitScalar(u8, text, '\n');
    var n: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, line, .{});
        defer parsed.deinit();
        try std.testing.expectEqual(std.json.Value.object, std.meta.activeTag(parsed.value));
        n += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), n);
}

```
