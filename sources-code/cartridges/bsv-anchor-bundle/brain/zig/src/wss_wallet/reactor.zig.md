---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/src/wss_wallet/reactor.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.450667+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/src/wss_wallet/reactor.zig

```zig
// B-pragmatic reactor integration for the wss_wallet endpoint —
// extracted from src/wss_wallet.zig as Phase 4 of the modularize.
// Pure code motion: no behaviour change.
//
// Owns: ReactorSession + tryUpgradeFromParsed + advanceFrame +
// handleReactorJsonRpc + the reactor* handler family + reactor write
// helpers + a few HTTP parsers shared with the reactor path.
//
// Distinct from src/wss_wallet/handlers.zig (the regular path's
// JSON-RPC handlers, called from serveSession's handleJsonRpc); the
// reactor* handlers below mirror those for the poll-based reactor
// transport in site_server.zig.

const std = @import("std");
const types = @import("types.zig");
const wss_codec = @import("wss_codec");
const http_parser_mod = @import("http_parser");
const helm_event_broker = @import("helm_event_broker");
const oddjobz_attention_handler = @import("oddjobz_attention_handler");
const cell_query_handler = @import("cell_query_handler");
const verb_dispatcher = @import("verb_dispatcher");
const manifest_registry = @import("manifest_registry");
const wss_operator_auth = @import("wss_operator_auth");
const sni_domain_map = @import("sni_domain_map");
const wrapped_dek_store = @import("wrapped_dek_store");
const bearer_tokens = @import("bearer_tokens");

const Backend = types.Backend;
const HELM_TOPICS = types.HELM_TOPICS;
const MAX_HELM_TOPICS_PER_SUB = types.MAX_HELM_TOPICS_PER_SUB;
const MAX_HELM_TOPIC_LEN = types.MAX_HELM_TOPIC_LEN;
const MAX_HELM_FETCH_LIMIT = types.MAX_HELM_FETCH_LIMIT;
const ServerVersion = types.ServerVersion;
const jsonEncodeString = types.jsonEncodeString;
const asciiContainsCaseInsensitive = types.asciiContainsCaseInsensitive;
const parseBearerHeader = types.parseBearerHeader;
const parseBearerQuery = types.parseBearerQuery;
const isHex64 = types.isHex64;

// JSON-RPC handlers (reactor calls back into the regular handler set
// for some paths; also borrows the OddjobzAttentionVerb enum when
// normalising verb strings).
const handlers = @import("handlers.zig");
const eventTypeMatchesTopics = types.eventTypeMatchesTopics;
const OddjobzAttentionVerb = handlers.OddjobzAttentionVerb;

pub const ReactorSession = struct {
    allocator: std.mem.Allocator,
    /// Set to the wss_wallet.Backend pointer when the HTTP→WSS upgrade
    /// fires.  Null for pure HTTP connections (session freed on close).
    backend: ?*Backend = null,
    /// W7.4/W7.5 — populated after hosted-operator auth; null in single-
    /// operator/dev mode (bearer token auth).  Used by wallet.getWrappedDek
    /// to scope the DEK load to the authenticated operator.
    authenticated_op_pkh16: ?[16]u8 = null,
    /// Helm subscription state — wired in Commit 6.
    /// Subscription ID returned by the broker; null when not subscribed.
    helm_sub_id: ?helm_event_broker.SubscriberId = null,
    helm_topics: ?[]const []const u8 = null,
    helm_topics_storage: ?[][]u8 = null,

    // REACTOR-DISPATCH (brain-wedge B-pragmatic Commit 6, 2026-05-07):
    //
    // Cross-thread helm event queue.
    //
    // The broker's publish() runs on whatever thread calls jobs.create
    // (typically the REPL dispatcher thread), while the reactor's
    // write_buf is touched only on the single reactor thread.  We bridge
    // the gap with a mutex-protected ArrayList of fully-encoded WSS text
    // frames.  The broker callback (reactorHelmEventCallback) appends
    // pre-encoded frames under the mutex; advanceFrame() drains the queue
    // into write_buf at the start of each inbound frame cycle.
    //
    // Because the reactor polls with a 100 ms timeout, events are
    // delivered within ~100 ms of publication at worst.  The mobile
    // AttentionService's 30 s polling timer is the safety net if the
    // connection is idle (no inbound frames to drive the drain).
    //
    // Frame encoding is done inside the broker callback (publisher thread)
    // so the reactor thread only does a memcpy during drain — fast enough
    // to hold the mutex safely.
    //
    // Bounded by HELM_EVENT_QUEUE_CAP: if the queue fills up (e.g. a very
    // bursty publisher with a stalled reactor), new events are silently
    // dropped from the callback side.  The mobile client can recover via
    // helm.fetch_since on reconnect.
    helm_event_mu: std.Thread.Mutex = .{},
    /// Pre-encoded WSS text frames for helm.event notifications, enqueued
    /// by the broker callback and drained into write_buf by advanceFrame.
    helm_event_queue: std.ArrayList(u8) = .{},

    /// Free any heap-allocated topics state.  Idempotent.
    pub fn freeTopics(self: *ReactorSession) void {
        if (self.helm_topics_storage) |storage| {
            for (storage) |t| self.allocator.free(t);
            self.allocator.free(storage);
            self.helm_topics_storage = null;
        }
        if (self.helm_topics) |topics| {
            self.allocator.free(topics);
            self.helm_topics = null;
        }
    }

    /// Unsubscribe from the broker (if subscribed) and free all helm state.
    /// Called by freeReactorCtx on connection close.
    pub fn helmTeardown(self: *ReactorSession, broker: *helm_event_broker.Broker) void {
        if (self.helm_sub_id) |id| {
            broker.unsubscribe(id);
            self.helm_sub_id = null;
        }
        self.freeTopics();
        self.helm_event_mu.lock();
        defer self.helm_event_mu.unlock();
        self.helm_event_queue.deinit(self.allocator);
        self.helm_event_queue = .{};
    }
};

/// Return value of tryUpgradeFromParsed.
pub const ReactorUpgradeResult = enum {
    /// Not a /api/v1/wallet upgrade request — dispatch to normal HTTP
    /// routing in the caller.
    not_a_wallet_upgrade,
    /// Valid upgrade — 101 response written to write_buf; caller should
    /// return .upgraded_to_wss from the dispatch_http callback.
    upgraded,
    /// Invalid upgrade — error response written to write_buf; caller should
    /// return .close_after_drain.
    rejected,
};

/// Reactor entry point: inspect a fully-parsed HTTP request and, if it is
/// a WS upgrade to /api/v1/wallet with valid auth, write the 101 response
/// to write_buf and return .upgraded.
///
/// Replaces the std.http.Server.Request-based tryUpgrade() for the reactor
/// path.  The caller (site_server.reactorDispatchHttp) also populates
/// session.backend so advanceFrame() can dispatch JSON-RPC methods.
pub fn tryUpgradeFromParsed(
    req: *const http_parser_mod.HttpRequest,
    backend: *Backend,
    session: *ReactorSession,
    write_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) ReactorUpgradeResult {
    // Path check — accept /api/v1/wallet exactly (query string stripped
    // by http_parser into req.path; query is in req.query).
    if (!std.mem.eql(u8, req.path, "/api/v1/wallet")) {
        return .not_a_wallet_upgrade;
    }

    // Must be GET.
    if (!std.mem.eql(u8, req.method, "GET")) {
        rawErrorResponse(write_buf, allocator, 405, "{\"error\":\"GET required for WS upgrade\"}");
        return .rejected;
    }

    // Upgrade header must be "websocket".
    const upgrade_val = req.header("upgrade") orelse {
        rawErrorResponse(write_buf, allocator, 400, "{\"error\":\"missing Upgrade: websocket\"}");
        return .rejected;
    };
    if (!std.ascii.eqlIgnoreCase(std.mem.trim(u8, upgrade_val, " \t"), "websocket")) {
        rawErrorResponse(write_buf, allocator, 400, "{\"error\":\"Upgrade must be websocket\"}");
        return .rejected;
    }

    // Connection header must contain "Upgrade".
    const conn_val = req.header("connection") orelse {
        rawErrorResponse(write_buf, allocator, 400, "{\"error\":\"missing Connection: Upgrade\"}");
        return .rejected;
    };
    if (!asciiContainsCaseInsensitive(conn_val, "Upgrade")) {
        rawErrorResponse(write_buf, allocator, 400, "{\"error\":\"Connection must contain Upgrade\"}");
        return .rejected;
    }

    // Sec-WebSocket-Key required.
    const ws_key = req.header("sec-websocket-key") orelse {
        rawErrorResponse(write_buf, allocator, 400, "{\"error\":\"missing Sec-WebSocket-Key\"}");
        return .rejected;
    };

    // Auth: hosted-operator mode (SNI+cert) or single-operator mode (bearer).
    if (backend.operator_domain_map) |domain_map| {
        // W7.4 — hosted-operator: validate via SNI hostname + BRC-52 cert chain.
        const host_val = req.header("host") orelse {
            rawErrorResponse(write_buf, allocator, 400, "{\"error\":\"missing Host header\"}");
            return .rejected;
        };
        const pubkey_hex = req.header(wss_operator_auth.PUBKEY_HEADER) orelse {
            rawErrorResponse(write_buf, allocator, 401, "{\"error\":\"missing X-Brain-Pubkey header\"}");
            return .rejected;
        };
        const auth_ctx = wss_operator_auth.authenticate(
            host_val,
            pubkey_hex,
            domain_map,
            backend.operator_data_dir,
            allocator,
        ) catch |err| {
            const msg = switch (err) {
                error.sni_not_registered => "{\"error\":\"operator domain not registered\"}",
                error.missing_pubkey_header => "{\"error\":\"missing X-Brain-Pubkey header\"}",
                error.bad_pubkey_format => "{\"error\":\"X-Brain-Pubkey must be 66 hex chars (compressed secp256k1)\"}",
                error.cert_not_found => "{\"error\":\"cert not found for this operator\"}",
                error.cert_chain_broken => "{\"error\":\"cert chain broken or revoked\"}",
                error.store_load_failed => "{\"error\":\"operator cert store unavailable\"}",
                error.out_of_memory => "{\"error\":\"internal\"}",
            };
            rawErrorResponse(write_buf, allocator, 401, msg);
            return .rejected;
        };
        // W7.5 — pin authenticated op_pkh16 onto the session for wallet.getWrappedDek.
        session.authenticated_op_pkh16 = auth_ctx.op_pkh16;
    } else {
        // Single-operator / dev mode: bearer token auth.
        const auth_hex = extractBearerFromParsed(req) orelse {
            rawErrorResponse(write_buf, allocator, 401, "{\"error\":\"missing bearer token (Authorization header or ?bearer=<hex64>)\"}");
            return .rejected;
        };
        _ = backend.tokens.verifyHex(auth_hex) catch |err| {
            const msg = switch (err) {
                error.expired => "{\"error\":\"bearer token expired\"}",
                error.bad_format => "{\"error\":\"bearer token must be 64 hex chars\"}",
                else => "{\"error\":\"bearer token not recognised\"}",
            };
            rawErrorResponse(write_buf, allocator, 401, msg);
            return .rejected;
        };
    }

    // All checks passed.  Write the 101 Switching Protocols response.
    var accept_b64: [28]u8 = undefined;
    wss_codec.computeAccept(ws_key, &accept_b64);
    var hdr_buf: [256]u8 = undefined;
    const hdr = std.fmt.bufPrint(
        &hdr_buf,
        "HTTP/1.1 101 Switching Protocols\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Accept: {s}\r\n\r\n",
        .{&accept_b64},
    ) catch {
        // bufPrint should never fail for this fixed-size format.
        rawErrorResponse(write_buf, allocator, 500, "{\"error\":\"internal\"}");
        return .rejected;
    };
    write_buf.appendSlice(allocator, hdr) catch {
        return .rejected;
    };

    // Wire the backend into the session so advanceFrame() can dispatch.
    session.backend = backend;

    return .upgraded;
}

/// Return value of advanceFrame.
pub const AdvanceFrameResult = enum {
    keep_open,
    close_after_drain,
    close_immediately,
};

/// Reactor per-frame WSS handler.  Called by site_server.reactorDispatchWss
/// each time the frame parser produces a complete frame.
///
/// Writes response bytes directly into write_buf (server→client frames,
/// unmasked per RFC 6455 §5.1).  Returns the desired connection outcome.
///
/// REACTOR-DISPATCH (brain-wedge B-pragmatic Commit 6, 2026-05-07):
///   Before dispatching the incoming frame, drain any pending helm.event
///   notification frames from the cross-thread queue into write_buf.
///   See ReactorSession.helm_event_queue for the threading contract.
pub fn advanceFrame(
    session: *ReactorSession,
    frame: wss_codec.Frame,
    write_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) AdvanceFrameResult {
    const backend = session.backend orelse {
        // Should never happen — session.backend is set in tryUpgradeFromParsed
        // before any WSS frames arrive.  Close defensively.
        return .close_immediately;
    };

    // REACTOR-DISPATCH (brain-wedge B-pragmatic Commit 6, 2026-05-07):
    //   Drain pending helm.event frames enqueued by the broker callback
    //   (running on the publisher's thread) into write_buf (reactor thread).
    //   We hold the mutex only long enough to swap out the queued bytes.
    {
        session.helm_event_mu.lock();
        const queued = session.helm_event_queue.items;
        if (queued.len > 0) {
            write_buf.appendSlice(allocator, queued) catch {};
            session.helm_event_queue.clearRetainingCapacity();
        }
        session.helm_event_mu.unlock();
    }

    switch (frame.opcode) {
        .close => {
            // RFC 6455 §5.5.1 — echo close frame then close.
            reactorWriteClose(write_buf, allocator, 1000, "bye");
            return .close_after_drain;
        },
        .ping => {
            // RFC 6455 §5.5.3 — pong with same payload.
            reactorWriteFrame(write_buf, allocator, .pong, frame.payload) catch {};
            return .keep_open;
        },
        .pong => return .keep_open, // unsolicited pong — ignore
        .text => {
            handleReactorJsonRpc(session, backend, frame.payload, write_buf, allocator) catch |err| {
                // Per-message failure — write an internal-error JSON-RPC
                // response and keep the session alive.
                const msg = std.fmt.allocPrint(
                    allocator,
                    "{{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{{\"code\":-32603,\"message\":\"internal: {s}\"}}}}",
                    .{@errorName(err)},
                ) catch return .keep_open;
                defer allocator.free(msg);
                reactorWriteFrame(write_buf, allocator, .text, msg) catch {};
            };
            return .keep_open;
        },
        else => {
            // Binary / continuation / unknown — close with 1003.
            reactorWriteClose(write_buf, allocator, 1003, "only text frames supported");
            return .close_after_drain;
        },
    }
}

/// JSON-RPC dispatcher for the reactor path.
/// Writes the response directly into write_buf.
/// Semantics identical to handleJsonRpc() except no stream/mutex.
fn handleReactorJsonRpc(
    session: *ReactorSession,
    backend: *Backend,
    body: []const u8,
    write_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
        const msg = "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":\"parse error: body is not valid JSON\"}}";
        return reactorWriteFrame(write_buf, allocator, .text, msg);
    };
    defer parsed.deinit();

    if (parsed.value != .object) {
        const msg = "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32600,\"message\":\"invalid request: must be a JSON object\"}}";
        return reactorWriteFrame(write_buf, allocator, .text, msg);
    }

    const id_val = parsed.value.object.get("id") orelse std.json.Value{ .null = {} };
    const method_val = parsed.value.object.get("method") orelse {
        return reactorWriteError(write_buf, allocator, id_val, -32600, "invalid request: missing 'method'");
    };
    if (method_val != .string) {
        return reactorWriteError(write_buf, allocator, id_val, -32600, "invalid request: 'method' must be a string");
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
        return reactorWriteResult(write_buf, allocator, id_val, result);
    }
    if (std.mem.eql(u8, method, "wallet.getNetwork")) {
        const result = try std.fmt.allocPrint(
            allocator,
            "{{\"network\":\"{s}\"}}",
            .{backend.network.asString()},
        );
        defer allocator.free(result);
        return reactorWriteResult(write_buf, allocator, id_val, result);
    }
    if (std.mem.eql(u8, method, "wallet.getAuthStatus")) {
        return reactorWriteResult(write_buf, allocator, id_val,
            "{\"authenticated\":false,\"reason\":\"wallet-engine-not-yet-wired\"}");
    }
    if (std.mem.eql(u8, method, "wallet.echo")) {
        const params_json = try std.json.Stringify.valueAlloc(allocator, params, .{});
        defer allocator.free(params_json);
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(allocator);
        try buf.appendSlice(allocator, "{\"echo\":");
        try buf.appendSlice(allocator, params_json);
        try buf.append(allocator, '}');
        return reactorWriteResult(write_buf, allocator, id_val, buf.items);
    }

    // REACTOR-DISPATCH (brain-wedge B-pragmatic Commit 6, 2026-05-07):
    //   The branches below dispatch helm.* and oddjobz.* to the same
    //   handlers the old serveSession path uses (lines ~524-585 of this
    //   file for helm, ~542-584 for oddjobz).  Reactor and serveSession
    //   share the handler logic — only the I/O surface differs (write_buf
    //   ArrayList vs stream + mutex).
    //   To revert: replace each branch below with the -32603 stub from
    //   Commit 5 and restore the single "helm. or oddjobz." catch-all.

    // ── D-O5.followup-4 — helm.subscribe / helm.unsubscribe ──────────
    if (std.mem.eql(u8, method, "helm.subscribe")) {
        return reactorHandleHelmSubscribe(session, backend, id_val, params, write_buf, allocator);
    }
    if (std.mem.eql(u8, method, "helm.unsubscribe")) {
        return reactorHandleHelmUnsubscribe(session, backend, id_val, write_buf, allocator);
    }

    // REACTOR-DISPATCH (brain-wedge B-pragmatic Commit 6, 2026-05-07):
    //   This branch dispatches helm.fetch_since to the same broker
    //   fetchSince path the old serveSession uses (line ~535 of this
    //   file).  Reactor and serveSession share the handler — only the
    //   I/O surface differs.  To revert: replace with the -32603 stub.
    if (std.mem.eql(u8, method, "helm.fetch_since")) {
        return reactorHandleHelmFetchSince(session, backend, id_val, params, write_buf, allocator);
    }

    // C4 PR-J5b — the legacy `oddjobz.ratify_proposal` reactor branch was
    // retired; ratification flows through the generic `ratify.submit` branch
    // (reactorHandleRatifySubmit, below) with namespace:"oddjobz".

    // C4 PR-J3 — the bespoke oddjobz query verbs were retired; reads flow
    // through the generic `cell.query`/`cell.get` reactor branches (below).

    // REACTOR-DISPATCH (brain-wedge B-pragmatic Commit 6, 2026-05-07):
    //   These branches dispatch oddjobz attention verbs to the same
    //   AttentionHandler the old serveSession uses (lines ~577-584).
    //   To revert: replace each branch with the -32603 stub from Commit 5.
    if (std.mem.eql(u8, method, "oddjobz.list_messages")) {
        return reactorHandleOddjobzAttention(session, backend, id_val, params, .list_messages, write_buf, allocator);
    }
    if (std.mem.eql(u8, method, "oddjobz.list_dispatch_decisions")) {
        return reactorHandleOddjobzAttention(session, backend, id_val, params, .list_dispatch_decisions, write_buf, allocator);
    }
    if (std.mem.eql(u8, method, "oddjobz.poll_attention_signals")) {
        return reactorHandleOddjobzAttention(session, backend, id_val, params, .poll_attention_signals, write_buf, allocator);
    }
    // C4 PR-J4 — generic namespace-scoped attention feed.
    if (std.mem.eql(u8, method, "attention.poll")) {
        return reactorHandleAttentionPoll(session, backend, id_val, params, write_buf, allocator);
    }
    // C4 PR-J5 — generic namespace-routed ratify.
    if (std.mem.eql(u8, method, "ratify.submit")) {
        return reactorHandleRatifySubmit(session, backend, id_val, params, write_buf, allocator);
    }

    // W7.5 — hosted-operator: return the wrapped DEK for the authenticated operator.
    if (std.mem.eql(u8, method, "wallet.getWrappedDek")) {
        return reactorHandleGetWrappedDek(session, backend, id_val, write_buf, allocator);
    }

    // D-RTC.4 — generic verb dispatch. Routes to the verb_registry
    // walkers (substrate.entity.encode, jambox.launch_clip, etc).
    // Wire shape: {jsonrpc:"2.0", method:"verb.dispatch",
    //   params:{extensionId:"<ext>", verb:"<v>", params:{...}}, id:n}
    // Returns the walker's JSON result body verbatim. Errors map to
    // standard JSON-RPC codes (-32602 invalid params, -32601 unknown
    // walker, -32603 walker failed).
    if (std.mem.eql(u8, method, "verb.dispatch")) {
        return reactorHandleVerbDispatch(backend, id_val, params, write_buf, allocator);
    }

    return reactorWriteError(write_buf, allocator, id_val, -32601,
        "method not found");
}

/// D-RTC.4 — generic verb.dispatch handler. Reads {extensionId, verb,
/// params} out of the JSON-RPC params object and routes through the
/// existing reactorDispatchToCartridge helper. Returns walker_not_found
/// as -32601 (unknown method) at the JSON-RPC layer so clients can
/// distinguish "no walker registered" from "walker rejected input".
fn reactorHandleVerbDispatch(
    backend: *Backend,
    id_val: std.json.Value,
    params: std.json.Value,
    write_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    if (params != .object) {
        return reactorWriteError(write_buf, allocator, id_val, -32602,
            "verb.dispatch params must be an object");
    }
    const ext_val = params.object.get("extensionId") orelse {
        return reactorWriteError(write_buf, allocator, id_val, -32602,
            "verb.dispatch missing extensionId");
    };
    if (ext_val != .string or ext_val.string.len == 0) {
        return reactorWriteError(write_buf, allocator, id_val, -32602,
            "verb.dispatch extensionId must be a non-empty string");
    }
    const verb_val = params.object.get("verb") orelse {
        return reactorWriteError(write_buf, allocator, id_val, -32602,
            "verb.dispatch missing verb");
    };
    if (verb_val != .string or verb_val.string.len == 0) {
        return reactorWriteError(write_buf, allocator, id_val, -32602,
            "verb.dispatch verb must be a non-empty string");
    }
    const inner_params = params.object.get("params") orelse std.json.Value{ .object = std.json.ObjectMap.init(allocator) };
    const routed = try reactorDispatchToCartridge(
        write_buf, allocator, backend, id_val, ext_val.string, verb_val.string, inner_params,
    );
    if (!routed) {
        return reactorWriteError(write_buf, allocator, id_val, -32601,
            "no walker registered for that extensionId/verb");
    }
}

// ─── Reactor-path helm and oddjobz handlers ──────────────────────────
//
// REACTOR-DISPATCH (brain-wedge B-pragmatic Commit 6, 2026-05-07):
//   These functions mirror the serveSession-path handlers (see lines
//   ~598-1019) for the reactor path.  The logic is identical; the only
//   difference is:
//     • serveSession path: session: *SessionState, writes via lockedWriteFrame
//     • reactor path:      session: *ReactorSession, writes into write_buf
//   Both paths share the Backend handlers (helm_broker, oddjobz_ratify,
//   oddjobz_query, oddjobz_attention) — the separation is purely I/O.

/// Broker callback registered by reactorHandleHelmSubscribe.
/// Runs on the publisher's thread (inside the broker mutex).
/// Encodes the helm.event notification as a WSS text frame and appends
/// it to the per-session helm_event_queue for the reactor to drain.
///
/// REACTOR-DISPATCH (brain-wedge B-pragmatic Commit 6, 2026-05-07):
///   This callback is the cross-thread bridge for helm.subscribe push.
///   See ReactorSession.helm_event_queue for the full threading contract.
///   To revert: remove the broker.subscribe() call in
///   reactorHandleHelmSubscribe and return a -32603 stub instead.
fn reactorHelmEventCallback(state: ?*anyopaque, event: helm_event_broker.Event) void {
    const session: *ReactorSession = @ptrCast(@alignCast(state.?));
    if (!eventTypeMatchesTopics(event.type, session.helm_topics)) return;

    // Build the notification JSON body:
    //   {"jsonrpc":"2.0","method":"helm.event",
    //    "params":{"type":"<type>","data":<payload>}}
    // Then encode it as a complete WSS text frame (unmasked, server→client).
    // We allocate a scratch buffer on the heap here because we're on the
    // publisher thread (not the reactor thread) — stack size is unknown.
    const allocator = session.allocator;

    var json_body: std.ArrayList(u8) = .{};
    defer json_body.deinit(allocator);
    json_body.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"method\":\"helm.event\",\"params\":{\"type\":") catch return;
    jsonEncodeString(allocator, &json_body, event.type) catch return;
    json_body.appendSlice(allocator, ",\"data\":") catch return;
    json_body.appendSlice(allocator, event.payload_json) catch return;
    json_body.appendSlice(allocator, "}}") catch return;

    // Encode as WSS frame bytes so the reactor thread only needs to
    // append pre-built bytes (no encoding work under the mutex).
    var frame_bytes: std.ArrayList(u8) = .{};
    defer frame_bytes.deinit(allocator);
    // Build frame header: FIN|text, length.
    const payload = json_body.items;
    var hdr: [4]u8 = undefined;
    var hdr_len: usize = 2;
    hdr[0] = 0x80 | @as(u8, @intFromEnum(wss_codec.Opcode.text)); // FIN | text
    if (payload.len < 126) {
        hdr[1] = @intCast(payload.len);
    } else if (payload.len <= 65535) {
        hdr[1] = 126;
        std.mem.writeInt(u16, hdr[2..4], @intCast(payload.len), .big);
        hdr_len = 4;
    } else {
        return; // payload too large — drop silently (defensive cap)
    }
    frame_bytes.appendSlice(allocator, hdr[0..hdr_len]) catch return;
    frame_bytes.appendSlice(allocator, payload) catch return;

    // Append to the cross-thread queue under the mutex.
    // The reactor drains this in advanceFrame() at the start of each
    // inbound frame cycle.
    session.helm_event_mu.lock();
    defer session.helm_event_mu.unlock();
    // Bounded: if the queue is already large (stalled reactor), drop.
    // 256 KiB is enough for hundreds of events; beyond that the client
    // reconnects and uses helm.fetch_since.
    const HELM_EVENT_QUEUE_CAP: usize = 256 * 1024;
    if (session.helm_event_queue.items.len + frame_bytes.items.len > HELM_EVENT_QUEUE_CAP) return;
    session.helm_event_queue.appendSlice(allocator, frame_bytes.items) catch return;
}

/// REACTOR-DISPATCH (brain-wedge B-pragmatic Commit 6, 2026-05-07):
///   Mirrors handleHelmSubscribe (line ~598) for the reactor path.
///   Topic validation, owned storage allocation, and broker registration
///   are identical; write target is write_buf instead of a stream.
fn reactorHandleHelmSubscribe(
    session: *ReactorSession,
    backend: *Backend,
    id_val: std.json.Value,
    params: std.json.Value,
    write_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    const broker = backend.helm_broker orelse {
        return reactorWriteError(write_buf, allocator, id_val, -32603, "helm broker unavailable on this server");
    };

    if (params != .object) {
        return reactorWriteError(write_buf, allocator, id_val, -32602, "helm.subscribe params must be an object");
    }
    const topics_val = params.object.get("topics") orelse {
        return reactorWriteError(write_buf, allocator, id_val, -32602, "helm.subscribe missing 'topics' array");
    };
    if (topics_val != .array) {
        return reactorWriteError(write_buf, allocator, id_val, -32602, "helm.subscribe 'topics' must be an array of strings");
    }
    if (topics_val.array.items.len == 0) {
        return reactorWriteError(write_buf, allocator, id_val, -32602, "helm.subscribe 'topics' must not be empty");
    }
    if (topics_val.array.items.len > MAX_HELM_TOPICS_PER_SUB) {
        return reactorWriteError(write_buf, allocator, id_val, -32602, "helm.subscribe 'topics' exceeds maximum");
    }

    // Pre-validate all entries before any allocation (mirrors serveSession path).
    for (topics_val.array.items) |item| {
        if (item != .string) {
            return reactorWriteError(write_buf, allocator, id_val, -32602, "helm.subscribe 'topics' must be strings");
        }
        if (item.string.len == 0 or item.string.len > MAX_HELM_TOPIC_LEN) {
            return reactorWriteError(write_buf, allocator, id_val, -32602, "helm.subscribe topic length out of range");
        }
        var matched = false;
        for (HELM_TOPICS) |known| {
            if (std.mem.eql(u8, item.string, known)) {
                matched = true;
                break;
            }
        }
        if (!matched) {
            return reactorWriteError(write_buf, allocator, id_val, -32602, "helm.subscribe unknown topic");
        }
    }

    // Allocate owned topic storage.
    const owned_storage = try allocator.alloc([]u8, topics_val.array.items.len);
    errdefer allocator.free(owned_storage);
    var allocated: usize = 0;
    errdefer {
        var i: usize = 0;
        while (i < allocated) : (i += 1) allocator.free(owned_storage[i]);
    }
    for (topics_val.array.items, 0..) |item, i| {
        owned_storage[i] = try allocator.dupe(u8, item.string);
        allocated = i + 1;
    }

    const view = try allocator.alloc([]const u8, owned_storage.len);
    errdefer allocator.free(view);
    for (owned_storage, 0..) |t, i| view[i] = t;

    // Replace any prior subscription.
    if (session.helm_sub_id) |id| {
        broker.unsubscribe(id);
        session.helm_sub_id = null;
    }
    session.freeTopics();

    // Clear any stale queued events from the prior subscription.
    {
        session.helm_event_mu.lock();
        defer session.helm_event_mu.unlock();
        session.helm_event_queue.clearRetainingCapacity();
    }

    // Assign storage, register callback, write success response.
    session.helm_topics_storage = owned_storage;
    session.helm_topics = view;
    const sub_id = broker.subscribe(.{
        .state = session,
        .callback = reactorHelmEventCallback,
    }) catch {
        session.freeTopics();
        return reactorWriteError(write_buf, allocator, id_val, -32603, "helm.subscribe broker registration failed");
    };
    session.helm_sub_id = sub_id;

    var body: std.ArrayList(u8) = .{};
    defer body.deinit(allocator);
    try body.appendSlice(allocator, "{\"subscribed\":true,\"topics\":[");
    for (view, 0..) |t, i| {
        if (i != 0) try body.append(allocator, ',');
        try jsonEncodeString(allocator, &body, t);
    }
    try body.append(allocator, ']');
    try body.append(allocator, '}');
    return reactorWriteResult(write_buf, allocator, id_val, body.items);
}

/// REACTOR-DISPATCH (brain-wedge B-pragmatic Commit 6, 2026-05-07):
///   Mirrors handleHelmUnsubscribe (line ~696) for the reactor path.
fn reactorHandleHelmUnsubscribe(
    session: *ReactorSession,
    backend: *Backend,
    id_val: std.json.Value,
    write_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    const broker = backend.helm_broker orelse {
        return reactorWriteError(write_buf, allocator, id_val, -32603, "helm broker unavailable on this server");
    };
    if (session.helm_sub_id) |id| {
        broker.unsubscribe(id);
        session.helm_sub_id = null;
    }
    session.freeTopics();
    {
        session.helm_event_mu.lock();
        defer session.helm_event_mu.unlock();
        session.helm_event_queue.clearRetainingCapacity();
    }
    return reactorWriteResult(write_buf, allocator, id_val, "{\"unsubscribed\":true}");
}

/// REACTOR-DISPATCH (brain-wedge B-pragmatic Commit 6, 2026-05-07):
///   Mirrors handleHelmFetchSince (line ~724) for the reactor path.
///   This branch dispatches helm.fetch_since to the same broker.fetchSince
///   path the old serveSession uses.  Reactor and serveSession share the
///   handler — only the I/O surface differs.
fn reactorHandleHelmFetchSince(
    session: *ReactorSession,
    backend: *Backend,
    id_val: std.json.Value,
    params: std.json.Value,
    write_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    _ = session;
    const broker = backend.helm_broker orelse {
        return reactorWriteError(write_buf, allocator, id_val, -32603, "helm broker unavailable on this server");
    };

    if (params != .object) {
        return reactorWriteError(write_buf, allocator, id_val, -32602, "helm.fetch_since params must be an object");
    }
    const since_val = params.object.get("since_ts") orelse {
        return reactorWriteError(write_buf, allocator, id_val, -32602, "helm.fetch_since missing 'since_ts'");
    };
    if (since_val != .integer) {
        return reactorWriteError(write_buf, allocator, id_val, -32602, "helm.fetch_since 'since_ts' must be an integer");
    }
    if (since_val.integer < 0) {
        return reactorWriteError(write_buf, allocator, id_val, -32602, "helm.fetch_since 'since_ts' must be non-negative");
    }
    var limit: u32 = MAX_HELM_FETCH_LIMIT;
    if (params.object.get("limit")) |limit_val| {
        if (limit_val != .integer) {
            return reactorWriteError(write_buf, allocator, id_val, -32602, "helm.fetch_since 'limit' must be an integer");
        }
        if (limit_val.integer < 1) {
            return reactorWriteError(write_buf, allocator, id_val, -32602, "helm.fetch_since 'limit' must be >= 1");
        }
        const clamped: u32 = if (limit_val.integer > @as(i64, MAX_HELM_FETCH_LIMIT))
            MAX_HELM_FETCH_LIMIT
        else
            @intCast(limit_val.integer);
        limit = clamped;
    }

    var cursor: i64 = since_val.integer;
    const events = broker.fetchSince(allocator, since_val.integer, limit, &cursor) catch
        return reactorWriteError(write_buf, allocator, id_val, -32603, "helm.fetch_since broker error");
    defer allocator.free(events);

    var body: std.ArrayList(u8) = .{};
    defer body.deinit(allocator);
    try body.appendSlice(allocator, "{\"events\":[");
    for (events, 0..) |ev, i| {
        if (i != 0) try body.append(allocator, ',');
        try body.appendSlice(allocator, "{\"event_id\":\"");
        try body.appendSlice(allocator, &ev.event_id);
        try body.appendSlice(allocator, "\",\"ts\":");
        const ts_str = try std.fmt.allocPrint(allocator, "{d}", .{ev.ts});
        defer allocator.free(ts_str);
        try body.appendSlice(allocator, ts_str);
        try body.appendSlice(allocator, ",\"kind\":");
        try jsonEncodeString(allocator, &body, ev.type);
        try body.appendSlice(allocator, ",\"payload\":");
        try body.appendSlice(allocator, ev.payload_json);
        try body.append(allocator, '}');
    }
    try body.appendSlice(allocator, "],\"next_cursor_ts\":");
    const cur_str = try std.fmt.allocPrint(allocator, "{d}", .{cursor});
    defer allocator.free(cur_str);
    try body.appendSlice(allocator, cur_str);
    try body.append(allocator, '}');
    return reactorWriteResult(write_buf, allocator, id_val, body.items);
}

/// REACTOR-DISPATCH (brain-wedge B-pragmatic Commit 6, 2026-05-07):
///   Mirrors handleOddjobzAttention (line ~983) for the reactor path.
///   Dispatches oddjobz attention verbs to the same AttentionHandler
///   the old serveSession uses.  To revert: replace each call site in
///   handleReactorJsonRpc with the -32603 stub from Commit 5.
fn reactorHandleOddjobzAttention(
    session: *ReactorSession,
    backend: *Backend,
    id_val: std.json.Value,
    params: std.json.Value,
    verb: OddjobzAttentionVerb,
    write_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    _ = session;
    const handler = backend.oddjobz_attention orelse {
        // DLDC-W.2.3 — cartridge route fallback via @tagName(verb).
        if (try reactorDispatchToCartridge(write_buf, allocator, backend, id_val, "oddjobz", @tagName(verb), params)) return;
        return reactorWriteError(write_buf, allocator, id_val, -32603, "oddjobz attention seam unavailable on this server");
    };

    const params_json = std.json.Stringify.valueAlloc(allocator, params, .{}) catch {
        return reactorWriteError(write_buf, allocator, id_val, -32603, "oddjobz attention: serialise failed");
    };
    defer allocator.free(params_json);

    const body = switch (verb) {
        .list_messages => handler.listMessages(allocator, params_json),
        .list_dispatch_decisions => handler.listDispatchDecisions(allocator, params_json),
        .poll_attention_signals => handler.pollAttentionSignals(allocator, params_json),
    } catch |err| {
        const code: i32 = switch (err) {
            error.invalid_params => -32602,
            error.out_of_memory => -32603,
            error.io_error => -32603,
        };
        const msg = switch (err) {
            error.invalid_params => "oddjobz attention: invalid params",
            error.out_of_memory => "oddjobz attention: out of memory",
            error.io_error => "oddjobz attention: JSONL read error",
        };
        return reactorWriteError(write_buf, allocator, id_val, code, msg);
    };
    defer allocator.free(body);
    return reactorWriteResult(write_buf, allocator, id_val, body);
}

/// C4 PR-J4 — reactor twin of handleAttentionPoll (generic namespace-scoped
/// attention feed). params { namespaces: [ "<ns>", … ], limit?: int }.
fn reactorHandleAttentionPoll(
    session: *ReactorSession,
    backend: *Backend,
    id_val: std.json.Value,
    params: std.json.Value,
    write_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    _ = session;
    const handler = backend.attention orelse {
        return reactorWriteError(write_buf, allocator, id_val, -32603, "attention.poll seam unavailable on this server");
    };
    if (params != .object) {
        return reactorWriteError(write_buf, allocator, id_val, -32602, "attention.poll params must be an object");
    }
    const ns_val = params.object.get("namespaces") orelse {
        return reactorWriteError(write_buf, allocator, id_val, -32602, "attention.poll: missing 'namespaces'");
    };
    if (ns_val != .array) {
        return reactorWriteError(write_buf, allocator, id_val, -32602, "attention.poll: 'namespaces' must be an array of strings");
    }
    var ns_list = std.ArrayList([]const u8){};
    defer ns_list.deinit(allocator);
    for (ns_val.array.items) |item| {
        if (item != .string) {
            return reactorWriteError(write_buf, allocator, id_val, -32602, "attention.poll: namespaces must be strings");
        }
        ns_list.append(allocator, item.string) catch {
            return reactorWriteError(write_buf, allocator, id_val, -32603, "attention.poll: out of memory");
        };
    }
    var limit: usize = 50;
    if (params.object.get("limit")) |lv| {
        if (lv == .integer and lv.integer > 0) limit = @intCast(lv.integer);
    }
    const body = handler.poll(allocator, ns_list.items, limit) catch |err| {
        const code: i32 = switch (err) {
            error.invalid_params => -32602,
            error.out_of_memory, error.source_error => -32603,
        };
        const msg = switch (err) {
            error.invalid_params => "attention.poll: invalid params",
            error.out_of_memory => "attention.poll: out of memory",
            error.source_error => "attention.poll: an attention source failed",
        };
        return reactorWriteError(write_buf, allocator, id_val, code, msg);
    };
    defer allocator.free(body);
    return reactorWriteResult(write_buf, allocator, id_val, body);
}

/// C4 PR-J5 — reactor twin of handleRatifySubmit (generic namespace-routed
/// ratify). params { namespace, proposal_id, sir_program, payload_hint }.
fn reactorHandleRatifySubmit(
    session: *ReactorSession,
    backend: *Backend,
    id_val: std.json.Value,
    params: std.json.Value,
    write_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    _ = session;
    const handler = backend.ratify orelse {
        return reactorWriteError(write_buf, allocator, id_val, -32603, "ratify.submit seam unavailable on this server (was --enable-repl set?)");
    };
    if (params != .object) {
        return reactorWriteError(write_buf, allocator, id_val, -32602, "ratify.submit params must be an object");
    }
    const ns_val = params.object.get("namespace") orelse {
        return reactorWriteError(write_buf, allocator, id_val, -32602, "ratify.submit: missing 'namespace'");
    };
    if (ns_val != .string or ns_val.string.len == 0) {
        return reactorWriteError(write_buf, allocator, id_val, -32602, "ratify.submit: 'namespace' must be a non-empty string");
    }
    const params_json = std.json.Stringify.valueAlloc(allocator, params, .{}) catch {
        return reactorWriteError(write_buf, allocator, id_val, -32603, "ratify.submit serialise failed");
    };
    defer allocator.free(params_json);

    const body = handler.submit(allocator, ns_val.string, params_json) catch |err| {
        const code: i32 = switch (err) {
            error.no_builder => -32601,
            error.builder_failed => -32000,
            error.out_of_memory => -32603,
        };
        const msg = switch (err) {
            error.no_builder => "ratify.submit: no builder registered for that namespace",
            error.builder_failed => "ratify.submit: graph builder rejected the proposal",
            error.out_of_memory => "ratify.submit: out of memory",
        };
        return reactorWriteError(write_buf, allocator, id_val, code, msg);
    };
    defer allocator.free(body);
    return reactorWriteResult(write_buf, allocator, id_val, body);
}

// ─── Reactor write helpers ────────────────────────────────────────────
// These write directly to an ArrayList(u8) write_buf rather than a
// stream, since the reactor drains the buffer via POLL.OUT.

/// Write a server→client WebSocket frame (unmasked) into write_buf.
/// Handles payloads up to 64 KiB (beyond that, close with 1009).
/// W7.5 — wallet.getWrappedDek: return the wrapped DEK for the authenticated
/// operator.  Only valid in hosted-operator mode (session.authenticated_op_pkh16
/// must be set by tryUpgradeFromParsed after W7.4 operator auth).
fn reactorHandleGetWrappedDek(
    session: *ReactorSession,
    backend: *Backend,
    id_val: std.json.Value,
    write_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) !void {
    const op_pkh16 = session.authenticated_op_pkh16 orelse {
        return reactorWriteError(write_buf, allocator, id_val, -32603,
            "wallet.getWrappedDek is only available in hosted-operator mode");
    };
    const hex = wrapped_dek_store.load(allocator, backend.operator_data_dir, op_pkh16) catch |err| {
        const msg = switch (err) {
            error.not_found => "wrapped DEK not provisioned for this operator",
            error.bad_format => "wrapped DEK stored in unexpected format",
            error.file_io => "wrapped DEK file I/O error",
            error.out_of_memory => "internal",
        };
        return reactorWriteError(write_buf, allocator, id_val, -32603, msg);
    };
    defer allocator.free(hex);
    var result: std.ArrayList(u8) = .{};
    defer result.deinit(allocator);
    try result.appendSlice(allocator, "{\"wrapped_dek\":\"");
    try result.appendSlice(allocator, hex);
    try result.appendSlice(allocator, "\"}");
    return reactorWriteResult(write_buf, allocator, id_val, result.items);
}

fn reactorWriteFrame(
    write_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    opcode: wss_codec.Opcode,
    payload: []const u8,
) !void {
    // Build the frame header (opcode byte + length encoding).
    var hdr: [4]u8 = undefined;
    var hdr_len: usize = 2;
    hdr[0] = 0x80 | @as(u8, @intFromEnum(opcode)); // FIN | opcode
    if (payload.len < 126) {
        hdr[1] = @intCast(payload.len);
    } else if (payload.len <= 65535) {
        hdr[1] = 126;
        std.mem.writeInt(u16, hdr[2..4], @intCast(payload.len), .big);
        hdr_len = 4;
    } else {
        // > 64 KiB shouldn't happen — the frame parser caps at MAX_PAYLOAD.
        return error.PayloadTooLarge;
    }
    try write_buf.appendSlice(allocator, hdr[0..hdr_len]);
    try write_buf.appendSlice(allocator, payload);
}

/// Write a close frame into write_buf with a 2-byte status code.
fn reactorWriteClose(
    write_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    status: u16,
    reason: []const u8,
) void {
    var payload: [128]u8 = undefined;
    std.mem.writeInt(u16, payload[0..2], status, .big);
    const reason_len = @min(reason.len, payload.len - 2);
    @memcpy(payload[2 .. 2 + reason_len], reason[0..reason_len]);
    // 0x88 = FIN | close opcode (0x08)
    var hdr = [_]u8{ 0x88, @intCast(2 + reason_len) };
    write_buf.appendSlice(allocator, &hdr) catch return;
    write_buf.appendSlice(allocator, payload[0 .. 2 + reason_len]) catch return;
}

/// Write a JSON-RPC result response frame.
fn reactorWriteResult(
    write_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    id: std.json.Value,
    result_json: []const u8,
) !void {
    const id_json = try std.json.Stringify.valueAlloc(allocator, id, .{});
    defer allocator.free(id_json);
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":");
    try buf.appendSlice(allocator, id_json);
    try buf.appendSlice(allocator, ",\"result\":");
    try buf.appendSlice(allocator, result_json);
    try buf.append(allocator, '}');
    try reactorWriteFrame(write_buf, allocator, .text, buf.items);
}

/// Write a JSON-RPC error response frame.
fn reactorWriteError(
    write_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    id: std.json.Value,
    code: i32,
    message: []const u8,
) !void {
    const id_json = try std.json.Stringify.valueAlloc(allocator, id, .{});
    defer allocator.free(id_json);
    var code_buf: [32]u8 = undefined;
    const code_str = try std.fmt.bufPrint(&code_buf, "{d}", .{code});
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"jsonrpc\":\"2.0\",\"id\":");
    try buf.appendSlice(allocator, id_json);
    try buf.appendSlice(allocator, ",\"error\":{\"code\":");
    try buf.appendSlice(allocator, code_str);
    try buf.appendSlice(allocator, ",\"message\":");
    try jsonEncodeString(allocator, &buf, message);
    try buf.appendSlice(allocator, "}}");
    try reactorWriteFrame(write_buf, allocator, .text, buf.items);
}

/// DLDC-W.2.3 — reactor-side dispatch-to-cartridge fallback helper.
///
/// Sibling of `wss_wallet/types.zig:dispatchToCartridge` for the
/// reactor.zig write path (write_buf instead of session.stream).
/// Same contract: returns true if it handled the response, false if
/// no cartridge route was available — caller falls through to V1
/// "seam unavailable" error.
fn reactorDispatchToCartridge(
    write_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    backend: *Backend,
    id_val: std.json.Value,
    extension_id: []const u8,
    verb: []const u8,
    params: std.json.Value,
) !bool {
    const reg = backend.verb_registry orelse return false;

    if (params != .object) {
        try reactorWriteError(write_buf, allocator, id_val, -32602, "params must be an object");
        return true;
    }

    const params_json = std.json.Stringify.valueAlloc(allocator, params, .{}) catch {
        try reactorWriteError(write_buf, allocator, id_val, -32603, "params serialise failed");
        return true;
    };
    defer allocator.free(params_json);

    const result = reg.dispatch(allocator, extension_id, verb, params_json) catch |err| {
        switch (err) {
            verb_dispatcher.DispatchError.walker_not_found => return false,
            verb_dispatcher.DispatchError.invalid_params => {
                try reactorWriteError(write_buf, allocator, id_val, -32602, "cartridge dispatch: invalid params");
                return true;
            },
            verb_dispatcher.DispatchError.walker_failed => {
                try reactorWriteError(write_buf, allocator, id_val, -32603, "cartridge dispatch: walker failed");
                return true;
            },
            verb_dispatcher.DispatchError.out_of_memory => {
                try reactorWriteError(write_buf, allocator, id_val, -32603, "cartridge dispatch: out of memory");
                return true;
            },
        }
    };
    defer allocator.free(result);
    try reactorWriteResult(write_buf, allocator, id_val, result);
    return true;
}

/// Write a raw HTTP error response (for rejected WS upgrades).
fn rawErrorResponse(
    write_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    status: u16,
    body: []const u8,
) void {
    const status_text = switch (status) {
        400 => "Bad Request",
        401 => "Unauthorized",
        405 => "Method Not Allowed",
        500 => "Internal Server Error",
        else => "Error",
    };
    var hdr_buf: [256]u8 = undefined;
    const hdr = std.fmt.bufPrint(
        &hdr_buf,
        "HTTP/1.1 {d} {s}\r\n" ++
            "Content-Type: application/json\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n\r\n",
        .{ status, status_text, body.len },
    ) catch return;
    write_buf.appendSlice(allocator, hdr) catch return;
    write_buf.appendSlice(allocator, body) catch return;
}

/// Extract bearer token from a parsed HttpRequest.
/// Checks Authorization header first, then ?bearer= query param.
fn extractBearerFromParsed(req: *const http_parser_mod.HttpRequest) ?[]const u8 {
    if (req.header("authorization")) |v| {
        if (parseBearerHeader(v)) |hex| return hex;
    }
    // Check query string for bearer=<hex64> (browser fallback).
    if (req.query.len > 0) {
        return parseBearerQueryString(req.query);
    }
    return null;
}

/// Parse `bearer=<hex64>` from a bare query string (no leading `?`).
/// Distinct from parseBearerQuery() which expects a full URL with `?`.
fn parseBearerQueryString(qs: []const u8) ?[]const u8 {
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

// ─── Tests ───────────────────────────────────────────────────────────

test "parseBearerHeader extracts 64-hex token" {
    const hex = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const v = std.fmt.comptimePrint("Bearer {s}", .{hex});
    const got = parseBearerHeader(v).?;
    try std.testing.expectEqualSlices(u8, hex, got);
}

test "parseBearerHeader rejects malformed" {
    try std.testing.expect(parseBearerHeader("Token abc") == null);
    try std.testing.expect(parseBearerHeader("Bearer xyz") == null);
    try std.testing.expect(parseBearerHeader("Bearer ") == null);
    try std.testing.expect(parseBearerHeader("Bearer abcdef") == null); // too short
}

test "parseBearerQuery extracts ?bearer=" {
    const hex = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef";
    const target = "/api/v1/wallet?bearer=" ++ hex;
    const got = parseBearerQuery(target).?;
    try std.testing.expectEqualSlices(u8, hex, got);
}

test "parseBearerQuery returns null without bearer param" {
    try std.testing.expect(parseBearerQuery("/api/v1/wallet") == null);
    try std.testing.expect(parseBearerQuery("/api/v1/wallet?other=foo") == null);
}

```
