---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/site_config.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.217334+00:00
---

# runtime/semantos-brain/src/site_config.zig

```zig
// Phase WSITE1 — Site config schema + parser.
//
// Reference: docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md §3 (WSITE1).
//
// Operator declares a website's routes + content + (eventually) auth gates
// in a JSON file at `~/.semantos/sites/<domain>/site.json`.  v0.1 ships
// JSON to match the rest of the Semantos Brain config surface; the spec calls for
// TOML and a port can land in WSITE1.5 without breaking consumers.
//
// Schema:
//
//     {
//       "site": {
//         "domain":       "pokerapp.example.com",
//         "content_root": "./public",
//         "listen_port":  8080
//       },
//       "routes": {
//         "/":         { "type": "static",  "file": "index.html", "public": true },
//         "/play":     { "type": "dynamic", "handler": "game.wasm",
//                        "auth": "identity_required" },
//         "/premium":  { "type": "static",  "file": "premium.html",
//                        "auth": "payment_required", "price_sats": 5000 }
//       }
//     }
//
// **Scope decisions for v0.1**:
//
//   • Static routes shipping; dynamic-route handlers are recognised as a
//     declared shape but their actual WASM-handler instantiation defers
//     to WSITE2.5+ (needs a per-handler instance lifecycle on the broker
//     side, not yet wired).
//
//   • `auth` field is parsed and stored, but the actual challenge
//     issuance is WSITE3.  v0.1 routes default to public; non-public
//     routes return 501 Not Implemented from the server with a pointer
//     to the WSITE3 work.
//
//   • The site-config cell signature (admin's wallet signs the config
//     per §6.3) is reserved for WSITE1.5 alongside the broker identity
//     bootstrap.  The schema shape includes the field so its absence is
//     surfaced as "unsigned (WSITE1.5)" in `brain site validate`.

const std = @import("std");

pub const ConfigError = error{
    parse_failed,
    schema_mismatch,
    invalid_route_type,
    invalid_auth_kind,
    invalid_cors_config,
    out_of_memory,
};

/// D-W1 Phase 3 — defaults for `Access-Control-Allow-Methods` covering
/// every verb the existing brain routes use (GET/POST/OPTIONS).  Static
/// arrays so a default-constructed `SiteConfig` doesn't need to allocate.
const default_cors_methods = [_][]const u8{ "GET", "POST", "OPTIONS" };

/// D-W1 Phase 3 — defaults for `Access-Control-Allow-Headers`.  Covers
/// the headers every existing brain client (helm SPA + curl smoke tests)
/// already sets.  See `SiteConfig.cors_allowed_headers` doc.
const default_cors_headers = [_][]const u8{ "authorization", "content-type", "x-requested-with" };

pub const RouteType = enum {
    static,
    dynamic,
    /// D-O5 / brain issue #274 — serve a whole directory tree as a single
    /// route.  Path traversal is rejected at the dispatch layer; unknown
    /// paths under the prefix fall through to `spa_fallback` so a
    /// client-side router (e.g. the helm Svelte SPA) takes over.  Schema:
    ///
    ///     "/helm/": {
    ///       "type": "directory",
    ///       "root": "./public/helm",
    ///       "spa_fallback": "index.html",
    ///       "auth": "identity_required"
    ///     }
    ///
    /// The `path` of a directory route MUST end in `/` — that's how
    /// dispatch knows to do a prefix match.  Dispatch reads
    /// `<root>/<rest>` where `rest` is the URL path with the route's
    /// prefix stripped; an empty `rest` (i.e. exactly the prefix) reads
    /// `<root>/<spa_fallback>`.
    directory,
    /// D-O6a — public chat v0.5 passthrough route.  The route's handler
    /// is brain-native (`chat_http.zig`); the operator does not supply a
    /// WASM blob.  Visitor POSTs are dispatched into `dispatcher.dispatch
    /// (llm.complete, scope=<route.scope>, system_prompt=<route.system_
    /// prompt>, prompt=<body.message>)` with `auth = .anonymous` +
    /// `capabilities = CapabilitySet.fromList(SiteConfig.anonymous_caps)`.
    /// See ODDJOBZ-EXTENSION-PLAN.md §O6 + BRAIN-DISPATCHER-UNIFICATION.md
    /// §3 line 182, §11 line ~428.
    chat,
    /// D-O7 — spawns a Bun subprocess per request to run the TypeScript
    /// handleConversationTurn pipeline.  Wire protocol: BRAIN writes
    /// `{ "message": "...", "session_id": "...", "data_dir": "..." }` to
    /// stdin; the script writes `{ "reply": "...", "action": {...},
    /// "done": false }` to stdout.  No persistent sidecar — one subprocess
    /// per request.  Acceptable for personal-scale sovereign nodes.
    intake,
    /// S10a (Semantos Sites 1.0) — operator-profile-driven site renderer.
    /// GET / or GET /index.html on a BYOD domain → load
    /// `$data_dir/sites/<domain>/profile.json` → renderSite → HTML.
    /// The handler is brain-native (operator_site_renderer.zig); the
    /// operator supplies a profile.json, not a WASM blob.  No site.json
    /// route config is needed beyond declaring this route type.
    operator_home,

    pub fn fromStr(s: []const u8) ?RouteType {
        if (std.mem.eql(u8, s, "static")) return .static;
        if (std.mem.eql(u8, s, "dynamic")) return .dynamic;
        if (std.mem.eql(u8, s, "directory")) return .directory;
        if (std.mem.eql(u8, s, "chat")) return .chat;
        if (std.mem.eql(u8, s, "intake")) return .intake;
        if (std.mem.eql(u8, s, "operator_home")) return .operator_home;
        return null;
    }
};

pub const AuthKind = enum {
    public,
    identity_required,
    payment_required,

    pub fn fromStr(s: []const u8) ?AuthKind {
        if (std.mem.eql(u8, s, "public")) return .public;
        if (std.mem.eql(u8, s, "identity_required")) return .identity_required;
        if (std.mem.eql(u8, s, "payment_required")) return .payment_required;
        return null;
    }

    pub fn label(self: AuthKind) []const u8 {
        return switch (self) {
            .public => "public",
            .identity_required => "identity_required",
            .payment_required => "payment_required",
        };
    }
};

pub const Route = struct {
    /// URL path, e.g. "/" or "/api/score".
    path: []const u8,
    kind: RouteType,
    /// For static routes: file relative to `content_root`. Empty for dynamic.
    file: []const u8 = "",
    /// For dynamic routes: WASM handler filename relative to
    /// `<sites_dir>/<domain>/handlers/`.  Empty for static.
    handler: []const u8 = "",
    /// WSITE2.5 — SHA-256 of the handler WASM file (raw bytes, not
    /// base64).  Required for `type: "dynamic"`.  Mirrors the
    /// trust-anchor pattern from `brain start` — the operator runs
    /// `brain hash <wasm_file>` once and pastes the result into
    /// `handler_sha256`.  All-zero ⇒ unset (refuses to load).
    handler_sha256: [32]u8 = [_]u8{0} ** 32,
    handler_sha256_set: bool = false,
    auth: AuthKind = .public,
    /// price_sats applies only when auth == .payment_required.
    price_sats: u64 = 0,
    /// Per-route session TTL override.  0 falls through to
    /// SiteConfig.session_ttl_seconds.
    session_ttl_seconds: u32 = 0,
    /// payment_recipient (compressed SEC1 pubkey, 33 bytes) — falls
    /// through to SiteConfig.payment_recipient when zero. Required
    /// for auth = .payment_required. Surfaced in the X-Semantos-
    /// Recipient challenge header so payers know where to send funds.
    payment_recipient: [33]u8 = [_]u8{0} ** 33,
    /// Whether this route's payment_recipient is set (independent of
    /// the bytes value, since [33]u8 always has 33 bytes).
    payment_recipient_set: bool = false,
    /// WSITE5 — per-route OutputStore basket name.  When set, verified
    /// payments to this route are filed into the named basket instead of
    /// the default.  Useful for separating revenue streams (e.g.
    /// `output_basket = "premium-feed"` vs `"comments"`).  Empty falls
    /// through to "default".
    output_basket: []const u8 = "",
    /// D-O5 — for `RouteType.directory`: filesystem path (relative to
    /// the Semantos Brain process CWD, or absolute) under which the SPA bundle's
    /// files live.  Empty for non-directory routes.
    root: []const u8 = "",
    /// D-O5 — for `RouteType.directory`: file inside `root` to serve
    /// when the URL does not match a real file (or the URL is exactly
    /// the route prefix).  Lets a single-page-app's client-side router
    /// take over for any path under the prefix.  Defaults to
    /// `index.html` at parse time when unset on a directory route.
    spa_fallback: []const u8 = "",
    /// D-O6a — for `kind == .chat` routes.  Scope name forwarded to
    /// `llm.complete` as the per-scope rate-limit / token-budget bucket
    /// AND used to derive the required cap (`cap.llm.complete:<scope>`).
    /// Example: `"anonymous-oddjobz"`.  Empty = invalid for chat routes
    /// (validate fails).
    chat_scope: []const u8 = "",
    /// D-O6a — tenant-configured system prompt prepended to every
    /// visitor message before dispatch.  Empty = no system prompt
    /// (the LLM gets the visitor message verbatim).  Operator-supplied
    /// — keep mindful of legal/pricing commitments per the deliverables
    /// note.
    chat_system_prompt: []const u8 = "",
    /// D-O6a — defensive cap on the visitor's `message` field length
    /// in chars.  0 = use the chat_http.DEFAULT_MAX_MESSAGE_CHARS
    /// fallback.  Body too large → HTTP 413.
    chat_max_message_chars: u32 = 0,
    /// D-O7 — for `kind == .intake` routes.  Absolute path (or relative to
    /// the site's handlers dir) to the Bun script that wraps
    /// handleConversationTurn.  Required for intake routes.
    intake_script: []const u8 = "",
    /// D-O7 — cap on the visitor's message field. 0 = use DEFAULT (4000).
    intake_max_message_chars: u32 = 0,
};

pub const SiteConfig = struct {
    domain: []const u8,
    content_root: []const u8,
    listen_port: u16,
    routes: []Route,
    /// Default session lifetime in seconds for auth-gated routes
    /// (overridable per-route via Route.session_ttl_seconds).  Default
    /// 24h.  0 means session never expires (don't use in production).
    session_ttl_seconds: u32 = 24 * 60 * 60,
    /// 32-byte secret the auth handler uses to HMAC-sign session cookies.
    /// Generated on `brain site init`; stored as hex in site.json.  Rotating
    /// invalidates all live sessions.  WSITE1.5 will replace this with
    /// the admin's identity key signing JWTs.
    signing_secret: [32]u8 = [_]u8{0} ** 32,
    /// Default payment_recipient for routes that don't override.
    /// Compressed SEC1 pubkey (33 bytes).  Surfaced in the
    /// X-Semantos-Recipient challenge header on 402 responses.
    /// Required by `brain site validate` if any route has
    /// auth = .payment_required without its own payment_recipient.
    payment_recipient: [33]u8 = [_]u8{0} ** 33,
    payment_recipient_set: bool = false,
    /// WSITE5.5 — operator's WIF-encoded private key used to sign
    /// admin-initiated spends (`brain refund`, future `brain send`).
    /// Empty when unset; commands that need it print a clear "set
    /// signing_key_wif in site.json" hint.
    ///
    /// Trust note: storing the key in plaintext on disk is the v0.1
    /// convenience trade-off.  v0.2 will encrypt-at-rest under an
    /// operator passphrase set at boot; v0.3 hands signing to the
    /// wallet-engine WASM module's tier-key custody flow so the
    /// signing key never leaves the WASM sandbox.
    signing_key_wif: []const u8 = "",
    /// D-O6a — capabilities granted to anonymous (no bearer / no cert)
    /// callers reaching this site.  Per-site allowlist drives which
    /// scopes the chat widget (and any future anonymous endpoints)
    /// may invoke.  Empty = anonymous calls are denied at the dispatcher
    /// (the chat route returns HTTP 401).  Typical entry for an
    /// oddjobz tenant: `"cap.llm.complete:anonymous-oddjobz"`.
    /// See BRAIN-DISPATCHER-UNIFICATION.md §3 line 182 + §11 line ~428.
    anonymous_caps: []const []const u8 = &.{},
    /// D-W1 Phase 3 — closes brain issue #273.  Per-site CORS allowlist.
    /// Each entry is either an exact origin (e.g.
    /// `"https://helm.example.com"`) or the literal `"*"` wildcard.
    /// Empty (the default) = same-origin only; OPTIONS preflights still
    /// return 204 but no `Access-Control-Allow-Origin` header is emitted,
    /// so the browser blocks the cross-origin call.  See
    /// https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS/Preflight_request.
    cors_allowed_origins: []const []const u8 = &.{},
    /// D-W1 Phase 3 — methods echoed in `Access-Control-Allow-Methods`.
    /// Default covers the verbs every existing brain route uses.  Operator
    /// can narrow per-site.
    cors_allowed_methods: []const []const u8 = &default_cors_methods,
    /// D-W1 Phase 3 — headers echoed in `Access-Control-Allow-Headers`.
    /// Default covers `authorization` (bearer-gated routes), `content-
    /// type` (JSON bodies on REPL + chat + device-pair), and
    /// `x-requested-with` (the helm SPA tags every fetch with it).
    cors_allowed_headers: []const []const u8 = &default_cors_headers,
    /// D-W1 Phase 3 — `Access-Control-Max-Age` value in seconds.  Default
    /// 600 (10 minutes) so the browser can cache the preflight without
    /// pinning a stale config for hours.
    cors_max_age_seconds: u32 = 600,
    /// D-W1 Phase 3 — when true, `Access-Control-Allow-Credentials: true`
    /// is added to responses with a matched origin.  Refused (parse
    /// error) when combined with a `*` wildcard in `cors_allowed_origins`
    /// per the CORS spec.
    cors_allow_credentials: bool = false,
    /// D-W1 Phase 3 — optional `Content-Security-Policy` header value
    /// emitted on every site response (Tier 2, see PR body).  Empty =
    /// no CSP header.  Operators can narrow the SPA's network surface
    /// without hand-writing a fronting proxy config.
    content_security_policy: []const u8 = "",
    /// Backing arena.  All slices in this struct (and every Route's
    /// strings) live until the arena is deinited.
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *SiteConfig) void {
        self.arena.deinit();
    }

    /// D-W1 Phase 3 — match the request's `Origin` against the per-site
    /// CORS allowlist.  Returns the value to echo in `Access-Control-
    /// Allow-Origin`, or `null` when the origin is disallowed.  Special
    /// cases:
    ///   • `cors_allowed_origins == ["*"]` ⇒ returns `"*"` (the literal
    ///     wildcard); browsers accept this for non-credentialed requests
    ///     only.  The parse stage refuses `*` + credentials so this
    ///     branch can't produce a CORS-spec-violating response.
    ///   • exact match ⇒ return the configured origin (echo verbatim,
    ///     not the request's `Origin` header — the latter is attacker-
    ///     controlled).
    ///   • no match ⇒ `null`.  Caller emits a 204 preflight WITHOUT an
    ///     ACAO header so the browser blocks the cross-origin call.
    pub fn matchCorsOrigin(self: *const SiteConfig, request_origin: []const u8) ?[]const u8 {
        for (self.cors_allowed_origins) |allowed| {
            if (std.mem.eql(u8, allowed, "*")) return "*";
            if (std.mem.eql(u8, allowed, request_origin)) return allowed;
        }
        return null;
    }

    /// Look up the route serving the given URL path.  Exact-match for
    /// `static` and `dynamic` routes; D-O5 added prefix-match support for
    /// `directory` routes (whose `path` MUST end in `/`).  Exact-match
    /// routes win over prefix matches when both exist (e.g. an exact
    /// `/helm/` static would shadow a `/helm/` directory — that's a
    /// config-author choice, surfaced via `validate`).
    pub fn routeFor(self: *const SiteConfig, url_path: []const u8) ?*const Route {
        // Exact-match pass first.
        for (self.routes) |*r| {
            if (std.mem.eql(u8, r.path, url_path)) return r;
        }
        // Directory prefix-match pass — pick the longest matching prefix
        // so nested directory routes work correctly.
        var best: ?*const Route = null;
        for (self.routes) |*r| {
            if (r.kind != .directory) continue;
            if (r.path.len == 0 or r.path[r.path.len - 1] != '/') continue;
            if (!std.mem.startsWith(u8, url_path, r.path)) continue;
            if (best == null or r.path.len > best.?.path.len) best = r;
        }
        return best;
    }
};

/// Parse a JSON site config. Caller owns the returned `SiteConfig`
/// (calls `deinit` when done).
pub fn parseJson(parent_allocator: std.mem.Allocator, json: []const u8) ConfigError!SiteConfig {
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    errdefer arena.deinit();
    const allocator = arena.allocator();

    const parsed = std.json.parseFromSliceLeaky(std.json.Value, allocator, json, .{}) catch {
        return error.parse_failed;
    };
    if (parsed != .object) return error.schema_mismatch;
    const root = parsed.object;

    // ── site.{domain, content_root, listen_port} ─────────────────────
    const site_v = root.get("site") orelse return error.schema_mismatch;
    if (site_v != .object) return error.schema_mismatch;
    const site_obj = site_v.object;

    const domain_v = site_obj.get("domain") orelse return error.schema_mismatch;
    const content_root_v = site_obj.get("content_root") orelse return error.schema_mismatch;
    if (domain_v != .string or content_root_v != .string) return error.schema_mismatch;

    const listen_port: u16 = if (site_obj.get("listen_port")) |v|
        if (v == .integer) std.math.cast(u16, v.integer) orelse return error.schema_mismatch else return error.schema_mismatch
    else
        8080;

    const session_ttl_seconds: u32 = if (site_obj.get("session_ttl_seconds")) |v|
        if (v == .integer) std.math.cast(u32, v.integer) orelse return error.schema_mismatch else return error.schema_mismatch
    else
        24 * 60 * 60;

    var signing_secret: [32]u8 = [_]u8{0} ** 32;
    if (site_obj.get("signing_secret")) |v| {
        if (v != .string) return error.schema_mismatch;
        if (v.string.len != 64) return error.schema_mismatch;
        decodeHex(v.string, &signing_secret) catch return error.schema_mismatch;
    }

    // WSITE5.5 — optional signing key.  We only check shape (string +
    // non-empty); WIF parsing happens at the broadcast call-site so a
    // typo doesn't refuse to start the server.
    var signing_key_wif: []const u8 = "";
    if (site_obj.get("signing_key_wif")) |v| {
        if (v != .string) return error.schema_mismatch;
        signing_key_wif = allocator.dupe(u8, v.string) catch return error.out_of_memory;
    }

    var site_payment_recipient: [33]u8 = [_]u8{0} ** 33;
    var site_payment_recipient_set = false;
    if (site_obj.get("payment_recipient")) |v| {
        if (v != .string) return error.schema_mismatch;
        if (v.string.len != 66) return error.schema_mismatch;
        decodeHex(v.string, &site_payment_recipient) catch return error.schema_mismatch;
        site_payment_recipient_set = true;
    }

    // D-O6a — anonymous_caps allowlist.  Optional array-of-strings under
    // `site.anonymous_caps`.  Each entry is a fully-qualified cap name
    // (e.g. `"cap.llm.complete:anonymous-oddjobz"`).  We dupe each string
    // into the arena so the slice handed to `CapabilitySet.fromList`
    // outlives the parsed std.json.Value.
    var anonymous_caps: []const []const u8 = &.{};
    if (site_obj.get("anonymous_caps")) |v| {
        if (v != .array) return error.schema_mismatch;
        const items = v.array.items;
        const buf = allocator.alloc([]const u8, items.len) catch return error.out_of_memory;
        for (items, 0..) |entry, idx| {
            if (entry != .string) return error.schema_mismatch;
            buf[idx] = allocator.dupe(u8, entry.string) catch return error.out_of_memory;
        }
        anonymous_caps = buf;
    }

    // D-W1 Phase 3 — per-site CORS config.  All fields optional; empty
    // `cors_allowed_origins` ⇒ same-origin-only (preflight returns 204
    // with no ACAO header so the browser blocks the cross-origin call).
    // Wildcard `"*"` is allowed but refused if combined with
    // `cors_allow_credentials = true` (CORS spec violation; browsers
    // would reject anyway, but failing at parse time gives the operator
    // a clear "fix your config" hint).
    var cors_allowed_origins: []const []const u8 = &.{};
    if (site_obj.get("cors_allowed_origins")) |v| {
        if (v != .array) return error.schema_mismatch;
        const items = v.array.items;
        const buf = allocator.alloc([]const u8, items.len) catch return error.out_of_memory;
        for (items, 0..) |entry, idx| {
            if (entry != .string) return error.schema_mismatch;
            buf[idx] = allocator.dupe(u8, entry.string) catch return error.out_of_memory;
        }
        cors_allowed_origins = buf;
    }

    var cors_allowed_methods: []const []const u8 = &default_cors_methods;
    if (site_obj.get("cors_allowed_methods")) |v| {
        if (v != .array) return error.schema_mismatch;
        const items = v.array.items;
        const buf = allocator.alloc([]const u8, items.len) catch return error.out_of_memory;
        for (items, 0..) |entry, idx| {
            if (entry != .string) return error.schema_mismatch;
            buf[idx] = allocator.dupe(u8, entry.string) catch return error.out_of_memory;
        }
        cors_allowed_methods = buf;
    }

    var cors_allowed_headers: []const []const u8 = &default_cors_headers;
    if (site_obj.get("cors_allowed_headers")) |v| {
        if (v != .array) return error.schema_mismatch;
        const items = v.array.items;
        const buf = allocator.alloc([]const u8, items.len) catch return error.out_of_memory;
        for (items, 0..) |entry, idx| {
            if (entry != .string) return error.schema_mismatch;
            buf[idx] = allocator.dupe(u8, entry.string) catch return error.out_of_memory;
        }
        cors_allowed_headers = buf;
    }

    var cors_max_age_seconds: u32 = 600;
    if (site_obj.get("cors_max_age_seconds")) |v| {
        if (v != .integer) return error.schema_mismatch;
        if (v.integer < 0) return error.schema_mismatch;
        cors_max_age_seconds = std.math.cast(u32, v.integer) orelse return error.schema_mismatch;
    }

    var cors_allow_credentials: bool = false;
    if (site_obj.get("cors_allow_credentials")) |v| {
        if (v != .bool) return error.schema_mismatch;
        cors_allow_credentials = v.bool;
    }

    // CORS spec: `Access-Control-Allow-Origin: *` is incompatible with
    // `Access-Control-Allow-Credentials: true`.  Refuse to start so the
    // operator notices at config time, not at the first failed preflight.
    if (cors_allow_credentials) {
        for (cors_allowed_origins) |o| {
            if (std.mem.eql(u8, o, "*")) return error.invalid_cors_config;
        }
    }

    var content_security_policy: []const u8 = "";
    if (site_obj.get("content_security_policy")) |v| {
        if (v != .string) return error.schema_mismatch;
        content_security_policy = allocator.dupe(u8, v.string) catch return error.out_of_memory;
    }

    const domain_dup = allocator.dupe(u8, domain_v.string) catch return error.out_of_memory;
    const content_root_dup = allocator.dupe(u8, content_root_v.string) catch return error.out_of_memory;

    // ── routes ───────────────────────────────────────────────────────
    var route_list = std.ArrayList(Route){};
    if (root.get("routes")) |routes_v| {
        if (routes_v != .object) return error.schema_mismatch;
        var it = routes_v.object.iterator();
        while (it.next()) |entry| {
            const path = entry.key_ptr.*;
            const r_v = entry.value_ptr.*;
            if (r_v != .object) return error.schema_mismatch;
            const r_obj = r_v.object;

            const type_v = r_obj.get("type") orelse return error.schema_mismatch;
            if (type_v != .string) return error.schema_mismatch;
            const route_type = RouteType.fromStr(type_v.string) orelse return error.invalid_route_type;

            var route = Route{
                .path = allocator.dupe(u8, path) catch return error.out_of_memory,
                .kind = route_type,
            };

            switch (route_type) {
                .static => {
                    const file_v = r_obj.get("file") orelse return error.schema_mismatch;
                    if (file_v != .string) return error.schema_mismatch;
                    route.file = allocator.dupe(u8, file_v.string) catch return error.out_of_memory;
                },
                .dynamic => {
                    const handler_v = r_obj.get("handler") orelse return error.schema_mismatch;
                    if (handler_v != .string) return error.schema_mismatch;
                    route.handler = allocator.dupe(u8, handler_v.string) catch return error.out_of_memory;
                    // WSITE2.5 — handler_sha256 is required for dynamic routes.
                    // Operators run `brain hash <handler>.wasm` once and paste.
                    if (r_obj.get("handler_sha256")) |sha_v| {
                        if (sha_v != .string) return error.schema_mismatch;
                        if (sha_v.string.len != 64) return error.schema_mismatch;
                        decodeHex(sha_v.string, &route.handler_sha256) catch return error.schema_mismatch;
                        route.handler_sha256_set = true;
                    }
                },
                .directory => {
                    // D-O5 — brain issue #274.  `root` is the on-disk dir
                    // that backs the route prefix.  `spa_fallback`
                    // defaults to `index.html` when omitted (the
                    // overwhelming convention) so most operator configs
                    // are a one-liner.  The `path` MUST end in `/` so
                    // dispatch can do a clean prefix match without
                    // accidentally swallowing sibling routes.
                    if (path.len == 0 or path[path.len - 1] != '/') {
                        return error.invalid_route_type;
                    }
                    const root_v = r_obj.get("root") orelse return error.schema_mismatch;
                    if (root_v != .string) return error.schema_mismatch;
                    route.root = allocator.dupe(u8, root_v.string) catch return error.out_of_memory;
                    if (r_obj.get("spa_fallback")) |fb_v| {
                        if (fb_v != .string) return error.schema_mismatch;
                        route.spa_fallback = allocator.dupe(u8, fb_v.string) catch return error.out_of_memory;
                    } else {
                        route.spa_fallback = allocator.dupe(u8, "index.html") catch return error.out_of_memory;
                    }
                },
                .chat => {
                    // D-O6a — chat routes carry no handler; the Semantos Brain-
                    // native chat_http endpoint dispatches on this
                    // route's `scope` + `system_prompt`.  Both fields
                    // optional at parse time; `validate()` enforces
                    // a non-empty `scope`.
                    if (r_obj.get("scope")) |sv| {
                        if (sv != .string) return error.schema_mismatch;
                        route.chat_scope = allocator.dupe(u8, sv.string) catch return error.out_of_memory;
                    }
                    if (r_obj.get("system_prompt")) |sp| {
                        if (sp != .string) return error.schema_mismatch;
                        route.chat_system_prompt = allocator.dupe(u8, sp.string) catch return error.out_of_memory;
                    }
                    if (r_obj.get("max_message_chars")) |mc| {
                        if (mc != .integer) return error.schema_mismatch;
                        if (mc.integer < 0) return error.schema_mismatch;
                        route.chat_max_message_chars = std.math.cast(u32, mc.integer) orelse return error.schema_mismatch;
                    }
                },
                .intake => {
                    if (r_obj.get("script")) |sv| {
                        if (sv != .string) return error.schema_mismatch;
                        route.intake_script = allocator.dupe(u8, sv.string) catch return error.out_of_memory;
                    }
                    if (r_obj.get("max_message_chars")) |mc| {
                        if (mc != .integer) return error.schema_mismatch;
                        if (mc.integer < 0) return error.schema_mismatch;
                        route.intake_max_message_chars = std.math.cast(u32, mc.integer) orelse return error.schema_mismatch;
                    }
                },
                // S10a — operator_home carries no config beyond the route type;
                // the profile is loaded from $data_dir/sites/<domain>/profile.json
                // at serve time by operator_site_renderer.
                .operator_home => {},
            }

            // auth is optional (defaults to public).  `public: true` is
            // a shorthand the spec example uses; map it to .public.
            if (r_obj.get("public")) |pub_v| {
                if (pub_v == .bool and pub_v.bool) {
                    route.auth = .public;
                }
            }
            if (r_obj.get("auth")) |auth_v| {
                if (auth_v != .string) return error.schema_mismatch;
                route.auth = AuthKind.fromStr(auth_v.string) orelse return error.invalid_auth_kind;
            }
            if (r_obj.get("price_sats")) |price_v| {
                if (price_v != .integer) return error.schema_mismatch;
                if (price_v.integer < 0) return error.schema_mismatch;
                route.price_sats = @intCast(price_v.integer);
            }
            if (r_obj.get("session_ttl_seconds")) |ttl_v| {
                if (ttl_v != .integer) return error.schema_mismatch;
                if (ttl_v.integer < 0) return error.schema_mismatch;
                route.session_ttl_seconds = std.math.cast(u32, ttl_v.integer) orelse return error.schema_mismatch;
            }
            if (r_obj.get("payment_recipient")) |recv_v| {
                if (recv_v != .string) return error.schema_mismatch;
                if (recv_v.string.len != 66) return error.schema_mismatch;
                decodeHex(recv_v.string, &route.payment_recipient) catch return error.schema_mismatch;
                route.payment_recipient_set = true;
            }
            // WSITE5 — per-route OutputStore basket override.
            if (r_obj.get("output_basket")) |basket_v| {
                if (basket_v != .string) return error.schema_mismatch;
                route.output_basket = allocator.dupe(u8, basket_v.string) catch return error.out_of_memory;
            }

            route_list.append(allocator, route) catch return error.out_of_memory;
        }
    }
    const routes_slice = route_list.toOwnedSlice(allocator) catch return error.out_of_memory;

    return .{
        .domain = domain_dup,
        .content_root = content_root_dup,
        .listen_port = listen_port,
        .routes = routes_slice,
        .session_ttl_seconds = session_ttl_seconds,
        .signing_secret = signing_secret,
        .payment_recipient = site_payment_recipient,
        .payment_recipient_set = site_payment_recipient_set,
        .signing_key_wif = signing_key_wif,
        .anonymous_caps = anonymous_caps,
        .cors_allowed_origins = cors_allowed_origins,
        .cors_allowed_methods = cors_allowed_methods,
        .cors_allowed_headers = cors_allowed_headers,
        .cors_max_age_seconds = cors_max_age_seconds,
        .cors_allow_credentials = cors_allow_credentials,
        .content_security_policy = content_security_policy,
        .arena = arena,
    };
}

/// Resolve effective payment_recipient for a route — falls through to
/// the site-level value if the route doesn't override.  Returns null
/// if neither is set (configuration error for payment_required routes).
pub fn effectiveRecipient(cfg: *const SiteConfig, route: *const Route) ?*const [33]u8 {
    if (route.payment_recipient_set) return &route.payment_recipient;
    if (cfg.payment_recipient_set) return &cfg.payment_recipient;
    return null;
}

fn decodeHex(hex: []const u8, out: []u8) !void {
    if (hex.len != out.len * 2) return error.bad_length;
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
        else => error.bad_hex,
    };
}

pub fn encodeHex(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var out = try allocator.alloc(u8, bytes.len * 2);
    const charset = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        out[i * 2 + 0] = charset[(b >> 4) & 0xf];
        out[i * 2 + 1] = charset[b & 0xf];
    }
    return out;
}

/// Read + parse a config file from disk. 1MB cap.
pub fn loadFromPath(parent_allocator: std.mem.Allocator, path: []const u8) !SiteConfig {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const stat = try file.stat();
    if (stat.size > 1024 * 1024) return error.parse_failed;
    const buf = try parent_allocator.alloc(u8, stat.size);
    defer parent_allocator.free(buf);
    _ = try file.readAll(buf);
    return parseJson(parent_allocator, buf);
}

/// Default config template emitted by `brain site init <domain>`.
/// Generates a fresh 32-byte signing secret so every site gets unique
/// session-cookie HMAC keys out of the box.
pub fn defaultJsonTemplate(allocator: std.mem.Allocator, domain: []const u8) ![]u8 {
    var secret: [32]u8 = undefined;
    std.crypto.random.bytes(&secret);
    const secret_hex = try encodeHex(allocator, &secret);
    defer allocator.free(secret_hex);
    return try std.fmt.allocPrint(allocator,
        \\{{
        \\  "site": {{
        \\    "domain":              "{s}",
        \\    "content_root":        "./public",
        \\    "listen_port":         8080,
        \\    "session_ttl_seconds": 86400,
        \\    "signing_secret":      "{s}"
        \\  }},
        \\  "routes": {{
        \\    "/": {{
        \\      "type": "static",
        \\      "file": "index.html",
        \\      "public": true
        \\    }}
        \\  }}
        \\}}
        \\
    , .{ domain, secret_hex });
}

// ─────────────────────────────────────────────────────────────────────
// Validation diagnostics
// ─────────────────────────────────────────────────────────────────────

pub const ValidationProblem = struct {
    severity: enum { warn, err },
    message: []u8, // owned by ValidationReport.allocator
};

pub const ValidationReport = struct {
    allocator: std.mem.Allocator,
    problems: std.ArrayList(ValidationProblem),

    pub fn init(allocator: std.mem.Allocator) ValidationReport {
        return .{ .allocator = allocator, .problems = .empty };
    }

    pub fn deinit(self: *ValidationReport) void {
        for (self.problems.items) |p| self.allocator.free(p.message);
        self.problems.deinit(self.allocator);
    }

    pub fn errCount(self: *const ValidationReport) usize {
        var n: usize = 0;
        for (self.problems.items) |p| {
            if (p.severity == .err) n += 1;
        }
        return n;
    }

    fn add(self: *ValidationReport, sev: enum { warn, err }, msg: []u8) !void {
        try self.problems.append(self.allocator, .{
            .severity = if (sev == .warn) .warn else .err,
            .message = msg,
        });
    }
};

/// Run static checks over a parsed config. Verifies declared static files
/// exist on disk (relative to content_root); flags dynamic routes as
/// "WSITE2.5 deferred"; flags non-public auth as "WSITE3 deferred".
/// Caller owns the returned report.
pub fn validate(allocator: std.mem.Allocator, cfg: *const SiteConfig) !ValidationReport {
    var report = ValidationReport.init(allocator);
    errdefer report.deinit();

    if (cfg.domain.len == 0) {
        try report.add(.err, try std.fmt.allocPrint(allocator, "site.domain is empty", .{}));
    }
    if (cfg.content_root.len == 0) {
        try report.add(.err, try std.fmt.allocPrint(allocator, "site.content_root is empty", .{}));
    }
    if (cfg.routes.len == 0) {
        try report.add(.warn, try std.fmt.allocPrint(allocator, "no routes declared — site will return 404 for everything", .{}));
    }

    for (cfg.routes) |r| {
        switch (r.kind) {
            .static => {
                // Try to open the file; warn if missing (operator may
                // still be authoring content).
                const path = try std.fs.path.join(allocator, &.{ cfg.content_root, r.file });
                defer allocator.free(path);
                std.fs.cwd().access(path, .{}) catch {
                    try report.add(.warn, try std.fmt.allocPrint(allocator,
                        "route {s}: file not found at {s}", .{ r.path, path }));
                };
            },
            .dynamic => {
                // WSITE2.5 — dynamic handlers ship.  Validate that the
                // operator has set both handler + handler_sha256 (refuse
                // to start otherwise; mirrors `brain start`).  Try to open
                // the file relative to `<site>/handlers/<name>` so the
                // operator gets a clear hint when the binary's missing.
                if (r.handler.len == 0) {
                    try report.add(.err, try std.fmt.allocPrint(allocator,
                        "route {s}: dynamic but no `handler` set", .{r.path}));
                }
                if (!r.handler_sha256_set) {
                    try report.add(.err, try std.fmt.allocPrint(allocator,
                        "route {s}: dynamic but no `handler_sha256` (run `brain hash <handler>.wasm` and paste)", .{r.path}));
                }
                if (r.handler.len > 0) {
                    const path = try std.fs.path.join(allocator, &.{ "handlers", r.handler });
                    defer allocator.free(path);
                    std.fs.cwd().access(path, .{}) catch {
                        try report.add(.warn, try std.fmt.allocPrint(allocator,
                            "route {s}: handler not found at {s}", .{ r.path, path }));
                    };
                }
            },
            .directory => {
                // D-O5 — directory routes back the SPA assets that ship
                // out of `apps/loom-svelte/dist/` (or any other static
                // bundle).  The route's `path` must end in `/`; the
                // backing `root` directory must be readable; the
                // `spa_fallback` file must exist inside it.
                if (r.path.len == 0 or r.path[r.path.len - 1] != '/') {
                    try report.add(.err, try std.fmt.allocPrint(allocator,
                        "route {s}: directory route path must end in '/'", .{r.path}));
                }
                if (r.root.len == 0) {
                    try report.add(.err, try std.fmt.allocPrint(allocator,
                        "route {s}: directory but no `root` set", .{r.path}));
                } else {
                    std.fs.cwd().access(r.root, .{}) catch {
                        try report.add(.warn, try std.fmt.allocPrint(allocator,
                            "route {s}: directory root not found at {s}", .{ r.path, r.root }));
                    };
                    if (r.spa_fallback.len > 0) {
                        const fb_path = try std.fs.path.join(allocator, &.{ r.root, r.spa_fallback });
                        defer allocator.free(fb_path);
                        std.fs.cwd().access(fb_path, .{}) catch {
                            try report.add(.warn, try std.fmt.allocPrint(allocator,
                                "route {s}: spa_fallback not found at {s}", .{ r.path, fb_path }));
                        };
                    }
                }
            },
            .chat => {
                // D-O6a — chat routes need `scope` set; otherwise the
                // dispatcher cap-check has nothing to match against.
                // The system_prompt is optional (the LLM gets the
                // visitor message verbatim if blank).
                if (r.chat_scope.len == 0) {
                    try report.add(.err, try std.fmt.allocPrint(allocator,
                        "route {s}: chat route missing `scope` (set scope=\"...\" — required to derive cap.llm.complete:<scope>)", .{r.path}));
                }
                // Heads-up: anonymous_caps must include the derived cap
                // for visitors to actually reach this route.  We can't
                // check it here without crossing into SiteConfig; the
                // operator-doc warns about this case.
                if (r.chat_scope.len > 0 and cfg.anonymous_caps.len == 0) {
                    try report.add(.warn, try std.fmt.allocPrint(allocator,
                        "route {s}: chat scope=\"{s}\" set but site.anonymous_caps is empty — visitors will get HTTP 401 (add \"cap.llm.complete:{s}\")", .{ r.path, r.chat_scope, r.chat_scope }));
                }
            },
            .intake => {
                if (r.intake_script.len == 0) {
                    try report.add(.err, try std.fmt.allocPrint(allocator,
                        "route {s}: intake route missing `script` (set script=\"/path/to/intake-handler.ts\")", .{r.path}));
                }
            },
            .operator_home => {
                // Profile is loaded at serve time from $data_dir/sites/<domain>/profile.json.
                // Warn if the route path isn't "/" — operator_home is always the root.
                if (!std.mem.eql(u8, r.path, "/") and !std.mem.eql(u8, r.path, "/index.html")) {
                    try report.add(.warn, try std.fmt.allocPrint(allocator,
                        "route {s}: operator_home is designed for '/' or '/index.html'", .{r.path}));
                }
            },
        }
        switch (r.auth) {
            .public => {},
            .identity_required, .payment_required => {
                // WSITE3 + WSITE4 ship the gate; WSITE3.5 lands BRC-52
                // cert validation, WSITE4.5 lands on-chain SPV verification
                // of cited txids.  Surface that as a heads-up rather than
                // a "deferred to phase X" error.
                try report.add(.warn, try std.fmt.allocPrint(allocator,
                    "route {s}: auth={s} active — signature gate ships today; cert/SPV validation pending WSITE3.5/4.5", .{ r.path, r.auth.label() }));
            },
        }
        if (r.auth == .payment_required and r.price_sats == 0) {
            try report.add(.err, try std.fmt.allocPrint(allocator,
                "route {s}: payment_required but price_sats=0", .{r.path}));
        }
        if (r.auth == .payment_required and effectiveRecipient(cfg, &r) == null) {
            try report.add(.err, try std.fmt.allocPrint(allocator,
                "route {s}: payment_required but no payment_recipient configured (set on route or site)", .{r.path}));
        }
    }

    return report;
}

```
