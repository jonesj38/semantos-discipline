---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/operator_profile_loader.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.256158+00:00
---

# runtime/semantos-brain/src/operator_profile_loader.zig

```zig
// S11 — Operator profile loader.
//
// Reads a profile.json from $data_dir/sites/<domain>/profile.json and
// assembles an OperatorProfile.  All strings are arena-allocated — the
// caller deinits the arena when done with the profile.
//
// profile.json schema (flat — all OperatorProfile fields at the top level):
//
//   {
//     "business_name":     "Oddjobz",
//     "trade_label":       "Handyman",
//     "geography":         "Sunshine Coast",
//     "phone":             "0412 345 678",
//     "abn":               "00 000 000 000",
//     "problem":           "...",
//     "uvp":               "...",
//     "hero_h1":           "Get a rough quote in minutes",
//     "hero_lede":         "...",
//     "segment":           "homeowners",
//     "tone":              "friendly",
//     "trust_signals":     ["...", "..."],
//     "services":          [{ "slug": "...", "label": "...", "icon": "...", "description": "..." }],
//     "pricing": {
//       "callout_fee":    { "label": "Service call", "amount": 120, "currency": "AUD" } | null,
//       "hourly_rate":    { "label": "Per hour",     "amount": 95,  "currency": "AUD" } | null,
//       "emergency_rate": null,
//       "minimum_charge": null,
//       "quote_policy":   "free_onsite"
//     },
//     "widget_title":       "Get a rough quote",
//     "widget_greeting":    "G'day! ...",
//     "widget_placeholder": "Describe the job...",
//     "widget_endpoint":    "/api/v1/chat"
//   }
//
// Missing optional fields fall back to the values in defaultProfile().
// On any parse error, the function returns error.invalid_profile.

const std = @import("std");
const op = @import("operator_profile");

pub const LoadError = error{
    file_not_found,
    file_too_large,
    invalid_profile,
    out_of_memory,
};

const MAX_PROFILE_BYTES = 64 * 1024; // 64 KB — profiles are tiny

/// Load an OperatorProfile from a profile.json file on disk.
/// `allocator` should be an arena — all returned strings point into it.
/// Returns error.file_not_found when the file doesn't exist.
pub fn loadFromFile(
    allocator: std.mem.Allocator,
    profile_path: []const u8,
) LoadError!op.OperatorProfile {
    const file = std.fs.cwd().openFile(profile_path, .{}) catch |e| switch (e) {
        error.FileNotFound, error.AccessDenied => return error.file_not_found,
        else => return error.file_not_found,
    };
    defer file.close();

    const stat = file.stat() catch return error.file_not_found;
    if (stat.size > MAX_PROFILE_BYTES) return error.file_too_large;

    const buf = allocator.alloc(u8, stat.size) catch return error.out_of_memory;
    const n = file.readAll(buf) catch return error.invalid_profile;
    return parseProfileJson(allocator, buf[0..n]);
}

/// Load from $data_dir/sites/<domain>/profile.json.
pub fn loadForDomain(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    domain: []const u8,
) LoadError!op.OperatorProfile {
    const path = std.fs.path.join(allocator, &.{ data_dir, "sites", domain, "profile.json" }) catch
        return error.out_of_memory;
    defer allocator.free(path);
    return loadFromFile(allocator, path);
}

/// Parse a profile.json payload into an OperatorProfile.
/// All strings are duped into `allocator`.
pub fn parseProfileJson(
    allocator: std.mem.Allocator,
    json: []const u8,
) LoadError!op.OperatorProfile {
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, allocator, json, .{}) catch
        return error.invalid_profile;
    if (parsed != .object) return error.invalid_profile;
    const root = parsed.object;

    // ── Scalar string fields ──────────────────────────────────────────
    const business_name   = dupeStr(allocator, root, "business_name",   "Oddjobz")     catch return error.out_of_memory;
    const trade_label     = dupeStr(allocator, root, "trade_label",     "Handyman")    catch return error.out_of_memory;
    const geography       = dupeStr(allocator, root, "geography",       "")            catch return error.out_of_memory;
    const phone           = dupeStr(allocator, root, "phone",           "")            catch return error.out_of_memory;
    const abn             = dupeStr(allocator, root, "abn",             "")            catch return error.out_of_memory;
    const problem         = dupeStr(allocator, root, "problem",         "")            catch return error.out_of_memory;
    const uvp             = dupeStr(allocator, root, "uvp",             "")            catch return error.out_of_memory;
    const hero_h1         = dupeStr(allocator, root, "hero_h1",         "")            catch return error.out_of_memory;
    const hero_lede       = dupeStr(allocator, root, "hero_lede",       "")            catch return error.out_of_memory;
    const segment         = dupeStr(allocator, root, "segment",         "homeowners")  catch return error.out_of_memory;
    const widget_title    = dupeStr(allocator, root, "widget_title",    "")            catch return error.out_of_memory;
    const widget_greeting = dupeStr(allocator, root, "widget_greeting", "")            catch return error.out_of_memory;
    const widget_placeholder = dupeStr(allocator, root, "widget_placeholder", "")     catch return error.out_of_memory;
    const widget_endpoint = dupeStr(allocator, root, "widget_endpoint", "/api/v1/chat") catch return error.out_of_memory;
    // DO-2 — widget on/off switch; default true (live) when absent.
    const widget_enabled = if (root.get("widget_enabled")) |v| switch (v) {
        .bool => |b| b,
        else => true,
    } else true;
    // WP-2 — governance knobs (default to the brain's built-ins when absent).
    const widget_rate_limit_per_hour = u32Field(root, "widget_rate_limit_per_hour", 100);
    const widget_tokens_per_day = u32Field(root, "widget_tokens_per_day", 100_000);
    const widget_max_message_chars = u32Field(root, "widget_max_message_chars", 4000);
    const widget_embed_origins = dupeStr(allocator, root, "widget_embed_origins", "") catch return error.out_of_memory;
    const widget_prompt_version = u32Field(root, "widget_prompt_version", 0);

    // ── tone ─────────────────────────────────────────────────────────
    const tone_str = if (root.get("tone")) |v| switch (v) {
        .string => |s| s,
        else    => "friendly",
    } else "friendly";
    const tone = op.Tone.fromString(tone_str);

    // ── trust_signals (array of strings) ─────────────────────────────
    const trust_signals = blk: {
        const v = root.get("trust_signals") orelse break :blk @as([][]const u8, &.{});
        if (v != .array) break :blk @as([][]const u8, &.{});
        const items = v.array.items;
        const buf = allocator.alloc([]const u8, items.len) catch return error.out_of_memory;
        for (items, 0..) |item, i| {
            const s = switch (item) {
                .string => |str| str,
                else    => "",
            };
            buf[i] = allocator.dupe(u8, s) catch return error.out_of_memory;
        }
        break :blk buf;
    };

    // ── services (array of objects) ──────────────────────────────────
    const services = blk: {
        const v = root.get("services") orelse break :blk @as([]op.Service, &.{});
        if (v != .array) break :blk @as([]op.Service, &.{});
        const items = v.array.items;
        const buf = allocator.alloc(op.Service, items.len) catch return error.out_of_memory;
        for (items, 0..) |item, i| {
            if (item != .object) {
                buf[i] = .{ .slug = "", .label = "", .icon = "", .description = "" };
                continue;
            }
            const obj = item.object;
            buf[i] = .{
                .slug        = dupeObjStr(allocator, obj, "slug",        "") catch return error.out_of_memory,
                .label       = dupeObjStr(allocator, obj, "label",       "") catch return error.out_of_memory,
                .icon        = dupeObjStr(allocator, obj, "icon",        "") catch return error.out_of_memory,
                .description = dupeObjStr(allocator, obj, "description", "") catch return error.out_of_memory,
            };
        }
        break :blk buf;
    };

    // ── pricing ──────────────────────────────────────────────────────
    const pricing = blk: {
        const pv = root.get("pricing") orelse break :blk op.Pricing{
            .callout_fee    = null,
            .hourly_rate    = null,
            .emergency_rate = null,
            .minimum_charge = null,
            .quote_policy   = .chat_first,
        };
        if (pv != .object) break :blk op.Pricing{
            .callout_fee    = null,
            .hourly_rate    = null,
            .emergency_rate = null,
            .minimum_charge = null,
            .quote_policy   = .chat_first,
        };
        const pobj = pv.object;
        const qp_str = if (pobj.get("quote_policy")) |qv| switch (qv) {
            .string => |s| s,
            else    => "chat_first",
        } else "chat_first";
        break :blk op.Pricing{
            .callout_fee    = parsePricingLine(allocator, pobj, "callout_fee")    catch return error.out_of_memory,
            .hourly_rate    = parsePricingLine(allocator, pobj, "hourly_rate")    catch return error.out_of_memory,
            .emergency_rate = parsePricingLine(allocator, pobj, "emergency_rate") catch return error.out_of_memory,
            .minimum_charge = parsePricingLine(allocator, pobj, "minimum_charge") catch return error.out_of_memory,
            .quote_policy   = op.QuotePolicy.fromString(qp_str),
            .travel_distance_km = if (pobj.get("travel_distance_km")) |tv| switch (tv) {
                .integer => |n| if (n >= 0) @as(u32, @intCast(n)) else null,
                else => null,
            } else null,
        };
    };

    return op.OperatorProfile{
        .business_name       = business_name,
        .trade_label         = trade_label,
        .geography           = geography,
        .phone               = phone,
        .abn                 = abn,
        .problem             = problem,
        .uvp                 = uvp,
        .hero_h1             = hero_h1,
        .hero_lede           = hero_lede,
        .trust_signals       = trust_signals,
        .tone                = tone,
        .segment             = segment,
        .services            = services,
        .pricing             = pricing,
        .widget_title        = widget_title,
        .widget_greeting     = widget_greeting,
        .widget_placeholder  = widget_placeholder,
        .widget_endpoint     = widget_endpoint,
        .widget_enabled      = widget_enabled,
        .widget_rate_limit_per_hour = widget_rate_limit_per_hour,
        .widget_tokens_per_day      = widget_tokens_per_day,
        .widget_max_message_chars   = widget_max_message_chars,
        .widget_embed_origins       = widget_embed_origins,
        .widget_prompt_version      = widget_prompt_version,
    };
}

// ── Write path (DO-2) ─────────────────────────────────────────────────

/// Persist the widget policy fields of `profile` into
/// `<data_dir>/sites/<domain>/profile.json` via a targeted JSON merge: the
/// existing file is parsed, ONLY the `widget_*` keys are overwritten (all other
/// keys are preserved verbatim), and the result is atomically rewritten. A
/// missing file is treated as `{}`. The widget strings are borrowed from
/// `profile` (the serve-held instance); they must outlive this call (they do —
/// caller mutates the in-memory profile first, then calls this).
pub fn saveWidgetFields(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    domain: []const u8,
    profile: *const op.OperatorProfile,
) !void {
    const path = try std.fs.path.join(allocator, &.{ data_dir, "sites", domain, "profile.json" });
    defer allocator.free(path);

    const existing: []u8 = std.fs.cwd().readFileAlloc(allocator, path, MAX_PROFILE_BYTES) catch
        try allocator.dupe(u8, "{}");
    defer allocator.free(existing);

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, existing, .{}) catch
        return error.invalid_profile;
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_profile;

    try parsed.value.object.put("widget_enabled", .{ .bool = profile.widget_enabled });
    try parsed.value.object.put("widget_endpoint", .{ .string = profile.widget_endpoint });
    try parsed.value.object.put("widget_title", .{ .string = profile.widget_title });
    try parsed.value.object.put("widget_greeting", .{ .string = profile.widget_greeting });
    try parsed.value.object.put("widget_placeholder", .{ .string = profile.widget_placeholder });
    try parsed.value.object.put("widget_rate_limit_per_hour", .{ .integer = @intCast(profile.widget_rate_limit_per_hour) });
    try parsed.value.object.put("widget_tokens_per_day", .{ .integer = @intCast(profile.widget_tokens_per_day) });
    try parsed.value.object.put("widget_max_message_chars", .{ .integer = @intCast(profile.widget_max_message_chars) });
    try parsed.value.object.put("widget_embed_origins", .{ .string = profile.widget_embed_origins });
    try parsed.value.object.put("widget_prompt_version", .{ .integer = @intCast(profile.widget_prompt_version) });

    const out = try std.json.Stringify.valueAlloc(allocator, parsed.value, .{ .whitespace = .indent_2 });
    defer allocator.free(out);

    try writeFileAtomic(path, out);
}

/// WP-4 — persist the operator pricing into profile.json's nested "pricing"
/// object, rewritten from the in-memory struct (which models the full pricing
/// schema, so non-settable fields loaded at boot are preserved). Mirrors
/// saveWidgetFields' parse → put → stringify → atomic-write.
pub fn savePricingFields(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    domain: []const u8,
    profile: *const op.OperatorProfile,
) !void {
    const path = try std.fs.path.join(allocator, &.{ data_dir, "sites", domain, "profile.json" });
    defer allocator.free(path);
    const existing: []u8 = std.fs.cwd().readFileAlloc(allocator, path, MAX_PROFILE_BYTES) catch
        try allocator.dupe(u8, "{}");
    defer allocator.free(existing);
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, existing, .{}) catch
        return error.invalid_profile;
    defer parsed.deinit();
    if (parsed.value != .object) return error.invalid_profile;

    var pobj = std.json.ObjectMap.init(allocator);
    const p = profile.pricing;
    if (p.callout_fee) |pl| try pobj.put("callout_fee", try pricingLineValue(allocator, pl));
    if (p.hourly_rate) |pl| try pobj.put("hourly_rate", try pricingLineValue(allocator, pl));
    if (p.emergency_rate) |pl| try pobj.put("emergency_rate", try pricingLineValue(allocator, pl));
    if (p.minimum_charge) |pl| try pobj.put("minimum_charge", try pricingLineValue(allocator, pl));
    try pobj.put("quote_policy", .{ .string = p.quote_policy.toString() });
    if (p.travel_distance_km) |km| try pobj.put("travel_distance_km", .{ .integer = @intCast(km) });
    try parsed.value.object.put("pricing", .{ .object = pobj });

    const out = try std.json.Stringify.valueAlloc(allocator, parsed.value, .{ .whitespace = .indent_2 });
    defer allocator.free(out);
    try writeFileAtomic(path, out);
}

fn pricingLineValue(allocator: std.mem.Allocator, pl: op.PricingLine) !std.json.Value {
    var o = std.json.ObjectMap.init(allocator);
    try o.put("label", .{ .string = pl.label });
    try o.put("amount", .{ .integer = @intCast(pl.amount) });
    try o.put("currency", .{ .string = pl.currency });
    return .{ .object = o };
}

/// Write `contents` to `path` via a sibling .tmp + rename (crash-safe). Mirrors
/// site_config_handler.writeFileAtomic.
fn writeFileAtomic(path: []const u8, contents: []const u8) !void {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const tmp_path = try std.fmt.bufPrint(&path_buf, "{s}.tmp", .{path});
    {
        const f = try std.fs.cwd().createFile(tmp_path, .{});
        defer f.close();
        try f.writeAll(contents);
        try f.sync();
    }
    try std.fs.cwd().rename(tmp_path, path);
}

// ── Helpers ───────────────────────────────────────────────────────────

/// WP-2 — read a non-negative integer profile field, falling back to `default`.
fn u32Field(root: std.json.ObjectMap, key: []const u8, default: u32) u32 {
    if (root.get(key)) |v| switch (v) {
        .integer => |n| return if (n >= 0) @intCast(n) else default,
        else => return default,
    };
    return default;
}

fn dupeStr(
    allocator: std.mem.Allocator,
    obj: std.json.ObjectMap,
    key: []const u8,
    default: []const u8,
) ![]const u8 {
    const v = obj.get(key) orelse return allocator.dupe(u8, default);
    return switch (v) {
        .string => |s| allocator.dupe(u8, s),
        else    => allocator.dupe(u8, default),
    };
}

fn dupeObjStr(
    allocator: std.mem.Allocator,
    obj: std.json.ObjectMap,
    key: []const u8,
    default: []const u8,
) ![]const u8 {
    const v = obj.get(key) orelse return allocator.dupe(u8, default);
    return switch (v) {
        .string => |s| allocator.dupe(u8, s),
        else    => allocator.dupe(u8, default),
    };
}

fn parsePricingLine(
    allocator: std.mem.Allocator,
    obj: std.json.ObjectMap,
    key: []const u8,
) !?op.PricingLine {
    const v = obj.get(key) orelse return null;
    return switch (v) {
        .null   => null,
        .object => |o| {
            const label_str = if (o.get("label")) |lv| switch (lv) {
                .string => |s| s,
                else    => "",
            } else "";
            const amount: u32 = if (o.get("amount")) |av| switch (av) {
                .integer => |n| if (n >= 0) @intCast(n) else 0,
                .float   => |f| @intFromFloat(@max(0, f)),
                else     => 0,
            } else 0;
            const currency_str = if (o.get("currency")) |cv| switch (cv) {
                .string => |s| s,
                else    => "AUD",
            } else "AUD";
            return op.PricingLine{
                .label    = try allocator.dupe(u8, label_str),
                .amount   = amount,
                .currency = try allocator.dupe(u8, currency_str),
            };
        },
        else => null,
    };
}

```
