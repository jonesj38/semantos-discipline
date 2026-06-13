---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/intent_cells_store_fs.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.230263+00:00
---

# runtime/semantos-brain/src/intent_cells_store_fs.zig

```zig
// Phase 3 — Intent cells store (typed-NL `oddjobz.intent_cell.v1` queue).
//
// Reference: docs/spec/oddjobz-intent-cell-v1.md ("Storage" section);
//            runtime/semantos-brain/src/leads_store_fs.zig (canonical post-#319 /
//            post-#422 per-string-heap-allocation template);
//            runtime/semantos-brain/src/sites_store_fs.zig (post-#422 per-key
//            owned-slice pattern for HashMap keys).
//
// Append-only JSON-lines store at `<data_dir>/oddjobz/intent-cells.jsonl`.
// One line per `created` event; the in-memory index is rebuilt by
// replaying the file at startup; writes append-then-fsync.
//
// What this is: the brain-side persistence sink for typed natural-
// language intent cells the operator's phone produces.  Each row
// captures the full envelope-shape minus `kind` + `version` (those
// are constants for v1) plus the brain's local kernel-result mirror
// + the phone's claimed kernel result preserved verbatim for drift
// analysis.
//
// Idempotency: same `cellId` + same envelope content → no-op for the
// in-memory map (existing record stays); same `cellId` + DIFFERENT
// content → `cell_id_in_use_with_different_contents` error.  The
// handler exposes the no-op as `status: "already_exists"`.
//
// Per-string heap allocation pattern (mirror leads_store_fs.zig
// post-#319): each IntentCellRecord's String fields are individually
// heap-allocated via `allocator.dupe`; an `OwnedStrings` ArrayList
// tracks them so `deinit` can free them in lock-step.  Avoids the
// dangling-slice hazard from PR #422 (shared `ArrayList(u8)` arena
// reallocs on grow → HashMap keys dangle → next put panics).

const std = @import("std");

pub const StoreError = error{
    out_of_memory,
    persistence_failed,
    bad_format,
    invalid_cell_id,
    invalid_hat_id,
    invalid_cert_id,
    invalid_correlation_id,
    invalid_phone_kernel_result,
    invalid_opcode_bytes,
    invalid_intent_summary,
    invalid_intent_action,
    invalid_intent_taxonomy,
    invalid_received_at,
    /// Same cellId already exists with byte-identical content.
    /// (Surfaced as `CreateResult.already_exists`; not raised as an
    /// error.)
    already_exists,
    /// Same cellId already exists with DIFFERENT content.  First-write-
    /// wins; the handler echoes this as the typed envelope error
    /// `cell_id_in_use_with_different_contents`.
    cell_id_in_use_with_different_contents,
};

/// Field-length envelopes.  Bounded so the JSONL file stays
/// hand-grep-friendly + so a malformed envelope can't blow up the
/// record-store memory budget.
pub const MAX_CELL_ID_BYTES: usize = 128;
pub const MAX_HAT_ID_BYTES: usize = 64;
pub const MAX_CERT_ID_BYTES: usize = 128;
pub const MAX_CORRELATION_ID_BYTES: usize = 64;
pub const MAX_OPCODE_BYTES_B64: usize = 16_000; // 10 KiB raw → ~13.4 KiB base64; 16 KiB envelope.
pub const MAX_PHONE_KERNEL_RESULT_BYTES: usize = 1024;
pub const MAX_INTENT_SUMMARY_BYTES: usize = 500;
pub const MAX_INTENT_ACTION_BYTES: usize = 64;
pub const MAX_INTENT_TAXONOMY_BYTES: usize = 1024;
/// Wave 9 follow-up — cap for the optional `originalIntent.targetJson`
/// string the producer ships when it has resolved entity refs or
/// money fields. Bounded the same way as taxonomy. If a producer ever
/// needs more than 1 KiB of structured target it should split into
/// a separate cell. Always optional; legacy producers omit the field.
pub const MAX_INTENT_TARGET_BYTES: usize = 1024;
pub const MAX_RECEIVED_AT_BYTES: usize = 64;

/// One row in the helm IntentCells view.  Owned by the store; pointers
/// into every string field are valid until the store is deinit'd.
pub const IntentCellRecord = struct {
    /// `cell-<sizeHex>-<bytePrefix>-<uuidTail>`; primary key.  Borrowed.
    cell_id: []const u8,
    /// Operator's root-cert id (32-hex).  Borrowed.
    hat_id: []const u8,
    /// Child-cert id under the operator's chain.  Borrowed.
    cert_id: []const u8,
    /// UUIDv4 threading through stage events for this turn.  Borrowed.
    correlation_id: []const u8,
    /// Brain's local kernel verdict: opcount.
    opcount: u32,
    /// Brain's local kernel verdict: stack depth.
    stack_depth: u32,
    /// Brain's local kernel verdict: gas used.
    gas_used: u32,
    /// Brain's local kernel verdict: ok flag.  Always true for
    /// persisted records (Phase 1 policy: brain rejects local
    /// failures before persisting).
    kernel_ok: bool,
    /// Phone's claimed `kernelResult` JSON, stored verbatim for
    /// drift analysis.  Borrowed.
    phone_kernel_result_json: []const u8,
    /// Base64 of the OIR-emitted opcode stream.  Borrowed.
    opcode_bytes_b64: []const u8,
    /// Operator-readable summary.  Borrowed.
    intent_summary: []const u8,
    /// One of `ExtensionGrammar.oddjobz.actionVerbs`.  Borrowed.
    intent_action: []const u8,
    /// Stringified `{what,how,why}` triple.  Borrowed.
    intent_taxonomy_json: []const u8,
    /// Server-stamped ISO-8601 UTC at append time.  Borrowed.
    received_at: []const u8,
};

/// Heap-allocated string set for one IntentCellRecord.  Each pointer
/// is its own `allocator.dupe` allocation so the slices never dangle
/// across store mutations.  Freed in lock-step with `records.deinit`
/// via `IntentCellsStore.deinit`.
const OwnedStrings = struct {
    cell_id: []u8,
    hat_id: []u8,
    cert_id: []u8,
    correlation_id: []u8,
    phone_kernel_result_json: []u8,
    opcode_bytes_b64: []u8,
    intent_summary: []u8,
    intent_action: []u8,
    intent_taxonomy_json: []u8,
    received_at: []u8,

    fn freeAll(self: *OwnedStrings, allocator: std.mem.Allocator) void {
        allocator.free(self.cell_id);
        allocator.free(self.hat_id);
        allocator.free(self.cert_id);
        allocator.free(self.correlation_id);
        allocator.free(self.phone_kernel_result_json);
        allocator.free(self.opcode_bytes_b64);
        allocator.free(self.intent_summary);
        allocator.free(self.intent_action);
        allocator.free(self.intent_taxonomy_json);
        allocator.free(self.received_at);
    }
};

pub const CreateResult = enum {
    created,
    already_exists,
};

pub const ListOpts = struct {
    /// Filter to records carrying this `hat_id`.  null = no filter.
    hat_id: ?[]const u8 = null,
    /// Filter to records with `received_at >= since` (string compare;
    /// works for ISO-8601 timestamps).  null = no filter.
    since: ?[]const u8 = null,
    /// Maximum number of records to return.  null = no cap.  When set,
    /// the most-recently-received N are returned (tail-cut).
    limit: ?usize = null,
};

pub const IntentCellsStore = struct {
    allocator: std.mem.Allocator,
    log_path: []u8,
    log_file: ?std.fs.File,
    records: std.ArrayList(IntentCellRecord),
    by_id: std.StringHashMap(usize),
    owned_strings: std.ArrayList(OwnedStrings),
    clock: *const fn () i64,

    pub fn init(
        allocator: std.mem.Allocator,
        data_dir: []const u8,
        clock_fn: *const fn () i64,
    ) !IntentCellsStore {
        const oddjobz_dir = try std.fs.path.join(allocator, &.{ data_dir, "oddjobz" });
        defer allocator.free(oddjobz_dir);
        std.fs.cwd().makePath(oddjobz_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        const log_path = try std.fs.path.join(allocator, &.{ oddjobz_dir, "intent-cells.jsonl" });
        errdefer allocator.free(log_path);
        var self = IntentCellsStore{
            .allocator = allocator,
            .log_path = log_path,
            .log_file = null,
            .records = .{},
            .by_id = std.StringHashMap(usize).init(allocator),
            .owned_strings = .{},
            .clock = clock_fn,
        };
        try self.openOrCreateLog();
        try self.replayLog();
        return self;
    }

    pub fn deinit(self: *IntentCellsStore) void {
        if (self.log_file) |f| f.close();
        for (self.owned_strings.items) |*s| s.freeAll(self.allocator);
        self.owned_strings.deinit(self.allocator);
        self.records.deinit(self.allocator);
        self.by_id.deinit();
        self.allocator.free(self.log_path);
    }

    /// Append a `created` event for `record` to the log + update the
    /// in-memory index + fsync.  Idempotent on `cell_id`.  Same id +
    /// byte-identical content → `.already_exists`; same id + different
    /// content → `cell_id_in_use_with_different_contents` error.
    pub fn create(self: *IntentCellsStore, record: IntentCellRecord) StoreError!CreateResult {
        try validateLengths(record);

        if (self.by_id.get(record.cell_id)) |idx| {
            const existing = self.records.items[idx];
            if (recordsEqual(existing, record)) {
                // Idempotent re-write: append the audit line so the
                // operator can see the duplicate submission, but the
                // in-memory record stays untouched (first-write-wins).
                self.appendCreatedLine(record) catch return StoreError.persistence_failed;
                return .already_exists;
            }
            return StoreError.cell_id_in_use_with_different_contents;
        }

        self.appendCreatedLine(record) catch return StoreError.persistence_failed;

        const stored = self.cloneRecord(record) catch |err| switch (err) {
            error.OutOfMemory => return StoreError.out_of_memory,
        };
        self.records.append(self.allocator, stored) catch return StoreError.out_of_memory;
        const idx = self.records.items.len - 1;
        self.by_id.put(self.records.items[idx].cell_id, idx) catch return StoreError.out_of_memory;
        return .created;
    }

    /// Lookup by `cell_id`.  Returns a pointer into the store's owned
    /// records (valid until deinit) or null on miss.
    pub fn findById(self: *const IntentCellsStore, id: []const u8) ?*const IntentCellRecord {
        const idx = self.by_id.get(id) orelse return null;
        return &self.records.items[idx];
    }

    /// Snapshot records matching `opts` in append order.  Caller owns
    /// the returned slice; pointers into each record borrow from the
    /// store and are valid until the store deinit's.
    pub fn list(
        self: *const IntentCellsStore,
        allocator: std.mem.Allocator,
        opts: ListOpts,
    ) ![]IntentCellRecord {
        var matched: std.ArrayList(IntentCellRecord) = .{};
        defer matched.deinit(allocator);
        for (self.records.items) |r| {
            if (opts.hat_id) |h| {
                if (!std.mem.eql(u8, r.hat_id, h)) continue;
            }
            if (opts.since) |s| {
                // Lexicographic compare works for ISO-8601 timestamps.
                if (std.mem.lessThan(u8, r.received_at, s)) continue;
            }
            try matched.append(allocator, r);
        }
        if (opts.limit) |lim| {
            if (matched.items.len > lim) {
                // Tail-cut: keep the most-recent N.
                const start = matched.items.len - lim;
                const out = try allocator.alloc(IntentCellRecord, lim);
                @memcpy(out, matched.items[start..]);
                return out;
            }
        }
        const out = try allocator.alloc(IntentCellRecord, matched.items.len);
        @memcpy(out, matched.items);
        return out;
    }

    pub fn count(self: *const IntentCellsStore) usize {
        return self.records.items.len;
    }

    // ── log replay + append ──

    fn openOrCreateLog(self: *IntentCellsStore) !void {
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

    pub fn replayLog(self: *IntentCellsStore) !void {
        const f = self.log_file orelse return;
        try f.seekTo(0);
        const max = 1024 * 1024 * 64;
        const text = try f.readToEndAlloc(self.allocator, max);
        defer self.allocator.free(text);

        var it = std.mem.splitScalar(u8, text, '\n');
        while (it.next()) |line| {
            if (line.len == 0) continue;
            try self.applyLogLine(line);
        }
        try f.seekFromEnd(0);
    }

    fn applyLogLine(self: *IntentCellsStore, line: []const u8) !void {
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            line,
            .{},
        ) catch return; // Skip malformed lines — forward-compat.
        defer parsed.deinit();

        if (parsed.value != .object) return;
        const obj = parsed.value.object;
        const kind = obj.get("kind") orelse return;
        if (kind != .string) return;
        if (!std.mem.eql(u8, kind.string, "created")) return;

        const cell_id_v = obj.get("cell_id") orelse return;
        if (cell_id_v != .string) return;
        // Idempotent replay — already seen this cellId.
        if (self.by_id.contains(cell_id_v.string)) return;

        const hat_id_v = obj.get("hat_id") orelse return;
        if (hat_id_v != .string) return;
        const cert_id_v = obj.get("cert_id") orelse return;
        if (cert_id_v != .string) return;
        const correlation_id_v = obj.get("correlation_id") orelse return;
        if (correlation_id_v != .string) return;
        const opcount_v = obj.get("opcount") orelse return;
        if (opcount_v != .integer) return;
        const stack_depth_v = obj.get("stack_depth") orelse return;
        if (stack_depth_v != .integer) return;
        const gas_used_v = obj.get("gas_used") orelse return;
        if (gas_used_v != .integer) return;
        const kernel_ok_v = obj.get("kernel_ok") orelse return;
        if (kernel_ok_v != .bool) return;
        const phone_kernel_v = obj.get("phone_kernel_result_json") orelse return;
        if (phone_kernel_v != .string) return;
        const opcode_v = obj.get("opcode_bytes_b64") orelse return;
        if (opcode_v != .string) return;
        const summary_v = obj.get("intent_summary") orelse return;
        if (summary_v != .string) return;
        const action_v = obj.get("intent_action") orelse return;
        if (action_v != .string) return;
        const taxonomy_v = obj.get("intent_taxonomy_json") orelse return;
        if (taxonomy_v != .string) return;
        const received_at_v = obj.get("received_at") orelse return;
        if (received_at_v != .string) return;

        const candidate = IntentCellRecord{
            .cell_id = cell_id_v.string,
            .hat_id = hat_id_v.string,
            .cert_id = cert_id_v.string,
            .correlation_id = correlation_id_v.string,
            .opcount = @intCast(opcount_v.integer),
            .stack_depth = @intCast(stack_depth_v.integer),
            .gas_used = @intCast(gas_used_v.integer),
            .kernel_ok = kernel_ok_v.bool,
            .phone_kernel_result_json = phone_kernel_v.string,
            .opcode_bytes_b64 = opcode_v.string,
            .intent_summary = summary_v.string,
            .intent_action = action_v.string,
            .intent_taxonomy_json = taxonomy_v.string,
            .received_at = received_at_v.string,
        };
        validateLengths(candidate) catch return;

        const stored = try self.cloneRecord(candidate);
        try self.records.append(self.allocator, stored);
        const idx = self.records.items.len - 1;
        try self.by_id.put(self.records.items[idx].cell_id, idx);
    }

    fn appendCreatedLine(self: *IntentCellsStore, r: IntentCellRecord) !void {
        const f = self.log_file orelse return;
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);

        try buf.print(self.allocator,
            "{{\"ts\":{d},\"kind\":\"created\",\"cell_id\":",
            .{self.clock()},
        );
        try writeJsonString(self.allocator, &buf, r.cell_id);
        try buf.appendSlice(self.allocator, ",\"hat_id\":");
        try writeJsonString(self.allocator, &buf, r.hat_id);
        try buf.appendSlice(self.allocator, ",\"cert_id\":");
        try writeJsonString(self.allocator, &buf, r.cert_id);
        try buf.appendSlice(self.allocator, ",\"correlation_id\":");
        try writeJsonString(self.allocator, &buf, r.correlation_id);
        try buf.print(self.allocator, ",\"opcount\":{d}", .{r.opcount});
        try buf.print(self.allocator, ",\"stack_depth\":{d}", .{r.stack_depth});
        try buf.print(self.allocator, ",\"gas_used\":{d}", .{r.gas_used});
        try buf.appendSlice(self.allocator, ",\"kernel_ok\":");
        try buf.appendSlice(self.allocator, if (r.kernel_ok) "true" else "false");
        try buf.appendSlice(self.allocator, ",\"phone_kernel_result_json\":");
        try writeJsonString(self.allocator, &buf, r.phone_kernel_result_json);
        try buf.appendSlice(self.allocator, ",\"opcode_bytes_b64\":");
        try writeJsonString(self.allocator, &buf, r.opcode_bytes_b64);
        try buf.appendSlice(self.allocator, ",\"intent_summary\":");
        try writeJsonString(self.allocator, &buf, r.intent_summary);
        try buf.appendSlice(self.allocator, ",\"intent_action\":");
        try writeJsonString(self.allocator, &buf, r.intent_action);
        try buf.appendSlice(self.allocator, ",\"intent_taxonomy_json\":");
        try writeJsonString(self.allocator, &buf, r.intent_taxonomy_json);
        try buf.appendSlice(self.allocator, ",\"received_at\":");
        try writeJsonString(self.allocator, &buf, r.received_at);
        try buf.appendSlice(self.allocator, "}\n");

        try f.writeAll(buf.items);
        try f.sync();
    }

    fn cloneRecord(self: *IntentCellsStore, r: IntentCellRecord) !IntentCellRecord {
        var owned: OwnedStrings = undefined;
        owned.cell_id = try self.allocator.dupe(u8, r.cell_id);
        errdefer self.allocator.free(owned.cell_id);
        owned.hat_id = try self.allocator.dupe(u8, r.hat_id);
        errdefer self.allocator.free(owned.hat_id);
        owned.cert_id = try self.allocator.dupe(u8, r.cert_id);
        errdefer self.allocator.free(owned.cert_id);
        owned.correlation_id = try self.allocator.dupe(u8, r.correlation_id);
        errdefer self.allocator.free(owned.correlation_id);
        owned.phone_kernel_result_json = try self.allocator.dupe(u8, r.phone_kernel_result_json);
        errdefer self.allocator.free(owned.phone_kernel_result_json);
        owned.opcode_bytes_b64 = try self.allocator.dupe(u8, r.opcode_bytes_b64);
        errdefer self.allocator.free(owned.opcode_bytes_b64);
        owned.intent_summary = try self.allocator.dupe(u8, r.intent_summary);
        errdefer self.allocator.free(owned.intent_summary);
        owned.intent_action = try self.allocator.dupe(u8, r.intent_action);
        errdefer self.allocator.free(owned.intent_action);
        owned.intent_taxonomy_json = try self.allocator.dupe(u8, r.intent_taxonomy_json);
        errdefer self.allocator.free(owned.intent_taxonomy_json);
        owned.received_at = try self.allocator.dupe(u8, r.received_at);
        errdefer self.allocator.free(owned.received_at);

        try self.owned_strings.append(self.allocator, owned);
        return .{
            .cell_id = owned.cell_id,
            .hat_id = owned.hat_id,
            .cert_id = owned.cert_id,
            .correlation_id = owned.correlation_id,
            .opcount = r.opcount,
            .stack_depth = r.stack_depth,
            .gas_used = r.gas_used,
            .kernel_ok = r.kernel_ok,
            .phone_kernel_result_json = owned.phone_kernel_result_json,
            .opcode_bytes_b64 = owned.opcode_bytes_b64,
            .intent_summary = owned.intent_summary,
            .intent_action = owned.intent_action,
            .intent_taxonomy_json = owned.intent_taxonomy_json,
            .received_at = owned.received_at,
        };
    }
};

fn validateLengths(r: IntentCellRecord) StoreError!void {
    if (r.cell_id.len == 0 or r.cell_id.len > MAX_CELL_ID_BYTES) return StoreError.invalid_cell_id;
    if (r.hat_id.len == 0 or r.hat_id.len > MAX_HAT_ID_BYTES) return StoreError.invalid_hat_id;
    if (r.cert_id.len == 0 or r.cert_id.len > MAX_CERT_ID_BYTES) return StoreError.invalid_cert_id;
    if (r.correlation_id.len == 0 or r.correlation_id.len > MAX_CORRELATION_ID_BYTES) return StoreError.invalid_correlation_id;
    if (r.phone_kernel_result_json.len > MAX_PHONE_KERNEL_RESULT_BYTES) return StoreError.invalid_phone_kernel_result;
    if (r.opcode_bytes_b64.len > MAX_OPCODE_BYTES_B64) return StoreError.invalid_opcode_bytes;
    if (r.intent_summary.len == 0 or r.intent_summary.len > MAX_INTENT_SUMMARY_BYTES) return StoreError.invalid_intent_summary;
    if (r.intent_action.len == 0 or r.intent_action.len > MAX_INTENT_ACTION_BYTES) return StoreError.invalid_intent_action;
    if (r.intent_taxonomy_json.len > MAX_INTENT_TAXONOMY_BYTES) return StoreError.invalid_intent_taxonomy;
    if (r.received_at.len == 0 or r.received_at.len > MAX_RECEIVED_AT_BYTES) return StoreError.invalid_received_at;
}

fn recordsEqual(a: IntentCellRecord, b: IntentCellRecord) bool {
    return std.mem.eql(u8, a.cell_id, b.cell_id) and
        std.mem.eql(u8, a.hat_id, b.hat_id) and
        std.mem.eql(u8, a.cert_id, b.cert_id) and
        std.mem.eql(u8, a.correlation_id, b.correlation_id) and
        a.opcount == b.opcount and
        a.stack_depth == b.stack_depth and
        a.gas_used == b.gas_used and
        a.kernel_ok == b.kernel_ok and
        std.mem.eql(u8, a.phone_kernel_result_json, b.phone_kernel_result_json) and
        std.mem.eql(u8, a.opcode_bytes_b64, b.opcode_bytes_b64) and
        std.mem.eql(u8, a.intent_summary, b.intent_summary) and
        std.mem.eql(u8, a.intent_action, b.intent_action) and
        std.mem.eql(u8, a.intent_taxonomy_json, b.intent_taxonomy_json);
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

/// Render a unix timestamp as a minimal ISO-8601 UTC string.
pub fn renderIsoTimestamp(allocator: std.mem.Allocator, unix_seconds: i64) ![]u8 {
    const epoch_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(unix_seconds) };
    const epoch_day = epoch_secs.getEpochDay();
    const day_secs = epoch_secs.getDaySeconds();
    const ymd = epoch_day.calculateYearDay();
    const month_day = ymd.calculateMonthDay();
    const year: u32 = ymd.year;
    const month: u8 = month_day.month.numeric();
    const day: u8 = month_day.day_index + 1;
    const hour: u8 = day_secs.getHoursIntoDay();
    const minute: u8 = day_secs.getMinutesIntoHour();
    const second: u8 = day_secs.getSecondsIntoMinute();
    return std.fmt.allocPrint(
        allocator,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{ year, month, day, hour, minute, second },
    );
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure logic.  Full conformance lives in
// tests/intent_cells_store_fs_conformance.zig.
// ─────────────────────────────────────────────────────────────────────

fn testClock() i64 {
    return 1_700_000_000;
}

fn fixtureRecord() IntentCellRecord {
    return .{
        .cell_id = "cell-000010-deadbeef-12345678",
        .hat_id = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"[0..32],
        .cert_id = "deadbeefdeadbeefdeadbeefdeadbeef",
        .correlation_id = "00000000-0000-4000-8000-000000000001",
        .opcount = 1,
        .stack_depth = 0,
        .gas_used = 1,
        .kernel_ok = true,
        .phone_kernel_result_json =
        \\{"ok":true,"opcount":1,"stackDepth":0,"gasUsed":1,"errorKind":null}
        ,
        .opcode_bytes_b64 = "AA==",
        .intent_summary = "Find the wattle street job",
        .intent_action = "find",
        .intent_taxonomy_json =
        \\{"what":"jobs","how":"find","why":"navigate"}
        ,
        .received_at = "2026-05-07T14:36:00Z",
    };
}

test "IntentCellsStore: create → findById → list round-trip" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try IntentCellsStore.init(allocator, data_dir, testClock);
    defer store.deinit();

    const r = fixtureRecord();
    try std.testing.expectEqual(CreateResult.created, try store.create(r));
    try std.testing.expectEqual(@as(usize, 1), store.count());

    const got = store.findById(r.cell_id) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings(r.cell_id, got.cell_id);
    try std.testing.expectEqualStrings("find", got.intent_action);

    const all = try store.list(allocator, .{});
    defer allocator.free(all);
    try std.testing.expectEqual(@as(usize, 1), all.len);
    try std.testing.expectEqualStrings(r.cell_id, all[0].cell_id);
}

test "IntentCellsStore: idempotent re-create with same content" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try IntentCellsStore.init(allocator, data_dir, testClock);
    defer store.deinit();

    const r = fixtureRecord();
    try std.testing.expectEqual(CreateResult.created, try store.create(r));
    try std.testing.expectEqual(CreateResult.already_exists, try store.create(r));
    try std.testing.expectEqual(@as(usize, 1), store.count());
}

test "IntentCellsStore: cellId reuse with different content errors" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try IntentCellsStore.init(allocator, data_dir, testClock);
    defer store.deinit();

    var r = fixtureRecord();
    _ = try store.create(r);
    r.intent_summary = "Different summary";
    try std.testing.expectError(
        StoreError.cell_id_in_use_with_different_contents,
        store.create(r),
    );
    // First-write-wins: the original record is unchanged.
    const got = store.findById(r.cell_id) orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("Find the wattle street job", got.intent_summary);
}

test "IntentCellsStore: list filters on hat_id" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try IntentCellsStore.init(allocator, data_dir, testClock);
    defer store.deinit();

    var r1 = fixtureRecord();
    r1.cell_id = "cell-000010-deadbeef-aaaaaaa1";
    r1.hat_id = "hat-A";
    _ = try store.create(r1);

    var r2 = fixtureRecord();
    r2.cell_id = "cell-000010-deadbeef-aaaaaaa2";
    r2.hat_id = "hat-B";
    _ = try store.create(r2);

    const filtered = try store.list(allocator, .{ .hat_id = "hat-A" });
    defer allocator.free(filtered);
    try std.testing.expectEqual(@as(usize, 1), filtered.len);
    try std.testing.expectEqualStrings("hat-A", filtered[0].hat_id);
}

test "IntentCellsStore: list filters on since" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try IntentCellsStore.init(allocator, data_dir, testClock);
    defer store.deinit();

    var r1 = fixtureRecord();
    r1.cell_id = "cell-000010-deadbeef-zzzzzzz1";
    r1.received_at = "2026-01-01T00:00:00Z";
    _ = try store.create(r1);

    var r2 = fixtureRecord();
    r2.cell_id = "cell-000010-deadbeef-zzzzzzz2";
    r2.received_at = "2026-06-01T00:00:00Z";
    _ = try store.create(r2);

    const recent = try store.list(allocator, .{ .since = "2026-03-01T00:00:00Z" });
    defer allocator.free(recent);
    try std.testing.expectEqual(@as(usize, 1), recent.len);
    try std.testing.expectEqualStrings("2026-06-01T00:00:00Z", recent[0].received_at);
}

test "IntentCellsStore: list applies limit (tail-cut)" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    var store = try IntentCellsStore.init(allocator, data_dir, testClock);
    defer store.deinit();

    inline for (.{ "1", "2", "3" }) |suffix| {
        var r = fixtureRecord();
        r.cell_id = "cell-000010-deadbeef-aaaaaaa" ++ suffix;
        _ = try store.create(r);
    }
    const last_two = try store.list(allocator, .{ .limit = 2 });
    defer allocator.free(last_two);
    try std.testing.expectEqual(@as(usize, 2), last_two.len);
    try std.testing.expectEqualStrings("cell-000010-deadbeef-aaaaaaa2", last_two[0].cell_id);
    try std.testing.expectEqualStrings("cell-000010-deadbeef-aaaaaaa3", last_two[1].cell_id);
}

test "IntentCellsStore: replay rebuilds in-memory state" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = try tmp.dir.realpath(".", &path_buf);

    {
        var store = try IntentCellsStore.init(allocator, data_dir, testClock);
        defer store.deinit();
        _ = try store.create(fixtureRecord());
    }

    var store2 = try IntentCellsStore.init(allocator, data_dir, testClock);
    defer store2.deinit();
    try std.testing.expectEqual(@as(usize, 1), store2.count());
    const got = store2.findById("cell-000010-deadbeef-12345678") orelse return error.MissingRecord;
    try std.testing.expectEqualStrings("find", got.intent_action);
}

```
