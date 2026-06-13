---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/messagebox_lmdb.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.262041+00:00
---

# runtime/semantos-brain/src/messagebox_lmdb.zig

```zig
// D-network-messagebox-first-class — LMDB-backed MessageBox store.
//
// Replaces MemStore (cleared on every restart) with a durable LMDB
// environment.  Implements the same DI fn-pointer surface so serve.zig
// can swap the store transparently.
//
// LMDB layout:
//   env path:  <data_dir>/messagebox_lmdb/
//   DBI name:  messagebox_v1
//   key:       32-char hex message ID (random 16 raw bytes, hex-encoded)
//   value:     JSON:
//     {"sender":"<66hex>","recipient":"<66hex>","kind":"signed|encrypted",
//      "payload":"<base64>","ts":<ms i64>}
//
// Key properties:
//   - Own LMDB env (not shared with entity_cells or intent_cells envs).
//   - max_dbs=1 since we only ever open messagebox_v1.
//   - Concurrency: single-threaded brain reactor; no locks needed.
//   - Malformed entries are silently skipped by list() — they won't
//     prevent other messages from being returned.

const std = @import("std");
const lmdb_mod = @import("lmdb");
const lmdb_config_mod = @import("lmdb_config");
const messagebox_http_mod = @import("messagebox_http");

pub const MessageboxLmdbStore = struct {
    allocator: std.mem.Allocator,
    env: lmdb_mod.Env,
    dbi: lmdb_mod.Dbi,

    const DBI_NAME: [*:0]const u8 = "messagebox_v1";

    /// Open (and create if needed) the LMDB store at `env_path`.
    /// Creates the directory if absent.  The caller is responsible for
    /// calling `deinit()` when the store is no longer needed.
    pub fn init(allocator: std.mem.Allocator, env_path: []const u8) !MessageboxLmdbStore {
        // Create the directory; tolerate PathAlreadyExists.
        std.fs.makeDirAbsolute(env_path) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => return e,
        };

        var env = try lmdb_mod.Env.open(env_path, .{
            .open_flags = lmdb_config_mod.LmdbConfig.prod_flags,
            .map_size   = lmdb_config_mod.LmdbConfig.default.map_size,
            .max_dbs    = 1,
            .mode       = lmdb_config_mod.LmdbConfig.default.mode,
        });
        errdefer env.close();

        // Open (and create) the DBI in an init write transaction.
        const init_txn = try env.beginTxn(.read_write);
        const dbi = init_txn.openDb(DBI_NAME, .{ .create = true }) catch |e| {
            init_txn.abort();
            return e;
        };
        try init_txn.commit();

        return .{ .allocator = allocator, .env = env, .dbi = dbi };
    }

    pub fn deinit(self: *MessageboxLmdbStore) void {
        self.env.close();
    }

    // ── DI fn implementations ──────────────────────────────────────────────

    /// Stores a message envelope and writes the new 32-char hex ID into `id_out`.
    pub fn send(
        ctx: ?*anyopaque,
        allocator: std.mem.Allocator,
        recipient_hex: []const u8,
        sender_hex: []const u8,
        kind: messagebox_http_mod.MessageKind,
        payload_b64: []const u8,
        id_out: *[32]u8,
    ) error{ StoreFull, OutOfMemory, Internal }!void {
        const self: *MessageboxLmdbStore = @ptrCast(@alignCast(ctx.?));

        // Random 16-byte ID, hex-encoded to 32 chars.
        var id_raw: [16]u8 = undefined;
        std.crypto.random.bytes(&id_raw);
        var id_hex: [32]u8 = undefined;
        hexEncode(&id_raw, &id_hex);
        @memcpy(id_out, &id_hex);

        // Pad sender / recipient to exactly 66 chars.
        var sender_padded: [66]u8 = undefined;
        hexCopyPad(&sender_padded, sender_hex);
        var recipient_padded: [66]u8 = undefined;
        hexCopyPad(&recipient_padded, recipient_hex);

        const ts_ms = std.time.milliTimestamp();

        // Serialise to JSON.  All fields (hex + base64 + digits) are safe
        // to embed verbatim — no JSON escaping needed.
        const value = std.fmt.allocPrint(
            allocator,
            "{{\"sender\":\"{s}\",\"recipient\":\"{s}\",\"kind\":\"{s}\"," ++
                "\"payload\":\"{s}\",\"ts\":{d}}}",
            .{ sender_padded, recipient_padded, kind.toString(), payload_b64, ts_ms },
        ) catch return error.OutOfMemory;
        defer allocator.free(value);

        const txn = self.env.beginTxn(.read_write) catch return error.Internal;
        txn.put(self.dbi, &id_hex, value, .{}) catch |e| {
            txn.abort();
            return switch (e) {
                error.map_full => error.StoreFull,
                else           => error.Internal,
            };
        };
        txn.commit() catch return error.Internal;
    }

    /// Returns all messages whose `recipient` field matches `recipient_hex`.
    /// The returned slice and each `payload_b64` within it are allocated on
    /// `allocator`; the caller must free them via `freeRecords`.
    pub fn list(
        ctx: ?*anyopaque,
        allocator: std.mem.Allocator,
        recipient_hex: []const u8,
    ) error{ OutOfMemory, Internal }![]messagebox_http_mod.MessageRecord {
        const self: *MessageboxLmdbStore = @ptrCast(@alignCast(ctx.?));

        const txn = self.env.beginTxn(.read_only) catch return error.Internal;
        defer txn.abort(); // read-only — abort is safe and free

        var cur = txn.openCursor(self.dbi) catch return error.Internal;
        defer cur.close();

        var out: std.ArrayListUnmanaged(messagebox_http_mod.MessageRecord) = .{};
        errdefer {
            for (out.items) |*rec| allocator.free(rec.payload_b64);
            out.deinit(allocator);
        }

        while (true) {
            const maybe_entry = cur.next() catch break;
            const entry = maybe_entry orelse break;

            // Key must be the 32-char hex ID; skip unexpected entries.
            if (entry.key.len != 32) continue;

            // Parse the JSON value; skip malformed entries gracefully.
            const parsed = std.json.parseFromSlice(
                std.json.Value, allocator, entry.val, .{},
            ) catch continue;
            defer parsed.deinit();

            const obj = switch (parsed.value) {
                .object => |o| o,
                else => continue,
            };

            // Recipient filter.
            const rcpt_val = obj.get("recipient") orelse continue;
            const rcpt: []const u8 = switch (rcpt_val) {
                .string => |s| s,
                else    => continue,
            };
            if (!std.mem.eql(u8, rcpt, recipient_hex)) continue;

            // Assemble the output record.  All fields are copied out of the
            // LMDB-managed buffer (valid only within this transaction) or
            // the parsed JSON arena before either exits.
            var rec: messagebox_http_mod.MessageRecord = undefined;

            @memcpy(&rec.id, entry.key); // key.len == 32, rec.id is [32]u8

            const sender_str: []const u8 = if (obj.get("sender")) |sv| switch (sv) {
                .string => |s| s,
                else    => "",
            } else "";
            hexCopyPad(&rec.sender_hex, sender_str);
            hexCopyPad(&rec.recipient_hex, rcpt);

            const kind_str: []const u8 = if (obj.get("kind")) |kv| switch (kv) {
                .string => |s| s,
                else    => "signed",
            } else "signed";
            rec.kind = messagebox_http_mod.MessageKind.fromString(kind_str) orelse .signed;

            rec.received_at = if (obj.get("ts")) |tv| switch (tv) {
                .integer => |n| n,
                .float   => |f| @as(i64, @intFromFloat(f)),
                else     => 0,
            } else 0;

            const payload_str: []const u8 = if (obj.get("payload")) |pv| switch (pv) {
                .string => |s| s,
                else    => "",
            } else "";

            // Dupe the payload (LMDB buffer invalid after txn).  The nested
            // errdefer protects against out.append OOM: if append fails, we
            // free the just-duped payload before propagating the error.
            {
                const payload_owned = try allocator.dupe(u8, payload_str);
                errdefer allocator.free(payload_owned);
                rec.payload_b64 = payload_owned;
                try out.append(allocator, rec);
                // success: payload_owned is now tracked inside out.items.
            }
        }

        return try out.toOwnedSlice(allocator);
    }

    /// Deletes the message with the given 32-char hex ID.
    pub fn ack(ctx: ?*anyopaque, id_hex: []const u8) error{ NotFound, Internal }!void {
        const self: *MessageboxLmdbStore = @ptrCast(@alignCast(ctx.?));

        const txn = self.env.beginTxn(.read_write) catch return error.Internal;
        txn.del(self.dbi, id_hex, null) catch |e| {
            txn.abort();
            return switch (e) {
                error.not_found => error.NotFound,
                else            => error.Internal,
            };
        };
        txn.commit() catch return error.Internal;
    }

    /// Free the slice returned by `list`.  Must be the counterpart of the
    /// `allocator` passed to `list`.
    pub fn freeRecords(
        ctx: ?*anyopaque,
        allocator: std.mem.Allocator,
        records: []messagebox_http_mod.MessageRecord,
    ) void {
        _ = ctx;
        for (records) |*rec| allocator.free(rec.payload_b64);
        allocator.free(records);
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    fn hexEncode(src: []const u8, out: []u8) void {
        const chars = "0123456789abcdef";
        for (src, 0..) |b, i| {
            out[i * 2]     = chars[b >> 4];
            out[i * 2 + 1] = chars[b & 0xf];
        }
    }

    fn hexCopyPad(dst: *[66]u8, src: []const u8) void {
        @memset(dst, '0');
        const n = @min(src.len, dst.len);
        @memcpy(dst[0..n], src[0..n]);
    }
};

// ─────────────────────────────────────────────────────────────────────────────
// Inline tests
// ─────────────────────────────────────────────────────────────────────────────

test "messagebox_lmdb: send + list + ack round-trip" {
    const alloc = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(tmp_path);

    const env_path = try std.fmt.allocPrint(alloc, "{s}/messagebox_lmdb", .{tmp_path});
    defer alloc.free(env_path);

    var store = try MessageboxLmdbStore.init(alloc, env_path);
    defer store.deinit();

    const RECIPIENT = "02" ++ "a5" ** 32; // 66 hex chars — dummy pubkey
    const SENDER    = "03" ++ "b0" ** 32;

    // Send a message.
    var id_hex: [32]u8 = undefined;
    try MessageboxLmdbStore.send(
        &store,
        alloc,
        RECIPIENT,
        SENDER,
        .signed,
        "aGVsbG8gd29ybGQ=", // base64("hello world")
        &id_hex,
    );
    try std.testing.expectEqual(@as(usize, 32), id_hex.len);

    // List — should return the message.
    const records = try MessageboxLmdbStore.list(&store, alloc, RECIPIENT);
    defer MessageboxLmdbStore.freeRecords(&store, alloc, records);

    try std.testing.expectEqual(@as(usize, 1), records.len);
    try std.testing.expectEqualSlices(u8, &id_hex, &records[0].id);
    try std.testing.expectEqual(messagebox_http_mod.MessageKind.signed, records[0].kind);
    try std.testing.expectEqualStrings("aGVsbG8gd29ybGQ=", records[0].payload_b64);

    // Ack — remove the message.
    try MessageboxLmdbStore.ack(&store, &id_hex);

    // List again — should be empty.
    const records2 = try MessageboxLmdbStore.list(&store, alloc, RECIPIENT);
    defer MessageboxLmdbStore.freeRecords(&store, alloc, records2);
    try std.testing.expectEqual(@as(usize, 0), records2.len);
}

test "messagebox_lmdb: ack unknown id returns NotFound" {
    const alloc = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(tmp_path);

    const env_path = try std.fmt.allocPrint(alloc, "{s}/messagebox_lmdb", .{tmp_path});
    defer alloc.free(env_path);

    var store = try MessageboxLmdbStore.init(alloc, env_path);
    defer store.deinit();

    const err = MessageboxLmdbStore.ack(&store, "deadbeef00000000deadbeef00000000");
    try std.testing.expectError(error.NotFound, err);
}

test "messagebox_lmdb: list filters by recipient" {
    const alloc = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(tmp_path);

    const env_path = try std.fmt.allocPrint(alloc, "{s}/messagebox_lmdb", .{tmp_path});
    defer alloc.free(env_path);

    var store = try MessageboxLmdbStore.init(alloc, env_path);
    defer store.deinit();

    const ALICE = "02" ++ "aa" ** 32;
    const BOB   = "03" ++ "bb" ** 32;
    const CAROL = "02" ++ "cc" ** 32;

    var id: [32]u8 = undefined;
    // Two messages for Alice, one for Bob.
    try MessageboxLmdbStore.send(&store, alloc, ALICE, CAROL, .signed, "bXNnMQ==", &id);
    try MessageboxLmdbStore.send(&store, alloc, ALICE, CAROL, .encrypted, "bXNnMg==", &id);
    try MessageboxLmdbStore.send(&store, alloc, BOB,   CAROL, .signed, "bXNnMw==", &id);

    // Alice's inbox should have 2 messages.
    const alice_msgs = try MessageboxLmdbStore.list(&store, alloc, ALICE);
    defer MessageboxLmdbStore.freeRecords(&store, alloc, alice_msgs);
    try std.testing.expectEqual(@as(usize, 2), alice_msgs.len);

    // Bob's inbox should have 1 message.
    const bob_msgs = try MessageboxLmdbStore.list(&store, alloc, BOB);
    defer MessageboxLmdbStore.freeRecords(&store, alloc, bob_msgs);
    try std.testing.expectEqual(@as(usize, 1), bob_msgs.len);
}

test "messagebox_lmdb: persists across store reopen" {
    const alloc = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(alloc, ".");
    defer alloc.free(tmp_path);

    const env_path = try std.fmt.allocPrint(alloc, "{s}/messagebox_lmdb", .{tmp_path});
    defer alloc.free(env_path);

    const RECIPIENT = "02" ++ "a5" ** 32;

    var id_hex: [32]u8 = undefined;

    // Open store, send, close.
    {
        var store = try MessageboxLmdbStore.init(alloc, env_path);
        try MessageboxLmdbStore.send(&store, alloc, RECIPIENT, "03" ++ "b0" ** 32,
            .signed, "cGVyc2lzdA==", &id_hex);
        store.deinit();
    }

    // Re-open store — message must still be there.
    {
        var store = try MessageboxLmdbStore.init(alloc, env_path);
        defer store.deinit();

        const records = try MessageboxLmdbStore.list(&store, alloc, RECIPIENT);
        defer MessageboxLmdbStore.freeRecords(&store, alloc, records);

        try std.testing.expectEqual(@as(usize, 1), records.len);
        try std.testing.expectEqualSlices(u8, &id_hex, &records[0].id);
        try std.testing.expectEqualStrings("cGVyc2lzdA==", records[0].payload_b64);
    }
}

```
