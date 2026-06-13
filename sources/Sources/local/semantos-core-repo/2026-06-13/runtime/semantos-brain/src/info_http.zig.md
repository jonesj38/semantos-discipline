---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/info_http.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.257686+00:00
---

# runtime/semantos-brain/src/info_http.zig

```zig
// D-O5m.followup-6 Phase 2 — `GET /api/v1/info` endpoint.
//
// Reference: this brief.  Mobile + federation peers fetch this
// endpoint post-pairing to discover the brain's mesh substrate
// configuration (shard-proxy URL, brain pin cert + pubkey, server
// version).  The shard-proxy URL is the load-bearing field — if
// present, the mobile shell builds a [ShardProxyMeshTransport]; if
// absent, it falls back to HTTP-REPL.
//
// ─── Wire shape ──────────────────────────────────────────────────────
//
//   GET /api/v1/info
//     Authorization: Bearer <hex64>      (helm session bearer)
//
//   Success (200):
//     {
//       "shard_proxy_endpoint": "https://shard.example.com" | null,
//       "shard_group_id": "tenant-acme.example.com" | "",
//       "brain_pin_cert_id": "<32-hex>",
//       "brain_pin_pubkey": "<66-hex compressed-SEC1>",
//       "server_version": "brain 0.1.0",
//       "theme": {                                   // D-O5.followup-6
//         "primary_hex": "#4F46E5",
//         "accent_hex": "#10B981",
//         "logo_url": "/logo.svg" | null,
//         "font_family": "system" | "serif" | ...,
//         "mode": "light" | "dark" | "auto"
//       }
//     }
//
//   401 → {"error":"unauthorised"}
//
// The endpoint is bearer-gated so a casual scanner can't enumerate
// shard-proxy URLs.  When the [mesh] section is absent in the tenant
// manifest, `shard_proxy_endpoint` is `null` and `shard_group_id` is
// the empty string — mobile sees these and skips the mesh path.
//
// Brain pin fields surface the operator's root cert id + pubkey so
// the mobile pairing flow's TOFU pin check can be re-asserted out-of-
// band (the device pair already pinned these during initial pairing,
// but post-#316 the helm UI surfaces them in a "verify your brain"
// view).
//
// D-O5.followup-6 — `theme` block.  Both helms (loom-svelte desktop
// + oddjobz-mobile Flutter) read the resolved theme post-pairing so
// they can render the operator's brand colors / logo / font / mode
// preference.  When `[theme]` is absent in the tenant manifest, the
// brain substitutes the canonical defaults inline (the wire contract
// is the single source of truth — clients don't ship their own
// defaults).  `logo_url` is JSON null when no logo is configured;
// every other field is always a string.
//
// D-O5.followup-8 — `hat` block.  The multi-hat helm (D-O5.followup-8
// loom-svelte side) needs to know which hat a bearer is acting under
// so the HatSwitcher can populate `hatName` / `hatId` / `certId` on
// first add (instead of stubbing the legacy migration values).  The
// handler resolves the calling bearer's TokenRecord via
// `bearer_tokens.verifyHex`, then surfaces:
//   • `hat.id`        — bearer's TokenRecord id (32-hex), the
//                       stable "which hat issued this call" key
//   • `hat.name`      — bearer's TokenRecord label, the operator-
//                       supplied display name (e.g. "Todd (tradie)")
//   • `hat.cert_id`   — the cert id this bearer was minted under,
//                       when the Semantos Brain deploy plumbs it through; empty
//                       for legacy `brain bearer issue` paths that
//                       don't yet carry cert linkage
// The full bearer→cert→cert.hat_id pipeline waits on D-O5p / D-O11
// federation work; this PR ships the wire shape so the helm-side
// HatSwitcher can populate its display fields today.  Anonymous /
// missing-bearer responses (the 401 path) emit no hat block.

const std = @import("std");
const bearer_tokens = @import("bearer_tokens");
const tenant_manifest = @import("tenant_manifest");

pub const Error = error{
    out_of_memory,
    write_failed,
};

pub const ROUTE_PATH = "/api/v1/info";

/// CC2b — one entry of the Brain→PWA cartridge-discovery list. The PWA
/// shell reads this from GET /api/v1/info to learn which cartridges
/// the Brain serves + which Flutter package renders each (the C3
/// binding). Populated by cmdServe from `enumerateUserInstalled`.
/// SH1-B (svelte-helm matrix; DECISION D9, revised D3) — one declarative
/// UI verb surfaced to the web helm so it renders DO|TALK|FIND from the
/// manifest. Form-factor-agnostic; rendering stays per-helm. Borrowed
/// strings (the serve-time CartridgeInfo slice is process-lifetime).
pub const UiVerb = struct {
    modal: []const u8,
    label: []const u8,
    intent_type: []const u8,
    subtitle: []const u8 = "",
    icon: []const u8 = "",
    /// SH14 / D12 — hat role: "operator" (default) | "admin". The helm's
    /// Dock filters by the active hat role.
    role: []const u8 = "operator",
};

pub const CartridgeInfo = struct {
    id: []const u8,
    role: []const u8 = "",
    experience_package: []const u8 = "",
    /// SH1-B — declarative UI layer. `surfacing_mode` is "" when the
    /// cartridge declares none (the helm treats absent as "default").
    /// `ui_verbs` is the cartridge's verb vocabulary; empty for
    /// UI-less / data-only cartridges.
    surfacing_mode: []const u8 = "",
    ui_verbs: []const UiVerb = &[_]UiVerb{},
};

pub const Acceptor = struct {
    allocator: std.mem.Allocator,
    bearer_tokens: *bearer_tokens.TokenStore,
    /// CC2b — cartridges this Brain serves (id/role/experience).
    /// Borrowed; lifetime managed by cmdServe. Empty = none surfaced.
    cartridges: []const CartridgeInfo = &[_]CartridgeInfo{},
    /// Shard-proxy endpoint URL.  Empty when [mesh] is absent in the
    /// manifest.  The wire form treats empty as JSON null.
    shard_proxy_endpoint: []const u8 = "",
    shard_group_id: []const u8 = "",
    /// Brain pin — the operator's root cert id (32 hex chars).
    brain_pin_cert_id: []const u8 = "",
    /// Brain pin — the operator's root cert pubkey (66 hex chars).
    brain_pin_pubkey_hex: []const u8 = "",
    /// Server version string the operator surfaces, e.g. "brain 0.1.0".
    server_version: []const u8 = "brain-unknown",
    // ── D-O5.followup-6 — per-tenant theme ────────────────────────
    /// Resolved theme — typically `manifest.resolvedTheme()`.  When
    /// every field is empty (the zero value) the handler substitutes
    /// the canonical defaults from `tenant_manifest`, so callers that
    /// haven't wired theming up still emit a valid wire-shape.
    theme: tenant_manifest.ResolvedTheme = .{
        .primary_hex = "",
        .accent_hex = "",
        .logo_url = "",
        .font_family = "",
        .mode = "",
    },
};

pub const InfoResult = struct {
    body: []u8,
    status: std.http.Status,

    pub fn deinit(self: *InfoResult, allocator: std.mem.Allocator) void {
        if (self.body.len > 0) {
            allocator.free(self.body);
            self.body = &.{};
        }
    }
};

/// Pure-logic handler — bearer must be valid; emits the JSON body.
/// Tests drive this directly without standing up an HTTP server.
pub fn handle(
    acceptor: *const Acceptor,
    bearer_hex: ?[]const u8,
) Error!InfoResult {
    const bearer = bearer_hex orelse {
        const body = std.fmt.allocPrint(
            acceptor.allocator,
            "{{\"error\":\"unauthorised\"}}",
            .{},
        ) catch return Error.out_of_memory;
        return .{ .body = body, .status = .unauthorized };
    };
    // D-O5.followup-8 — capture the TokenRecord so the `hat` block
    // can surface the bearer's id + label.  When brain later wires the
    // bearer→cert linkage (D-O11) the cert id rides through the same
    // record.  For today's bearers, `bearer_record.label` is the
    // operator-supplied name from `brain bearer issue --label`.
    const bearer_record = acceptor.bearer_tokens.verifyHex(bearer) catch {
        const body = std.fmt.allocPrint(
            acceptor.allocator,
            "{{\"error\":\"unauthorised\"}}",
            .{},
        ) catch return Error.out_of_memory;
        return .{ .body = body, .status = .unauthorized };
    };

    // Build the body manually so the JSON null vs string distinction
    // for shard_proxy_endpoint is preserved (the wire contract is
    // load-bearing on the mobile factory selecting the fallback path).
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(acceptor.allocator);

    buf.append(acceptor.allocator, '{') catch return Error.out_of_memory;
    buf.appendSlice(acceptor.allocator, "\"shard_proxy_endpoint\":") catch return Error.out_of_memory;
    if (acceptor.shard_proxy_endpoint.len == 0) {
        buf.appendSlice(acceptor.allocator, "null") catch return Error.out_of_memory;
    } else {
        buf.append(acceptor.allocator, '"') catch return Error.out_of_memory;
        appendJsonEscaped(&buf, acceptor.allocator, acceptor.shard_proxy_endpoint) catch return Error.out_of_memory;
        buf.append(acceptor.allocator, '"') catch return Error.out_of_memory;
    }
    buf.appendSlice(acceptor.allocator, ",\"shard_group_id\":\"") catch return Error.out_of_memory;
    appendJsonEscaped(&buf, acceptor.allocator, acceptor.shard_group_id) catch return Error.out_of_memory;
    buf.appendSlice(acceptor.allocator, "\",\"brain_pin_cert_id\":\"") catch return Error.out_of_memory;
    appendJsonEscaped(&buf, acceptor.allocator, acceptor.brain_pin_cert_id) catch return Error.out_of_memory;
    buf.appendSlice(acceptor.allocator, "\",\"brain_pin_pubkey\":\"") catch return Error.out_of_memory;
    appendJsonEscaped(&buf, acceptor.allocator, acceptor.brain_pin_pubkey_hex) catch return Error.out_of_memory;
    buf.appendSlice(acceptor.allocator, "\",\"server_version\":\"") catch return Error.out_of_memory;
    appendJsonEscaped(&buf, acceptor.allocator, acceptor.server_version) catch return Error.out_of_memory;

    // ── D-O5.followup-6 — `theme` block ─────────────────────────────
    // Resolve every field to the operator's value or the canonical
    // default (so clients don't need to know defaults).  `logo_url`
    // is JSON null when no logo is configured; every other field is
    // a string.
    const primary = if (acceptor.theme.primary_hex.len > 0)
        acceptor.theme.primary_hex
    else
        tenant_manifest.THEME_DEFAULT_PRIMARY;
    const accent = if (acceptor.theme.accent_hex.len > 0)
        acceptor.theme.accent_hex
    else
        tenant_manifest.THEME_DEFAULT_ACCENT;
    const font = if (acceptor.theme.font_family.len > 0)
        acceptor.theme.font_family
    else
        tenant_manifest.THEME_DEFAULT_FONT_FAMILY;
    const mode = if (acceptor.theme.mode.len > 0)
        acceptor.theme.mode
    else
        tenant_manifest.THEME_DEFAULT_MODE;

    buf.appendSlice(acceptor.allocator, "\",\"theme\":{\"primary_hex\":\"") catch return Error.out_of_memory;
    appendJsonEscaped(&buf, acceptor.allocator, primary) catch return Error.out_of_memory;
    buf.appendSlice(acceptor.allocator, "\",\"accent_hex\":\"") catch return Error.out_of_memory;
    appendJsonEscaped(&buf, acceptor.allocator, accent) catch return Error.out_of_memory;
    buf.appendSlice(acceptor.allocator, "\",\"logo_url\":") catch return Error.out_of_memory;
    if (acceptor.theme.logo_url.len == 0) {
        buf.appendSlice(acceptor.allocator, "null") catch return Error.out_of_memory;
    } else {
        buf.append(acceptor.allocator, '"') catch return Error.out_of_memory;
        appendJsonEscaped(&buf, acceptor.allocator, acceptor.theme.logo_url) catch return Error.out_of_memory;
        buf.append(acceptor.allocator, '"') catch return Error.out_of_memory;
    }
    buf.appendSlice(acceptor.allocator, ",\"font_family\":\"") catch return Error.out_of_memory;
    appendJsonEscaped(&buf, acceptor.allocator, font) catch return Error.out_of_memory;
    buf.appendSlice(acceptor.allocator, "\",\"mode\":\"") catch return Error.out_of_memory;
    appendJsonEscaped(&buf, acceptor.allocator, mode) catch return Error.out_of_memory;
    buf.appendSlice(acceptor.allocator, "\"}") catch return Error.out_of_memory;

    // ── D-O5.followup-8 — `hat` block ────────────────────────────────
    // The bearer that authenticated this call corresponds to one
    // hat — surface its id + label so the helm-side HatSwitcher can
    // populate display fields without stubbing.  `cert_id` is empty
    // until D-O11 wires bearer→cert linkage; helms tolerate the
    // empty value (HatSwitcher renders the label + id only).
    buf.appendSlice(acceptor.allocator, ",\"hat\":{\"id\":\"") catch return Error.out_of_memory;
    appendJsonEscaped(&buf, acceptor.allocator, &bearer_record.id) catch return Error.out_of_memory;
    buf.appendSlice(acceptor.allocator, "\",\"name\":\"") catch return Error.out_of_memory;
    appendJsonEscaped(&buf, acceptor.allocator, bearer_record.label) catch return Error.out_of_memory;
    buf.appendSlice(acceptor.allocator, "\",\"cert_id\":\"") catch return Error.out_of_memory;
    // cert_id is empty for today's bearer-only path.  Future PR
    // (D-O11 federation) plumbs the cert this bearer was minted
    // under and surfaces it here.  Empty string is the wire
    // contract for "no cert linkage yet" — distinguishes from a
    // missing field a future schema rev might add.
    // SH14 / D12 — the hat's role (operator | admin) from its bearer token.
    // The helm gates the verb shelf by this (operator=base, admin=+managerial).
    buf.appendSlice(acceptor.allocator, "\",\"role\":\"") catch return Error.out_of_memory;
    appendJsonEscaped(&buf, acceptor.allocator, bearer_record.role) catch return Error.out_of_memory;
    // close role string + hat object (root still open).
    buf.appendSlice(acceptor.allocator, "\"}") catch return Error.out_of_memory;

    // ── CC2b — `cartridges` discovery array ─────────────────────────
    // The PWA shell renders against this: which cartridges the Brain
    // serves, their role, and the Flutter package (C3 binding).
    buf.appendSlice(acceptor.allocator, ",\"cartridges\":[") catch return Error.out_of_memory;
    for (acceptor.cartridges, 0..) |c, i| {
        if (i > 0) buf.append(acceptor.allocator, ',') catch return Error.out_of_memory;
        buf.appendSlice(acceptor.allocator, "{\"id\":\"") catch return Error.out_of_memory;
        appendJsonEscaped(&buf, acceptor.allocator, c.id) catch return Error.out_of_memory;
        buf.appendSlice(acceptor.allocator, "\",\"role\":\"") catch return Error.out_of_memory;
        appendJsonEscaped(&buf, acceptor.allocator, c.role) catch return Error.out_of_memory;
        buf.appendSlice(acceptor.allocator, "\",\"experiencePackage\":\"") catch return Error.out_of_memory;
        appendJsonEscaped(&buf, acceptor.allocator, c.experience_package) catch return Error.out_of_memory;
        // SH1-B — declarative UI layer (DECISION D9). surfacingMode + the
        // cartridge's verb vocabulary; the web helm renders DO|TALK|FIND
        // from these. Empty surfacingMode ⇒ helm treats as "default".
        buf.appendSlice(acceptor.allocator, "\",\"surfacingMode\":\"") catch return Error.out_of_memory;
        appendJsonEscaped(&buf, acceptor.allocator, c.surfacing_mode) catch return Error.out_of_memory;
        buf.appendSlice(acceptor.allocator, "\",\"verbs\":[") catch return Error.out_of_memory;
        for (c.ui_verbs, 0..) |v, vi| {
            if (vi > 0) buf.append(acceptor.allocator, ',') catch return Error.out_of_memory;
            buf.appendSlice(acceptor.allocator, "{\"modal\":\"") catch return Error.out_of_memory;
            appendJsonEscaped(&buf, acceptor.allocator, v.modal) catch return Error.out_of_memory;
            buf.appendSlice(acceptor.allocator, "\",\"label\":\"") catch return Error.out_of_memory;
            appendJsonEscaped(&buf, acceptor.allocator, v.label) catch return Error.out_of_memory;
            buf.appendSlice(acceptor.allocator, "\",\"intentType\":\"") catch return Error.out_of_memory;
            appendJsonEscaped(&buf, acceptor.allocator, v.intent_type) catch return Error.out_of_memory;
            buf.appendSlice(acceptor.allocator, "\",\"subtitle\":\"") catch return Error.out_of_memory;
            appendJsonEscaped(&buf, acceptor.allocator, v.subtitle) catch return Error.out_of_memory;
            buf.appendSlice(acceptor.allocator, "\",\"icon\":\"") catch return Error.out_of_memory;
            appendJsonEscaped(&buf, acceptor.allocator, v.icon) catch return Error.out_of_memory;
            buf.appendSlice(acceptor.allocator, "\",\"role\":\"") catch return Error.out_of_memory;
            appendJsonEscaped(&buf, acceptor.allocator, v.role) catch return Error.out_of_memory;
            buf.appendSlice(acceptor.allocator, "\"}") catch return Error.out_of_memory;
        }
        buf.appendSlice(acceptor.allocator, "]}") catch return Error.out_of_memory;
    }
    buf.appendSlice(acceptor.allocator, "]}") catch return Error.out_of_memory;

    const owned = buf.toOwnedSlice(acceptor.allocator) catch return Error.out_of_memory;
    return .{ .body = owned, .status = .ok };
}

/// Plug into `site_server.handleRequest`.  Returns true iff matched +
/// handled.  Reserved BEFORE route lookup so an operator's site config
/// can't shadow it.
pub fn maybeHandle(
    request: *std.http.Server.Request,
    acceptor: *const Acceptor,
) Error!bool {
    const target = request.head.target;
    const method = request.head.method;
    if (!std.mem.eql(u8, target, ROUTE_PATH)) return false;

    if (method != .GET) {
        try respondJson(request, .method_not_allowed,
            "{\"error\":\"method_not_allowed\",\"hint\":\"GET required\"}");
        return true;
    }

    const bearer = bearerFromHeaders(request);
    var result = try handle(acceptor, bearer);
    defer result.deinit(acceptor.allocator);
    try respondJson(request, result.status, result.body);
    return true;
}

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

fn appendJsonEscaped(
    buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    s: []const u8,
) !void {
    // Minimal JSON escape — covers " \ control chars.  v0.1 inputs
    // are operator-supplied ASCII (URL, hex strings, semver), so the
    // common case is a no-op pass-through.
    for (s) |c| {
        switch (c) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            else => |b| {
                if (b < 0x20) {
                    var hex_buf: [6]u8 = undefined;
                    const slice = std.fmt.bufPrint(&hex_buf, "\\u{x:0>4}", .{b}) catch unreachable;
                    try buf.appendSlice(allocator, slice);
                } else {
                    try buf.append(allocator, b);
                }
            },
        }
    }
}

fn bearerFromHeaders(request: *std.http.Server.Request) ?[]const u8 {
    const auth = headerValue(request, "authorization") orelse return null;
    const prefix = "Bearer ";
    const lower_prefix = "bearer ";
    if (std.mem.startsWith(u8, auth, prefix)) return auth[prefix.len..];
    if (std.mem.startsWith(u8, auth, lower_prefix)) return auth[lower_prefix.len..];
    return null;
}

fn headerValue(request: *std.http.Server.Request, name: []const u8) ?[]const u8 {
    var it = request.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
    }
    return null;
}

fn respondJson(request: *std.http.Server.Request, status: std.http.Status, body: []const u8) Error!void {
    request.respond(body, .{
        .status = status,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
            .{ .name = "cache-control", .value = "no-store" },
        },
    }) catch return Error.write_failed;
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — pure-logic body shapes.  Full HTTP-roundtrip lives
// in tests/info_http_test.zig.
// ─────────────────────────────────────────────────────────────────────

test "appendJsonEscaped passes through ASCII unchanged" {
    const allocator = std.testing.allocator;
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try appendJsonEscaped(&buf, allocator, "https://shard.example.com");
    try std.testing.expectEqualStrings("https://shard.example.com", buf.items);
}

test "appendJsonEscaped escapes quotes + backslash" {
    const allocator = std.testing.allocator;
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try appendJsonEscaped(&buf, allocator, "a\"b\\c");
    try std.testing.expectEqualStrings("a\\\"b\\\\c", buf.items);
}

```
