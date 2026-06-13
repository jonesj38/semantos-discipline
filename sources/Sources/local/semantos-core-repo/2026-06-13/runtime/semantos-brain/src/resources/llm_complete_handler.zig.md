---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/resources/llm_complete_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.293341+00:00
---

# runtime/semantos-brain/src/resources/llm_complete_handler.zig

```zig
// Phase D-W1 / Phase 1 follow-up — see docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3
// (the `llm.complete` row, line 182) and §8 Phase 1 follow-up.
//
// Dispatcher resource handler that fronts `llm_http_adapter.complete()`.
// Same architectural shape as bearer_tokens_handler.zig and
// identity_certs_handler.zig (Phase 1 Parts 1 + 2):
//
//   • One JSON-args / JSON-result entry point per command.
//   • Capability declared by command via `cap_for_cmd_fn`.
//   • Mutex-serialised under one Handler instance.
//
// One command lands here:
//
//   complete  — { prompt, system_prompt?, max_tokens?, temperature?,
//                  scope }                            →  { text, model,
//                                                           tokens_used }
//                cap = cap.llm.complete:<scope>
//
// The capability scheme is per-scope: a bearer with
// `cap.llm.complete:foo` may complete only with `scope=foo`; root-scope
// auth (in_process_root, local_uid) bypasses the per-scope check via
// the dispatcher's existing root-scope short-circuit.  This lets one
// operator partition completion-quota between an anonymous chat widget
// (`scope=anonymous-oddjobz`) and an internal operator-tool
// (`scope=oddjobz-internal`) without coupling them.
//
// ─── Per-scope rate-limit + budget shape ──────────────────────────────
//
// Two limiters per scope:
//
//   • Token-bucket on REQUEST count: 100 per rolling hour by default.
//     A request that would exceed the bucket returns
//     `rate_limit_exceeded` and is NOT charged against the day-token
//     budget.  Sliding-window-counter shape — counts per minute over
//     the last 60 minutes; cheap, no float math, plenty accurate for
//     the human-paced LLM-completion case.
//
//   • Token-budget on RESPONSE tokens: 100,000 per UTC day by default.
//     A request that would exceed the daily budget after the response
//     comes back is allowed to complete (we already charged the rate-
//     limit slot + made the HTTP call) but the NEXT request in that
//     scope is rejected with `budget_exhausted` until midnight UTC.
//     Calendar-day rollover; current-day count resets to zero on the
//     first request after the UTC-midnight boundary.
//
// Both limiters persist to `<data_dir>/llm-budgets.json` so budget
// state survives restart.  JSON shape:
//
//   {
//     "version": 1,
//     "scopes": {
//       "<scope-name>": {
//         "request_history": [<unix-second>, <unix-second>, ...],
//         "tokens_today": <int>,
//         "tokens_today_day": <int>,        // utc-day index
//         "lifetime_tokens": <int>          // informational
//       }
//     }
//   }
//
// `request_history` is pruned to the last hour at every dispatch so the
// file size stays bounded.  An OS write-failure on persist is swallowed
// — losing budget durability is preferable to losing a completion.
//
// ─── Anonymous caller path ────────────────────────────────────────────
//
// Per-site config's `anonymous_caps` list (see `site_config.zig` /
// `dispatcher.AuthContext.anonymous`) controls whether a visitor's
// chat-widget POST can hit `cap.llm.complete:<scope>`.  This handler
// makes no assumption either way — capability evaluation happens in
// the dispatcher's `dispatch()` against the scope-derived cap string;
// site config is the single seam that decides which scopes (if any) an
// anonymous caller may invoke.
//
// ─── Errors ───────────────────────────────────────────────────────────
//
//   rate_limit_exceeded  — over the request-bucket for this scope
//   budget_exhausted     — over the daily-token budget for this scope
//   backend_unavailable  — llm_http_adapter returned transport_error
//                          / rate_limited / config_error
//   prompt_too_long      — defensive cap on operator-supplied prompt
//                          length (combined with system_prompt)
//   invalid_args         — JSON parse / required fields missing
//   out_of_memory        — allocator failure on result encoding
//

const std = @import("std");
const dispatcher = @import("dispatcher");
const llm = @import("llm_adapter");
const llm_http = @import("llm_http_adapter");

pub const RESOURCE_NAME = "llm";

/// Default request-budget cap per scope.  Operator may override per-
/// scope at handler init time; persists across restarts via the
/// budgets file's `request_history` window.
pub const DEFAULT_REQUESTS_PER_HOUR: u32 = 100;

/// Default token-budget cap per scope per UTC day.
pub const DEFAULT_TOKENS_PER_DAY: u32 = 100_000;

/// Hard upper bound on (system_prompt.len + prompt.len) at the wire.
/// Catches operator-supplied runaway prompts before they hit the
/// backend.  64 KiB is well past any realistic prompt; the day-budget
/// will catch long-but-numerous prompts.
pub const MAX_COMBINED_PROMPT_LEN: usize = 64 * 1024;

pub const HandlerError = error{
    /// JSON args parse failed or required arg missing.
    invalid_args,
    /// Per-scope request bucket is full for the current sliding hour.
    rate_limit_exceeded,
    /// Per-scope day-token budget is exhausted; resets at next UTC
    /// midnight.
    budget_exhausted,
    /// Combined prompt + system_prompt exceeds MAX_COMBINED_PROMPT_LEN.
    prompt_too_long,
    /// llm_http_adapter could not reach the backend (transport error,
    /// upstream rate limit, missing config, missing api_key_env).
    backend_unavailable,
    /// Result-allocation failed.
    out_of_memory,
};

// ─────────────────────────────────────────────────────────────────────
// Per-scope budget state — kept in-memory; persisted on every mutation.
// ─────────────────────────────────────────────────────────────────────

const ScopeBudget = struct {
    /// Sliding-window history of request unix-seconds.  Pruned to the
    /// last hour at every dispatch.  ArrayList because the typical
    /// shape is "tens of entries" — well under ArrayList's amortised
    /// O(1) costs.
    request_history: std.ArrayList(i64),
    /// Token count consumed so far on the current UTC day.
    tokens_today: u32,
    /// UTC day index (unix_ts / 86400) the `tokens_today` count
    /// applies to.  Rolls over at midnight UTC.
    tokens_today_day: i64,
    /// Cumulative lifetime token count, for informational reporting.
    lifetime_tokens: u64,

    fn init() ScopeBudget {
        return .{
            .request_history = .{},
            .tokens_today = 0,
            .tokens_today_day = 0,
            .lifetime_tokens = 0,
        };
    }

    fn deinit(self: *ScopeBudget, allocator: std.mem.Allocator) void {
        self.request_history.deinit(allocator);
    }

    /// Drop entries older than `now - 3600`.  Linear in the dropped
    /// prefix; bounded by `requests_per_hour` since the bucket caps
    /// throughput.
    fn pruneOldRequests(self: *ScopeBudget, allocator: std.mem.Allocator, now: i64) void {
        const cutoff = now - 3600;
        var keep_from: usize = 0;
        for (self.request_history.items, 0..) |t, i| {
            if (t > cutoff) {
                keep_from = i;
                break;
            }
            keep_from = i + 1;
        }
        if (keep_from == 0) return;
        // Shift in place.
        const items = self.request_history.items;
        const n = items.len - keep_from;
        std.mem.copyForwards(i64, items[0..n], items[keep_from..]);
        self.request_history.shrinkRetainingCapacity(n);
        _ = allocator;
    }

    /// Roll over the day counter if we've crossed a UTC-midnight
    /// boundary since the last accounted token.
    fn maybeRollDay(self: *ScopeBudget, now: i64) void {
        const day = @divFloor(now, 86400);
        if (day != self.tokens_today_day) {
            self.tokens_today = 0;
            self.tokens_today_day = day;
        }
    }
};

/// Map from scope-name → ScopeBudget.  Owned-string keys; freed in
/// deinit.  StringHashMap is fine here — the working set is per-site
/// scopes (a handful, not thousands).
const BudgetMap = std.StringHashMap(ScopeBudget);

// ─────────────────────────────────────────────────────────────────────
// Handler
// ─────────────────────────────────────────────────────────────────────

pub const Handler = struct {
    allocator: std.mem.Allocator,
    /// Borrowed adapter — Handler does not own its lifetime.  Caller
    /// constructs the HttpLlmAdapter and keeps it alive across
    /// dispatches.
    adapter: *llm_http.HttpLlmAdapter,
    /// Persisted per-scope budget state.  Path is
    /// `<data_dir>/llm-budgets.json`.  `data_dir`-owned slice.
    budgets_path: []u8,
    /// Per-scope budget state.  Mutated under `mu`.  Owned-string
    /// keys; freed in deinit.
    budgets: BudgetMap,
    /// Per-scope caps; for v0.1 these are global defaults applied to
    /// every scope.  A future revision can plumb per-scope overrides
    /// through `data_dir`-supplied config (out of scope here).
    requests_per_hour: u32,
    tokens_per_day: u32,
    /// Pinned-clock for tests.
    clock: *const fn () i64,
    /// Serialises issue / list / status across transports.
    mu: std.Thread.Mutex,

    pub fn init(
        allocator: std.mem.Allocator,
        adapter: *llm_http.HttpLlmAdapter,
        data_dir: []const u8,
        clock_fn: *const fn () i64,
    ) !Handler {
        const budgets_path = try std.fs.path.join(allocator, &.{ data_dir, "llm-budgets.json" });
        errdefer allocator.free(budgets_path);
        // Best-effort: ensure data_dir exists (mirrors bearer_tokens
        // / identity_certs storage init).
        std.fs.cwd().makePath(data_dir) catch {};

        var self = Handler{
            .allocator = allocator,
            .adapter = adapter,
            .budgets_path = budgets_path,
            .budgets = BudgetMap.init(allocator),
            .requests_per_hour = DEFAULT_REQUESTS_PER_HOUR,
            .tokens_per_day = DEFAULT_TOKENS_PER_DAY,
            .clock = clock_fn,
            .mu = .{},
        };
        try self.loadBudgets();
        return self;
    }

    pub fn deinit(self: *Handler) void {
        var it = self.budgets.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.budgets.deinit();
        self.allocator.free(self.budgets_path);
    }

    pub fn resourceHandler(self: *Handler) dispatcher.ResourceHandler {
        return .{
            .name = RESOURCE_NAME,
            .state = self,
            .cap_for_cmd_fn = capForCmd,
            .handle_fn = handle,
        };
    }

    /// Override request-bucket cap (mainly for tests).
    pub fn setRequestsPerHour(self: *Handler, n: u32) void {
        self.requests_per_hour = n;
    }

    /// Override day-token-budget cap (mainly for tests).
    pub fn setTokensPerDay(self: *Handler, n: u32) void {
        self.tokens_per_day = n;
    }

    pub fn getOrCreateScope(self: *Handler, scope: []const u8) !*ScopeBudget {
        if (self.budgets.getPtr(scope)) |p| return p;
        const owned = try self.allocator.dupe(u8, scope);
        errdefer self.allocator.free(owned);
        const gop = try self.budgets.getOrPut(owned);
        if (gop.found_existing) {
            // Race-impossible under mu; defensive free.
            self.allocator.free(owned);
            return gop.value_ptr;
        }
        gop.value_ptr.* = ScopeBudget.init();
        return gop.value_ptr;
    }

    fn loadBudgets(self: *Handler) !void {
        return loadBudgetsImpl(self);
    }

    fn persistBudgets(self: *Handler) !void {
        return persistBudgetsImpl(self);
    }
};

// ─────────────────────────────────────────────────────────────────────
// Capability declarations
// ─────────────────────────────────────────────────────────────────────

fn capForCmd(state: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    _ = state;
    if (std.mem.eql(u8, cmd, "complete")) {
        // The required cap is `cap.llm.complete:<scope>` — but we
        // can't compute `<scope>` here (cap_for_cmd_fn doesn't see
        // the args).  Returning `.none` would skip the dispatcher's
        // outer cap check entirely; instead `handle` reads the
        // parsed scope and runs the per-scope match itself, then
        // returns `dispatcher.DispatchError.capability_denied` if
        // the caller's set doesn't contain the resolved cap.  Root-
        // scope auth (`in_process_root` / `local_uid`) bypasses both
        // checks via the dispatcher's existing root-scope short-
        // circuit and the matching guard in `handle`.
        return .none;
    }
    if (std.mem.eql(u8, cmd, "vision")) {
        // Same deferred per-scope cap pattern as `complete`.
        // Required cap at dispatch time: `cap.llm.vision:<scope>`.
        return .none;
    }
    return error.unknown_command;
}

// ─────────────────────────────────────────────────────────────────────
// Dispatch entry point
// ─────────────────────────────────────────────────────────────────────

fn handle(
    state: ?*anyopaque,
    ctx: *const dispatcher.DispatchContext,
    cmd: []const u8,
    args_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!dispatcher.Result {
    const self: *Handler = @ptrCast(@alignCast(state.?));
    self.mu.lock();
    defer self.mu.unlock();

    if (std.mem.eql(u8, cmd, "complete")) {
        return handleComplete(self, ctx, allocator, args_json);
    }
    if (std.mem.eql(u8, cmd, "vision")) {
        return handleVision(self, ctx, allocator, args_json);
    }
    return error.unknown_command;
}

fn handleComplete(
    self: *Handler,
    ctx: *const dispatcher.DispatchContext,
    allocator: std.mem.Allocator,
    args_json: []const u8,
) !dispatcher.Result {
    const args = parseCompleteArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer args.deinit(allocator);

    // Per-scope cap check — the dispatcher's outer cap-decl pass left
    // us a placeholder; we now resolve the real per-scope cap and
    // re-check against the caller's CapabilitySet.  Root-scope auth
    // already bypassed the outer check, so we mirror that here.
    if (!isRootScope(ctx.auth)) {
        var cap_buf: [256]u8 = undefined;
        const required = std.fmt.bufPrint(&cap_buf, "cap.llm.complete:{s}", .{args.scope}) catch
            return HandlerError.invalid_args;
        if (!ctx.capabilities.contains(required)) {
            return dispatcher.DispatchError.capability_denied;
        }
    }

    // Defensive prompt-length cap — backends will reject anyway, but
    // catching it here means a wedged operator-supplied prompt
    // doesn't burn rate-limit slots / token budget against a doomed
    // upstream call.
    if (args.prompt.len + args.system_prompt.len > MAX_COMBINED_PROMPT_LEN) {
        return HandlerError.prompt_too_long;
    }

    const now = self.clock();
    const scope = try self.getOrCreateScope(args.scope);
    scope.pruneOldRequests(self.allocator, now);
    scope.maybeRollDay(now);

    // Day-budget gate: an over-budget scope rejects BEFORE we consume
    // a request slot, so a paused operator can resume on the next UTC
    // day without losing slots in the meantime.
    if (scope.tokens_today >= self.tokens_per_day) {
        return HandlerError.budget_exhausted;
    }

    // Request-bucket gate.
    if (scope.request_history.items.len >= self.requests_per_hour) {
        return HandlerError.rate_limit_exceeded;
    }

    // Charge the request slot now (regardless of whether the upstream
    // call succeeds) so a hot backend cannot be DoSed via repeated
    // `transport_error` retries.
    try scope.request_history.append(self.allocator, now);

    // Persist budget state — best-effort (drop OS errors).  Done
    // BEFORE the upstream call so a crash mid-call still leaves the
    // request slot accounted for.
    self.persistBudgets() catch {};

    var resp = llm_http.complete(self.adapter, allocator, .{
        .prompt = args.prompt,
        .system_prompt = args.system_prompt,
        .max_tokens = args.max_tokens,
        .temperature = args.temperature,
    }) catch |err| switch (err) {
        llm.LlmError.config_error,
        llm.LlmError.transport_error,
        llm.LlmError.rate_limited,
        llm.LlmError.schema_violation,
        => return HandlerError.backend_unavailable,
        llm.LlmError.out_of_memory => return HandlerError.out_of_memory,
        llm.LlmError.not_enabled => return HandlerError.backend_unavailable,
    };
    defer llm_http.completionResponseDeinit(&resp, allocator);

    // Charge tokens against the day-budget.  We use a saturating add
    // so a backend that lies about a u32-overflow value can't wrap
    // the counter to zero (paranoia; real backends report at most a
    // few thousand).
    const bumped: u64 = @as(u64, scope.tokens_today) + @as(u64, resp.tokens_used);
    scope.tokens_today = if (bumped > std.math.maxInt(u32)) std.math.maxInt(u32) else @intCast(bumped);
    scope.lifetime_tokens +%= resp.tokens_used;
    self.persistBudgets() catch {};

    return ownedJsonResult(allocator, resp);
}

/// Mirror of `dispatcher.isRootScope` — we don't export it from
/// dispatcher.zig (it's a private helper there), so we duplicate the
/// shape locally.  Two-line function; trivially obvious.
fn isRootScope(auth: dispatcher.AuthContext) bool {
    return switch (auth) {
        .in_process_root, .local_uid => true,
        .bearer, .cert, .anonymous => false,
    };
}

// ─────────────────────────────────────────────────────────────────────
// `vision` command — image + optional text → text
//
// Same rate-limit + day-budget logic as `complete`; only the HTTP body
// shape differs (multipart content array with an image block).
// Response is decoded identically to `complete` (Anthropic returns the
// same messages shape regardless of whether the user turn had an image).
//
// Hard upper bound on image_b64 length: 8 MiB base64 ≈ 6 MiB raw.
// Anthropic's documented image limit is 5 MiB raw / ~6.7 MiB b64.
// We cap slightly above that so a just-under-limit JPEG doesn't hit an
// off-by-one; the API will reject anything actually over limit anyway.
// ─────────────────────────────────────────────────────────────────────

pub const MAX_IMAGE_B64_LEN: usize = 8 * 1024 * 1024; // 8 MiB

fn handleVision(
    self: *Handler,
    ctx: *const dispatcher.DispatchContext,
    allocator: std.mem.Allocator,
    args_json: []const u8,
) !dispatcher.Result {
    const args = parseVisionArgs(allocator, args_json) catch return HandlerError.invalid_args;
    defer args.deinit(allocator);

    // Per-scope cap check — mirrors handleComplete exactly.
    if (!isRootScope(ctx.auth)) {
        var cap_buf: [256]u8 = undefined;
        const required = std.fmt.bufPrint(&cap_buf, "cap.llm.vision:{s}", .{args.scope}) catch
            return HandlerError.invalid_args;
        if (!ctx.capabilities.contains(required)) {
            return dispatcher.DispatchError.capability_denied;
        }
    }

    // Prompt-length gate covers system_prompt + text prompt.
    if (args.prompt.len + args.system_prompt.len > MAX_COMBINED_PROMPT_LEN) {
        return HandlerError.prompt_too_long;
    }
    // Separate gate on image size.
    if (args.image_b64.len > MAX_IMAGE_B64_LEN) {
        return HandlerError.prompt_too_long;
    }

    const now = self.clock();
    const scope = try self.getOrCreateScope(args.scope);
    scope.pruneOldRequests(self.allocator, now);
    scope.maybeRollDay(now);

    if (scope.tokens_today >= self.tokens_per_day) {
        return HandlerError.budget_exhausted;
    }
    if (scope.request_history.items.len >= self.requests_per_hour) {
        return HandlerError.rate_limit_exceeded;
    }

    // Charge the request slot before the upstream call.
    try scope.request_history.append(self.allocator, now);
    self.persistBudgets() catch {};

    var resp = llm_http.vision(self.adapter, allocator, .{
        .image_b64 = args.image_b64,
        .media_type = args.media_type,
        .prompt = args.prompt,
        .system_prompt = args.system_prompt,
        .max_tokens = args.max_tokens,
        .temperature = args.temperature,
    }) catch |err| switch (err) {
        llm.LlmError.config_error,
        llm.LlmError.transport_error,
        llm.LlmError.rate_limited,
        llm.LlmError.schema_violation,
        => return HandlerError.backend_unavailable,
        llm.LlmError.out_of_memory => return HandlerError.out_of_memory,
        llm.LlmError.not_enabled => return HandlerError.backend_unavailable,
    };
    defer llm_http.completionResponseDeinit(&resp, allocator);

    const bumped: u64 = @as(u64, scope.tokens_today) + @as(u64, resp.tokens_used);
    scope.tokens_today = if (bumped > std.math.maxInt(u32)) std.math.maxInt(u32) else @intCast(bumped);
    scope.lifetime_tokens +%= resp.tokens_used;
    self.persistBudgets() catch {};

    return ownedJsonResult(allocator, resp);
}

// ─────────────────────────────────────────────────────────────────────
// Args parsing
// ─────────────────────────────────────────────────────────────────────

const CompleteArgs = struct {
    prompt: []u8,
    system_prompt: []u8,
    scope: []u8,
    max_tokens: u32,
    temperature: f32,

    fn deinit(self: CompleteArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.prompt);
        allocator.free(self.system_prompt);
        allocator.free(self.scope);
    }
};

fn parseCompleteArgs(allocator: std.mem.Allocator, args_json: []const u8) !CompleteArgs {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;

    const prompt_v = obj.get("prompt") orelse return error.invalid_args;
    if (prompt_v != .string) return error.invalid_args;
    const prompt = try allocator.dupe(u8, prompt_v.string);
    errdefer allocator.free(prompt);

    const system_prompt: []u8 = blk: {
        if (obj.get("system_prompt")) |v| {
            if (v == .string) break :blk try allocator.dupe(u8, v.string);
        }
        break :blk try allocator.dupe(u8, "");
    };
    errdefer allocator.free(system_prompt);

    const scope_v = obj.get("scope") orelse return error.invalid_args;
    if (scope_v != .string) return error.invalid_args;
    if (scope_v.string.len == 0) return error.invalid_args;
    // Validate scope name shape — same charset as a cap-name segment.
    for (scope_v.string) |c| {
        if (!isScopeChar(c)) return error.invalid_args;
    }
    const scope = try allocator.dupe(u8, scope_v.string);
    errdefer allocator.free(scope);

    var max_tokens: u32 = 0;
    if (obj.get("max_tokens")) |v| {
        if (v == .integer and v.integer >= 0 and v.integer <= std.math.maxInt(u32)) {
            max_tokens = @intCast(v.integer);
        }
    }
    var temperature: f32 = -1.0;
    if (obj.get("temperature")) |v| {
        switch (v) {
            .float => |f| temperature = @floatCast(f),
            .integer => |i| temperature = @floatFromInt(i),
            else => {},
        }
    }

    return .{
        .prompt = prompt,
        .system_prompt = system_prompt,
        .scope = scope,
        .max_tokens = max_tokens,
        .temperature = temperature,
    };
}

fn isScopeChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or
        (c >= 'A' and c <= 'Z') or
        (c >= '0' and c <= '9') or
        c == '-' or c == '_' or c == '.';
}

// ─────────────────────────────────────────────────────────────────────
// Vision args
// ─────────────────────────────────────────────────────────────────────

const VisionArgs = struct {
    /// Base64-encoded image bytes.
    image_b64: []u8,
    /// MIME type, e.g. "image/jpeg".  Defaults to "image/jpeg" if absent.
    media_type: []u8,
    /// Optional text prompt.  Empty string if absent.
    prompt: []u8,
    /// Optional system prompt.  Empty string if absent.
    system_prompt: []u8,
    scope: []u8,
    max_tokens: u32,
    temperature: f32,

    fn deinit(self: VisionArgs, allocator: std.mem.Allocator) void {
        allocator.free(self.image_b64);
        allocator.free(self.media_type);
        allocator.free(self.prompt);
        allocator.free(self.system_prompt);
        allocator.free(self.scope);
    }
};

fn parseVisionArgs(allocator: std.mem.Allocator, args_json: []const u8) !VisionArgs {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_args;
    const obj = parsed.value.object;

    const image_v = obj.get("image_b64") orelse return error.invalid_args;
    if (image_v != .string or image_v.string.len == 0) return error.invalid_args;
    const image_b64 = try allocator.dupe(u8, image_v.string);
    errdefer allocator.free(image_b64);

    const media_type: []u8 = blk: {
        if (obj.get("media_type")) |v| {
            if (v == .string and v.string.len > 0) break :blk try allocator.dupe(u8, v.string);
        }
        break :blk try allocator.dupe(u8, "image/jpeg");
    };
    errdefer allocator.free(media_type);

    const prompt: []u8 = blk: {
        if (obj.get("prompt")) |v| {
            if (v == .string) break :blk try allocator.dupe(u8, v.string);
        }
        break :blk try allocator.dupe(u8, "");
    };
    errdefer allocator.free(prompt);

    const system_prompt: []u8 = blk: {
        if (obj.get("system_prompt")) |v| {
            if (v == .string) break :blk try allocator.dupe(u8, v.string);
        }
        break :blk try allocator.dupe(u8, "");
    };
    errdefer allocator.free(system_prompt);

    const scope_v = obj.get("scope") orelse return error.invalid_args;
    if (scope_v != .string or scope_v.string.len == 0) return error.invalid_args;
    for (scope_v.string) |c| {
        if (!isScopeChar(c)) return error.invalid_args;
    }
    const scope = try allocator.dupe(u8, scope_v.string);
    errdefer allocator.free(scope);

    var max_tokens: u32 = 0;
    if (obj.get("max_tokens")) |v| {
        if (v == .integer and v.integer >= 0 and v.integer <= std.math.maxInt(u32)) {
            max_tokens = @intCast(v.integer);
        }
    }
    var temperature: f32 = -1.0;
    if (obj.get("temperature")) |v| {
        switch (v) {
            .float => |f| temperature = @floatCast(f),
            .integer => |i| temperature = @floatFromInt(i),
            else => {},
        }
    }

    return .{
        .image_b64 = image_b64,
        .media_type = media_type,
        .prompt = prompt,
        .system_prompt = system_prompt,
        .scope = scope,
        .max_tokens = max_tokens,
        .temperature = temperature,
    };
}

// ─────────────────────────────────────────────────────────────────────
// Result encoding
// ─────────────────────────────────────────────────────────────────────

fn ownedJsonResult(
    allocator: std.mem.Allocator,
    resp: llm_http.CompletionResponse,
) !dispatcher.Result {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"text\":");
    try writeJsonString(allocator, &buf, resp.text);
    try buf.appendSlice(allocator, ",\"model\":");
    try writeJsonString(allocator, &buf, resp.model);
    try buf.print(allocator, ",\"tokens_used\":{d}}}", .{resp.tokens_used});
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn writeJsonString(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    s: []const u8,
) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

// ─────────────────────────────────────────────────────────────────────
// Budget persistence
// ─────────────────────────────────────────────────────────────────────

/// Load `<data_dir>/llm-budgets.json` into the in-memory map.  Missing
/// file = empty map (first-run shape).  Malformed file is logged and
/// treated as empty — better to lose budget state than to refuse
/// service.
fn loadBudgetsImpl(self: *Handler) !void {
    const f = std.fs.cwd().openFile(self.budgets_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return,
    };
    defer f.close();
    var buf: [128 * 1024]u8 = undefined;
    const n = f.readAll(&buf) catch return;
    if (n == 0) return;

    const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, buf[0..n], .{}) catch return;
    defer parsed.deinit();
    if (parsed.value != .object) return;
    const root = parsed.value.object;
    const scopes_v = root.get("scopes") orelse return;
    if (scopes_v != .object) return;

    var it = scopes_v.object.iterator();
    while (it.next()) |entry| {
        const name = entry.key_ptr.*;
        const v = entry.value_ptr.*;
        if (v != .object) continue;
        const scope_obj = v.object;

        const owned_name = self.allocator.dupe(u8, name) catch return;
        var sb = ScopeBudget.init();

        if (scope_obj.get("request_history")) |hv| {
            if (hv == .array) {
                for (hv.array.items) |t| {
                    if (t == .integer) {
                        sb.request_history.append(self.allocator, t.integer) catch break;
                    }
                }
            }
        }
        if (scope_obj.get("tokens_today")) |tv| {
            if (tv == .integer and tv.integer >= 0 and tv.integer <= std.math.maxInt(u32)) {
                sb.tokens_today = @intCast(tv.integer);
            }
        }
        if (scope_obj.get("tokens_today_day")) |dv| {
            if (dv == .integer) sb.tokens_today_day = dv.integer;
        }
        if (scope_obj.get("lifetime_tokens")) |lv| {
            if (lv == .integer and lv.integer >= 0) sb.lifetime_tokens = @intCast(lv.integer);
        }

        const gop = self.budgets.getOrPut(owned_name) catch {
            self.allocator.free(owned_name);
            sb.deinit(self.allocator);
            return;
        };
        if (gop.found_existing) {
            self.allocator.free(owned_name);
            sb.deinit(self.allocator);
            continue;
        }
        gop.value_ptr.* = sb;
    }
}

/// Serialise the in-memory map to disk.  Mode 0600 — informational
/// (no secrets), but the file lives under the operator's data_dir
/// alongside other operator-only state.
fn persistBudgetsImpl(self: *Handler) !void {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(self.allocator);
    try buf.appendSlice(self.allocator, "{\"version\":1,\"scopes\":{");
    var first = true;
    var it = self.budgets.iterator();
    while (it.next()) |entry| {
        if (!first) try buf.append(self.allocator, ',');
        first = false;
        try writeJsonString(self.allocator, &buf, entry.key_ptr.*);
        try buf.appendSlice(self.allocator, ":{\"request_history\":[");
        for (entry.value_ptr.request_history.items, 0..) |t, i| {
            if (i != 0) try buf.append(self.allocator, ',');
            try buf.print(self.allocator, "{d}", .{t});
        }
        try buf.print(
            self.allocator,
            "],\"tokens_today\":{d},\"tokens_today_day\":{d},\"lifetime_tokens\":{d}}}",
            .{ entry.value_ptr.tokens_today, entry.value_ptr.tokens_today_day, entry.value_ptr.lifetime_tokens },
        );
    }
    try buf.appendSlice(self.allocator, "}}");

    const f = std.fs.cwd().createFile(self.budgets_path, .{ .mode = 0o600 }) catch return;
    defer f.close();
    f.writeAll(buf.items) catch return;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure unit shape; full conformance lives in
// tests/llm_complete_conformance.zig.
// ─────────────────────────────────────────────────────────────────────

test "isScopeChar accepts dotted-namespace cap-name shape" {
    try std.testing.expect(isScopeChar('a'));
    try std.testing.expect(isScopeChar('Z'));
    try std.testing.expect(isScopeChar('0'));
    try std.testing.expect(isScopeChar('-'));
    try std.testing.expect(isScopeChar('_'));
    try std.testing.expect(isScopeChar('.'));
    try std.testing.expect(!isScopeChar(' '));
    try std.testing.expect(!isScopeChar('/'));
    try std.testing.expect(!isScopeChar('"'));
}

test "parseCompleteArgs requires prompt + scope" {
    const allocator = std.testing.allocator;
    const minimal =
        \\{"prompt":"hi","scope":"foo"}
    ;
    const args = try parseCompleteArgs(allocator, minimal);
    defer args.deinit(allocator);
    try std.testing.expectEqualSlices(u8, "hi", args.prompt);
    try std.testing.expectEqualSlices(u8, "foo", args.scope);
    try std.testing.expectEqualSlices(u8, "", args.system_prompt);
    try std.testing.expectEqual(@as(u32, 0), args.max_tokens);
}

test "parseCompleteArgs rejects empty scope" {
    const allocator = std.testing.allocator;
    const bad =
        \\{"prompt":"hi","scope":""}
    ;
    try std.testing.expectError(error.invalid_args, parseCompleteArgs(allocator, bad));
}

```
