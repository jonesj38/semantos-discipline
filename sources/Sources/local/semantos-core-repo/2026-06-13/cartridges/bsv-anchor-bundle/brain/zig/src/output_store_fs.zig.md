---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/output_store_fs.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.445409+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/output_store_fs.zig

```zig
// Phase WSITE4.6 — File-backed OutputStore for the sovereign-node shell.
//
// Reference: docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md §3 (WSITE4.6 —
// internalizeAction integration) and `WALLET-ACTIVE-USE-ROADMAP.md` §2 / WA2.
//
// Persists the wallet's UTXO set on disk so verified payments survive
// process restarts.  Conforms to the same `output_store.OutputStore` vtable
// the in-memory `LocalOutputStore` exposes — drop-in for any caller that
// already speaks the cell-engine surface.
//
// On-disk format: append-only JSON-line log (mirrors payment_ledger.zig +
// audit_log.zig).  Each line is one event:
//
//   {"op":"add","record":{...full OutputRecord JSON...}}
//   {"op":"mark_spent","txid":"<hex>","vout":N,"spending":"<hex>"}
//   {"op":"prune_beef","txid":"<hex>","vout":N}
//   {"op":"delete","txid":"<hex>","vout":N}
//
// On `init`, every line is replayed in order to reconstruct in-memory
// state.  The file is then opened in append-only mode for subsequent
// writes.  Rolled-back state isn't supported at v0.1 — operators wipe
// `outputs.log` only as a recovery tool.
//
// Layout:
//
//     <data-dir>/outputs.log            — append-only event log
//
// All variable-length fields (locking_script, beef, basket, tags, custom
// instructions) are persisted as base64 strings to keep the log a single
// JSON object per line.  The choice keeps the log human-readable for the
// most common fields (basket, tags) while staying robust to binary data
// in scripts + BEEFs.

const std = @import("std");
const output_store = @import("output_store");

pub const OutputStore = output_store.OutputStore;
pub const OutputRecord = output_store.OutputRecord;
pub const Outpoint = output_store.Outpoint;
pub const StoreError = output_store.StoreError;
pub const OutputStatus = output_store.OutputStatus;

const Key = [36]u8;

pub const FsOutputStore = struct {
    allocator: std.mem.Allocator,
    log_path: []u8,
    log_file: ?std.fs.File,
    /// In-memory cache, replayed from disk on init.  All variable-length
    /// fields owned by `allocator`.
    map: std.AutoHashMap(Key, OutputRecord),

    pub fn init(allocator: std.mem.Allocator, data_dir: []const u8) !FsOutputStore {
        std.fs.cwd().makePath(data_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        const log_path = try std.fs.path.join(allocator, &.{ data_dir, "outputs.log" });
        errdefer allocator.free(log_path);

        var self: FsOutputStore = .{
            .allocator = allocator,
            .log_path = log_path,
            .log_file = null,
            .map = std.AutoHashMap(Key, OutputRecord).init(allocator),
        };
        self.replayFromDisk() catch |err| switch (err) {
            error.FileNotFound => {},
            else => {
                self.deinit();
                return err;
            },
        };
        // Re-open in append mode for future writes.
        const f = std.fs.cwd().createFile(log_path, .{ .read = false, .truncate = false }) catch null;
        if (f) |fh| fh.seekFromEnd(0) catch {};
        self.log_file = f;
        return self;
    }

    pub fn deinit(self: *FsOutputStore) void {
        if (self.log_file) |f| f.close();
        var it = self.map.valueIterator();
        while (it.next()) |rec| self.freeRecord(rec);
        self.map.deinit();
        self.allocator.free(self.log_path);
    }

    pub fn store(self: *FsOutputStore) OutputStore {
        return .{ .ctx = @ptrCast(self), .vtable = &fs_vtable };
    }

    // ── Internal helpers ───────────────────────────────────────────────

    fn keyFor(op: Outpoint) Key {
        var k: Key = undefined;
        @memcpy(k[0..32], &op.txid);
        std.mem.writeInt(u32, k[32..36], op.vout, .little);
        return k;
    }

    fn freeRecord(self: *FsOutputStore, r: *OutputRecord) void {
        self.allocator.free(r.locking_script);
        self.allocator.free(r.beef);
        self.allocator.free(r.basket);
        self.allocator.free(r.tags);
        self.allocator.free(r.custom_instructions);
    }

    fn copySlice(self: *FsOutputStore, src: []const u8) StoreError![]const u8 {
        const dst = self.allocator.alloc(u8, src.len) catch return error.out_of_memory;
        @memcpy(dst, src);
        return dst;
    }

    fn cloneRecord(self: *FsOutputStore, src: OutputRecord) StoreError!OutputRecord {
        return .{
            .outpoint = src.outpoint,
            .satoshis = src.satoshis,
            .locking_script = try self.copySlice(src.locking_script),
            .derived_key_hash = src.derived_key_hash,
            .derivation_protocol_hash = src.derivation_protocol_hash,
            .derivation_counterparty = src.derivation_counterparty,
            .derivation_index = src.derivation_index,
            .beef = try self.copySlice(src.beef),
            .basket = try self.copySlice(src.basket),
            .tags = try self.copySlice(src.tags),
            .custom_instructions = try self.copySlice(src.custom_instructions),
            .confirmations = src.confirmations,
            .status = src.status,
            .spending_txid = src.spending_txid,
        };
    }

    // ── JSON serialisation ─────────────────────────────────────────────

    fn writeAddEvent(self: *FsOutputStore, rec: OutputRecord) !void {
        const f = self.log_file orelse return;
        var buf = std.ArrayList(u8){};
        defer buf.deinit(self.allocator);

        try buf.appendSlice(self.allocator, "{\"op\":\"add\",\"record\":{");
        try writeJsonField(self.allocator, &buf, "txid", &rec.outpoint.txid);
        try buf.appendSlice(self.allocator, ",\"vout\":");
        try printInt(self.allocator, &buf, rec.outpoint.vout);
        try buf.appendSlice(self.allocator, ",\"satoshis\":");
        try printInt(self.allocator, &buf, rec.satoshis);
        try buf.appendSlice(self.allocator, ",");
        try writeJsonField(self.allocator, &buf, "locking_script", rec.locking_script);
        try buf.appendSlice(self.allocator, ",");
        try writeJsonField(self.allocator, &buf, "derived_key_hash", &rec.derived_key_hash);
        try buf.appendSlice(self.allocator, ",");
        try writeJsonField(self.allocator, &buf, "derivation_protocol_hash", &rec.derivation_protocol_hash);
        try buf.appendSlice(self.allocator, ",");
        try writeJsonField(self.allocator, &buf, "derivation_counterparty", &rec.derivation_counterparty);
        try buf.appendSlice(self.allocator, ",\"derivation_index\":");
        try printInt(self.allocator, &buf, rec.derivation_index);
        try buf.appendSlice(self.allocator, ",");
        try writeJsonField(self.allocator, &buf, "beef", rec.beef);
        try buf.appendSlice(self.allocator, ",");
        try writeJsonStringField(self.allocator, &buf, "basket", rec.basket);
        try buf.appendSlice(self.allocator, ",");
        try writeJsonField(self.allocator, &buf, "tags", rec.tags);
        try buf.appendSlice(self.allocator, ",");
        try writeJsonField(self.allocator, &buf, "custom_instructions", rec.custom_instructions);
        try buf.appendSlice(self.allocator, ",\"confirmations\":");
        try printInt(self.allocator, &buf, rec.confirmations);
        try buf.appendSlice(self.allocator, ",\"status\":");
        try printInt(self.allocator, &buf, @as(u8, @intFromEnum(rec.status)));
        try buf.appendSlice(self.allocator, ",");
        try writeJsonField(self.allocator, &buf, "spending_txid", &rec.spending_txid);
        try buf.appendSlice(self.allocator, "}}\n");
        f.writeAll(buf.items) catch return error.persistence_failed;
    }

    fn writeMarkSpentEvent(self: *FsOutputStore, op: Outpoint, spending: [32]u8) !void {
        const f = self.log_file orelse return;
        var buf = std.ArrayList(u8){};
        defer buf.deinit(self.allocator);
        try buf.appendSlice(self.allocator, "{\"op\":\"mark_spent\",");
        try writeJsonField(self.allocator, &buf, "txid", &op.txid);
        try buf.appendSlice(self.allocator, ",\"vout\":");
        try printInt(self.allocator, &buf, op.vout);
        try buf.appendSlice(self.allocator, ",");
        try writeJsonField(self.allocator, &buf, "spending", &spending);
        try buf.appendSlice(self.allocator, "}\n");
        f.writeAll(buf.items) catch return error.persistence_failed;
    }

    fn writePruneBeefEvent(self: *FsOutputStore, op: Outpoint) !void {
        const f = self.log_file orelse return;
        var buf = std.ArrayList(u8){};
        defer buf.deinit(self.allocator);
        try buf.appendSlice(self.allocator, "{\"op\":\"prune_beef\",");
        try writeJsonField(self.allocator, &buf, "txid", &op.txid);
        try buf.appendSlice(self.allocator, ",\"vout\":");
        try printInt(self.allocator, &buf, op.vout);
        try buf.appendSlice(self.allocator, "}\n");
        f.writeAll(buf.items) catch return error.persistence_failed;
    }

    fn writeDeleteEvent(self: *FsOutputStore, op: Outpoint) !void {
        const f = self.log_file orelse return;
        var buf = std.ArrayList(u8){};
        defer buf.deinit(self.allocator);
        try buf.appendSlice(self.allocator, "{\"op\":\"delete\",");
        try writeJsonField(self.allocator, &buf, "txid", &op.txid);
        try buf.appendSlice(self.allocator, ",\"vout\":");
        try printInt(self.allocator, &buf, op.vout);
        try buf.appendSlice(self.allocator, "}\n");
        f.writeAll(buf.items) catch return error.persistence_failed;
    }

    // Hex-encoded so the file stays a single line of JSON without
    // base64-padding edge cases.  Hex doubles the size vs base64 but the
    // log is not the primary storage path — the lmdb backing in v0.3
    // uses raw bytes.
    fn writeJsonField(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), name: []const u8, bytes: []const u8) !void {
        try buf.append(allocator, '"');
        try buf.appendSlice(allocator, name);
        try buf.appendSlice(allocator, "\":\"");
        const hex_chars = "0123456789abcdef";
        for (bytes) |b| {
            try buf.append(allocator, hex_chars[(b >> 4) & 0xf]);
            try buf.append(allocator, hex_chars[b & 0xf]);
        }
        try buf.append(allocator, '"');
    }

    fn writeJsonStringField(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), name: []const u8, s: []const u8) !void {
        try buf.append(allocator, '"');
        try buf.appendSlice(allocator, name);
        try buf.appendSlice(allocator, "\":\"");
        // Naive escape — basket names and similar fields are plain ASCII
        // by convention; we only escape backslash + quote for safety.
        for (s) |c| {
            if (c == '"' or c == '\\') {
                try buf.append(allocator, '\\');
            }
            try buf.append(allocator, c);
        }
        try buf.append(allocator, '"');
    }

    fn printInt(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), v: anytype) !void {
        var tmp: [32]u8 = undefined;
        const s = try std.fmt.bufPrint(&tmp, "{d}", .{v});
        try buf.appendSlice(allocator, s);
    }

    // ── Replay ─────────────────────────────────────────────────────────

    fn replayFromDisk(self: *FsOutputStore) !void {
        const file = std.fs.cwd().openFile(self.log_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer file.close();
        const stat = try file.stat();
        if (stat.size == 0) return;

        const buf = try self.allocator.alloc(u8, stat.size);
        defer self.allocator.free(buf);
        _ = try file.readAll(buf);

        var line_iter = std.mem.tokenizeScalar(u8, buf, '\n');
        while (line_iter.next()) |line| {
            self.applyEventLine(line) catch {
                // Skip malformed lines — better to soldier on with
                // partial state than refuse to start.
                continue;
            };
        }
    }

    fn applyEventLine(self: *FsOutputStore, line: []const u8) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const parsed = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), line, .{}) catch return error.bad_event;
        if (parsed != .object) return error.bad_event;
        const obj = parsed.object;
        const op_v = obj.get("op") orelse return error.bad_event;
        if (op_v != .string) return error.bad_event;
        const op_str = op_v.string;

        if (std.mem.eql(u8, op_str, "add")) {
            const rec_v = obj.get("record") orelse return error.bad_event;
            if (rec_v != .object) return error.bad_event;
            const rec = try self.parseRecord(rec_v.object);
            const k = keyFor(rec.outpoint);
            // Replay can encounter the same add twice if writes raced —
            // last-write-wins.  Free prior + replace.
            if (self.map.getPtr(k)) |prior| self.freeRecord(prior);
            self.map.put(k, rec) catch return error.out_of_memory;
            return;
        }
        if (std.mem.eql(u8, op_str, "mark_spent")) {
            const op = try parseOutpoint(obj);
            const sp_v = obj.get("spending") orelse return error.bad_event;
            if (sp_v != .string) return error.bad_event;
            var spending: [32]u8 = undefined;
            try hexDecode(sp_v.string, &spending);
            const k = keyFor(op);
            const entry = self.map.getPtr(k) orelse return; // dangling event; ignore
            entry.status = .spent;
            entry.spending_txid = spending;
            return;
        }
        if (std.mem.eql(u8, op_str, "prune_beef")) {
            const op = try parseOutpoint(obj);
            const k = keyFor(op);
            const entry = self.map.getPtr(k) orelse return;
            self.allocator.free(entry.beef);
            entry.beef = &[_]u8{};
            return;
        }
        if (std.mem.eql(u8, op_str, "delete")) {
            const op = try parseOutpoint(obj);
            const k = keyFor(op);
            if (self.map.getPtr(k)) |r| self.freeRecord(r);
            _ = self.map.remove(k);
            return;
        }
        return error.bad_event;
    }

    fn parseOutpoint(obj: std.json.ObjectMap) !Outpoint {
        const txid_v = obj.get("txid") orelse return error.bad_event;
        const vout_v = obj.get("vout") orelse return error.bad_event;
        if (txid_v != .string or vout_v != .integer) return error.bad_event;
        var txid: [32]u8 = undefined;
        try hexDecode(txid_v.string, &txid);
        return .{ .txid = txid, .vout = @intCast(vout_v.integer) };
    }

    fn parseRecord(self: *FsOutputStore, obj: std.json.ObjectMap) !OutputRecord {
        const op = try parseOutpoint(obj);
        const sats_v = obj.get("satoshis") orelse return error.bad_event;
        if (sats_v != .integer or sats_v.integer < 0) return error.bad_event;

        const ls = try parseHexBytesOwned(self.allocator, obj, "locking_script");
        errdefer self.allocator.free(ls);
        const beef = try parseHexBytesOwned(self.allocator, obj, "beef");
        errdefer self.allocator.free(beef);
        const basket = try parseStringOwned(self.allocator, obj, "basket");
        errdefer self.allocator.free(basket);
        const tags = try parseHexBytesOwned(self.allocator, obj, "tags");
        errdefer self.allocator.free(tags);
        const ci = try parseHexBytesOwned(self.allocator, obj, "custom_instructions");
        errdefer self.allocator.free(ci);

        var dkh: [32]u8 = undefined;
        try parseHexFixed(obj, "derived_key_hash", &dkh);
        var dph: [16]u8 = undefined;
        try parseHexFixed(obj, "derivation_protocol_hash", &dph);
        var dcp: [33]u8 = undefined;
        try parseHexFixed(obj, "derivation_counterparty", &dcp);
        var sp: [32]u8 = undefined;
        try parseHexFixed(obj, "spending_txid", &sp);

        const di_v = obj.get("derivation_index") orelse return error.bad_event;
        const conf_v = obj.get("confirmations") orelse return error.bad_event;
        const status_v = obj.get("status") orelse return error.bad_event;
        if (di_v != .integer or conf_v != .integer or status_v != .integer) return error.bad_event;

        const status_int: u8 = @intCast(status_v.integer);
        const status: OutputStatus = std.meta.intToEnum(OutputStatus, status_int) catch return error.bad_event;

        return .{
            .outpoint = op,
            .satoshis = @intCast(sats_v.integer),
            .locking_script = ls,
            .derived_key_hash = dkh,
            .derivation_protocol_hash = dph,
            .derivation_counterparty = dcp,
            .derivation_index = @intCast(di_v.integer),
            .beef = beef,
            .basket = basket,
            .tags = tags,
            .custom_instructions = ci,
            .confirmations = @intCast(conf_v.integer),
            .status = status,
            .spending_txid = sp,
        };
    }

    // ── VTable implementations ─────────────────────────────────────────

    fn vAdd(ctx: *anyopaque, record: OutputRecord) StoreError!void {
        const self: *FsOutputStore = @ptrCast(@alignCast(ctx));
        const k = keyFor(record.outpoint);
        if (self.map.contains(k)) return error.duplicate_outpoint;
        const owned = try self.cloneRecord(record);
        self.map.put(k, owned) catch return error.out_of_memory;
        self.writeAddEvent(record) catch return error.persistence_failed;
    }

    fn vList(
        ctx: *anyopaque,
        basket_filter: ?[]const u8,
        tag_filter: ?[]const u8,
        allocator: std.mem.Allocator,
    ) StoreError![]OutputRecord {
        const self: *FsOutputStore = @ptrCast(@alignCast(ctx));
        var matching: std.ArrayList(OutputRecord) = .empty;
        defer matching.deinit(allocator);
        var it = self.map.valueIterator();
        while (it.next()) |entry| {
            if (entry.status != .unspent) continue;
            if (basket_filter) |b| if (!std.mem.eql(u8, entry.basket, b)) continue;
            if (tag_filter) |t| if (!hasTag(entry.tags, t)) continue;
            matching.append(allocator, entry.*) catch return error.out_of_memory;
        }
        return matching.toOwnedSlice(allocator) catch return error.out_of_memory;
    }

    fn hasTag(packed_tags: []const u8, want: []const u8) bool {
        var i: usize = 0;
        while (i + 2 <= packed_tags.len) {
            const tag_len = std.mem.readInt(u16, packed_tags[i..][0..2], .little);
            i += 2;
            if (i + tag_len > packed_tags.len) return false;
            if (std.mem.eql(u8, packed_tags[i .. i + tag_len], want)) return true;
            i += tag_len;
        }
        return false;
    }

    fn vGet(ctx: *anyopaque, op: Outpoint) ?OutputRecord {
        const self: *FsOutputStore = @ptrCast(@alignCast(ctx));
        return self.map.get(keyFor(op));
    }

    fn vMarkSpent(ctx: *anyopaque, op: Outpoint, spending: [32]u8) StoreError!void {
        const self: *FsOutputStore = @ptrCast(@alignCast(ctx));
        const k = keyFor(op);
        const entry = self.map.getPtr(k) orelse return error.unknown_outpoint;
        entry.status = .spent;
        entry.spending_txid = spending;
        self.writeMarkSpentEvent(op, spending) catch return error.persistence_failed;
    }

    fn vPrune(ctx: *anyopaque, min_confirmations: u32) StoreError!u64 {
        const self: *FsOutputStore = @ptrCast(@alignCast(ctx));
        var pruned: u64 = 0;
        var it = self.map.valueIterator();
        while (it.next()) |entry| {
            if (entry.confirmations >= min_confirmations and entry.beef.len > 0) {
                self.allocator.free(entry.beef);
                entry.beef = &[_]u8{};
                self.writePruneBeefEvent(entry.outpoint) catch return error.persistence_failed;
                pruned += 1;
            }
        }
        var to_delete: std.ArrayList(Key) = .empty;
        defer to_delete.deinit(self.allocator);
        var it2 = self.map.iterator();
        while (it2.next()) |entry| {
            if (entry.value_ptr.status == .spent and entry.value_ptr.confirmations >= 1000) {
                to_delete.append(self.allocator, entry.key_ptr.*) catch return error.out_of_memory;
            }
        }
        for (to_delete.items) |k| {
            const op = blk: {
                var op: Outpoint = undefined;
                @memcpy(&op.txid, k[0..32]);
                op.vout = std.mem.readInt(u32, k[32..36], .little);
                break :blk op;
            };
            self.writeDeleteEvent(op) catch return error.persistence_failed;
            if (self.map.getPtr(k)) |r| self.freeRecord(r);
            _ = self.map.remove(k);
            pruned += 1;
        }
        return pruned;
    }

    fn vSnapshot(ctx: *anyopaque, allocator: std.mem.Allocator) StoreError![]OutputRecord {
        const self: *FsOutputStore = @ptrCast(@alignCast(ctx));
        var out = allocator.alloc(OutputRecord, self.map.count()) catch return error.out_of_memory;
        var it = self.map.valueIterator();
        var i: usize = 0;
        while (it.next()) |entry| : (i += 1) out[i] = entry.*;
        return out;
    }

    fn vReplay(ctx: *anyopaque, records: []const OutputRecord) StoreError!void {
        const self: *FsOutputStore = @ptrCast(@alignCast(ctx));
        // Wipe in-memory state. The on-disk log is *not* truncated —
        // operators wanting a clean replay slate should delete
        // outputs.log before calling replay.  This matches the
        // LocalOutputStore semantics: replay replaces, doesn't merge.
        var it = self.map.iterator();
        while (it.next()) |entry| self.freeRecord(entry.value_ptr);
        self.map.clearRetainingCapacity();
        for (records) |r| {
            const owned = try self.cloneRecord(r);
            self.map.put(keyFor(r.outpoint), owned) catch return error.out_of_memory;
            self.writeAddEvent(r) catch return error.persistence_failed;
        }
    }

    const fs_vtable: OutputStore.VTable = .{
        .add_output = vAdd,
        .list_outputs = vList,
        .get_output = vGet,
        .mark_spent = vMarkSpent,
        .prune_confirmed = vPrune,
        .snapshot = vSnapshot,
        .replay = vReplay,
    };
};

// ─────────────────────────────────────────────────────────────────────
// Hex helpers — used by both write + replay.
// ─────────────────────────────────────────────────────────────────────

fn parseHexBytesOwned(allocator: std.mem.Allocator, obj: std.json.ObjectMap, name: []const u8) ![]u8 {
    const v = obj.get(name) orelse return error.bad_event;
    if (v != .string) return error.bad_event;
    const hex = v.string;
    if (hex.len % 2 != 0) return error.bad_event;
    const out = try allocator.alloc(u8, hex.len / 2);
    errdefer allocator.free(out);
    try hexDecode(hex, out);
    return out;
}

fn parseStringOwned(allocator: std.mem.Allocator, obj: std.json.ObjectMap, name: []const u8) ![]u8 {
    const v = obj.get(name) orelse return error.bad_event;
    if (v != .string) return error.bad_event;
    return allocator.dupe(u8, v.string);
}

fn parseHexFixed(obj: std.json.ObjectMap, name: []const u8, out: []u8) !void {
    const v = obj.get(name) orelse return error.bad_event;
    if (v != .string) return error.bad_event;
    if (v.string.len != out.len * 2) return error.bad_event;
    try hexDecode(v.string, out);
}

fn hexDecode(hex: []const u8, out: []u8) !void {
    if (hex.len != out.len * 2) return error.bad_event;
    for (0..out.len) |i| {
        const hi = try nibble(hex[i * 2]);
        const lo = try nibble(hex[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
    }
}

fn nibble(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => 10 + (c - 'a'),
        'A'...'F' => 10 + (c - 'A'),
        else => error.bad_event,
    };
}

```
