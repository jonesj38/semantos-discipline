---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/llm_complete_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.172843+00:00
---

# runtime/semantos-brain/tests/llm_complete_conformance.zig

```zig
// Phase D-W1 / Phase 1 follow-up — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3
// (the `llm.complete` row, line 182), §8 Phase 1 follow-up.
//
// Conformance suite for `llm_complete_handler.zig`.  Exercises the
// dispatcher seam end-to-end (Dispatcher → ResourceHandler →
// HttpLlmAdapter) against the single spec'd command `complete` and
// asserts:
//
//   • Root scope can complete; the per-scope cap check is bypassed for
//     `in_process_root` (mirrors dispatcher's existing root-scope
//     short-circuit).
//   • A bearer with `cap.llm.complete:foo` can complete with
//     `scope=foo`, and is denied for `scope=bar` (capability_denied).
//   • Rate-limit kicks in: requests_per_hour + 1 returns
//     `rate_limit_exceeded`.
//   • Day-budget persists across handler instances (write to disk →
//     instantiate fresh handler → budget state restored).
//   • Audit-pair invariant — every dispatch produces a
//     `phase=start` / `phase=end` audit pair.
//   • Errors are typed: `rate_limit_exceeded`, `budget_exhausted`,
//     `backend_unavailable`, `prompt_too_long`.

const std = @import("std");
const dispatcher = @import("dispatcher");
const audit_log = @import("audit_log");
const llm = @import("llm_adapter");
const llm_http = @import("llm_http_adapter");
const handler_mod = @import("llm_complete_handler");

// ─────────────────────────────────────────────────────────────────────
// Fake-backend helpers (cribbed from llm_http_adapter_conformance.zig)
// ─────────────────────────────────────────────────────────────────────

fn startFakeServer(
    response_status: u16,
    response_body: []const u8,
    url_buf: *[64]u8,
    listener_out: *std.net.Server,
    url_out: *[]const u8,
) !std.Thread {
    const addr = try std.net.Address.parseIp4("127.0.0.1", 0);
    listener_out.* = try addr.listen(.{ .reuse_address = true });
    const port = listener_out.*.listen_address.in.getPort();
    url_out.* = try std.fmt.bufPrint(url_buf, "http://127.0.0.1:{d}/v1", .{port});
    return std.Thread.spawn(.{}, serveOne, .{ listener_out, response_status, response_body });
}

fn serveOne(listener: *std.net.Server, status: u16, body: []const u8) void {
    const conn = listener.accept() catch return;
    defer conn.stream.close();

    var req_buf: [16 * 1024]u8 = undefined;
    var total: usize = 0;
    while (total < req_buf.len) {
        const n = conn.stream.read(req_buf[total..]) catch return;
        if (n == 0) break;
        total += n;
        if (std.mem.indexOf(u8, req_buf[0..total], "\r\n\r\n")) |hdr_end| {
            const headers = req_buf[0..hdr_end];
            if (findContentLength(headers)) |cl| {
                while (total - (hdr_end + 4) < cl and total < req_buf.len) {
                    const n2 = conn.stream.read(req_buf[total..]) catch return;
                    if (n2 == 0) break;
                    total += n2;
                }
            }
            break;
        }
    }

    var resp: [4096]u8 = undefined;
    const r = std.fmt.bufPrint(
        &resp,
        "HTTP/1.1 {d} OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}",
        .{ status, body.len, body },
    ) catch return;
    conn.stream.writeAll(r) catch return;
}

fn findContentLength(headers: []const u8) ?usize {
    var it = std.mem.splitSequence(u8, headers, "\r\n");
    while (it.next()) |line| {
        if (std.ascii.startsWithIgnoreCase(line, "content-length:")) {
            const v = std.mem.trim(u8, line["content-length:".len..], " \t");
            return std.fmt.parseInt(usize, v, 10) catch null;
        }
    }
    return null;
}

// ─────────────────────────────────────────────────────────────────────
// Test fixture
// ─────────────────────────────────────────────────────────────────────

fn pinnedClock() i64 {
    return 1_700_000_000;
}

const Fixture = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,
    data_dir: []u8,
    audit_path: []u8,
    audit: audit_log.AuditLog,
    cfg_endpoint: []u8,
    adapter: llm_http.HttpLlmAdapter,
    handler: handler_mod.Handler,
    disp: dispatcher.Dispatcher,

    fn init(
        allocator: std.mem.Allocator,
        endpoint: []const u8,
        backend: llm.Backend,
    ) !*Fixture {
        const self = try allocator.create(Fixture);
        errdefer allocator.destroy(self);
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const real = try tmp.dir.realpath(".", &path_buf);
        const data_dir = try allocator.dupe(u8, real);
        errdefer allocator.free(data_dir);
        const audit_path = try std.fs.path.join(allocator, &.{ real, "audit.log" });
        errdefer allocator.free(audit_path);
        const cfg_endpoint = try allocator.dupe(u8, endpoint);
        errdefer allocator.free(cfg_endpoint);

        self.* = .{
            .allocator = allocator,
            .tmp_dir = tmp,
            .data_dir = data_dir,
            .audit_path = audit_path,
            .audit = audit_log.AuditLog.init(),
            .cfg_endpoint = cfg_endpoint,
            .adapter = undefined,
            .handler = undefined,
            .disp = undefined,
        };
        try self.audit.open(audit_path);

        // Build a default-on config pointing at the fake.  api_key_env
        // is unset for `local` backend (no auth header).  For
        // openai/anthropic we point at a known env-var name.
        const cfg = llm.LlmConfig{
            .enabled = true,
            .backend = backend,
            .endpoint = cfg_endpoint,
            .model = "test-model",
            .api_key_env = "",
        };
        self.adapter = llm_http.HttpLlmAdapter.init(allocator, cfg);
        self.handler = try handler_mod.Handler.init(allocator, &self.adapter, data_dir, pinnedClock);
        self.disp = dispatcher.Dispatcher.init(allocator, &self.audit);
        try self.disp.register(self.handler.resourceHandler());
        return self;
    }

    fn deinit(self: *Fixture) void {
        self.disp.deinit();
        self.handler.deinit();
        // Adapter's cfg.endpoint was supplied by us via cfg_endpoint;
        // we own that allocation directly.  We do NOT call
        // cfg.deinit() because that would attempt to free the static
        // "test-model" / "" defaults via allocator.free (UB).
        self.audit.close();
        self.tmp_dir.cleanup();
        self.allocator.free(self.cfg_endpoint);
        self.allocator.free(self.audit_path);
        self.allocator.free(self.data_dir);
        self.allocator.destroy(self);
    }

    fn dumpAudit(self: *Fixture) ![]u8 {
        const f = try std.fs.cwd().openFile(self.audit_path, .{});
        defer f.close();
        const stat = try f.stat();
        const buf = try self.allocator.alloc(u8, stat.size);
        errdefer self.allocator.free(buf);
        const n = try f.readAll(buf);
        return buf[0..n];
    }
};

fn rootCtx() dispatcher.DispatchContext {
    return .{
        .auth = .in_process_root,
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{ .request_id = "test", .transport_label = "test" },
    };
}

fn bearerCtxWithCaps(caps: []const []const u8) dispatcher.DispatchContext {
    return .{
        .auth = .{ .bearer = .{ .fingerprint_hex = [_]u8{'0'} ** 64, .label = "test" } },
        .capabilities = dispatcher.CapabilitySet.fromList(caps),
        .meta = .{ .request_id = "test-bearer", .transport_label = "test" },
    };
}

fn jsonString(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.not_object;
    const v = parsed.value.object.get(key) orelse return error.missing_key;
    if (v != .string) return error.not_string;
    return try allocator.dupe(u8, v.string);
}

// Body the local-backend fake server responds with.  Encodes a `content`
// string and a `tokens_predicted` count that drives the day-budget.
fn localBackendBody(text: []const u8, tokens: u32) []const u8 {
    _ = text;
    _ = tokens;
    // Static body (the fake server doesn't echo our request); we
    // return a single canned JSON every time.
    return
        \\{"content":"hello world","tokens_predicted":42,"model":"test-model"}
    ;
}

// ─────────────────────────────────────────────────────────────────────
// Happy path — root scope completes against the fake backend
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup llm.complete: root scope completes against fake local backend" {
    const allocator = std.testing.allocator;

    var url_buf: [64]u8 = undefined;
    var listener: std.net.Server = undefined;
    var url: []const u8 = undefined;
    const t = try startFakeServer(
        200,
        \\{"content":"hello world","tokens_predicted":42,"model":"test-model"}
    , &url_buf, &listener, &url);
    defer t.join();
    defer listener.deinit();

    var fx = try Fixture.init(allocator, url, .local);
    defer fx.deinit();

    var ctx = rootCtx();
    var result = try fx.disp.dispatch(&ctx, "llm", "complete",
        \\{"prompt":"say hi","scope":"oddjobz-internal"}
    );
    defer result.deinit();

    const text = try jsonString(allocator, result.payload, "text");
    defer allocator.free(text);
    try std.testing.expectEqualStrings("hello world", text);
}

// ─────────────────────────────────────────────────────────────────────
// Bearer scope match — has cap.llm.complete:foo, calls with scope=foo
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup llm.complete: bearer with cap.llm.complete:foo can complete scope=foo" {
    const allocator = std.testing.allocator;

    var url_buf: [64]u8 = undefined;
    var listener: std.net.Server = undefined;
    var url: []const u8 = undefined;
    const t = try startFakeServer(
        200,
        \\{"content":"hello","tokens_predicted":1,"model":"m"}
    , &url_buf, &listener, &url);
    defer t.join();
    defer listener.deinit();

    var fx = try Fixture.init(allocator, url, .local);
    defer fx.deinit();

    const caps = [_][]const u8{"cap.llm.complete:foo"};
    var ctx = bearerCtxWithCaps(&caps);
    var result = try fx.disp.dispatch(&ctx, "llm", "complete",
        \\{"prompt":"hi","scope":"foo"}
    );
    defer result.deinit();
    const text = try jsonString(allocator, result.payload, "text");
    defer allocator.free(text);
    try std.testing.expectEqualStrings("hello", text);
}

// ─────────────────────────────────────────────────────────────────────
// Bearer scope mismatch — has :foo, calls with scope=bar → denied
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup llm.complete: bearer with cap.llm.complete:foo is denied for scope=bar" {
    const allocator = std.testing.allocator;

    var fx = try Fixture.init(allocator, "http://127.0.0.1:1/never-called", .local);
    defer fx.deinit();

    const caps = [_][]const u8{"cap.llm.complete:foo"};
    var ctx = bearerCtxWithCaps(&caps);
    const err = fx.disp.dispatch(&ctx, "llm", "complete",
        \\{"prompt":"hi","scope":"bar"}
    );
    try std.testing.expectError(dispatcher.DispatchError.capability_denied, err);
}

// ─────────────────────────────────────────────────────────────────────
// Rate-limit gate — over the request bucket within the rolling hour
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup llm.complete: 101st request in an hour returns rate_limit_exceeded" {
    const allocator = std.testing.allocator;

    // We don't care about HTTP at all here — the rate-limit gate fires
    // BEFORE the upstream call.  Pre-populate budget state so we land
    // exactly at the cap, then assert the next dispatch fails.
    var fx = try Fixture.init(allocator, "http://127.0.0.1:1/unused", .local);
    defer fx.deinit();

    fx.handler.setRequestsPerHour(2);

    // Two pre-populated requests to fill the bucket.  We reach into
    // the handler's map directly — same allocator, same lifetime
    // ownership.
    const scope_name = "oddjobz-internal";
    fx.handler.mu.lock();
    {
        defer fx.handler.mu.unlock();
        const sb = try fx.handler.getOrCreateScope(scope_name);
        try sb.request_history.append(allocator, pinnedClock() - 60);
        try sb.request_history.append(allocator, pinnedClock() - 30);
    }

    var ctx = rootCtx();
    const err = fx.disp.dispatch(&ctx, "llm", "complete",
        \\{"prompt":"hi","scope":"oddjobz-internal"}
    );
    try std.testing.expectError(handler_mod.HandlerError.rate_limit_exceeded, err);
}

// ─────────────────────────────────────────────────────────────────────
// Budget gate — over the day-token budget
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup llm.complete: scope at day-budget cap returns budget_exhausted" {
    const allocator = std.testing.allocator;

    var fx = try Fixture.init(allocator, "http://127.0.0.1:1/unused", .local);
    defer fx.deinit();

    fx.handler.setTokensPerDay(50);

    fx.handler.mu.lock();
    {
        defer fx.handler.mu.unlock();
        const sb = try fx.handler.getOrCreateScope("oddjobz-internal");
        sb.tokens_today = 50;
        sb.tokens_today_day = @divFloor(pinnedClock(), 86400);
    }

    var ctx = rootCtx();
    const err = fx.disp.dispatch(&ctx, "llm", "complete",
        \\{"prompt":"hi","scope":"oddjobz-internal"}
    );
    try std.testing.expectError(handler_mod.HandlerError.budget_exhausted, err);
}

// ─────────────────────────────────────────────────────────────────────
// Persistence — write to disk → fresh handler → budget state restored
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup llm.complete: budget state persists across handler instances" {
    const allocator = std.testing.allocator;

    var url_buf: [64]u8 = undefined;
    var listener: std.net.Server = undefined;
    var url: []const u8 = undefined;
    const t = try startFakeServer(
        200,
        \\{"content":"x","tokens_predicted":42,"model":"m"}
    , &url_buf, &listener, &url);
    defer t.join();
    defer listener.deinit();

    // First handler: do one dispatch.  Adapter's complete() will hit
    // the fake server and bump tokens_today by 42.  Then deinit
    // (drops the in-memory map).
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = try tmp.dir.realpath(".", &path_buf);
    const data_dir = try allocator.dupe(u8, real);
    defer allocator.free(data_dir);

    const cfg = llm.LlmConfig{
        .enabled = true,
        .backend = .local,
        .endpoint = url,
        .model = "test-model",
        .api_key_env = "",
    };
    var adapter = llm_http.HttpLlmAdapter.init(allocator, cfg);

    {
        var h1 = try handler_mod.Handler.init(allocator, &adapter, data_dir, pinnedClock);
        defer h1.deinit();

        var audit = audit_log.AuditLog.init();
        const audit_path = try std.fs.path.join(allocator, &.{ data_dir, "audit.log" });
        defer allocator.free(audit_path);
        try audit.open(audit_path);
        defer audit.close();

        var disp = dispatcher.Dispatcher.init(allocator, &audit);
        defer disp.deinit();
        try disp.register(h1.resourceHandler());

        var ctx = rootCtx();
        var result = try disp.dispatch(&ctx, "llm", "complete",
            \\{"prompt":"persist-me","scope":"oddjobz-internal"}
        );
        defer result.deinit();
    }

    // Second handler against the SAME data_dir — should load the
    // budget state from `<data_dir>/llm-budgets.json`.
    var h2 = try handler_mod.Handler.init(allocator, &adapter, data_dir, pinnedClock);
    defer h2.deinit();

    h2.mu.lock();
    defer h2.mu.unlock();
    const sb = h2.getOrCreateScope("oddjobz-internal") catch unreachable;
    try std.testing.expectEqual(@as(u32, 42), sb.tokens_today);
    try std.testing.expectEqual(@as(usize, 1), sb.request_history.items.len);
}

// ─────────────────────────────────────────────────────────────────────
// Backend unavailable — bad endpoint surfaces as backend_unavailable
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup llm.complete: unreachable backend surfaces as backend_unavailable" {
    const allocator = std.testing.allocator;

    // Port 1 — bind-refused on every Linux + macOS we test on, so
    // the fetch returns transport_error which the handler maps.
    var fx = try Fixture.init(allocator, "http://127.0.0.1:1/", .local);
    defer fx.deinit();

    var ctx = rootCtx();
    const err = fx.disp.dispatch(&ctx, "llm", "complete",
        \\{"prompt":"hi","scope":"oddjobz-internal"}
    );
    try std.testing.expectError(handler_mod.HandlerError.backend_unavailable, err);
}

// ─────────────────────────────────────────────────────────────────────
// Prompt too long — defensive cap before charging anything
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup llm.complete: combined prompt > 64 KiB returns prompt_too_long" {
    const allocator = std.testing.allocator;

    var fx = try Fixture.init(allocator, "http://127.0.0.1:1/unused", .local);
    defer fx.deinit();

    var prompt: std.ArrayList(u8) = .{};
    defer prompt.deinit(allocator);
    try prompt.appendSlice(allocator, "{\"prompt\":\"");
    try prompt.appendNTimes(allocator, 'a', handler_mod.MAX_COMBINED_PROMPT_LEN + 1);
    try prompt.appendSlice(allocator, "\",\"scope\":\"foo\"}");

    var ctx = rootCtx();
    const err = fx.disp.dispatch(&ctx, "llm", "complete", prompt.items);
    try std.testing.expectError(handler_mod.HandlerError.prompt_too_long, err);
}

// ─────────────────────────────────────────────────────────────────────
// Audit-pair invariant — every dispatch (success OR error) records two
// audit entries with phase=start + phase=end.
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup llm.complete: every dispatch records start + end audit pair" {
    const allocator = std.testing.allocator;

    var fx = try Fixture.init(allocator, "http://127.0.0.1:1/", .local);
    defer fx.deinit();

    var ctx = rootCtx();
    const err = fx.disp.dispatch(&ctx, "llm", "complete",
        \\{"prompt":"hi","scope":"foo"}
    );
    // backend_unavailable surfaces as a handler error; the dispatcher
    // still emits the start + end audit pair regardless.
    try std.testing.expectError(handler_mod.HandlerError.backend_unavailable, err);

    const audit_text = try fx.dumpAudit();
    defer allocator.free(audit_text);

    var start_count: usize = 0;
    var end_count: usize = 0;
    var line_it = std.mem.splitSequence(u8, audit_text, "\n");
    while (line_it.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.indexOf(u8, line, "phase=start") != null) start_count += 1;
        if (std.mem.indexOf(u8, line, "phase=end") != null) end_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), start_count);
    try std.testing.expectEqual(@as(usize, 1), end_count);
}

// ─────────────────────────────────────────────────────────────────────
// Per-scope isolation — two scopes track independent token budgets
// ─────────────────────────────────────────────────────────────────────

test "D-W1 P1.followup llm.complete: token budgets are per-scope, not global" {
    const allocator = std.testing.allocator;

    var fx = try Fixture.init(allocator, "http://127.0.0.1:1/unused", .local);
    defer fx.deinit();

    fx.handler.setTokensPerDay(50);

    // Scope A is at-budget; scope B is fresh.  Scope-B dispatch must
    // NOT be blocked by scope-A's exhaustion.  We don't care about
    // the upstream call — port 1 is closed, so we'll see
    // `backend_unavailable` for scope B (NOT `budget_exhausted`).
    fx.handler.mu.lock();
    {
        defer fx.handler.mu.unlock();
        const sb_a = try fx.handler.getOrCreateScope("scope-a");
        sb_a.tokens_today = 50;
        sb_a.tokens_today_day = @divFloor(pinnedClock(), 86400);
    }

    var ctx = rootCtx();

    const err_a = fx.disp.dispatch(&ctx, "llm", "complete",
        \\{"prompt":"hi","scope":"scope-a"}
    );
    try std.testing.expectError(handler_mod.HandlerError.budget_exhausted, err_a);

    const err_b = fx.disp.dispatch(&ctx, "llm", "complete",
        \\{"prompt":"hi","scope":"scope-b"}
    );
    try std.testing.expectError(handler_mod.HandlerError.backend_unavailable, err_b);
}

```
