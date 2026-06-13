---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/resources/site_handler.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.295168+00:00
---

# runtime/semantos-brain/src/resources/site_handler.zig

```zig
// DO-1/DO-2 — `site` operator resource: chat-widget policy management.
//
// The operator-facing surface for a hosted site's chat-widget policy, reached
// via the `do | manage | site | widget` grammar (do_verb_registry → dispatcher).
// Mirrors site_config_handler.zig (cap.brain.admin-gated, mutex'd) but operates
// on the operator PROFILE (widget enable + endpoint + copy).
//
// Commands:
//   widget_get — {} → { enabled, endpoint, title, greeting, placeholder }
//   widget_set — { enabled?, endpoint?, title?, greeting?, placeholder? } → {ok}
//                cap = cap.brain.admin
//
// widget_set mutates the SERVE-HELD in-memory OperatorProfile (the same instance
// the oddjobz chat route reads via deps.operator_profile — so the toggle is live
// without a restart, DO-3) THEN persists the widget_* keys back to profile.json
// (targeted merge) and emits a `site.widget.config.changed` helm broker event.
//
// The brain serves a single domain (BRAIN_DOMAIN), so the handler reads/writes
// the serve-held profile directly — no per-call domain arg. `profile` is null on
// boot paths that didn't load one (e.g. the standalone cli/repl); widget_get
// then reports defaults and widget_set returns no_profile.

const std = @import("std");
const dispatcher = @import("dispatcher");
const operator_profile = @import("operator_profile");
const operator_profile_loader = @import("operator_profile_loader");
const helm_event_broker = @import("helm_event_broker");

pub const RESOURCE_NAME = "site";

pub const HandlerError = error{
    invalid_args,
    no_profile,
    store_error,
    out_of_memory,
    not_found,
};

pub const Handler = struct {
    allocator: std.mem.Allocator,
    /// The serve-held operator profile (borrowed, MUTABLE — widget_set mutates it
    /// in place so the cartridge's reads see the change live). Null when no
    /// profile was loaded for the served domain.
    profile: ?*operator_profile.OperatorProfile,
    /// Helm event broker for `site.widget.config.changed` (DO-2). Null-degrades.
    broker: ?*helm_event_broker.Broker,
    /// `<data_dir>` + served `<domain>` — the profile.json path for persistence.
    data_dir: []const u8,
    domain: []const u8,
    mu: std.Thread.Mutex,

    pub fn init(
        allocator: std.mem.Allocator,
        profile: ?*operator_profile.OperatorProfile,
        broker: ?*helm_event_broker.Broker,
        data_dir: []const u8,
        domain: []const u8,
    ) Handler {
        return .{
            .allocator = allocator,
            .profile = profile,
            .broker = broker,
            .data_dir = data_dir,
            .domain = domain,
            .mu = .{},
        };
    }

    pub fn resourceHandler(self: *Handler) dispatcher.ResourceHandler {
        return .{
            .name = RESOURCE_NAME,
            .state = self,
            .cap_for_cmd_fn = capForCmd,
            .handle_fn = handle,
            .audit_reads = true,
            .is_read_fn = isRead,
        };
    }
};

fn capForCmd(_: ?*anyopaque, cmd: []const u8) dispatcher.CapDeclError!dispatcher.CapDecl {
    if (std.mem.eql(u8, cmd, "widget_get")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "widget_set")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "pricing_get")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "pricing_set")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "prompt_get")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "prompt_set")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "prompt_list")) return .{ .require = "cap.brain.admin" };
    if (std.mem.eql(u8, cmd, "prompt_rollback")) return .{ .require = "cap.brain.admin" };
    return error.unknown_command;
}

pub fn isRead(cmd: []const u8) bool {
    return std.mem.eql(u8, cmd, "widget_get") or std.mem.eql(u8, cmd, "pricing_get") or
        std.mem.eql(u8, cmd, "prompt_get") or std.mem.eql(u8, cmd, "prompt_list");
}

fn handle(
    state: ?*anyopaque,
    _: *const dispatcher.DispatchContext,
    cmd: []const u8,
    args_json: []const u8,
    allocator: std.mem.Allocator,
) anyerror!dispatcher.Result {
    const self: *Handler = @ptrCast(@alignCast(state.?));
    self.mu.lock();
    defer self.mu.unlock();

    if (std.mem.eql(u8, cmd, "widget_get")) return handleWidgetGet(self, allocator);
    if (std.mem.eql(u8, cmd, "widget_set")) return handleWidgetSet(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "pricing_get")) return handlePricingGet(self, allocator);
    if (std.mem.eql(u8, cmd, "pricing_set")) return handlePricingSet(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "prompt_get")) return handlePromptGet(self, allocator);
    if (std.mem.eql(u8, cmd, "prompt_set")) return handlePromptSet(self, allocator, args_json);
    if (std.mem.eql(u8, cmd, "prompt_list")) return handlePromptList(self, allocator);
    if (std.mem.eql(u8, cmd, "prompt_rollback")) return handlePromptRollback(self, allocator, args_json);
    return error.unknown_command;
}

fn handleWidgetGet(self: *Handler, allocator: std.mem.Allocator) !dispatcher.Result {
    var enabled = true;
    var endpoint: []const u8 = "/api/v1/chat";
    var title: []const u8 = "";
    var greeting: []const u8 = "";
    var placeholder: []const u8 = "";
    var rate_limit: u32 = 100;
    var daily_tokens: u32 = 100_000;
    var max_chars: u32 = 4000;
    var origins: []const u8 = "";
    if (self.profile) |p| {
        enabled = p.widget_enabled;
        if (p.widget_endpoint.len > 0) endpoint = p.widget_endpoint;
        title = p.widget_title;
        greeting = p.widget_greeting;
        placeholder = p.widget_placeholder;
        rate_limit = p.widget_rate_limit_per_hour;
        daily_tokens = p.widget_tokens_per_day;
        max_chars = p.widget_max_message_chars;
        origins = p.widget_embed_origins;
    }

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.print(allocator, "{{\"enabled\":{},\"endpoint\":", .{enabled});
    try writeJsonString(allocator, &buf, endpoint);
    try buf.appendSlice(allocator, ",\"title\":");
    try writeJsonString(allocator, &buf, title);
    try buf.appendSlice(allocator, ",\"greeting\":");
    try writeJsonString(allocator, &buf, greeting);
    try buf.appendSlice(allocator, ",\"placeholder\":");
    try writeJsonString(allocator, &buf, placeholder);
    try buf.print(allocator, ",\"rate_limit\":{d},\"daily_tokens\":{d},\"max_chars\":{d},\"embed_origins\":", .{ rate_limit, daily_tokens, max_chars });
    try writeJsonString(allocator, &buf, origins);
    try buf.appendSlice(allocator, "}");
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn handleWidgetSet(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const prof = self.profile orelse return HandlerError.no_profile;

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch
        return HandlerError.invalid_args;
    defer parsed.deinit();
    if (parsed.value != .object) return HandlerError.invalid_args;
    const obj = parsed.value.object;

    var changed = false;
    // enabled accepts a bool OR a "true"/"false" string (the `do` grammar sends
    // string-valued k=v args).
    if (obj.get("enabled")) |v| {
        prof.widget_enabled = coerceBool(v) orelse return HandlerError.invalid_args;
        changed = true;
    }
    // String fields are duped into self.allocator (serve lifetime) — NOT the
    // per-request allocator — since they live on the serve-held profile.
    if (try setStrField(self.allocator, obj, "endpoint", &prof.widget_endpoint)) changed = true;
    if (try setStrField(self.allocator, obj, "title", &prof.widget_title)) changed = true;
    if (try setStrField(self.allocator, obj, "greeting", &prof.widget_greeting)) changed = true;
    if (try setStrField(self.allocator, obj, "placeholder", &prof.widget_placeholder)) changed = true;
    // WP-2 — governance knobs (numeric; the `do` grammar sends them as strings).
    // rate_limit + daily_tokens are boot-seeded into llm_complete_handler (apply on
    // next brain start); max_chars is read live by the cartridge chat route.
    if (try setU32Field(obj, "rate_limit", &prof.widget_rate_limit_per_hour)) changed = true;
    if (try setU32Field(obj, "daily_tokens", &prof.widget_tokens_per_day)) changed = true;
    if (try setU32Field(obj, "max_chars", &prof.widget_max_message_chars)) changed = true;
    // WP-3 — comma-separated embed-origin allowlist (live: read by the chat route).
    if (try setStrField(self.allocator, obj, "origins", &prof.widget_embed_origins)) changed = true;

    if (!changed) return HandlerError.invalid_args;

    // Persist the widget_* keys back to profile.json (targeted merge).
    operator_profile_loader.saveWidgetFields(self.allocator, self.data_dir, self.domain, prof) catch
        return HandlerError.store_error;

    // Emit a helm event so operator dashboards reflect the change live.
    if (self.broker) |b| {
        const payload = try std.fmt.allocPrint(
            allocator,
            "{{\"domain\":\"{s}\",\"enabled\":{},\"endpoint\":\"{s}\"}}",
            .{ self.domain, prof.widget_enabled, prof.widget_endpoint },
        );
        defer allocator.free(payload);
        b.publish(.{ .type = "site.widget.config.changed", .payload_json = payload });
    }

    const out = try std.fmt.allocPrint(allocator, "{{\"ok\":true,\"enabled\":{}}}", .{prof.widget_enabled});
    return dispatcher.Result.ownedPayload(allocator, out);
}

// ── WP-4 — pricing (do manage site pricing) ────────────────────────────────

fn handlePricingGet(self: *Handler, allocator: std.mem.Allocator) !dispatcher.Result {
    const empty = operator_profile.Pricing{
        .callout_fee = null,
        .hourly_rate = null,
        .emergency_rate = null,
        .minimum_charge = null,
        .quote_policy = .chat_first,
        .travel_distance_km = null,
    };
    const p = if (self.profile) |pr| pr.pricing else empty;
    // -1 = unset (operator-facing read).
    const hourly: i64 = if (p.hourly_rate) |pl| @intCast(pl.amount) else -1;
    const callout: i64 = if (p.callout_fee) |pl| @intCast(pl.amount) else -1;
    const minimum: i64 = if (p.minimum_charge) |pl| @intCast(pl.amount) else -1;
    const travel: i64 = if (p.travel_distance_km) |km| @intCast(km) else -1;

    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.print(allocator, "{{\"hourly_rate\":{d},\"callout_fee\":{d},\"minimum_charge\":{d},\"travel_km\":{d},\"quote_policy\":", .{ hourly, callout, minimum, travel });
    try writeJsonString(allocator, &buf, p.quote_policy.toString());
    try buf.appendSlice(allocator, "}");
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn handlePricingSet(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const prof = self.profile orelse return HandlerError.no_profile;

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch
        return HandlerError.invalid_args;
    defer parsed.deinit();
    if (parsed.value != .object) return HandlerError.invalid_args;
    const obj = parsed.value.object;

    var changed = false;
    if (try readU32Arg(obj, "hourly_rate")) |amt| {
        setPricingLineAmount(&prof.pricing.hourly_rate, "Hourly rate", amt);
        changed = true;
    }
    if (try readU32Arg(obj, "callout")) |amt| {
        setPricingLineAmount(&prof.pricing.callout_fee, "Call-out fee", amt);
        changed = true;
    }
    if (try readU32Arg(obj, "minimum")) |amt| {
        setPricingLineAmount(&prof.pricing.minimum_charge, "Minimum charge", amt);
        changed = true;
    }
    if (try readU32Arg(obj, "travel_km")) |km| {
        prof.pricing.travel_distance_km = km;
        changed = true;
    }
    if (obj.get("quote_policy")) |v| {
        if (v != .string) return HandlerError.invalid_args;
        prof.pricing.quote_policy = operator_profile.QuotePolicy.fromString(v.string);
        changed = true;
    }
    if (!changed) return HandlerError.invalid_args;

    operator_profile_loader.savePricingFields(self.allocator, self.data_dir, self.domain, prof) catch
        return HandlerError.store_error;

    if (self.broker) |b| {
        const payload = try std.fmt.allocPrint(allocator, "{{\"domain\":\"{s}\"}}", .{self.domain});
        defer allocator.free(payload);
        b.publish(.{ .type = "site.pricing.changed", .payload_json = payload });
    }

    return dispatcher.Result.ownedPayload(allocator, try allocator.dupe(u8, "{\"ok\":true}"));
}

/// Read a non-negative integer arg (int or numeric string); null if absent.
fn readU32Arg(obj: std.json.ObjectMap, key: []const u8) !?u32 {
    const v = obj.get(key) orelse return null;
    switch (v) {
        .integer => |n| {
            if (n < 0) return error.invalid_args;
            return @intCast(n);
        },
        .string => |s| return std.fmt.parseInt(u32, s, 10) catch error.invalid_args,
        else => return error.invalid_args,
    }
}

/// Update an existing PricingLine's amount (preserving label/currency) or create
/// one with a default label + AUD.
fn setPricingLineAmount(field: *?operator_profile.PricingLine, default_label: []const u8, amount: u32) void {
    if (field.*) |*pl| {
        pl.amount = amount;
    } else {
        field.* = .{ .label = default_label, .amount = amount, .currency = "AUD" };
    }
}

// ── WP-5 — versioned conversation prompt (do manage/list/rollback site prompt) ──
//
// Versions append to <data_dir>/sites/<domain>/prompts.jsonl, one JSON record per
// line: {"id":N,"ts":T,"text":"…"}. The active version id lives on the profile
// (widget_prompt_version, persisted via saveWidgetFields). The operator tunes the
// system prompt for their trade with full history + rollback; WP-6 wires the
// active version into the intake conversation.

const MAX_PROMPTS_BYTES: usize = 4 * 1024 * 1024;

fn promptsPath(self: *Handler, allocator: std.mem.Allocator) ![]u8 {
    return std.fs.path.join(allocator, &.{ self.data_dir, "sites", self.domain, "prompts.jsonl" });
}

fn readPromptsFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(allocator, path, MAX_PROMPTS_BYTES) catch |e| switch (e) {
        error.FileNotFound => try allocator.dupe(u8, ""),
        else => return HandlerError.store_error,
    };
}

fn handlePromptGet(self: *Handler, allocator: std.mem.Allocator) !dispatcher.Result {
    const active: u32 = if (self.profile) |p| p.widget_prompt_version else 0;
    var text: []const u8 = "";
    if (active != 0) {
        const path = try promptsPath(self, allocator);
        defer allocator.free(path);
        const contents = try readPromptsFile(allocator, path);
        defer allocator.free(contents);
        var it = std.mem.splitScalar(u8, contents, '\n');
        while (it.next()) |line| {
            if (line.len == 0) continue;
            const lp = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
            defer lp.deinit();
            if (lp.value != .object) continue;
            const idv = lp.value.object.get("id") orelse continue;
            if (idv != .integer or idv.integer != active) continue;
            if (lp.value.object.get("text")) |tv| {
                if (tv == .string) text = try allocator.dupe(u8, tv.string);
            }
            break;
        }
    }
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.print(allocator, "{{\"version\":{d},\"text\":", .{active});
    try writeJsonString(allocator, &buf, text);
    try buf.appendSlice(allocator, "}");
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn handlePromptSet(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const prof = self.profile orelse return HandlerError.no_profile;
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch
        return HandlerError.invalid_args;
    defer parsed.deinit();
    if (parsed.value != .object) return HandlerError.invalid_args;
    const tv = parsed.value.object.get("text") orelse return HandlerError.invalid_args;
    if (tv != .string) return HandlerError.invalid_args;

    const path = try promptsPath(self, allocator);
    defer allocator.free(path);

    // Highest existing id → next id.
    var max_id: u32 = 0;
    {
        const contents = try readPromptsFile(allocator, path);
        defer allocator.free(contents);
        var it = std.mem.splitScalar(u8, contents, '\n');
        while (it.next()) |line| {
            if (line.len == 0) continue;
            const lp = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
            defer lp.deinit();
            if (lp.value == .object) {
                if (lp.value.object.get("id")) |idv| {
                    if (idv == .integer and idv.integer > max_id) max_id = @intCast(idv.integer);
                }
            }
        }
    }
    const new_id = max_id + 1;
    const ts = std.time.timestamp();

    if (std.fs.path.dirname(path)) |dir| std.fs.cwd().makePath(dir) catch {};
    const f = std.fs.cwd().createFile(path, .{ .truncate = false }) catch return HandlerError.store_error;
    defer f.close();
    f.seekFromEnd(0) catch return HandlerError.store_error;
    var line: std.ArrayList(u8) = .{};
    defer line.deinit(allocator);
    try line.print(allocator, "{{\"id\":{d},\"ts\":{d},\"text\":", .{ new_id, ts });
    try writeJsonString(allocator, &line, tv.string);
    try line.appendSlice(allocator, "}\n");
    f.writeAll(line.items) catch return HandlerError.store_error;

    prof.widget_prompt_version = new_id;
    operator_profile_loader.saveWidgetFields(self.allocator, self.data_dir, self.domain, prof) catch
        return HandlerError.store_error;
    if (self.broker) |b| {
        const payload = try std.fmt.allocPrint(allocator, "{{\"domain\":\"{s}\",\"version\":{d}}}", .{ self.domain, new_id });
        defer allocator.free(payload);
        b.publish(.{ .type = "site.prompt.changed", .payload_json = payload });
    }
    return dispatcher.Result.ownedPayload(allocator, try std.fmt.allocPrint(allocator, "{{\"ok\":true,\"version\":{d}}}", .{new_id}));
}

fn handlePromptList(self: *Handler, allocator: std.mem.Allocator) !dispatcher.Result {
    const active: u32 = if (self.profile) |p| p.widget_prompt_version else 0;
    const path = try promptsPath(self, allocator);
    defer allocator.free(path);
    const contents = try readPromptsFile(allocator, path);
    defer allocator.free(contents);
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);
    try buf.print(allocator, "{{\"active\":{d},\"versions\":[", .{active});
    var first = true;
    var it = std.mem.splitScalar(u8, contents, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        const lp = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
        defer lp.deinit();
        if (lp.value != .object) continue;
        const idv = lp.value.object.get("id") orelse continue;
        if (idv != .integer) continue;
        const tsv: i64 = if (lp.value.object.get("ts")) |x| (if (x == .integer) x.integer else 0) else 0;
        const tlen: usize = if (lp.value.object.get("text")) |x| (if (x == .string) x.string.len else 0) else 0;
        if (!first) try buf.appendSlice(allocator, ",");
        first = false;
        try buf.print(allocator, "{{\"id\":{d},\"ts\":{d},\"chars\":{d}}}", .{ idv.integer, tsv, tlen });
    }
    try buf.appendSlice(allocator, "]}");
    return dispatcher.Result.ownedPayload(allocator, try buf.toOwnedSlice(allocator));
}

fn handlePromptRollback(self: *Handler, allocator: std.mem.Allocator, args_json: []const u8) !dispatcher.Result {
    const prof = self.profile orelse return HandlerError.no_profile;
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, args_json, .{}) catch
        return HandlerError.invalid_args;
    defer parsed.deinit();
    if (parsed.value != .object) return HandlerError.invalid_args;
    const target: u32 = (try readU32Arg(parsed.value.object, "id")) orelse
        (try readU32Arg(parsed.value.object, "version")) orelse return HandlerError.invalid_args;

    const path = try promptsPath(self, allocator);
    defer allocator.free(path);
    const contents = try readPromptsFile(allocator, path);
    defer allocator.free(contents);
    var found = false;
    var it = std.mem.splitScalar(u8, contents, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        const lp = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
        defer lp.deinit();
        if (lp.value == .object) {
            if (lp.value.object.get("id")) |idv| {
                if (idv == .integer and idv.integer == target) {
                    found = true;
                    break;
                }
            }
        }
    }
    if (!found) return HandlerError.not_found;

    prof.widget_prompt_version = target;
    operator_profile_loader.saveWidgetFields(self.allocator, self.data_dir, self.domain, prof) catch
        return HandlerError.store_error;
    if (self.broker) |b| {
        const payload = try std.fmt.allocPrint(allocator, "{{\"domain\":\"{s}\",\"version\":{d}}}", .{ self.domain, target });
        defer allocator.free(payload);
        b.publish(.{ .type = "site.prompt.changed", .payload_json = payload });
    }
    return dispatcher.Result.ownedPayload(allocator, try std.fmt.allocPrint(allocator, "{{\"ok\":true,\"version\":{d}}}", .{target}));
}

fn coerceBool(v: std.json.Value) ?bool {
    return switch (v) {
        .bool => |b| b,
        .string => |s| if (std.mem.eql(u8, s, "true")) true else if (std.mem.eql(u8, s, "false")) false else null,
        else => null,
    };
}

/// If `obj[key]` is a string, dupe it into `allocator` and store into `field*`.
/// Returns true when a value was set.
fn setStrField(allocator: std.mem.Allocator, obj: std.json.ObjectMap, key: []const u8, field: *[]const u8) !bool {
    const v = obj.get(key) orelse return false;
    if (v != .string) return error.invalid_args;
    field.* = try allocator.dupe(u8, v.string);
    return true;
}

/// WP-2 — if `obj[key]` is a non-negative integer (or a numeric string from the
/// `do` grammar), store it into `field*`. Returns true when a value was set.
fn setU32Field(obj: std.json.ObjectMap, key: []const u8, field: *u32) !bool {
    const v = obj.get(key) orelse return false;
    switch (v) {
        .integer => |n| {
            if (n < 0) return error.invalid_args;
            field.* = @intCast(n);
        },
        .string => |s| field.* = std.fmt.parseInt(u32, s, 10) catch return error.invalid_args,
        else => return error.invalid_args,
    }
    return true;
}

fn writeJsonString(allocator: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    const encoded = try std.json.Stringify.valueAlloc(allocator, s, .{});
    defer allocator.free(encoded);
    try out.appendSlice(allocator, encoded);
}

// ── inline tests ──────────────────────────────────────────────────────────

const testing = std.testing;

test "site_handler: widget_get reports defaults with no profile" {
    var h = Handler.init(testing.allocator, null, null, "", "");
    var rh = h.resourceHandler();
    const ctx = dispatcher.DispatchContext{
        .auth = .in_process_root,
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "test" },
    };
    var result = try rh.handle_fn(rh.state, &ctx, "widget_get", "{}", testing.allocator);
    defer result.deinit();
    try testing.expect(std.mem.indexOf(u8, result.payload, "\"/api/v1/chat\"") != null);
    try testing.expect(std.mem.indexOf(u8, result.payload, "\"enabled\":true") != null);
}

test "site_handler: both commands require admin cap" {
    try testing.expectEqualStrings("cap.brain.admin", (try capForCmd(null, "widget_get")).require);
    try testing.expectEqualStrings("cap.brain.admin", (try capForCmd(null, "widget_set")).require);
}

test "site_handler: widget_set with no profile returns no_profile" {
    var h = Handler.init(testing.allocator, null, null, "", "");
    var rh = h.resourceHandler();
    const ctx = dispatcher.DispatchContext{
        .auth = .in_process_root,
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "test" },
    };
    try testing.expectError(HandlerError.no_profile, rh.handle_fn(rh.state, &ctx, "widget_set", "{\"enabled\":false}", testing.allocator));
}

test "coerceBool: bool + string forms" {
    try testing.expectEqual(@as(?bool, true), coerceBool(.{ .bool = true }));
    try testing.expectEqual(@as(?bool, false), coerceBool(.{ .string = "false" }));
    try testing.expectEqual(@as(?bool, null), coerceBool(.{ .string = "maybe" }));
}

```
