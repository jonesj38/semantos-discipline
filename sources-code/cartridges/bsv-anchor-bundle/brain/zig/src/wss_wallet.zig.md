---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/wss_wallet.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.446355+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/wss_wallet.zig

```zig
// Phase Brain 4.5 — WSS wallet endpoint at /api/v1/wallet.
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 4 — WSS).
//
// Composition:
//   site_server.handleConnection peeks at the first request from a
//   freshly-accepted TCP connection. If it's a GET upgrade to
//   /api/v1/wallet AND the bearer token is valid, control transfers
//   here: this module writes the 101 response, then enters a frame
//   loop dispatching JSON-RPC calls until the client closes (or we
//   close on protocol violation / oversize).
//
// Wire format (BRC-100-aligned JSON-RPC 2.0):
//
//     client→server text frame:
//       {"jsonrpc":"2.0","id":1,"method":"wallet.getVersion","params":{}}
//
//     server→client text frame:
//       {"jsonrpc":"2.0","id":1,"result":{"version":"brain-0.1","protocol":"brc-100"}}
//
//     error response:
//       {"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"method not found: wallet.foo"}}
//
// ─── v0.1 method scope ───────────────────────────────────────────────
//
// Only read-only "shape" methods land in v0.1 — the real BRC-100 method
// surface (createAction, signAction, getPublicKey, etc.) needs a
// proper Zig→wasmtime call path into the wallet engine, which lands in
// Brain 4.6. The four methods here prove the WS pipe end-to-end against
// `wscat` / `bun ws` / browser WebSocket clients without depending on
// the wallet-engine WASM.
//
//   wallet.getVersion       → {version, protocol, server}
//   wallet.getNetwork       → {network} ("mainnet"/"testnet" — config-derived)
//   wallet.getAuthStatus    → {authenticated:false, reason:"engine-not-loaded"}
//                              for v0.1; Brain 4.6 wires real status from the broker
//   wallet.echo             → {echo: <params>} — diagnostic
//
// Anything else returns JSON-RPC error -32601 ("method not found").
// Malformed JSON returns -32700 ("parse error"). Protocol violations
// at the WS layer (bad masking, oversize payload, unsupported opcode)
// terminate the session with the appropriate close code.

const std = @import("std");
const bearer_tokens = @import("bearer_tokens");
const wss_codec = @import("wss_codec");
const helm_event_broker = @import("helm_event_broker");
const oddjobz_ratify_handler = @import("oddjobz_ratify_handler");
const oddjobz_query_handler = @import("oddjobz_query_handler");
// Generic cell.query / cell.get primitive — typeHash-keyed projection.
// See cell_query_handler.zig for the dispatch table.
const cell_query_handler = @import("cell_query_handler");
// Generic verb.dispatch primitive — uniform write-seam for extension
// action verbs. See verb_dispatcher.zig for the walker contract.
const verb_dispatcher = @import("verb_dispatcher");
// Manifest registry — tracks which extensions the brain has been told
// about at runtime. See manifest_registry.zig for the lifecycle.
const manifest_registry = @import("manifest_registry");
const oddjobz_attention_handler = @import("oddjobz_attention_handler");
// B-pragmatic reactor path (Commit 5 — brain-wedge fix).
// http_parser_mod gives us HttpRequest for tryUpgradeFromParsed().
const http_parser_mod = @import("http_parser");
// W7.4 — hosted-operator SNI+cert auth.
const wss_operator_auth = @import("wss_operator_auth");
const sni_domain_map = @import("sni_domain_map");
// W7.5 — per-operator wrapped DEK store.
const wrapped_dek_store = @import("wrapped_dek_store");

// Shared types extracted to wss_wallet/types.zig.  Re-exported here
// so external callers (`site_server.zig`, `cli.zig`, tests) keep
// reaching them as `wss_wallet.X`.
const types = @import("wss_wallet/types.zig");
pub const MAX_PAYLOAD_BYTES = types.MAX_PAYLOAD_BYTES;
pub const SessionError = types.SessionError;
pub const ServerVersion = types.ServerVersion;
pub const Network = types.Network;
pub const Backend = types.Backend;
pub const HELM_TOPICS = types.HELM_TOPICS;
pub const MAX_HELM_TOPICS_PER_SUB = types.MAX_HELM_TOPICS_PER_SUB;
pub const MAX_HELM_TOPIC_LEN = types.MAX_HELM_TOPIC_LEN;
pub const MAX_HELM_FETCH_LIMIT = types.MAX_HELM_FETCH_LIMIT;
pub const HandshakeResult = types.HandshakeResult;

// File-local aliases for the types that stay private to the
// wss_wallet endpoint (used by the handler bodies + serveSession).
const SessionState = types.SessionState;
const helmEventCallback = types.helmEventCallback;
const eventTypeMatchesTopics = types.eventTypeMatchesTopics;
const topicPlural = types.topicPlural;
const jsonEncodeString = types.jsonEncodeString;
const lockedWriteFrame = types.lockedWriteFrame;
const lockedWriteClose = types.lockedWriteClose;
const writeResultRaw = types.writeResultRaw;
const writeError = types.writeError;

// Phase 3 — JSON-RPC method handlers extracted to wss_wallet/handlers.zig.
// File-local aliases so handleJsonRpc + the Reactor's handleReactorJsonRpc
// keep working with the existing identifiers.
const handlers = @import("wss_wallet/handlers.zig");
const handleHelmSubscribe = handlers.handleHelmSubscribe;
const handleHelmUnsubscribe = handlers.handleHelmUnsubscribe;
const handleHelmFetchSince = handlers.handleHelmFetchSince;
const handleCellQuery = handlers.handleCellQuery;
const handleCellGet = handlers.handleCellGet;
const handleAttentionPoll = handlers.handleAttentionPoll;
const handleRatifySubmit = handlers.handleRatifySubmit;
const handleVerbDispatch = handlers.handleVerbDispatch;
const handleManifestInstall = handlers.handleManifestInstall;
const handleManifestList = handlers.handleManifestList;
const handleManifestUninstall = handlers.handleManifestUninstall;
const handleOddjobzAttention = handlers.handleOddjobzAttention;
const OddjobzQueryVerb = handlers.OddjobzQueryVerb;
const OddjobzAttentionVerb = handlers.OddjobzAttentionVerb;

// Phase 4 — Reactor cluster extracted to wss_wallet/reactor.zig.
// Re-export the pub items so external callers (site_server.zig)
// keep reaching them as wss_wallet.ReactorSession / .tryUpgradeFromParsed
// / .advanceFrame / .AdvanceFrameResult / .ReactorUpgradeResult.
const reactor = @import("wss_wallet/reactor.zig");
pub const ReactorSession = reactor.ReactorSession;
pub const ReactorUpgradeResult = reactor.ReactorUpgradeResult;
pub const AdvanceFrameResult = reactor.AdvanceFrameResult;
pub const tryUpgradeFromParsed = reactor.tryUpgradeFromParsed;
pub const advanceFrame = reactor.advanceFrame;

/// Inspect a parsed std.http.Server.Request and, if it's a WS upgrade
/// to /api/v1/wallet, validate the bearer token and write the 101
/// response. The caller (site_server.handleConnection) then transfers
/// control to `serveSession` over the underlying conn.stream.
///
/// `auth_token_id_out` (if non-null) receives the verified bearer
/// token's UUIDv4 id (32 hex chars), for downstream audit-log
/// decoration. Only set on `.upgraded`.
pub fn tryUpgrade(
    request: *std.http.Server.Request,
    backend: *Backend,
    stream: std.net.Stream,
    auth_token_id_out: ?*[32]u8,
) !HandshakeResult {
    const target = request.head.target;
    const method = request.head.method;
    // Match `/api/v1/wallet` exactly, or `/api/v1/wallet?<query>` for
    // browser clients using the query-string bearer fallback.
    const path_only = if (std.mem.indexOfScalar(u8, target, '?')) |q|
        target[0..q]
    else
        target;
    if (!std.mem.eql(u8, path_only, "/api/v1/wallet")) {
        return .not_a_wallet_upgrade;
    }
    if (method != .GET) {
        try respondHttp(request, .method_not_allowed, "{\"error\":\"GET required for WS upgrade\"}");
        return .rejected;
    }

    // Validate the WS-specific headers.
    const upgrade = headerValue(request, "upgrade") orelse {
        try respondHttp(request, .bad_request, "{\"error\":\"missing Upgrade: websocket\"}");
        return .rejected;
    };
    if (!std.ascii.eqlIgnoreCase(std.mem.trim(u8, upgrade, " \t"), "websocket")) {
        try respondHttp(request, .bad_request, "{\"error\":\"Upgrade must be websocket\"}");
        return .rejected;
    }
    const conn_hdr = headerValue(request, "connection") orelse {
        try respondHttp(request, .bad_request, "{\"error\":\"missing Connection: Upgrade\"}");
        return .rejected;
    };
    if (!asciiContainsCaseInsensitive(conn_hdr, "Upgrade")) {
        try respondHttp(request, .bad_request, "{\"error\":\"Connection must contain Upgrade\"}");
        return .rejected;
    }
    const ws_key = headerValue(request, "sec-websocket-key") orelse {
        try respondHttp(request, .bad_request, "{\"error\":\"missing Sec-WebSocket-Key\"}");
        return .rejected;
    };

    // Bearer auth — same token store as the HTTP REPL. The WS handshake
    // is a regular HTTP request, so Authorization: Bearer ... works
    // exactly like the REPL endpoint. Browsers can't set arbitrary
    // headers on `new WebSocket(...)` directly; for browser clients we
    // also accept `?bearer=<hex>` in the query string as a fallback.
    const auth_hex = extractBearer(target, request) orelse {
        try respondHttp(request, .unauthorized, "{\"error\":\"missing bearer token (Authorization header or ?bearer=<hex64>)\"}");
        return .rejected;
    };
    const record = backend.tokens.verifyHex(auth_hex) catch |err| {
        const msg = switch (err) {
            error.expired => "{\"error\":\"bearer token expired\"}",
            error.bad_format => "{\"error\":\"bearer token must be 64 hex chars\"}",
            else => "{\"error\":\"bearer token not recognised\"}",
        };
        try respondHttp(request, .unauthorized, msg);
        return .rejected;
    };
    if (auth_token_id_out) |out| out.* = record.id;

    // Compute Sec-WebSocket-Accept and write the 101 response directly
    // to the underlying stream — std.http.Server.Request.respond doesn't
    // expose a way to set status 101 with the right header set, and we
    // need to take over the stream regardless.
    var accept_b64: [28]u8 = undefined;
    wss_codec.computeAccept(ws_key, &accept_b64);
    var resp_buf: [256]u8 = undefined;
    const resp = try std.fmt.bufPrint(
        &resp_buf,
        "HTTP/1.1 101 Switching Protocols\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Accept: {s}\r\n\r\n",
        .{&accept_b64},
    );
    stream.writeAll(resp) catch return error.write_failed;
    return .upgraded;
}

// ─── Frame loop / method dispatch ────────────────────────────────────

/// Take over an upgraded stream. Reads frames, parses them as JSON-RPC,
/// dispatches to the method registry, writes the response. Loops until
/// the client closes or a protocol violation kills the session.
pub fn serveSession(
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    backend: *Backend,
) !void {
    var session = SessionState{
        .allocator = allocator,
        .stream = stream,
        .write_mu = .{},
    };
    defer if (backend.helm_broker) |broker| session.unsubscribeAndFree(broker) else session.freeTopics();

    while (true) {
        const frame = wss_codec.readFrame(allocator, stream, MAX_PAYLOAD_BYTES) catch |err| switch (err) {
            error.Eof => return,
            error.Fragmented => {
                wss_codec.writeClose(stream, 1003, "fragmentation not supported") catch {};
                return;
            },
            error.NotMasked => {
                wss_codec.writeClose(stream, 1002, "client frames must be masked") catch {};
                return;
            },
            error.PayloadTooLarge => {
                wss_codec.writeClose(stream, 1009, "payload too large") catch {};
                return;
            },
            error.UnsupportedOpcode => {
                wss_codec.writeClose(stream, 1003, "unsupported opcode or RSV bits") catch {};
                return;
            },
            else => return,
        };
        defer allocator.free(frame.payload);

        switch (frame.opcode) {
            .close => {
                // Echo a close back per RFC 6455 §5.5.1 then return.
                lockedWriteClose(&session, 1000, "bye");
                return;
            },
            .ping => {
                // RFC 6455 §5.5.3 — pong with same payload.
                lockedWriteFrame(&session, .pong, frame.payload) catch return;
                continue;
            },
            .pong => continue, // unsolicited pong is permitted, ignore
            .text => {
                handleJsonRpc(&session, backend, frame.payload) catch |err| {
                    // Per-message failure — write a JSON-RPC error and
                    // keep the session alive (the client may retry).
                    const msg = std.fmt.allocPrint(
                        allocator,
                        "{{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{{\"code\":-32603,\"message\":\"internal error: {s}\"}}}}",
                        .{@errorName(err)},
                    ) catch return;
                    defer allocator.free(msg);
                    lockedWriteFrame(&session, .text, msg) catch return;
                };
            },
            else => {
                // Binary / continuation / unknown — close with 1003.
                lockedWriteClose(&session, 1003, "only text frames supported");
                return;
            },
        }
    }
}


fn handleJsonRpc(
    session: *SessionState,
    backend: *Backend,
    body: []const u8,
) !void {
    const allocator = session.allocator;
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        const msg = "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":\"parse error: body is not valid JSON\"}}";
        return lockedWriteFrame(session, .text, msg);
    };
    defer parsed.deinit();

    if (parsed.value != .object) {
        const msg = "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"invalid request: must be a JSON object\"}}";
        return lockedWriteFrame(session, .text, msg);
    }

    const id_val = parsed.value.object.get("id") orelse std.json.Value{ .null = {} };
    const method_val = parsed.value.object.get("method") orelse {
        return writeError(session, id_val, -32600, "invalid request: missing 'method'");
    };
    if (method_val != .string) {
        return writeError(session, id_val, -32600, "invalid request: 'method' must be a string");
    }
    const method = method_val.string;
    const params = parsed.value.object.get("params") orelse std.json.Value{ .null = {} };

    if (std.mem.eql(u8, method, "wallet.getVersion")) {
        const v = ServerVersion{};
        const result = try std.fmt.allocPrint(
            allocator,
            "{{\"version\":\"{s}\",\"protocol\":\"{s}\",\"server\":\"{s}\"}}",
            .{ v.version, v.protocol, v.server },
        );
        defer allocator.free(result);
        return writeResultRaw(session, id_val, result);
    }
    if (std.mem.eql(u8, method, "wallet.getNetwork")) {
        const result = try std.fmt.allocPrint(
            allocator,
            "{{\"network\":\"{s}\"}}",
            .{backend.network.asString()},
        );
        defer allocator.free(result);
        return writeResultRaw(session, id_val, result);
    }
    if (std.mem.eql(u8, method, "wallet.getAuthStatus")) {
        // v0.1 stub — real engine status lands in Brain 4.6.
        const result =
            "{\"authenticated\":false,\"reason\":\"wallet-engine-not-yet-wired\"}";
        return writeResultRaw(session, id_val, result);
    }
    if (std.mem.eql(u8, method, "wallet.echo")) {
        // Diagnostic — echoes params back.
        const params_json = try std.json.Stringify.valueAlloc(allocator, params, .{});
        defer allocator.free(params_json);
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(allocator);
        try buf.appendSlice(allocator, "{\"echo\":");
        try buf.appendSlice(allocator, params_json);
        try buf.append(allocator, '}');
        return writeResultRaw(session, id_val, buf.items);
    }

    // ── D-O5.followup-4 — helm.subscribe / helm.unsubscribe ──
    //
    // helm.subscribe registers a per-connection broker subscriber with
    // the supplied topic list (or replaces the previous registration).
    // helm.unsubscribe drops the registration (idempotent).  Both
    // require the broker to be wired into the backend; absent → -32603
    // "helm broker unavailable".
    if (std.mem.eql(u8, method, "helm.subscribe")) {
        return handleHelmSubscribe(session, backend, id_val, params);
    }
    if (std.mem.eql(u8, method, "helm.unsubscribe")) {
        return handleHelmUnsubscribe(session, backend, id_val);
    }
    // Sovereign-push D.1 — `helm.fetch_since` lets a freshly-woken
    // device pull events the brain published while it was offline,
    // keyed by the wake-only push envelope's `ts`.  Bounded result
    // size keeps the wire frame inside MAX_PAYLOAD_BYTES.
    if (std.mem.eql(u8, method, "helm.fetch_since")) {
        return handleHelmFetchSince(session, backend, id_val, params);
    }
    // C4 PR-J5b — the legacy `oddjobz.ratify_proposal` method was retired;
    // ratification now flows through the generic `ratify.submit` (below) with
    // `namespace:"oddjobz"`, which routes to the same oddjobz ratify handler
    // via the builder registry. legacy-ingest's brain-rpc.ts sends ratify.submit.
    // C4 PR-J3 — the bespoke `oddjobz.find_*`/`list_*`/`get_*` query methods
    // were retired. Reads go through the generic `cell.query`/`cell.get`
    // (below) keyed by typeHash alias (oddjobz.{site,customer,job,attachment}.v2)
    // + a filter; oddjobz registers the decoders in registerInto. The live
    // clients already use cell.query/cell.get.

    // Generic cell-DAG read primitive — typeHash-keyed projection over
    // any registered extension's cells. See cell_query_handler.zig for
    // the dispatch table; experiences contribute typeHashes there.
    if (std.mem.eql(u8, method, "cell.query")) {
        return handleCellQuery(session, backend, id_val, params);
    }
    if (std.mem.eql(u8, method, "cell.get")) {
        return handleCellGet(session, backend, id_val, params);
    }
    // C4 PR-J4 — generic namespace-scoped attention feed.
    if (std.mem.eql(u8, method, "attention.poll")) {
        return handleAttentionPoll(session, backend, id_val, params);
    }
    // C4 PR-J5 — generic namespace-routed ratify.
    if (std.mem.eql(u8, method, "ratify.submit")) {
        return handleRatifySubmit(session, backend, id_val, params);
    }

    // Generic verb.dispatch — uniform write-seam for declared extension
    // action verbs. See verb_dispatcher.zig for the walker contract.
    // Params: { extensionId: string, verb: string, params: object }
    if (std.mem.eql(u8, method, "verb.dispatch")) {
        return handleVerbDispatch(session, backend, id_val, params);
    }

    // Manifest install / list — PWA and native shells push installed
    // extensions to the brain so other paired shells discover them.
    // See manifest_registry.zig for the registry shape.
    if (std.mem.eql(u8, method, "manifest.install")) {
        return handleManifestInstall(session, backend, id_val, params);
    }
    if (std.mem.eql(u8, method, "manifest.list")) {
        return handleManifestList(session, backend, id_val, params);
    }
    if (std.mem.eql(u8, method, "manifest.uninstall")) {
        return handleManifestUninstall(session, backend, id_val, params);
    }

    // Tier 2P Phase B — attention RPC verbs.
    if (std.mem.eql(u8, method, "oddjobz.list_messages")) {
        return handleOddjobzAttention(session, backend, id_val, params, .list_messages);
    }
    if (std.mem.eql(u8, method, "oddjobz.list_dispatch_decisions")) {
        return handleOddjobzAttention(session, backend, id_val, params, .list_dispatch_decisions);
    }
    if (std.mem.eql(u8, method, "oddjobz.poll_attention_signals")) {
        return handleOddjobzAttention(session, backend, id_val, params, .poll_attention_signals);
    }

    const err_msg = try std.fmt.allocPrint(
        allocator,
        "method not found: {s}",
        .{method},
    );
    defer allocator.free(err_msg);
    return writeError(session, id_val, -32601, err_msg);
}

// ─── Helpers ─────────────────────────────────────────────────────────

fn respondHttp(
    request: *std.http.Server.Request,
    status: std.http.Status,
    body: []const u8,
) !void {
    request.respond(body, .{
        .status = status,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
            .{ .name = "cache-control", .value = "no-store" },
        },
    }) catch return error.write_failed;
}

fn headerValue(request: *std.http.Server.Request, name: []const u8) ?[]const u8 {
    var it = request.iterateHeaders();
    while (it.next()) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, name)) return h.value;
    }
    return null;
}

/// Pull the bearer token out of the request — first the Authorization
/// header, then `?bearer=<hex64>` as a fallback for browser WS clients
/// (which can't set arbitrary headers on `new WebSocket(...)`).
fn extractBearer(target: []const u8, request: *std.http.Server.Request) ?[]const u8 {
    if (headerValue(request, "authorization")) |v| {
        if (parseBearerHeader(v)) |hex| return hex;
    }
    // Query-string fallback. Looks for `?bearer=` or `&bearer=` followed
    // by exactly 64 hex chars.
    return parseBearerQuery(target);
}

fn parseBearerHeader(value: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, value, " \t");
    if (!std.mem.startsWith(u8, trimmed, "Bearer ") and !std.mem.startsWith(u8, trimmed, "bearer ")) {
        return null;
    }
    const tok = std.mem.trim(u8, trimmed[7..], " \t");
    if (tok.len != 64) return null;
    if (!isHex64(tok)) return null;
    return tok;
}

fn parseBearerQuery(target: []const u8) ?[]const u8 {
    const q = std.mem.indexOfScalar(u8, target, '?') orelse return null;
    const qs = target[q + 1 ..];
    var it = std.mem.splitScalar(u8, qs, '&');
    while (it.next()) |pair| {
        if (std.mem.startsWith(u8, pair, "bearer=")) {
            const v = pair[7..];
            if (v.len != 64) return null;
            if (!isHex64(v)) return null;
            return v;
        }
    }
    return null;
}

fn isHex64(s: []const u8) bool {
    if (s.len != 64) return false;
    for (s) |c| {
        const ok = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
        if (!ok) return false;
    }
    return true;
}

fn asciiContainsCaseInsensitive(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}


```
