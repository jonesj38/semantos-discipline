---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cli/repl.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.287176+00:00
---

# runtime/semantos-brain/src/cli/repl.zig

```zig
// Brain 3 — REPL boot.  Extracted from src/cli.zig as Move 10 of
// the cli-modularize refactor.  Pure code motion: no behaviour change.
//
// This file owns cmdRepl + ReplBackend.  Distinct from src/repl.zig
// (the REPL implementation library); this file is the CLI seam that
// wires the broker + stores + handlers + Session for `brain repl`.

const std = @import("std");
const cli_common = @import("common.zig");
const cli_site = @import("site.zig");
const audit_log_mod = @import("audit_log");
const broker_mod = @import("broker");
const dispatcher_mod = @import("dispatcher");
const runner_mod = @import("runner");
const repl_mod = @import("repl");
const config = @import("config");
const module_loader = @import("module_loader");
const instance_manager = @import("instance_manager");
const slot_store_fs_mod = @import("slot_store_fs");
const state_store_fs_mod = @import("state_store_fs");
const header_store_fs_mod = @import("header_store_fs");
const header_store_mod = @import("header_store");
const helm_event_broker_mod = @import("helm_event_broker");
const identity_certs_mod = @import("identity_certs");
const llm_adapter = @import("llm_adapter");
const llm_http_adapter_mod = @import("llm_http_adapter");
const llm_suggester = @import("llm_suggester");
const lmdb_mod = @import("lmdb");
const lmdb_config_mod = @import("lmdb_config");
const lmdb_cell_store_mod = @import("lmdb_cell_store");
const cell_handler_mod = @import("cell_handler");
const intent_cell_lmdb_store_mod = @import("intent_cell_lmdb_store");
// C4 PR-H5b — the REPL now stands up the oddjobz typed stores + dispatcher
// handlers via the cartridge seam (same as serve), not inline. The per-store
// jobs/customers/visits/quotes/estimates/invoices/attachments imports are
// gone; the cartridge's registerInto owns them.
const cartridge_seam = @import("cartridge_seam");
const repl_verb_registry_mod = @import("repl_verb_registry"); // C4 PR-R3
const extensions_mod = @import("extensions");
const extension_manifest_loader = @import("extension_manifest_loader");
const intent_cells_handler_mod = @import("intent_cells_handler");
const sites_store_fs_mod = @import("sites_store_fs");
const site_config_handler_mod = @import("site_config_handler");
const unix_socket_transport = @import("unix_socket");
const bearer_tokens_mod = @import("bearer_tokens");
const bearer_tokens_handler_mod = @import("bearer_tokens_handler");
const identity_certs_handler_mod = @import("identity_certs_handler");
const headers_handler_mod = @import("headers_handler");
const modules_handler_mod = @import("modules_handler");
const device_pair_mod = @import("device_pair");
const bsvz_mod = @import("bsvz");

const Output = cli_common.Output;
const ExitCode = cli_common.ExitCode;
const sitesDir = cli_site.sitesDir;
const flushOutput = cli_common.flushOutput;
const realClock = cli_common.realClock;

pub fn cmdRepl(
    allocator: std.mem.Allocator,
    out: *const Output,
    config_path: []const u8,
    args: []const [:0]u8,
) !ExitCode {
    var enable_llm = false;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--llm")) {
            enable_llm = true;
        } else if (std.mem.eql(u8, args[i], "--config-path")) {
            // Already resolved by main.zig; skip the value.
            i += 1;
        }
    }

    var backend = ReplBackend.bringUp(allocator, config_path, out) catch |e| switch (e) {
        error.config_error => return .config_error,
        error.hash_mismatch => return .hash_mismatch,
        error.file_io => return .file_io,
        else => return e,
    };
    defer backend.deinit();
    var session = backend.makeSession();

    // D-W1 Phase 1 follow-up — attach a CertStore so REPL `device
    // pair / claim / list / revoke` can drive the cert chain
    // directly.  Best-effort: failure is non-fatal (the device verb
    // will hint at the CLI form when no store is attached).
    var repl_cert_store: ?identity_certs_mod.CertStore =
        identity_certs_mod.CertStore.init(allocator, backend.cfg.shell.data_dir, realClock) catch null;
    defer if (repl_cert_store) |*cs| cs.deinit();
    if (repl_cert_store) |*cs| session.cert_store = cs;

    // ── Brain 5.2 — optional LLM adapter ──
    var llm_state: ?LlmReplState = null;
    defer if (llm_state) |*s| s.deinit();
    if (enable_llm) {
        llm_state = bringUpLlmAdapter(allocator, backend.cfg.shell.data_dir, out) catch |e| {
            try out.print("--llm: failed to bring up adapter: {s}\n", .{@errorName(e)});
            return .config_error;
        };
        if (llm_state) |s| {
            try out.print("LLM enabled — backend={s} model={s}. Modal-prefix lines (`do `, `find `, `talk `) route through the LLM.\n", .{ s.cfg.backend.toString(), s.cfg.model });
        }
    }

    try out.print("brain REPL — type `help` for commands, `exit` to leave.\n", .{});

    // Smoke-test pass #1, fix #9 — embedded vs daemon banner.
    //
    // `brain repl` brings up its own in-process dispatcher + opens its
    // own data dir.  When a daemon is already running on the same
    // data_dir, REPL changes here are NOT visible to the daemon
    // (different process, different store handle).  Pre-fix, an
    // operator who ran `add job ...` in the REPL while `brain serve`
    // was up saw nothing on the helm — exactly the smoke-test bug.
    //
    // Routing the REPL through the daemon's Unix socket is a real
    // refactor (the embedded session carries cert_store / llm /
    // dispatch_audit etc. that the socket protocol doesn't yet
    // surface).  Until that lands, surface the gap loudly so the
    // operator can choose: stop the daemon and use the REPL, or
    // hit the daemon's HTTP-REPL endpoint.
    detectDaemonAndWarn(allocator, backend.cfg.shell.data_dir, out) catch {};

    return try replLoop(allocator, out, &session, backend.cfg.shell.data_dir, if (llm_state) |*s| s else null);
}

/// Best-effort: probe the Unix socket and, if a daemon is running on
/// this data_dir, print a multi-line warning before the prompt.  Any
/// error is silently swallowed (a missing socket is the expected case).
fn detectDaemonAndWarn(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    out: *const Output,
) !void {
    if (unix_socket_transport.Client.connect(allocator, data_dir)) |client_val| {
        var client = client_val;
        defer client.close();
        const sock_path = try std.fs.path.join(allocator, &.{ data_dir, unix_socket_transport.SOCKET_BASENAME });
        defer allocator.free(sock_path);
        try out.print(
            \\
            \\WARNING — embedded mode (running daemon at {s} is NOT used).
            \\         Changes from this REPL will NOT be visible to the daemon.
            \\         Hit the daemon's POST /api/v1/repl endpoint instead, or
            \\         stop the daemon (`pkill -f 'brain serve'`) before continuing.
            \\
            \\
        , .{sock_path});
    } else |_| {}
}

/// Brain 5.2 — LLM adapter + config bundle held alongside the REPL session.
const LlmReplState = struct {
    cfg: llm_adapter.LlmConfig,
    adapter: *llm_http_adapter_mod.HttpLlmAdapter,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *LlmReplState) void {
        self.allocator.destroy(self.adapter);
        self.cfg.deinit(self.allocator);
    }

    pub fn parseAdapter(self: *LlmReplState) llm_adapter.LlmAdapter {
        return self.adapter.adapter();
    }
};

/// Load LlmConfig from disk and, if enabled+configured, heap-allocate a
/// HttpLlmAdapter that points at it.  Returns null if the operator hasn't
/// run `brain llm enable` yet — `--llm` without prior config is treated
/// as "no-op fallback to plain REPL" rather than a hard error so the
/// flag is safe to leave in shell aliases.
fn bringUpLlmAdapter(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    out: *const Output,
) !?LlmReplState {
    var cfg = llm_adapter.loadConfig(allocator, data_dir) catch |e| switch (e) {
        error.FileNotFound => {
            try out.print("--llm: no config found at {s}/llm.json — run `brain llm enable` first; falling back to plain REPL\n", .{data_dir});
            return null;
        },
        else => return e,
    };
    if (!cfg.enabled or cfg.backend == .none or cfg.endpoint.len == 0) {
        try out.print("--llm: config disabled or unset (enabled={}, backend={s}); falling back to plain REPL\n", .{ cfg.enabled, cfg.backend.toString() });
        cfg.deinit(allocator);
        return null;
    }
    const adapter = try allocator.create(llm_http_adapter_mod.HttpLlmAdapter);
    adapter.* = llm_http_adapter_mod.HttpLlmAdapter.init(allocator, cfg);
    return .{ .cfg = cfg, .adapter = adapter, .allocator = allocator };
}

/// Brain 4 — shared lifecycle helper for the REPL backend.
///
/// Owns every resource the `repl.Session` borrows: the Semantos Brain Config, the
/// instance manager, loaded modules, file-backed slot/state/header
/// stores, the audit log, the broker, the runner, and any instantiated
/// module instances.  Heap-allocated so the field addresses are stable
/// across moves — `Session.broker` etc. are `*const` pointers into the
/// backend's fields and would dangle if the backend itself were moved
/// after the Session was built.
///
/// Used by:
///   - `cmdRepl` — interactive operator REPL
///   - `cmdServe --enable-repl` — wires the backend through
///     `SiteServer.attachReplBackend` so HTTP REPL requests dispatch
///     into the same Session
pub const ReplBackend = struct {
    allocator: std.mem.Allocator,
    cfg: config.Config,
    manager: instance_manager.InstanceManager,
    loaded_modules: std.ArrayList(module_loader.LoadedModule),
    slot_fs: slot_store_fs_mod.FsSlotStore,
    state_fs: state_store_fs_mod.FsStateStore,
    header_fs: header_store_fs_mod.FsHeaderStore,
    audit: audit_log_mod.AuditLog,
    audit_path: []u8,
    broker: broker_mod.Broker,
    runner: runner_mod.Runner,
    instances: std.ArrayList(repl_mod.NamedInstance),
    header_store_handle: header_store_mod.HeaderStore,

    pub const BringUpError = error{
        config_error,
        hash_mismatch,
        file_io,
        out_of_memory,
    };

    pub fn bringUp(
        allocator: std.mem.Allocator,
        config_path: []const u8,
        out: *const Output,
    ) anyerror!*ReplBackend {
        const self = try allocator.create(ReplBackend);
        errdefer allocator.destroy(self);
        self.allocator = allocator;

        self.cfg = config.loadFromPath(allocator, config_path) catch |e| {
            try out.print("failed to load config: {s}\n", .{@errorName(e)});
            return BringUpError.config_error;
        };
        errdefer self.cfg.deinit();

        self.manager = instance_manager.InstanceManager.init(allocator);
        errdefer self.manager.deinit();

        self.loaded_modules = .{};
        errdefer {
            for (self.loaded_modules.items) |*lm| lm.deinit();
            self.loaded_modules.deinit(allocator);
        }
        try self.loaded_modules.ensureTotalCapacityPrecise(allocator, self.cfg.modules.len);

        for (self.cfg.modules) |m| {
            const full_path = if (std.fs.path.isAbsolute(m.path))
                try allocator.dupe(u8, m.path)
            else
                try std.fs.path.join(allocator, &.{ self.cfg.shell.modules_dir, m.path });
            defer allocator.free(full_path);
            const lm = module_loader.loadAndVerify(allocator, m.name, full_path, &m.sha256) catch |e| {
                try out.print("module {s}: {s}\n", .{ m.name, @errorName(e) });
                return BringUpError.hash_mismatch;
            };
            try self.loaded_modules.append(allocator, lm);
            try self.manager.register(&self.loaded_modules.items[self.loaded_modules.items.len - 1]);
        }

        // Stand up the file-backed stores.
        std.fs.cwd().makePath(self.cfg.shell.data_dir) catch {};
        self.slot_fs = slot_store_fs_mod.FsSlotStore.init(allocator, self.cfg.shell.data_dir) catch return BringUpError.file_io;
        errdefer self.slot_fs.deinit();
        self.state_fs = state_store_fs_mod.FsStateStore.init(allocator, self.cfg.shell.data_dir) catch return BringUpError.file_io;
        errdefer self.state_fs.deinit();
        self.header_fs = header_store_fs_mod.FsHeaderStore.init(allocator, self.cfg.shell.data_dir) catch return BringUpError.file_io;
        errdefer self.header_fs.deinit();

        self.audit = audit_log_mod.AuditLog.init();
        errdefer self.audit.close();
        self.audit_path = try std.fs.path.join(allocator, &.{ self.cfg.shell.data_dir, "audit.log" });
        errdefer allocator.free(self.audit_path);
        self.audit.open(self.audit_path) catch return BringUpError.file_io;

        self.broker = broker_mod.Broker.init(
            allocator,
            self.slot_fs.store(),
            self.state_fs.store(),
            self.header_fs.store(),
            &self.audit,
        );

        self.runner = runner_mod.Runner.init(allocator, &self.broker);
        errdefer self.runner.deinit();

        self.instances = .{};
        errdefer {
            for (self.instances.items) |*ni| {
                var inst = ni.instance;
                inst.deinit();
            }
            self.instances.deinit(allocator);
        }
        if (self.runner.wasmtimeEnabled()) {
            for (self.loaded_modules.items, 0..) |*lm, i| {
                const kind: broker_mod.Module = if (i == 0) .wallet_engine else .headers_verifier;
                const inst = self.runner.instantiate(lm, kind) catch |e| {
                    try out.print("  ✗ {s}: instantiate failed ({s})\n", .{ lm.name, @errorName(e) });
                    continue;
                };
                try self.instances.append(allocator, .{ .name = lm.name, .instance = inst });
            }
        }

        self.header_store_handle = self.header_fs.store();
        return self;
    }

    pub fn deinit(self: *ReplBackend) void {
        for (self.instances.items) |*ni| {
            var inst = ni.instance;
            inst.deinit();
        }
        self.instances.deinit(self.allocator);
        self.runner.deinit();
        self.audit.close();
        self.allocator.free(self.audit_path);
        self.header_fs.deinit();
        self.state_fs.deinit();
        self.slot_fs.deinit();
        for (self.loaded_modules.items) |*lm| lm.deinit();
        self.loaded_modules.deinit(self.allocator);
        self.manager.deinit();
        self.cfg.deinit();
        self.allocator.destroy(self);
    }

    /// Build a `repl.Session` borrowing every backend field. Caller MUST
    /// keep the backend alive for the session's entire lifetime.
    pub fn makeSession(self: *ReplBackend) repl_mod.Session {
        return repl_mod.Session{
            .allocator = self.allocator,
            .cfg = &self.cfg,
            .audit_path = self.audit_path,
            .audit = &self.audit,
            .broker = &self.broker,
            .manager = &self.manager,
            .runner = &self.runner,
            .instances = self.instances.items,
            .header_store = &self.header_store_handle,
        };
    }
};

/// REPL loop — reads stdin line-by-line, dispatches each through the
/// session, persists to history.  Exits on EOF or quit signal.
fn replLoop(
    allocator: std.mem.Allocator,
    out: *const Output,
    session: *repl_mod.Session,
    data_dir: []const u8,
    llm_state: ?*LlmReplState,
) !ExitCode {
    // ── D-W1 Phase 0 — bring up the in-process dispatcher ────────────
    //
    // The dispatcher's lifetime is the replLoop's call frame.  The
    // shim handler captures a pointer to `session` (whose address is
    // stable for cmdRepl's duration) so cmdStatus / cmdHelp can read
    // every borrowed field through the same Session struct as the
    // legacy direct-call path.
    var disp = dispatcher_mod.Dispatcher.init(allocator, session.audit);
    defer disp.deinit();
    try repl_mod.registerReplShims(&disp, session);
    session.dispatcher = &disp;

    // C4 PR-R3 — cartridge-owned REPL verb registry. The cartridge seam's
    // dispatchRegistrations (below) populates it; handleLine consults it via
    // session.repl_verb_registry. Empty until a cartridge registers verbs.
    var repl_verb_registry_repl: repl_verb_registry_mod.ReplVerbRegistry = .{};
    session.repl_verb_registry = &repl_verb_registry_repl;

    // ── D-O5.followup-4 — process-scoped helm event broker ──
    //
    // One Broker per cmdRepl session.  cmdRepl doesn't bring up the
    // WSS endpoint (the REPL is operator-local), so the broker has no
    // subscriber-hub side here — the jobs_handler still emits, but
    // the events fan out to zero subscribers (a no-op).  The broker
    // is wired in this scope so the REPL surface tests the emit path
    // even when no helm is connected.
    var helm_broker = helm_event_broker_mod.Broker.init(allocator);
    defer helm_broker.deinit();


    // W0.2 — shared LMDB env + CellStore for the 5 entity stores in the
    // REPL path.  Best-effort: if env open fails all five stores stay null.
    var repl_entity_lmdb_env: ?lmdb_mod.Env = blk: {
        const entity_lmdb_path = try std.fs.path.join(
            allocator,
            &.{ session.cfg.shell.data_dir, "entity_cells_lmdb" },
        );
        defer allocator.free(entity_lmdb_path);
        std.fs.makeDirAbsolute(entity_lmdb_path) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => {
                try out.print("repl: entity-cells lmdb dir create failed: {s}\n", .{@errorName(e)});
                break :blk null;
            },
        };
        break :blk lmdb_mod.Env.open(entity_lmdb_path, .{
            .open_flags = lmdb_config_mod.LmdbConfig.prod_flags,
            .map_size = lmdb_config_mod.LmdbConfig.default.map_size,
            .max_dbs = lmdb_config_mod.LmdbConfig.default.max_dbs,
            .mode = lmdb_config_mod.LmdbConfig.default.mode,
        }) catch |e| blk2: {
            try out.print("repl: failed to open entity-cells LMDB env: {s} (entity stores disabled)\n", .{@errorName(e)});
            break :blk2 null;
        };
    };
    defer if (repl_entity_lmdb_env) |*env| env.close();
    var repl_entity_cell_store_impl: ?lmdb_cell_store_mod.LmdbCellStore = if (repl_entity_lmdb_env) |*env|
        lmdb_cell_store_mod.LmdbCellStore.init(env, allocator) catch null
    else
        null;
    var repl_entity_cell_store: ?@import("cell_store").CellStore = if (repl_entity_cell_store_impl) |*impl|
        impl.store()
    else
        null;

    // ── C4 PR-H5b — oddjobz resources via the cartridge seam ─────────────
    //
    // Instead of constructing the typed stores + handlers inline, the REPL now
    // runs the SAME cartridge dispatch serve does: each installed cartridge's
    // registerInto builds its stores over the shared entity cell store +
    // registers its dispatcher resources on `disp`. The REPL's find/transition
    // verbs (src/repl/oddjobz_cmds.zig) dispatch through those registered
    // handlers, so they work unchanged — and the REPL now also gains the
    // estimates resource + the find-jobs→attachments[] late-bind it lacked.
    //
    // Behaviour note: the REPL's oddjobz verbs now (correctly) depend on the
    // oddjobz cartridge being installed in <data_dir>/extensions/ — same as
    // serve. A REPL-only deps bag (operator-local): no HTTP routes, no bearer
    // store, no NATS / content / mint-context / store registry. Best-effort:
    // any failure logs + leaves the verbs disabled (the REPL stays up).
    if (repl_entity_cell_store) |*ecs| {
        const manifests = extensions_mod.enumerateUserInstalled(allocator, session.cfg.shell.data_dir) catch |e| blk: {
            try out.print("repl: cartridge manifest enumeration failed: {s} (oddjobz verbs disabled)\n", .{@errorName(e)});
            break :blk @as([]extension_manifest_loader.ExtensionManifest, &.{});
        };
        defer extension_manifest_loader.deinitManifests(allocator, @constCast(manifests));
        const repl_cart_deps = cartridge_seam.CartridgeDeps{
            .cell_store = ecs,
            .broker = &helm_broker,
            .audit_log = session.audit,
            .site_data_dir = session.cfg.shell.data_dir,
            // C4 PR-R3 — the cartridge registers its REPL verb forms here.
            .repl_verb_registry = &repl_verb_registry_repl,
            // bearer_tokens / route_registry / store_registry / content_store /
            // nats_producer / mint_context_registry / cert_store: null — the REPL
            // is operator-local (no HTTP surface, no event spine, no mint handler).
        };
        cartridge_seam.dispatchRegistrations(&disp, allocator, &repl_cart_deps, manifests) catch |e| {
            try out.print("repl: cartridge dispatch failed: {s} (oddjobz verbs disabled)\n", .{@errorName(e)});
        };
    }

    // ── Phase 3 (W0.3) — typed `intent_cells` resource ──
    //
    // W0.3: intent cells now stored in LMDB via IntentCellLmdbStore.
    // We open a dedicated LMDB env for intent cells so the store works
    // regardless of the main --store-backend flag.
    const intent_cells_lmdb_path_repl = try std.fs.path.join(
        allocator,
        &.{ session.cfg.shell.data_dir, "intent_cells_lmdb" },
    );
    defer allocator.free(intent_cells_lmdb_path_repl);
    std.fs.makeDirAbsolute(intent_cells_lmdb_path_repl) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => try out.print("repl: intent-cells lmdb dir create failed: {s}\n", .{@errorName(e)}),
    };
    var intent_cells_env_repl: ?lmdb_mod.Env = lmdb_mod.Env.open(intent_cells_lmdb_path_repl, .{
        .open_flags = lmdb_config_mod.LmdbConfig.prod_flags,
        .map_size = lmdb_config_mod.LmdbConfig.default.map_size,
        .max_dbs = lmdb_config_mod.LmdbConfig.default.max_dbs,
        .mode = lmdb_config_mod.LmdbConfig.default.mode,
    }) catch |e| blk: {
        try out.print("repl: failed to open intent-cells LMDB env: {s} (submit-intent-cell verbs disabled)\n", .{@errorName(e)});
        break :blk null;
    };
    defer if (intent_cells_env_repl) |*env| env.close();
    var intent_cells_store_repl: ?intent_cell_lmdb_store_mod.IntentCellLmdbStore = null;
    if (intent_cells_env_repl) |*env| {
        intent_cells_store_repl = intent_cell_lmdb_store_mod.IntentCellLmdbStore.init(env, allocator) catch |e| blk: {
            try out.print("repl: failed to open intent-cells store: {s} (submit-intent-cell verbs disabled)\n", .{@errorName(e)});
            break :blk null;
        };
    }
    defer if (intent_cells_store_repl) |*ics| ics.deinit();
    var intent_cells_handler: ?intent_cells_handler_mod.Handler = null;
    if (intent_cells_store_repl) |*ics| {
        intent_cells_handler = intent_cells_handler_mod.Handler.initWithDeps(
            allocator,
            ics,
            session.cert_store,
            &helm_broker,
            session.audit,
        );
        try disp.register(intent_cells_handler.?.resourceHandler());
    }

    // ── D-DOG.1.0c Phase 2A.1 — typed `sites` view-store ──
    //
    // Best-effort init.  No handler is registered in this phase: the
    // store sits as substrate for Phase 2A.4's ratify-handler rewrite,
    // which adds the lookup-or-mint call sites (`findByLookupKey` for
    // dedup-by-address, `getById` for "do we already have this cell?").
    // Constructing here means the store's address is stable for the
    // dispatcher's lifetime so the Phase 2A.4 retrofit is a one-line
    // pointer-pass — no wiring churn between phases.  Failure to open
    // the JSONL log is non-fatal (the daemon stays up; lookup-or-mint
    // would just run as if the file were empty).
    // W6.2 — sites_store LMDB init (needs repl_entity_cell_store).
    var sites_store: ?sites_store_fs_mod.SitesStore = null;
    defer if (sites_store) |*ss| ss.deinit();
    if (repl_entity_cell_store) |*ecs| {
        sites_store = sites_store_fs_mod.SitesStore.init(allocator, ecs, realClock) catch |e| blk: {
            try out.print("repl: failed to open sites store: {s} (graph-aware lookup-or-mint disabled)\n", .{@errorName(e)});
            break :blk null;
        };
    }
    // Silence unused-variable if no handler registers it yet — Phase 2A.4
    // turns this into a real call site.
    _ = &sites_store;

    // ── D-O5.followup-5 — typed `site_config` resource ──
    //
    // Whole-blob read + write of `<sites_dir>/<domain>/site.json` for
    // the helm SPA's editor view.  The REPL surface (`site config show
    // / set / validate`) routes through the same handler.  No store
    // dependency — the handler owns the on-disk file directly.
    const site_config_sites_dir_repl = sitesDir(allocator) catch |e| blk: {
        try out.print("repl: failed to resolve sites_dir: {s} (site config verbs disabled)\n", .{@errorName(e)});
        break :blk @as(?[]u8, null);
    };
    defer if (site_config_sites_dir_repl) |d| allocator.free(d);
    var site_config_handler: ?site_config_handler_mod.Handler = null;
    if (site_config_sites_dir_repl) |d| {
        site_config_handler = site_config_handler_mod.Handler.init(allocator, d);
        try disp.register(site_config_handler.?.resourceHandler());
    }

    // admin-create-cell Phase D.3 — generic cell.create resource.
    // Shares the same LmdbCellStore the entity stores use. The handler
    // is thin (encode + put); field validation lives in admin_cmds.zig.
    var cell_handler: ?cell_handler_mod.Handler = null;
    if (repl_entity_cell_store) |*ecs| {
        cell_handler = cell_handler_mod.Handler.init(allocator, ecs);
        try disp.register(cell_handler.?.resourceHandler());
    }

    const stdin_file = std.fs.File.stdin();
    while (true) {
        try out.print("> ", .{});
        // Flush captured buffer to real stdout before reading the next
        // line so the prompt appears.
        flushOutput(out);

        const line = readLine(allocator, stdin_file) catch |err| switch (err) {
            error.EndOfFile => {
                try out.print("\n", .{});
                flushOutput(out);
                return .ok;
            },
            else => return err,
        };
        defer allocator.free(line);

        // Persist to history before dispatch (post-dispatch persistence
        // would lose the line if the handler crashes — though no v0.1
        // command currently can crash the loop).
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len > 0) {
            repl_mod.appendHistory(allocator, data_dir, trimmed);
        }

        // ── Brain 5.2 — modal-prefix routing ───────────────────────────
        // When --llm is enabled AND the line starts with a modal verb
        // (`do `, `find `, `talk `), route the utterance through the
        // LLM adapter, show the parsed shape + a suggested REPL command
        // (when one exists), and require explicit confirmation before
        // dispatch. The trust boundary stays intact: the LLM never
        // dispatches anything itself; the operator types `y` or types
        // a different command, and any signing op triggers the wallet
        // engine's own confirmation gate (second layer of safety).
        if (llm_state) |s| {
            if (isModalPrefixed(trimmed)) {
                const dispatch_line = mediateModalLine(allocator, out, session, s, trimmed) catch |err| {
                    try out.print("[llm] mediation failed: {s}\n", .{@errorName(err)});
                    flushOutput(out);
                    continue;
                };
                defer if (dispatch_line) |dl| allocator.free(dl);
                if (dispatch_line == null) {
                    // Operator aborted; no dispatch.
                    flushOutput(out);
                    continue;
                }
                const exit = repl_mod.handleLine(session, out, dispatch_line.?) catch |err| {
                    try out.print("repl error: {s}\n", .{@errorName(err)});
                    flushOutput(out);
                    continue;
                };
                flushOutput(out);
                if (exit == .quit) return .ok;
                continue;
            }
        }

        const exit = repl_mod.handleLine(session, out, line) catch |err| {
            try out.print("repl error: {s}\n", .{@errorName(err)});
            flushOutput(out);
            continue;
        };
        flushOutput(out);
        if (exit == .quit) return .ok;
    }
}

fn isModalPrefixed(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "do ") or
        std.mem.startsWith(u8, line, "find ") or
        std.mem.startsWith(u8, line, "talk ");
}

/// Run an LLM mediation cycle: parse → preview → confirm → return the
/// command line to dispatch (or null if aborted). On any error, returns
/// it; the caller loops back to the prompt.
///
/// Audit-log pattern: every parse logs `module="llm" op="parse"` with
/// a short detail summarising the parsed modal/who/what; every
/// confirmed dispatch logs `module="llm" op="dispatch"`; every abort
/// logs `module="llm" op="abort"`.
fn mediateModalLine(
    allocator: std.mem.Allocator,
    out: *const Output,
    session: *repl_mod.Session,
    state: *LlmReplState,
    utterance: []const u8,
) !?[]u8 {
    const adapter = state.parseAdapter();
    const req = llm_adapter.ParseRequest{
        .utterance = utterance,
        .available_verbs = "status,modules,audit,call,headers,bearer,llm,help,exit",
        .context_hint = "",
    };
    const parsed = adapter.parse(allocator, req) catch |err| {
        const summary = try std.fmt.allocPrint(allocator, "parse failed: {s}", .{@errorName(err)});
        defer allocator.free(summary);
        session.audit.record(allocator, .{
            .module = "llm",
            .op = "parse",
            .result = .err,
            .detail = summary,
        }) catch {};
        try out.print("[llm] {s}\n", .{summary});
        return null;
    };
    defer {
        allocator.free(parsed.who);
        allocator.free(parsed.what);
        allocator.free(parsed.why);
    }

    // Audit the successful parse.
    const parse_summary = try std.fmt.allocPrint(
        allocator,
        "modal={s} who={s} what={s} conf={d:.2}",
        .{ parsed.modal.toString(), parsed.who, parsed.what, parsed.confidence },
    );
    defer allocator.free(parse_summary);
    session.audit.record(allocator, .{
        .module = "llm",
        .op = "parse",
        .result = .ok,
        .detail = parse_summary,
    }) catch {};

    try out.print("[llm] parsed: {s}\n", .{parse_summary});

    const suggestion = llm_suggester.suggest(allocator, parsed) catch |err| {
        try out.print("[llm] suggester error: {s}\n", .{@errorName(err)});
        return null;
    };
    defer llm_suggester.freeSuggestion(allocator, suggestion);

    switch (suggestion) {
        .line => |suggested| {
            try out.print("[llm] suggested: {s}\n", .{suggested});
            try out.print("[llm] dispatch? [y/N/edit] ", .{});
            flushOutput(out);
            const answer = try readLine(allocator, std.fs.File.stdin());
            defer allocator.free(answer);
            const trimmed_answer = std.mem.trim(u8, answer, " \t\r\n");
            if (eqIgnoreCase(trimmed_answer, "y") or eqIgnoreCase(trimmed_answer, "yes")) {
                session.audit.record(allocator, .{
                    .module = "llm",
                    .op = "dispatch",
                    .result = .ok,
                    .detail = suggested,
                }) catch {};
                return try allocator.dupe(u8, suggested);
            }
            if (eqIgnoreCase(trimmed_answer, "edit") or eqIgnoreCase(trimmed_answer, "e")) {
                return try promptManualLine(allocator, out, session, suggested);
            }
            session.audit.record(allocator, .{
                .module = "llm",
                .op = "abort",
                .result = .denied,
                .detail = parse_summary,
            }) catch {};
            try out.print("[llm] aborted\n", .{});
            return null;
        },
        .no_suggestion => |hint| {
            try out.print("[llm] {s}\n", .{hint});
            return try promptManualLine(allocator, out, session, "");
        },
    }
}

fn promptManualLine(
    allocator: std.mem.Allocator,
    out: *const Output,
    session: *repl_mod.Session,
    initial: []const u8,
) !?[]u8 {
    if (initial.len > 0) {
        try out.print("[llm] type a command (or empty to abort) — suggestion was: {s}\n> ", .{initial});
    } else {
        try out.print("[llm] type a command (or empty to abort)\n> ", .{});
    }
    flushOutput(out);
    const typed = try readLine(allocator, std.fs.File.stdin());
    const trimmed = std.mem.trim(u8, typed, " \t\r\n");
    if (trimmed.len == 0) {
        allocator.free(typed);
        session.audit.record(allocator, .{
            .module = "llm",
            .op = "abort",
            .result = .denied,
            .detail = "empty manual entry",
        }) catch {};
        try out.print("[llm] aborted\n", .{});
        return null;
    }
    session.audit.record(allocator, .{
        .module = "llm",
        .op = "dispatch",
        .result = .ok,
        .detail = trimmed,
    }) catch {};
    return typed;
}

fn eqIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (std.ascii.toLower(x) != std.ascii.toLower(y)) return false;
    return true;
}

fn readLine(allocator: std.mem.Allocator, file: std.fs.File) ![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);
    var byte: [1]u8 = undefined;
    while (true) {
        const n = file.read(&byte) catch |err| switch (err) {
            else => return err,
        };
        if (n == 0) {
            if (buf.items.len == 0) return error.EndOfFile;
            break;
        }
        if (byte[0] == '\n') break;
        try buf.append(allocator, byte[0]);
    }
    return buf.toOwnedSlice(allocator);
}

// ─────────────────────────────────────────────────────────────────────
// WSITE1 — site management
// ─────────────────────────────────────────────────────────────────────



```
