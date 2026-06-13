---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/bearer_tokens.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.218791+00:00
---

# runtime/semantos-brain/src/bearer_tokens.zig

```zig
// Phase Brain 4 — Bearer-token issuance + verification for the remote-access
// surfaces (HTTP REPL at /api/v1/repl + WSS at /api/v1/wallet).
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 4).
//
// Operator issues a token via `brain bearer issue --label <name> --ttl 7d`.
// We print the raw 32-byte secret as 64-hex once; subsequent commands
// can only see the token's metadata + sha256 fingerprint.  Verification
// hashes the incoming Authorization-header value and looks it up.
//
// Storage: append-only JSON-lines log at <data-dir>/bearer-tokens.log,
// mirroring the audit-log shape.  Three event kinds:
//
//     {"ts":...,"kind":"issued","id":"<uuid>","label":"...",
//      "fingerprint":"<32-hex>","expires_at":<unix-sec>}
//     {"ts":...,"kind":"revoked","id":"<uuid>"}
//     {"ts":...,"kind":"used","id":"<uuid>","peer":"<ip>"}    (optional)
//
// In-memory map: fingerprint → record.  Rebuilt at startup by replaying
// the log.  Revoked tokens are kept in the log (for audit) but not in
// the live map.
//
// Why hashes + not raw secrets?  An attacker with read access to the
// log file shouldn't be able to authenticate as any token-holder.
// Tokens are 256-bit random; sha256 fingerprints make verification a
// constant-time hash + map lookup.  The raw token leaves the process
// only once — at issuance — over the operator's TTY.

const std = @import("std");

pub const TokenError = error{
    not_found,
    expired,
    revoked,
    out_of_memory,
    bad_format,
    duplicate_id,
};

pub const TokenRecord = struct {
    /// 16-byte UUIDv4 (hex-encoded as 32 chars).
    id: [32]u8,
    /// Operator-supplied human label.
    label: []u8,
    /// sha256(token_bytes) hex-encoded.
    fingerprint: [64]u8,
    /// Unix-seconds the token was issued at.
    issued_at: i64,
    /// Unix-seconds the token expires at; 0 = never.
    expires_at: i64,
    /// SH14 / D12 — hat role this token acts under: "operator" (default,
    /// base helm verbs) | "admin" (+managerial). Owned. Old log lines with
    /// no role replay as "operator" (back-compat). The helm reads it via the
    /// /api/v1/info hat block and gates the verb shelf by it.
    role: []u8,
};

pub const TokenStore = struct {
    allocator: std.mem.Allocator,
    /// Absolute path to the append-only log.  Owned.
    log_path: []u8,
    /// Open handle to the log file.  Held for the store's lifetime;
    /// flushed after every write.
    log_file: ?std.fs.File,
    /// fingerprint → TokenRecord.  Pointers are owned by the store;
    /// rebuilt by `replayLog`.
    by_fingerprint: std.StringHashMap(TokenRecord),
    /// Optional clock injection for deterministic tests.
    clock: *const fn () i64,

    pub fn init(
        allocator: std.mem.Allocator,
        data_dir: []const u8,
        clock_fn: *const fn () i64,
    ) !TokenStore {
        const log_path = try std.fs.path.join(allocator, &.{ data_dir, "bearer-tokens.log" });
        std.fs.cwd().makePath(data_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => {
                allocator.free(log_path);
                return err;
            },
        };
        var self = TokenStore{
            .allocator = allocator,
            .log_path = log_path,
            .log_file = null,
            .by_fingerprint = std.StringHashMap(TokenRecord).init(allocator),
            .clock = clock_fn,
        };
        try self.openOrCreateLog();
        try self.replayLog();
        return self;
    }

    pub fn deinit(self: *TokenStore) void {
        if (self.log_file) |f| f.close();
        var it = self.by_fingerprint.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.label);
            self.allocator.free(entry.value_ptr.role);
        }
        self.by_fingerprint.deinit();
        self.allocator.free(self.log_path);
    }

    /// Issue a new token. Returns the raw 32-byte secret and the
    /// matching TokenRecord. The caller is responsible for printing
    /// the raw bytes once — they are NOT recoverable later.
    /// Result of issuing a token — named so issue + issueWithRole share one
    /// return type (anonymous structs are distinct types in Zig).
    pub const IssueResult = struct { token: [32]u8, record: TokenRecord };

    pub fn issue(
        self: *TokenStore,
        label: []const u8,
        ttl_secs: i64,
    ) !IssueResult {
        // Default to the operator role (base helm verbs). SH14/D12.
        return self.issueWithRole(label, ttl_secs, "operator");
    }

    /// SH14 / D12 — issue a token bound to a hat role ("operator" | "admin").
    /// An unknown role is coerced to "operator" (fail-safe: never elevates).
    pub fn issueWithRole(
        self: *TokenStore,
        label: []const u8,
        ttl_secs: i64,
        role: []const u8,
    ) !IssueResult {
        var raw: [32]u8 = undefined;
        std.crypto.random.bytes(&raw);

        var fp_bytes: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(&raw, &fp_bytes, .{});
        var fp_hex: [64]u8 = undefined;
        hexEncode(&fp_bytes, &fp_hex);

        var id_bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&id_bytes);
        var id_hex: [32]u8 = undefined;
        hexEncode(&id_bytes, &id_hex);

        const now = self.clock();
        const expires_at: i64 = if (ttl_secs == 0) 0 else now + ttl_secs;

        const role_norm: []const u8 = if (std.mem.eql(u8, role, "admin")) "admin" else "operator";

        const owned_label = try self.allocator.dupe(u8, label);
        errdefer self.allocator.free(owned_label);
        const owned_role = try self.allocator.dupe(u8, role_norm);
        errdefer self.allocator.free(owned_role);
        const owned_fp_key = try self.allocator.dupe(u8, &fp_hex);
        errdefer self.allocator.free(owned_fp_key);

        const rec = TokenRecord{
            .id = id_hex,
            .label = owned_label,
            .fingerprint = fp_hex,
            .issued_at = now,
            .expires_at = expires_at,
            .role = owned_role,
        };

        try self.by_fingerprint.put(owned_fp_key, rec);

        try self.appendIssued(rec);

        return .{ .token = raw, .record = rec };
    }

    /// Revoke a token by id.  Idempotent: revoking an unknown id is a
    /// no-op; revoking an already-revoked id is a no-op.
    pub fn revoke(self: *TokenStore, id_hex: []const u8) !void {
        if (id_hex.len != 32) return TokenError.bad_format;
        // Find the record by id (linear scan — typical operator has <20 tokens).
        var it = self.by_fingerprint.iterator();
        while (it.next()) |entry| {
            if (std.mem.eql(u8, &entry.value_ptr.id, id_hex)) {
                try self.appendRevoked(id_hex);
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.label);
                self.allocator.free(entry.value_ptr.role);
                _ = self.by_fingerprint.removeByPtr(entry.key_ptr);
                return;
            }
        }
        // Unknown id — log a noop revoke for audit completeness.
        try self.appendRevoked(id_hex);
    }

    /// Verify a bearer secret. Returns the matching record or an error.
    /// Constant-time-ish: the sha256 + hashmap lookup are both O(1)
    /// independent of which token matches.
    pub fn verify(self: *TokenStore, raw_token: []const u8) !TokenRecord {
        if (raw_token.len != 32) return TokenError.bad_format;
        var fp_bytes: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(raw_token, &fp_bytes, .{});
        var fp_hex: [64]u8 = undefined;
        hexEncode(&fp_bytes, &fp_hex);

        const rec = self.by_fingerprint.get(&fp_hex) orelse return TokenError.not_found;
        if (rec.expires_at != 0 and self.clock() >= rec.expires_at) {
            return TokenError.expired;
        }
        return rec;
    }

    /// Verify a hex-encoded bearer (64 hex chars). Convenience wrapper
    /// for the common Authorization-header path.
    pub fn verifyHex(self: *TokenStore, hex_token: []const u8) !TokenRecord {
        if (hex_token.len != 64) return TokenError.bad_format;
        var raw: [32]u8 = undefined;
        try hexDecode(hex_token, &raw);
        return self.verify(&raw);
    }

    /// Snapshot of all live (issued, not revoked, possibly expired)
    /// tokens. Caller must NOT free the returned slice; pointers are
    /// owned by the store.
    pub fn list(self: *TokenStore, allocator: std.mem.Allocator) ![]TokenRecord {
        var out = try allocator.alloc(TokenRecord, self.by_fingerprint.count());
        var i: usize = 0;
        var it = self.by_fingerprint.iterator();
        while (it.next()) |entry| {
            out[i] = entry.value_ptr.*;
            i += 1;
        }
        return out;
    }

    pub fn count(self: *const TokenStore) usize {
        return self.by_fingerprint.count();
    }

    // ── log replay + append ──

    fn openOrCreateLog(self: *TokenStore) !void {
        const cwd = std.fs.cwd();
        const f = cwd.openFile(self.log_path, .{ .mode = .read_write }) catch |err| switch (err) {
            error.FileNotFound => blk: {
                break :blk try cwd.createFile(self.log_path, .{ .read = true });
            },
            else => return err,
        };
        try f.seekFromEnd(0);
        self.log_file = f;
    }

    fn replayLog(self: *TokenStore) !void {
        const f = self.log_file orelse return;
        try f.seekTo(0);
        const max = 1024 * 1024 * 16;
        const text = try f.readToEndAlloc(self.allocator, max);
        defer self.allocator.free(text);

        var it = std.mem.splitScalar(u8, text, '\n');
        while (it.next()) |line| {
            if (line.len == 0) continue;
            try self.applyLogLine(line);
        }
        try f.seekFromEnd(0);
    }

    fn applyLogLine(self: *TokenStore, line: []const u8) !void {
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            line,
            .{},
        ) catch return; // Skip malformed lines (forward-compat).
        defer parsed.deinit();

        const obj = parsed.value.object;
        const kind = obj.get("kind") orelse return;
        if (kind != .string) return;

        if (std.mem.eql(u8, kind.string, "issued")) {
            const id = (obj.get("id") orelse return).string;
            const label = (obj.get("label") orelse return).string;
            const fp = (obj.get("fingerprint") orelse return).string;
            const issued_at = (obj.get("issued_at") orelse return).integer;
            const expires_at = (obj.get("expires_at") orelse return).integer;
            if (id.len != 32 or fp.len != 64) return;

            // SH14 / D12 — role is optional in the log; old lines default to
            // "operator". Only the literal "admin" elevates (fail-safe).
            const role_raw: []const u8 = if (obj.get("role")) |r|
                (if (r == .string) r.string else "operator")
            else
                "operator";
            const role_norm: []const u8 = if (std.mem.eql(u8, role_raw, "admin")) "admin" else "operator";

            const owned_label = try self.allocator.dupe(u8, label);
            errdefer self.allocator.free(owned_label);
            const owned_role = try self.allocator.dupe(u8, role_norm);
            errdefer self.allocator.free(owned_role);
            const owned_fp = try self.allocator.dupe(u8, fp);
            errdefer self.allocator.free(owned_fp);

            var rec: TokenRecord = .{
                .id = undefined,
                .label = owned_label,
                .fingerprint = undefined,
                .issued_at = issued_at,
                .expires_at = expires_at,
                .role = owned_role,
            };
            @memcpy(&rec.id, id);
            @memcpy(&rec.fingerprint, fp);
            try self.by_fingerprint.put(owned_fp, rec);
            return;
        }

        if (std.mem.eql(u8, kind.string, "revoked")) {
            const id = (obj.get("id") orelse return).string;
            if (id.len != 32) return;
            // Linear scan to find by id.
            var it = self.by_fingerprint.iterator();
            while (it.next()) |entry| {
                if (std.mem.eql(u8, &entry.value_ptr.id, id)) {
                    self.allocator.free(entry.key_ptr.*);
                    self.allocator.free(entry.value_ptr.label);
                    self.allocator.free(entry.value_ptr.role);
                    _ = self.by_fingerprint.removeByPtr(entry.key_ptr);
                    return;
                }
            }
            return;
        }
    }

    fn appendIssued(self: *TokenStore, rec: TokenRecord) !void {
        const f = self.log_file orelse return;
        var buf: [512]u8 = undefined;
        const line = try std.fmt.bufPrint(
            &buf,
            "{{\"ts\":{d},\"kind\":\"issued\",\"id\":\"{s}\",\"label\":\"{s}\",\"fingerprint\":\"{s}\",\"issued_at\":{d},\"expires_at\":{d},\"role\":\"{s}\"}}\n",
            .{
                self.clock(),
                rec.id,
                rec.label,
                rec.fingerprint,
                rec.issued_at,
                rec.expires_at,
                rec.role,
            },
        );
        try f.writeAll(line);
        try f.sync();
    }

    fn appendRevoked(self: *TokenStore, id_hex: []const u8) !void {
        const f = self.log_file orelse return;
        var buf: [256]u8 = undefined;
        const line = try std.fmt.bufPrint(
            &buf,
            "{{\"ts\":{d},\"kind\":\"revoked\",\"id\":\"{s}\"}}\n",
            .{ self.clock(), id_hex },
        );
        try f.writeAll(line);
        try f.sync();
    }
};

// ── Helpers ──

pub fn hexEncode(bytes: []const u8, out: []u8) void {
    std.debug.assert(out.len == bytes.len * 2);
    const chars = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2] = chars[b >> 4];
        out[i * 2 + 1] = chars[b & 0x0f];
    }
}

pub fn hexDecode(hex: []const u8, out: []u8) !void {
    if (hex.len != out.len * 2) return TokenError.bad_format;
    var i: usize = 0;
    while (i < out.len) : (i += 1) {
        out[i] = (try parseHexNibble(hex[i * 2]) << 4) | try parseHexNibble(hex[i * 2 + 1]);
    }
}

fn parseHexNibble(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => 10 + (c - 'a'),
        'A'...'F' => 10 + (c - 'A'),
        else => TokenError.bad_format,
    };
}

// ─────────────────────────────────────────────────────────────────────
// SH14 / D12 — per-hat role tests.
// ─────────────────────────────────────────────────────────────────────

fn roleTestClock() i64 {
    return 1_700_000_000;
}

test "issue: defaults role to operator" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir = try tmp.dir.realpath(".", &path_buf);
    var store = try TokenStore.init(allocator, dir, roleTestClock);
    defer store.deinit();

    const issued = try store.issue("laptop", 0);
    try std.testing.expectEqualStrings("operator", issued.record.role);
}

test "issueWithRole: admin honoured; verify surfaces role" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir = try tmp.dir.realpath(".", &path_buf);
    var store = try TokenStore.init(allocator, dir, roleTestClock);
    defer store.deinit();

    const issued = try store.issueWithRole("admin-hat", 0, "admin");
    try std.testing.expectEqualStrings("admin", issued.record.role);
    const rec = try store.verify(&issued.token);
    try std.testing.expectEqualStrings("admin", rec.role);
}

test "issueWithRole: unknown role coerces to operator (fail-safe)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir = try tmp.dir.realpath(".", &path_buf);
    var store = try TokenStore.init(allocator, dir, roleTestClock);
    defer store.deinit();

    const issued = try store.issueWithRole("x", 0, "superuser");
    try std.testing.expectEqualStrings("operator", issued.record.role);
}

test "replay: legacy issued line without role → operator (back-compat)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Pre-seed a pre-SH14 issued line — NO role field.
    {
        var f = try tmp.dir.createFile("bearer-tokens.log", .{});
        defer f.close();
        try f.writeAll(
            "{\"ts\":1,\"kind\":\"issued\",\"id\":\"" ++ ("0" ** 32) ++
                "\",\"label\":\"legacy\",\"fingerprint\":\"" ++ ("a" ** 64) ++
                "\",\"issued_at\":1,\"expires_at\":0}\n",
        );
    }

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir = try tmp.dir.realpath(".", &path_buf);
    var store = try TokenStore.init(allocator, dir, roleTestClock);
    defer store.deinit();

    const recs = try store.list(allocator);
    defer allocator.free(recs);
    try std.testing.expectEqual(@as(usize, 1), recs.len);
    try std.testing.expectEqualStrings("legacy", recs[0].label);
    try std.testing.expectEqualStrings("operator", recs[0].role);
}

test "replay: round-trips an admin role through the log" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir = try tmp.dir.realpath(".", &path_buf);

    // Issue an admin token, then re-open the store (forces a log replay).
    {
        var store = try TokenStore.init(allocator, dir, roleTestClock);
        defer store.deinit();
        _ = try store.issueWithRole("admin-hat", 0, "admin");
    }
    var store2 = try TokenStore.init(allocator, dir, roleTestClock);
    defer store2.deinit();
    const recs = try store2.list(allocator);
    defer allocator.free(recs);
    try std.testing.expectEqual(@as(usize, 1), recs.len);
    try std.testing.expectEqualStrings("admin", recs[0].role);
}

```
