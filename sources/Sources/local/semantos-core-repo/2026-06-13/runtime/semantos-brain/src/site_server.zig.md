---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/site_server.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.215990+00:00
---

# runtime/semantos-brain/src/site_server.zig

```zig
// Phase WSITE2 — Static + dynamic content serving.
//
// Reference: docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md §3 (WSITE2).
//
// Listens on a TCP port, parses HTTP requests via std.http.Server, routes
// each one to a handler per the parsed `SiteConfig`. Static handler reads
// the file from disk and writes it back. Dynamic / auth-gated routes are
// stubbed at v0.1 to return 501 Not Implemented with a pointer to the
// WSITE2.5 / WSITE3 work.
//
// Scope decisions for v0.1:
//
//   • HTTP only.  TLS termination is the operator's responsibility (run
//     Caddy in front of `:8080`); built-in TLS lands when `std.crypto.tls`
//     stabilises further.
//
//   • Single-threaded request loop.  Each connection is handled to
//     completion before accept()ing the next.  Fine for personal /
//     low-traffic sovereign nodes (the vast majority of v0.1 deployments).
//     Multi-connection threading is operator infra (run multiple brain
//     processes behind a load balancer) and lands in WSITE2.5+ if
//     warranted.
//
//   • No request body parsing yet.  Static GETs only — dynamic POSTs
//     wait for the WSITE2.5 dynamic-handler dispatch.
//
//   • Access log: simple JSON-line append at <data-dir>/sites/<domain>/
//     access.log (mirrors the audit-log shape from broker.zig).
//
// The `serve()` function is a long-running blocking loop; tests drive
// `handleRequest()` directly with synthetic Request stand-ins for unit
// coverage without sockets.

const std = @import("std");
// ── B-pragmatic reactor (brain-wedge fix) ──────────────────────────────
// These three imports land with Commit 5.  They are the ONLY new
// compile-time deps needed to wire the EventLoop into site_server.
// If you need to revert: remove these three lines, delete the reactor
// helpers at the bottom of this file, and restore the old serve() body
// from the RIP-OUT-MARKER comment.
const event_loop_mod = @import("event_loop");
const connection_state_mod = @import("connection_state");
const http_parser_mod = @import("http_parser");
// C4 PR-F1 — cartridge HTTP route registry (reactor consults it for
// cartridge-contributed routes before the static/404 fallthrough).
const http_route_registry = @import("http_route_registry");
const wss_rpc_registry = @import("wss_rpc_registry");
// W0.4: oddjobz_jsonl_watcher removed — mtime polling replaced by Pravega.
const intent_action_router_mod = @import("intent_action_router");
const visit_rollup_router_mod = @import("visit_rollup_router");
const quote_seed_router_mod = @import("quote_seed_router");
// dispatcher: needed by reactorHandleChat to build the anonymous
// DispatchContext + CapabilitySet, mirroring the blocking chat path.
const dispatcher_mod = @import("dispatcher");
// ─────────────────────────────────────────────────────────────────────
const site_config = @import("site_config");
const auth_handler = @import("auth_handler");
const payment_ledger = @import("payment_ledger");
const output_store_fs = @import("output_store_fs");
const runner_mod = @import("runner");
const module_loader = @import("module_loader");
const bearer_tokens = @import("bearer_tokens");
const repl = @import("repl");
const wss_wallet = @import("wss_wallet");
// Platform wallet architecture §3.2 — POST /api/v1/wallet-op structured
// wallet action endpoint (internal, localhost-only, bearer-gated).
const wallet_op_http = @import("wallet_op_http");
// D-O5p — POST /api/v1/device-pair production acceptor.
const device_pair_http = @import("device_pair_http");
// identity_certs + bkds reach the site_server transitively via the
// device_pair_http acceptor; importing them at the site_server seam
// keeps cmdServe's wiring readable when it constructs the acceptor.
const identity_certs_mod = @import("identity_certs");
const bkds_mod = @import("bkds");

comptime {
    _ = identity_certs_mod;
    _ = bkds_mod;
}
// D-W1 Phase 4 — SignedBundle mesh receive seam.
const signed_bundle_transport = @import("signed_bundle_transport");
// D-W2 Phase 2 — POST <bundle-frame-endpoint> dispatches into the
// extension subscription receive seam.  Distinct from D-W1 Phase 4's
// SignedBundle endpoint above (different envelope shape).
const extension_subscribe = @import("extension_subscribe");
const signed_bundle_mod = @import("signed_bundle");
// D-O5m.followup-8 capture+upload — multipart upload + bearer-gated
// blob fetch endpoints.
// C4 PR-H7b — attachments_upload_http import removed (upload moved to the cartridge).
const voice_extract_http = @import("voice_extract_http");
const image_extract_http = @import("image_extract_http");
const audio_extract_http = @import("audio_extract_http");
// D-O5m.followup-9 Phase A — push-register substrate endpoint.
const push_register_http = @import("push_register_http");
// C4 PR-I1 — conversation_send_http import removed (route moved to the cartridge).
// C4 PR-H3 — search_contacts_http import removed (route moved to the cartridge).
// D-network-messagebox-first-class — /api/v1/messages store-and-forward relay.
const messagebox_http = @import("messagebox_http");
// D-brain-contacts-api — /api/v1/contacts CRUD + edge management.
const contacts_http = @import("contacts_http");
// D-brain-intent-classifier-api — /api/v1/intent/* classify + taxonomy.
const intent_http = @import("intent_http");
// D-brain-identity-store-api — /api/v1/identity/* hat + cert endpoints.
const identity_http = @import("identity_http");
// D-brain-loom-store-api — GET /api/v1/objects/{type}[/{id}] typed surface.
const loom_store_http = @import("loom_store_http");
// D-brain-flow-runner-api — /api/v1/flow state machine.
const flow_http = @import("flow_http");
// D-O5m.followup-6 Phase 2 — `GET /api/v1/info` endpoint.  Bearer-
// gated; surfaces shard-proxy URL + brain-pin so mobile + federation
// peers can decide between the mesh transport + the HTTP-REPL fallback.
const info_http = @import("info_http");
// C4 PR-H6 — attachments_blob_http import removed (blob GET moved to the cartridge).
// D-LC1 — raw cell-over-HTTP read path. The acceptor holds a borrowed
// pointer to the brain's CellStore vtable wrapper + bearer_tokens;
// cmdServe attaches via attachCellRawAcceptor.
const cell_raw_http = @import("cell_raw_http");
const cells_mint_http = @import("cells_mint_http");
// Betterment-practice pask sweep — GET /api/v1/betterment/sweep.
const betterment_sweep_http = @import("betterment_sweep_http");
// W3.2 — /api/v1/events WebSocket endpoint (Pravega-to-Flutter bridge).
const events_stream_handler = @import("events_stream_handler");
// P1c — Twilio inbound SMS webhook. POST /api/v1/twilio/inbound.
// C4 PR-I2 — twilio_inbound_http import removed (webhook moved to the cartridge).
const oddjobz_event_bus_mod = @import("oddjobz_event_bus");
comptime {
    _ = signed_bundle_mod;
}

// Site-server utility helpers extracted to src/site_server/util.zig.
// Re-export the pub surface used externally (cli/wallet.zig reaches
// HeaderStoreTracker as site_server.HeaderStoreTracker; reactor.zig
// reaches util via its own import).  After T5, SiteServer's own
// method body no longer needs any util fns directly — the dead
// blocking-path methods were the only callers, and they're gone.
const util = @import("site_server/util.zig");
pub const setSocketTimeouts = util.setSocketTimeouts;
pub const HeaderStoreTracker = util.HeaderStoreTracker;
pub const clientAcceptsGzip = util.clientAcceptsGzip;
pub const isSafeRelativeUrlPath = util.isSafeRelativeUrlPath;
pub const guessContentType = util.guessContentType;

// B-pragmatic reactor helpers extracted to src/site_server/reactor.zig.
// Only one symbol is referenced from the SiteServer struct body
// (reactorMakeCtx, passed by pointer to event_loop_mod in serve());
// re-export it as a file-local alias.
const reactor = @import("site_server/reactor.zig");
const reactorMakeCtx = reactor.reactorMakeCtx;

// D-LC1 / D-LC4 — re-export the cell-raw + cell-since reactor handlers so
// the conformance suite in tests/cell_raw_http_conformance.zig can drive
// them directly with a synthetic HttpRequest, sidestepping the TCP-listener
// fixture other reactor tests use. Handlers stay defined in reactor.zig;
// these are just thin pub aliases for testability.
pub const reactorHandleCellRaw = reactor.reactorHandleCellRaw;
pub const reactorHandleCellSince = reactor.reactorHandleCellSince;

// (request.zig / connection.zig / auth.zig / static.zig / dispatch.zig
//  were extracted from the pre-wedge-fix blocking-accept-loop path.
//  After 2026-05-07 the reactor in site_server/reactor.zig is the sole
//  live HTTP dispatcher, so those modules were dead in production.
//  T5 — deleted 2026-05-12 once T0-T2 + T4 had ported all the endpoints
//  the V1 pilot needs (attachments upload/blob, info, voice-extract).
//  /auth/callback was not re-ported; its visitor-paywall flow is
//  deferred (D7) until a public paywalled site exists.  /api/v1/events
//  is deferred (T3) and stubbed via PWA polling for V1.)

pub const ServerError = error{
    listen_failed,
    read_failed,
    write_failed,
    out_of_memory,
};

/// Mounted server state. One per running site.
pub const SiteServer = struct {
    allocator: std.mem.Allocator,
    config: *const site_config.SiteConfig,
    /// Absolute path to the access log file. Owned.
    access_log_path: []const u8,
    /// Open access log file. Held for the server's lifetime; appended
    /// to per request.
    access_log: ?std.fs.File,
    /// WSITE3 — session + challenge store backing auth-gated routes.
    /// Owned by the server; constructed in `init`.
    auth_store: auth_handler.SessionStore,
    /// WSITE4 — payment ledger for payment_required routes.  Append-
    /// only on disk; queries via `brain revenue`.  Verification of
    /// claimed BEEFs against the chain is deferred to WSITE4.5.
    payments: payment_ledger.PaymentLedger,
    /// WSITE4.6 — file-backed OutputStore for verified UTXOs the admin
    /// has internalized.  Each site gets its own outputs.log under the
    /// site's data dir; revenue summaries + future spend operations
    /// read from here.  Conforms to the cell-engine OutputStore vtable
    /// browser + lmdb mirrors implement.
    outputs: output_store_fs.FsOutputStore,
    /// WSITE2.5 — optional runner for dynamic-route handler dispatch.
    /// `attachRunner` populates this; absent → all dynamic routes
    /// return 503 with a "rebuild with wasmtime" hint.
    runner: ?*runner_mod.Runner = null,
    /// WSITE2.5 — pre-instantiated handler bindings, one per dynamic
    /// route. Index aligned with `handler_loaded`.  Routes that fail
    /// to load (missing binary, hash mismatch, instantiate fail) are
    /// absent — the per-request lookup returns null and we 503.
    handler_instances: std.ArrayList(HandlerSlot) = .empty,
    /// WSITE2.5 — handlers dir (`<data>/sites/<domain>/handlers`).  Owned.
    handlers_dir: []const u8 = "",
    /// D-O7 — absolute path to this site's data dir
    /// (`<data_root>/sites/<domain>/`).  Used by intake routes to tell
    /// the Bun subprocess where to persist session state.  Owned.
    site_data_dir: []const u8 = "",
    /// Brain 4 — optional bearer-token store + REPL session for
    /// `POST /api/v1/repl`. Both must be set via `attachReplBackend`
    /// before the route serves. When either is null the route returns
    /// 503 "REPL backend not enabled". Borrowed; lifetime managed by
    /// the caller (typically `cmdServe`).
    bearer_tokens: ?*bearer_tokens.TokenStore = null,
    repl_session: ?*repl.Session = null,
    /// Brain 4.5 — optional wallet WSS backend. When set + bearer_tokens
    /// is also set, GET /api/v1/wallet upgrades to WebSocket and the
    /// connection drops out of std.http.Server into wss_wallet.serveSession
    /// for JSON-RPC dispatch. Borrowed; same lifetime rules as
    /// `bearer_tokens`.
    wss_backend: ?*wss_wallet.Backend = null,
    /// D-O5p — optional device-pair acceptor backing
    /// POST /api/v1/device-pair.  When null the route returns 503
    /// with a "device-pair acceptor not enabled" hint (mirrors the
    /// other optional-backend routes' shape).  Borrowed; lifetime
    /// managed by the caller (typically `cmdServe`).
    device_pair_acceptor: ?*device_pair_http.Acceptor = null,
    /// D-W1 Phase 4 — optional SignedBundle mesh receive seam.  When
    /// set, POST <bundle_endpoint_path> dispatches into
    /// `signed_bundle_transport.maybeHandle`.  Absent → the endpoint
    /// 404s (no fallback shape; mesh transport is opt-in per
    /// deployment).  Borrowed; lifetime managed by the caller
    /// (typically `cmdServe` when --signed-bundle-endpoint is set).
    bundle_acceptor: ?*signed_bundle_transport.BundleAcceptor = null,
    /// Path the bundle acceptor binds to.  Borrowed; only valid when
    /// `bundle_acceptor` is also set.
    bundle_endpoint_path: ?[]const u8 = null,
    /// D-W2 Phase 2 — optional extension-bundle frame receive seam.
    /// When set, POST <frame_endpoint_path> dispatches into
    /// `extension_subscribe.maybeHandle`.  Absent → endpoint 404s.
    /// Borrowed; lifetime managed by `cmdServe` when
    /// --bundle-frame-endpoint is set.
    frame_acceptor: ?*extension_subscribe.FrameAcceptor = null,
    frame_endpoint_path: ?[]const u8 = null,
    // C4 PR-H7b — attachments_upload_acceptor field removed: POST
    // /api/v1/attachments/upload moved to the oddjobz cartridge over the route
    // registry. (C4 PR-H6 removed the blob-GET acceptor field similarly.)

    /// D-LC1 — optional acceptor backing GET /api/v1/cell/<sha256hex>.
    /// When set, the route returns the raw 1024-byte cell straight out of
    /// the CellStore vtable as application/x-semantos-cell. Absent →
    /// endpoint 404s. Borrowed; lifetime managed by cmdServe.
    cell_raw_acceptor: ?*const cell_raw_http.Acceptor = null,

    /// BRAIN-GENERIC-MINT-VERB M1 — optional acceptor backing POST
    /// /api/v1/cells. When set, the route resolves the typeHash via the
    /// cartridge cellType registry, encodes a canonical 1024-byte cell,
    /// persists via the CellStore vtable, and publishes to the helm
    /// event broker as `cells.<cartridge-id>.minted`. Absent → 404.
    /// Borrowed; lifetime managed by cmdServe.
    cells_mint_acceptor: ?*const cells_mint_http.Acceptor = null,

    /// Tracker T7 — BRC-52 cert + capability request auth.  When set,
    /// the reactor's central auth gate verifies cert-auth headers
    /// (X-Brain-Pubkey / X-Brain-Cert-Sig / X-Brain-Cert-Ts) against
    /// this store and gates admin routes on the admin capability.
    /// Borrowed; same store cmdServe wires into the cells_mint acceptor's
    /// `.certs`.  Null → cert auth unavailable (legacy bearer path only).
    cert_store: ?*identity_certs_mod.CertStore = null,
    /// T7 migration switch.  false (default) → the bearer token still
    /// works on every route (cert auth is opt-in per request via the
    /// cert headers).  true → the legacy bearer fallback is retired and
    /// a valid cert credential is REQUIRED.  cmdServe sets this from
    /// `BRAIN_REQUIRE_CERT_AUTH`.
    require_cert_auth: bool = false,

    /// Betterment practice pask sweep — GET /api/v1/betterment/sweep.
    /// When set, the endpoint runs sweepPracticeHistory() over all
    /// betterment.practice.* cells and returns primed themes for the SCAN state.
    /// Absent → endpoint 503. Borrowed; lifetime managed by cmdServe.
    betterment_sweep_acceptor: ?*const betterment_sweep_http.Acceptor = null,

    /// D-O5m.followup-3 Phase 1 — optional acceptor backing
    /// POST /api/v1/voice-extract.  When set, the route runs the
    /// multipart endpoint that verifies the signed transcript and
    /// shells into the runtime/intent pipeline.  Absent → endpoint
    /// 404s.  Borrowed; lifetime managed by `cmdServe` when voice
    /// support is enabled.
    voice_extract_acceptor: ?*voice_extract_http.Acceptor = null,

    /// Betterment OCR — /api/v1/image-extract acceptor.  Absent → 404.
    /// Borrowed; lifetime managed by `cmdServe` when image-extract is enabled.
    image_extract_acceptor: ?*image_extract_http.Acceptor = null,

    /// Betterment voice — /api/v1/audio-extract acceptor.  Absent → 404.
    audio_extract_acceptor: ?*audio_extract_http.Acceptor = null,

    /// D-O5m.followup-9 Phase A — optional acceptor backing POST/DELETE
    /// /api/v1/push-register.  When set, the route persists APNs/FCM
    /// device tokens onto the device's identity-cert record.  Absent →
    /// endpoint 404s.  Borrowed; lifetime managed by `cmdServe`.  The
    /// real APNs/FCM dispatchers + Flutter Firebase wiring ship in
    /// Phases B + C — this Phase A only stages the substrate.
    push_register_acceptor: ?*const push_register_http.Acceptor = null,

    // C4 PR-I1 — conv_send_acceptor field removed: POST
    // /api/v1/conversation/:id/send moved to the oddjobz cartridge over the
    // route registry.

    // C4 PR-H3 — search_contacts_acceptor field removed: POST
    // /api/v1/search/contacts is now served by the oddjobz cartridge over the
    // route registry (reads the cartridge-owned customers + sites stores).

    /// D-network-messagebox-first-class — optional acceptor backing
    /// /api/v1/messages.  When set, POST /send + GET /list + POST /ack
    /// route to messagebox_http.accept.  Absent → 404.  Borrowed; set
    /// via `attachMessageboxEndpoint`.
    messagebox_acceptor: ?*const messagebox_http.Acceptor = null,

    /// D-brain-contacts-api — optional acceptor backing /api/v1/contacts.
    /// When set, GET/POST + sub-paths route to contacts_http.accept.
    /// Absent → endpoint 404s. Borrowed; set via `attachContactsEndpoint`.
    contacts_acceptor: ?*const contacts_http.Acceptor = null,

    /// D-brain-intent-classifier-api — optional acceptor backing
    /// /api/v1/intent/*. When set, classify/taxonomy routes delegate to
    /// intent_http.accept. Absent → endpoint 404s. Borrowed; set via
    /// `attachIntentEndpoint`.
    intent_acceptor: ?*const intent_http.Acceptor = null,
    /// D-brain-identity-store-api — optional acceptor backing
    /// /api/v1/identity/*. When set, hat/hats/cert routes delegate to
    /// identity_http.accept. Absent → endpoint 404s. Borrowed; set via
    /// `attachIdentityEndpoint`.
    identity_acceptor: ?*const identity_http.Acceptor = null,
    /// D-brain-loom-store-api — optional acceptor backing /api/v1/objects.
    /// When set, GET requests route to loom_store_http.accept.
    /// Absent → endpoint 404s. Borrowed; set via `attachLoomStoreEndpoint`.
    loom_store_acceptor: ?*const loom_store_http.Acceptor = null,
    /// D-brain-flow-runner-api — optional acceptor backing /api/v1/flow.
    /// When set, routes to flow_http.accept. Absent → 404.
    /// Borrowed; set via `attachFlowEndpoint`.
    flow_acceptor: ?*const flow_http.Acceptor = null,

    // C4 PR-I2 — twilio_inbound_acceptor field removed: POST /api/v1/twilio/inbound
    // moved to the oddjobz cartridge over the route registry.

    // C4 PR-G5 — conv_approve_script REMOVED: POST /api/v1/conversation/turn/:id/approve
    // is now served by the oddjobz cartridge via the route registry.

    /// D-OJ-conv-identity-merge-endpoint — optional script path for
    /// POST /api/v1/identity/merge.
    /// When null the endpoint 404s. Borrowed; set via
    /// `attachIdentityMergeEndpoint`.
    identity_merge_script: ?[]const u8 = null,

    // C4 PR-G6 — re_anchor_script REMOVED: POST /api/v1/conversation/turn/:id/re-anchor
    // is now served by the oddjobz cartridge via the route registry.

    // C4 PR-G4 — propose_turn_script REMOVED: POST /api/v1/conversation/turn/propose
    // is now served by the oddjobz cartridge via the route registry.
    // C4 PR-G2 — customer_link_resolve_script REMOVED: GET /api/v1/c/{token}
    // is now served by the oddjobz cartridge via the route registry (it execs
    // its own shipped script, resolved via cartridge_dir).

    // C4 PR-G3 — conv_turns_query_script REMOVED: GET /api/v1/conversation/turns
    // is now served by the oddjobz cartridge via the route registry.

    // C4 PR-G7 — voice_note_script REMOVED: POST /api/v1/voice-note is now served
    // by the oddjobz cartridge via the route registry.

    /// D-O5m.followup-6 Phase 2 — optional acceptor backing GET
    /// /api/v1/info.  Surfaces the shard-proxy URL + brain pin to
    /// mobile + federation peers so they can construct the mesh
    /// transport at startup.  Absent → endpoint 404s.  Borrowed.
    info_acceptor: ?*const info_http.Acceptor = null,

    /// Tier 3 — optional intent-action router.  Forwarded into the
    /// EventLoop so each poll tick drains the router's pending
    /// queue.  Borrowed pointer; cmdServe owns the Router instance.
    intent_router: ?*intent_action_router_mod.Router = null,

    /// Tier 3 follow-up — optional visit-rollup router. Forwarded
    /// into the EventLoop so each poll tick drains its queue (filled
    /// by the broker callback on `visit.transitioned`→completed).
    /// Borrowed pointer; cmdServe owns the Router instance.
    visit_rollup_router: ?*visit_rollup_router_mod.Router = null,

    /// Slice 4 — optional quote-seed router. Forwarded into the
    /// EventLoop so each poll tick drains its queue (filled by the
    /// broker callback on `job.transitioned` qualified→quoted).
    /// Borrowed pointer; cmdServe owns the Router instance.
    quote_seed_router: ?*quote_seed_router_mod.Router = null,

    /// Platform wallet architecture §3.2 — optional acceptor backing
    /// POST /api/v1/wallet-op.  When set, the endpoint receives
    /// structured action JSON (pay / anchorTransition / createAction),
    /// dispatches to the in-process wallet via bsvz, and returns
    /// { txid }.  Localhost-only by design; Caddy must NOT proxy this
    /// path.  Absent → endpoint returns 503.  Borrowed; lifetime
    /// managed by the caller (cmdServe).
    wallet_op_acceptor: ?*wallet_op_http.Acceptor = null,

    /// C4 PR-F1 — cartridge-contributed HTTP route registry. The reactor
    /// consults this (after hardcoded routes, before static/404) so a
    /// cartridge can serve an HTTP endpoint registered at boot via the
    /// cartridge seam — without a typed field here or a reactor.zig edit.
    /// Borrowed; lifetime managed by cmdServe. Absent → no cartridge routes.
    route_registry: ?*http_route_registry.RouteRegistry = null,

    /// Unified WSS RPC channel — cartridge + substrate method table the reactor
    /// consults per frame on /api/v1/rpc. Populated at boot (substrate methods
    /// pre-registered by cmdServe; cartridges add theirs via the cartridge
    /// seam). Borrowed; lifetime managed by cmdServe. Absent → /api/v1/rpc 503.
    rpc_registry: ?*wss_rpc_registry.RpcRegistry = null,

    /// W3.2 — optional OddjobzEventBus backing GET /api/v1/events.
    /// When set, WebSocket upgrade requests to /api/v1/events are
    /// served by events_stream_handler.serveSession, forwarding job FSM
    /// transition events to Flutter clients filtered by `hat` query
    /// param.  Absent → endpoint returns 503.  Borrowed; lifetime
    /// managed by the caller (cmdServe).
    oddjobz_event_bus: ?*oddjobz_event_bus_mod.OddjobzEventBus = null,

    /// One pre-instantiated handler bound to a single dynamic route.
    pub const HandlerSlot = struct {
        /// The route this handler serves.  Borrowed from `config.routes`.
        route: *const site_config.Route,
        /// The verified WASM bytes — owned via `loaded.deinit`.
        loaded: module_loader.LoadedModule,
        /// Live wasmtime instance — owned via `instance.deinit`.
        instance: runner_mod.Instance,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        config: *const site_config.SiteConfig,
        data_dir: []const u8,
    ) !SiteServer {
        const dir = try std.fs.path.join(allocator, &.{ data_dir, "sites", config.domain });
        const site_data_dir_owned = try allocator.dupe(u8, dir);
        errdefer allocator.free(site_data_dir_owned);
        defer allocator.free(dir);
        std.fs.cwd().makePath(dir) catch {};
        const log_path = try std.fs.path.join(allocator, &.{ dir, "access.log" });
        errdefer allocator.free(log_path);
        const log_file = std.fs.cwd().createFile(log_path, .{
            .read = false,
            .truncate = false,
        }) catch null;
        if (log_file) |f| f.seekFromEnd(0) catch {};

        const sess_path = try std.fs.path.join(allocator, &.{ dir, "sessions.log" });
        defer allocator.free(sess_path);
        const auth_store = try auth_handler.SessionStore.init(allocator, sess_path);

        const pay_path = try std.fs.path.join(allocator, &.{ dir, "payments.log" });
        defer allocator.free(pay_path);
        const payments = try payment_ledger.PaymentLedger.init(allocator, pay_path);

        // WSITE4.6 — outputs.log lives next to payments.log so a single
        // domain's "what did I receive + what's spendable" picture is
        // colocated with the claim ledger.
        const outputs = try output_store_fs.FsOutputStore.init(allocator, dir);

        // WSITE2.5 — handlers dir lives at <site>/handlers/.
        const handlers_dir = try std.fs.path.join(allocator, &.{ dir, "handlers" });
        errdefer allocator.free(handlers_dir);
        std.fs.cwd().makePath(handlers_dir) catch {};

        return .{
            .allocator = allocator,
            .config = config,
            .access_log_path = log_path,
            .access_log = log_file,
            .auth_store = auth_store,
            .payments = payments,
            .outputs = outputs,
            .handlers_dir = handlers_dir,
            .site_data_dir = site_data_dir_owned,
        };
    }

    pub fn deinit(self: *SiteServer) void {
        if (self.access_log) |f| f.close();
        self.allocator.free(self.access_log_path);
        self.auth_store.deinit();
        self.payments.deinit();
        self.outputs.deinit();
        // WSITE2.5 — tear down each pre-instantiated handler.
        for (self.handler_instances.items) |*slot| {
            slot.instance.deinit();
            slot.loaded.deinit();
        }
        self.handler_instances.deinit(self.allocator);
        self.allocator.free(self.handlers_dir);
        self.allocator.free(self.site_data_dir);
    }

    /// Brain 4 — attach the bearer-token store + REPL session so the
    /// `POST /api/v1/repl` route can dispatch into `repl.handleLine`.
    /// Both pointers are borrowed; caller (typically `cmdServe`) owns
    /// the lifetimes and must keep them alive for the server's run.
    /// Calling without both set leaves the route 503'd.
    pub fn attachReplBackend(
        self: *SiteServer,
        tokens: *bearer_tokens.TokenStore,
        session: *repl.Session,
    ) void {
        self.bearer_tokens = tokens;
        self.repl_session = session;
    }

    /// Brain 4.5 — attach the wallet WSS backend so GET /api/v1/wallet
    /// upgrades to WebSocket and dispatches BRC-100-shaped JSON-RPC
    /// calls. Re-uses `bearer_tokens` (set via `attachReplBackend`) for
    /// auth — the wallet endpoint and the REPL endpoint share one token
    /// space. Borrowed pointer; lifetime managed by the caller.
    pub fn attachWalletBackend(self: *SiteServer, backend: *wss_wallet.Backend) void {
        self.wss_backend = backend;
    }

    /// Platform wallet architecture §3.2 — attach the structured
    /// wallet-op acceptor so POST /api/v1/wallet-op can dispatch.
    /// Localhost-only; Caddy must NOT proxy this path.  Borrowed
    /// pointer; lifetime managed by the caller (cmdServe).  When
    /// unset the route returns 503.
    pub fn attachWalletOpEndpoint(self: *SiteServer, acceptor: *wallet_op_http.Acceptor) void {
        self.wallet_op_acceptor = acceptor;
    }

    /// D-O5p — attach the device-pair acceptor backing
    /// POST /api/v1/device-pair.  Borrowed pointer; lifetime managed
    /// by the caller.  When unset the route 503s.
    pub fn attachDevicePairAcceptor(self: *SiteServer, acceptor: *device_pair_http.Acceptor) void {
        self.device_pair_acceptor = acceptor;
    }

    /// D-W1 Phase 4 — attach the SignedBundle mesh receive seam.
    /// Mesh peers POST a SignedBundle envelope to `endpoint_path`;
    /// the acceptor decodes, verifies the cert chain + signature,
    /// constructs a DispatchContext, calls the dispatcher, returns
    /// the wire.Response as the body.  Both pointers borrowed;
    /// caller (cmdServe) owns the lifetimes.  Default disabled.
    pub fn attachBundleAcceptor(
        self: *SiteServer,
        acceptor: *signed_bundle_transport.BundleAcceptor,
        endpoint_path: []const u8,
    ) void {
        self.bundle_acceptor = acceptor;
        self.bundle_endpoint_path = endpoint_path;
    }

    /// D-W2 Phase 2 — attach the extension-bundle frame receive seam.
    /// The publisher's TS sidecar (`cartridges/oddjobz/brain/tools/
    /// subscribe-bundles.ts`) POSTs raw BRC-12 frame bytes to
    /// `endpoint_path`; the acceptor decodes the frame, runs
    /// verifyFrame + applyVerifiedFrame, returns the typed JSON body.
    /// Both pointers borrowed; caller (cmdServe) owns the lifetimes.
    /// Default disabled.
    pub fn attachFrameAcceptor(
        self: *SiteServer,
        acceptor: *extension_subscribe.FrameAcceptor,
        endpoint_path: []const u8,
    ) void {
        self.frame_acceptor = acceptor;
        self.frame_endpoint_path = endpoint_path;
    }

    /// D-O5m.followup-9 Phase A — attach the push-register endpoint
    /// acceptor.  Pointer borrowed; lifetime managed by the caller
    /// (cmdServe).  Absent → endpoint 404s.  Substrate scope: this
    /// PR ships schema + endpoint + event flag only.  Phases B/C ship
    /// the real APNs/FCM dispatchers + Flutter wiring.
    pub fn attachPushRegisterEndpoint(
        self: *SiteServer,
        acceptor: *const push_register_http.Acceptor,
    ) void {
        self.push_register_acceptor = acceptor;
    }

    // C4 PR-I1 — attachConversationSendEndpoint removed (route moved to the
    // oddjobz cartridge over the route registry).

    // C4 PR-H3 — attachSearchContactsEndpoint removed (route moved to the
    // oddjobz cartridge over the route registry).

    /// D-network-messagebox-first-class — attach the MessageBox acceptor.
    /// Pointer borrowed; cmdServe owns the Acceptor lifetime.
    pub fn attachMessageboxEndpoint(
        self: *SiteServer,
        acceptor: *const messagebox_http.Acceptor,
    ) void {
        self.messagebox_acceptor = acceptor;
    }

    /// D-brain-contacts-api — attach the contacts acceptor.  Pointer
    /// borrowed; cmdServe owns the Acceptor lifetime.
    pub fn attachContactsEndpoint(
        self: *SiteServer,
        acceptor: *const contacts_http.Acceptor,
    ) void {
        self.contacts_acceptor = acceptor;
    }

    /// D-brain-intent-classifier-api — attach the intent acceptor.  Pointer
    /// borrowed; cmdServe owns the Acceptor lifetime.
    pub fn attachIntentEndpoint(
        self: *SiteServer,
        acceptor: *const intent_http.Acceptor,
    ) void {
        self.intent_acceptor = acceptor;
    }

    /// D-brain-identity-store-api — attach the identity acceptor.  Pointer
    /// borrowed; cmdServe owns the Acceptor lifetime.
    pub fn attachIdentityEndpoint(
        self: *SiteServer,
        acceptor: *const identity_http.Acceptor,
    ) void {
        self.identity_acceptor = acceptor;
    }

    /// D-brain-loom-store-api — attach the loom-store acceptor.
    /// Pointer borrowed; cmdServe owns the Acceptor lifetime.
    pub fn attachLoomStoreEndpoint(
        self: *SiteServer,
        acceptor: *const loom_store_http.Acceptor,
    ) void {
        self.loom_store_acceptor = acceptor;
    }

    /// D-brain-flow-runner-api — attach the flow acceptor. Pointer
    /// borrowed; cmdServe owns the Acceptor lifetime.
    pub fn attachFlowEndpoint(
        self: *SiteServer,
        acceptor: *const flow_http.Acceptor,
    ) void {
        self.flow_acceptor = acceptor;
    }

    // C4 PR-I2 — attachTwilioInboundEndpoint REMOVED (webhook moved to the
    // oddjobz cartridge over the route registry).

    // C4 PR-G5 — attachConversationApproveEndpoint REMOVED (route migrated to
    // the oddjobz cartridge via the route registry).

    /// D-OJ-conv-identity-merge-endpoint — attach the bun identity-merge
    /// script path so POST /api/v1/identity/merge can dispatch.
    /// Slice is borrowed; caller (cmdServe) owns the lifetime.
    /// When unset the endpoint returns 404.
    pub fn attachIdentityMergeEndpoint(self: *SiteServer, script: []const u8) void {
        self.identity_merge_script = script;
    }

    // C4 PR-G6 — attachReAnchorEndpoint REMOVED (route migrated to the oddjobz
    // cartridge via the route registry).

    // C4 PR-G4 — attachProposeTurnEndpoint REMOVED (route migrated to the
    // oddjobz cartridge via the route registry).
    // C4 PR-G2 — attachCustomerLinkResolveEndpoint REMOVED (route migrated to
    // the oddjobz cartridge via the route registry).

    // C4 PR-G7 — attachVoiceNoteEndpoint REMOVED (route migrated to the oddjobz
    // cartridge via the route registry).

    // C4 PR-G3 — attachConvTurnsQueryEndpoint REMOVED (route migrated to the
    // oddjobz cartridge via the route registry).

    // C4 PR-H7b — attachUploadEndpoint REMOVED (POST /api/v1/attachments/upload
    // moved to the oddjobz cartridge over the route registry).

    /// D-LC1 — attach the raw cell-over-HTTP acceptor. Borrowed pointer;
    /// lifetime managed by cmdServe. Absent → GET /api/v1/cell/<sha> returns
    /// 404 (reactor handler).
    pub fn attachCellRawAcceptor(
        self: *SiteServer,
        acceptor: *const cell_raw_http.Acceptor,
    ) void {
        self.cell_raw_acceptor = acceptor;
    }

    /// BRAIN-GENERIC-MINT-VERB M1 — attach the generic mint acceptor.
    /// Borrowed pointer; lifetime managed by cmdServe. Absent → POST
    /// /api/v1/cells returns 404 (reactor handler).
    pub fn attachCellsMintAcceptor(
        self: *SiteServer,
        acceptor: *const cells_mint_http.Acceptor,
    ) void {
        self.cells_mint_acceptor = acceptor;
    }

    /// Betterment practice pask sweep — attach the sweep acceptor so
    /// GET /api/v1/betterment/sweep can dispatch into sweep_runner.ts via Bun.
    /// Borrowed pointer; lifetime managed by cmdServe. Absent → 503.
    pub fn attachBettermentSweepAcceptor(
        self: *SiteServer,
        acceptor: *const betterment_sweep_http.Acceptor,
    ) void {
        self.betterment_sweep_acceptor = acceptor;
    }

    /// T7 — attach the cert store + migration switch backing the
    /// reactor's cert + capability auth gate.  Borrowed pointer; lifetime
    /// managed by cmdServe (same store as the cells_mint acceptor's
    /// `.certs`).  Absent → cert auth unavailable, legacy bearer only.
    pub fn attachCertAuth(
        self: *SiteServer,
        cert_store: ?*identity_certs_mod.CertStore,
        require_cert_auth: bool,
    ) void {
        self.cert_store = cert_store;
        self.require_cert_auth = require_cert_auth;
    }

    /// T8a — attach the /api/v1/info acceptor.  Borrowed pointer;
    /// lifetime managed by cmdServe.  Absent → endpoint 404 (handler
    /// in site_server/reactor.zig:reactorHandleInfo returns
    /// {"error":"not_found"} when the field is null).
    pub fn attachInfoAcceptor(
        self: *SiteServer,
        acceptor: *const info_http.Acceptor,
    ) void {
        self.info_acceptor = acceptor;
    }

    /// C4 PR-F1 — attach the cartridge HTTP route registry. Borrowed pointer;
    /// lifetime managed by cmdServe. cmdServe creates the registry, attaches
    /// it here, then hands the same pointer to cartridges via
    /// CartridgeDeps.route_registry so their registerInto can add routes.
    pub fn attachRouteRegistry(
        self: *SiteServer,
        registry: *http_route_registry.RouteRegistry,
    ) void {
        self.route_registry = registry;
    }

    /// Attach the unified WSS RPC method registry. Borrowed pointer; lifetime
    /// managed by cmdServe. cmdServe creates it, pre-registers substrate
    /// methods (cell.query/repl.eval/…), attaches it here, then hands the same
    /// pointer to cartridges via CartridgeDeps.rpc_registry.
    pub fn attachRpcRegistry(
        self: *SiteServer,
        registry: *wss_rpc_registry.RpcRegistry,
    ) void {
        self.rpc_registry = registry;
    }

    /// T8b — attach the /api/v1/voice-extract acceptor.  Borrowed
    /// pointer; lifetime managed by cmdServe.  Absent → endpoint 404.
    /// The acceptor itself carries a VoiceExtractShell function pointer
    /// that runs the bun intent pipeline; cmdServe constructs both
    /// together when the shell impl is available.
    pub fn attachVoiceExtractAcceptor(
        self: *SiteServer,
        acceptor: *voice_extract_http.Acceptor,
    ) void {
        self.voice_extract_acceptor = acceptor;
    }

    /// Betterment OCR — attach the image-extract acceptor (bun shell-out to
    /// Claude vision).  cmdServe constructs it when the script path is set.
    pub fn attachImageExtractAcceptor(
        self: *SiteServer,
        acceptor: *image_extract_http.Acceptor,
    ) void {
        self.image_extract_acceptor = acceptor;
    }

    /// Betterment voice — attach the audio-extract acceptor (bun → whisper.cpp).
    pub fn attachAudioExtractAcceptor(
        self: *SiteServer,
        acceptor: *audio_extract_http.Acceptor,
    ) void {
        self.audio_extract_acceptor = acceptor;
    }

    /// Tier 3 — attach the intent-action router so the EventLoop
    /// drains its queue on every poll tick.  Borrowed pointer;
    /// lifetime managed by cmdServe.  Absent → no router drain
    /// happens (router is gated OFF by default).
    pub fn attachIntentRouter(
        self: *SiteServer,
        router: *intent_action_router_mod.Router,
    ) void {
        self.intent_router = router;
    }

    /// Tier 3 follow-up — attach the visit-rollup router so the
    /// EventLoop drains its queue every poll tick. Borrowed pointer;
    /// lifetime managed by cmdServe. Absent → no rollup drain.
    pub fn attachVisitRollupRouter(
        self: *SiteServer,
        router: *visit_rollup_router_mod.Router,
    ) void {
        self.visit_rollup_router = router;
    }

    /// Slice 4 — attach the quote-seed router so the EventLoop drains
    /// its queue every poll tick. Borrowed pointer; lifetime managed
    /// by cmdServe. Absent → no quote-seed drain.
    pub fn attachQuoteSeedRouter(
        self: *SiteServer,
        router: *quote_seed_router_mod.Router,
    ) void {
        self.quote_seed_router = router;
    }

    /// W3.2 — attach the OddjobzEventBus so GET /api/v1/events upgrades
    /// to WebSocket and forwards job FSM events to Flutter clients.
    /// Borrowed pointer; lifetime managed by the caller (cmdServe).
    /// Absent → endpoint returns 503.
    pub fn attachEventsStreamBackend(
        self: *SiteServer,
        bus: *oddjobz_event_bus_mod.OddjobzEventBus,
    ) void {
        self.oddjobz_event_bus = bus;
    }

    /// WSITE2.5 — attach a runner and pre-instantiate every dynamic
    /// route's handler.  Call after `init` and before `serve`.  Errors
    /// per-handler are non-fatal: the slot is omitted, and per-request
    /// dispatch returns 503 with the underlying error name.  Returns
    /// the count of successfully instantiated handlers.
    pub fn attachRunner(self: *SiteServer, runner: *runner_mod.Runner) !u32 {
        self.runner = runner;
        // Pre-reserve so appends never relocate — we hand out raw
        // pointers to slots from the dispatcher.
        var dynamic_count: usize = 0;
        for (self.config.routes) |r| {
            if (r.kind == .dynamic) dynamic_count += 1;
            // D-O6a — `.chat` routes have no WASM handler; skip them
            // here so the count + per-route loop below leave them alone.
        }
        try self.handler_instances.ensureTotalCapacityPrecise(self.allocator, dynamic_count);

        var ok_count: u32 = 0;
        for (self.config.routes) |*r| {
            if (r.kind != .dynamic) continue;
            self.loadHandlerSlot(r) catch |err| {
                self.logRequest(.GET, r.path, switch (err) {
                    error.handler_unset => 500,
                    error.handler_hash_unset => 500,
                    error.hash_mismatch => 500,
                    error.file_too_large => 413,
                    else => 503,
                }) catch {};
                continue;
            };
            ok_count += 1;
        }
        return ok_count;
    }

    fn loadHandlerSlot(self: *SiteServer, route: *const site_config.Route) !void {
        if (route.handler.len == 0) return error.handler_unset;
        if (!route.handler_sha256_set) return error.handler_hash_unset;
        const path = try std.fs.path.join(self.allocator, &.{ self.handlers_dir, route.handler });
        defer self.allocator.free(path);
        var loaded = try module_loader.loadAndVerify(
            self.allocator,
            route.handler,
            path,
            &route.handler_sha256,
        );
        errdefer loaded.deinit();
        const runner = self.runner orelse return error.runner_missing;
        if (!runner.wasmtimeEnabled()) return error.wasmtime_disabled;
        const inst = try runner.instantiate(&loaded, .dynamic_handler);
        try self.handler_instances.append(self.allocator, .{
            .route = route,
            .loaded = loaded,
            .instance = inst,
        });
    }

    pub fn findHandlerSlot(self: *SiteServer, route: *const site_config.Route) ?*HandlerSlot {
        for (self.handler_instances.items) |*slot| {
            if (slot.route == route) return slot;
        }
        return null;
    }

    /// Block-listen on the configured port until an error or signal.
    ///
    /// RIP-OUT-MARKER (brain-wedge B-pragmatic, 2026-05-07):
    ///   This function was rewritten from a blocking accept loop to a
    ///   poll-based single-threaded reactor to fix the "Bridget wedge" —
    ///   one phone holding a WSS connection to /api/v1/wallet was blocking
    ///   every other HTTP request.
    ///
    ///   The old body was:
    ///     while (true) {
    ///         if (cancel) |c| { if (c.load(.acquire)) return; }
    ///         const conn = listener.accept() catch |err| switch (err) { ... };
    ///         self.handleConnection(conn) catch {};
    ///     }
    ///
    ///   To revert: restore that loop and remove all reactor helpers at the
    ///   end of this file, plus the three @import lines at the top.
    ///
    /// `cancel` — if non-null, the loop checks the flag each poll tick
    /// (100 ms granularity) and returns cleanly when it fires.
    pub fn serve(self: *SiteServer, cancel: ?*const std.atomic.Value(bool)) !void {
        // Bind on [::] (IPv6 wildcard) so we accept BOTH IPv4 and IPv6
        // connections.  Required for direct-IPv6 brain-to-brain reaches at
        // the T1/T3 /128 session-key addresses (see D-network-ipv6-session-keys).
        //
        // Relies on the Linux kernel default `net.ipv6.bindv6only=0` (dual-stack
        // — IPv4 connections arrive as IPv4-mapped IPv6 like ::ffff:1.2.3.4).
        // Every major distro ships this default.  Hardened images that flip
        // it to 1 will lose IPv4 connectivity until reverted — we don't yet
        // setsockopt IPV6_V6ONLY=0 explicitly because std.net.Address.listen()
        // doesn't expose the socket pre-bind; if this becomes an operator
        // pain-point, switch to manual posix.socket+setsockopt+bind+listen.
        const addr = try std.net.Address.parseIp6("::", self.config.listen_port);
        var listener = try addr.listen(.{ .reuse_address = true });
        defer listener.deinit();

        // Make the listener fd non-blocking so poll() can gate accept()
        // without spinning.  Without this, accept() on the listener fd
        // would block when poll() reports POLL.IN but the connection was
        // already taken (race on multi-core).
        const listener_fd = listener.stream.handle;
        const flags = try std.posix.fcntl(listener_fd, std.posix.F.GETFL, 0);
        _ = try std.posix.fcntl(
            listener_fd,
            std.posix.F.SETFL,
            flags | @as(u32, @bitCast(std.posix.O{ .NONBLOCK = true })),
        );

        var loop = try event_loop_mod.EventLoop.init(
            self.allocator,
            listener_fd,
            &reactorMakeCtx,
            @ptrCast(self),
        );
        defer loop.deinit();

        // Tier 3 — forward the intent-action router so its pending
        // queue is drained on every reactor tick.
        loop.intent_router = self.intent_router;
        // Tier 3 follow-up — same for the visit-rollup router.
        loop.visit_rollup_router = self.visit_rollup_router;
        // Slice 4 — same for the quote-seed router.
        loop.quote_seed_router = self.quote_seed_router;

        // If the caller passed a cancel signal, we monitor it from a
        // background thread that calls loop.stop() when it fires.  The
        // reactor checks loop.shutdown on every 100 ms poll tick and exits
        // cleanly.  This is safe because loop.stop() is an atomic store.
        var cancel_thread: ?std.Thread = null;
        if (cancel) |c| {
            if (c.load(.acquire)) return; // already cancelled
            cancel_thread = try std.Thread.spawn(.{}, reactorCancelWatcher, .{ &loop, c });
        }
        defer if (cancel_thread) |t| t.detach();

        try loop.run();
    }

    /// Background thread that monitors `cancel` and calls `loop.stop()`
    /// when the flag fires.  Runs for the lifetime of serve().
    fn reactorCancelWatcher(
        loop: *event_loop_mod.EventLoop,
        cancel: *const std.atomic.Value(bool),
    ) void {
        while (!loop.shutdown.load(.acquire)) {
            if (cancel.load(.acquire)) {
                loop.stop();
                return;
            }
            std.Thread.sleep(20 * 1_000_000); // 20 ms in nanoseconds
        }
    }

    pub fn logRequest(self: *SiteServer, method: std.http.Method, target: []const u8, status: u16) !void {
        const file = self.access_log orelse return;
        const ts = std.time.timestamp();
        var line_buf: [512]u8 = undefined;
        const line = try std.fmt.bufPrint(&line_buf,
            "{{\"ts\":{d},\"method\":\"{s}\",\"path\":\"{s}\",\"status\":{d}}}\n",
            .{ ts, @tagName(method), target, status });
        file.writeAll(line) catch {};
    }
};

```
