---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cors.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.221981+00:00
---

# runtime/semantos-brain/src/cors.zig

```zig
// D-W1 Phase 3 — CORS / OPTIONS preflight helper.
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §5.3 + §8 Phase 3,
// closes brain issue #273.
//
// The site_server hands every incoming request to `prepare()` once, before
// route lookup.  The returned `Cors` value holds the per-request CORS
// state — matched origin (or null if disallowed / no Origin header set),
// pre-rendered comma-joined methods + headers strings, plus the configured
// max-age + credentials policy.
//
// Two output shapes:
//   - `optionsHeaders()` — full preflight response: ACAO + ACAM + ACAH +
//     ACMA (+ ACAC when configured).  Used for the OPTIONS short-circuit
//     at the top of handleRequest.
//   - `responseHeaders()` — actual-response shape: ACAO (+ ACAC when
//     configured).  Browsers don't need the Methods/Headers list on a
//     non-preflight response, so we keep it small.
//
// Both shapes return zero headers when:
//   - the request had no Origin header (same-origin call, no preflight,
//     no ACAO needed), OR
//   - the configured allowlist doesn't match the request's Origin (the
//     browser then blocks the response in JS).

const std = @import("std");
const site_config = @import("site_config");

/// Per-request CORS state.  Populated once at the top of handleRequest;
/// passed by value (small POD) through serve* helpers.
pub const Cors = struct {
    /// The value to echo in `Access-Control-Allow-Origin`.  Null when
    /// the request had no Origin header OR the configured allowlist
    /// doesn't match.  Browsers treat absence as "block".  Either the
    /// configured origin (exact match) or the literal `"*"` wildcard.
    allow_origin: ?[]const u8 = null,
    /// Comma-joined `Access-Control-Allow-Methods` value rendered into
    /// the per-request buffer.  Slice into `methods_buf`.
    methods: []const u8 = "",
    /// Comma-joined `Access-Control-Allow-Headers` value rendered into
    /// the per-request buffer.  Slice into `headers_buf`.
    headers: []const u8 = "",
    /// `Access-Control-Max-Age` rendered as a decimal string.  Slice
    /// into `max_age_buf`.
    max_age: []const u8 = "",
    /// Whether to emit `Access-Control-Allow-Credentials: true`.
    allow_credentials: bool = false,
    /// Optional `Content-Security-Policy` header value (Tier 2).  Empty
    /// = no CSP header.  Borrowed from site_config; lives the request's
    /// lifetime.
    csp: []const u8 = "",

    /// Backing storage for the rendered values.  The `Cors` struct
    /// borrows slices into these; they must outlive the struct.
    pub const Buffers = struct {
        methods: [256]u8 = undefined,
        headers: [256]u8 = undefined,
        max_age: [16]u8 = undefined,
    };

    /// Inspect the request, match its Origin against the site's CORS
    /// allowlist, and render the response-header strings into `bufs`.
    /// Returns a Cors value whose slices borrow from `bufs`.
    pub fn prepare(
        request: *std.http.Server.Request,
        cfg: *const site_config.SiteConfig,
        bufs: *Buffers,
    ) Cors {
        const origin = headerValue(request, "origin");
        return prepareFromOrigin(origin, cfg, bufs);
    }

    /// Reactor variant of prepare() — takes the Origin header value
    /// directly instead of a *std.http.Server.Request.  Identical logic;
    /// factored out so the reactor path can call it without depending on
    /// the blocking stdlib HTTP type.
    pub fn prepareFromOrigin(
        origin: ?[]const u8,
        cfg: *const site_config.SiteConfig,
        bufs: *Buffers,
    ) Cors {
        if (origin == null) return .{ .csp = cfg.content_security_policy };
        const matched = cfg.matchCorsOrigin(origin.?);
        if (matched == null) return .{ .csp = cfg.content_security_policy };

        const methods_str = joinComma(&bufs.methods, cfg.cors_allowed_methods);
        const headers_str = joinComma(&bufs.headers, cfg.cors_allowed_headers);
        const max_age_str = std.fmt.bufPrint(&bufs.max_age, "{d}", .{cfg.cors_max_age_seconds}) catch "0";

        return .{
            .allow_origin = matched,
            .methods = methods_str,
            .headers = headers_str,
            .max_age = max_age_str,
            .allow_credentials = cfg.cors_allow_credentials,
            .csp = cfg.content_security_policy,
        };
    }

    /// Build the headers for an OPTIONS preflight response.  Caller
    /// passes a fixed-capacity buffer (5-7 slots is plenty); this fills
    /// the prefix + returns the populated subslice.
    pub fn optionsHeaders(self: Cors, slots: []std.http.Header) []const std.http.Header {
        var n: usize = 0;
        if (self.allow_origin) |ao| {
            slots[n] = .{ .name = "access-control-allow-origin", .value = ao };
            n += 1;
            slots[n] = .{ .name = "access-control-allow-methods", .value = self.methods };
            n += 1;
            slots[n] = .{ .name = "access-control-allow-headers", .value = self.headers };
            n += 1;
            slots[n] = .{ .name = "access-control-max-age", .value = self.max_age };
            n += 1;
            // The Vary header is best-practice on responses whose body
            // varies by Origin.  Prevents a same-origin response cached
            // by an upstream proxy from being reused for a cross-origin
            // request (and vice versa).
            slots[n] = .{ .name = "vary", .value = "Origin" };
            n += 1;
            if (self.allow_credentials) {
                slots[n] = .{ .name = "access-control-allow-credentials", .value = "true" };
                n += 1;
            }
        }
        if (self.csp.len > 0 and n < slots.len) {
            slots[n] = .{ .name = "content-security-policy", .value = self.csp };
            n += 1;
        }
        return slots[0..n];
    }

    /// Build the headers for a non-OPTIONS response (the cross-origin
    /// caller's actual GET / POST etc.).  ACAO + Vary + optional ACAC
    /// + optional CSP — no Methods/Headers/Max-Age (those are preflight-
    /// only per the CORS spec).
    pub fn responseHeaders(self: Cors, slots: []std.http.Header) []const std.http.Header {
        var n: usize = 0;
        if (self.allow_origin) |ao| {
            slots[n] = .{ .name = "access-control-allow-origin", .value = ao };
            n += 1;
            slots[n] = .{ .name = "vary", .value = "Origin" };
            n += 1;
            if (self.allow_credentials) {
                slots[n] = .{ .name = "access-control-allow-credentials", .value = "true" };
                n += 1;
            }
        }
        if (self.csp.len > 0 and n < slots.len) {
            slots[n] = .{ .name = "content-security-policy", .value = self.csp };
            n += 1;
        }
        return slots[0..n];
    }

    /// Combine the CORS response headers with a route-specific `extra`
    /// list (e.g. content-type, set-cookie) into the caller-supplied
    /// buffer.  Caller sizes `out` ≥ `extra.len + 5`.
    pub fn merge(
        self: Cors,
        out: []std.http.Header,
        extra: []const std.http.Header,
    ) []const std.http.Header {
        var n: usize = 0;
        for (extra) |h| {
            out[n] = h;
            n += 1;
        }
        const cors_slice = self.responseHeaders(out[n..]);
        return out[0 .. n + cors_slice.len];
    }
};

fn joinComma(buf: []u8, parts: []const []const u8) []const u8 {
    var w = std.Io.Writer.fixed(buf);
    var first = true;
    for (parts) |p| {
        if (!first) {
            _ = w.writeAll(", ") catch return buf[0..w.end];
        }
        _ = w.writeAll(p) catch return buf[0..w.end];
        first = false;
    }
    return buf[0..w.end];
}

fn headerValue(request: *std.http.Server.Request, name: []const u8) ?[]const u8 {
    var it = request.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
    }
    return null;
}

// ─────────────────────────────────────────────────────────────────────
// Tests — exercise the pure helpers (joinComma + matchCorsOrigin
// behaviour via Cors.prepare).  Full request roundtrip lives in
// tests/cors_conformance.zig.
// ─────────────────────────────────────────────────────────────────────

test "cors: joinComma renders a single value without trailing separator" {
    var buf: [32]u8 = undefined;
    const out = joinComma(&buf, &.{"GET"});
    try std.testing.expectEqualStrings("GET", out);
}

test "cors: joinComma renders multiple values separated by ', '" {
    var buf: [64]u8 = undefined;
    const out = joinComma(&buf, &.{ "GET", "POST", "OPTIONS" });
    try std.testing.expectEqualStrings("GET, POST, OPTIONS", out);
}

test "cors: joinComma handles an empty list" {
    var buf: [16]u8 = undefined;
    const out = joinComma(&buf, &.{});
    try std.testing.expectEqualStrings("", out);
}

```
