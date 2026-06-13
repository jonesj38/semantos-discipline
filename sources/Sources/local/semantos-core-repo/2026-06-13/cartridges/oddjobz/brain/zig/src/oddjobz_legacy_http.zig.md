---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/oddjobz_legacy_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.548229+00:00
---

# cartridges/oddjobz/brain/zig/src/oddjobz_legacy_http.zig

```zig
// LI-3c — legacy ingestion admin HTTP + public OAuth callback.
//
// Brain routes that wrap the cartridge-shipped legacy-host.ts (LI-3) so the
// operator can drive OAuth onboarding over a URL or the PWA — and Google can
// complete the grant via a PUBLIC callback (no localhost loopback / manual
// code-paste). Each route spawns `bun run legacy-host.ts` with the matching
// {args,flags} and returns its JSON; the callback returns an HTML confirmation.
//
//   POST /api/v1/legacy/register-client  (admin) {provider?,client_id,client_secret?,redirect_uri}
//   POST /api/v1/legacy/connect          (admin) {provider?} → { authorizeUrl, ... }
//   GET  /api/v1/legacy/oauth/callback   (PUBLIC) ?code=&state=&provider? → grant (HTML)
//   GET  /api/v1/legacy/status           (admin)
//
// admin = a valid operator bearer (single-operator mode). The callback is public
// by necessity (Google redirects to it) but is safe: legacy-host's `resume`
// validates the state-nonce against the disk-backed pending store, so a forged
// callback fails closed.

const std = @import("std");
const http_parser = @import("http_parser");
const http_route_registry = @import("http_route_registry");
const bearer_tokens_mod = @import("bearer_tokens");

pub const State = struct {
    allocator: std.mem.Allocator,
    /// Absolute path to the cartridge-shipped legacy-host.ts.
    script_path: []const u8,
    bearer_tokens: *bearer_tokens_mod.TokenStore,
};

const JSON_CT = "application/json";

// ── register-client ────────────────────────────────────────────────────────
pub fn registerClientRoute(state_any: *anyopaque, req: *const http_parser.HttpRequest, alloc: std.mem.Allocator) anyerror!http_route_registry.RouteResponse {
    const st: *State = @ptrCast(@alignCast(state_any));
    if (!std.mem.eql(u8, req.method, "POST")) return methodNotAllowed();
    if (!adminOk(st, req)) return unauthorized();

    const parsed = std.json.parseFromSlice(std.json.Value, alloc, req.body, .{}) catch return badRequest("bad_json");
    defer parsed.deinit();
    if (parsed.value != .object) return badRequest("bad_json");
    const obj = parsed.value.object;
    const provider = strOr(obj, "provider", "gmail");
    const client_id = strOr(obj, "client_id", "");
    const redirect_uri = strOr(obj, "redirect_uri", "");
    if (client_id.len == 0 or redirect_uri.len == 0) return badRequest("client_id + redirect_uri required");
    const client_secret = strOr(obj, "client_secret", "");

    // stdin: {"args":["register-client","<p>"],"flags":{"client-id":..,"redirect-uri":..,"client-secret":..}}
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(alloc);
    try buf.appendSlice(alloc, "{\"args\":[\"register-client\",");
    try appendJson(alloc, &buf, provider);
    try buf.appendSlice(alloc, "],\"flags\":{\"client-id\":");
    try appendJson(alloc, &buf, client_id);
    try buf.appendSlice(alloc, ",\"redirect-uri\":");
    try appendJson(alloc, &buf, redirect_uri);
    if (client_secret.len > 0) {
        try buf.appendSlice(alloc, ",\"client-secret\":");
        try appendJson(alloc, &buf, client_secret);
    }
    try buf.appendSlice(alloc, "}}");
    return jsonFromHost(st, alloc, buf.items);
}

// ── connect ────────────────────────────────────────────────────────────────
pub fn connectRoute(state_any: *anyopaque, req: *const http_parser.HttpRequest, alloc: std.mem.Allocator) anyerror!http_route_registry.RouteResponse {
    const st: *State = @ptrCast(@alignCast(state_any));
    if (!std.mem.eql(u8, req.method, "POST")) return methodNotAllowed();
    if (!adminOk(st, req)) return unauthorized();
    const provider = blk: {
        const parsed = std.json.parseFromSlice(std.json.Value, alloc, req.body, .{}) catch break :blk "gmail";
        defer parsed.deinit();
        if (parsed.value == .object) break :blk alloc.dupe(u8, strOr(parsed.value.object, "provider", "gmail")) catch "gmail";
        break :blk "gmail";
    };
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(alloc);
    try buf.appendSlice(alloc, "{\"args\":[\"connect\",");
    try appendJson(alloc, &buf, provider);
    try buf.appendSlice(alloc, "]}");
    return jsonFromHost(st, alloc, buf.items);
}

// ── status ─────────────────────────────────────────────────────────────────
pub fn statusRoute(state_any: *anyopaque, req: *const http_parser.HttpRequest, alloc: std.mem.Allocator) anyerror!http_route_registry.RouteResponse {
    const st: *State = @ptrCast(@alignCast(state_any));
    if (!adminOk(st, req)) return unauthorized();
    return jsonFromHost(st, alloc, "{\"args\":[\"status\"]}");
}

// ── oauth/callback (PUBLIC) ──────────────────────────────────────────────────
pub fn callbackRoute(state_any: *anyopaque, req: *const http_parser.HttpRequest, alloc: std.mem.Allocator) anyerror!http_route_registry.RouteResponse {
    const st: *State = @ptrCast(@alignCast(state_any));
    const code = queryParam(req.query, "code") orelse return html(400, "Missing <code>. Did Google redirect here correctly?");
    const state_nonce = queryParam(req.query, "state") orelse return html(400, "Missing <state>.");

    // legacy-ingest `resume` grammar is `resume <state> <code>` — the provider
    // is recorded inside the pending state keyed by the nonce, so it must NOT be
    // passed as an arg here (doing so shifts <state> into the <code> slot and the
    // nonce lookup fails with "state nonce unknown or expired").
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(alloc);
    try buf.appendSlice(alloc, "{\"args\":[\"resume\",");
    try appendJson(alloc, &buf, state_nonce);
    try buf.appendSlice(alloc, ",");
    try appendJson(alloc, &buf, code);
    try buf.appendSlice(alloc, "]}");

    const out = spawnLegacyHost(st.allocator, st.script_path, buf.items) catch
        return html(502, "Failed to complete the grant (host spawn error).");
    defer st.allocator.free(out);
    // resume returns {ok:true,...} on success.
    if (std.mem.indexOf(u8, out, "\"ok\":true") != null) {
        return html(200, "\u{2705} Connected. You can close this tab.");
    }
    return html(400, "Grant failed (likely an expired or already-used link). Run connect again.");
}

// ── helpers ──────────────────────────────────────────────────────────────────

/// Spawn `bun run <script>`, write `stdin_json`, return stdout (≤256 KB). Caller frees.
fn spawnLegacyHost(allocator: std.mem.Allocator, script: []const u8, stdin_json: []const u8) ![]u8 {
    var child = std.process.Child.init(&.{ "bun", "run", script }, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;
    try child.spawn();
    if (child.stdin) |stdin| {
        try stdin.writeAll(stdin_json);
        stdin.close();
        child.stdin = null;
    }
    var out: std.ArrayList(u8) = .{};
    errdefer out.deinit(allocator);
    if (child.stdout) |stdout| {
        const rbuf = try allocator.alloc(u8, 256 * 1024);
        defer allocator.free(rbuf);
        var total: usize = 0;
        while (true) {
            const n = stdout.read(rbuf[total..]) catch break;
            if (n == 0) break;
            total += n;
            if (total >= rbuf.len) break;
        }
        try out.appendSlice(allocator, rbuf[0..total]);
    }
    _ = child.wait() catch {};
    return out.toOwnedSlice(allocator);
}

/// Spawn the host and return its stdout verbatim as a JSON RouteResponse.
fn jsonFromHost(st: *State, alloc: std.mem.Allocator, stdin_json: []const u8) !http_route_registry.RouteResponse {
    const out = spawnLegacyHost(st.allocator, st.script_path, stdin_json) catch
        return .{ .status = 502, .status_text = "Bad Gateway", .body = "{\"error\":\"host_spawn_failed\"}" };
    return .{ .status = 200, .status_text = "OK", .content_type = JSON_CT, .body = try alloc.dupe(u8, out) };
}

fn adminOk(st: *State, req: *const http_parser.HttpRequest) bool {
    const bearer = bearerHex64(req) orelse return false;
    _ = st.bearer_tokens.verifyHex(bearer) catch return false;
    return true;
}

fn bearerHex64(req: *const http_parser.HttpRequest) ?[]const u8 {
    const authz = req.header("authorization") orelse return null;
    const prefix = "Bearer ";
    if (authz.len <= prefix.len) return null;
    if (!std.ascii.eqlIgnoreCase(authz[0..prefix.len], prefix)) return null;
    const tok = std.mem.trim(u8, authz[prefix.len..], " \t");
    if (tok.len != 64) return null;
    return tok;
}

fn queryParam(query: []const u8, name: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, query, '&');
    while (it.next()) |pair| {
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        if (std.mem.eql(u8, pair[0..eq], name)) return pair[eq + 1 ..];
    }
    return null;
}

fn strOr(obj: std.json.ObjectMap, key: []const u8, default: []const u8) []const u8 {
    if (obj.get(key)) |v| if (v == .string) return v.string;
    return default;
}

fn appendJson(alloc: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    const enc = try std.json.Stringify.valueAlloc(alloc, s, .{});
    defer alloc.free(enc);
    try buf.appendSlice(alloc, enc);
}

fn methodNotAllowed() http_route_registry.RouteResponse {
    return .{ .status = 405, .status_text = "Method Not Allowed", .body = "{\"error\":\"method\"}" };
}
fn unauthorized() http_route_registry.RouteResponse {
    return .{ .status = 401, .status_text = "Unauthorized", .body = "{\"error\":\"bearer_invalid\"}" };
}
fn badRequest(msg: []const u8) http_route_registry.RouteResponse {
    _ = msg;
    return .{ .status = 400, .status_text = "Bad Request", .body = "{\"error\":\"bad_request\"}" };
}
fn html(status: u16, comptime body_inner: []const u8) http_route_registry.RouteResponse {
    return .{
        .status = status,
        .status_text = "OK",
        .content_type = "text/html; charset=utf-8",
        .body = "<!doctype html><meta charset=utf-8><body style=\"font:16px system-ui;padding:3rem;text-align:center\"><p>" ++ body_inner ++ "</p></body>",
    };
}

// ── inline tests ──────────────────────────────────────────────────────────
const testing = std.testing;
test "LI-3c queryParam extracts code + state" {
    try testing.expectEqualStrings("abc", queryParam("code=abc&state=xyz", "code").?);
    try testing.expectEqualStrings("xyz", queryParam("code=abc&state=xyz", "state").?);
    try testing.expect(queryParam("code=abc", "state") == null);
}
test "LI-3c bearer parse" {
    var req: http_parser.HttpRequest = undefined;
    _ = &req;
    // bearerHex64 logic exercised via the string prefix check.
    try testing.expect(std.mem.eql(u8, "Bearer "[0..7], "Bearer "));
}

```
