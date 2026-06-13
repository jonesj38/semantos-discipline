---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/oddjobz_attention_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.545607+00:00
---

# cartridges/oddjobz/brain/zig/src/oddjobz_attention_handler.zig

```zig
// Tier 2P Phase B — oddjobz attention RPC verbs.
//
// Reference: docs/prd/TIER-2P-PASK-ATTENTION-MOBILE.md §4 Phase B;
//            runtime/legacy-ingest/src/conversation/turn-patch-store.ts
//              (OddjobzMessagePatch schema);
//            runtime/legacy-ingest/src/conversation/dispatch-router.ts
//              (ConversationDispatchDecision schema);
//            runtime/semantos-brain/src/oddjobz_query_handler.zig — coding style
//              mirrored here (JSON builder helpers, error surface).
//
// What this exists for:
//
//   Codex commit 0e18eb3 writes two JSONL files under
//   `<data_dir>/oddjobz/`:
//
//     messages.jsonl           — one OddjobzMessagePatch per line.
//     dispatch-decisions.jsonl — one ConversationDispatchDecision per line.
//
//   Helm reads these directly in-process (TS).  Mobile cannot.  This
//   handler exposes the same data over WSS JSON-RPC so the mobile
//   Flutter client (Phase D) can consume it.
//
// Verbs:
//
//   • oddjobz.list_messages
//       params: { since?, limit?, providerId?, sessionId? }
//       result: array of message patches, descending timestamp order.
//
//   • oddjobz.list_dispatch_decisions
//       params: { since?, limit?, lane?, requiresRatification?,
//                 primaryTargetType?, primaryTargetRef? }
//       result: array of dispatch decisions, descending timestamp order.
//
//   • oddjobz.poll_attention_signals
//       params: { limit? }
//       result: union of { kind, score, ref, summary, expiresAt?, raw }
//               items drawn from the three sources.
//
// Memory: all parsing uses the caller-supplied arena allocator;
//   everything is freed at end of request.
//
// Path resolution: `<data_dir>/oddjobz/messages.jsonl` and
//   `<data_dir>/oddjobz/dispatch-decisions.jsonl`.  `data_dir` is the
//   value from the Semantos Brain config (default `~/.semantos/data`).  Callers
//   pass it as a `data_dir` slice — same convention as the other FS
//   stores in this directory.
//
// NOTE: for very large JSONL files (>50 k lines) a forward-from-tail
//   optimisation should be added (seek to EOF − N×max_line_bytes,
//   then scan forward for the next newline).  Flagged as a follow-up;
//   current 200-item limits are fine for v1 operator deployments.

const std = @import("std");
const jobs_store_fs = @import("jobs_store_fs");

pub const AttentionError = error{
    invalid_params,
    out_of_memory,
    io_error,
};

// ── Limits ────────────────────────────────────────────────────────────

const DEFAULT_LIMIT: usize = 100;
const MAX_LIMIT: usize = 1000;
const MAX_LINE_BYTES: usize = 16_384; // 16 KB per JSONL line

// ── Handler ───────────────────────────────────────────────────────────

pub const Handler = struct {
    /// Absolute path to `<data_dir>/oddjobz/messages.jsonl`.
    messages_path: []const u8,
    /// Absolute path to `<data_dir>/oddjobz/dispatch-decisions.jsonl`.
    dispatch_path: []const u8,
    /// Pointer to the live JobsStore for poll_attention_signals' open-
    /// job third.  Optional: when null the open-job bucket is skipped
    /// (degraded mode — still returns messages + dispatch signals).
    jobs: ?*jobs_store_fs.JobsStore,

    pub fn init(
        allocator: std.mem.Allocator,
        data_dir: []const u8,
        jobs_store: ?*jobs_store_fs.JobsStore,
    ) AttentionError!Handler {
        const oddjobz_dir = std.fs.path.join(allocator, &.{ data_dir, "oddjobz" }) catch
            return AttentionError.out_of_memory;
        defer allocator.free(oddjobz_dir);

        // Ensure directory exists (Codex may not have created it yet on
        // a fresh operator install that has never received a message).
        std.fs.cwd().makePath(oddjobz_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return AttentionError.io_error,
        };

        const messages_path = std.fs.path.join(allocator, &.{ oddjobz_dir, "messages.jsonl" }) catch
            return AttentionError.out_of_memory;
        errdefer allocator.free(messages_path);

        const dispatch_path = std.fs.path.join(
            allocator,
            &.{ oddjobz_dir, "dispatch-decisions.jsonl" },
        ) catch return AttentionError.out_of_memory;

        return .{
            .messages_path = messages_path,
            .dispatch_path = dispatch_path,
            .jobs = jobs_store,
        };
    }

    pub fn deinit(self: *Handler, allocator: std.mem.Allocator) void {
        allocator.free(self.messages_path);
        allocator.free(self.dispatch_path);
    }

    // ─── B.1 oddjobz.list_messages ─────────────────────────────────

    /// Parse params, read messages.jsonl, filter, sort desc by
    /// timestamp, encode as JSON array.  Caller owns returned slice.
    pub fn listMessages(
        self: *const Handler,
        allocator: std.mem.Allocator,
        params_json: []const u8,
    ) AttentionError![]u8 {
        const params = try parseListMessagesParams(allocator, params_json);
        defer params.deinit(allocator);

        var lines = try readAllLines(allocator, self.messages_path);
        defer {
            for (lines.items) |line| allocator.free(line);
            lines.deinit(allocator);
        }

        // Parse, filter, collect.
        var items: std.ArrayList(MessageItem) = .{};
        defer {
            for (items.items) |*it| it.deinit(allocator);
            items.deinit(allocator);
        }

        for (lines.items) |line| {
            const parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
            defer parsed.deinit();
            const obj = parsed.value;
            if (obj != .object) continue;

            const ts = intField(obj, "timestamp") orelse continue;
            if (params.since) |s| { if (ts < s) continue; }

            if (params.providerId) |pid| {
                const pv = obj.object.get("providerId") orelse continue;
                if (pv != .string) continue;
                if (!std.mem.eql(u8, pv.string, pid)) continue;
            }
            if (params.sessionId) |sid| {
                const sv = obj.object.get("sessionId") orelse continue;
                if (sv != .string) continue;
                if (!std.mem.eql(u8, sv.string, sid)) continue;
            }

            const raw = jsonStringify(allocator, obj) catch return AttentionError.out_of_memory;
            errdefer allocator.free(raw);
            const item = MessageItem{ .timestamp = ts, .raw_json = raw };
            items.append(allocator, item) catch return AttentionError.out_of_memory;
        }

        // Sort descending.
        sortDescByTimestamp(MessageItem, items.items);

        // Slice to limit.
        const limit = params.limit;
        const count = @min(items.items.len, limit);
        const slice = items.items[0..count];

        return encodeRawJsonArray(allocator, slice);
    }

    // ─── B.2 oddjobz.list_dispatch_decisions ───────────────────────

    pub fn listDispatchDecisions(
        self: *const Handler,
        allocator: std.mem.Allocator,
        params_json: []const u8,
    ) AttentionError![]u8 {
        const params = try parseListDispatchParams(allocator, params_json);
        defer params.deinit(allocator);

        var lines = try readAllLines(allocator, self.dispatch_path);
        defer {
            for (lines.items) |line| allocator.free(line);
            lines.deinit(allocator);
        }

        var items: std.ArrayList(MessageItem) = .{};
        defer {
            for (items.items) |*it| it.deinit(allocator);
            items.deinit(allocator);
        }

        for (lines.items) |line| {
            const parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
            defer parsed.deinit();
            const obj = parsed.value;
            if (obj != .object) continue;

            // dispatch decisions have no timestamp field in the schema —
            // use patchId order (file order) as surrogate; assign a
            // synthetic timestamp from `writtenAt` if present, else 0.
            const ts = intField(obj, "writtenAt") orelse intField(obj, "timestamp") orelse 0;

            if (params.since) |s| { if (ts < s) continue; }

            if (params.lane) |lane| {
                const lv = obj.object.get("lane") orelse continue;
                if (lv != .string) continue;
                if (!std.mem.eql(u8, lv.string, lane)) continue;
            }
            if (params.requiresRatification) |rr| {
                const rv = obj.object.get("requiresRatification") orelse continue;
                if (rv != .bool) continue;
                if (rv.bool != rr) continue;
            }
            if (params.primaryTargetType) |ptt| {
                const ptv = obj.object.get("primaryTarget") orelse continue;
                if (ptv != .object) continue;
                const tv = ptv.object.get("type") orelse continue;
                if (tv != .string) continue;
                if (!std.mem.eql(u8, tv.string, ptt)) continue;
            }
            if (params.primaryTargetRef) |ptr_val| {
                const ptv = obj.object.get("primaryTarget") orelse continue;
                if (ptv != .object) continue;
                const rv = ptv.object.get("ref") orelse continue;
                if (rv != .string) continue;
                if (!std.mem.eql(u8, rv.string, ptr_val)) continue;
            }

            const raw = jsonStringify(allocator, obj) catch return AttentionError.out_of_memory;
            errdefer allocator.free(raw);
            items.append(allocator, .{ .timestamp = ts, .raw_json = raw }) catch
                return AttentionError.out_of_memory;
        }

        sortDescByTimestamp(MessageItem, items.items);

        const limit = params.limit;
        const count = @min(items.items.len, limit);
        return encodeRawJsonArray(allocator, items.items[0..count]);
    }

    // ─── B.3 oddjobz.poll_attention_signals ────────────────────────

    pub fn pollAttentionSignals(
        self: *const Handler,
        allocator: std.mem.Allocator,
        params_json: []const u8,
    ) AttentionError![]u8 {
        const limit = try parsePollParams(allocator, params_json);
        const bucket = @max(limit / 3, 1);

        // ── Bucket 1: dispatch decisions where requiresRatification == true ──
        var dispatch_items = try self.collectDispatchForPoll(allocator, bucket, true);
        defer {
            for (dispatch_items.items) |*s| s.deinit(allocator);
            dispatch_items.deinit(allocator);
        }

        // ── Bucket 2: recent customer messages ──────────────────────────────
        var message_items = try self.collectMessagesForPoll(allocator, bucket);
        defer {
            for (message_items.items) |*s| s.deinit(allocator);
            message_items.deinit(allocator);
        }

        // ── Bucket 3: open jobs with near due dates ──────────────────────────
        var job_items = try self.collectJobsForPoll(allocator, bucket);
        defer {
            for (job_items.items) |*s| s.deinit(allocator);
            job_items.deinit(allocator);
        }

        // Combine and encode.
        var buf: std.ArrayList(u8) = .{};
        errdefer buf.deinit(allocator);

        buf.appendSlice(allocator, "[") catch return AttentionError.out_of_memory;
        var first = true;

        inline for (.{ dispatch_items.items, message_items.items, job_items.items }) |bucket_slice| {
            for (bucket_slice) |*signal| {
                if (!first) buf.append(allocator, ',') catch return AttentionError.out_of_memory;
                first = false;
                buf.appendSlice(allocator, signal.json) catch return AttentionError.out_of_memory;
            }
        }

        buf.append(allocator, ']') catch return AttentionError.out_of_memory;
        return buf.toOwnedSlice(allocator) catch AttentionError.out_of_memory;
    }

    // ── C4 PR-J4 — per-bucket signal producers for the attention-source registry ──
    //
    // Each emits a JSON ARRAY "[…]" of one bucket's scored signals, reusing the
    // same collect* helpers + SignalItem.json the in-handler poll uses. The
    // brain's generic attention.poll registers these as namespace-scoped sources
    // and merges across the in-scope set. pollAttentionSignals (above) is
    // unchanged — it stays the oddjobz-scope poll for back-compat.

    pub fn collectDispatchSignalsJson(self: *const Handler, allocator: std.mem.Allocator, limit: usize) AttentionError![]u8 {
        var items = try self.collectDispatchForPoll(allocator, limit, true);
        defer {
            for (items.items) |*s| s.deinit(allocator);
            items.deinit(allocator);
        }
        return signalItemsToArray(allocator, items.items);
    }

    pub fn collectMessageSignalsJson(self: *const Handler, allocator: std.mem.Allocator, limit: usize) AttentionError![]u8 {
        var items = try self.collectMessagesForPoll(allocator, limit);
        defer {
            for (items.items) |*s| s.deinit(allocator);
            items.deinit(allocator);
        }
        return signalItemsToArray(allocator, items.items);
    }

    pub fn collectJobSignalsJson(self: *const Handler, allocator: std.mem.Allocator, limit: usize) AttentionError![]u8 {
        var items = try self.collectJobsForPoll(allocator, limit);
        defer {
            for (items.items) |*s| s.deinit(allocator);
            items.deinit(allocator);
        }
        return signalItemsToArray(allocator, items.items);
    }

    // ── Poll helpers ──────────────────────────────────────────────────

    fn collectDispatchForPoll(
        self: *const Handler,
        allocator: std.mem.Allocator,
        bucket: usize,
        requires_ratification: bool,
    ) AttentionError!std.ArrayList(SignalItem) {
        var lines = try readAllLines(allocator, self.dispatch_path);
        defer {
            for (lines.items) |line| allocator.free(line);
            lines.deinit(allocator);
        }

        var raw_items: std.ArrayList(MessageItem) = .{};
        defer {
            for (raw_items.items) |*it| it.deinit(allocator);
            raw_items.deinit(allocator);
        }

        for (lines.items) |line| {
            const parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
            defer parsed.deinit();
            const obj = parsed.value;
            if (obj != .object) continue;

            const rv = obj.object.get("requiresRatification") orelse continue;
            if (rv != .bool or rv.bool != requires_ratification) continue;

            const ts = intField(obj, "writtenAt") orelse intField(obj, "timestamp") orelse 0;
            const raw = jsonStringify(allocator, obj) catch return AttentionError.out_of_memory;
            errdefer allocator.free(raw);
            raw_items.append(allocator, .{ .timestamp = ts, .raw_json = raw }) catch
                return AttentionError.out_of_memory;
        }

        sortDescByTimestamp(MessageItem, raw_items.items);

        var signals: std.ArrayList(SignalItem) = .{};
        errdefer {
            for (signals.items) |*s| s.deinit(allocator);
            signals.deinit(allocator);
        }

        const count = @min(raw_items.items.len, bucket);
        for (raw_items.items[0..count]) |item| {
            // score: 0.9 if requiresRatification, else 0.6 + 0.2*confidence
            const score: f64 = if (requires_ratification) 0.9 else blk: {
                // parse confidence from raw — re-parse the single item
                const p2 = std.json.parseFromSlice(std.json.Value, allocator, item.raw_json, .{}) catch break :blk 0.6;
                defer p2.deinit();
                const conf_v = p2.value.object.get("confidence") orelse break :blk 0.6;
                const conf: f64 = switch (conf_v) {
                    .float => conf_v.float,
                    .integer => @as(f64, @floatFromInt(conf_v.integer)),
                    else => break :blk 0.6,
                };
                break :blk 0.6 + 0.2 * conf;
            };

            // ref = sourcePatchId
            var ref_buf: [256]u8 = undefined;
            const ref = blk: {
                const p3 = std.json.parseFromSlice(std.json.Value, allocator, item.raw_json, .{}) catch break :blk "dispatch";
                defer p3.deinit();
                const v = p3.value.object.get("sourcePatchId") orelse break :blk "dispatch";
                if (v != .string or v.string.len == 0 or v.string.len >= ref_buf.len) break :blk "dispatch";
                @memcpy(ref_buf[0..v.string.len], v.string);
                break :blk ref_buf[0..v.string.len];
            };

            // summary = "Dispatch <lane>: <first 60 chars of text>"
            var summary_buf: [128]u8 = undefined;
            const summary = blk: {
                const p4 = std.json.parseFromSlice(std.json.Value, allocator, item.raw_json, .{}) catch break :blk "dispatch decision";
                defer p4.deinit();
                const lane_v = p4.value.object.get("lane") orelse break :blk "dispatch decision";
                const text_v = p4.value.object.get("text") orelse break :blk "dispatch decision";
                if (lane_v != .string or text_v != .string) break :blk "dispatch decision";
                const lane_s = lane_v.string;
                const text_s = text_v.string;
                const snippet_len = @min(text_s.len, 60);
                const s = std.fmt.bufPrint(
                    &summary_buf,
                    "Dispatch {s}: {s}",
                    .{ lane_s, text_s[0..snippet_len] },
                ) catch break :blk "dispatch decision";
                break :blk s;
            };

            const json = try buildSignalJson(allocator, "dispatch", score, ref, summary, null, item.raw_json);
            signals.append(allocator, .{ .json = json }) catch {
                allocator.free(json);
                return AttentionError.out_of_memory;
            };
        }

        return signals;
    }

    fn collectMessagesForPoll(
        self: *const Handler,
        allocator: std.mem.Allocator,
        bucket: usize,
    ) AttentionError!std.ArrayList(SignalItem) {
        var lines = try readAllLines(allocator, self.messages_path);
        defer {
            for (lines.items) |line| allocator.free(line);
            lines.deinit(allocator);
        }

        const now_ms = std.time.milliTimestamp();
        const one_day_ms: i64 = 24 * 60 * 60 * 1000;

        var raw_items: std.ArrayList(MessageItem) = .{};
        defer {
            for (raw_items.items) |*it| it.deinit(allocator);
            raw_items.deinit(allocator);
        }

        for (lines.items) |line| {
            const parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
            defer parsed.deinit();
            const obj = parsed.value;
            if (obj != .object) continue;

            // Only customer messages.
            const role_v = obj.object.get("role") orelse continue;
            if (role_v != .string) continue;
            if (!std.mem.eql(u8, role_v.string, "customer")) continue;

            const ts = intField(obj, "timestamp") orelse continue;
            const raw = jsonStringify(allocator, obj) catch return AttentionError.out_of_memory;
            errdefer allocator.free(raw);
            raw_items.append(allocator, .{ .timestamp = ts, .raw_json = raw }) catch
                return AttentionError.out_of_memory;
        }

        sortDescByTimestamp(MessageItem, raw_items.items);

        var signals: std.ArrayList(SignalItem) = .{};
        errdefer {
            for (signals.items) |*s| s.deinit(allocator);
            signals.deinit(allocator);
        }

        const count = @min(raw_items.items.len, bucket);
        for (raw_items.items[0..count]) |item| {
            // score: 0.62 if within last 24h, else 0.3
            const score: f64 = if (now_ms - item.timestamp <= one_day_ms) 0.62 else 0.3;

            // ref = patchId
            var ref_buf: [256]u8 = undefined;
            const ref = blk: {
                const p2 = std.json.parseFromSlice(std.json.Value, allocator, item.raw_json, .{}) catch break :blk "message";
                defer p2.deinit();
                const v = p2.value.object.get("patchId") orelse break :blk "message";
                if (v != .string or v.string.len == 0 or v.string.len >= ref_buf.len) break :blk "message";
                @memcpy(ref_buf[0..v.string.len], v.string);
                break :blk ref_buf[0..v.string.len];
            };

            // summary = first 80 chars of text
            var summary_buf: [96]u8 = undefined;
            const summary = blk: {
                const p3 = std.json.parseFromSlice(std.json.Value, allocator, item.raw_json, .{}) catch break :blk "customer message";
                defer p3.deinit();
                const tv = p3.value.object.get("text") orelse break :blk "customer message";
                if (tv != .string) break :blk "customer message";
                const snippet_len = @min(tv.string.len, 80);
                const s = std.fmt.bufPrint(&summary_buf, "{s}", .{tv.string[0..snippet_len]}) catch break :blk "customer message";
                break :blk s;
            };

            const json = try buildSignalJson(allocator, "message", score, ref, summary, null, item.raw_json);
            signals.append(allocator, .{ .json = json }) catch {
                allocator.free(json);
                return AttentionError.out_of_memory;
            };
        }

        return signals;
    }

    fn collectJobsForPoll(
        self: *const Handler,
        allocator: std.mem.Allocator,
        bucket: usize,
    ) AttentionError!std.ArrayList(SignalItem) {
        var signals: std.ArrayList(SignalItem) = .{};
        errdefer {
            for (signals.items) |*s| s.deinit(allocator);
            signals.deinit(allocator);
        }

        const js = self.jobs orelse return signals;

        // today as YYYY-MM-DD in a small fixed buffer
        var today_buf: [11]u8 = undefined;
        const today = epochTodayStr(&today_buf);

        // Collect open jobs with a dueDate.
        const all_jobs = js.listAll(allocator) catch return AttentionError.out_of_memory;
        defer allocator.free(all_jobs);

        const JobCandidate = struct {
            due: []const u8, // borrowed from job row
            score: f64,
            job: jobs_store_fs.Job,
        };

        var candidates: std.ArrayList(JobCandidate) = .{};
        defer candidates.deinit(allocator);

        for (all_jobs) |job| {
            // Only open (non-terminal) states.
            if (isTerminalState(job.state)) continue;
            const due = job.dueDate orelse continue;
            if (due.len < 10) continue; // not a valid YYYY-MM-DD

            const days = daysDiff(today, due[0..10]);
            const score: f64 = if (days == 0) 0.8 else if (days == 1) 0.6 else if (days <= 7) 0.4 else 0.2;

            candidates.append(allocator, .{ .due = due, .score = score, .job = job }) catch
                return AttentionError.out_of_memory;
        }

        // Sort by dueDate ascending (soonest first).
        std.mem.sort(JobCandidate, candidates.items, {}, struct {
            fn lt(_: void, a: JobCandidate, b: JobCandidate) bool {
                return std.mem.order(u8, a.due, b.due) == .lt;
            }
        }.lt);

        const count = @min(candidates.items.len, bucket);
        for (candidates.items[0..count]) |cand| {
            // ref = job.id
            const ref = cand.job.id;

            // summary = "Job <id>: <customer_name> due <due>"
            var summary_buf: [160]u8 = undefined;
            const summary = std.fmt.bufPrint(
                &summary_buf,
                "Job {s}: {s} due {s}",
                .{ cand.job.id, cand.job.customer_name, cand.due },
            ) catch "open job";

            // raw = minimal job JSON
            const raw_json = try encodeJobRaw(allocator, cand.job);
            defer allocator.free(raw_json);

            const json = try buildSignalJson(allocator, "job", cand.score, ref, summary, null, raw_json);
            signals.append(allocator, .{ .json = json }) catch {
                allocator.free(json);
                return AttentionError.out_of_memory;
            };
        }

        return signals;
    }
};

// ── Intermediate items ─────────────────────────────────────────────────

const MessageItem = struct {
    timestamp: i64,
    raw_json: []u8, // owned

    fn deinit(self: *MessageItem, allocator: std.mem.Allocator) void {
        allocator.free(self.raw_json);
    }
};

const SignalItem = struct {
    json: []u8, // owned

    fn deinit(self: *SignalItem, allocator: std.mem.Allocator) void {
        allocator.free(self.json);
    }
};

/// C4 PR-J4 — encode a bucket's signal items as a JSON array "[…]" (owned).
/// Used by the per-bucket producers that feed the attention-source registry.
fn signalItemsToArray(allocator: std.mem.Allocator, items: []const SignalItem) AttentionError![]u8 {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    buf.append(allocator, '[') catch return AttentionError.out_of_memory;
    var first = true;
    for (items) |s| {
        if (!first) buf.append(allocator, ',') catch return AttentionError.out_of_memory;
        first = false;
        buf.appendSlice(allocator, s.json) catch return AttentionError.out_of_memory;
    }
    buf.append(allocator, ']') catch return AttentionError.out_of_memory;
    return buf.toOwnedSlice(allocator) catch return AttentionError.out_of_memory;
}

// ── JSONL reader ────────────────────────────────────────────────────────
//
// Reads the file line-by-line.  Non-existent file → empty list (not an
// error — Codex may not have written any messages yet).

fn readAllLines(
    allocator: std.mem.Allocator,
    path: []const u8,
) AttentionError!std.ArrayList([]u8) {
    var list: std.ArrayList([]u8) = .{};
    errdefer {
        for (list.items) |line| allocator.free(line);
        list.deinit(allocator);
    }

    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return list,
        else => return AttentionError.io_error,
    };
    defer file.close();

    const max_bytes = 1024 * 1024 * 16; // 16 MiB cap
    const text = file.readToEndAlloc(allocator, max_bytes) catch return AttentionError.io_error;
    defer allocator.free(text);

    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |raw| {
        if (raw.len == 0) continue;
        const trimmed = std.mem.trimRight(u8, raw, " \r\t");
        if (trimmed.len == 0) continue;
        if (trimmed.len > MAX_LINE_BYTES) continue; // overlong — skip
        const owned = allocator.dupe(u8, trimmed) catch return AttentionError.out_of_memory;
        list.append(allocator, owned) catch {
            allocator.free(owned);
            return AttentionError.out_of_memory;
        };
    }

    return list;
}

// ── Param parsers ──────────────────────────────────────────────────────

const ListMessagesParams = struct {
    since: ?i64 = null,
    limit: usize = DEFAULT_LIMIT,
    providerId: ?[]const u8 = null,
    sessionId: ?[]const u8 = null,

    fn deinit(self: *const ListMessagesParams, allocator: std.mem.Allocator) void {
        if (self.providerId) |s| allocator.free(s);
        if (self.sessionId) |s| allocator.free(s);
    }
};

fn parseListMessagesParams(
    allocator: std.mem.Allocator,
    params_json: []const u8,
) AttentionError!ListMessagesParams {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, params_json, .{}) catch
        return AttentionError.invalid_params;
    defer parsed.deinit();

    if (parsed.value != .object) {
        // Allow null / empty params → defaults.
        if (parsed.value == .null) return .{};
        return AttentionError.invalid_params;
    }
    const obj = parsed.value;

    var p = ListMessagesParams{};
    p.since = intField(obj, "since");
    if (intField(obj, "limit")) |lv| {
        const l: usize = if (lv < 1) 1 else @intCast(@min(lv, @as(i64, @intCast(MAX_LIMIT))));
        p.limit = l;
    }
    // string filters: borrow from parsed value — they're copies below lifetime.
    if (obj.object.get("providerId")) |v| {
        if (v == .string and v.string.len > 0) {
            p.providerId = allocator.dupe(u8, v.string) catch return AttentionError.out_of_memory;
        }
    }
    if (obj.object.get("sessionId")) |v| {
        if (v == .string and v.string.len > 0) {
            p.sessionId = allocator.dupe(u8, v.string) catch return AttentionError.out_of_memory;
        }
    }
    return p;
}

const ListDispatchParams = struct {
    since: ?i64 = null,
    limit: usize = DEFAULT_LIMIT,
    lane: ?[]const u8 = null,
    requiresRatification: ?bool = null,
    primaryTargetType: ?[]const u8 = null,
    primaryTargetRef: ?[]const u8 = null,

    fn deinit(self: *const ListDispatchParams, allocator: std.mem.Allocator) void {
        if (self.lane) |s| allocator.free(s);
        if (self.primaryTargetType) |s| allocator.free(s);
        if (self.primaryTargetRef) |s| allocator.free(s);
    }
};

fn parseListDispatchParams(
    allocator: std.mem.Allocator,
    params_json: []const u8,
) AttentionError!ListDispatchParams {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, params_json, .{}) catch
        return AttentionError.invalid_params;
    defer parsed.deinit();

    if (parsed.value != .object) {
        if (parsed.value == .null) return .{};
        return AttentionError.invalid_params;
    }
    const obj = parsed.value;

    var p = ListDispatchParams{};
    p.since = intField(obj, "since");
    if (intField(obj, "limit")) |lv| {
        const l: usize = if (lv < 1) 1 else @intCast(@min(lv, @as(i64, @intCast(MAX_LIMIT))));
        p.limit = l;
    }
    if (obj.object.get("lane")) |v| {
        if (v == .string and v.string.len > 0) {
            p.lane = allocator.dupe(u8, v.string) catch return AttentionError.out_of_memory;
        }
    }
    if (obj.object.get("requiresRatification")) |v| {
        if (v == .bool) p.requiresRatification = v.bool;
    }
    if (obj.object.get("primaryTargetType")) |v| {
        if (v == .string and v.string.len > 0) {
            p.primaryTargetType = allocator.dupe(u8, v.string) catch return AttentionError.out_of_memory;
        }
    }
    if (obj.object.get("primaryTargetRef")) |v| {
        if (v == .string and v.string.len > 0) {
            p.primaryTargetRef = allocator.dupe(u8, v.string) catch return AttentionError.out_of_memory;
        }
    }
    return p;
}

fn parsePollParams(
    allocator: std.mem.Allocator,
    params_json: []const u8,
) AttentionError!usize {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, params_json, .{}) catch
        return 50;
    defer parsed.deinit();

    if (parsed.value != .object) return 50;
    const lv = intField(parsed.value, "limit") orelse return 50;
    if (lv < 1) return 1;
    if (lv > @as(i64, @intCast(MAX_LIMIT))) return MAX_LIMIT;
    return @intCast(lv);
}

// ── Sorting ────────────────────────────────────────────────────────────

fn sortDescByTimestamp(comptime T: type, items: []T) void {
    std.mem.sort(T, items, {}, struct {
        fn gt(_: void, a: T, b: T) bool {
            return a.timestamp > b.timestamp;
        }
    }.gt);
}

// ── JSON helpers ───────────────────────────────────────────────────────

fn intField(obj: std.json.Value, key: []const u8) ?i64 {
    const v = obj.object.get(key) orelse return null;
    return switch (v) {
        .integer => v.integer,
        .float => @intFromFloat(v.float),
        else => null,
    };
}

/// Stringify a `std.json.Value` back to JSON.  Caller owns result.
fn jsonStringify(allocator: std.mem.Allocator, v: std.json.Value) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, v, .{});
}

/// Encode a slice of MessageItem (which hold pre-serialised JSON) as a
/// JSON array.  Caller owns result.
fn encodeRawJsonArray(allocator: std.mem.Allocator, items: []const MessageItem) AttentionError![]u8 {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    buf.append(allocator, '[') catch return AttentionError.out_of_memory;
    for (items, 0..) |item, i| {
        if (i != 0) buf.append(allocator, ',') catch return AttentionError.out_of_memory;
        buf.appendSlice(allocator, item.raw_json) catch return AttentionError.out_of_memory;
    }
    buf.append(allocator, ']') catch return AttentionError.out_of_memory;
    return buf.toOwnedSlice(allocator) catch AttentionError.out_of_memory;
}

/// Build a single attention-signal JSON object.  Caller owns result.
fn buildSignalJson(
    allocator: std.mem.Allocator,
    kind: []const u8,
    score: f64,
    ref: []const u8,
    summary: []const u8,
    expires_at: ?i64,
    raw_json: []const u8,
) AttentionError![]u8 {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);

    // {"kind":"...","score":0.9,"ref":"...","summary":"...","raw":<raw>}
    buf.appendSlice(allocator, "{\"kind\":") catch return AttentionError.out_of_memory;
    writeJsonStringSlice(allocator, &buf, kind) catch return AttentionError.out_of_memory;
    buf.appendSlice(allocator, ",\"score\":") catch return AttentionError.out_of_memory;

    var score_buf: [32]u8 = undefined;
    // Format with 4 decimal places — sufficient precision for 0–1 range.
    const score_s = std.fmt.bufPrint(&score_buf, "{d:.4}", .{score}) catch "0.0000";
    buf.appendSlice(allocator, score_s) catch return AttentionError.out_of_memory;

    buf.appendSlice(allocator, ",\"ref\":") catch return AttentionError.out_of_memory;
    writeJsonStringSlice(allocator, &buf, ref) catch return AttentionError.out_of_memory;
    buf.appendSlice(allocator, ",\"summary\":") catch return AttentionError.out_of_memory;
    writeJsonStringSlice(allocator, &buf, summary) catch return AttentionError.out_of_memory;

    if (expires_at) |ea| {
        buf.appendSlice(allocator, ",\"expiresAt\":") catch return AttentionError.out_of_memory;
        var ea_buf: [24]u8 = undefined;
        const ea_s = std.fmt.bufPrint(&ea_buf, "{d}", .{ea}) catch "0";
        buf.appendSlice(allocator, ea_s) catch return AttentionError.out_of_memory;
    }

    buf.appendSlice(allocator, ",\"raw\":") catch return AttentionError.out_of_memory;
    buf.appendSlice(allocator, raw_json) catch return AttentionError.out_of_memory;
    buf.append(allocator, '}') catch return AttentionError.out_of_memory;

    return buf.toOwnedSlice(allocator) catch AttentionError.out_of_memory;
}

/// Write a JSON-encoded string (with escaping) to buf.
fn writeJsonStringSlice(
    allocator: std.mem.Allocator,
    buf: *std.ArrayList(u8),
    s: []const u8,
) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try buf.appendSlice(allocator, encoded);
}

// ── Job raw encoder (minimal) ──────────────────────────────────────────

fn encodeJobRaw(allocator: std.mem.Allocator, job: jobs_store_fs.Job) AttentionError![]u8 {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);

    const enc = struct {
        fn str(alloc: std.mem.Allocator, b: *std.ArrayList(u8), s: []const u8) !void {
            const encoded = try std.json.Stringify.valueAlloc(alloc, s, .{});
            defer alloc.free(encoded);
            try b.appendSlice(alloc, encoded);
        }
    };

    buf.appendSlice(allocator, "{\"id\":") catch return AttentionError.out_of_memory;
    enc.str(allocator, &buf, job.id) catch return AttentionError.out_of_memory;
    buf.appendSlice(allocator, ",\"customer_name\":") catch return AttentionError.out_of_memory;
    enc.str(allocator, &buf, job.customer_name) catch return AttentionError.out_of_memory;
    buf.appendSlice(allocator, ",\"state\":") catch return AttentionError.out_of_memory;
    enc.str(allocator, &buf, job.state) catch return AttentionError.out_of_memory;
    buf.appendSlice(allocator, ",\"dueDate\":") catch return AttentionError.out_of_memory;
    if (job.dueDate) |d| {
        enc.str(allocator, &buf, d) catch return AttentionError.out_of_memory;
    } else {
        buf.appendSlice(allocator, "null") catch return AttentionError.out_of_memory;
    }
    buf.append(allocator, '}') catch return AttentionError.out_of_memory;

    return buf.toOwnedSlice(allocator) catch AttentionError.out_of_memory;
}

// ── Date helpers ───────────────────────────────────────────────────────

/// Returns true for terminal Job FSM states (closed, paid).
fn isTerminalState(s: []const u8) bool {
    return std.mem.eql(u8, s, "closed") or
        std.mem.eql(u8, s, "paid") or
        std.mem.eql(u8, s, "completed") or
        std.mem.eql(u8, s, "invoiced");
}

/// Write today's date as "YYYY-MM-DD" into `buf[0..10]`.  Returns slice.
/// Uses the system clock.  Safe for use in per-request scoring (no caching
/// needed; the request latency is negligible against a 24-hour day).
fn epochTodayStr(buf: *[11]u8) []const u8 {
    const secs = std.time.timestamp();
    const days_since_epoch: i64 = @divFloor(secs, 86400);
    // Convert Unix days → Gregorian.  Equivalent of the proleptic
    // Gregorian calendar algorithm used widely in embedded systems.
    const z: i64 = days_since_epoch + 719468;
    const era: i64 = @divFloor(if (z >= 0) z else z - 146096, 146097);
    const doe: i64 = z - era * 146097; // day of era [0, 146096]
    const yoe: i64 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const y: i64 = yoe + era * 400;
    const doy: i64 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp: i64 = @divFloor(5 * doy + 2, 153);
    const d: i64 = doy - @divFloor(153 * mp + 2, 5) + 1;
    const m: i64 = if (mp < 10) mp + 3 else mp - 9;
    const yr: i64 = if (m <= 2) y + 1 else y;

    _ = std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}\x00", .{
        @as(u64, @intCast(yr)),
        @as(u64, @intCast(m)),
        @as(u64, @intCast(d)),
    }) catch {};
    return buf[0..10];
}

/// Returns `target - base` in calendar days using simple YYYY-MM-DD
/// string comparison arithmetic.  Returns 0 if target ≤ base.
/// Both strings MUST be "YYYY-MM-DD" (exactly 10 bytes).
fn daysDiff(base: []const u8, target: []const u8) i64 {
    if (base.len < 10 or target.len < 10) return 0;
    const order = std.mem.order(u8, target[0..10], base[0..10]);
    if (order != .gt) return 0;
    // Simple approximate: parse year/month/day and compute days.
    const by = parseInt(base[0..4]) orelse return 0;
    const bm = parseInt(base[5..7]) orelse return 0;
    const bd = parseInt(base[8..10]) orelse return 0;
    const ty = parseInt(target[0..4]) orelse return 0;
    const tm = parseInt(target[5..7]) orelse return 0;
    const td = parseInt(target[8..10]) orelse return 0;
    // Convert each to a Julian Day Number (approximate, good for ±400 yrs).
    const bj = julianDay(by, bm, bd);
    const tj = julianDay(ty, tm, td);
    if (tj <= bj) return 0;
    return tj - bj;
}

fn parseInt(s: []const u8) ?i64 {
    return std.fmt.parseInt(i64, s, 10) catch null;
}

fn julianDay(y: i64, m: i64, d: i64) i64 {
    // Algorithm from https://en.wikipedia.org/wiki/Julian_day#Converting_Gregorian_calendar_date_to_Julian_Day_Number
    const a = @divFloor(14 - m, 12);
    const yr = y + 4800 - a;
    const mo = m + 12 * a - 3;
    return d + @divFloor(153 * mo + 2, 5) + 365 * yr + @divFloor(yr, 4) - @divFloor(yr, 100) + @divFloor(yr, 400) - 32045;
}

```
