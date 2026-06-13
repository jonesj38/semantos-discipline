---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/site_server/reactor.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.289110+00:00
---

# runtime/semantos-brain/src/site_server/reactor.zig

```zig
// B-pragmatic reactor helpers — extracted from src/site_server.zig.
// Pure code motion: no behaviour change.
//
// These module-level functions are the glue between the EventLoop reactor
// (event_loop.zig / connection_state.zig) and the existing SiteServer
// routing / wss_wallet logic.  All take `*SiteServer` (or `*ReactorCtx`
// which carries a `*SiteServer` field) and dispatch into the same code
// paths the std.http.Server handler hits — just with the reactor's
// pre-parsed HttpRequest + write_buf protocol instead of std.http.

const std = @import("std");
// Circular file import — Zig 0.15 handles mutual file imports as long
// as there's no comptime dependency cycle.  We only reference the
// SiteServer *struct type* here (passed as `*SiteServer`), so the
// import resolves cleanly.
const server_mod = @import("../site_server.zig");
const SiteServer = server_mod.SiteServer;

const util = @import("util.zig");
const setSocketTimeouts = util.setSocketTimeouts;
const headerValue = util.headerValue;
const clientAcceptsGzip = util.clientAcceptsGzip;
const isSafeRelativeUrlPath = util.isSafeRelativeUrlPath;
const guessContentType = util.guessContentType;
const readBody = util.readBody;
const readDynamicBody = util.readDynamicBody;
const DynamicBody = util.DynamicBody;
const ReadBodyError = util.ReadBodyError;

const connection_state_mod = @import("connection_state");
const cors_mod = @import("cors");
const http_parser_mod = @import("http_parser");
const wss_wallet = @import("wss_wallet");
const repl = @import("repl");
const repl_http = @import("repl_http");
const intake_http = @import("intake_http");
const auth_handler = @import("auth_handler");
const site_config = @import("site_config");
const dispatcher_mod = @import("dispatcher");
// Tracker T7 — BRC-52 cert + capability request auth.
const cert_request_auth = @import("cert_request_auth");
const runner_mod = @import("runner");
const event_loop_mod = @import("event_loop");
const bearer_tokens = @import("bearer_tokens");
const wallet_op_http = @import("wallet_op_http");
const device_pair_http = @import("device_pair_http");
const attachments_upload_http = @import("attachments_upload_http");
// C4 PR-H6 — attachments_blob_http import removed (blob GET moved to the cartridge).
const cell_raw_http = @import("cell_raw_http");
const cells_mint_http = @import("cells_mint_http");
const bundle_sign_http = @import("bundle_sign_http");
/// PR-anchor-on-mint — reactor calls AnchorEmitter when
/// `acceptor.auto_anchor_on_mint` is true. Same pattern cell_handler.zig
/// already uses post-persist; this wires the generic
/// `POST /api/v1/cells` path into the same auto-anchor pipeline so NP OS
/// substrate cells get a PushDrop anchor on creation just like the
/// typed-object cells do via the legacy cell_handler.zig path.
const anchor_emitter_mod = @import("anchor_emitter");
const betterment_sweep_http = @import("betterment_sweep_http");
const cells_mint_validator = @import("cells_mint_validator");
const substrate_entity = @import("substrate_entity");
// M1.7 — transport-agnostic mint body. Both this HTTP handler and the
// `cells.mint` WSS RPC method call mintCellCore so their behaviour can't drift.
const cells_mint_core = @import("cells_mint_core");
const bkds = @import("bkds");
const info_http = @import("info_http");
const voice_extract_http = @import("voice_extract_http");
const image_extract_http = @import("image_extract_http");
const audio_extract_http = @import("audio_extract_http");
const push_register_http = @import("push_register_http");
// C4 PR-I1 — conversation_send_http import removed (route moved to the cartridge).
// C4 PR-I2 — twilio_inbound_http import removed (webhook moved to the cartridge).
const identity_merge_http = @import("identity_merge_http");
// C4 PR-H3 — search_contacts_http import removed (route moved to the cartridge).
const contacts_http = @import("contacts_http");
const messagebox_http = @import("messagebox_http");
const intent_http = @import("intent_http");
const identity_http = @import("identity_http");
const loom_store_http = @import("loom_store_http");
const flow_http = @import("flow_http");
const events_stream_handler = @import("events_stream_handler");
const oddjobz_event_bus_mod = @import("oddjobz_event_bus");
const wss_codec = @import("wss_codec");
const wss_rpc = @import("wss_rpc_registry");
const intent_action_router_mod = @import("intent_action_router");
const payment_ledger = @import("payment_ledger");
const payment_verifier = @import("payment_verifier");

const AuthError = auth_handler.AuthError;

/// Which WSS session kind is active on a connection after upgrade.
/// .none on plain HTTP connections; set by the upgrade handler that
/// claims the connection.
pub const SessionKind = enum { none, wallet, events, rpc };

pub const ReactorCtx = struct {
    server: *SiteServer,
    session: *wss_wallet.ReactorSession,
    /// T3 — populated when the connection upgrades to /api/v1/events.
    /// Lives in the ReactorCtx (same lifetime as the session) so the
    /// bus callback's state pointer survives between subscribe and
    /// teardown.
    events_session: ?*EventsReactorSession = null,
    /// Unified WSS RPC channel — populated when the connection upgrades to
    /// /api/v1/rpc. Same lifetime as the ctx so a subscription's push queue
    /// survives between subscribe and teardown.
    rpc_session: ?*RpcReactorSession = null,
    kind: SessionKind = .none,
};

/// Per-connection state for a `/api/v1/rpc` WSS session (the unified RPC
/// channel). Auth is bound ONCE at the upgrade: `is_admin` records whether the
/// upgrade credential was an operator/admin (today: any valid bearer, matching
/// the brain's bearer-implies-everything posture; cert cap sets land additively
/// in `caps`). Per-method gating reads these against `RpcMethod.required_cap`.
///
/// Threading mirrors EventsReactorSession: `push_queue` + `push_mu` form a
/// cross-thread queue between a bus publisher (for `subscribe` channels, M2+)
/// and the reactor thread, flushed by `reactorTickDrain` + the frame handler.
pub const RpcReactorSession = struct {
    allocator: std.mem.Allocator,
    is_admin: bool = false,
    /// Capability strings granted at upgrade (owned copies). Empty today;
    /// populated when cert→cap-set derivation lands. Checked via
    /// dispatcher.CapabilitySet semantics in reactorRpcCapOk.
    caps: dispatcher_mod.CapabilitySet = dispatcher_mod.CapabilitySet.empty(),
    /// Serialized WSS text frames awaiting flush (subscription pushes).
    push_queue: std.ArrayList(u8) = .{},
    push_mu: std.Thread.Mutex = .{},

    pub fn drainInto(self: *RpcReactorSession, write_buf: *std.ArrayList(u8), allocator: std.mem.Allocator) void {
        self.push_mu.lock();
        defer self.push_mu.unlock();
        if (self.push_queue.items.len == 0) return;
        write_buf.appendSlice(allocator, self.push_queue.items) catch return;
        self.push_queue.clearRetainingCapacity();
    }

    pub fn teardown(self: *RpcReactorSession) void {
        self.push_mu.lock();
        self.push_queue.deinit(self.allocator);
        self.push_mu.unlock();
    }
};

/// T3 — per-connection state for a `/api/v1/events` WSS session.
///
/// Threading: `event_queue` + `event_mu` form a cross-thread queue
/// between the bus publisher thread (calls `eventsBusCallback`) and
/// the reactor thread (calls `drainInto`).  The reactor's pre-tick
/// drain runs `drainInto` every poll cycle; the events frame handler
/// also runs it on each inbound frame for lower latency.
///
/// Hat filter: events whose `hat_id` doesn't match `hat()` are dropped
/// in the callback before they hit the queue (saves serialisation cost).
pub const EventsReactorSession = struct {
    allocator: std.mem.Allocator,
    hat_buf: [128]u8 = undefined,
    hat_len: usize = 0,
    bus: ?*oddjobz_event_bus_mod.OddjobzEventBus = null,
    sub_id: ?oddjobz_event_bus_mod.SubscriberId = null,
    /// Serialized WSS text frames awaiting flush.  Filled by the bus
    /// callback (publisher thread); drained by the reactor thread.
    event_queue: std.ArrayList(u8) = .{},
    event_mu: std.Thread.Mutex = .{},

    pub fn hat(self: *const EventsReactorSession) []const u8 {
        return self.hat_buf[0..self.hat_len];
    }

    pub fn drainInto(self: *EventsReactorSession, write_buf: *std.ArrayList(u8), allocator: std.mem.Allocator) void {
        self.event_mu.lock();
        defer self.event_mu.unlock();
        if (self.event_queue.items.len == 0) return;
        write_buf.appendSlice(allocator, self.event_queue.items) catch return;
        self.event_queue.clearRetainingCapacity();
    }

    pub fn teardown(self: *EventsReactorSession) void {
        if (self.bus) |bus| {
            if (self.sub_id) |sid| {
                bus.unsubscribe(sid);
                self.sub_id = null;
            }
        }
        self.event_mu.lock();
        self.event_queue.deinit(self.allocator);
        self.event_mu.unlock();
    }
};

/// T3 — pre-tick drain hook installed via ConnectionContext.pre_tick_drain.
/// Called by the EventLoop once per poll cycle BEFORE poll() blocks.
/// Walks the ReactorCtx's events_session (if any) and appends its queued
/// frame bytes to write_buf.
fn reactorTickDrain(
    ctx_ptr: *anyopaque,
    write_buf: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
) void {
    const ctx: *ReactorCtx = @ptrCast(@alignCast(ctx_ptr));
    if (ctx.events_session) |es| es.drainInto(write_buf, allocator);
    if (ctx.rpc_session) |rs| rs.drainInto(write_buf, allocator);
}

/// T3 — bus callback registered with `OddjobzEventBus.subscribe`.
/// Runs on the publisher's thread (whoever calls `bus.publish`).
/// Serialises the event to a WSS text frame and appends to the
/// per-session queue under the queue mutex.
///
/// Hat filter: events whose hat_id doesn't match the session's hat
/// are dropped before the queue, saving the serialisation cost.
fn eventsBusCallback(state: ?*anyopaque, event: oddjobz_event_bus_mod.JobEvent) void {
    const sess: *EventsReactorSession = @ptrCast(@alignCast(state.?));
    if (!std.mem.eql(u8, event.hat_id, sess.hat())) return;

    // Build the JSON payload.
    var json_buf: std.ArrayList(u8) = .{};
    defer json_buf.deinit(sess.allocator);
    events_stream_handler.serializeEvent(sess.allocator, &json_buf, event) catch return;

    // Encode as a WSS text frame and append to the cross-thread queue.
    sess.event_mu.lock();
    defer sess.event_mu.unlock();
    reactorWriteFrameInto(&sess.event_queue, sess.allocator, .text, json_buf.items) catch return;
}

/// Helper mirroring wss_wallet/reactor.zig's reactorWriteFrame: encode
/// a WSS frame (server→client, unmasked per RFC 6455 §5.1) into the
/// given ArrayList.  Extracted as a local helper so eventsBusCallback
/// doesn't reach into the wss_wallet module.
fn reactorWriteFrameInto(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    opcode: wss_codec.Opcode,
    payload: []const u8,
) !void {
    var hdr_buf: [10]u8 = undefined;
    var hdr_len: usize = 2;
    hdr_buf[0] = 0x80 | @as(u8, @intFromEnum(opcode)); // FIN | opcode
    if (payload.len < 126) {
        hdr_buf[1] = @intCast(payload.len);
    } else if (payload.len <= 0xffff) {
        hdr_buf[1] = 126;
        std.mem.writeInt(u16, hdr_buf[2..4], @intCast(payload.len), .big);
        hdr_len = 4;
    } else {
        hdr_buf[1] = 127;
        std.mem.writeInt(u64, hdr_buf[2..10], payload.len, .big);
        hdr_len = 10;
    }
    try out.appendSlice(allocator, hdr_buf[0..hdr_len]);
    try out.appendSlice(allocator, payload);
}

/// T0 — per-route body-handling policy table.
///
/// Routes that need bodies larger than `http_parser.DEFAULT_BODY_CAP`
/// (256 KiB) declare their cap here.  The parser invokes `reactorBodyPolicy`
/// after headers parse, gets the cap, and allocates a heap body buffer
/// up to that size.  Reject (413/BodyTooLarge) if Content-Length exceeds.
///
/// Adding a new route with a large body:
///   1. Add an entry below with the route path + cap in bytes.
///   2. Add the dispatch branch in `reactorDispatchHttp`.
///   3. Update the V1 port tracker (`docs/REACTOR-PORT-TRACKER.md`).
///
/// Caps deliberately leave headroom over the acceptor's own enforcement
/// (e.g. attachments_upload.DEFAULT_MAX_BLOB_BYTES = 10 MiB → 12 MiB
/// cap here so the multipart envelope + signed Transcript metadata fit).
///
/// The total list is data, not logic — the lookup is linear because
/// the list is short.  If it grows past ~16 entries, switch to a
/// std.StaticStringMap.
const RouteBodyCap = struct {
    path: []const u8,
    cap_bytes: usize,
};

const ROUTE_BODY_CAPS = [_]RouteBodyCap{
    // T1 — attachment uploads.  Cap = DEFAULT_MAX_BLOB_BYTES (10 MiB)
    // + headroom for the multipart envelope + signed Transcript metadata.
    .{ .path = "/api/v1/attachments/upload", .cap_bytes = 12 * 1024 * 1024 },
    // T4 — voice notes.  Cap = DEFAULT_MAX_AUDIO_BYTES (5 MiB) + signed
    // Transcript JSON + metadata + optional sir_candidate JSON + multipart
    // envelope.  6 MiB gives ~1 MiB headroom over the audio cap.
    .{ .path = "/api/v1/voice-extract", .cap_bytes = 6 * 1024 * 1024 },
    // Betterment OCR — image-extract.  Cap = DEFAULT_MAX_IMAGE_BYTES (4 MiB)
    // × MAX_PAGES (4) + multipart envelope + metadata headroom.
    .{ .path = "/api/v1/image-extract", .cap_bytes = 4 * 4 * 1024 * 1024 + 256 * 1024 },
    // Betterment voice — audio-extract. Cap = DEFAULT_MAX_AUDIO_BYTES (16 MiB)
    // + multipart envelope + metadata headroom.
    .{ .path = "/api/v1/audio-extract", .cap_bytes = 16 * 1024 * 1024 + 256 * 1024 },
};

/// T0 — body policy callback wired into the ConnectionContext.
/// Called by http_parser.Parser once headers are parsed, before any
/// body bytes are buffered.  Looks up the per-route cap; falls back
/// to DEFAULT_BODY_CAP (256 KiB).
pub fn reactorBodyPolicy(
    req: *const http_parser_mod.HttpRequest,
    _: *anyopaque,
) http_parser_mod.BodyPolicy {
    for (ROUTE_BODY_CAPS) |entry| {
        if (std.mem.eql(u8, req.path, entry.path)) {
            return .{ .buffer = entry.cap_bytes };
        }
    }
    return .{ .buffer = http_parser_mod.DEFAULT_BODY_CAP };
}

/// Factory called by EventLoop.acceptNewConnection for each new fd.
/// `ud` is *SiteServer cast from the opaque pointer.
///
/// Allocates a ReactorCtx (which contains a ReactorSession) per connection.
/// Both are freed by freeReactorCtx when the connection closes.
pub fn reactorMakeCtx(
    fd: std.posix.fd_t,
    ud: *anyopaque,
) anyerror!connection_state_mod.ConnectionContext {
    _ = fd;
    const server: *SiteServer = @ptrCast(@alignCast(ud));
    const alloc = server.allocator;

    const session = try alloc.create(wss_wallet.ReactorSession);
    errdefer alloc.destroy(session);
    session.* = .{ .allocator = alloc };

    // T3 — pre-allocate the events session struct.  Most connections
    // never upgrade to /api/v1/events so this is wasted (~few hundred
    // bytes) on the common path; the alternative is a lazy-alloc
    // dance during the upgrade that complicates the lifecycle.
    // Stays inert (sub_id null, hat_len 0) until reactorEventsUpgrade
    // populates it.
    const events_session = try alloc.create(EventsReactorSession);
    errdefer alloc.destroy(events_session);
    events_session.* = .{ .allocator = alloc };

    // Pre-allocate the RPC session struct (same rationale as events_session:
    // most connections never upgrade to /api/v1/rpc, but lazy-alloc during the
    // upgrade complicates the lifecycle). Stays inert until reactorRpcUpgrade
    // populates it.
    const rpc_session = try alloc.create(RpcReactorSession);
    errdefer alloc.destroy(rpc_session);
    rpc_session.* = .{ .allocator = alloc };

    const ctx = try alloc.create(ReactorCtx);
    errdefer alloc.destroy(ctx);
    ctx.* = .{
        .server = server,
        .session = session,
        .events_session = events_session,
        .rpc_session = rpc_session,
        .kind = .none,
    };

    return .{
        .dispatch_http = &reactorDispatchHttp,
        .dispatch_wss = &reactorDispatchWss,
        .body_policy_fn = &reactorBodyPolicy,
        .body_policy_ctx = @ptrCast(ctx),  // not currently inspected, but reserved
        .http_ctx = @ptrCast(ctx),  // *ReactorCtx — carries server + session
        .wss_ctx = @ptrCast(ctx),   // *ReactorCtx — same pointer so free_wss_ctx sees full ctx
        .free_wss_ctx = &freeReactorCtx,
        // T3 — pre-poll drain so cross-thread bus-callback queues
        // flush into write_buf before each poll cycle.
        .pre_tick_drain = &reactorTickDrain,
        .tick_drain_ctx = @ptrCast(ctx),
    };
}

/// Free the ReactorCtx and its embedded ReactorSession.
/// Called by ConnectionState.deinit() when the connection closes.
///
/// REACTOR-DISPATCH (brain-wedge B-pragmatic Commit 6, 2026-05-07):
///   Now calls helmTeardown (instead of just freeTopics) so that helm
///   subscriptions are unregistered from the broker on connection close.
///   Without this, the broker would keep calling the dead session's
///   reactorHelmEventCallback after the connection was gone.
pub fn freeReactorCtx(ptr: *anyopaque, _: std.mem.Allocator) void {
    const ctx: *ReactorCtx = @ptrCast(@alignCast(ptr));
    const alloc = ctx.server.allocator;
    // Unsubscribe from the broker and free all helm state.
    // If the session has no helm subscription, helmTeardown is a no-op
    // (it checks helm_sub_id for null before calling broker.unsubscribe).
    if (ctx.session.backend) |backend| {
        if (backend.helm_broker) |broker| {
            ctx.session.helmTeardown(broker);
        } else {
            ctx.session.freeTopics();
        }
    } else {
        ctx.session.freeTopics();
    }
    // T3 — tear down the events session.  teardown() is null-safe
    // for the bus subscription (only unsubscribes when sub_id was
    // populated by the events upgrade handler).
    if (ctx.events_session) |es| {
        es.teardown();
        alloc.destroy(es);
    }
    // Tear down the RPC session (frees the push queue; null-safe — only
    // populated after a /api/v1/rpc upgrade).
    if (ctx.rpc_session) |rs| {
        rs.teardown();
        alloc.destroy(rs);
    }
    alloc.destroy(ctx.session);
    alloc.destroy(ctx);
}

/// HTTP dispatch callback for the reactor.
/// Called by ConnectionState.feedHttpBytes() on each complete HTTP request.
/// Appends a raw HTTP/1.1 response to write_buf; returns the desired
/// connection outcome.
///
/// Routing priority matches handleRequest():
///   1. OPTIONS preflight            → 204 No Content
///   2. /api/v1/wallet WSS upgrade   → 101 Switching Protocols
///   3. /api/v1/repl                 → REPL handler (stub → 503 in reactor)
///   4. All other paths              → static file / directory / 404
///
/// Complex routes (auth callback, device-pair, chat, payment, bundle mesh,
/// block-headers proxy) fall back to a 501 Not Implemented response with a
/// comment pointing the operator at the TODO-REACTOR-COMPLETE marker.
/// These will be wired in a follow-up commit once the reactor path is
/// verified end-to-end for the WSS fix.
pub fn reactorDispatchHttp(
    args: connection_state_mod.HttpDispatchArgs,
) connection_state_mod.HttpDispatchResult {
    const ctx: *ReactorCtx = @ptrCast(@alignCast(args.http_ctx));
    const server = ctx.server;
    const session = ctx.session;
    const req = args.request;
    const write_buf = args.write_buf;
    const alloc = args.allocator;

    const method = req.method;
    const path = req.path;

    // ── CORS computation (mirrors the blocking handleRequest path) ──────
    // Compute once at request entry so all response branches get CORS
    // headers.  Buffers live in this stack frame for the request lifetime.
    var cors_bufs: cors_mod.Cors.Buffers = .{};
    const cors = cors_mod.Cors.prepareFromOrigin(
        req.header("origin"),
        server.config, // *const SiteConfig — no & needed (config is already a pointer)
        &cors_bufs,
    );

    // ── 1. OPTIONS preflight ────────────────────────────────────────────
    if (std.mem.eql(u8, method, "OPTIONS")) {
        // Full preflight headers (ACAO + ACAM + ACAH + ACMA + Vary).
        var opts_hdr_slots: [8]std.http.Header = undefined;
        const opts_hdrs = cors.optionsHeaders(&opts_hdr_slots);
        reactorWriteWithCors(write_buf, alloc, 204, "No Content", "text/plain", "", opts_hdrs);
        return .close_after_drain;
    }

    // ── 2. /api/v1/wallet — WSS upgrade ────────────────────────────────
    // This is THE fix: when a GET upgrade arrives, we write the 101 and
    // signal the state machine to switch to WSS phase.  Subsequent frames
    // on this fd go to reactorDispatchWss — no blocking read loop.
    if (std.mem.eql(u8, path, "/api/v1/wallet")) {
        if (server.wss_backend) |wb| {
            const result = wss_wallet.tryUpgradeFromParsed(req, wb, session, write_buf, alloc);
            switch (result) {
                .upgraded => {
                    // T3 — record which session kind owns the connection
                    // so reactorDispatchWss routes frames correctly.
                    ctx.kind = .wallet;
                    server.logRequest(.GET, "/api/v1/wallet [101]", 101) catch {};
                    return .upgraded_to_wss;
                },
                .rejected => {
                    server.logRequest(.GET, "/api/v1/wallet", 401) catch {};
                    return .close_after_drain;
                },
                .not_a_wallet_upgrade => {
                    // Not a WS upgrade (missing headers) — fall through to 503.
                },
            }
        }
        // Wallet backend not attached, or not a valid WS upgrade.
        const body = if (server.wss_backend == null)
            "{\"error\":\"wallet WSS backend not enabled\"}"
        else
            "{\"error\":\"GET /api/v1/wallet requires WebSocket Upgrade headers\"}";
        var rsp_slots: [8]std.http.Header = undefined;
        reactorWriteWithCors(write_buf, alloc, 503, "Service Unavailable", "application/json", body,
            cors.responseHeaders(&rsp_slots));
        server.logRequest(.GET, "/api/v1/wallet", 503) catch {};
        return .close_after_drain;
    }

    // ── 3. /api/v1/repl ────────────────────────────────────────────────
    // RIP-OUT-MARKER (brain-wedge B-pragmatic Commit 7, 2026-05-07):
    //   This branch dispatches POST /api/v1/repl through the reactor.
    //   The bearer-auth + JSON-body + repl.handleLine logic mirrors the
    //   old serveSession path in repl_http.zig::maybeHandle (preserved
    //   in case we want to compare or revert).  To revert: replace this
    //   branch with the 503 TODO-REACTOR-COMPLETE stub from Commit 5.
    if (std.mem.eql(u8, path, "/api/v1/repl")) {
        var repl_cors_slots: [8]std.http.Header = undefined;
        const repl_cors_hdrs = cors.responseHeaders(&repl_cors_slots);
        const repl_status = reactorHandleRepl(server, req, write_buf, alloc, repl_cors_hdrs);
        server.logRequest(methodToEnum(method), path, repl_status) catch {};
        return .close_after_drain;
    }

    // ── 4. /api/v1/device-pair ─────────────────────────────────────────
    // RIP-OUT-MARKER (brain-wedge Commit 8a, 2026-05-06):
    //   This branch dispatches POST /api/v1/device-pair through the reactor.
    //   The JSON-body parse + acceptor dispatch mirrors the old blocking path
    //   in device_pair_http.zig::maybeHandle (preserved as reference + revert
    //   path).  Device-pair is intentionally unauthenticated — it is HOW a
    //   new device gets its bearer token.  To revert: replace this branch with
    //   a 503 TODO-REACTOR-COMPLETE stub.
    if (std.mem.eql(u8, path, "/api/v1/device-pair")) {
        var dp_cors_slots: [8]std.http.Header = undefined;
        const dp_cors_hdrs = cors.responseHeaders(&dp_cors_slots);
        const dp_status = reactorHandleDevicePair(server, req, write_buf, alloc, dp_cors_hdrs);
        server.logRequest(methodToEnum(method), path, dp_status) catch {};
        return .close_after_drain;
    }

    // C4 PR-H7b — POST /api/v1/attachments/upload moved to the oddjobz cartridge
    // over the route registry (consulted below). The hardcoded branch +
    // reactorHandleAttachmentsUpload are gone. NOTE: the 12 MiB ROUTE_BODY_CAPS
    // entry for this path STAYS — the route-registry handler still reads the
    // multipart body from the (pre-buffered) req.body.

    // C4 PR-H6 — GET /api/v1/attachments/{id}/blob moved to the oddjobz cartridge
    // over the route registry (consulted below). The hardcoded branch +
    // reactorHandleAttachmentsBlob are gone; the cartridge handler returns the
    // blob with its mime content-type + cache-control via RouteResponse.

    // ── 6a. /api/v1/cells — BRAIN-GENERIC-MINT-VERB M1 (2026-05-26) ────
    //   POST generic cell mint. Matched BEFORE /api/v1/cell/ so the
    //   plural path doesn't fall through into reactorHandleCellRaw
    //   (which would 400 on the non-hex tail). Bearer-gated. Body is
    //   JSON {typeHashHex, payload, capabilityProof?}; resolved via the
    //   cartridge cellType registry, encoded via substrate_entity.
    //   encodeFromTypeHash, persisted via cell_store, published via
    //   the helm event broker as cells.<cartridge-id>.minted.
    {
        const path_only = if (std.mem.indexOfScalar(u8, path, '?')) |q| path[0..q] else path;
        if (std.mem.eql(u8, path_only, cells_mint_http.ROUTE)) {
            var cm_cors_slots: [8]std.http.Header = undefined;
            const cm_cors_hdrs = cors.responseHeaders(&cm_cors_slots);
            const cm_status = reactorHandleCellsMint(server, req, write_buf, alloc, cm_cors_hdrs);
            server.logRequest(methodToEnum(method), path, cm_status) catch {};
            return .close_after_drain;
        }
    }

    // ── 6b. /api/v1/bundle/sign — D-helm-rtc-operator-sign ─────────────
    //   POST: sign a helm-supplied unsigned SignedBundle AS the operator
    //   (rtc.jingle signalling, etc.) using the operator pin private key.
    //   Admin route. Matched before /api/v1/bundle (receive seam).
    {
        const path_only = if (std.mem.indexOfScalar(u8, path, '?')) |q| path[0..q] else path;
        if (std.mem.eql(u8, path_only, bundle_sign_http.ROUTE)) {
            var bs_cors_slots: [8]std.http.Header = undefined;
            const bs_cors_hdrs = cors.responseHeaders(&bs_cors_slots);
            const bs_status = reactorHandleBundleSign(server, req, write_buf, alloc, bs_cors_hdrs);
            server.logRequest(methodToEnum(method), path, bs_status) catch {};
            return .close_after_drain;
        }
    }

    // ── 6c. /api/v1/cell/since/<prev_hash_hex> — D-LC4 (2026-05-20) ─────
    //   GET forward state-DAG children. Matched BEFORE the general /cell/
    //   prefix so /since/ doesn't fall through into reactorHandleCellRaw
    //   (which would 400 on the non-hex tail). Bearer-gated.
    if (std.mem.startsWith(u8, path, "/api/v1/cell/since/")) {
        var cs_cors_slots: [8]std.http.Header = undefined;
        const cs_cors_hdrs = cors.responseHeaders(&cs_cors_slots);
        const cs_status = reactorHandleCellSince(server, req, write_buf, alloc, cs_cors_hdrs);
        server.logRequest(methodToEnum(method), path, cs_status) catch {};
        return .close_after_drain;
    }

    // ── 6b. /api/v1/cell/<sha256hex> — D-LC1 (2026-05-20) ───────────────
    //   GET raw 1024-byte cell from LmdbCellStore. Bearer-gated. Matched
    //   by prefix; the handler validates the hex tail and returns 400 on
    //   malformed paths so this branch is safe to take eagerly.
    if (std.mem.startsWith(u8, path, "/api/v1/cell/")) {
        var cr_cors_slots: [8]std.http.Header = undefined;
        const cr_cors_hdrs = cors.responseHeaders(&cr_cors_slots);
        const cr_status = reactorHandleCellRaw(server, req, write_buf, alloc, cr_cors_hdrs);
        server.logRequest(methodToEnum(method), path, cr_status) catch {};
        return .close_after_drain;
    }

    // ── 6d. /api/v1/betterment/sweep — pask-informed SCAN primer ─────────────
    //   GET betterment.practice.* cells → Bun sweep_runner.ts → primed themes.
    //   Bearer-gated. Falls through to 503 when acceptor isn't attached.
    if (std.mem.eql(u8, path, betterment_sweep_http.ROUTE)) {
        var ss_cors_slots: [8]std.http.Header = undefined;
        const ss_cors_hdrs = cors.responseHeaders(&ss_cors_slots);
        const ss_status = reactorHandleBettermentSweep(server, req, write_buf, alloc, ss_cors_hdrs);
        server.logRequest(methodToEnum(method), path, ss_status) catch {};
        return .close_after_drain;
    }

    // ── 7. /api/v1/info — T2 port (2026-05-12) ─────────────────────────
    //   GET brain pin + shard-proxy + theme + hat info.  Bearer-gated.
    //   Falls through to 404 when info_acceptor isn't attached (matches
    //   the dead request.zig wire shape — info is opt-in per deployment).
    if (std.mem.eql(u8, path, "/api/v1/info")) {
        var info_cors_slots: [8]std.http.Header = undefined;
        const info_cors_hdrs = cors.responseHeaders(&info_cors_slots);
        const info_status = reactorHandleInfo(server, req, write_buf, alloc, info_cors_hdrs);
        server.logRequest(methodToEnum(method), path, info_status) catch {};
        return .close_after_drain;
    }

    // ── 8b. /api/v1/events — T3 port (2026-05-13) ──────────────────────
    //   WSS upgrade: bearer not required at the upgrade layer (the bus
    //   subscription itself is hat-filtered).  Subscribes the
    //   connection's EventsReactorSession to the OddjobzEventBus; the
    //   bus callback queues frames, the pre-tick drain flushes them
    //   to write_buf.  Falls through to 503 when no bus is attached.
    //   Strip any trailing query string before matching.
    {
        const path_only = if (std.mem.indexOfScalar(u8, path, '?')) |q| path[0..q] else path;
        if (std.mem.eql(u8, path_only, "/api/v1/events")) {
            var ev_cors_slots: [8]std.http.Header = undefined;
            const ev_cors_hdrs = cors.responseHeaders(&ev_cors_slots);
            return reactorEventsUpgrade(server, ctx, req, write_buf, alloc, ev_cors_hdrs);
        }
        // Unified WSS RPC channel. Authenticated ONCE at the upgrade
        // (cert/bearer); subsequent frames carry many logical methods routed
        // through the RpcRegistry. Falls through to 503 when no registry is
        // attached, 401 on a failed upgrade auth.
        if (std.mem.eql(u8, path_only, "/api/v1/rpc")) {
            var rpc_cors_slots: [8]std.http.Header = undefined;
            const rpc_cors_hdrs = cors.responseHeaders(&rpc_cors_slots);
            return reactorRpcUpgrade(server, ctx, req, write_buf, alloc, rpc_cors_hdrs);
        }
    }

    // ── 8. /api/v1/voice-extract — T4 port (2026-05-12) ────────────────
    //   Multipart POST: audio blob + signed Transcript + metadata
    //   (+ optional Phase 2 sir_candidate).  Bearer-gated; verifies the
    //   Transcript signature so the dictation provably came from a device
    //   cert authorized to mutate the bound scope.  Shells out to bun for
    //   the intent pipeline.  Body cap 6 MiB declared in ROUTE_BODY_CAPS.
    //   Falls through to 404 when voice_extract_acceptor isn't attached.
    if (std.mem.eql(u8, path, "/api/v1/voice-extract")) {
        var ve_cors_slots: [8]std.http.Header = undefined;
        const ve_cors_hdrs = cors.responseHeaders(&ve_cors_slots);
        const ve_status = reactorHandleVoiceExtract(server, req, write_buf, alloc, ve_cors_hdrs);
        server.logRequest(methodToEnum(method), path, ve_status) catch {};
        return .close_after_drain;
    }

    // ── 8b. /api/v1/image-extract — betterment OCR (Claude vision) ─────
    //   Multipart POST: 1..MAX_PAGES `image` parts + optional metadata.
    //   Bearer-gated (no cert-signature, unlike voice).  Shells out to bun
    //   (image-extract.ts → Claude vision) which returns ReleaseTurns JSON.
    //   Body cap declared in ROUTE_BODY_CAPS.  404 when acceptor unattached.
    if (std.mem.eql(u8, path, "/api/v1/image-extract")) {
        var ie_cors_slots: [8]std.http.Header = undefined;
        const ie_cors_hdrs = cors.responseHeaders(&ie_cors_slots);
        const ie_status = reactorHandleImageExtract(server, req, write_buf, alloc, ie_cors_hdrs);
        server.logRequest(methodToEnum(method), path, ie_status) catch {};
        return .close_after_drain;
    }

    // ── 8c. /api/v1/audio-extract — betterment voice (server-side whisper) ─
    //   Multipart POST: one `audio` part (16kHz mono WAV) + optional metadata.
    //   Bearer-gated. Shells to bun audio-extract.ts → whisper.cpp → ReleaseTurns.
    if (std.mem.eql(u8, path, "/api/v1/audio-extract")) {
        var ae_cors_slots: [8]std.http.Header = undefined;
        const ae_cors_hdrs = cors.responseHeaders(&ae_cors_slots);
        const ae_status = reactorHandleAudioExtract(server, req, write_buf, alloc, ae_cors_hdrs);
        server.logRequest(methodToEnum(method), path, ae_status) catch {};
        return .close_after_drain;
    }

    // ── 8c. /api/v1/push-register — T6 port (2026-05-13) ───────────────
    //   POST: device registers an APNs/FCM/UnifiedPush token onto its
    //   identity-cert record. DELETE: clears the registration.
    //   Bearer-gated; pure-logic via push_register_http.acceptPost /
    //   acceptDelete. Body bound ≤8 KiB inside the acceptor; the route
    //   inherits the DEFAULT_BODY_CAP (256 KiB) which is more than
    //   enough headroom. Falls through to 404 when
    //   push_register_acceptor isn't attached.
    if (std.mem.eql(u8, path, "/api/v1/push-register")) {
        var pr_cors_slots: [8]std.http.Header = undefined;
        const pr_cors_hdrs = cors.responseHeaders(&pr_cors_slots);
        const pr_status = reactorHandlePushRegister(server, req, write_buf, alloc, pr_cors_hdrs);
        server.logRequest(methodToEnum(method), path, pr_status) catch {};
        return .close_after_drain;
    }

    // C4 PR-I1 — POST /api/v1/conversation/:id/send moved to the oddjobz cartridge
    // over the route registry (consulted below). The hardcoded branch +
    // reactorHandleConversationSend are gone.

    // C4 PR-I2 — POST /api/v1/twilio/inbound moved to the oddjobz cartridge over
    // the route registry (consulted below). The hardcoded branch +
    // reactorHandleTwilioInbound are gone.

    // ── Phase 5 — /api/v1/voice-note — MIGRATED (C4 PR-G7): now served by the
    //   oddjobz cartridge via the route registry (consulted below). Removed:
    //   this branch + reactorHandleVoiceNote + SiteServer.voice_note_script.

    // ── 8i. /api/v1/conversation/turn/propose — MIGRATED (C4 PR-G4): now served
    //   by the oddjobz cartridge via the route registry (consulted below). The
    //   /approve + /re-anchor routes use endsWith, so /propose falls through to
    //   the registry cleanly. Removed: this branch + reactorHandleProposeTurn +
    //   SiteServer.propose_turn_script.

    // ── 8j. /api/v1/c/{token} — MIGRATED (C4 PR-G2): customer-link-resolve is
    //   now served by the oddjobz cartridge via the route registry (consulted
    //   below, before static/404). Removed with this branch: reactorHandleCustomer
    //   LinkResolve + SiteServer.customer_link_resolve_script + the operator flag.

    // ── 8f. /api/v1/conversation/turn/:id/approve — MIGRATED (C4 PR-G5): now
    //   served by the oddjobz cartridge via the route registry (prefix+suffix
    //   Route, consulted below). Removed: this branch + reactorHandleConversation
    //   Approve + SiteServer.conv_approve_script.

    // ── 8h. /api/v1/conversation/turn/:id/re-anchor — MIGRATED (C4 PR-G6): now
    //   served by the oddjobz cartridge via the route registry (prefix+suffix
    //   Route, consulted below). Removed: this branch + reactorHandleReAnchor +
    //   SiteServer.re_anchor_script.

    // ── 8g. /api/v1/identity/merge — D-OJ-conv-identity-merge-endpoint ──
    //   POST: operator merges two participant identities into one.
    //   Bearer-gated; dispatches to bun subprocess via
    //   identity_merge_http.callMergeScript. Falls through to 404
    //   when identity_merge_script isn't set.
    if (std.mem.eql(u8, path, "/api/v1/identity/merge")) {
        var im_cors_slots: [8]std.http.Header = undefined;
        const im_cors_hdrs = cors.responseHeaders(&im_cors_slots);
        const im_status = reactorHandleIdentityMerge(server, req, write_buf, alloc, im_cors_hdrs);
        server.logRequest(methodToEnum(method), path, im_status) catch {};
        return .close_after_drain;
    }

    // C4 PR-H3 — /api/v1/search/contacts moved to the oddjobz cartridge over the
    // route registry (consulted below, after the hardcoded routes). The hardcoded
    // branch + reactorHandleSearchContacts are gone.

    // ── 8e2. /api/v1/messages — D-network-messagebox-first-class ──────────
    //   POST /api/v1/messages/send   → store BRC-77/78 envelope for recipient
    //   GET  /api/v1/messages/list   → list pending envelopes for recipient
    //   POST /api/v1/messages/ack    → acknowledge + delete a message
    //   Falls through to 404 when messagebox_acceptor isn't attached.
    if (std.mem.startsWith(u8, path, "/api/v1/messages")) {
        const tail = path["/api/v1/messages".len..];
        if (tail.len == 0 or tail[0] == '/') {
            var mb_cors_slots: [8]std.http.Header = undefined;
            const mb_cors_hdrs = cors.responseHeaders(&mb_cors_slots);
            const mb_status = reactorHandleMessagebox(server, req, write_buf, alloc, mb_cors_hdrs);
            server.logRequest(methodToEnum(method), path, mb_status) catch {};
            return .close_after_drain;
        }
    }

    // ── 8f. /api/v1/contacts — D-brain-contacts-api (2026-05-24) ───────
    //   GET  /api/v1/contacts        → list all contacts (bearer-gated)
    //   POST /api/v1/contacts        → add contact
    //   GET  /api/v1/contacts/{id}   → get one contact
    //   POST /api/v1/contacts/{id}/edges   → create edge
    //   DELETE /api/v1/contacts/{id}/edges/{eid} → revoke edge
    //   Falls through to 404 when contacts_acceptor isn't attached.
    if (std.mem.startsWith(u8, path, "/api/v1/contacts")) {
        const tail = path["/api/v1/contacts".len..];
        // Avoid matching /api/v1/contacts-something-else
        if (tail.len == 0 or tail[0] == '/') {
            var ct_cors_slots: [8]std.http.Header = undefined;
            const ct_cors_hdrs = cors.responseHeaders(&ct_cors_slots);
            const ct_status = reactorHandleContacts(server, req, write_buf, alloc, ct_cors_hdrs);
            server.logRequest(methodToEnum(method), path, ct_status) catch {};
            return .close_after_drain;
        }
    }

    // ── 8g. /api/v1/intent — D-brain-intent-classifier-api ─────────────
    //   POST /api/v1/intent/classify          → text → IntentClassification
    //   GET  /api/v1/intent/taxonomy          → taxonomy tree snapshot
    //   POST /api/v1/intent/taxonomy/inject   → merge extension grammar
    //   Falls through to 404 when intent_acceptor isn't attached.
    if (std.mem.startsWith(u8, path, "/api/v1/intent")) {
        const tail = path["/api/v1/intent".len..];
        if (tail.len == 0 or tail[0] == '/') {
            var it_cors_slots: [8]std.http.Header = undefined;
            const it_cors_hdrs = cors.responseHeaders(&it_cors_slots);
            const it_status = reactorHandleIntent(server, req, write_buf, alloc, it_cors_hdrs);
            server.logRequest(methodToEnum(method), path, it_status) catch {};
            return .close_after_drain;
        }
    }

    // ── 8h. /api/v1/identity/{hat,hats,cert} — D-brain-identity-store-api
    //   GET  /api/v1/identity/hat          → active hat for bearer
    //   GET  /api/v1/identity/hats         → list all known hats
    //   POST /api/v1/identity/hat/switch   → switch active hat
    //   GET  /api/v1/identity/cert         → cert snapshot for bearer
    //   Note: /api/v1/identity/merge is handled above (exact match) and
    //   will never reach this block.
    //   Falls through to 404 when identity_acceptor isn't attached.
    if (std.mem.startsWith(u8, path, "/api/v1/identity")) {
        const tail = path["/api/v1/identity".len..];
        if (tail.len == 0 or tail[0] == '/') {
            var id_cors_slots: [8]std.http.Header = undefined;
            const id_cors_hdrs = cors.responseHeaders(&id_cors_slots);
            const id_status = reactorHandleIdentityStore(server, req, write_buf, alloc, id_cors_hdrs);
            server.logRequest(methodToEnum(method), path, id_status) catch {};
            return .close_after_drain;
        }
    }

    // ── 8n. /api/v1/objects — D-brain-loom-store-api (2026-05-24) ───────
    //   GET /api/v1/objects/{type}        → list objects of that type
    //   GET /api/v1/objects/{type}/{id}   → get one object by id
    //   Falls through to 404 when loom_store_acceptor isn't attached.
    if (std.mem.startsWith(u8, path, "/api/v1/objects")) {
        const tail = path["/api/v1/objects".len..];
        if (tail.len == 0 or tail[0] == '/') {
            var ls_cors_slots: [8]std.http.Header = undefined;
            const ls_cors_hdrs = cors.responseHeaders(&ls_cors_slots);
            const ls_status = reactorHandleLoomStore(server, req, write_buf, alloc, ls_cors_hdrs);
            server.logRequest(methodToEnum(method), path, ls_status) catch {};
            return .close_after_drain;
        }
    }

    // ── 8p. /api/v1/flow — D-brain-flow-runner-api (2026-05-24) ──────────
    //   POST /api/v1/flow/run              → start a new flow run
    //   GET  /api/v1/flow/{runId}          → get run state
    //   POST /api/v1/flow/{runId}/step     → advance run one step
    //   Falls through to 404 when flow_acceptor isn't attached.
    if (std.mem.startsWith(u8, path, "/api/v1/flow")) {
        const tail = path["/api/v1/flow".len..];
        if (tail.len == 0 or tail[0] == '/') {
            var fl_cors_slots: [8]std.http.Header = undefined;
            const fl_cors_hdrs = cors.responseHeaders(&fl_cors_slots);
            const fl_status = reactorHandleFlow(server, req, write_buf, alloc, fl_cors_hdrs);
            server.logRequest(methodToEnum(method), path, fl_status) catch {};
            return .close_after_drain;
        }
    }

    // ── 8k. /api/v1/conversation/turns — MIGRATED (C4 PR-G3): now served by the
    //   oddjobz cartridge via the route registry (consulted below). Removed with
    //   this branch: reactorHandleConvTurnsQuery + SiteServer.conv_turns_query_script.

    // ── 8b. Cartridge-contributed HTTP routes (C4 PR-F1 route registry) ──
    // Consulted AFTER the hardcoded substrate/cartridge routes above (so
    // substrate routes always win) and BEFORE the static-file / 404
    // fallthrough below. A cartridge registers its route at boot via
    // deps.route_registry (cartridge seam); the v1 handler returns a
    // structured response we write with CORS. This is how oddjobz's HTTP
    // acceptors leave serve.zig — migrated over this seam in PR-F2+.
    if (server.route_registry) |rr| {
        if (rr.match(method, path)) |route| {
            var rr_cors_slots: [8]std.http.Header = undefined;
            const rr_cors_hdrs = cors.responseHeaders(&rr_cors_slots);
            const resp = route.handle(route.state, req, alloc) catch |err| {
                std.log.warn(
                    "route registry: handler for {s} {s} failed: {s}",
                    .{ method, path, @errorName(err) },
                );
                reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json", "{\"error\":\"route_handler_failed\"}", rr_cors_hdrs);
                server.logRequest(methodToEnum(method), path, 500) catch {};
                return .close_after_drain;
            };
            // C4 PR-H6 — append the route's optional extra headers (e.g. a binary
            // download's cache-control) after the CORS headers, into one slice.
            var rr_hdr_slots: [16]std.http.Header = undefined;
            var rr_hdr_n: usize = 0;
            for (rr_cors_hdrs) |h| {
                if (rr_hdr_n >= rr_hdr_slots.len) break;
                rr_hdr_slots[rr_hdr_n] = h;
                rr_hdr_n += 1;
            }
            for (resp.extra_headers) |h| {
                if (rr_hdr_n >= rr_hdr_slots.len) break;
                rr_hdr_slots[rr_hdr_n] = h;
                rr_hdr_n += 1;
            }
            reactorWriteWithCors(write_buf, alloc, resp.status, resp.status_text, resp.content_type, resp.body, rr_hdr_slots[0..rr_hdr_n]);
            server.logRequest(methodToEnum(method), path, resp.status) catch {};
            return .close_after_drain;
        }
    }

    // ── 9. Static file delivery via site_config route lookup ───────────
    // Route lookup uses the existing config — no need to re-implement.
    // For simple static routes we serve directly; for auth/payment/dynamic
    // routes we return a clear TODO-REACTOR-COMPLETE message.
    const route_opt = server.config.routeFor(path);
    if (route_opt == null) {
        var notfound_slots: [8]std.http.Header = undefined;
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "text/plain", "404 Not Found\n",
            cors.responseHeaders(&notfound_slots));
        server.logRequest(methodToEnum(method), path, 404) catch {};
        return .close_after_drain;
    }
    const r = route_opt.?;

    // ── RIP-OUT-MARKER (brain-wedge Commit 8b, 2026-05-06): ─────────────
    //   Auth-gated routes wired in reactor.  Replaces the 503 stub from
    //   Commit 5.  Each auth variant checks the __semantos_session cookie
    //   and, on failure, issues the appropriate challenge response (401 for
    //   identity_required, 402 for payment_required).  On success it falls
    //   through to the route-kind dispatch below (chat / static / etc.).
    //   To revert: restore the original 503 stub block:
    //
    //     switch (r.auth) {
    //         .identity_required, .payment_required => {
    //             const body = "...503...";
    //             var auth_slots: [8]std.http.Header = undefined;
    //             reactorWriteWithCors(write_buf, alloc, 503, ..., cors.responseHeaders(&auth_slots));
    //             server.logRequest(methodToEnum(method), path, 503) catch {};
    //             return .close_after_drain;
    //         },
    //         .public => {},
    //     }
    switch (r.auth) {
        .identity_required => {
            var auth_cors_slots: [8]std.http.Header = undefined;
            const auth_cors_hdrs = cors.responseHeaders(&auth_cors_slots);
            if (!reactorRequestHasValidSession(server, req)) {
                const status = reactorHandleIdentityRequired(server, path, write_buf, alloc, auth_cors_hdrs);
                server.logRequest(methodToEnum(method), path, status) catch {};
                return .close_after_drain;
            }
        },
        .payment_required => {
            var auth_cors_slots: [8]std.http.Header = undefined;
            const auth_cors_hdrs = cors.responseHeaders(&auth_cors_slots);
            if (!reactorRequestHasValidSession(server, req)) {
                const status = reactorHandlePaymentRequired(server, r, path, write_buf, alloc, auth_cors_hdrs);
                server.logRequest(methodToEnum(method), path, status) catch {};
                return .close_after_drain;
            }
        },
        .public => {},
    }
    // ── END RIP-OUT-MARKER (brain-wedge Commit 8b) ─────────────────────

    // C4 CW-1 — the D-O6a `chat` site-route + chat_http (LLM-only, no-persist)
    // are retired; the oddjobz cartridge now owns POST /api/v1/chat over the
    // route registry (matched above). A vestigial `RouteType.chat` config (if any)
    // falls through to not-found here; CW-4 removes the enum with RouteType.intake.
    if (r.kind == .intake) {
        var intake_cors_slots: [8]std.http.Header = undefined;
        const intake_cors_hdrs = cors.responseHeaders(&intake_cors_slots);
        const intake_status = reactorHandleIntake(server, req, r, write_buf, alloc, intake_cors_hdrs);
        server.logRequest(methodToEnum(method), path, intake_status) catch {};
        return .close_after_drain;
    }

    // ── RIP-OUT-MARKER (brain-wedge Commit 8c, 2026-05-06): ─────────────
    //   Dynamic WASM handler routes wired in reactor.  Replaces the 501 stub
    //   from Commit 5.  Auth-gated dynamic routes are already handled by the
    //   Commit 8b auth switch above — only authenticated requests reach here.
    //   To revert: replace this block with:
    //
    //     if (r.kind == .dynamic) {
    //         const body = "{\"error\":\"dynamic routes not yet served in reactor mode\"}";
    //         var dyn_slots: [8]std.http.Header = undefined;
    //         reactorWriteWithCors(write_buf, alloc, 501, "Not Implemented", "application/json", body,
    //             cors.responseHeaders(&dyn_slots));
    //         server.logRequest(methodToEnum(method), path, 501) catch {};
    //         return .close_after_drain;
    //     }
    if (r.kind == .dynamic) {
        var dyn_cors_slots: [8]std.http.Header = undefined;
        const dyn_cors_hdrs = cors.responseHeaders(&dyn_cors_slots);
        const dyn_status = reactorHandleDynamic(server, req, write_buf, alloc, r, dyn_cors_hdrs);
        server.logRequest(methodToEnum(method), path, dyn_status) catch {};
        return .close_after_drain;
    }
    // ── END RIP-OUT-MARKER (brain-wedge Commit 8c) ─────────────────────

    // Static / directory file delivery.
    var static_cors_slots: [8]std.http.Header = undefined;
    const static_cors_hdrs = cors.responseHeaders(&static_cors_slots);

    if (r.kind == .directory) {
        // Directory route: strip the route prefix to get the rest, then
        // serve root/<rest>.  Empty rest (exactly the prefix) or file-not-
        // found both fall back to root/<spa_fallback> so the SPA router
        // handles deep links (e.g. Flutter web's CanvasKit build).
        reactorServeDirectory(server, r, path, write_buf, alloc, static_cors_hdrs) catch |err| {
            var err_slots: [8]std.http.Header = undefined;
            const body = "{\"error\":\"internal server error serving directory route\"}";
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json", body,
                cors.responseHeaders(&err_slots));
            std.log.warn("reactor: directory serve error on {s}: {s}", .{ path, @errorName(err) });
            server.logRequest(methodToEnum(method), path, 500) catch {};
            return .close_after_drain;
        };
        server.logRequest(methodToEnum(method), path, 200) catch {};
        return .close_after_drain;
    }

    reactorServeStatic(server, r, write_buf, alloc, static_cors_hdrs) catch |err| {
        var err_slots: [8]std.http.Header = undefined;
        const body = "{\"error\":\"internal server error serving static file\"}";
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json", body,
            cors.responseHeaders(&err_slots));
        std.log.warn("reactor: static serve error on {s}: {s}", .{ path, @errorName(err) });
        server.logRequest(methodToEnum(method), path, 500) catch {};
        return .close_after_drain;
    };
    server.logRequest(methodToEnum(method), path, 200) catch {};
    return .close_after_drain;
}

/// WSS frame dispatch callback for the reactor.
/// Called by ConnectionState.feedWssBytes() on each complete WSS frame.
/// Routes to the right per-session handler based on which upgrade
/// claimed this connection (set by the upgrade handler in
/// reactorDispatchHttp via ctx.kind).
pub fn reactorDispatchWss(
    args: connection_state_mod.WssDispatchArgs,
) connection_state_mod.WssDispatchResult {
    const rctx: *ReactorCtx = @ptrCast(@alignCast(args.ctx));
    switch (rctx.kind) {
        .events => {
            // T3 — dispatch to events frame handler.
            const sess = rctx.events_session orelse return .close_immediately;
            const bus = sess.bus orelse return .close_immediately;
            return reactorEventsHandleFrame(sess, bus, args.frame, args.write_buf, args.allocator);
        },
        .rpc => {
            // Unified RPC channel — dispatch the frame through the registry.
            const sess = rctx.rpc_session orelse return .close_immediately;
            return reactorRpcHandleFrame(rctx.server, sess, args.frame, args.write_buf, args.allocator);
        },
        .wallet, .none => {
            // Default: wallet session (pre-T3 behaviour).  `.none`
            // shouldn't happen post-upgrade — defensive routing
            // through wallet preserves the pre-T3 contract.
            const result = wss_wallet.advanceFrame(
                rctx.session,
                args.frame,
                args.write_buf,
                args.allocator,
            );
            return switch (result) {
                .keep_open => .keep_open,
                .close_after_drain => .close_after_drain,
                .close_immediately => .close_immediately,
            };
        },
    }
}

// ─── Reactor response helpers ─────────────────────────────────────────────

/// Write a simple HTTP/1.1 response with a fixed body into write_buf.
/// Used for error responses, OPTIONS preflight, and 404s.
pub fn reactorWriteSimple(
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    status: u16,
    status_text: []const u8,
    content_type: []const u8,
    body: []const u8,
) void {
    var hdr_buf: [512]u8 = undefined;
    const hdr = std.fmt.bufPrint(
        &hdr_buf,
        "HTTP/1.1 {d} {s}\r\n" ++
            "Content-Type: {s}\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n\r\n",
        .{ status, status_text, content_type, body.len },
    ) catch return;
    write_buf.appendSlice(alloc, hdr) catch return;
    if (body.len > 0) write_buf.appendSlice(alloc, body) catch return;
}

/// Write an HTTP/1.1 response including CORS headers from `cors_hdrs`.
/// Replaces reactorWriteSimple for all responses inside reactorDispatchHttp
/// so that cross-origin requests get the correct ACAO / Vary headers.
///
/// Header layout:
///   Status line
///   Content-Type
///   Content-Length
///   Connection: close
///   <cors_hdrs[0]>: <value>   ← 0–7 extra CORS headers
///   <cors_hdrs[N]>: <value>
///   (blank line)
///   <body>
pub fn reactorWriteWithCors(
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    status: u16,
    status_text: []const u8,
    content_type: []const u8,
    body: []const u8,
    cors_hdrs: []const std.http.Header,
) void {
    var hdr_buf: [512]u8 = undefined;
    const status_line = std.fmt.bufPrint(
        &hdr_buf,
        "HTTP/1.1 {d} {s}\r\n" ++
            "Content-Type: {s}\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n",
        .{ status, status_text, content_type, body.len },
    ) catch return;
    write_buf.appendSlice(alloc, status_line) catch return;
    // Append each CORS header individually.
    for (cors_hdrs) |h| {
        var cors_line_buf: [256]u8 = undefined;
        const cors_line = std.fmt.bufPrint(&cors_line_buf, "{s}: {s}\r\n", .{ h.name, h.value }) catch continue;
        write_buf.appendSlice(alloc, cors_line) catch return;
    }
    // Blank line ends headers.
    write_buf.appendSlice(alloc, "\r\n") catch return;
    if (body.len > 0) write_buf.appendSlice(alloc, body) catch return;
}

/// Reactor-compatible intake route handler.  Spawns the Bun subprocess
/// for each request.  Returns the HTTP status code.
pub fn reactorHandleIntake(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    route: *const site_config.Route,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    if (!std.mem.eql(u8, req.method, "POST")) {
        reactorWriteWithCors(write_buf, alloc, 405, "Method Not Allowed", "application/json",
            "{\"error\":\"POST required\"}", cors_hdrs);
        return 405;
    }

    const max_chars: u32 = if (route.intake_max_message_chars > 0)
        route.intake_max_message_chars
    else
        intake_http.DEFAULT_MAX_MESSAGE_CHARS;

    const parsed = intake_http.parseIntakeRequest(alloc, req.body) catch |err| {
        const msg = switch (err) {
            error.missing_message => "{\"error\":\"missing required field: message\"}",
            error.malformed => "{\"error\":\"body must be JSON {message:string, session_id?:string}\"}",
            else => "{\"error\":\"failed to parse body\"}",
        };
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json", msg, cors_hdrs);
        return 400;
    };
    defer parsed.deinit(alloc);

    if (parsed.message.len > max_chars) {
        reactorWriteWithCors(write_buf, alloc, 413, "Payload Too Large", "application/json",
            "{\"error\":\"message exceeds max_message_chars\"}", cors_hdrs);
        return 413;
    }

    // P1b — extract optional `?j=<cellId>` query param.  When present, the
    // intake-handler TypeScript anchors the written ConversationTurn to the
    // job cell.  Validated: must be exactly 64 hex chars or ignored.
    const raw_j = events_stream_handler.queryParam(req.query, "j");
    var j_param: ?[]const u8 = null;
    if (raw_j) |j| {
        if (j.len == 64) {
            var all_hex = true;
            for (j) |c| {
                if (!((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F'))) {
                    all_hex = false;
                    break;
                }
            }
            if (all_hex) j_param = j;
        }
    }

    const response_body = intake_http.callScript(alloc, route.intake_script, parsed, server.site_data_dir, j_param) catch |err| {
        std.log.warn("intake: subprocess error on {s}: {s}", .{ route.path, @errorName(err) });
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"intake subprocess failed\"}", cors_hdrs);
        return 500;
    };
    defer alloc.free(response_body);

    if (response_body.len == 0) {
        reactorWriteWithCors(write_buf, alloc, 502, "Bad Gateway", "application/json",
            "{\"error\":\"intake script returned empty response\"}", cors_hdrs);
        return 502;
    }

    reactorWriteWithCors(write_buf, alloc, 200, "OK", "application/json", response_body, cors_hdrs);
    return 200;
}

/// Reactor-compatible REPL route handler.  Mirrors repl_http.maybeHandle()
/// but writes to write_buf instead of std.http.Server.Request.
///
/// Returns the HTTP status code so the caller can pass it to logRequest.
///
/// Steps (matching the blocking repl_http.maybeHandle path):
///   1. POST-only gate → 405
///   2. Bearer-auth gate → 401 with the same error messages as maybeHandle
///   3. Backend gate → 503 when bearer_tokens or repl_session is absent
///   4. Parse JSON body for {"cmd":"..."} → 400 on malformed input
///   5. Dispatch into repl.handleLine with a captured Output buffer
///   6. Write 200 with {"result":"...","exit":"..."} JSON
pub fn reactorHandleRepl(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    // 1. Method gate — REPL is POST-only.
    if (!std.mem.eql(u8, req.method, "POST")) {
        reactorWriteWithCors(write_buf, alloc, 405, "Method Not Allowed", "application/json",
            "{\"error\":\"POST required\"}", cors_hdrs);
        return 405;
    }

    // 2. Bearer auth — mirrors repl_http.maybeHandle's auth block.
    const auth_header = req.header("authorization") orelse {
        reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
            "{\"error\":\"missing bearer token\"}", cors_hdrs);
        return 401;
    };
    const bearer_hex = repl_http.parseBearerHeader(auth_header) orelse {
        reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
            "{\"error\":\"malformed Authorization header\"}", cors_hdrs);
        return 401;
    };

    // 3. Backend gate — both bearer_tokens and repl_session must be set.
    const toks = server.bearer_tokens orelse {
        reactorWriteWithCors(write_buf, alloc, 503, "Service Unavailable", "application/json",
            "{\"error\":\"REPL backend not enabled in this serve mode\"}", cors_hdrs);
        return 503;
    };
    const sess = server.repl_session orelse {
        reactorWriteWithCors(write_buf, alloc, 503, "Service Unavailable", "application/json",
            "{\"error\":\"REPL backend not enabled in this serve mode\"}", cors_hdrs);
        return 503;
    };

    _ = toks.verifyHex(bearer_hex) catch |err| {
        const msg = switch (err) {
            error.expired => "{\"error\":\"bearer token expired\"}",
            error.bad_format => "{\"error\":\"bearer token must be 64 hex chars\"}",
            else => "{\"error\":\"bearer token not recognised\"}",
        };
        reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
            msg, cors_hdrs);
        return 401;
    };

    // 4. Parse JSON body for {"cmd":"..."}.
    const cmd = repl_http.parseCmdField(alloc, req.body) catch {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"body must be JSON {\\\"cmd\\\":\\\"...\\\"}\"}",
            cors_hdrs);
        return 400;
    };
    defer alloc.free(cmd);

    // 5. Dispatch into repl.handleLine with a captured Output buffer.
    var out_buf: std.ArrayList(u8) = .{};
    defer out_buf.deinit(alloc);
    var out: repl.Output = .{ .buffer = &out_buf, .allocator = alloc };
    const exit = repl.handleLine(sess, &out, cmd) catch |err| {
        const summary_buf = std.fmt.allocPrint(
            alloc,
            "{{\"error\":\"REPL dispatch failed: {s}\"}}",
            .{@errorName(err)},
        ) catch {
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                "{\"error\":\"REPL dispatch failed\"}", cors_hdrs);
            return 500;
        };
        defer alloc.free(summary_buf);
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            summary_buf, cors_hdrs);
        return 500;
    };

    // 6. Build response: {"result":"<json-encoded output>","exit":"continue"|"quit"}.
    var resp_buf: std.ArrayList(u8) = .{};
    defer resp_buf.deinit(alloc);
    resp_buf.appendSlice(alloc, "{\"result\":") catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"failed to build response\"}", cors_hdrs);
        return 500;
    };
    repl_http.jsonEncodeString(alloc, &resp_buf, out_buf.items) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"failed to build response\"}", cors_hdrs);
        return 500;
    };
    resp_buf.appendSlice(alloc, ",\"exit\":\"") catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"failed to build response\"}", cors_hdrs);
        return 500;
    };
    resp_buf.appendSlice(alloc, switch (exit) {
        .quit => "quit",
        .@"continue" => "continue",
    }) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"failed to build response\"}", cors_hdrs);
        return 500;
    };
    resp_buf.appendSlice(alloc, "\"}") catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"failed to build response\"}", cors_hdrs);
        return 500;
    };

    reactorWriteWithCors(write_buf, alloc, 200, "OK", "application/json", resp_buf.items, cors_hdrs);
    return 200;
}

/// Reactor-compatible device-pair route handler.
/// Mirrors device_pair_http.maybeHandle() but writes to write_buf instead
/// of std.http.Server.Request.
///
/// Returns the HTTP status code so the caller can pass it to logRequest.
///
/// Device-pair is intentionally unauthenticated — it is the mechanism by
/// which a new device obtains its bearer token.  Do NOT add bearer auth here.
///
/// Steps (mirroring device_pair_http.maybeHandle):
///   1. Method gate — POST only (405 otherwise).
///   2. Acceptor gate — 503 when device_pair_acceptor is null.
///   3. Parse JSON body — 400 on malformed/missing fields.
///   4. Call device_pair_http.accept() — maps result kind to HTTP status.
///   5. Write JSON response (success or typed error).
pub fn reactorHandleDevicePair(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    // 1. Method gate — device-pair is POST-only.
    if (!std.mem.eql(u8, req.method, "POST")) {
        reactorWriteWithCors(write_buf, alloc, 405, "Method Not Allowed", "application/json",
            "{\"error\":\"method_not_allowed\",\"hint\":\"POST required\"}", cors_hdrs);
        return 405;
    }

    // 2. Acceptor gate — 503 when not attached.
    const acceptor = server.device_pair_acceptor orelse {
        reactorWriteWithCors(write_buf, alloc, 503, "Service Unavailable", "application/json",
            "{\"error\":\"device-pair acceptor not enabled in this serve mode\"}", cors_hdrs);
        return 503;
    };

    // 3. Parse JSON body.  Body is already accumulated by the http_parser.
    const parsed_req = device_pair_http.parseAcceptRequest(alloc, req.body) catch |err| {
        const msg = switch (err) {
            error.derivation_missing_fields => "{\"error\":\"derivation_missing_fields\"}",
            else => "{\"error\":\"payload_invalid_format\"}",
        };
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json", msg, cors_hdrs);
        return 400;
    };
    // AcceptHttpRequest.deinit is private; free the owned token slice directly.
    defer alloc.free(parsed_req.token);

    // 4. Dispatch into the acceptor.
    const now: i64 = @intCast(std.time.timestamp());
    var result = device_pair_http.accept(
        acceptor,
        now,
        parsed_req.token,
        parsed_req.derivation_pubkey,
        parsed_req.derivation_proof,
    ) catch |err| switch (err) {
        device_pair_http.Error.out_of_memory => {
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                "{\"error\":\"internal_error\",\"hint\":\"out_of_memory\"}", cors_hdrs);
            return 500;
        },
        else => {
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                "{\"error\":\"internal_error\"}", cors_hdrs);
            return 500;
        },
    };
    defer result.deinit(alloc);

    // 5. Write response.
    const http_status = result.kind.httpStatus();
    const status_code: u16 = @intFromEnum(http_status);

    if (result.kind == .registered) {
        const cert_id = result.cert_id orelse {
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                "{\"error\":\"internal_error\",\"hint\":\"registered with no cert_id\"}", cors_hdrs);
            return 500;
        };
        const brain_id = result.brain_cert_id orelse {
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                "{\"error\":\"internal_error\",\"hint\":\"registered with no brain_cert_id\"}", cors_hdrs);
            return 500;
        };

        // Mint a bearer token when the token store is wired so the device
        // can immediately hit /api/v1/repl without a separate bearer-mint
        // roundtrip.  Mirrors device_pair_http.maybeHandle's bearer block.
        var bearer_hex: [64]u8 = undefined;
        var bearer_set = false;
        if (acceptor.token_store) |ts| {
            const issued = ts.issue("device-pair", 60 * 60 * 24 * 30) catch null;
            if (issued) |minted| {
                const hex_chars = "0123456789abcdef";
                for (minted.token, 0..) |b, i| {
                    bearer_hex[i * 2] = hex_chars[b >> 4];
                    bearer_hex[i * 2 + 1] = hex_chars[b & 0x0f];
                }
                bearer_set = true;
            }
        }

        var resp_buf: std.ArrayList(u8) = .{};
        defer resp_buf.deinit(alloc);
        if (bearer_set) {
            resp_buf.print(alloc,
                "{{\"status\":\"registered\",\"cert_id\":\"{s}\",\"brain_cert_id\":\"{s}\",\"bearer\":\"{s}\"}}",
                .{ &cert_id, &brain_id, &bearer_hex }) catch {
                reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                    "{\"error\":\"internal_error\"}", cors_hdrs);
                return 500;
            };
        } else {
            resp_buf.print(alloc,
                "{{\"status\":\"registered\",\"cert_id\":\"{s}\",\"brain_cert_id\":\"{s}\"}}",
                .{ &cert_id, &brain_id }) catch {
                reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                    "{\"error\":\"internal_error\"}", cors_hdrs);
                return 500;
            };
        }
        const status_text = if (status_code == 200) "OK" else "Error";
        reactorWriteWithCors(write_buf, alloc, status_code, status_text, "application/json",
            resp_buf.items, cors_hdrs);
        return status_code;
    }

    // Error path — emit {"error":"<typed code>"}.
    var err_buf: std.ArrayList(u8) = .{};
    defer err_buf.deinit(alloc);
    err_buf.print(alloc, "{{\"error\":\"{s}\"}}", .{result.kind.wireName()}) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"internal_error\"}", cors_hdrs);
        return 500;
    };
    // Map the Zig HTTP status enum to a text string.
    const status_text = switch (http_status) {
        .bad_request => "Bad Request",
        .unauthorized => "Unauthorized",
        .conflict => "Conflict",
        .gone => "Gone",
        .unprocessable_entity => "Unprocessable Entity",
        .internal_server_error => "Internal Server Error",
        else => "Error",
    };
    reactorWriteWithCors(write_buf, alloc, status_code, status_text, "application/json",
        err_buf.items, cors_hdrs);
    return status_code;
}

// ─── T1 — attachment upload + blob retrieval handlers ─────────────────────────
//
// These mirror attachments_upload_http.maybeHandle and
// attachments_blob_http.maybeHandle (the std.http.Server-shape entry
// points in the dead request.zig path) but write to write_buf instead
// of calling request.respond.  Pure logic mirror — the acceptor module
// owns the multipart parser, signature verification, blob persistence,
// and metadata cell insertion, all reused as pub helpers.
//
// Per-route body cap (12 MiB) is declared in ROUTE_BODY_CAPS so T0's
// parser allocates a body buffer large enough for the multipart
// envelope before reaching this handler.

/// Extract a 64-hex-char bearer token from the Authorization header on
/// a reactor HttpRequest.  Returns null on missing / malformed.  Mirrors
/// attachments_upload_http.bearerFromHeaders but on the parsed-request
/// shape (no std.http.Server.Request).
fn reactorBearerHex64(req: *const http_parser_mod.HttpRequest) ?[]const u8 {
    const authz = req.header("authorization") orelse return null;
    const prefix = "Bearer ";
    if (authz.len <= prefix.len) return null;
    if (!std.ascii.eqlIgnoreCase(authz[0..prefix.len], prefix)) return null;
    const tok = std.mem.trim(u8, authz[prefix.len..], " \t");
    if (tok.len != 64) return null;
    for (tok) |c| {
        const ok = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
        if (!ok) return null;
    }
    return tok;
}

/// Tracker T7 — unified request auth: BRC-52 cert + capability OR the
/// legacy bearer token.  Returns the access decision for `path`:
///
///   • If the cert-auth headers (X-Brain-Pubkey / X-Brain-Cert-Sig /
///     X-Brain-Cert-Ts) are present, authorise via `cert_request_auth`
///     against the brain's cert store: the route's class (admin / user /
///     public, per `ROUTE_AUTH_POLICIES`) decides whether the cert's
///     capability suffices.  An operator (admin) cert is allowed on admin
///     routes; a verified non-admin cert is `deny_forbidden` (403) there
///     but allowed on user/public routes.
///   • Otherwise fall back to the legacy bearer token — UNLESS the
///     operator set `require_cert_auth`, in which case a cert credential
///     is mandatory and the bearer path is retired.
///
/// `path` MUST be the query-stripped path (the bytes the client signs in
/// the challenge); callers pass the same `path_only` they route on.
const AuthOutcome = enum { allow, deny_unauthorized, deny_forbidden };

fn reactorAuthorize(
    server: *SiteServer,
    bearer_store: *bearer_tokens.TokenStore,
    req: *const http_parser_mod.HttpRequest,
    path: []const u8,
) AuthOutcome {
    const pubkey_hex = req.header(cert_request_auth.PUBKEY_HEADER);
    const sig_hex = req.header(cert_request_auth.SIG_HEADER);
    const ts_str = req.header(cert_request_auth.TIMESTAMP_HEADER);

    if (cert_request_auth.hasCertHeaders(pubkey_hex, sig_hex, ts_str)) {
        const store = server.cert_store orelse return .deny_unauthorized;
        const decision = cert_request_auth.authorizeFromHeaders(
            store,
            pubkey_hex,
            sig_hex,
            ts_str,
            req.method,
            path,
            std.time.timestamp(),
            cert_request_auth.DEFAULT_MAX_SKEW_SECS,
        );
        return switch (decision) {
            .allow_admin, .allow_user => .allow,
            .deny_forbidden => .deny_forbidden,
            .deny_unauthenticated => .deny_unauthorized,
        };
    }

    // Legacy bearer fallback (retired when require_cert_auth is set).
    if (server.require_cert_auth) return .deny_unauthorized;
    const bearer = reactorBearerHex64(req) orelse return .deny_unauthorized;
    _ = bearer_store.verifyHex(bearer) catch return .deny_unauthorized;
    return .allow;
}

// C4 PR-H7b — reactorHandleAttachmentsUpload removed. POST
// /api/v1/attachments/upload is now served by the oddjobz cartridge's
// route-registry handler (attachmentsUploadRouteHandler in registration.zig),
// which builds a per-request attachments_upload_http.Acceptor over the
// cartridge-owned stores + the substrate cert/token stores from CartridgeDeps.

// C4 PR-H6 — reactorHandleAttachmentsBlob removed. GET
// /api/v1/attachments/{id}/blob is now served by the oddjobz cartridge's
// route-registry handler (attachmentsBlobRouteHandler in registration.zig),
// reading the cartridge-owned attachments + blob stores + returning the blob
// with its mime content-type + cache-control via RouteResponse.extra_headers.

// ─── BRAIN-GENERIC-MINT-VERB M1 — POST /api/v1/cells generic mint ───────────
//
// POST only. Body shape: {"typeHashHex":"<64hex>","payload":{...},
// "capabilityProof": <opaque, optional>}.  Bearer-gated.
//
// Pipeline (per docs/design/BRAIN-GENERIC-MINT-VERB.md):
//   1. Acceptor gate            → 404 if not attached
//   2. Method gate              → 405 if not POST
//   3. Bearer auth              → 401 if missing/invalid
//   4. Parse body               → 400 / 413
//   5. Registry lookup typeHash → 404 if unknown
//   6. Map registry Linearity → substrate_entity.LinearityClass
//   7. encodeFromTypeHash       → 413 if payload >768 bytes (octave-1
//                                  escalation lands in M2 follow-up)
//   8. cell_store.put           → 500 on persistence failure
//   9. broker.publish           → cells.<cartridge-id>.minted (best-effort;
//                                  publish failures don't fail the mint —
//                                  same posture as anchor emission in
//                                  cell_handler.zig)
//   10. 201 Created            → {"cellId":"<64hex>","cartridgeId":"...",
//                                  "cellType":"...","persistedAt":<unix-ms>}
//
// Capability gate: v0.1.0 honours the registry's `capability_name` as
// metadata only — the brain's bearer_tokens layer doesn't yet surface
// per-cert capability sets (parked under Phase-1b BCA/cert identity
// work).  When that lands, the gate fails-closed on missing capability;
// for now any valid bearer + known typeHash is sufficient.  Documented
// in the design record under OI-1.
/// D-helm-rtc-operator-sign — POST /api/v1/bundle/sign.
///
/// Signs a helm-supplied UNSIGNED SignedBundle AS the operator, using the
/// operator pin private key (`device_pair_acceptor.operator_root_priv`). The
/// helm SPA never holds that key, so call signalling (rtc.jingle) is signed
/// here and the recipient can verify call authenticity. ADMIN route: only the
/// operator may sign as the operator. Signing core is bundle_sign_http.zig.
pub fn reactorHandleBundleSign(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    // 1. Operator-key gate — 404 when device pairing (hence the operator root
    //    priv) isn't configured; 503 when the key half wasn't loaded.
    const acceptor = server.device_pair_acceptor orelse {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "application/json",
            "{\"error\":\"not_found\"}", cors_hdrs);
        return 404;
    };
    const priv = acceptor.operator_root_priv orelse {
        reactorWriteWithCors(write_buf, alloc, 503, "Service Unavailable", "application/json",
            "{\"error\":\"operator_key_unavailable\"}", cors_hdrs);
        return 503;
    };
    const toks = server.bearer_tokens orelse {
        reactorWriteWithCors(write_buf, alloc, 503, "Service Unavailable", "application/json",
            "{\"error\":\"auth_unavailable\"}", cors_hdrs);
        return 503;
    };

    // 2. Method gate — POST only.
    if (!std.mem.eql(u8, req.method, "POST")) {
        reactorWriteWithCors(write_buf, alloc, 405, "Method Not Allowed", "application/json",
            "{\"error\":\"method_not_allowed\",\"hint\":\"POST required\"}", cors_hdrs);
        return 405;
    }

    // 3. Auth — ADMIN route. Query-stripped path matches the signed bytes.
    const auth_path = if (std.mem.indexOfScalar(u8, req.path, '?')) |q| req.path[0..q] else req.path;
    switch (reactorAuthorize(server, toks, req, auth_path)) {
        .allow => {},
        .deny_unauthorized => {
            reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
                "{\"error\":\"unauthorized\",\"hint\":\"present a valid bearer token or BRC-52 cert credential\"}", cors_hdrs);
            return 401;
        },
        .deny_forbidden => {
            reactorWriteWithCors(write_buf, alloc, 403, "Forbidden", "application/json",
                "{\"error\":\"capability_denied\",\"hint\":\"this route requires the admin capability (cap.brain.admin)\"}", cors_hdrs);
            return 403;
        },
    }

    // 4. Parse → re-stamp → sign → encode (pure core).
    const signed_json = bundle_sign_http.signBundleJson(alloc, req.body, priv, std.time.timestamp()) catch |err| switch (err) {
        error.parse_failed => {
            reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
                "{\"error\":\"bad_request\",\"hint\":\"body must be an unsigned SignedBundle JSON\"}", cors_hdrs);
            return 400;
        },
        else => {
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                "{\"error\":\"sign_failed\"}", cors_hdrs);
            return 500;
        },
    };
    defer alloc.free(signed_json);

    // 5. 200 — the signed bundle, ready for the helm to relay unchanged.
    reactorWriteWithCors(write_buf, alloc, 200, "OK", "application/json", signed_json, cors_hdrs);
    return 200;
}

pub fn reactorHandleCellsMint(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    // 1. Acceptor gate.
    const acceptor = server.cells_mint_acceptor orelse {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "application/json",
            "{\"error\":\"not_found\"}", cors_hdrs);
        return 404;
    };

    // 2. Method gate — POST only.
    if (!std.mem.eql(u8, req.method, "POST")) {
        reactorWriteWithCors(write_buf, alloc, 405, "Method Not Allowed", "application/json",
            "{\"error\":\"method_not_allowed\",\"hint\":\"POST required\"}", cors_hdrs);
        return 405;
    }

    // 3. Auth — Tracker T7.  `/api/v1/cells` is an ADMIN route: an
    //    operator (admin) cert OR the legacy bearer token is accepted; a
    //    verified non-admin (field-user) cert is rejected with 403,
    //    isolating field users from the sovereign mint surface.  Path is
    //    query-stripped so it matches the bytes the client signs.
    const auth_path = if (std.mem.indexOfScalar(u8, req.path, '?')) |q| req.path[0..q] else req.path;
    switch (reactorAuthorize(server, acceptor.bearer_tokens, req, auth_path)) {
        .allow => {},
        .deny_unauthorized => {
            reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
                "{\"error\":\"unauthorized\",\"hint\":\"present a valid bearer token or BRC-52 cert credential\"}", cors_hdrs);
            return 401;
        },
        .deny_forbidden => {
            reactorWriteWithCors(write_buf, alloc, 403, "Forbidden", "application/json",
                "{\"error\":\"capability_denied\",\"hint\":\"this route requires the admin capability (cap.brain.admin)\"}", cors_hdrs);
            return 403;
        },
    }

    // 4. Parse request body.
    var mint_req = cells_mint_http.parseRequestBody(alloc, req.body) catch |err| switch (err) {
        cells_mint_http.Error.payload_too_large => {
            reactorWriteWithCors(write_buf, alloc, 413, "Payload Too Large", "application/json",
                "{\"error\":\"payload_too_large\"}", cors_hdrs);
            return 413;
        },
        cells_mint_http.Error.out_of_memory => {
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                "{\"error\":\"out_of_memory\"}", cors_hdrs);
            return 500;
        },
        else => {
            reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
                "{\"error\":\"bad_request\",\"hint\":\"body must be {typeHashHex,payload}\"}", cors_hdrs);
            return 400;
        },
    };
    defer cells_mint_http.deinitRequest(alloc, &mint_req);

    // 5. Registry lookup.
    const entry = cells_mint_http.resolveCellType(&mint_req.type_hash) catch {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "application/json",
            "{\"error\":\"unknown_type_hash\"}", cors_hdrs);
        return 404;
    };

    // 5b–9. BRAIN-GENERIC-MINT-VERB — delegate the mint BODY (schema
    //        validation, operator-signature verify, linearity map, encode,
    //        cell-script dispatch hook, persist, auto-anchor, broker publish)
    //        to the shared transport-agnostic core (`cells_mint_core`). The
    //        `cells.mint` WSS RPC method calls the SAME core, so the two
    //        transports can't drift. The auth/method/parse/lookup steps above
    //        stay here because they differ per transport (RPC binds auth at
    //        the socket upgrade and parses `params` rather than an HTTP body).
    switch (cells_mint_core.mintCellCore(acceptor, &mint_req, entry, alloc)) {
        .created => |c| {
            // 10. 201 Created — body echoes resolved metadata so the client
            //     can correlate without re-deriving anything.
            var resp_buf = std.ArrayList(u8){};
            defer resp_buf.deinit(alloc);
            resp_buf.writer(alloc).print(
                "{{\"cellId\":\"{s}\",\"cartridgeId\":\"{s}\",\"cellType\":\"{s}\",\"persistedAt\":{d}}}",
                .{ c.cell_hash_hex[0..64], c.cartridge_id, c.cell_type_name, c.persisted_at },
            ) catch {
                reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                    "{\"error\":\"response_build_failed\"}", cors_hdrs);
                return 500;
            };
            reactorWriteWithCors(write_buf, alloc, 201, "Created", "application/json",
                resp_buf.items, cors_hdrs);
            return 201;
        },
        .failed => |f| {
            // Reconstruct the exact pre-extraction JSON body for each failure
            // tag + its optional structured detail, then write it at f's
            // status. The body shapes here are byte-identical to what the
            // inline handler produced before the core extraction.
            var resp_buf = std.ArrayList(u8){};
            defer resp_buf.deinit(alloc);
            const print_result = if (f.detail) |d| switch (d) {
                .field_type => |ft| resp_buf.writer(alloc).print(
                    "{{\"error\":\"{s}\",\"field\":\"{s}\",\"expectedType\":\"{s}\"}}",
                    .{ f.error_tag, ft.field, ft.expected_type }),
                .reason => |r| resp_buf.writer(alloc).print(
                    "{{\"error\":\"{s}\",\"reason\":\"{s}\"}}", .{ f.error_tag, r }),
                .hint => |h| resp_buf.writer(alloc).print(
                    "{{\"error\":\"{s}\",\"hint\":\"{s}\"}}", .{ f.error_tag, h }),
            } else resp_buf.writer(alloc).print(
                "{{\"error\":\"{s}\"}}", .{f.error_tag});
            const body: []const u8 = if (print_result) |_|
                resp_buf.items
            else |_|
                "{\"error\":\"response_build_failed\"}";
            reactorWriteWithCors(write_buf, alloc, f.http_status,
                mintFailureStatusText(f.http_status), "application/json", body, cors_hdrs);
            return f.http_status;
        },
    }
}

/// HTTP reason-phrase for the statuses `cells_mint_core.MintOutcome.Failure`
/// can carry. Mirrors the literals the inline mint handler used per branch.
fn mintFailureStatusText(status: u16) []const u8 {
    return switch (status) {
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        413 => "Payload Too Large",
        else => "Internal Server Error",
    };
}

// ─── D-LC1 — /api/v1/cell/<sha256hex> raw-cell read handler ──────────────────
//
// GET only. Returns the 1024-byte cell straight out of LmdbCellStore with
// Content-Type: application/x-semantos-cell. Bearer-gated. Echoes
// `x-cell-sha256` so the client can re-check the bytes it received against
// the hash it asked for without recomputing locally first.
//
// 404 is the canonical response for both "acceptor not attached" and
// "cell not found" — matches the wire shape the other reactor endpoints use.

pub fn reactorHandleCellRaw(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    // 1. Acceptor gate.
    const acceptor = server.cell_raw_acceptor orelse {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "application/json",
            "{\"error\":\"not_found\"}", cors_hdrs);
        return 404;
    };

    // 2. Method gate — GET / HEAD only.
    if (!std.mem.eql(u8, req.method, "GET") and !std.mem.eql(u8, req.method, "HEAD")) {
        reactorWriteWithCors(write_buf, alloc, 405, "Method Not Allowed", "application/json",
            "{\"error\":\"method_not_allowed\",\"hint\":\"GET required\"}", cors_hdrs);
        return 405;
    }

    // 3. Path → 32-byte hash via the acceptor module's pure helper.
    const hash = cell_raw_http.parsePath(req.path) orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"bad_request\",\"hint\":\"path must be /api/v1/cell/<64hex>\"}", cors_hdrs);
        return 400;
    };

    // 4. Bearer auth.
    const bearer = reactorBearerHex64(req) orelse {
        reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
            "{\"error\":\"bearer_invalid\"}", cors_hdrs);
        return 401;
    };
    _ = acceptor.bearer_tokens.verifyHex(bearer) catch {
        reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
            "{\"error\":\"bearer_invalid\"}", cors_hdrs);
        return 401;
    };

    // 5. Look up cell by hash.
    const cell_opt = acceptor.cell_store.getCell(&hash) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"persistence_failed\"}", cors_hdrs);
        return 500;
    };
    const cell = cell_opt orelse {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "application/json",
            "{\"error\":\"not_found\"}", cors_hdrs);
        return 404;
    };

    // 6. Build response. Echo the hash back so clients can verify integrity
    //    without recomputing on every fetch. cache-control: immutable since
    //    cells are content-addressed.
    var hash_hex: [64]u8 = undefined;
    bytesToHex(&hash, &hash_hex);

    // D-LC5 — surface the anchor status if brain has projected one. Clients
    // can decide whether to trust the cell (e.g. wait for `confirmed`
    // before user-facing display). Absent header = brain has no opinion.
    const anchor_status_opt = acceptor.cell_store.getAnchorStatus(&hash);

    var extra_slots: [10]std.http.Header = undefined;
    var extra_n: usize = 0;
    for (cors_hdrs) |h| {
        if (extra_n >= extra_slots.len) break;
        extra_slots[extra_n] = h;
        extra_n += 1;
    }
    if (extra_n < extra_slots.len) {
        extra_slots[extra_n] = .{ .name = "cache-control", .value = "public, max-age=31536000, immutable" };
        extra_n += 1;
    }
    if (extra_n < extra_slots.len) {
        extra_slots[extra_n] = .{ .name = "x-cell-sha256", .value = &hash_hex };
        extra_n += 1;
    }
    if (anchor_status_opt) |status| {
        if (extra_n < extra_slots.len) {
            const status_str: []const u8 = switch (status) {
                .pending => "pending",
                .confirmed => "confirmed",
            };
            extra_slots[extra_n] = .{ .name = "x-cell-anchor", .value = status_str };
            extra_n += 1;
        }
    }
    reactorWriteWithCors(write_buf, alloc, 200, "OK", "application/x-semantos-cell",
        cell[0..], extra_slots[0..extra_n]);
    return 200;
}

// ─── Betterment-practice pask sweep — GET /api/v1/betterment/sweep ───────────────────────
//
// 1. Acceptor gate — 503 when not attached.
// 2. Method gate — GET only.
// 3. Bearer auth.
// 4. Fetch all cell hashes owned by the zero owner from the cell store.
// 5. Load each cell, filter to betterment.practice.* namespace prefix, cap at 300.
// 6. Build JSON { "cells": [...] } and pipe to `bun run <sweep_script>`.
// 7. Return the Bun subprocess stdout (PaskSweepResult JSON) as the response.
//
// The payload bytes (cell[256..1023]) are embedded as a raw JSON VALUE in
// the cells array — they ARE valid JSON written by the mint path, trimmed
// of trailing NUL bytes.

pub fn reactorHandleBettermentSweep(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    // 1. Acceptor gate.
    const acceptor = server.betterment_sweep_acceptor orelse {
        reactorWriteWithCors(write_buf, alloc, 503, "Service Unavailable", "application/json",
            "{\"error\":\"not_configured\",\"hint\":\"self-sweep acceptor not attached\"}", cors_hdrs);
        return 503;
    };

    // 2. Method gate — GET only.
    if (!std.mem.eql(u8, req.method, "GET")) {
        reactorWriteWithCors(write_buf, alloc, 405, "Method Not Allowed", "application/json",
            "{\"error\":\"method_not_allowed\",\"hint\":\"GET required\"}", cors_hdrs);
        return 405;
    }

    // 3. Bearer auth.
    const bearer = reactorBearerHex64(req) orelse {
        reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
            "{\"error\":\"bearer_invalid\"}", cors_hdrs);
        return 401;
    };
    _ = acceptor.bearer_tokens.verifyHex(bearer) catch {
        reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
            "{\"error\":\"bearer_invalid\"}", cors_hdrs);
        return 401;
    };

    // 4. Fetch all hashes owned by zero owner.
    const zero_owner: [16]u8 = [_]u8{0} ** 16;
    const cell_hashes = acceptor.cell_store.cellsByOwner(alloc, &zero_owner) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"sweep_failed\",\"hint\":\"cellsByOwner failed\"}", cors_hdrs);
        return 500;
    };
    defer alloc.free(cell_hashes);

    // 5. Build JSON cells array — iterate up to 300 cells.
    var json_buf: std.ArrayList(u8) = .{};
    defer json_buf.deinit(alloc);
    json_buf.appendSlice(alloc, "{\"cells\":[") catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"sweep_failed\",\"hint\":\"OOM building JSON\"}", cors_hdrs);
        return 500;
    };

    const max_cells: usize = 300;
    var count: usize = 0;
    var first = true;

    for (cell_hashes) |*hash| {
        if (count >= max_cells) break;

        const cell_opt = acceptor.cell_store.getCell(hash) catch continue;
        const cell = cell_opt orelse continue;

        // Check namespace prefix: cell[TYPEHASH_OFFSET..TYPEHASH_OFFSET+8]
        // must match BETTERMENT_NAMESPACE_PREFIX.
        const prefix_start = betterment_sweep_http.TYPEHASH_OFFSET;
        if (!std.mem.eql(u8, cell[prefix_start .. prefix_start + 8], &betterment_sweep_http.BETTERMENT_NAMESPACE_PREFIX)) {
            continue;
        }

        // typeHashHex: 32 bytes at TYPEHASH_OFFSET.
        var type_hash_hex: [64]u8 = undefined;
        bytesToHex(cell[betterment_sweep_http.TYPEHASH_OFFSET .. betterment_sweep_http.TYPEHASH_OFFSET + 32], &type_hash_hex);

        // cellId: the hash itself (32 bytes).
        var cell_id_hex: [64]u8 = undefined;
        bytesToHex(hash, &cell_id_hex);

        // mintedAtMs: u64 LE at TIMESTAMP_OFFSET, divide by 1_000_000.
        const ts_ns = std.mem.readInt(u64, cell[betterment_sweep_http.TIMESTAMP_OFFSET..][0..8], .little);
        const ts_ms: u64 = ts_ns / 1_000_000;

        // Payload: cell[HEADER_BYTES..1024], trimmed of trailing NUL bytes.
        const payload_full = cell[betterment_sweep_http.HEADER_BYTES..betterment_sweep_http.CELL_BYTES];
        var payload_end: usize = payload_full.len;
        while (payload_end > 0 and payload_full[payload_end - 1] == 0) {
            payload_end -= 1;
        }
        const payload_slice = if (payload_end > 0) payload_full[0..payload_end] else "{}";

        if (!first) {
            json_buf.append(alloc, ',') catch continue;
        }
        first = false;

        // Embed payload as a raw JSON value (not a quoted string).
        json_buf.writer(alloc).print(
            "{{\"typeHashHex\":\"{s}\",\"cellId\":\"{s}\",\"mintedAtMs\":{d},\"payload\":{s}}}",
            .{ &type_hash_hex, &cell_id_hex, ts_ms, payload_slice },
        ) catch continue;

        count += 1;
    }

    json_buf.appendSlice(alloc, "]}") catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"sweep_failed\",\"hint\":\"OOM closing JSON\"}", cors_hdrs);
        return 500;
    };

    // 6. Spawn Bun subprocess, write JSON to stdin, read stdout.
    var child = std.process.Child.init(&.{ "bun", "run", acceptor.sweep_script }, alloc);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit;

    child.spawn() catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"sweep_failed\",\"hint\":\"bun spawn failed\"}", cors_hdrs);
        return 500;
    };

    if (child.stdin) |stdin| {
        stdin.writeAll(json_buf.items) catch {};
        stdin.close();
        child.stdin = null;
    }

    var bun_out: std.ArrayList(u8) = .{};
    defer bun_out.deinit(alloc);

    if (child.stdout) |stdout| {
        const max_out = 512 * 1024; // 512 KB cap
        const buf = alloc.alloc(u8, max_out) catch {
            _ = child.wait() catch {};
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                "{\"error\":\"sweep_failed\",\"hint\":\"OOM reading bun stdout\"}", cors_hdrs);
            return 500;
        };
        defer alloc.free(buf);
        var total: usize = 0;
        while (true) {
            const n = stdout.read(buf[total..]) catch break;
            if (n == 0) break;
            total += n;
            if (total >= buf.len) break;
        }
        bun_out.appendSlice(alloc, buf[0..total]) catch {};
    }

    _ = child.wait() catch {};

    // 7. Return the Bun output.
    if (bun_out.items.len == 0) {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"sweep_failed\",\"hint\":\"bun returned empty output\"}", cors_hdrs);
        return 500;
    }

    reactorWriteWithCors(write_buf, alloc, 200, "OK", "application/json",
        bun_out.items, cors_hdrs);
    return 200;
}

fn bytesToHex(bytes: []const u8, out: []u8) void {
    const hex_chars = "0123456789abcdef";
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        out[i * 2] = hex_chars[(bytes[i] >> 4) & 0x0F];
        out[i * 2 + 1] = hex_chars[bytes[i] & 0x0F];
    }
}

// ─── D-LC4 — /api/v1/cell/since/<prev_hash_hex> forward-walk handler ─────────
//
// GET only. Returns every cell whose `prev_state_hash` header equals the
// given hash, concatenated as `application/x-semantos-cells`. Body length
// is N × 1024 bytes; N can be zero (returned as 200 with empty body when
// no forward children exist — that's the genesis tip).
//
// Caps response at 1 MiB (1024 cells) per request. The D-LC4 follow-up
// (this file) adds cursor pagination so clients can walk past the cap:
//
//   GET /api/v1/cell/since/<prev_hash_hex>?limit=N&after=<64hex>
//
//   - `limit` clamped to [1, MAX_CELLS_PER_SINCE_RESPONSE]; 0 → 400.
//   - `after` (optional) — strictly-after cursor; the cell whose hash equals
//     `after` is NOT included in the page. Pass the previous response's
//     `x-next-cursor` header as `?after=<hex>` to fetch the next page.
//   - `x-next-cursor: <hex>` response header is set IFF more results
//     exist under the same prev_state_hash; absent on the last page.
//   - `x-cell-count: N` continues to report the count returned (may be
//     less than `limit` when this is the last page).

const MAX_CELLS_PER_SINCE_RESPONSE: usize = 1024;

pub fn reactorHandleCellSince(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    const acceptor = server.cell_raw_acceptor orelse {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "application/json",
            "{\"error\":\"not_found\"}", cors_hdrs);
        return 404;
    };

    if (!std.mem.eql(u8, req.method, "GET") and !std.mem.eql(u8, req.method, "HEAD")) {
        reactorWriteWithCors(write_buf, alloc, 405, "Method Not Allowed", "application/json",
            "{\"error\":\"method_not_allowed\",\"hint\":\"GET required\"}", cors_hdrs);
        return 405;
    }

    const prev_hash = cell_raw_http.parseSincePath(req.path) orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"bad_request\",\"hint\":\"path must be /api/v1/cell/since/<64hex>\"}", cors_hdrs);
        return 400;
    };

    // Parse the query-string tail (after '?' in req.path). parseSincePath
    // already stripped the tail before hex-decoding; splitPathQuery gives
    // us the raw query string so parseSinceQuery can pull out limit/after.
    const path_split = cell_raw_http.splitPathQuery(req.path);
    const parsed_q = cell_raw_http.parseSinceQuery(path_split.query) catch |err| {
        switch (err) {
            error.invalid_limit => {
                reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
                    "{\"error\":\"bad_request\",\"hint\":\"limit must be a non-negative integer\"}", cors_hdrs);
                return 400;
            },
            error.invalid_after => {
                reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
                    "{\"error\":\"bad_request\",\"hint\":\"after must be 64 hex chars\"}", cors_hdrs);
                return 400;
            },
        }
    };

    // Resolve effective limit: default is MAX, explicit 0 → 400, large
    // values clamped silently (matches the existing soft-cap posture and
    // matches what task spec calls out).
    const effective_limit: usize = blk: {
        if (parsed_q.limit) |n| {
            if (n == 0) {
                reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
                    "{\"error\":\"bad_request\",\"hint\":\"limit must be >= 1\"}", cors_hdrs);
                return 400;
            }
            break :blk @min(@as(usize, n), MAX_CELLS_PER_SINCE_RESPONSE);
        }
        break :blk MAX_CELLS_PER_SINCE_RESPONSE;
    };

    const bearer = reactorBearerHex64(req) orelse {
        reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
            "{\"error\":\"bearer_invalid\"}", cors_hdrs);
        return 401;
    };
    _ = acceptor.bearer_tokens.verifyHex(bearer) catch {
        reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
            "{\"error\":\"bearer_invalid\"}", cors_hdrs);
        return 401;
    };

    // Enumerate forward children for the given prev_state_hash, optionally
    // starting strictly-after a previous cursor. cellsByPrevStateRange owns
    // the LMDB seek-and-skip-on-equal semantics — see its doc comment.
    const after_opt: ?*const [32]u8 = if (parsed_q.after) |*a| a else null;
    const range = acceptor.cell_store.cellsByPrevStateRange(
        alloc, &prev_hash, after_opt, effective_limit,
    ) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"persistence_failed\"}", cors_hdrs);
        return 500;
    };
    defer alloc.free(range.hashes);

    const n = range.hashes.len;

    // Stream concatenated cell bytes. Build the body in-memory; brain
    // doesn't support chunked responses out of this handler shape today,
    // and 1 MiB is well within the write-buf cap.
    var body = std.ArrayList(u8){};
    defer body.deinit(alloc);
    body.ensureTotalCapacity(alloc, n * cell_raw_http.CELL_BYTES) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"out_of_memory\"}", cors_hdrs);
        return 500;
    };
    for (range.hashes) |h| {
        const cell_opt = acceptor.cell_store.getCell(&h) catch {
            // Index pointed at a hash whose primary entry is missing — log
            // (drop) and continue. Doesn't fail the request because the
            // remaining children may still be useful.
            continue;
        };
        if (cell_opt) |cell| {
            body.appendSlice(alloc, cell[0..]) catch {
                reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                    "{\"error\":\"out_of_memory\"}", cors_hdrs);
                return 500;
            };
        }
    }

    // Build response. x-cell-count: count returned. x-next-cursor: hex of
    // the LAST cell in the response, IFF more pages exist — clients pass
    // that value back as `?after=<hex>`.
    var count_buf: [16]u8 = undefined;
    const count_str = std.fmt.bufPrint(&count_buf, "{d}", .{n}) catch "0";

    var cursor_hex: [64]u8 = undefined;
    const want_cursor = range.has_more and n > 0;
    if (want_cursor) {
        const last = range.hashes[n - 1];
        const hex_chars = "0123456789abcdef";
        for (last, 0..) |b, i| {
            cursor_hex[i * 2] = hex_chars[b >> 4];
            cursor_hex[i * 2 + 1] = hex_chars[b & 0x0f];
        }
    }

    var extra_slots: [12]std.http.Header = undefined;
    var extra_n: usize = 0;
    for (cors_hdrs) |h| {
        if (extra_n >= extra_slots.len) break;
        extra_slots[extra_n] = h;
        extra_n += 1;
    }
    if (extra_n < extra_slots.len) {
        extra_slots[extra_n] = .{ .name = "cache-control", .value = "no-cache" };
        extra_n += 1;
    }
    if (extra_n < extra_slots.len) {
        extra_slots[extra_n] = .{ .name = "x-cell-count", .value = count_str };
        extra_n += 1;
    }
    if (want_cursor and extra_n < extra_slots.len) {
        extra_slots[extra_n] = .{ .name = "x-next-cursor", .value = &cursor_hex };
        extra_n += 1;
    }
    reactorWriteWithCors(write_buf, alloc, 200, "OK", "application/x-semantos-cells",
        body.items, extra_slots[0..extra_n]);
    return 200;
}

// ─── T4 — /api/v1/voice-extract handler ─────────────────────────────────────
//
// Mirrors voice_extract_http.maybeHandle but writes to write_buf.  Reuses
// the acceptor module's pure helpers: parseVoiceMultipart, verifyTranscriptSignature.
// Also reuses attachments_upload_http.boundaryFromContentType (identical
// to voice_extract's private copy; the helper is already pub from T1).
//
// Per-route body cap (6 MiB) declared in ROUTE_BODY_CAPS so T0's parser
// allocates a buffer large enough for the multipart envelope.
//
// Multipart parts: audio (binary blob) + transcript (signed JSON) +
// metadata (JSON) + optional sir_candidate (Phase 2 on-device intent
// hint).  Voice scope is bound at capture time per D5 in the tracker
// (the metadata JSON's `scope` field is signed alongside the Transcript).

pub fn reactorHandleVoiceExtract(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    // 1. Method gate — POST only.
    if (!std.mem.eql(u8, req.method, "POST")) {
        reactorWriteWithCors(write_buf, alloc, 405, "Method Not Allowed", "application/json",
            "{\"error\":\"method_not_allowed\",\"hint\":\"POST required\"}", cors_hdrs);
        return 405;
    }

    // 2. Acceptor gate — 404 when voice-extract isn't enabled on this brain.
    const acceptor = server.voice_extract_acceptor orelse {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "application/json",
            "{\"error\":\"not_found\"}", cors_hdrs);
        return 404;
    };

    // 3. Bearer auth.
    const bearer = reactorBearerHex64(req) orelse {
        reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
            "{\"error\":\"bearer_invalid\"}", cors_hdrs);
        return 401;
    };
    _ = acceptor.bearer_tokens.verifyHex(bearer) catch {
        reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
            "{\"error\":\"bearer_invalid\"}", cors_hdrs);
        return 401;
    };

    // 4. Content-type → boundary.  Reuse the T1 helper (identical to
    //    voice_extract's private copy).
    const ct = req.header("content-type") orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"payload_invalid_format\",\"hint\":\"missing content-type\"}", cors_hdrs);
        return 400;
    };
    const boundary = attachments_upload_http.boundaryFromContentType(ct) orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"payload_invalid_format\",\"hint\":\"missing multipart boundary\"}", cors_hdrs);
        return 400;
    };

    // 5. Body already heap-buffered by T0.  Parse multipart parts.
    var parts = voice_extract_http.parseVoiceMultipart(alloc, req.body, boundary) catch |err| switch (err) {
        voice_extract_http.Error.boundary_missing,
        voice_extract_http.Error.payload_invalid_format,
        => {
            reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
                "{\"error\":\"payload_invalid_format\"}", cors_hdrs);
            return 400;
        },
        voice_extract_http.Error.out_of_memory => {
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                "{\"error\":\"out_of_memory\"}", cors_hdrs);
            return 500;
        },
        else => {
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                "{\"error\":\"multipart_parse_failed\"}", cors_hdrs);
            return 500;
        },
    };
    defer parts.deinit(alloc);

    const audio_bytes = parts.audio orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"payload_invalid_format\",\"hint\":\"missing audio part\"}", cors_hdrs);
        return 400;
    };
    const transcript_json = parts.transcript orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"payload_invalid_format\",\"hint\":\"missing transcript part\"}", cors_hdrs);
        return 400;
    };
    const metadata_json = parts.metadata orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"payload_invalid_format\",\"hint\":\"missing metadata part\"}", cors_hdrs);
        return 400;
    };

    if (audio_bytes.len > acceptor.max_audio_bytes) {
        reactorWriteWithCors(write_buf, alloc, 413, "Payload Too Large", "application/json",
            "{\"error\":\"too_large\"}", cors_hdrs);
        return 413;
    }

    // 6. Verify the signed Transcript (proves the dictation came from
    //    a device cert authorized to mutate the bound scope).
    var verify = voice_extract_http.verifyTranscriptSignature(alloc, acceptor.certs, transcript_json) catch |err| switch (err) {
        voice_extract_http.VerifyError.payload_invalid_format => {
            reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
                "{\"error\":\"payload_invalid_format\",\"hint\":\"transcript JSON malformed\"}", cors_hdrs);
            return 400;
        },
        voice_extract_http.VerifyError.cert_unknown => {
            reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
                "{\"error\":\"cert_unknown\"}", cors_hdrs);
            return 401;
        },
        voice_extract_http.VerifyError.signature_invalid => {
            reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
                "{\"error\":\"signature_invalid\"}", cors_hdrs);
            return 401;
        },
        voice_extract_http.VerifyError.out_of_memory => {
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                "{\"error\":\"out_of_memory\"}", cors_hdrs);
            return 500;
        },
    };
    defer verify.deinit(alloc);

    // 7. Best-effort persist audio blob into the content-addressable store.
    //    Phase 1 keeps this opt-in; failure here doesn't abort the request.
    if (acceptor.blobs) |blobs| {
        var audio_hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(audio_bytes, &audio_hash, .{});
        var audio_hash_hex: [64]u8 = undefined;
        bkds.hexEncode(&audio_hash, &audio_hash_hex);
        blobs.write(&audio_hash_hex, audio_bytes) catch {};
    }

    // 8. Run the intent pipeline shell-out (bun subprocess in production,
    //    stub in tests).  IntentResult JSON passes straight through to the
    //    client.
    const intent_result = acceptor.shell.run(
        alloc,
        transcript_json,
        metadata_json,
        parts.sir_candidate,
    ) catch |err| switch (err) {
        voice_extract_http.ShellError.bun_unavailable => {
            reactorWriteWithCors(write_buf, alloc, 503, "Service Unavailable", "application/json",
                "{\"error\":\"bun_unavailable\"}", cors_hdrs);
            return 503;
        },
        voice_extract_http.ShellError.pipeline_failed => {
            reactorWriteWithCors(write_buf, alloc, 422, "Unprocessable Entity", "application/json",
                "{\"error\":\"pipeline_failed\"}", cors_hdrs);
            return 422;
        },
        voice_extract_http.ShellError.out_of_memory => {
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                "{\"error\":\"out_of_memory\"}", cors_hdrs);
            return 500;
        },
    };
    defer alloc.free(intent_result);

    reactorWriteWithCors(write_buf, alloc, 200, "OK", "application/json", intent_result, cors_hdrs);
    return 200;
}

// Betterment OCR — /api/v1/image-extract.  Multipart POST of 1..MAX_PAGES
// `image` parts (+ optional metadata).  Bearer-only (release photos are not
// device-signed this pass).  Shells out to bun (image-extract.ts → Claude
// vision); the ExtractResult JSON (turns + rawText) passes straight through.
pub fn reactorHandleImageExtract(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    // 1. Method gate — POST only.
    if (!std.mem.eql(u8, req.method, "POST")) {
        reactorWriteWithCors(write_buf, alloc, 405, "Method Not Allowed", "application/json",
            "{\"error\":\"method_not_allowed\",\"hint\":\"POST required\"}", cors_hdrs);
        return 405;
    }

    // 2. Acceptor gate — 404 when image-extract isn't enabled on this brain.
    const acceptor = server.image_extract_acceptor orelse {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "application/json",
            "{\"error\":\"not_found\"}", cors_hdrs);
        return 404;
    };

    // 3. Bearer auth.
    const bearer = reactorBearerHex64(req) orelse {
        reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
            "{\"error\":\"bearer_invalid\"}", cors_hdrs);
        return 401;
    };
    _ = acceptor.bearer_tokens.verifyHex(bearer) catch {
        reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
            "{\"error\":\"bearer_invalid\"}", cors_hdrs);
        return 401;
    };

    // 4. Content-type → boundary (reuse the shared helper).
    const ct = req.header("content-type") orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"payload_invalid_format\",\"hint\":\"missing content-type\"}", cors_hdrs);
        return 400;
    };
    const boundary = attachments_upload_http.boundaryFromContentType(ct) orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"payload_invalid_format\",\"hint\":\"missing multipart boundary\"}", cors_hdrs);
        return 400;
    };

    // 5. Body already heap-buffered by T0.  Parse the image parts.
    var parts = image_extract_http.parseImageMultipart(alloc, req.body, boundary) catch |err| switch (err) {
        image_extract_http.Error.boundary_missing,
        image_extract_http.Error.payload_invalid_format,
        => {
            reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
                "{\"error\":\"payload_invalid_format\"}", cors_hdrs);
            return 400;
        },
        else => {
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                "{\"error\":\"out_of_memory\"}", cors_hdrs);
            return 500;
        },
    };
    defer parts.deinit(alloc);

    if (parts.images.items.len == 0) {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"payload_invalid_format\",\"hint\":\"no image parts\"}", cors_hdrs);
        return 400;
    }
    if (parts.images.items.len > acceptor.max_pages) {
        reactorWriteWithCors(write_buf, alloc, 413, "Payload Too Large", "application/json",
            "{\"error\":\"too_large\",\"hint\":\"too many pages\"}", cors_hdrs);
        return 413;
    }
    for (parts.images.items) |img| {
        if (img.bytes.len > acceptor.max_image_bytes) {
            reactorWriteWithCors(write_buf, alloc, 413, "Payload Too Large", "application/json",
                "{\"error\":\"too_large\"}", cors_hdrs);
            return 413;
        }
    }

    // 6. Run the OCR pipeline shell-out.  ExtractResult JSON passes through.
    //    api_key/model are optional BYOK overrides (per-request, never persisted).
    const extract_result = acceptor.shell.run(
        alloc,
        parts.images.items,
        parts.metadata,
        parts.api_key,
        parts.model,
    ) catch |err| switch (err) {
        image_extract_http.ShellError.bun_unavailable => {
            reactorWriteWithCors(write_buf, alloc, 503, "Service Unavailable", "application/json",
                "{\"error\":\"bun_unavailable\"}", cors_hdrs);
            return 503;
        },
        image_extract_http.ShellError.pipeline_failed => {
            reactorWriteWithCors(write_buf, alloc, 422, "Unprocessable Entity", "application/json",
                "{\"error\":\"pipeline_failed\"}", cors_hdrs);
            return 422;
        },
        image_extract_http.ShellError.out_of_memory => {
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                "{\"error\":\"out_of_memory\"}", cors_hdrs);
            return 500;
        },
    };
    defer alloc.free(extract_result);

    reactorWriteWithCors(write_buf, alloc, 200, "OK", "application/json", extract_result, cors_hdrs);
    return 200;
}

// Betterment voice — /api/v1/audio-extract. Multipart POST of one `audio` part
// (16kHz mono WAV) + optional metadata. Bearer-only. Shells to bun
// (audio-extract.ts → whisper.cpp); the ExtractResult JSON passes straight through.
pub fn reactorHandleAudioExtract(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    if (!std.mem.eql(u8, req.method, "POST")) {
        reactorWriteWithCors(write_buf, alloc, 405, "Method Not Allowed", "application/json",
            "{\"error\":\"method_not_allowed\",\"hint\":\"POST required\"}", cors_hdrs);
        return 405;
    }

    const acceptor = server.audio_extract_acceptor orelse {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "application/json",
            "{\"error\":\"not_found\"}", cors_hdrs);
        return 404;
    };

    const bearer = reactorBearerHex64(req) orelse {
        reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
            "{\"error\":\"bearer_invalid\"}", cors_hdrs);
        return 401;
    };
    _ = acceptor.bearer_tokens.verifyHex(bearer) catch {
        reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
            "{\"error\":\"bearer_invalid\"}", cors_hdrs);
        return 401;
    };

    const ct = req.header("content-type") orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"payload_invalid_format\",\"hint\":\"missing content-type\"}", cors_hdrs);
        return 400;
    };
    const boundary = attachments_upload_http.boundaryFromContentType(ct) orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"payload_invalid_format\",\"hint\":\"missing multipart boundary\"}", cors_hdrs);
        return 400;
    };

    var parts = audio_extract_http.parseAudioMultipart(alloc, req.body, boundary) catch |err| switch (err) {
        audio_extract_http.Error.boundary_missing,
        audio_extract_http.Error.payload_invalid_format,
        => {
            reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
                "{\"error\":\"payload_invalid_format\"}", cors_hdrs);
            return 400;
        },
        else => {
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                "{\"error\":\"out_of_memory\"}", cors_hdrs);
            return 500;
        },
    };
    defer parts.deinit(alloc);

    const audio_bytes = parts.audio orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"payload_invalid_format\",\"hint\":\"missing audio part\"}", cors_hdrs);
        return 400;
    };
    if (audio_bytes.len > acceptor.max_audio_bytes) {
        reactorWriteWithCors(write_buf, alloc, 413, "Payload Too Large", "application/json",
            "{\"error\":\"too_large\"}", cors_hdrs);
        return 413;
    }

    const extract_result = acceptor.shell.run(alloc, audio_bytes, parts.metadata) catch |err| switch (err) {
        audio_extract_http.ShellError.bun_unavailable => {
            reactorWriteWithCors(write_buf, alloc, 503, "Service Unavailable", "application/json",
                "{\"error\":\"bun_unavailable\"}", cors_hdrs);
            return 503;
        },
        audio_extract_http.ShellError.pipeline_failed => {
            reactorWriteWithCors(write_buf, alloc, 422, "Unprocessable Entity", "application/json",
                "{\"error\":\"pipeline_failed\"}", cors_hdrs);
            return 422;
        },
        audio_extract_http.ShellError.out_of_memory => {
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
                "{\"error\":\"out_of_memory\"}", cors_hdrs);
            return 500;
        },
    };
    defer alloc.free(extract_result);

    reactorWriteWithCors(write_buf, alloc, 200, "OK", "application/json", extract_result, cors_hdrs);
    return 200;
}

// ─── T3 — /api/v1/events WSS upgrade + frame handler ───────────────────────
//
// Mirrors events_stream_handler.tryUpgrade + serveSession but writes
// to write_buf and lives inside the reactor's single-threaded poll
// loop.  Cross-thread bus events arrive via eventsBusCallback (defined
// near the top of this file with EventsReactorSession), which appends
// serialised WSS frames to the session's event_queue; the reactor's
// pre-tick drain (reactorTickDrain) and this frame handler both call
// drainInto to flush the queue into write_buf.

/// Reactor-shape WSS upgrade for `/api/v1/events`.  Validates the
/// upgrade request, writes the 101 to write_buf, subscribes to the
/// OddjobzEventBus, and populates ctx.events_session.
///
/// Returns `.upgraded_to_wss` on success so ConnectionState switches
/// the connection's phase to WSS.  Returns `.close_after_drain` with
/// an HTTP 4xx written for any rejection (missing hat, bad method, no
/// upgrade headers, bus not attached).
fn reactorEventsUpgrade(
    server: *SiteServer,
    ctx: *ReactorCtx,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) connection_state_mod.HttpDispatchResult {
    // 1. Method gate — GET only.
    if (!std.mem.eql(u8, req.method, "GET")) {
        reactorWriteWithCors(write_buf, alloc, 405, "Method Not Allowed", "application/json",
            "{\"error\":\"GET required for WS upgrade\"}", cors_hdrs);
        server.logRequest(methodToEnum(req.method), req.path, 405) catch {};
        return .close_after_drain;
    }

    // 2. Bus gate — endpoint disabled when the operator didn't attach
    //    an OddjobzEventBus to the SiteServer.
    const bus = server.oddjobz_event_bus orelse {
        reactorWriteWithCors(write_buf, alloc, 503, "Service Unavailable", "application/json",
            "{\"error\":\"events stream backend not enabled in this serve mode\"}", cors_hdrs);
        server.logRequest(methodToEnum(req.method), req.path, 503) catch {};
        return .close_after_drain;
    };

    // 3. Parse `hat` (required) + optional `resume_after` from the query.
    const hat_val = events_stream_handler.queryParam(req.query, "hat") orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"missing required query param: hat\"}", cors_hdrs);
        server.logRequest(methodToEnum(req.method), req.path, 400) catch {};
        return .close_after_drain;
    };

    const sess = ctx.events_session orelse {
        // Should never happen — reactorMakeCtx pre-allocates the session.
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"internal: events session not allocated\"}", cors_hdrs);
        server.logRequest(methodToEnum(req.method), req.path, 500) catch {};
        return .close_after_drain;
    };

    if (hat_val.len == 0 or hat_val.len >= sess.hat_buf.len) {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"hat param too long or empty\"}", cors_hdrs);
        server.logRequest(methodToEnum(req.method), req.path, 400) catch {};
        return .close_after_drain;
    }
    @memcpy(sess.hat_buf[0..hat_val.len], hat_val);
    sess.hat_len = hat_val.len;

    var resume_after_buf: [16]u8 = undefined;
    var has_resume_after = false;
    if (events_stream_handler.queryParam(req.query, "resume_after")) |ra| {
        if (ra.len == 16) {
            @memcpy(&resume_after_buf, ra[0..16]);
            has_resume_after = true;
        }
    }

    // 4. Validate WebSocket upgrade headers.
    const upgrade_hdr = req.header("upgrade") orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"missing Upgrade: websocket\"}", cors_hdrs);
        server.logRequest(methodToEnum(req.method), req.path, 400) catch {};
        return .close_after_drain;
    };
    if (!std.ascii.eqlIgnoreCase(std.mem.trim(u8, upgrade_hdr, " \t"), "websocket")) {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"Upgrade must be websocket\"}", cors_hdrs);
        server.logRequest(methodToEnum(req.method), req.path, 400) catch {};
        return .close_after_drain;
    }
    const conn_hdr = req.header("connection") orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"missing Connection: Upgrade\"}", cors_hdrs);
        server.logRequest(methodToEnum(req.method), req.path, 400) catch {};
        return .close_after_drain;
    };
    if (!events_stream_handler.asciiContainsCaseInsensitive(conn_hdr, "Upgrade")) {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"Connection must contain Upgrade\"}", cors_hdrs);
        server.logRequest(methodToEnum(req.method), req.path, 400) catch {};
        return .close_after_drain;
    }
    const ws_key = req.header("sec-websocket-key") orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"missing Sec-WebSocket-Key\"}", cors_hdrs);
        server.logRequest(methodToEnum(req.method), req.path, 400) catch {};
        return .close_after_drain;
    };

    // 5. Write the 101 response into write_buf (no CORS headers — WS
    //    upgrades are exempt from CORS preflight per the WHATWG spec).
    var accept_b64: [28]u8 = undefined;
    wss_codec.computeAccept(ws_key, &accept_b64);
    var hdr_buf: [256]u8 = undefined;
    const resp = std.fmt.bufPrint(
        &hdr_buf,
        "HTTP/1.1 101 Switching Protocols\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Accept: {s}\r\n\r\n",
        .{&accept_b64},
    ) catch {
        return .close_after_drain;
    };
    write_buf.appendSlice(alloc, resp) catch return .close_after_drain;

    // 6. Subscribe to the bus.  state pointer is the per-connection
    //    EventsReactorSession; bus calls eventsBusCallback on every
    //    publish (publisher's thread).
    sess.bus = bus;
    sess.sub_id = bus.subscribe(.{
        .state = @ptrCast(sess),
        .callback = &eventsBusCallback,
    }) catch {
        // Subscribe failure — log + close the session.
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"subscribe failed\"}", cors_hdrs);
        server.logRequest(methodToEnum(req.method), req.path, 500) catch {};
        return .close_after_drain;
    };

    // 7. Optional replay from ring buffer.  fetchSince returns an
    //    owned slice of JobEvent; we serialize each into the session
    //    queue under the queue mutex.  Hat filter applied here too.
    if (has_resume_after) {
        if (bus.fetchSince(alloc, &resume_after_buf, 512)) |replayed| {
            defer alloc.free(replayed);
            sess.event_mu.lock();
            defer sess.event_mu.unlock();
            for (replayed) |ev| {
                if (!std.mem.eql(u8, ev.hat_id, sess.hat())) continue;
                var json_buf: std.ArrayList(u8) = .{};
                defer json_buf.deinit(alloc);
                events_stream_handler.serializeEvent(alloc, &json_buf, ev) catch continue;
                reactorWriteFrameInto(&sess.event_queue, alloc, .text, json_buf.items) catch continue;
            }
        } else |_| {
            // Best-effort replay; missing resume_after is not fatal.
        }
    }

    // 8. Mark the connection as an events session.  Subsequent WSS
    //    frames flow through reactorDispatchWss's events branch.
    ctx.kind = .events;
    server.logRequest(.GET, "/api/v1/events [101]", 101) catch {};
    return .upgraded_to_wss;
}

/// Reactor-shape events WSS frame handler.  Drains any pending bus
/// events first (so the response includes everything that arrived
/// since the last tick), then processes the incoming frame.
fn reactorEventsHandleFrame(
    sess: *EventsReactorSession,
    bus: *oddjobz_event_bus_mod.OddjobzEventBus,
    frame: wss_codec.Frame,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
) connection_state_mod.WssDispatchResult {
    // Drain any queued events first.
    sess.drainInto(write_buf, alloc);

    switch (frame.opcode) {
        .close => {
            reactorWriteCloseHelper(write_buf, alloc, 1000, "bye");
            return .close_after_drain;
        },
        .ping => {
            reactorWriteFrameInto(write_buf, alloc, .pong, frame.payload) catch {};
            return .keep_open;
        },
        .pong => return .keep_open,
        .text => {
            // Only resume_after triggers a replay.  ack frames are
            // intentionally no-op (the connection just stays open).
            if (std.mem.indexOf(u8, frame.payload, "\"resume_after\"") != null) {
                var eid_buf: [16]u8 = undefined;
                if (events_stream_handler.extractEventId(frame.payload, "resume_after", &eid_buf)) {
                    if (bus.fetchSince(alloc, &eid_buf, 512)) |replayed| {
                        defer alloc.free(replayed);
                        sess.event_mu.lock();
                        defer sess.event_mu.unlock();
                        for (replayed) |ev| {
                            if (!std.mem.eql(u8, ev.hat_id, sess.hat())) continue;
                            var json_buf: std.ArrayList(u8) = .{};
                            defer json_buf.deinit(alloc);
                            events_stream_handler.serializeEvent(alloc, &json_buf, ev) catch continue;
                            reactorWriteFrameInto(&sess.event_queue, alloc, .text, json_buf.items) catch continue;
                        }
                    } else |_| {}
                }
                // Drain again so the replay frames go out this tick.
                sess.drainInto(write_buf, alloc);
            }
            return .keep_open;
        },
        else => return .keep_open,
    }
}

/// Local helper for emitting a WSS close frame to write_buf.  The
/// existing reactorWriteClose lives in wss_wallet/reactor.zig (per-
/// session); we replicate the 4-byte close payload + frame envelope
/// here so the events handler doesn't reach across module boundaries.
fn reactorWriteCloseHelper(
    out: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    code: u16,
    reason: []const u8,
) void {
    var payload_buf: [128]u8 = undefined;
    if (2 + reason.len > payload_buf.len) return;
    std.mem.writeInt(u16, payload_buf[0..2], code, .big);
    @memcpy(payload_buf[2..][0..reason.len], reason);
    reactorWriteFrameInto(out, allocator, .close, payload_buf[0 .. 2 + reason.len]) catch {};
}

// ─── Unified WSS RPC channel — /api/v1/rpc upgrade + frame dispatch ─────────
//
// One multiplexed socket carries many logical methods (cell.query, repl.eval,
// cells.mint, subscribe, conversation.*, voice.submit) routed through the
// SiteServer's RpcRegistry. Auth is bound ONCE here at the upgrade; per-method
// capability checks are pure (reactorRpcCapOk) against the session snapshot.
// Every handler runs synchronously into write_buf — no self-call into the
// brain (the single-threaded-reactor deadlock guard).

/// Reactor-shape WSS upgrade for `/api/v1/rpc`. Mirrors reactorEventsUpgrade:
/// validate the upgrade, authenticate (cert/bearer) ONCE, snapshot the auth
/// onto ctx.rpc_session, write the 101, mark the connection `.rpc`.
fn reactorRpcUpgrade(
    server: *SiteServer,
    ctx: *ReactorCtx,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) connection_state_mod.HttpDispatchResult {
    // 1. Method gate — GET only.
    if (!std.mem.eql(u8, req.method, "GET")) {
        reactorWriteWithCors(write_buf, alloc, 405, "Method Not Allowed", "application/json",
            "{\"error\":\"GET required for WS upgrade\"}", cors_hdrs);
        server.logRequest(methodToEnum(req.method), req.path, 405) catch {};
        return .close_after_drain;
    }

    // 2. Registry gate — endpoint disabled when no RpcRegistry is attached.
    if (server.rpc_registry == null) {
        reactorWriteWithCors(write_buf, alloc, 503, "Service Unavailable", "application/json",
            "{\"error\":\"RPC channel not enabled in this serve mode\"}", cors_hdrs);
        server.logRequest(methodToEnum(req.method), req.path, 503) catch {};
        return .close_after_drain;
    }

    // 3. Auth gate — bound ONCE at the upgrade. Reuses the unified
    //    cert-or-bearer authorize against the query-stripped path the client
    //    signs. require_cert_auth retires the bearer fallback inside it.
    const toks = server.bearer_tokens orelse {
        reactorWriteWithCors(write_buf, alloc, 503, "Service Unavailable", "application/json",
            "{\"error\":\"auth backend not enabled in this serve mode\"}", cors_hdrs);
        server.logRequest(methodToEnum(req.method), req.path, 503) catch {};
        return .close_after_drain;
    };
    // Browsers can't set request headers on a WebSocket handshake, so accept a
    // `?bearer=<64hex>` query param as a fallback when no Authorization header
    // is present (same posture as the events/wallet endpoints). Header auth is
    // preferred on native clients. require_cert_auth still retires bearer.
    const query_bearer_ok = blk: {
        if (server.require_cert_auth) break :blk false;
        if (req.header("authorization") != null) break :blk false; // header path wins
        const qb = events_stream_handler.queryParam(req.query, "bearer") orelse break :blk false;
        if (qb.len != 64) break :blk false;
        _ = toks.verifyHex(qb) catch break :blk false;
        break :blk true;
    };
    const outcome: AuthOutcome = if (query_bearer_ok) .allow else reactorAuthorize(server, toks, req, "/api/v1/rpc");
    switch (outcome) {
        .allow => {},
        .deny_unauthorized => {
            reactorWriteWithCors(write_buf, alloc, 401, "Unauthorized", "application/json",
                "{\"error\":\"RPC upgrade requires a valid credential\"}", cors_hdrs);
            server.logRequest(methodToEnum(req.method), req.path, 401) catch {};
            return .close_after_drain;
        },
        .deny_forbidden => {
            reactorWriteWithCors(write_buf, alloc, 403, "Forbidden", "application/json",
                "{\"error\":\"credential not permitted on /api/v1/rpc\"}", cors_hdrs);
            server.logRequest(methodToEnum(req.method), req.path, 403) catch {};
            return .close_after_drain;
        },
    }

    const sess = ctx.rpc_session orelse {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"internal: rpc session not allocated\"}", cors_hdrs);
        server.logRequest(methodToEnum(req.method), req.path, 500) catch {};
        return .close_after_drain;
    };
    // M0: a valid upgrade credential is treated as operator/admin (matches the
    // brain's current bearer-implies-everything posture). When cert→cap-set
    // derivation lands, snapshot the verified cert's caps into sess.caps and
    // set is_admin only for operator certs (reactorAuthorize must surface the
    // allow_admin/allow_user distinction it currently collapses).
    sess.is_admin = true;

    // 4. Validate the WebSocket upgrade headers (same checks as events).
    const upgrade_hdr = req.header("upgrade") orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"missing Upgrade: websocket\"}", cors_hdrs);
        return .close_after_drain;
    };
    if (!std.ascii.eqlIgnoreCase(std.mem.trim(u8, upgrade_hdr, " \t"), "websocket")) {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"Upgrade must be websocket\"}", cors_hdrs);
        return .close_after_drain;
    }
    const conn_hdr = req.header("connection") orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"missing Connection: Upgrade\"}", cors_hdrs);
        return .close_after_drain;
    };
    if (!events_stream_handler.asciiContainsCaseInsensitive(conn_hdr, "Upgrade")) {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"Connection must contain Upgrade\"}", cors_hdrs);
        return .close_after_drain;
    }
    const ws_key = req.header("sec-websocket-key") orelse {
        reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
            "{\"error\":\"missing Sec-WebSocket-Key\"}", cors_hdrs);
        return .close_after_drain;
    };

    // 5. Write the 101 (WS upgrades are exempt from CORS preflight).
    var accept_b64: [28]u8 = undefined;
    wss_codec.computeAccept(ws_key, &accept_b64);
    var hdr_buf: [256]u8 = undefined;
    const resp = std.fmt.bufPrint(
        &hdr_buf,
        "HTTP/1.1 101 Switching Protocols\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Accept: {s}\r\n\r\n",
        .{&accept_b64},
    ) catch return .close_after_drain;
    write_buf.appendSlice(alloc, resp) catch return .close_after_drain;

    // 6. Mark the connection as an RPC session.
    ctx.kind = .rpc;
    server.logRequest(.GET, "/api/v1/rpc [101]", 101) catch {};
    return .upgraded_to_wss;
}

/// Per-method capability check. A method with no `required_cap` needs only a
/// valid upgrade; otherwise the session's snapshot must imply the cap (admin
/// implies everything). Pure — no I/O, no allocation.
fn reactorRpcCapOk(sess: *const RpcReactorSession, method: *const wss_rpc.RpcMethod) bool {
    const cap = method.required_cap orelse return true;
    if (sess.is_admin) return true;
    return sess.caps.contains(cap);
}

/// Dispatch one client text frame to the registry and return the response
/// frame bytes (owned by `alloc`; empty slice = no response, e.g. an ack).
/// Pure of socket/opcode concerns so it's unit-testable without a live socket.
fn reactorRpcDispatchText(
    server: *SiteServer,
    sess: *const RpcReactorSession,
    text: []const u8,
    alloc: std.mem.Allocator,
) ![]u8 {
    const registry = server.rpc_registry orelse
        return wss_rpc.encodeErr(alloc, "", "internal", "rpc registry detached");

    const frame = try wss_rpc.parseClientFrame(alloc, text);
    switch (frame) {
        .request => |r| {
            defer alloc.free(r.id);
            defer alloc.free(r.method);
            defer alloc.free(r.params);
            const method = registry.match(r.method) orelse
                return wss_rpc.encodeErr(alloc, r.id, "unknown_method", r.method);
            if (!reactorRpcCapOk(sess, method))
                return wss_rpc.encodeErr(alloc, r.id, "forbidden", method.required_cap.?);
            const result = method.handle(method.state, r.params, alloc) catch |err|
                return wss_rpc.encodeErr(alloc, r.id, "internal", @errorName(err));
            return switch (result) {
                .ok => |body| wss_rpc.encodeRes(alloc, r.id, body),
                .err => |e| wss_rpc.encodeErr(alloc, r.id, e.code, e.message),
            };
        },
        .ack => |k| {
            // Subscription acks are a no-op until the subscribe channel lands
            // (M2). Free the parsed fields; emit nothing.
            alloc.free(k.sub);
            alloc.free(k.event_id);
            return alloc.dupe(u8, "");
        },
        .unsupported => return wss_rpc.encodeErr(alloc, "", "bad_request", "unsupported frame"),
        .parse_error => return wss_rpc.encodeErr(alloc, "", "bad_request", "frame is not a JSON object"),
    }
}

/// Reactor-shape RPC WSS frame handler. Drains any queued subscription pushes
/// first, then processes the inbound frame. Text frames dispatch through the
/// registry; the response (if any) is framed back synchronously.
fn reactorRpcHandleFrame(
    server: *SiteServer,
    sess: *RpcReactorSession,
    frame: wss_codec.Frame,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
) connection_state_mod.WssDispatchResult {
    sess.drainInto(write_buf, alloc);

    switch (frame.opcode) {
        .close => {
            reactorWriteCloseHelper(write_buf, alloc, 1000, "bye");
            return .close_after_drain;
        },
        .ping => {
            reactorWriteFrameInto(write_buf, alloc, .pong, frame.payload) catch {};
            return .keep_open;
        },
        .pong => return .keep_open,
        .text => {
            const resp = reactorRpcDispatchText(server, sess, frame.payload, alloc) catch
                return .keep_open;
            defer alloc.free(resp);
            if (resp.len > 0) reactorWriteFrameInto(write_buf, alloc, .text, resp) catch {};
            return .keep_open;
        },
        else => return .keep_open,
    }
}

// ─── T2 — /api/v1/info handler ──────────────────────────────────────────────
//
// Mirrors info_http.maybeHandle but writes to write_buf.  The pure logic
// lives in info_http.handle (returns an InfoResult with body + status);
// the reactor handler just adapts the request shape and wire bytes.

/// Reactor-shape variant of info_http.maybeHandle.  GET-only;
/// bearer-gated; emits brain pin + shard-proxy + theme + hat info.
pub fn reactorHandleInfo(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    // 1. Acceptor gate — 404 when the endpoint isn't enabled (matches
    //    the wire shape of the original request.zig path).
    const acceptor = server.info_acceptor orelse {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "application/json",
            "{\"error\":\"not_found\"}", cors_hdrs);
        return 404;
    };

    // 2. Method gate — GET only.
    if (!std.mem.eql(u8, req.method, "GET")) {
        reactorWriteWithCors(write_buf, alloc, 405, "Method Not Allowed", "application/json",
            "{\"error\":\"method_not_allowed\",\"hint\":\"GET required\"}", cors_hdrs);
        return 405;
    }

    // 3. Bearer auth flows through info_http.handle (it returns 401 with
    //    the canonical {"error":"unauthorised"} body when missing/invalid).
    const bearer = reactorBearerHex64(req);
    var result = info_http.handle(acceptor, bearer) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"internal\"}", cors_hdrs);
        return 500;
    };
    defer result.deinit(alloc);

    const status_u16: u16 = @intCast(@intFromEnum(result.status));
    const status_text: []const u8 = switch (result.status) {
        .ok => "OK",
        .unauthorized => "Unauthorized",
        else => "Error",
    };
    reactorWriteWithCors(write_buf, alloc, status_u16, status_text, "application/json",
        result.body, cors_hdrs);
    return status_u16;
}

// ─── T6 — /api/v1/push-register handler ─────────────────────────────────────
//
// Mirrors push_register_http.maybeHandle but writes to write_buf. Calls
// the pure-logic acceptPost / acceptDelete directly; doesn't go through
// the std.http.Server.Request shim. Bearer-gated; same wire-shape as
// the (now-dead) request.zig path it replaces.
//
// Wire shape (per push_register_http.zig header comment):
//   POST   {cert_id, platform, token}  →  {registered: true, platform, registered_at}
//   DELETE {cert_id}                   →  {registered: false}
//   Errors: typed code in body (platform_invalid, token_empty,
//           endpoint_invalid, token_too_large, payload_invalid_format,
//           unauthorised, store_error).

/// Reactor-shape handler for POST / DELETE /api/v1/push-register.
/// Returns the HTTP status code so the caller can pass it to logRequest.
pub fn reactorHandlePushRegister(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    // 1. Method gate — POST or DELETE only.
    const is_post = std.mem.eql(u8, req.method, "POST");
    const is_delete = std.mem.eql(u8, req.method, "DELETE");
    if (!is_post and !is_delete) {
        reactorWriteWithCors(write_buf, alloc, 405, "Method Not Allowed", "application/json",
            "{\"error\":\"method_not_allowed\",\"hint\":\"POST or DELETE required\"}", cors_hdrs);
        return 405;
    }

    // 2. Acceptor gate — 404 when push-register isn't enabled on this brain.
    const acceptor = server.push_register_acceptor orelse {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "application/json",
            "{\"error\":\"not_found\"}", cors_hdrs);
        return 404;
    };

    // 3. Bearer from headers. The pure-logic path re-verifies, so we just
    //    pass the raw hex64 (or null) through.
    const bearer = reactorBearerHex64(req);

    // 4. Body bytes already heap-buffered by T0 parser (DEFAULT_BODY_CAP =
    //    256 KiB, well above push-register's MAX_BODY_BYTES = 8 KiB).
    const body = req.body;

    // 5. Dispatch to pure-logic accept{Post,Delete}.
    var result = if (is_post)
        push_register_http.acceptPost(acceptor, bearer, body) catch {
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error",
                "application/json", "{\"error\":\"out_of_memory\"}", cors_hdrs);
            return 500;
        }
    else
        push_register_http.acceptDelete(acceptor, bearer, body) catch {
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error",
                "application/json", "{\"error\":\"out_of_memory\"}", cors_hdrs);
            return 500;
        };
    defer result.deinit(alloc);

    // 6. Format response body. Success paths emit canonical JSON; error
    //    paths emit {"error":"<wireName>"} per the acceptor's typed kind.
    const status_u16: u16 = @intCast(@intFromEnum(result.kind.httpStatus()));
    const status_text: []const u8 = switch (result.kind) {
        .registered, .unregistered => "OK",
        .unauthorised => "Unauthorized",
        .token_too_large => "Payload Too Large",
        .store_error => "Internal Server Error",
        .platform_invalid,
        .token_empty,
        .endpoint_invalid,
        .payload_invalid_format,
        => "Bad Request",
    };

    if (result.kind == .registered) {
        var resp_buf: std.ArrayList(u8) = .{};
        defer resp_buf.deinit(alloc);
        resp_buf.print(
            alloc,
            "{{\"registered\":true,\"platform\":\"{s}\",\"registered_at\":\"{s}\"}}",
            .{ result.platform.wireName(), result.registered_at },
        ) catch {
            reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error",
                "application/json", "{\"error\":\"out_of_memory\"}", cors_hdrs);
            return 500;
        };
        reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
            "application/json", resp_buf.items, cors_hdrs);
        return status_u16;
    }

    if (result.kind == .unregistered) {
        reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
            "application/json", "{\"registered\":false}", cors_hdrs);
        return status_u16;
    }

    // Error path — typed wireName.
    var err_buf: std.ArrayList(u8) = .{};
    defer err_buf.deinit(alloc);
    err_buf.print(alloc, "{{\"error\":\"{s}\"}}", .{result.kind.wireName()}) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error",
            "application/json", "{\"error\":\"out_of_memory\"}", cors_hdrs);
        return 500;
    };
    reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
        "application/json", err_buf.items, cors_hdrs);
    return status_u16;
}

// C4 PR-I1 — reactorHandleConversationSend removed. POST
// /api/v1/conversation/:id/send is now served by the oddjobz cartridge's
// route-registry handler (conversationSendRouteHandler in registration.zig),
// which loads the Twilio config + std.http sender + reads the cartridge-owned
// customers store, building a per-request conversation_send_http.Acceptor.

// ─── /api/v1/identity/merge (D-OJ-conv-identity-merge-endpoint) ─────────────
//
// HTTP wrapper around identity_merge_http.callMergeScript.
// Parses the request body, pulls the bearer hex, dispatches to the bun
// subprocess and maps the typed MergeResult to an HTTP response.
pub fn reactorHandleIdentityMerge(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    // 1. Method gate — POST only.
    if (!std.mem.eql(u8, req.method, "POST")) {
        reactorWriteWithCors(write_buf, alloc, 405, "Method Not Allowed", "application/json",
            "{\"error\":\"method_not_allowed\",\"hint\":\"POST required\"}", cors_hdrs);
        return 405;
    }

    // 2. Script must be configured.
    const script = server.identity_merge_script orelse {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "application/json",
            "{\"error\":\"not_found\"}", cors_hdrs);
        return 404;
    };

    // 3. Parse request body.
    const merge_req = identity_merge_http.parseRequest(alloc, req.body) catch |err| {
        switch (err) {
            error.missing_field => {
                reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
                    "{\"error\":\"missing_field\"}", cors_hdrs);
                return 400;
            },
            error.malformed => {
                reactorWriteWithCors(write_buf, alloc, 400, "Bad Request", "application/json",
                    "{\"error\":\"malformed_body\"}", cors_hdrs);
                return 400;
            },
            error.out_of_memory => {
                reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error",
                    "application/json", "{\"error\":\"out_of_memory\"}", cors_hdrs);
                return 500;
            },
        }
    };
    defer merge_req.deinit(alloc);

    // 4. Bearer from Authorization header.
    const bearer = reactorBearerHex64(req);

    // 5. Dispatch to bun subprocess.
    var result = identity_merge_http.callMergeScript(
        alloc,
        script,
        bearer,
        merge_req,
    ) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error",
            "application/json", "{\"error\":\"script_error\"}", cors_hdrs);
        return 500;
    };
    defer result.deinit(alloc);

    // 6. Map result to HTTP response.
    const status: std.http.Status = result.kind.httpStatus();
    const status_u16: u16 = @intCast(@intFromEnum(status));
    const status_text: []const u8 = status.phrase() orelse "Error";

    switch (result.kind) {
        .merged => {
            // Build: { "ok":true, "mergeId":"...", "chain":[...] }
            var resp_buf: std.ArrayList(u8) = .{};
            defer resp_buf.deinit(alloc);
            resp_buf.print(alloc,
                "{{\"ok\":true,\"mergeId\":\"{s}\",\"chain\":{s}}}",
                .{ result.merge_id, result.chain_json },
            ) catch {
                reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error",
                    "application/json", "{\"error\":\"out_of_memory\"}", cors_hdrs);
                return 500;
            };
            reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
                "application/json", resp_buf.items, cors_hdrs);
            return status_u16;
        },
        .same_identity => {
            reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
                "application/json", "{\"error\":\"same_identity\"}", cors_hdrs);
            return status_u16;
        },
        .not_confirmed => {
            reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
                "application/json", "{\"error\":\"not_confirmed\"}", cors_hdrs);
            return status_u16;
        },
        .db_error => {
            reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
                "application/json", "{\"error\":\"db_error\"}", cors_hdrs);
            return status_u16;
        },
        .unauthorised => {
            reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
                "application/json", "{\"error\":\"unauthorized\"}", cors_hdrs);
            return status_u16;
        },
        .script_error => {
            reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
                "application/json", "{\"error\":\"script_error\"}", cors_hdrs);
            return status_u16;
        },
    }
}

// C4 PR-H3 — reactorHandleSearchContacts removed. POST /api/v1/search/contacts
// is now served by the oddjobz cartridge's route-registry handler
// (searchContactsRouteHandler in the cartridge registration.zig), which reads the
// cartridge-owned customers + sites stores + validates the bearer via the
// substrate token store handed through CartridgeDeps.

// ─── Auth-gate reactor helpers (brain-wedge Commit 8b) ─────────────────────────
//
// These functions mirror the blocking serveIdentityChallenge /
// servePaymentChallenge helpers in SiteServer but write to write_buf
// instead of std.http.Server.Request, so they can run on the single
// reactor thread without blocking.
//
// RIP-OUT-MARKER (brain-wedge Commit 8b, 2026-05-06):
//   These three functions replace the 503 stub for auth-gated routes in
//   reactorDispatchHttp.  To revert: delete this section and restore
//   the 503 stub.

/// Reactor variant of SiteServer.requestHasValidSession.
/// Reads the Cookie header from the parsed reactor HttpRequest.
pub fn reactorRequestHasValidSession(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
) bool {
    const cookie = req.header("cookie") orelse return false;
    const sess_cookie = auth_handler.extractCookie(cookie, "__semantos_session") orelse return false;
    return auth_handler.verifySessionCookie(server.config.signing_secret, sess_cookie, &server.auth_store) != null;
}

/// Reactor variant of SiteServer.serveIdentityChallenge.
///
/// Issues a fresh challenge nonce via auth_store, then writes a 401
/// response with the X-Semantos-* headers and the challenge cookie into
/// write_buf.  Returns the HTTP status code (401 on success, 500 on
/// nonce issuance failure) so the caller can pass it to logRequest.
pub fn reactorHandleIdentityRequired(
    server: *SiteServer,
    return_to: []const u8,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    const nonce = server.auth_store.issueChallenge(return_to) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "text/plain",
            "500 Internal Server Error\n", cors_hdrs);
        return 500;
    };

    // Stack buffers for dynamic header values — the write path flushes
    // synchronously so these are safe on the stack (same rationale as
    // the blocking serveIdentityChallenge).
    var nonce_buf: [64]u8 = undefined;
    const nonce_hdr = std.fmt.bufPrint(&nonce_buf, "{s}", .{nonce}) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "text/plain",
            "500 Internal Server Error\n", cors_hdrs);
        return 500;
    };

    var return_buf: [256]u8 = undefined;
    const return_hdr = std.fmt.bufPrint(&return_buf, "{s}", .{return_to}) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "text/plain",
            "500 Internal Server Error\n", cors_hdrs);
        return 500;
    };

    var cookie_buf: [128]u8 = undefined;
    const cookie_hdr = std.fmt.bufPrint(&cookie_buf,
        "__semantos_challenge={s}; HttpOnly; Path=/auth; Max-Age=300",
        .{nonce}) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "text/plain",
            "500 Internal Server Error\n", cors_hdrs);
        return 500;
    };

    // Write the status line + fixed headers into write_buf, then the
    // X-Semantos-* challenge headers, then the CORS headers, then body.
    const html_body =
        "<!doctype html><title>Sign in with Semantos</title>" ++
        "<h1>Authentication required</h1>" ++
        "<p>This page requires identity authentication. The Semantos wallet origin can complete this flow.</p>" ++
        "<p>If you came here from a JSON client, see the <code>X-Semantos-*</code> headers.</p>\n";

    var hdr_buf: [768]u8 = undefined;
    const status_line = std.fmt.bufPrint(
        &hdr_buf,
        "HTTP/1.1 401 Unauthorized\r\n" ++
            "Content-Type: text/html; charset=utf-8\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n" ++
            "x-semantos-challenge: type=identity_auth\r\n" ++
            "x-semantos-nonce: {s}\r\n" ++
            "x-semantos-return-to: {s}\r\n" ++
            "x-semantos-wallet-origin-hint: https://wallet.semantos.app\r\n" ++
            "set-cookie: {s}\r\n",
        .{ html_body.len, nonce_hdr, return_hdr, cookie_hdr },
    ) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "text/plain",
            "500 Internal Server Error\n", cors_hdrs);
        return 500;
    };
    write_buf.appendSlice(alloc, status_line) catch return 500;
    for (cors_hdrs) |h| {
        var cors_line_buf: [256]u8 = undefined;
        const cors_line = std.fmt.bufPrint(&cors_line_buf, "{s}: {s}\r\n", .{ h.name, h.value }) catch continue;
        write_buf.appendSlice(alloc, cors_line) catch return 500;
    }
    write_buf.appendSlice(alloc, "\r\n") catch return 500;
    write_buf.appendSlice(alloc, html_body) catch return 500;
    return 401;
}

/// Reactor variant of SiteServer.servePaymentChallenge.
///
/// Issues a fresh challenge nonce, then writes a 402 Payment Required
/// response with the X-Semantos-* payment challenge headers and the
/// challenge cookie into write_buf.  Returns the HTTP status code.
pub fn reactorHandlePaymentRequired(
    server: *SiteServer,
    route: *const site_config.Route,
    return_to: []const u8,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    const recipient = site_config.effectiveRecipient(server.config, route) orelse {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "text/plain",
            "500 Internal Server Error — route is payment_required but no payment_recipient configured\n",
            cors_hdrs);
        return 500;
    };

    const nonce = server.auth_store.issueChallenge(return_to) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "text/plain",
            "500 Internal Server Error\n", cors_hdrs);
        return 500;
    };

    var nonce_buf: [64]u8 = undefined;
    const nonce_hdr = std.fmt.bufPrint(&nonce_buf, "{s}", .{nonce}) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "text/plain",
            "500 Internal Server Error\n", cors_hdrs);
        return 500;
    };

    var price_buf: [32]u8 = undefined;
    const price_hdr = std.fmt.bufPrint(&price_buf, "{d}", .{route.price_sats}) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "text/plain",
            "500 Internal Server Error\n", cors_hdrs);
        return 500;
    };

    var recipient_buf: [66]u8 = undefined;
    auth_handler.hexEncode(recipient, &recipient_buf);

    var return_buf: [256]u8 = undefined;
    const return_hdr = std.fmt.bufPrint(&return_buf, "{s}", .{return_to}) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "text/plain",
            "500 Internal Server Error\n", cors_hdrs);
        return 500;
    };

    var cookie_buf: [128]u8 = undefined;
    const cookie_hdr = std.fmt.bufPrint(&cookie_buf,
        "__semantos_challenge={s}; HttpOnly; Path=/auth; Max-Age=300",
        .{nonce}) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "text/plain",
            "500 Internal Server Error\n", cors_hdrs);
        return 500;
    };

    var html_buf: [1024]u8 = undefined;
    const html = std.fmt.bufPrint(&html_buf,
        "<!doctype html><title>Payment required</title>" ++
            "<h1>Payment required</h1>" ++
            "<p>This page costs <strong>{d} sats</strong>. Send to <code>{s}</code> and complete the auth flow.</p>" ++
            "<p>If you came here from a JSON client, see the <code>X-Semantos-*</code> headers.</p>\n",
        .{ route.price_sats, &recipient_buf }) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "text/plain",
            "500 Internal Server Error\n", cors_hdrs);
        return 500;
    };

    var hdr_buf: [1024]u8 = undefined;
    const status_line = std.fmt.bufPrint(
        &hdr_buf,
        "HTTP/1.1 402 Payment Required\r\n" ++
            "Content-Type: text/html; charset=utf-8\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n" ++
            "x-semantos-challenge: type=payment\r\n" ++
            "x-semantos-nonce: {s}\r\n" ++
            "x-semantos-price-sats: {s}\r\n" ++
            "x-semantos-recipient: {s}\r\n" ++
            "x-semantos-return-to: {s}\r\n" ++
            "x-semantos-wallet-origin-hint: https://wallet.semantos.app\r\n" ++
            "set-cookie: {s}\r\n",
        .{ html.len, nonce_hdr, price_hdr, &recipient_buf, return_hdr, cookie_hdr },
    ) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "text/plain",
            "500 Internal Server Error\n", cors_hdrs);
        return 500;
    };
    write_buf.appendSlice(alloc, status_line) catch return 500;
    for (cors_hdrs) |h| {
        var cors_line_buf: [256]u8 = undefined;
        const cors_line = std.fmt.bufPrint(&cors_line_buf, "{s}: {s}\r\n", .{ h.name, h.value }) catch continue;
        write_buf.appendSlice(alloc, cors_line) catch return 500;
    }
    write_buf.appendSlice(alloc, "\r\n") catch return 500;
    write_buf.appendSlice(alloc, html) catch return 500;
    return 402;
}

// ─── END Auth-gate reactor helpers (brain-wedge Commit 8b) ─────────────────────

/// Reactor-compatible dynamic WASM handler route dispatch.  Mirrors
/// dispatchDynamic() from line ~1309 but writes to write_buf instead of
/// std.http.Server.Request.
///
/// Returns the HTTP status code so the caller can pass it to logRequest.
///
/// Failure modes (matching dispatchDynamic exactly):
///   • runner == null         → 503 "rebuild with wasmtime"
///   • findHandlerSlot == null → 503 "handler not loaded"
///   • body too large (> REQUEST_CAP already absorbed by http_parser)
///                            → body from parser is capped; passed as-is
///   • callHandlerHandle error → 500 with @errorName(err)
///   • handler success        → handler's status + body + Content-Type
pub fn reactorHandleDynamic(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    route: *const site_config.Route,
    cors_hdrs: []const std.http.Header,
) u16 {
    // Gate 1 — runner liveness.
    if (server.runner == null) {
        reactorWriteWithCors(
            write_buf, alloc, 503, "Service Unavailable", "application/json",
            "{\"error\":\"dynamic-handler runtime not enabled — rebuild brain with wasmtime support\"}",
            cors_hdrs,
        );
        return 503;
    }

    // Gate 2 — handler slot lookup.
    const slot = server.findHandlerSlot(route) orelse {
        reactorWriteWithCors(
            write_buf, alloc, 503, "Service Unavailable", "application/json",
            "{\"error\":\"dynamic handler not loaded for this route\"}",
            cors_hdrs,
        );
        return 503;
    };

    // Dispatch.  The request body was already accumulated by the http_parser
    // (capped at MAX_BODY_BYTES = 128 KiB); pass it directly.  Handlers that
    // need larger inputs must declare tighter input constraints themselves.
    const method_kind = runner_mod.methodFromHttp(methodToEnum(req.method));
    const result = runner_mod.callHandlerHandle(
        &slot.instance,
        alloc,
        method_kind,
        req.body,
    ) catch |err| {
        var msg_buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(
            &msg_buf,
            "{{\"error\":\"{s}\"}}",
            .{@errorName(err)},
        ) catch "{\"error\":\"handler error\"}";
        reactorWriteWithCors(
            write_buf, alloc, 500, "Internal Server Error", "application/json",
            msg, cors_hdrs,
        );
        return 500;
    };
    defer alloc.free(result.body);

    // Map u16 → status text for the response line.
    const status_text: []const u8 = switch (result.status) {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        409 => "Conflict",
        413 => "Payload Too Large",
        422 => "Unprocessable Entity",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        501 => "Not Implemented",
        503 => "Service Unavailable",
        else => "Unknown",
    };

    // v0.1 ABI: guess Content-Type from route path extension (handlers don't
    // yet emit their own Content-Type — mirrors dispatchDynamic behaviour).
    const ctype = guessContentType(req.path);

    // Write the response using the CORS-aware helper so dynamic routes also
    // get the correct cross-origin headers.
    //
    // Note: reactorWriteWithCors expects a fixed body slice. result.body is
    // allocated; we pass a slice view (valid until defer alloc.free runs at
    // the end of this function — fine because write_buf.appendSlice copies).
    reactorWriteWithCors(
        write_buf, alloc, result.status, status_text, ctype,
        result.body, cors_hdrs,
    );
    return result.status;
}

/// Serve a static file from a route config entry into write_buf.
/// Reads the file from disk, guesses the Content-Type, writes HTTP/1.1
/// including any CORS headers passed in cors_hdrs.
pub fn reactorServeStatic(
    server: *SiteServer,
    route: *const site_config.Route,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) !void {
    const full_path = try std.fs.path.join(alloc, &.{ server.config.content_root, route.file });
    defer alloc.free(full_path);

    const file = std.fs.cwd().openFile(full_path, .{}) catch {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "text/plain", "404 Not Found\n", cors_hdrs);
        return;
    };
    defer file.close();

    const stat = try file.stat();
    if (stat.size > 16 * 1024 * 1024) {
        reactorWriteWithCors(write_buf, alloc, 413, "Payload Too Large", "text/plain", "413 Payload Too Large\n", cors_hdrs);
        return;
    }

    const body_buf = try alloc.alloc(u8, stat.size);
    defer alloc.free(body_buf);
    const got = try file.readAll(body_buf);
    const body = body_buf[0..got];

    const ctype = guessContentType(route.file);
    // Build status line + fixed headers, then append CORS headers, then body.
    var hdr_buf: [512]u8 = undefined;
    const status_line = try std.fmt.bufPrint(
        &hdr_buf,
        "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: {s}\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n",
        .{ ctype, got },
    );
    try write_buf.appendSlice(alloc, status_line);
    for (cors_hdrs) |h| {
        var cors_line_buf: [256]u8 = undefined;
        const cors_line = std.fmt.bufPrint(&cors_line_buf, "{s}: {s}\r\n", .{ h.name, h.value }) catch continue;
        try write_buf.appendSlice(alloc, cors_line);
    }
    try write_buf.appendSlice(alloc, "\r\n");
    try write_buf.appendSlice(alloc, body);
}

/// Serve a file from a `directory` route.
///
/// Strips the route path prefix from `url_path` to get `rest`.
/// Serves `route.root/<rest>`.  Falls back to `route.root/<spa_fallback>`
/// when rest is empty (exact prefix match) or when the target file is
/// not found on disk — this is what makes Flutter/React SPA deep-links
/// work: every unknown path returns index.html so the client router can
/// parse it.
///
/// File size cap: 32 MB (larger CanvasKit .wasm files need the extra room).
pub fn reactorServeDirectory(
    _: *SiteServer,
    route: *const site_config.Route,
    url_path: []const u8,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) !void {
    // Strip route prefix.  route.path ends in '/'; url_path starts with '/'.
    const prefix_len = if (route.path.len > 0 and route.path[route.path.len - 1] == '/')
        route.path.len - 1  // leave the leading slash on rest when prefix is just "/"
    else
        route.path.len;
    const rest_raw = if (url_path.len > prefix_len) url_path[prefix_len + 1 ..] else "";

    // Build the candidate file path.
    const candidate = if (rest_raw.len == 0)
        try std.fs.path.join(alloc, &.{ route.root, route.spa_fallback })
    else
        try std.fs.path.join(alloc, &.{ route.root, rest_raw });
    defer alloc.free(candidate);

    const file = std.fs.cwd().openFile(candidate, .{}) catch |e| blk: {
        // File not found, or the path resolves to a directory (e.g. the URL
        // has a trailing slash like /app/assets/) → serve the SPA fallback so
        // the client-side router handles it.  IsDir is treated identically to
        // FileNotFound here — we never serve directory listings.
        if (e == error.FileNotFound or e == error.NotDir or e == error.IsDir) {
            const fallback = try std.fs.path.join(alloc, &.{ route.root, route.spa_fallback });
            defer alloc.free(fallback);
            const fb = std.fs.cwd().openFile(fallback, .{}) catch {
                reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "text/plain",
                    "404 Not Found\n", cors_hdrs);
                return;
            };
            break :blk fb;
        }
        return e;
    };
    defer file.close();

    const stat = try file.stat();
    if (stat.size > 32 * 1024 * 1024) {
        reactorWriteWithCors(write_buf, alloc, 413, "Payload Too Large", "text/plain",
            "413 Payload Too Large\n", cors_hdrs);
        return;
    }

    const body_buf = try alloc.alloc(u8, stat.size);
    defer alloc.free(body_buf);
    const got = try file.readAll(body_buf);
    const body = body_buf[0..got];

    const ctype = guessContentType(if (rest_raw.len == 0) route.spa_fallback else rest_raw);
    var hdr_buf: [512]u8 = undefined;
    const status_line = try std.fmt.bufPrint(
        &hdr_buf,
        "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: {s}\r\n" ++
            "Content-Length: {d}\r\n" ++
            "Connection: close\r\n",
        .{ ctype, got },
    );
    try write_buf.appendSlice(alloc, status_line);
    for (cors_hdrs) |h| {
        var cors_line_buf: [256]u8 = undefined;
        const cors_line = std.fmt.bufPrint(&cors_line_buf, "{s}: {s}\r\n", .{ h.name, h.value }) catch continue;
        try write_buf.appendSlice(alloc, cors_line);
    }
    try write_buf.appendSlice(alloc, "\r\n");
    try write_buf.appendSlice(alloc, body);
}

// ─── /api/v1/messages (D-network-messagebox-first-class) ───────────────────
//
// Delegates to messagebox_http.accept which routes internally by method+path:
//   POST /api/v1/messages/send   → store BRC-77/78 envelope for recipient
//   GET  /api/v1/messages/list   → list pending envelopes for recipient
//   POST /api/v1/messages/ack    → acknowledge + delete a message
// The acceptor is optional; absent → 404.
pub fn reactorHandleMessagebox(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    const acceptor = server.messagebox_acceptor orelse {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "application/json",
            "{\"error\":\"not_found\"}", cors_hdrs);
        return 404;
    };

    const bearer = reactorBearerHex64(req);

    var result = messagebox_http.accept(acceptor, req.method, req.path, req.query, bearer, req.body) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error",
            "application/json", "{\"error\":\"out_of_memory\"}", cors_hdrs);
        return 500;
    };
    defer result.deinit(alloc);

    const status_u16 = result.kind.httpStatus();
    const status_text: []const u8 = switch (result.kind) {
        .ok => "OK",
        .created => "Created",
        .no_content => "No Content",
        .bad_request => "Bad Request",
        .unauthorised => "Unauthorized",
        .not_found => "Not Found",
        .method_not_allowed => "Method Not Allowed",
        .internal_error => "Internal Server Error",
    };

    if (result.body.len > 0) {
        reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
            "application/json", result.body, cors_hdrs);
    } else {
        reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
            "application/json", "", cors_hdrs);
    }
    return status_u16;
}

// ─── /api/v1/contacts (D-brain-contacts-api, 2026-05-24) ────────────────────
//
// Delegates to contacts_http.accept which routes internally by method + path.
// The acceptor is optional; absent → 404.
pub fn reactorHandleContacts(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    const acceptor = server.contacts_acceptor orelse {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "application/json",
            "{\"error\":\"not_found\"}", cors_hdrs);
        return 404;
    };

    const bearer = reactorBearerHex64(req);

    var result = contacts_http.accept(acceptor, req.method, req.path, bearer, req.body) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error",
            "application/json", "{\"error\":\"out_of_memory\"}", cors_hdrs);
        return 500;
    };
    defer result.deinit(alloc);

    const status_u16 = result.kind.httpStatus();
    const status_text: []const u8 = switch (result.kind) {
        .ok => "OK",
        .created => "Created",
        .no_content => "No Content",
        .bad_request => "Bad Request",
        .unauthorised => "Unauthorized",
        .not_found => "Not Found",
        .method_not_allowed => "Method Not Allowed",
        .conflict => "Conflict",
        .internal_error => "Internal Server Error",
    };

    if (result.body.len > 0) {
        reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
            "application/json", result.body, cors_hdrs);
    } else {
        reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
            "application/json", "", cors_hdrs);
    }
    return status_u16;
}

// ─── /api/v1/intent (D-brain-intent-classifier-api) ──────────────────────────
//
// Delegates to intent_http.accept which routes internally by method + path.
// The acceptor is optional; absent → 404.
pub fn reactorHandleIntent(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    const acceptor = server.intent_acceptor orelse {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "application/json",
            "{\"error\":\"not_found\"}", cors_hdrs);
        return 404;
    };

    const bearer = reactorBearerHex64(req);

    var result = intent_http.accept(acceptor, req.method, req.path, bearer, req.body) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error",
            "application/json", "{\"error\":\"out_of_memory\"}", cors_hdrs);
        return 500;
    };
    defer result.deinit(alloc);

    const status_u16 = result.kind.httpStatus();
    const status_text: []const u8 = switch (result.kind) {
        .ok => "OK",
        .created => "Created",
        .no_content => "No Content",
        .bad_request => "Bad Request",
        .unauthorised => "Unauthorized",
        .not_found => "Not Found",
        .method_not_allowed => "Method Not Allowed",
        .internal_error => "Internal Server Error",
    };

    if (result.body.len > 0) {
        reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
            "application/json", result.body, cors_hdrs);
    } else {
        reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
            "application/json", "", cors_hdrs);
    }
    return status_u16;
}

// ─── /api/v1/identity/* (D-brain-identity-store-api) ───────────────────────
//
// Delegates to identity_http.accept which routes internally by method + path.
// The acceptor is optional; absent → 404.
// Note: /api/v1/identity/merge is NOT routed here — it is handled earlier
// by the dedicated section 8g exact-match, which always takes precedence.
pub fn reactorHandleIdentityStore(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    const acceptor = server.identity_acceptor orelse {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "application/json",
            "{\"error\":\"not_found\"}", cors_hdrs);
        return 404;
    };

    const bearer = reactorBearerHex64(req);

    var result = identity_http.accept(acceptor, req.method, req.path, bearer, req.body) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error",
            "application/json", "{\"error\":\"out_of_memory\"}", cors_hdrs);
        return 500;
    };
    defer result.deinit(alloc);

    const status_u16 = result.kind.httpStatus();
    const status_text: []const u8 = switch (result.kind) {
        .ok => "OK",
        .no_content => "No Content",
        .bad_request => "Bad Request",
        .unauthorised => "Unauthorized",
        .not_found => "Not Found",
        .method_not_allowed => "Method Not Allowed",
        .internal_error => "Internal Server Error",
    };

    if (result.body.len > 0) {
        reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
            "application/json", result.body, cors_hdrs);
    } else {
        reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
            "application/json", "", cors_hdrs);
    }
    return status_u16;
}

// ─── /api/v1/objects (D-brain-loom-store-api, 2026-05-24) ──────────────────
pub fn reactorHandleLoomStore(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    const acceptor = server.loom_store_acceptor orelse {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "application/json",
            "{\"error\":\"loom store not available\"}", cors_hdrs);
        return 404;
    };
    const bearer = reactorBearerHex64(req);
    var result = loom_store_http.accept(acceptor, req.method, req.path, bearer, req.body) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error", "application/json",
            "{\"error\":\"internal error\"}", cors_hdrs);
        return 500;
    };
    defer result.deinit(alloc);
    const status_u16 = result.kind.httpStatus();
    const status_text: []const u8 = switch (result.kind) {
        .ok => "OK",
        .bad_request => "Bad Request",
        .unauthorised => "Unauthorized",
        .not_found => "Not Found",
        .method_not_allowed => "Method Not Allowed",
        .internal_error => "Internal Server Error",
    };
    if (result.body.len > 0) {
        reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
            "application/json", result.body, cors_hdrs);
    } else {
        reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
            "application/json", "", cors_hdrs);
    }
    return status_u16;
}

pub fn reactorHandleFlow(
    server: *SiteServer,
    req: *const http_parser_mod.HttpRequest,
    write_buf: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    cors_hdrs: []const std.http.Header,
) u16 {
    const acceptor = server.flow_acceptor orelse {
        reactorWriteWithCors(write_buf, alloc, 404, "Not Found", "application/json",
            "{\"error\":\"not_found\"}", cors_hdrs);
        return 404;
    };
    const bearer = reactorBearerHex64(req);
    var result = flow_http.accept(acceptor, req.method, req.path, bearer, req.body) catch {
        reactorWriteWithCors(write_buf, alloc, 500, "Internal Server Error",
            "application/json", "{\"error\":\"out_of_memory\"}", cors_hdrs);
        return 500;
    };
    defer result.deinit(alloc);
    const status_u16 = result.kind.httpStatus();
    const status_text: []const u8 = switch (result.kind) {
        .ok => "OK",
        .created => "Created",
        .bad_request => "Bad Request",
        .unauthorised => "Unauthorized",
        .not_found => "Not Found",
        .method_not_allowed => "Method Not Allowed",
        .internal_error => "Internal Server Error",
    };
    reactorWriteWithCors(write_buf, alloc, status_u16, status_text,
        "application/json", result.body, cors_hdrs);
    return status_u16;
}

/// Map a method string to std.http.Method for logRequest() compatibility.
/// Falls back to .GET for unrecognised methods (access log still records
/// the exact method via the path string in practice).
pub fn methodToEnum(method: []const u8) std.http.Method {
    if (std.mem.eql(u8, method, "GET")) return .GET;
    if (std.mem.eql(u8, method, "POST")) return .POST;
    if (std.mem.eql(u8, method, "PUT")) return .PUT;
    if (std.mem.eql(u8, method, "DELETE")) return .DELETE;
    if (std.mem.eql(u8, method, "HEAD")) return .HEAD;
    if (std.mem.eql(u8, method, "OPTIONS")) return .OPTIONS;
    if (std.mem.eql(u8, method, "PATCH")) return .PATCH;
    return .GET;
}

// C4 PR-I2 — reactorHandleTwilioInbound removed. POST /api/v1/twilio/inbound is
// now served by the oddjobz cartridge's route-registry handler
// (twilioInboundRouteHandler in registration.zig), reading the cartridge-owned
// customers + jobs stores + exec'ing the cartridge-shipped intake script.

// RIP-OUT-MARKER (brain-wedge B-pragmatic, 2026-05-07): end of reactor section.

```
