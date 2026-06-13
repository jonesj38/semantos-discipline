---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cli/serve.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.285456+00:00
---

# runtime/semantos-brain/src/cli/serve.zig

```zig
// cmdServe (WSITE2 — `brain serve`) extracted from src/cli.zig as
// Move 11 (final big move) of the cli-modularize refactor.  Pure
// code motion: no behaviour change.
//
// Owns: cmdServe (the HTTP/WSS site server entry-point), runUnixServer,
// PushBrokerBridge, countDynamicRoutes, DynamicRuntime, setUpDynamicRuntime,
// resolveDefaultConfigPath, stubSpvLookup, and the local
// realClock/daemonErrorAsZigError/wire_errbody helpers cmdServe uses
// inline.

const std = @import("std");
const cli_common = @import("common.zig");
const cli_site = @import("site.zig");
const cli_device = @import("device.zig");
const cli_repl = @import("repl.zig");
const cli_lifecycle = @import("lifecycle.zig");
const config = @import("config");
const module_loader = @import("module_loader");
const instance_manager = @import("instance_manager");
const audit_log_mod = @import("audit_log");
const bearer_tokens_mod = @import("bearer_tokens");
const broker_mod = @import("broker");
const dispatcher_mod = @import("dispatcher");
const runner_mod = @import("runner");
const repl_mod = @import("repl");
const slot_store_fs_mod = @import("slot_store_fs");
const state_store_fs_mod = @import("state_store_fs");
const header_store_fs_mod = @import("header_store_fs");
const lmdb_mod = @import("lmdb");
const lmdb_config_mod = @import("lmdb_config");
const lmdb_cell_store_mod = @import("lmdb_cell_store");
const site_config_mod = @import("site_config");
const site_server_mod = @import("site_server");
const http_route_registry_mod = @import("http_route_registry");
const store_registry_mod = @import("store_registry");
const wss_wallet_mod = @import("wss_wallet");
const wallet_op_http_mod = @import("wallet_op_http");
const payment_ledger_mod = @import("payment_ledger");
const payment_verifier_mod = @import("payment_verifier");
const output_store_mod = @import("output_store");
const output_store_fs_mod = @import("output_store_fs");
const headers_handler_mod = @import("headers_handler");
const bearer_tokens_handler_mod = @import("bearer_tokens_handler");
const unix_socket_transport = @import("unix_socket");
const identity_certs_mod = @import("identity_certs");
const identity_certs_handler_mod = @import("identity_certs_handler");
const extensions_mod = @import("extensions");
// C5 PR-4b-1 — cartridge-extension dispatch seam.  See
// docs/design/BRAIN-EXTENSION-LOADER.md §5 boot loader loop.  Called
// at end of cmdServe after all substrate handlers register +
// before server.serve() starts accepting.  Today no cartridge
// handler has migrated over the seam (cartridge_seam.registrations
// is empty); the call is a no-op except for the forward-compat
// warning path if any cartridge.json declares an unknown handler.
const cartridge_seam = @import("cartridge_seam");
const extension_manifest_loader = @import("extension_manifest_loader");
// C4 CW-3 — operator profile (operator-policy seam): loaded per-domain at serve
// boot + threaded into CartridgeDeps so the cartridge chat route binds its
// endpoint to operator policy.
const operator_profile_mod = @import("operator_profile");
const operator_profile_loader_mod = @import("operator_profile_loader");
// DO-1 — the `do` operator-action grammar: the registry + the substrate `site`
// resource (chat-widget policy), surfaced over the HTTP REPL for the helm.
const do_verb_registry_mod = @import("do_verb_registry");
// C4 PR-R3 — cartridge REPL verb registry (find jobs / find attention / FSM
// transitions / conversation verbs). serve.zig must attach this to the
// repl_session AND pass it through CartridgeDeps, else cartridge verbs are
// unreachable over repl.eval (the unified-channel REPL) — they only worked in
// the CLI repl, which does wire it. Without this the oddjobz operator loop
// can't ride the channel.
const repl_verb_registry_mod = @import("repl_verb_registry");
const site_handler_mod = @import("site_handler");
const llm_complete_handler_mod = @import("llm_complete_handler");
const llm_transcribe_audio_handler_mod = @import("llm_transcribe_audio_handler");
const llm_embed_handler_mod = @import("llm_embed_handler");
const llm_adapter = @import("llm_adapter");
const llm_http_adapter_mod = @import("llm_http_adapter");
const device_pair_mod = @import("device_pair");
const sites_handler_mod = @import("sites_handler");
const site_config_handler_mod = @import("site_config_handler");
const cell_handler_mod = @import("cell_handler");
const qr_render_mod = @import("qr_render");
const device_pair_http_mod = @import("device_pair_http");
const tenant_manifest_mod = @import("tenant_manifest");
const signed_bundle_transport_mod = @import("signed_bundle_transport");
const extension_subscriber_mod = @import("extension_subscriber");
const extension_subscribe_mod = @import("extension_subscribe");
// C4 PR-I2 — jobs_store_fs import removed (last serve use, the twilio-inbound
// callbacks, moved to the oddjobz cartridge).
const helm_event_broker_mod = @import("helm_event_broker");
// PR-3a-bridge-2c — file-based bridge from broker cell.created → bun
// anchor-runner.ts → real BSV broadcast.  See module doc-comment.
const anchor_queue_writer_mod = @import("anchor_queue_writer");
// AnchorRunnerSupervisor — long-lived child-process supervisor for
// the anchor-runner.ts daemon. Opt-in via BRAIN_ANCHOR_RUNNER=1.
const anchor_runner_supervisor_mod = @import("anchor_runner_supervisor");
// PR-3a-bridge-3 — companion reader: tails the runner's confirmations
// file + emits audit-log entries per broadcast outcome.
const anchor_confirmation_reader_mod = @import("anchor_confirmation_reader");
// C4 PR-I2 — customers_store_fs import removed (last serve use, the twilio-inbound
// callbacks, moved to the oddjobz cartridge).
const visits_store_fs_mod = @import("visits_store_fs");
// C4 PR-H2b-1 — the quotes/estimates/invoices/attachments/leads store modules
// + all the oddjobz dispatcher-handler modules are now imported by the oddjobz
// cartridge's registration.zig (which owns their construction), not here. The
// jobs/customers/visits/sites store modules stay imported: serve's remaining
// store consumers still name those types.
const intent_cell_lmdb_store_mod = @import("intent_cell_lmdb_store");
const intent_cells_handler_mod = @import("intent_cells_handler");
const intent_action_router_mod = @import("intent_action_router");
const visit_rollup_router_mod = @import("visit_rollup_router");
const quote_seed_router_mod = @import("quote_seed_router");
const sites_store_fs_mod = @import("sites_store_fs");
const oddjobz_ratify_handler_mod = @import("oddjobz_ratify_handler");
const verb_dispatcher_mod = @import("verb_dispatcher");
const oddjobz_ratify_walker_mod = @import("oddjobz_ratify_walker");
// Universal multi-cartridge boot (replaces the per-cartridge jambox
// store/state/registerAll hand-wiring). docs/design/UNIVERSAL-CARTRIDGE-BOOT.md
const cartridge_boot_mod = @import("cartridge_boot");
const chess_native_bridge = @import("chess_native_bridge");
const entity_encode_walker_mod = @import("entity_encode_walker");
const content_store_local_fs_mod = @import("content_store_local_fs");
const overdue_jobs_walker_mod = @import("overdue_jobs_walker");
const pipeline_gaps_walker_mod = @import("pipeline_gaps_walker");
const manifest_registry_mod = @import("manifest_registry");
const cell_query_handler_mod = @import("cell_query_handler");
const cell_decoder_registry_mod = @import("cell_decoder_registry");
const wss_rpc_registry_mod = @import("wss_rpc_registry");
const wss_rpc_methods = @import("wss_rpc_methods");
const attention_source_registry_mod = @import("attention_source_registry");
const attention_poll_handler_mod = @import("attention_poll_handler");
// SH7 / D15 — shell-native attention source JSON builders.
const shell_attention_sources_mod = @import("shell_attention_sources");
const ratify_builder_registry_mod = @import("ratify_builder_registry");
const ratify_submit_handler_mod = @import("ratify_submit_handler");
const oddjobz_attention_handler_mod = @import("oddjobz_attention_handler");
const hat_bkds_mod = @import("hat_bkds");
const hat_registry_mod = @import("hat_registry");
const attachment_blobs_fs_mod = @import("attachment_blobs_fs");
// C4 PR-H7b — attachments_upload_http import removed (upload moved to the cartridge).
// C4 PR-H6 — attachments_blob_http import removed (blob GET moved to the cartridge).
const cell_raw_http_mod = @import("cell_raw_http");
const cells_mint_http_mod = @import("cells_mint_http");
const betterment_sweep_http_mod = @import("betterment_sweep_http");
const cartridge_cell_boot_mod = @import("cartridge_cell_boot");
const cells_mint_handler_mod = @import("cells_mint_handler");
// PR-3e — bsv-spv-verify-specific ScriptContextBuilder + the HeaderStore
// interface module (re-exported via the cell-engine-header-store-mod).
// Used to wire Handler.setContextBuilder at boot.
const cells_mint_spv_context_mod = @import("cells_mint_spv_context");
// C4 PR-E2 — cells_mint_mnca_context moved to the mnca CARTRIDGE
// (cartridges/mnca/brain/zig/); it registers its mint-context builder via
// the cartridge seam at boot, so serve.zig no longer imports or names it.
const cell_engine_header_store_mod = @import("header_store");
const info_http_mod = @import("info_http");
const voice_extract_http_mod = @import("voice_extract_http");
const push_register_http_mod = @import("push_register_http");
// C4 PR-I1/I2 — conversation_send_http + twilio_adapter + twilio_inbound_http
// imports removed (the SMS adapter moved to the oddjobz cartridge).
// C4 PR-H3 — search_contacts_http import removed (route moved to the cartridge).
const contact_book_lmdb_mod = @import("contact_book_lmdb");
const contacts_http_mod = @import("contacts_http");
const messagebox_http_mod = @import("messagebox_http");
const messagebox_lmdb_mod = @import("messagebox_lmdb");
const session_addr_mod = @import("session_addr");
const ipv6_iface_mod = @import("ipv6_iface");
const intent_http_mod = @import("intent_http");
const identity_http_mod = @import("identity_http");
const loom_store_http_mod = @import("loom_store_http");
const flow_http_mod = @import("flow_http");
const voice_extract_shell_mod = @import("voice_extract_shell");
const image_extract_http_mod = @import("image_extract_http");
const image_extract_shell_mod = @import("image_extract_shell");
const audio_extract_http_mod = @import("audio_extract_http");
const audio_extract_shell_mod = @import("audio_extract_shell");
const oddjobz_event_bus_mod = @import("oddjobz_event_bus");
const nats_event_bridge_mod = @import("nats_event_bridge");
const apns_dispatcher_mod = @import("apns_dispatcher");
const fcm_dispatcher_mod = @import("fcm_dispatcher");
const unifiedpush_dispatcher_mod = @import("unifiedpush_dispatcher");
const push_dispatcher_mod = @import("push_dispatcher");
const push_http_transport_mod = @import("push_http_transport");
const pask_snapshot_store_lmdb_mod = @import("pask_snapshot_store_lmdb");
const nats_client_mod = @import("nats_client");
const nats_event_producer_mod = @import("nats_event_producer");
const bkds_mod = @import("bkds");

const Output = cli_common.Output;
const ExitCode = cli_common.ExitCode;
const resolveDataDir = cli_common.resolveDataDir;
const jsonStringField = cli_common.jsonStringField;
const flushOutput = cli_common.flushOutput;
const realClock = cli_common.realClock;
const daemonErrorAsZigError = cli_common.daemonErrorAsZigError;
const siteConfigPath = cli_site.siteConfigPath;
const readOperatorPriv = cli_device.readOperatorPriv;
const ReplBackend = cli_repl.ReplBackend;

// W0.6 — derive a 32-bit domain_flag from a domain string via FNV-1a.
// This is the W0.6 pragmatic synthesis; M-level work will read the
// flag from site.json when the operator has set one explicitly.  The
// well-known flags (oddjobz=0x000101, carpenter=0x000102, etc.) are
// NOT derived this way — they are assigned by the platform.  This
// function is used ONLY for operator-provisioned custom domains that
// haven't been assigned a flag in the cell-engine registry yet.
fn domainToFlag(domain: []const u8) u32 {
    // FNV-1a 32-bit: offset_basis=2166136261, prime=16777619.
    var hash: u32 = 2166136261;
    for (domain) |byte| {
        hash ^= @as(u32, byte);
        hash *%= 16777619;
    }
    // Mask to 24 bits so flags stay in the operator-defined range
    // (0x010000..0xFFFFFF); platform-assigned flags live in 0x0001xx.
    return (hash & 0x00FFFFFF) | 0x010000;
}

// W0.6 — stub capability-change handler wired into startCapabilityWatcher.
// M3.5 will replace this with a live reload from the capability_utxo
// change feed.
fn onCapabilityChange(domain_flag: u32, caps: []const []const u8) void {
    _ = domain_flag;
    _ = caps;
    // No-op stub; the real implementation polls Pravega (M3.5).
}

/// T6 — ISO-8601 timestamp helper for push_register_http.Acceptor.
/// Mirrors the apns/fcm/unifiedpush dispatchers' defaultNowIso so the
/// registered_at field has the same wire shape everywhere.
fn defaultPushRegisterNowIso(allocator: std.mem.Allocator) anyerror![]u8 {
    const ts = std.time.timestamp();
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(ts) };
    const day_seconds = epoch_seconds.getDaySeconds();
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    return std.fmt.allocPrint(
        allocator,
        "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z",
        .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        },
    );
}

// ─── W2 conv-send acceptor helpers ─────────────────────────────────────────
//
// These bridge the pure-orchestration conversation_send_http.Acceptor
// to the brain's running services.  Each is a thin closure that the
// acceptor invokes via function pointer.

const ConvSendCtx = struct {
    bearer_tokens: *bearer_tokens_mod.TokenStore,
};

// C4 PR-J4 — attention-source collect thunks: cast the opaque ctx (the
// oddjobz_attention handler) + emit one bucket's signal array. Registered into
// the attention-source registry under namespace "oddjobz".
fn oddjobzDispatchSource(ctx: *anyopaque, allocator: std.mem.Allocator, limit: usize) anyerror![]u8 {
    const h: *oddjobz_attention_handler_mod.Handler = @ptrCast(@alignCast(ctx));
    return h.collectDispatchSignalsJson(allocator, limit);
}
fn oddjobzMessageSource(ctx: *anyopaque, allocator: std.mem.Allocator, limit: usize) anyerror![]u8 {
    const h: *oddjobz_attention_handler_mod.Handler = @ptrCast(@alignCast(ctx));
    return h.collectMessageSignalsJson(allocator, limit);
}
fn oddjobzJobSource(ctx: *anyopaque, allocator: std.mem.Allocator, limit: usize) anyerror![]u8 {
    const h: *oddjobz_attention_handler_mod.Handler = @ptrCast(@alignCast(ctx));
    return h.collectJobSignalsJson(allocator, limit);
}

// SH7 / D15 — shell-native attention sources (namespace "shell"). ctx for the
// identity source; the token store outlives the server (cmdServe scope).
const ShellAttnCtx = struct {
    token_store: ?*bearer_tokens_mod.TokenStore = null,
    /// No recovery-envelope store on origin/main (C6b future) → false → the
    /// standing recovery-setup nudge fires.
    has_recovery: bool = false,
};

fn shellIdentitySource(ctx: *anyopaque, allocator: std.mem.Allocator, limit: usize) anyerror![]u8 {
    const c: *ShellAttnCtx = @ptrCast(@alignCast(ctx));
    const store = c.token_store orelse
        return shell_attention_sources_mod.buildShellIdentityJson(allocator, &.{}, c.has_recovery, std.time.timestamp(), limit);
    const recs = store.list(allocator) catch
        return shell_attention_sources_mod.buildShellIdentityJson(allocator, &.{}, c.has_recovery, store.clock(), limit);
    defer if (recs.len > 0) allocator.free(recs);
    const te = allocator.alloc(shell_attention_sources_mod.TokenExpiry, recs.len) catch
        return shell_attention_sources_mod.buildShellIdentityJson(allocator, &.{}, c.has_recovery, store.clock(), limit);
    defer allocator.free(te);
    for (recs, 0..) |_, i| te[i] = .{
        .id = recs[i].id[0..],
        .label = recs[i].label,
        .expires_at = recs[i].expires_at,
    };
    return shell_attention_sources_mod.buildShellIdentityJson(allocator, te, c.has_recovery, store.clock(), limit);
}

fn shellRatifySource(_: *anyopaque, allocator: std.mem.Allocator, _: usize) anyerror![]u8 {
    // Placeholder — no queryable pending-ratification queue on origin/main yet.
    return shell_attention_sources_mod.buildPendingRatificationsJson(allocator);
}

/// C4 PR-J5 — ratify builder submit thunk: adapts the oddjobz ratify handler
/// onto the generic RatifyBuilder.submit vtable. Reuses the existing walker
/// (handleRatify → serialise wire blob); the DispatchError coerces to anyerror.
fn oddjobzRatifySubmit(ctx: *anyopaque, allocator: std.mem.Allocator, params_json: []const u8) anyerror![]u8 {
    return oddjobz_ratify_walker_mod.walker(allocator, ctx, params_json);
}

fn convSendIsBearerValid(ctx: ?*anyopaque, bearer_hex: []const u8) bool {
    const self: *ConvSendCtx = @ptrCast(@alignCast(ctx.?));
    // verifyHex requires 64 hex chars + token-store lookup; any error
    // (bad format, unknown, revoked, expired) is treated as invalid.
    _ = self.bearer_tokens.verifyHex(bearer_hex) catch return false;
    return true;
}

// C4 PR-I1 — the conversation-send helpers (ConvSendLookupCtx +
// convSendLookupContact + convSendPersistMessage + ProdSenderCtx +
// convSendProdSender) moved into the oddjobz cartridge's registration.zig: the
// outbound-SMS route is now served over the route registry. ConvSendCtx +
// convSendIsBearerValid stay here (shared bearer validation for the contacts /
// messagebox / attention / intent acceptors).

// C4 PR-H3 — the W3 search-contacts helpers (SearchContactsCtx +
// searchListCustomers + searchListSites) moved into the oddjobz cartridge's
// registration.zig: the route is now served over the route registry, reading
// the cartridge-owned customers + sites stores.

// ── P1c — Twilio inbound SMS webhook context + adapter fns ──────────────────

// C4 PR-I2 — the twilio-inbound helpers (TwilioInboundCtx + twilioInboundFind
// Customer/FindOpenJob/AuthorizeJob) moved into the oddjobz cartridge's
// registration.zig: the inbound webhook is now served over the route registry.

// ── D-brain-loom-store-api — Dispatcher adapter fns ─────────────────────────
// Bridge between loom_store_http fn-pointer API and the brain dispatcher.
// Both fns dispatch in-process as root (no network roundtrip; same allocator).

fn loomIsBearerValid(ctx: ?*anyopaque, bearer: []const u8) bool {
    const ts: *bearer_tokens_mod.TokenStore = @ptrCast(@alignCast(ctx.?));
    _ = ts.verifyHex(bearer) catch return false;
    return true;
}

fn loomFindObjects(
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    resource_type: []const u8,
) anyerror![]u8 {
    const disp: *dispatcher_mod.Dispatcher = @ptrCast(@alignCast(ctx.?));
    const dispatch_ctx: dispatcher_mod.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "http_loom" },
    };
    var result = disp.dispatch(&dispatch_ctx, resource_type, "find", "{}") catch |err| {
        // unknown_resource / unknown_command → empty array (graceful)
        if (err == dispatcher_mod.DispatchError.unknown_resource or
            err == dispatcher_mod.DispatchError.unknown_command)
        {
            return allocator.dupe(u8, "[]");
        }
        return err;
    };
    defer result.deinit();
    if (result.payload.len == 0) return allocator.dupe(u8, "[]");
    return allocator.dupe(u8, result.payload);
}

fn loomFindObjectById(
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    resource_type: []const u8,
    id: []const u8,
) anyerror!?[]u8 {
    const disp: *dispatcher_mod.Dispatcher = @ptrCast(@alignCast(ctx.?));
    const dispatch_ctx: dispatcher_mod.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "http_loom" },
    };
    const payload = try std.fmt.allocPrint(allocator, "{{\"id\":\"{s}\"}}", .{id});
    defer allocator.free(payload);
    var result = disp.dispatch(&dispatch_ctx, resource_type, "find_by_id", payload) catch |err| {
        if (err == dispatcher_mod.DispatchError.unknown_resource or
            err == dispatcher_mod.DispatchError.unknown_command)
        {
            return null;
        }
        return err;
    };
    defer result.deinit();
    if (result.payload.len == 0) return null;
    return @as(?[]u8, try allocator.dupe(u8, result.payload));
}

// ── D-brain-contacts-api — ContactBookStore adapter fns ─────────────────────
// Bridge between contacts_http fn-pointer API and contact_book_lmdb_mod types.

fn contactsListAll(ctx: ?*anyopaque, allocator: std.mem.Allocator) anyerror![]contacts_http_mod.Contact {
    const store: *contact_book_lmdb_mod.ContactBookStore = @ptrCast(@alignCast(ctx.?));
    const raw = try store.listContacts(allocator);
    defer allocator.free(raw);
    const result = try allocator.alloc(contacts_http_mod.Contact, raw.len);
    for (raw, 0..) |c, i| {
        result[i] = .{
            .certId = c.certId, .publicKey = c.publicKey, .displayName = c.displayName,
            .email = c.email, .source = c.source, .addedAt = c.addedAt, .updatedAt = c.updatedAt,
        };
    }
    return result;
}

fn contactsGetOne(ctx: ?*anyopaque, certId: []const u8) ?contacts_http_mod.Contact {
    const store: *contact_book_lmdb_mod.ContactBookStore = @ptrCast(@alignCast(ctx.?));
    const c = store.getContact(certId) orelse return null;
    return contacts_http_mod.Contact{
        .certId = c.certId, .publicKey = c.publicKey,
        .displayName = c.displayName, .email = c.email,
        .source = c.source, .addedAt = c.addedAt, .updatedAt = c.updatedAt,
    };
}

fn contactsAdd(
    ctx: ?*anyopaque,
    certId: []const u8,
    publicKey: []const u8,
    displayName: []const u8,
    email: ?[]const u8,
) anyerror!contacts_http_mod.Contact {
    const store: *contact_book_lmdb_mod.ContactBookStore = @ptrCast(@alignCast(ctx.?));
    const c = try store.addContact(certId, publicKey, displayName, email);
    return contacts_http_mod.Contact{
        .certId = c.certId, .publicKey = c.publicKey,
        .displayName = c.displayName, .email = c.email,
        .source = c.source, .addedAt = c.addedAt, .updatedAt = c.updatedAt,
    };
}

fn contactsAddEdge(
    ctx: ?*anyopaque,
    certId: []const u8,
    edgeId: []const u8,
    edgeType: []const u8,
    signingKeyIndex: i64,
    recoveryPolicy: []const u8,
) anyerror!contacts_http_mod.EdgeRecord {
    const store: *contact_book_lmdb_mod.ContactBookStore = @ptrCast(@alignCast(ctx.?));
    const e = try store.addEdge(.{
        .certId = certId, .edgeId = edgeId, .edgeType = edgeType,
        .signingKeyIndex = signingKeyIndex, .recoveryPolicy = recoveryPolicy,
    });
    return contacts_http_mod.EdgeRecord{
        .edgeId = e.edgeId, .certId = e.certId, .edgeType = e.edgeType,
        .signingKeyIndex = e.signingKeyIndex, .recoveryPolicy = e.recoveryPolicy,
        .revokedAt = e.revokedAt, .createdAt = e.createdAt,
    };
}

fn contactsRevokeEdge(ctx: ?*anyopaque, certId: []const u8, edgeId: []const u8) anyerror!void {
    const store: *contact_book_lmdb_mod.ContactBookStore = @ptrCast(@alignCast(ctx.?));
    try store.revokeEdge(certId, edgeId);
}

//
// The intent acceptor delegates classify and taxonomy to the dispatcher's
// intent.classify / intent.taxonomy_snapshot commands.  Bridges the DI
// fn-pointer API to the in-process dispatcher.

fn intentClassify(
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    text: []const u8,
    source: ?[]const u8,
) anyerror![]u8 {
    const disp: *dispatcher_mod.Dispatcher = @ptrCast(@alignCast(ctx.?));
    const dispatch_ctx: dispatcher_mod.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "http_intent" },
    };

    // Build a minimal JSON payload: {"text":"...","source":"..."}.
    var payload_buf: std.ArrayListUnmanaged(u8) = .{};
    defer payload_buf.deinit(allocator);
    try payload_buf.appendSlice(allocator, "{\"text\":");
    try appendJsonString(allocator, &payload_buf, text);
    if (source) |src| {
        try payload_buf.appendSlice(allocator, ",\"source\":");
        try appendJsonString(allocator, &payload_buf, src);
    }
    try payload_buf.append(allocator, '}');

    var result = try disp.dispatch(&dispatch_ctx, "intent", "classify", payload_buf.items);
    defer result.deinit();

    // Result payload is the JSON response from the dispatcher.
    if (result.payload.len == 0) return error.EmptyDispatchResponse;
    return allocator.dupe(u8, result.payload);
}

fn intentTaxonomySnapshot(
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]u8 {
    const disp: *dispatcher_mod.Dispatcher = @ptrCast(@alignCast(ctx.?));
    const dispatch_ctx: dispatcher_mod.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "http_intent" },
    };

    var result = try disp.dispatch(&dispatch_ctx, "intent", "taxonomy_snapshot", "{}");
    defer result.deinit();

    if (result.payload.len == 0) return error.EmptyDispatchResponse;
    return allocator.dupe(u8, result.payload);
}

/// Append a JSON-escaped string literal (with surrounding quotes) to buf.
fn appendJsonString(
    allocator: std.mem.Allocator,
    buf: *std.ArrayListUnmanaged(u8),
    s: []const u8,
) !void {
    try buf.append(allocator, '"');
    for (s) |ch| {
        switch (ch) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            else => try buf.append(allocator, ch),
        }
    }
    try buf.append(allocator, '"');
}


// ─── D-brain-identity-store-api helpers ──────────────────────────────────────
//
// Bridge between identity_http fn-pointer API and bearer_tokens_mod.
// For V1, hat info is derived from the TokenRecord (label, issued_at,
// fingerprint).  cert_id linkage is deferred to T7 (brain-auth gap).
// bearer_tokens_mod already imported at top-level.

const IdentityCtx = struct {
    token_store: *bearer_tokens_mod.TokenStore,
    allocator: std.mem.Allocator,
};

// identityJsonString → appendJsonString (same implementation; merged after
// D-brain-intent-classifier-api landed the shared helper on main).
const identityJsonString = appendJsonString;

fn identityGetActiveHat(
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    bearer: []const u8,
) anyerror!?[]u8 {
    const self: *IdentityCtx = @ptrCast(@alignCast(ctx.?));
    const record = self.token_store.verifyHex(bearer) catch return null;

    // Build JSON from TokenRecord fields.  cert_id is empty until T7.
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);

    // id = first 32 hex chars of fingerprint (stable UUIDv4-ish key).
    try buf.appendSlice(allocator, "{\"id\":\"");
    try buf.appendSlice(allocator, record.fingerprint[0..@min(32, record.fingerprint.len)]);
    try buf.appendSlice(allocator, "\",\"hat_id\":\"");
    try buf.appendSlice(allocator, record.id[0..@min(32, record.id.len)]);
    try buf.appendSlice(allocator, "\",\"hat_name\":");
    try identityJsonString(allocator, &buf, record.label);
    try buf.appendSlice(allocator, ",\"cert_id\":\"\",\"bearer_fingerprint\":\"");
    try buf.appendSlice(allocator, &record.fingerprint);
    var ts_buf: [32]u8 = undefined;
    try buf.appendSlice(allocator,
        "\",\"brain_base_url\":\"\",\"color_hex\":\"\",\"logged_in_at\":");
    try buf.appendSlice(allocator, try std.fmt.bufPrint(&ts_buf, "{d}", .{record.issued_at * 1000}));
    try buf.appendSlice(allocator, ",\"last_used_at\":");
    try buf.appendSlice(allocator, try std.fmt.bufPrint(&ts_buf, "{d}", .{record.issued_at * 1000}));
    try buf.appendSlice(allocator, ",\"is_active\":true}");

    return @as(?[]u8, try buf.toOwnedSlice(allocator));
}

fn identityListHats(
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
) anyerror![]u8 {
    const self: *IdentityCtx = @ptrCast(@alignCast(ctx.?));
    const tokens = try self.token_store.list(allocator);
    defer allocator.free(tokens);

    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, "{\"hats\":[");
    for (tokens, 0..) |tok, i| {
        if (i != 0) try buf.append(allocator, ',');
        var ts_buf: [32]u8 = undefined;
        try buf.appendSlice(allocator, "{\"id\":\"");
        try buf.appendSlice(allocator, tok.fingerprint[0..@min(32, tok.fingerprint.len)]);
        try buf.appendSlice(allocator, "\",\"hat_id\":\"");
        try buf.appendSlice(allocator, tok.id[0..@min(32, tok.id.len)]);
        try buf.appendSlice(allocator, "\",\"hat_name\":");
        try identityJsonString(allocator, &buf, tok.label);
        try buf.appendSlice(allocator,
            ",\"cert_id\":\"\",\"bearer_fingerprint\":\"\",\"brain_base_url\":\"\",\"color_hex\":\"\",\"logged_in_at\":");
        try buf.appendSlice(allocator, try std.fmt.bufPrint(&ts_buf, "{d}", .{tok.issued_at * 1000}));
        try buf.appendSlice(allocator, ",\"last_used_at\":");
        try buf.appendSlice(allocator, try std.fmt.bufPrint(&ts_buf, "{d}", .{tok.issued_at * 1000}));
        try buf.appendSlice(allocator, ",\"is_active\":false}");
    }
    try buf.appendSlice(allocator, "]}");
    return buf.toOwnedSlice(allocator);
}

// C4 PR-I1 — convSendProdSender (the std.http.Client Twilio sender) moved into
// the oddjobz cartridge's registration.zig with the conversation-send route.

// ── D-network-messagebox-first-class — event emit bridge ────────────────────
//
// After a message is stored by /api/v1/messages/send, we fan-out a
// "messagebox.received" event to every /api/v1/events WSS subscriber so the
// phone gets a push notification without polling.
//
// Wire shape (reuses JobStateChangedEvent on the Dart side):
//   job_id     = "messagebox.received"   (sentinel string)
//   cell_id    = <32-char hex message ID>
//   from_state = ""
//   to_state   = "signed" | "encrypted"
//   ts_ms      = receipt timestamp
//   hat_id     = brain domain (e.g. "oddjobtodd.info")

const MessageboxEmitCtx = struct {
    bus: *oddjobz_event_bus_mod.OddjobzEventBus,
    hat_id: []const u8,
};

fn messageboxEmitEvent(
    ctx: ?*anyopaque,
    msg_id: *const [32]u8,
    _: []const u8, // recipient_hex — not used in the event frame
    kind: messagebox_http_mod.MessageKind,
    ts_ms: i64,
) void {
    const self: *MessageboxEmitCtx = @ptrCast(@alignCast(ctx.?));
    const kind_str: []const u8 = switch (kind) {
        .signed => "signed",
        .encrypted => "encrypted",
    };
    // ts_ms is i64 (milliTimestamp); bus.publish takes u64 — clamp negatives
    // (which can't happen in practice) to 0.
    const ts_u64: u64 = @intCast(@max(0, ts_ms));
    self.bus.publish("messagebox.received", msg_id, "", kind_str, ts_u64, self.hat_id);
}

// ── D-brain-flow-runner-api — in-memory run store ───────────────────────────
//
// V1: arena-backed StringHashMap; state is lost on restart.  Phase-2 will
// add durable storage (LMDB or a dedicated NDJSON append log).
//
// All strings in FlowRunRecord that are stored persistently (run_id,
// flow_id, current_step) are duped into the arena allocator so they
// outlive the call frame.  The `status` field always points to a string
// literal ("running", "completed", "cancelled", "failed") and is never
// freed.

const FlowRunRecord = struct {
    run_id: []const u8, // arena-owned
    flow_id: []const u8, // arena-owned
    status: []const u8, // string literal
    current_step: []const u8, // arena-owned; "start" until phase-2 flow defs land
};

const FlowRunStore = struct {
    map: std.StringHashMap(FlowRunRecord),
    allocator: std.mem.Allocator, // arena allocator
    next_id: u64 = 0,

    fn init(arena_alloc: std.mem.Allocator) FlowRunStore {
        return .{
            .map = std.StringHashMap(FlowRunRecord).init(arena_alloc),
            .allocator = arena_alloc,
            .next_id = 0,
        };
    }

    /// Create a new run; returns owned JSON (caller frees via out_alloc).
    fn startRun(
        self: *FlowRunStore,
        out_alloc: std.mem.Allocator,
        flow_id: []const u8,
        context_json: []const u8,
    ) ![]u8 {
        _ = context_json; // V1: context stored in flow def (phase-2); ignored here
        self.next_id += 1;
        const run_id = try std.fmt.allocPrint(self.allocator, "run-{d}", .{self.next_id});
        const flow_id_owned = try self.allocator.dupe(u8, flow_id);
        const rec = FlowRunRecord{
            .run_id = run_id,
            .flow_id = flow_id_owned,
            .status = "running",
            .current_step = "start",
        };
        try self.map.put(run_id, rec);
        return serializeRecord(out_alloc, rec);
    }

    /// Return current state JSON or null when run_id is unknown.
    fn getState(
        self: *FlowRunStore,
        out_alloc: std.mem.Allocator,
        run_id: []const u8,
    ) !?[]u8 {
        const rec = self.map.get(run_id) orelse return null;
        return @as(?[]u8, try serializeRecord(out_alloc, rec));
    }

    /// Advance / approve / cancel a run; returns updated state JSON or null.
    fn stepRun(
        self: *FlowRunStore,
        out_alloc: std.mem.Allocator,
        run_id: []const u8,
        action: []const u8,
        payload_json: []const u8,
    ) !?[]u8 {
        _ = payload_json; // V1: step payload ignored; phase-2 will thread it into guard eval
        const rec_ptr = self.map.getPtr(run_id) orelse return null;
        if (std.mem.eql(u8, action, "cancel")) {
            rec_ptr.status = "cancelled";
        } else if (std.mem.eql(u8, action, "approve")) {
            rec_ptr.status = "completed";
        }
        // "advance" keeps the run in "running" state; step sequencing
        // (current_step transitions) requires flow definitions — deferred to
        // D-brain-flow-runner-api phase-2.
        return @as(?[]u8, try serializeRecord(out_alloc, rec_ptr.*));
    }

    fn serializeRecord(out_alloc: std.mem.Allocator, rec: FlowRunRecord) ![]u8 {
        return std.fmt.allocPrint(
            out_alloc,
            "{{\"run_id\":\"{s}\",\"flow_id\":\"{s}\",\"status\":\"{s}\",\"current_step\":\"{s}\"}}",
            .{ rec.run_id, rec.flow_id, rec.status, rec.current_step },
        );
    }
};

// ── D-brain-flow-runner-api bridge functions ─────────────────────────────────

fn flowIsBearerValid(ctx: ?*anyopaque, bearer: []const u8) bool {
    const ts: *bearer_tokens_mod.TokenStore = @ptrCast(@alignCast(ctx.?));
    _ = ts.verifyHex(bearer) catch return false;
    return true;
}

fn flowStartRun(
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    flow_id: []const u8,
    context_json: []const u8,
) anyerror![]u8 {
    const store: *FlowRunStore = @ptrCast(@alignCast(ctx.?));
    return store.startRun(allocator, flow_id, context_json);
}

fn flowGetState(
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    run_id: []const u8,
) anyerror!?[]u8 {
    const store: *FlowRunStore = @ptrCast(@alignCast(ctx.?));
    return store.getState(allocator, run_id);
}

fn flowStepRun(
    ctx: ?*anyopaque,
    allocator: std.mem.Allocator,
    run_id: []const u8,
    action: []const u8,
    payload_json: []const u8,
) anyerror!?[]u8 {
    const store: *FlowRunStore = @ptrCast(@alignCast(ctx.?));
    return store.stepRun(allocator, run_id, action, payload_json);
}

pub fn cmdServe(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 1) {
        try out.print("usage: brain serve <domain> [--port N] [--enable-repl] [--repl-config-path <path>] [--enable-intent-action-router] [--extra-hat DOMAIN]...\n", .{});
        try out.print("       brain serve --tenant-manifest <path> [--enable-repl] [--repl-config-path <path>] [--enable-intent-action-router] [--extra-hat DOMAIN]...\n", .{});
        return .bad_args;
    }

    // ── First-pass arg scan: find --tenant-manifest if present ───────
    //
    // D-O9: when the operator passes `--tenant-manifest <path>`, the
    // manifest is the source of truth for the tenant identity.  The
    // positional `<domain>` becomes optional in that mode.  We do a
    // lightweight first-pass scan so the positional vs flag-driven
    // shape is decided up front.  We also accept the
    // `--tenant-manifest=<path>` glued form because that's what the
    // systemd unit ExecStart writes.
    var tenant_manifest_path: ?[]const u8 = null;
    {
        const prefix = "--tenant-manifest=";
        var j: usize = 0;
        while (j < args.len) : (j += 1) {
            if (std.mem.eql(u8, args[j], "--tenant-manifest") and j + 1 < args.len) {
                tenant_manifest_path = args[j + 1];
                break;
            }
            if (args[j].len > prefix.len and std.mem.startsWith(u8, args[j], prefix)) {
                tenant_manifest_path = args[j][prefix.len..];
                break;
            }
        }
    }

    // ── Tenant manifest mode ─────────────────────────────────────────
    //
    // When `--tenant-manifest <path>` is set we parse + validate the
    // manifest before anything else.  Domain + listen port are
    // sourced from the manifest; the operator can override the port
    // via `--port` for ad-hoc dev runs but the rest of the identity
    // is fixed.  This is the systemd `%i`-instance code path: each
    // tenant systemd unit boots with `brain serve --tenant-manifest=
    // /etc/semantos/tenants/<domain>.toml`.
    var manifest_holder: ?tenant_manifest_mod.TenantManifest = null;
    defer if (manifest_holder) |*m| m.deinit();
    var resolved_domain: []const u8 = if (args.len > 0 and !std.mem.startsWith(u8, args[0], "--")) args[0] else "";
    var resolved_port_from_manifest: ?u16 = null;

    if (tenant_manifest_path) |mpath| {
        var mf = tenant_manifest_mod.loadFromPath(allocator, mpath) catch |e| {
            try out.print("serve: failed to load --tenant-manifest {s}: {s}\n", .{ mpath, @errorName(e) });
            return .config_error;
        };
        // Validate against the manifest's directory (so the
        // owner_cert_path resolution is meaningful).
        const manifest_dir = std.fs.path.dirname(mpath) orelse ".";
        var report = tenant_manifest_mod.validate(allocator, &mf, manifest_dir) catch |e| {
            mf.deinit();
            try out.print("serve: --tenant-manifest validate failed: {s}\n", .{@errorName(e)});
            return .config_error;
        };
        defer report.deinit();
        if (report.errCount() > 0) {
            try out.print("serve: --tenant-manifest {s} has {d} validation error(s):\n", .{ mpath, report.errCount() });
            for (report.problems.items) |p| {
                if (p.severity == .err) try out.print("  - {s}\n", .{p.message});
            }
            mf.deinit();
            return .config_error;
        }
        resolved_domain = mf.domain;
        resolved_port_from_manifest = mf.listen_port_start;
        manifest_holder = mf;

        // Surface the resolved tenant identity so operators can
        // verify systemd's %i substitution against the manifest at
        // boot.  The systemd unit's StandardOutput=journal pipe
        // carries this line into journald keyed by the unit name.
        try out.print("[tenant] manifest:        {s}\n", .{mpath});
        try out.print("[tenant] domain:          {s}\n", .{manifest_holder.?.domain});
        try out.print("[tenant] listen_port:     {d}\n", .{manifest_holder.?.listen_port_start});
        try out.print("[tenant] extensions:      ", .{});
        for (manifest_holder.?.extensions_install, 0..) |ext, k| {
            if (k > 0) try out.print(", ", .{});
            try out.print("{s}", .{ext});
        }
        try out.print("\n", .{});
    } else if (resolved_domain.len == 0) {
        try out.print("usage: brain serve <domain> [--port N] [--enable-repl] [--repl-config-path <path>] [--enable-intent-action-router] [--extra-hat DOMAIN]...\n", .{});
        try out.print("       brain serve --tenant-manifest <path> [--enable-repl] [--repl-config-path <path>] [--enable-intent-action-router] [--extra-hat DOMAIN]...\n", .{});
        return .bad_args;
    }

    const domain = resolved_domain;

    // Optional flags.
    var port_override: ?u16 = null;
    var enable_repl = false;
    var repl_config_path: ?[:0]const u8 = null;
    // D-W1 Phase 4 — opt-in SignedBundle mesh receive endpoint.  Empty
    // string = disabled; non-empty path turns the seam on (default
    // path "/api/v1/bundle" when --signed-bundle-endpoint is supplied
    // without an argument is intentionally NOT supported — the
    // operator must spell the path explicitly).
    var signed_bundle_endpoint: ?[:0]const u8 = null;
    // D-W2 Phase 2 — opt-in extension-bundle frame receive endpoint.
    // Distinct from --signed-bundle-endpoint; default disabled.
    var bundle_frame_endpoint: ?[:0]const u8 = null;
    // T8b — voice-extract subprocess config.  Default disabled
    // (endpoint stays 404 unless both --voice-extract-script and
    // --voice-extract-cwd are passed).
    var voice_extract_script: ?[]const u8 = null;
    // Betterment-practice pask sweep — optional script path for bun sweep_runner.ts.
    // Endpoint stays 503 unless --betterment-sweep-script is passed.
    var betterment_sweep_script: ?[]const u8 = null;
    // C4 PR-G5 — oddjobz_approve_script REMOVED: POST /api/v1/conversation/turn/:id/approve
    // is served by the oddjobz cartridge via the route registry (cartridge-owned script).
    // D-OJ-conv-identity-merge-endpoint — optional script path for bun
    // identity-merge subprocess.
    // Endpoint stays 404 unless --oddjobz-identity-merge-script is passed.
    var oddjobz_identity_merge_script: ?[]const u8 = null;
    // C4 PR-G6 — oddjobz_re_anchor_script REMOVED: POST /api/v1/conversation/turn/:id/re-anchor
    // is served by the oddjobz cartridge via the route registry (cartridge-owned script).
    // C4 PR-G4 — oddjobz_propose_turn_script REMOVED: POST /api/v1/conversation/turn/propose
    // is served by the oddjobz cartridge via the route registry (cartridge-owned script).
    // C4 PR-G2 — oddjobz_customer_link_resolve_script REMOVED: GET /api/v1/c/{token}
    // is served by the oddjobz cartridge via the route registry (cartridge-owned script).
    // D-OJ-conv-turns-query — optional script path for bun turns-query subprocess.
    // Endpoint stays 404 unless --oddjobz-conv-turns-query-script is passed.
    var oddjobz_conv_turns_query_script: ?[]const u8 = null;
    // C4 PR-G7 — oddjobz_voice_note_script REMOVED: POST /api/v1/voice-note is
    // served by the oddjobz cartridge via the route registry (cartridge-owned script).
    var voice_extract_cwd: ?[]const u8 = null;
    var voice_extract_bun: []const u8 = "bun";
    // Betterment OCR — image-extract subprocess config.  Endpoint stays 404
    // unless both --image-extract-script and --image-extract-cwd are passed.
    var image_extract_script: ?[]const u8 = null;
    var image_extract_cwd: ?[]const u8 = null;
    var image_extract_bun: []const u8 = "bun";
    // Betterment voice — audio-extract subprocess config (bun → whisper.cpp).
    var audio_extract_script: ?[]const u8 = null;
    var audio_extract_cwd: ?[]const u8 = null;
    var audio_extract_bun: []const u8 = "bun";
    // Tier 3 — brain-side bridge from `intent_cell.created` broker
    // events to the oddjobz.jobs FSM.  OFF by default; the operator
    // turns it on for the demo, off afterwards.  Also honours the
    // env-var BRAIN_INTENT_ROUTER=1 for systemd-unit one-shot enables.
    var enable_intent_router = false;
    // D-network-ipv6-session-keys — /56 prefix + interface for per-contact
    // /128 assignment.  Both are optional; if absent the feature is disabled.
    // The prefix is the first 64 bits of the routed IPv6 block, e.g.:
    //   --ipv6-prefix 2404:9400:17e5:1e00::
    //   --ipv6-iface eth0   (default)
    var ipv6_prefix: ?[]const u8 = null;
    var ipv6_iface: []const u8 = "eth0";
    // W0.6 — extra hat domain names collected from --extra-hat flags.
    // Each entry is a domain string (e.g. "carpenter.local") that will
    // be registered in the HatRegistry alongside the primary domain.
    var extra_hat_domains: std.ArrayList([]const u8) = .{};
    defer extra_hat_domains.deinit(allocator);
    // When in tenant-manifest mode we have NO positional <domain>, so
    // we start scanning flags from index 0.  Otherwise the legacy
    // single-tenant shape consumed args[0] as the domain.
    var i: usize = if (tenant_manifest_path == null) 1 else 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
            port_override = std.fmt.parseInt(u16, args[i + 1], 10) catch {
                try out.print("serve: invalid --port `{s}`\n", .{args[i + 1]});
                return .bad_args;
            };
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--enable-repl")) {
            enable_repl = true;
        } else if (std.mem.eql(u8, args[i], "--repl-config-path") and i + 1 < args.len) {
            repl_config_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--signed-bundle-endpoint") and i + 1 < args.len) {
            signed_bundle_endpoint = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--bundle-frame-endpoint") and i + 1 < args.len) {
            bundle_frame_endpoint = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--betterment-sweep-script") and i + 1 < args.len) {
            // Betterment-practice pask sweep — absolute path to
            // cartridges/betterment/brain/src/sweep_runner.ts.
            betterment_sweep_script = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--voice-extract-script") and i + 1 < args.len) {
            // T8b — absolute path to cartridges/oddjobz/brain/tools/voice-extract.ts.
            voice_extract_script = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--voice-extract-cwd") and i + 1 < args.len) {
            // T8b — working directory for the bun subprocess (workspace
            // root, so @semantos/* imports in the CLI resolve).
            voice_extract_cwd = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--voice-extract-bun") and i + 1 < args.len) {
            // T8b — path to the bun executable.  Defaults to "bun"
            // (PATH lookup); pass an absolute path for production.
            voice_extract_bun = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--image-extract-script") and i + 1 < args.len) {
            // Betterment OCR — absolute path to cartridges/betterment/brain/tools/image-extract.ts.
            image_extract_script = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--image-extract-cwd") and i + 1 < args.len) {
            // Betterment OCR — working directory for the bun subprocess (workspace root).
            image_extract_cwd = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--image-extract-bun") and i + 1 < args.len) {
            // Betterment OCR — path to the bun executable.  Defaults to "bun".
            image_extract_bun = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--audio-extract-script") and i + 1 < args.len) {
            // Betterment voice — absolute path to cartridges/betterment/brain/tools/audio-extract.ts.
            audio_extract_script = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--audio-extract-cwd") and i + 1 < args.len) {
            audio_extract_cwd = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--audio-extract-bun") and i + 1 < args.len) {
            audio_extract_bun = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--oddjobz-identity-merge-script") and i + 1 < args.len) {
            // D-OJ-conv-identity-merge-endpoint — absolute path to
            // cartridges/oddjobz/brain/src/conversation/identity-merge-script.ts.
            oddjobz_identity_merge_script = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--oddjobz-conv-turns-query-script") and i + 1 < args.len) {
            // D-OJ-conv-turns-query — absolute path to
            // cartridges/oddjobz/brain/src/conversation/conversation-turns-query-script.ts.
            oddjobz_conv_turns_query_script = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--enable-intent-action-router")) {
            // Tier 3 — opt-in router from the broker event into
            // the jobs FSM.  Must be paired with --enable-repl
            // (the dispatcher + jobs handler are stood up in that
            // block); cmdServe enforces the dependency below.
            enable_intent_router = true;
        } else if (std.mem.eql(u8, args[i], "--extra-hat") and i + 1 < args.len) {
            // W0.6 — register an additional hat domain.  Repeatable;
            // each value is a domain string (e.g. "carpenter.local").
            // The domain_flag is derived from the domain's site.json
            // at start-up (or defaults to a hash of the domain name
            // when no explicit flag is present in the site config).
            // Full domain_flag → site.json integration is M-level;
            // for W0.6 we store the domain name and register it
            // in the HatRegistry with a synthesized flag at boot.
            try extra_hat_domains.append(allocator, args[i + 1]);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--tenant-manifest") and i + 1 < args.len) {
            // already consumed in the first-pass scan above; skip
            // the flag's value here.
            i += 1;
        } else if (std.mem.startsWith(u8, args[i], "--tenant-manifest=")) {
            // glued form already consumed in the first-pass scan.
        } else if (std.mem.eql(u8, args[i], "--ipv6-prefix") and i + 1 < args.len) {
            // D-network-ipv6-session-keys: /56 or /64 prefix for per-contact
            // /128 assignment.  Example: 2404:9400:17e5:1e00::
            ipv6_prefix = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--ipv6-iface") and i + 1 < args.len) {
            // Network interface to add /128 addresses to (default: eth0).
            // Run `ip link show` on the VPS to confirm (may be ens3, eth0…)
            ipv6_iface = args[i + 1];
            i += 1;
        }
    }
    // Env-var override for systemd-unit one-shot enables.  Any value
    // in BRAIN_INTENT_ROUTER other than "0" / empty turns the gate on.
    if (std.posix.getenv("BRAIN_INTENT_ROUTER")) |envv| {
        if (envv.len > 0 and !std.mem.eql(u8, envv, "0")) {
            enable_intent_router = true;
        }
    }
    // Manifest port wins over default but `--port` still overrides
    // (operator escape hatch for dev / port-collision recovery).
    if (resolved_port_from_manifest) |p| {
        if (port_override == null) port_override = p;
    }

    // W0.6 — HatRegistry: bring up the in-process hat directory.
    //
    // The primary domain is always registered as the first hat.  Its
    // domain_flag is synthesised from the domain string via a simple
    // 32-bit FNV-1a hash so the primary hat has a stable, deterministic
    // flag across restarts.  Each --extra-hat domain is registered the
    // same way.  Full domain_flag ↔ site.json integration (where the
    // operator stores the flag in site.json explicitly) is M-level work;
    // the hash-based synthesis is the W0.6 pragmatic default.
    //
    // The registry is deinit'd at the end of cmdServe (owned by the
    // defer below).  Capability watchers are stub no-ops for W0.6.
    var hat_registry = hat_registry_mod.HatRegistry.init(allocator);
    defer hat_registry.deinit();
    {
        const primary_flag = domainToFlag(domain);
        hat_registry.addHat(primary_flag, domain) catch |e| {
            // Non-fatal: log and continue; the registry is an
            // additive seam — the serve path works without it.
            try out.print("serve {s}: hat_registry.addHat (primary): {s}\n", .{ domain, @errorName(e) });
        };
        // Log the primary hat registration.
        try out.print("[hat_registry] primary hat: {s} (flag=0x{X:0>6})\n", .{ domain, primary_flag });

        for (extra_hat_domains.items) |extra_domain| {
            const extra_flag = domainToFlag(extra_domain);
            hat_registry.addHat(extra_flag, extra_domain) catch |e| {
                try out.print("serve {s}: hat_registry.addHat ({s}): {s}\n", .{ domain, extra_domain, @errorName(e) });
                continue;
            };
            // Wire the M3.5 capability-watcher stub so the hook site
            // exists and M3.5 can fill it in without touching cmdServe.
            hat_registry_mod.startCapabilityWatcher(extra_flag, onCapabilityChange);
            try out.print("[hat_registry] extra hat:   {s} (flag=0x{X:0>6})\n", .{ extra_domain, extra_flag });
        }
    }

    const path = try siteConfigPath(allocator, domain);
    defer allocator.free(path);
    var cfg = site_config_mod.loadFromPath(allocator, path) catch |e| {
        try out.print("serve {s}: failed to load {s}: {s}\n", .{ domain, path, @errorName(e) });
        return .config_error;
    };
    defer cfg.deinit();
    if (port_override) |p| cfg.listen_port = p;

    // Resolve content_root relative to site dir.
    const site_dir = std.fs.path.dirname(path) orelse ".";
    var dir_handle = std.fs.cwd().openDir(site_dir, .{}) catch |e| {
        try out.print("serve {s}: open {s}: {s}\n", .{ domain, site_dir, @errorName(e) });
        return .file_io;
    };
    defer dir_handle.close();
    dir_handle.setAsCwd() catch {};

    // Data dir — use the same resolution logic as every other brain command
    // so bearer-tokens.log, audit.log, etc. all land in the same place
    // regardless of which subcommand wrote them.
    const data_dir_path = try resolveDataDir(allocator);
    defer allocator.free(data_dir_path);

    var server = site_server_mod.SiteServer.init(allocator, &cfg, data_dir_path) catch |e| {
        try out.print("serve {s}: server init: {s}\n", .{ domain, @errorName(e) });
        return .file_io;
    };
    defer server.deinit();

    // C4 PR-F1 — cartridge HTTP route registry. Lives for cmdServe (stable
    // address for the reactor); cartridges append routes to it at boot via
    // CartridgeDeps.route_registry, and the reactor consults server.route_registry
    // at request time. Attached now so it's live before any route registers.
    var route_registry_serve: http_route_registry_mod.RouteRegistry = .{};
    server.attachRouteRegistry(&route_registry_serve);

    // Unified WSS RPC channel — method registry. Same lifetime/stable-address
    // contract as route_registry_serve. Substrate methods (cell.query/repl.eval)
    // are registered below once their backing handlers exist; cartridges append
    // their own via CartridgeDeps.rpc_registry at boot.
    var rpc_registry_serve: wss_rpc_registry_mod.RpcRegistry = .{};
    server.attachRpcRegistry(&rpc_registry_serve);

    // C4 PR-H1 — typed store registry (the §6b store-carve seam). Stable address
    // for cmdServe; the oddjobz cartridge publishes the nine shared store
    // pointers into it in registerInto, and the brain's remaining store
    // consumers (WSS query/attention/ratify + the store-coupled HTTP acceptors)
    // read them back through it. Declared empty here; handed to cartridges via
    // CartridgeDeps.store_registry below.
    var store_registry_serve: store_registry_mod.StoreRegistry = .{};

    // C4 PR-J2 — cell-decoder registry (the generic cell.query seam). Stable
    // address; the cartridge registers a decoder per cellType in registerInto,
    // and cell_query_handler dispatches through it. Declared empty here.
    var cell_decoder_registry_serve: cell_decoder_registry_mod.CellDecoderRegistry = .{};

    // C4 PR-J4 — attention-source registry + generic poll handler. Stable
    // address; cartridges register namespace-scoped signal sources, the generic
    // attention.poll merges the caller's in-scope namespaces. (oddjobz's sources
    // are registered by serve below for now — its attention handler is still
    // serve-owned; moving registration into registerInto is a follow-up.)
    var attention_source_registry_serve: attention_source_registry_mod.AttentionSourceRegistry = .{};
    var attention_poll_serve: ?attention_poll_handler_mod.Handler = null;
    // SH7 / D15 — ctx for the shell-native identity attention source. Lives for
    // the server run (borrowed by the registry); .token_store filled at registration.
    var shell_identity_ctx: ShellAttnCtx = .{};

    // C4 PR-J5 — ratify-builder registry + generic submit handler. Stable
    // address; cartridges register one graph builder per namespace, the generic
    // ratify.submit routes by namespace. (oddjobz's builder is registered by
    // serve below for now — its ratify handler is still serve-owned; moving
    // registration into registerInto is a follow-up.)
    var ratify_builder_registry_serve: ratify_builder_registry_mod.RatifyBuilderRegistry = .{};
    var ratify_submit_serve: ?ratify_submit_handler_mod.Handler = null;

    // WSITE2.5 — if any route is dynamic, stand up a broker + runner
    // so we can pre-instantiate handlers.  Static-only sites skip this
    // (no broker / wasmtime cost; the binary still works in stub mode).
    var has_dynamic = false;
    for (cfg.routes) |r| {
        if (r.kind == .dynamic) {
            has_dynamic = true;
            break;
        }
    }

    var dynamic_setup: ?DynamicRuntime = null;
    defer if (dynamic_setup) |*d| d.deinit();

    if (has_dynamic) {
        dynamic_setup = setUpDynamicRuntime(allocator, data_dir_path) catch |e| {
            try out.print("serve {s}: failed to bring up dynamic-handler runtime: {s}\n", .{ domain, @errorName(e) });
            return .file_io;
        };
        const ok = server.attachRunner(&dynamic_setup.?.runner) catch |e| {
            try out.print("serve {s}: attachRunner: {s}\n", .{ domain, @errorName(e) });
            return .file_io;
        };
        try out.print("  dynamic handlers: {d} of {d} loaded\n", .{ ok, countDynamicRoutes(&cfg) });
    }

    // ── Brain 4 — `--enable-repl` brings up the REPL backend + token store
    //     and attaches them to the SiteServer so /api/v1/repl dispatches
    //     into the same Session the operator's `brain repl` would use.
    var repl_backend: ?*ReplBackend = null;
    defer if (repl_backend) |b| b.deinit();
    var token_store: ?bearer_tokens_mod.TokenStore = null;
    defer if (token_store) |*ts| ts.deinit();
    var repl_session: ?repl_mod.Session = null;
    // DO-1/CW-3 — the served domain's operator profile, function-scoped so both
    // the cartridge deps (CW-3) AND the substrate `site` handler (DO-1, which the
    // dispatcher borrows for the brain's lifetime) reference one stable instance.
    // Loaded best-effort inside the --enable-repl block; null when absent.
    var operator_profile_holder: ?operator_profile_mod.OperatorProfile = null;
    // C4 PR-R3 — cartridge REPL verb registry. Populated by the cartridge seam
    // (via CartridgeDeps below) and attached to repl_session so `find jobs`,
    // `find attention`, FSM transition verbs, and conversation verbs route over
    // repl.eval on the unified channel (parity with the CLI repl).
    var repl_verb_registry_serve: repl_verb_registry_mod.ReplVerbRegistry = .{};
    // DO-1 — the `do <verb> <resource> <target>` operator-action registry.
    var do_registry_serve: do_verb_registry_mod.DoVerbRegistry = .{};
    do_registry_serve.add(.{
        .verb = "manage",
        .resource = "site",
        .target = "widget",
        .dispatch_resource = "site",
        .read_command = "widget_get",
        .write_command = "widget_set",
        .summary = "manage the public chat widget policy (enabled, endpoint, copy)",
    });
    // WP-4 — `do manage site pricing` (hourly_rate, travel_km, quote_policy, …).
    do_registry_serve.add(.{
        .verb = "manage",
        .resource = "site",
        .target = "pricing",
        .dispatch_resource = "site",
        .read_command = "pricing_get",
        .write_command = "pricing_set",
        .summary = "manage pricing: hourly_rate, callout, minimum, travel_km, quote_policy",
    });
    // WP-5 — versioned conversation prompt: `do manage site prompt` (get / set
    // text=…), `do list site prompt` (version history), `do rollback site prompt
    // id=N` (repoint the active version).
    do_registry_serve.add(.{
        .verb = "manage",
        .resource = "site",
        .target = "prompt",
        .dispatch_resource = "site",
        .read_command = "prompt_get",
        .write_command = "prompt_set",
        .summary = "manage the conversation prompt (get active; set text=… to add a version)",
    });
    do_registry_serve.add(.{
        .verb = "list",
        .resource = "site",
        .target = "prompt",
        .dispatch_resource = "site",
        .read_command = "prompt_list",
        .summary = "list conversation-prompt versions (id, ts, chars) + the active one",
    });
    do_registry_serve.add(.{
        .verb = "rollback",
        .resource = "site",
        .target = "prompt",
        .dispatch_resource = "site",
        .read_command = "prompt_rollback",
        .write_command = "prompt_rollback",
        .summary = "rollback the active conversation prompt to an earlier version (id=N)",
    });
    var wss_backend: ?wss_wallet_mod.Backend = null;
    var wallet_op_acceptor: ?wallet_op_http_mod.Acceptor = null;
    // D-O5.followup-4 — process-scoped helm event broker.  Stood up
    // exactly once per `brain serve` so wss_wallet's helm.subscribe RPC
    // and jobs_handler's emit path share the same broker (and
    // therefore the same fan-out subscriber list).  Owned at the top
    // of cmdServe so its address is stable for the duration of the
    // server.  Constructed regardless of `--enable-repl`: even when
    // the REPL backend is off, we still want the WSS endpoint's
    // helm.subscribe path to return a clean response (broker present,
    // zero events fan out — same shape the helms hit when nothing is
    // happening).  Substrate scope: only jobs_handler emits in this
    // PR; other handlers' emitters land in followup PRs.
    var helm_broker_serve = helm_event_broker_mod.Broker.init(allocator);
    defer helm_broker_serve.deinit();

    // PR-3a-bridge-2c — AnchorQueueWriter: appends every cell.created
    // event the broker fans out to a JSON-lines file the wallet-
    // headers anchor-runner.ts process tails for BSV broadcast.
    // Off by default; opt-in via env BRAIN_ANCHOR_QUEUE_PATH (e.g.,
    // BRAIN_ANCHOR_QUEUE_PATH=~/.local/share/semantos-brain/anchor-queue.jsonl).
    // Null path → writer attached as a no-op; broker callback skips
    // it cheaply.
    const anchor_queue_path_opt: ?[]const u8 = std.process.getEnvVarOwned(
        allocator,
        "BRAIN_ANCHOR_QUEUE_PATH",
    ) catch null;
    defer if (anchor_queue_path_opt) |p| allocator.free(p);
    if (anchor_queue_path_opt) |p| {
        try out.print("[anchor_queue_writer] enabled — appending cell.created events to: {s}\n", .{p});
    }
    var anchor_queue_writer_serve = anchor_queue_writer_mod.AnchorQueueWriter.init(
        allocator,
        .{ .queue_path = anchor_queue_path_opt },
    );
    try anchor_queue_writer_serve.attach(&helm_broker_serve);
    defer anchor_queue_writer_serve.detach(&helm_broker_serve);

    // AnchorRunnerSupervisor — spawn `bun anchor-runner.ts` as a
    // supervised child when the operator opts in. Closes the gap
    // where queue lines accumulate but no broadcaster runs.
    //
    // Required env:
    //   BRAIN_ANCHOR_RUNNER=1           — enable the supervisor
    //   BRAIN_ANCHOR_QUEUE_PATH=<path>  — must match the writer above
    //   BRAIN_ANCHOR_RUNNER_SCRIPT=<path>
    //                                   — absolute path to
    //                                     anchor-runner.ts in the
    //                                     wallet-headers cartridge
    // Optional env:
    //   BRAIN_ANCHOR_RUNNER_BUN=<path>  — bun binary; default "bun"
    //                                     (PATH lookup)
    //   BRAIN_ANCHOR_RUNNER_POLL_MS=<N> — runner poll interval
    //
    // Disabled by default. When disabled OR queue path absent, the
    // supervisor is never constructed (operator-driven runner path
    // remains valid).
    var anchor_runner_enabled = false;
    if (std.process.getEnvVarOwned(allocator, "BRAIN_ANCHOR_RUNNER")) |raw| {
        defer allocator.free(raw);
        anchor_runner_enabled = std.mem.eql(u8, raw, "1") or
            std.ascii.eqlIgnoreCase(raw, "true") or
            std.ascii.eqlIgnoreCase(raw, "yes");
    } else |_| {}

    const anchor_runner_script_opt: ?[]const u8 = if (anchor_runner_enabled)
        (std.process.getEnvVarOwned(allocator, "BRAIN_ANCHOR_RUNNER_SCRIPT") catch null)
    else
        null;
    defer if (anchor_runner_script_opt) |p| allocator.free(p);

    const anchor_runner_bun_opt: ?[]const u8 = if (anchor_runner_enabled)
        (std.process.getEnvVarOwned(allocator, "BRAIN_ANCHOR_RUNNER_BUN") catch null)
    else
        null;
    defer if (anchor_runner_bun_opt) |p| allocator.free(p);

    const anchor_runner_poll_str_opt: ?[]const u8 = if (anchor_runner_enabled)
        (std.process.getEnvVarOwned(allocator, "BRAIN_ANCHOR_RUNNER_POLL_MS") catch null)
    else
        null;
    defer if (anchor_runner_poll_str_opt) |p| allocator.free(p);

    var anchor_runner_supervisor_opt: ?anchor_runner_supervisor_mod.Supervisor = null;

    if (anchor_runner_enabled) {
        if (anchor_queue_path_opt == null) {
            try out.print(
                "[anchor_runner_supervisor] enabled but BRAIN_ANCHOR_QUEUE_PATH not set; supervisor will NOT start\n",
                .{},
            );
        } else if (anchor_runner_script_opt == null) {
            try out.print(
                "[anchor_runner_supervisor] enabled but BRAIN_ANCHOR_RUNNER_SCRIPT not set; supervisor will NOT start\n",
                .{},
            );
        } else {
            const poll_ms: ?u32 = blk: {
                const s = anchor_runner_poll_str_opt orelse break :blk null;
                const parsed = std.fmt.parseInt(u32, s, 10) catch {
                    try out.print(
                        "[anchor_runner_supervisor] BRAIN_ANCHOR_RUNNER_POLL_MS={s} not a valid u32; ignoring\n",
                        .{s},
                    );
                    break :blk null;
                };
                break :blk parsed;
            };
            anchor_runner_supervisor_opt = anchor_runner_supervisor_mod.Supervisor.init(
                allocator,
                .{
                    .bun_path = anchor_runner_bun_opt orelse "bun",
                    .script_path = anchor_runner_script_opt.?,
                    .queue_path = anchor_queue_path_opt.?,
                    .poll_ms = poll_ms,
                },
            );
            anchor_runner_supervisor_opt.?.start() catch |err| {
                try out.print(
                    "[anchor_runner_supervisor] failed to start: {s}\n",
                    .{@errorName(err)},
                );
                anchor_runner_supervisor_opt = null;
            };
            if (anchor_runner_supervisor_opt != null) {
                try out.print("[anchor_runner_supervisor] started; supervising anchor-runner.ts\n", .{});
            }
        }
    }
    defer if (anchor_runner_supervisor_opt) |*s| s.stop();

    // PR-3a-bridge-3 — AnchorConfirmationReader env lookup.  Reader
    // itself is constructed below once disp_audit is open (the reader
    // needs the audit handle).  We capture the path here so it
    // shares lifetime with other env-derived strings declared in
    // this scope.
    const anchor_confirmations_path_opt: ?[]const u8 = std.process.getEnvVarOwned(
        allocator,
        "BRAIN_ANCHOR_CONFIRMATIONS_PATH",
    ) catch null;
    defer if (anchor_confirmations_path_opt) |p| allocator.free(p);
    if (anchor_confirmations_path_opt) |p| {
        try out.print("[anchor_confirmation_reader] enabled — will drain at boot from: {s}\n", .{p});
    }

    // ── D-W1 Phase 1 — Unix socket transport.  Bound alongside the
    //     HTTP server when --enable-repl is set; the CLI's bearer-token
    //     commands (and forthcoming identity_certs / llm.complete CLI
    //     paths) talk to this socket instead of writing the bearer log
    //     directly.  See BRAIN-DISPATCHER-UNIFICATION.md §5.2.
    var disp_audit: ?audit_log_mod.AuditLog = null;
    var disp_audit_path: ?[]u8 = null;
    defer if (disp_audit) |*a| a.close();
    defer if (disp_audit_path) |p| allocator.free(p);
    var dispatcher_inst: ?dispatcher_mod.Dispatcher = null;
    defer if (dispatcher_inst) |*d| d.deinit();
    var bearer_handler: ?bearer_tokens_handler_mod.Handler = null;
    // C4 PR-H2b-1 — the §6b oddjobz typed-store + dispatcher-handler vars
    // (jobs/customers/sites/visits/quotes/estimates/invoices/attachments/leads)
    // are gone: the cartridge's registerInto now owns construction + lifetime +
    // registration, publishing the store pointers into store_registry_serve. The
    // NATS client/producer below stay (substrate event spine; deps.nats_producer
    // hands the producer to the cartridge's jobs handler).
    // W7.3 — NATS client + event producer (best-effort; failure disables emit).
    var nats_client_serve: ?nats_client_mod.NatsClient = null;
    defer if (nats_client_serve) |*nc| nc.deinit();
    var nats_producer_serve: ?nats_event_producer_mod.NatsEventProducer = null;
    // C4 PR-H2b-1 — customers/visits/quotes/estimates/invoices/attachments/leads
    // store + handler vars removed (now cartridge-owned, see above).
    // W0.2 — shared LMDB env + CellStore vtable for the 5 entity stores
    // (customers, visits, quotes, invoices, attachments).  A single
    // environment covers all five domains via the entity_tag discriminator
    // written into every 1024-byte cell header.  Best-effort: failure
    // leaves all entity-store pointers null (same graceful degradation as
    // the FS-backed path).
    var entity_lmdb_env_serve: ?lmdb_mod.Env = null;
    defer if (entity_lmdb_env_serve) |*env| env.close();
    var entity_cell_store_impl_serve: ?lmdb_cell_store_mod.LmdbCellStore = undefined;
    var entity_cell_store_serve: ?@import("cell_store").CellStore = null;
    // Octave-1 escalation content store (`<data_dir>/content/o1/`).
    // Holds payloads that exceed the 768-byte inline cell budget; the
    // entity.encode walker writes overflow slots and the jobs store
    // derefs them on replay. Best-effort: a null store means
    // over-budget payloads are rejected at encode (never truncated).
    var content_store_serve: ?content_store_local_fs_mod.ContentStoreLocalFs = null;
    defer if (content_store_serve) |*cs| cs.deinit();

    // Phase 3 (W0.3) — typed `intent_cells` resource (typed-NL command
    // round-trip from the operator's phone).  W0.3: LMDB-backed store.
    // Stood up alongside the FSM-handler set so the helm-over-HTTP path
    // (POST /api/v1/repl) has the same surface the local operator REPL
    // gets.  Best-effort: failure prints a hint and leaves the verb
    // dispatching to unknown_resource.
    var intent_cells_env_serve: ?lmdb_mod.Env = null;
    defer if (intent_cells_env_serve) |*env| env.close();
    var intent_cells_store_serve: ?intent_cell_lmdb_store_mod.IntentCellLmdbStore = null;
    defer if (intent_cells_store_serve) |*ics| ics.deinit();
    var intent_cells_handler_serve: ?intent_cells_handler_mod.Handler = null;
    // W0.5 — Pask snapshot store: persist Pask graph state to LMDB on
    // shutdown + after each confirmed FSM transition, and restore it on
    // boot.  Uses its own `pask_snapshots_lmdb/` env under data_dir_path
    // so it doesn't share DBIs with the entity stores or intent cells.
    // Initialised inside --enable-repl after cert_store is up so we can
    // use the operator root cert ID as the snapshot key.  Best-effort:
    // failure prints a warning and leaves pask_snapshot_store_serve null.
    var pask_snapshots_env_serve: ?lmdb_mod.Env = null;
    defer if (pask_snapshots_env_serve) |*env| env.close();
    var pask_snapshot_store_serve: ?pask_snapshot_store_lmdb_mod.LmdbPaskSnapshotStore = null;
    // W0.5 — shutdown commit: persist current Pask state on any
    // cmdServe exit path (normal shutdown, error return, Ctrl-C).
    // The cert_id mirrors the boot-restore key: operator root cert ID
    // when available, otherwise the domain string.
    // TODO(W0.5-green): replace stub blob with pask_interact_run's
    // serialise_state() output once the WASM serialisation API is wired.
    defer if (pask_snapshot_store_serve) |*ps| {
        // Build a minimal valid PASK stub blob (12-byte header, 0-byte payload).
        var stub: [12]u8 = undefined;
        std.mem.writeInt(u32, stub[0..4], 0x4B534150, .little); // magic
        std.mem.writeInt(u32, stub[4..8], 1, .little); // version
        std.mem.writeInt(u32, stub[8..12], 0, .little); // payload length = 0
        const vtable = ps.store();
        _ = vtable.commitSnapshot(domain, &stub) catch {};
    };
    // Tier 3 — typed-NL → jobs FSM bridge.  Subscribes to the helm
    // event broker on init; unsubscribes via deinit.  OFF by default
    // — only constructed when `enable_intent_router` is true (set
    // by --enable-intent-action-router or BRAIN_INTENT_ROUTER=1) and
    // the dependencies (dispatcher + jobs store + jobs handler) are
    // up.  Heap-allocated by the router itself so its address is
    // stable across the broker's subscriber list.
    var intent_action_router_serve: ?*intent_action_router_mod.Router = null;
    defer if (intent_action_router_serve) |r| r.deinit();
    // Tier 3 follow-up — visit-rollup router. Shares the intent-
    // router gate (both are automated broker→FSM advancement
    // subscribers; the systemd unit already passes
    // --enable-intent-action-router). Heap-allocated for a stable
    // subscriber-list address.
    var visit_rollup_router_serve: ?*visit_rollup_router_mod.Router = null;
    defer if (visit_rollup_router_serve) |r| r.deinit();
    // ODDJOBZ-ESTIMATE-ROM-INGRESS Slice 4 — quote-seed router.
    // Shares the intent-router gate (all three are automated
    // broker→FSM-advancement subscribers). Heap-allocated for a
    // stable subscriber-list address.
    var quote_seed_router_serve: ?*quote_seed_router_mod.Router = null;
    defer if (quote_seed_router_serve) |r| r.deinit();
    // C4 PR-H2b-1 — the `sites` view-store var is gone; the oddjobz cartridge
    // constructs it + publishes it into store_registry_serve.sites.
    // D-DOG.1.0b' — oddjobz Layer-2 ratify seam.  Stood up after the
    // dispatcher + jobs handler are registered (its `handleRatify`
    // dispatches into `jobs.create`).  Threaded into wss_backend so
    // the `oddjobz.ratify_proposal` JSON-RPC verb can route ratifies
    // through the existing typed handlers.  Best-effort init: failure
    // prints a hint and leaves the verb returning `oddjobz ratify
    // seam unavailable` (-32603), so a degraded daemon still serves
    // every other endpoint.
    var oddjobz_ratify_serve: ?oddjobz_ratify_handler_mod.Handler = null;
    defer if (oddjobz_ratify_serve) |*h| h.deinit();
    // Generic verb dispatcher — uniform write-seam registry. Constructed
    // unconditionally so other extensions can register walkers even
    // when the oddjobz ratify seam isn't up. Threaded into
    // wss_backend.verb_registry so the `verb.dispatch` JSON-RPC method
    // can route to any registered walker.
    var verb_registry_serve: ?verb_dispatcher_mod.Registry = null;
    defer if (verb_registry_serve) |*r| r.deinit();
    // Universal cartridge boot — constructs every table cartridge's
    // store+state, heap-owned for the wss_backend lifetime. This is
    // UNCONDITIONAL, exactly as the per-cartridge inits were here
    // (jambox store+state, …). Gate 1 (compilation substrate) is
    // enforced by WHERE registerInto is invoked below — inside the
    // `--enable-repl` block, identical to the legacy per-cartridge
    // registerAll calls. docs/design/UNIVERSAL-CARTRIDGE-BOOT.md.
    // ── Phase-2 chess wallet: optional, all-or-nothing. Reads the
    //    anchors manifest from <data_dir>/chess/manifest.json (wallet
    //    UI's "Export anchors manifest" button writes this), ensures
    //    <data_dir>/chess/intents/ for pay_fn intents, and threads the
    //    native semantos_linear_consume wrapper. Any missing piece →
    //    chess store stays Phase-1 (verbs work, no real money). ───────
    var chess_manifest_buf: ?[]const u8 = null;
    defer if (chess_manifest_buf) |b| allocator.free(b);
    {
        const mpath = std.fmt.allocPrint(allocator, "{s}/chess/manifest.json", .{data_dir_path}) catch null;
        if (mpath) |p| {
            defer allocator.free(p);
            chess_manifest_buf = std.fs.cwd().readFileAlloc(allocator, p, 1 << 20) catch null;
        }
    }
    var chess_queue_dir_buf: ?[]const u8 = null;
    defer if (chess_queue_dir_buf) |b| allocator.free(b);
    chess_queue_dir_buf = std.fmt.allocPrint(allocator, "{s}/chess/intents", .{data_dir_path}) catch null;
    if (chess_queue_dir_buf) |p| std.fs.cwd().makePath(p) catch {};
    // Cartridge-scoped consumer cert: distinguishes "chess cartridge
    // consumed it" from any other consumer in the kernel's replay
    // ledger. Static bytes are sufficient — the kernel just keys
    // /.consumed/{sha256(path)}/{sha256(cert)} by these bytes.
    const chess_consumer_cert: []const u8 = "semantos:chess-cartridge:v1";
    const chess_consume_fn = if (chess_manifest_buf != null) chess_native_bridge.nativeConsumeFn() else null;

    var cart_runtime: ?cartridge_boot_mod.CartridgeRuntime =
        cartridge_boot_mod.CartridgeRuntime.constructAll(.{
            .allocator = allocator,
            .clock_fn = realClock,
            .chess_manifest_json = chess_manifest_buf,
            .chess_queue_dir = chess_queue_dir_buf,
            .chess_consumer_cert = if (chess_manifest_buf != null) chess_consumer_cert else null,
            .chess_consume_fn = chess_consume_fn,
        }) catch |e| blk: {
            std.debug.print(
                "serve {s}: cartridge constructAll failed: {s} (cartridge verbs unavailable)\n",
                .{ domain, @errorName(e) },
            );
            break :blk null;
        };
    defer if (cart_runtime) |*r| r.deinit();
    // D-RTC.4 — entity.encode walker state. Wired with the entity cell
    // store below if it came up; otherwise the walker returns
    // persisted=false (still produces valid cell_ids for dry-run /
    // legacy-ingest reingest --dry-run flows).
    var entity_encode_walker_state: entity_encode_walker_mod.State = .{};
    var overdue_jobs_walker_state: overdue_jobs_walker_mod.State = .{};
    var pipeline_gaps_walker_state: pipeline_gaps_walker_mod.State = .{};
    // Manifest registry — empty at boot today; compile-bundled
    // extensions get seeded via manifest.install at server bring-up
    // below. Future: load from LMDB so installs survive restart.
    var manifest_registry_serve: ?manifest_registry_mod.Registry = null;
    defer if (manifest_registry_serve) |*r| r.deinit();
    // Generic cell.query primitive — typeHash-keyed projection over the
    // cell DAG. Wraps oddjobz_query_handler today; future extensions
    // register their typeHashes alongside as they bring view-stores
    // online. Threaded into wss_backend.cell_query.
    var cell_query_serve: ?cell_query_handler_mod.Handler = null;
    // C4 PR-J3 — the bespoke oddjobz cross-store query handler was retired;
    // reads go through the generic cell.query/cell.get (cell_query_serve above).
    // Tier 2P Phase B — attention JSONL reader handler.  Constructed
    // when --enable-repl is set; reads JSONL files written by Codex's
    // oddjobz attention/dispatch pipeline.
    var oddjobz_attention_serve: ?oddjobz_attention_handler_mod.Handler = null;
    defer if (oddjobz_attention_serve) |*h| h.deinit(allocator);
    // D-O5.followup-5 — whole-blob site.json editor handler.  Borrows
    // the resolved sites_dir for its lifetime; no per-request
    // allocations.  Cap-gated on cap.brain.admin (same as sites_handler).
    // The dir slice is owned by `site_config_sites_dir_serve`; the
    // handler borrows it.  Both must live until the dispatcher
    // tears down (i.e. until cmdServe returns).
    var site_config_handler_serve: ?site_config_handler_mod.Handler = null;
    var cell_handler_serve: ?cell_handler_mod.Handler = null;
    // BRAIN-GENERIC-MINT-VERB M3 — REPL `cells mint` handler.  Wired
    // alongside cell_handler_serve below when entity_cell_store_serve +
    // the helm broker are both up.
    var cells_mint_handler_serve: ?cells_mint_handler_mod.Handler = null;

    // PR-3e — backing storage for the bsv-spv-verify ScriptContextBuilder.
    // The HeaderStore value is a thin (vtable + opaque ctx) handle;
    // FsHeaderStore owns the on-disk file. We borrow a HeaderStore
    // facet of it via `.store()` and stash it next to the SPV State
    // so the Handler's setContextBuilder gets a stable address.
    // Both stay alive for the duration of cmdServe — the deferred
    // dynamic_setup.deinit() tears down the underlying FsHeaderStore.
    var cells_mint_spv_header_store: ?cell_engine_header_store_mod.HeaderStore = null;
    var cells_mint_spv_ctx_state: ?cells_mint_spv_context_mod.State = null;

    // C4 brain-carve — growable registry replaces the fixed [2] children
    // array + one-shot CompositeContextBuilder. Substrate appends the SPV
    // builder here; the mnca CARTRIDGE appends its MNCA-anchor-transition
    // builder via registerInto (deps.mint_context_registry, PR-E2). Lives
    // for cmdServe so its address stays stable for the Handler's
    // context_builder slot — and so the cartridge's boot-time add() is
    // visible to the Handler at mint-dispatch (request) time.
    var cells_mint_registry: ?cells_mint_handler_mod.MintContextRegistry = null;
    var site_config_sites_dir_serve: ?[]u8 = null;
    defer if (site_config_sites_dir_serve) |d| allocator.free(d);
    // C5 PR-4b-3-attachments (2026-05-29): attachments_handler_serve
    // var removed — the handler is now constructed + registered by
    // cartridges/oddjobz/brain/zig/registration.zig via the C5
    // cartridge_seam.  See the removed construction block below for
    // the migration trail.
    //
    // C4 PR-H7b — attachments_upload acceptor var removed (route moved to the
    // oddjobz cartridge over the route registry; blob store fully cartridge-owned).
    // D-LC1 — raw cell-over-HTTP acceptor. Wired when entity_cell_store_impl_serve
    // is up AND token_store is up; absent either → endpoint stays 404.
    var cell_raw_acceptor: ?cell_raw_http_mod.Acceptor = null;
    // BRAIN-GENERIC-MINT-VERB M1 — generic mint acceptor + boot-lifetime
    // arena for cartridge cellType string ownership.  The arena is
    // intentionally never deinit'd in production — strings live for the
    // brain process lifetime, mirroring substrate_entity's
    // registered_specs invariant.
    var cells_mint_acceptor: ?cells_mint_http_mod.Acceptor = null;
    // Betterment-practice pask sweep — wired when entity_cell_store_serve + token_store
    // are up AND --betterment-sweep-script is passed.  Absent any → endpoint stays 503.
    var betterment_sweep_acceptor: ?betterment_sweep_http_mod.Acceptor = null;
    var cartridge_boot_arena = std.heap.ArenaAllocator.init(allocator);
    // Intentionally NOT defer-deinit'd: registry holds references into
    // this arena for the brain process lifetime.
    // T8a — info_acceptor backing storage.  The acceptor borrows slices
    // (cert id, pubkey hex, manifest fields), so the storage lives in
    // cmdServe's stack frame for the lifetime of the SiteServer.
    var info_acceptor: ?info_http_mod.Acceptor = null;
    var info_brain_pin_cert_id: [identity_certs_mod.CERT_ID_HEX_LEN]u8 = undefined;
    var info_brain_pin_pubkey_hex: [bkds_mod.PUBKEY_LEN * 2]u8 = undefined;

    // T8b — voice-extract acceptor + bun-shell impl.  Both nullable;
    // wired only when --voice-extract-script + --voice-extract-cwd are
    // passed (the three flag vars are declared earlier alongside the
    // other endpoint flags).  Absence → endpoint stays 404.
    var voice_extract_shell: ?voice_extract_shell_mod.Shell = null;
    var voice_extract_acceptor: ?voice_extract_http_mod.Acceptor = null;
    var image_extract_shell: ?image_extract_shell_mod.Shell = null;
    var image_extract_acceptor: ?image_extract_http_mod.Acceptor = null;
    var audio_extract_shell: ?audio_extract_shell_mod.Shell = null;
    var audio_extract_acceptor: ?audio_extract_http_mod.Acceptor = null;

    // T6 — push-register acceptor (V2 gate; APNs/FCM token registration).
    // Wired when cert_store + token_store are up.  Endpoint stays 404
    // when either is absent.
    var push_register_acceptor: ?push_register_http_mod.Acceptor = null;

    // W2 of CUSTOMER-CONV-LOOP-PLAN — conversation-send acceptor.
    // conv_send_ctx — the shared bearer-validation context (token store), used by
    // the contacts / messagebox / attention / intent acceptors. C4 PR-I1: the
    // conversation-send acceptor + its Twilio config / sender / lookup vars moved
    // to the oddjobz cartridge over the route registry.
    var conv_send_ctx: ?ConvSendCtx = null;

    // C4 PR-H3 — search-contacts acceptor vars removed (route moved to the
    // oddjobz cartridge's route-registry registration).

    // C4 PR-I2 — twilio-inbound acceptor vars removed (webhook moved to the
    // oddjobz cartridge over the route registry).

    // D-brain-contacts-api — LMDB-backed contact book + HTTP acceptor.
    // Initialised after entity_cell_store_serve is ready.
    var contact_book_store: ?contact_book_lmdb_mod.ContactBookStore = null;
    defer if (contact_book_store) |*s| s.deinit();
    var contacts_acceptor: ?contacts_http_mod.Acceptor = null;

    // D-network-ipv6-session-keys — /128 address table (Tier 1 + T3).
    // Addresses are removed from the network interface when this table is freed.
    var ipv6_addr_table: ?ipv6_iface_mod.AddrTable = null;
    defer if (ipv6_addr_table) |*t| t.deinitAndRemoveAll();

    // D-network-messagebox-first-class — LMDB-backed BRC-77/78 relay.
    // Persists envelopes across brain restarts; replaces the ephemeral MemStore.
    var messagebox_lmdb_store: ?messagebox_lmdb_mod.MessageboxLmdbStore = null;
    defer if (messagebox_lmdb_store) |*s| s.deinit();
    var messagebox_acceptor: ?messagebox_http_mod.Acceptor = null;
    var messagebox_emit_ctx: ?MessageboxEmitCtx = null;

    // D-brain-intent-classifier-api — intent HTTP acceptor.
    // Wired when the dispatcher is available; delegates to
    // intent.classify / intent.taxonomy_snapshot dispatcher commands.
    var intent_acceptor: ?intent_http_mod.Acceptor = null;
    // D-brain-identity-store-api — hat + cert HTTP acceptor.
    // Wired when bearer_tokens store is available; delegates to
    // identity_certs_mod for cert lookups and bearer_tokens for hat list.
    var identity_ctx: ?IdentityCtx = null;
    var identity_acceptor: ?identity_http_mod.Acceptor = null;
    // D-brain-loom-store-api — dispatcher-backed typed REST surface.
    // Wired once the dispatcher is up + token_store is available.
    var loom_store_acceptor: ?loom_store_http_mod.Acceptor = null;
    // D-brain-flow-runner-api — in-memory run store + HTTP acceptor.
    // Arena-managed; all run state is lost on restart (V1 — durable
    // storage is D-brain-flow-runner-api phase-2).
    var flow_arena = std.heap.ArenaAllocator.init(allocator);
    defer flow_arena.deinit();
    var flow_run_store: ?FlowRunStore = null;
    var flow_acceptor: ?flow_http_mod.Acceptor = null;

    // T3 — OddjobzEventBus for the /api/v1/events WSS stream.  After
    // 2026-05-13 the bus is a fan-out adapter from NATS, not a parallel
    // producer: jobs_handler publishes only to NATS, the nats_event_bridge
    // (constructed below, after the bus + NATS are up) subscribes to NATS
    // and republishes fsm_transition events to this bus.
    var oddjobz_event_bus = oddjobz_event_bus_mod.OddjobzEventBus.init(allocator);
    defer oddjobz_event_bus.deinit();
    // The NATS-to-bus bridge.  Best-effort: a connect failure logs and
    // continues — /api/v1/events stays open but receives no events.
    var nats_event_bridge: ?nats_event_bridge_mod.Bridge = null;
    defer if (nats_event_bridge) |*b| b.deinit();
    // D-W1 Phase 1 Part 2 — identity_certs resource handler.  Bound
    // alongside bearer_tokens so D-O5p pairing flow (and `brain device
    // list/revoke`) talks to the same dispatcher seam.
    var cert_store: ?identity_certs_mod.CertStore = null;
    defer if (cert_store) |*cs| cs.deinit();
    var cert_handler: ?identity_certs_handler_mod.Handler = null;
    // D-O5p — POST /api/v1/device-pair acceptor.  Stood up after the
    // cert store + the operator priv (when present) is loaded; routed
    // by the SiteServer when a device-pair POST hits.
    var device_pair_acceptor: ?device_pair_http_mod.Acceptor = null;
    // D-W1 Phase 1 follow-up — `llm.*` resource handlers.  The
    // HttpLlmAdapter wraps the operator's loaded `LlmConfig` (mode
    // 0600 file at `<data_dir>/llm-config.json`); the dispatcher
    // handler wraps that with per-scope rate-limit + budget tracking
    // (`<data_dir>/llm-budgets.json`).
    var llm_cfg: ?llm_adapter.LlmConfig = null;
    defer if (llm_cfg) |*c| c.deinit(allocator);
    var llm_http_inst: ?llm_http_adapter_mod.HttpLlmAdapter = null;
    var llm_complete: ?llm_complete_handler_mod.Handler = null;
    defer if (llm_complete) |*h| h.deinit();
    var llm_transcribe: ?llm_transcribe_audio_handler_mod.Handler = null;
    var llm_embed: ?llm_embed_handler_mod.Handler = null;
    // D-W1 Phase 4 — SignedBundle mesh acceptor.  Bound only when
    // --signed-bundle-endpoint is supplied AND --enable-repl is also
    // set (the acceptor needs the dispatcher + cert store the REPL
    // boot path stands up).  See BRAIN-DISPATCHER-UNIFICATION.md §5.4.
    var bundle_acceptor: ?signed_bundle_transport_mod.BundleAcceptor = null;
    defer if (bundle_acceptor) |*a| a.deinit();
    // D-W2 Phase 2 — extension-bundle frame receive acceptor.  Bound
    // only when --bundle-frame-endpoint is supplied AND the tenant
    // manifest carries a [trusted_signers] block (otherwise there's
    // no signer set to verify against).  Default: SPV client is a
    // deny-all stub; v0.1 production deployments override with a
    // real SPV-light client (TODO: wire bsv-cli adapter).  See
    // BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md §10.
    var frame_acceptor: ?extension_subscribe_mod.FrameAcceptor = null;
    // D-O5m.followup-9 Phase B — push dispatchers + bridge.  Loaded
    // when `<data_dir>/push-config.json` exists; empty when absent.
    // The bridge struct owns the borrowed dispatcher pointers + the
    // cert-store handle; its address is stable for the duration of
    // cmdServe so the broker's PushHook can hold a pointer to it.
    var push_cfg: ?config.PushConfig = null;
    defer if (push_cfg) |*c| c.deinit();
    var apns_transport: ?push_http_transport_mod.StdHttpTransport = null;
    var fcm_transport: ?push_http_transport_mod.StdHttpTransport = null;
    // Sovereign-push D.3 — UnifiedPush transport.  Init alongside
    // APNs/FCM whenever push is enabled at all; UP is the libre
    // backend and has no signing material to gate on.
    var up_transport: ?push_http_transport_mod.StdHttpTransport = null;
    var apns_dispatcher: ?apns_dispatcher_mod.ApnsDispatcher = null;
    defer if (apns_dispatcher) |*a| a.deinit();
    var fcm_dispatcher: ?fcm_dispatcher_mod.FcmDispatcher = null;
    defer if (fcm_dispatcher) |*f| f.deinit();
    var up_dispatcher: ?unifiedpush_dispatcher_mod.UnifiedPushDispatcher = null;
    defer if (up_dispatcher) |*u| u.deinit();
    var push_dispatcher: ?push_dispatcher_mod.PushDispatcher = null;
    var push_bridge: ?PushBrokerBridge = null;
    var unix_server: ?*unix_socket_transport.Server = null;
    var unix_thread: ?std.Thread = null;
    defer if (unix_server) |s| {
        s.stop();
        if (unix_thread) |t| t.join();
        s.deinit();
    };

    if (enable_repl) {
        const brain_cfg_path = if (repl_config_path) |p| try allocator.dupe(u8, p) else try resolveDefaultConfigPath(allocator);
        defer allocator.free(brain_cfg_path);
        repl_backend = ReplBackend.bringUp(allocator, brain_cfg_path, out) catch |e| {
            try out.print("serve {s}: --enable-repl: failed to bring up REPL backend: {s}\n", .{ domain, @errorName(e) });
            return .file_io;
        };
        token_store = bearer_tokens_mod.TokenStore.init(allocator, data_dir_path, realClock) catch |e| {
            try out.print("serve {s}: --enable-repl: failed to open bearer-token store: {s}\n", .{ domain, @errorName(e) });
            return .file_io;
        };
        repl_session = repl_backend.?.makeSession();
        server.attachReplBackend(&token_store.?, &repl_session.?);
        // Brain 4.5 — share the same bearer-token store with the WSS wallet
        // endpoint; one operator-level token grants access to both
        // /api/v1/repl and /api/v1/wallet.
        wss_backend = wss_wallet_mod.Backend{
            .tokens = &token_store.?,
            .network = .mainnet,
            // D-O5.followup-4 — wire the broker so helm.subscribe
            // RPC routes register per-connection subscribers; jobs.
            // transition publishes "job.transitioned" events that
            // fan out to every subscriber.
            .helm_broker = &helm_broker_serve,
        };
        server.attachWalletBackend(&wss_backend.?);

        // Platform wallet architecture §3.2 — POST /api/v1/wallet-op.
        // Shares the same bearer-token store as the REPL + WSS wallet.
        // ARC URL is hardcoded; signing key comes from site.json.
        wallet_op_acceptor = wallet_op_http_mod.Acceptor{
            .tokens = &token_store.?,
            .outputs = server.outputs.store(),
            .signing_key_wif = server.config.signing_key_wif,
            .arc_url = wallet_op_http_mod.DEFAULT_ARC_URL,
        };
        server.attachWalletOpEndpoint(&wallet_op_acceptor.?);

        // T3 — wire the OddjobzEventBus onto the SiteServer so the
        // reactor's /api/v1/events upgrade handler can find it.  The
        // bus is constructed at the top of cmdServe; deinit fires when
        // cmdServe returns.  Producers (jobs/customers/visits/quotes/
        // invoices handlers) dual-publish to this bus alongside the
        // Pravega producer when their FSM transitions fire.
        server.attachEventsStreamBackend(&oddjobz_event_bus);

        // Tier 2P D.2 follow-up — JSONL file watcher.  Polls the two
        // attention JSONL paths on every reactor tick (~100 ms) and
        // publishes oddjobz.{message,dispatch}.appended topics when
        // mtime increases.  Mobile AttentionService already subscribes
        // — see `apps/oddjobz-mobile/lib/src/repl/attention_service.dart`.
        // Reads baseline mtimes at construction so a Semantos Brain restart does
        // NOT re-emit for pre-existing content.
        // W0.4: oddjobz_jsonl_watcher removed — mtime polling replaced by Pravega.

        // ── Stand up the dispatcher + Unix socket transport ──
        // Audit log shares the daemon's existing audit.log file (every
        // dispatch produces its start/end pair alongside the broker's
        // host_* audit lines).  Best-effort open: failure is non-fatal
        // because the dispatcher swallows record-time errors.
        disp_audit = audit_log_mod.AuditLog.init();
        disp_audit_path = try std.fs.path.join(allocator, &.{ data_dir_path, "audit.log" });
        disp_audit.?.open(disp_audit_path.?) catch {};

        // PR-3a-bridge-3 — boot-time drain of any anchor confirmations
        // the runner wrote while the brain was down.  Audit log is
        // now open and ready to receive entries.  In-process re-polls
        // are NOT wired this PR — operators cron a follow-up CLI
        // command (see anchor_confirmation_reader.zig doc-comment).
        if (anchor_confirmations_path_opt) |_| {
            var reader = anchor_confirmation_reader_mod.AnchorConfirmationReader.init(
                allocator,
                .{ .confirmations_path = anchor_confirmations_path_opt },
                &disp_audit.?,
            );
            reader.poll();
        }

        dispatcher_inst = dispatcher_mod.Dispatcher.init(allocator, &disp_audit.?);
        bearer_handler = bearer_tokens_handler_mod.Handler.init(allocator, &token_store.?);
        try dispatcher_inst.?.register(bearer_handler.?.resourceHandler());

        // W0.1: jobs_store_serve init is deferred to after entity_cell_store_serve
        // is available (see below).  Declared null at top of cmdServe scope.

        // W0.2 — open the shared entity LMDB env for customers, visits,
        // quotes, invoices, and attachments stores.  A single data dir
        // (`entity_cells_lmdb/` under data_dir_path) hosts all five
        // entity domains.  Best-effort: if the env open fails we leave
        // entity_cell_store_serve as null and all five entity stores
        // stay null below (harmless — each is gated on
        // entity_cell_store_serve != null before calling init).
        {
            const entity_lmdb_path = try std.fs.path.join(
                allocator,
                &.{ data_dir_path, "entity_cells_lmdb" },
            );
            defer allocator.free(entity_lmdb_path);
            std.fs.makeDirAbsolute(entity_lmdb_path) catch |e| switch (e) {
                error.PathAlreadyExists => {},
                else => try out.print("serve {s}: entity-cells lmdb dir create failed: {s}\n", .{ domain, @errorName(e) }),
            };
            entity_lmdb_env_serve = lmdb_mod.Env.open(entity_lmdb_path, .{
                .open_flags = lmdb_config_mod.LmdbConfig.prod_flags,
                .map_size = lmdb_config_mod.LmdbConfig.default.map_size,
                .max_dbs = lmdb_config_mod.LmdbConfig.default.max_dbs,
                .mode = lmdb_config_mod.LmdbConfig.default.mode,
            }) catch |e| blk: {
                try out.print("serve {s}: --enable-repl: failed to open entity-cells LMDB env: {s} (entity stores disabled)\n", .{ domain, @errorName(e) });
                break :blk null;
            };
        }
        std.debug.print("[debug] entity_lmdb_env_serve null={}\n", .{entity_lmdb_env_serve == null});
        if (entity_lmdb_env_serve) |*env| {
            entity_cell_store_impl_serve = lmdb_cell_store_mod.LmdbCellStore.init(env, allocator) catch |e| blk: {
                std.debug.print("[debug] LmdbCellStore.init failed: {s}\n", .{@errorName(e)});
                try out.print("serve {s}: --enable-repl: failed to init entity cell store: {s} (entity stores disabled)\n", .{ domain, @errorName(e) });
                break :blk null;
            };
            if (entity_cell_store_impl_serve) |*impl| {
                entity_cell_store_serve = impl.store();
                std.debug.print("[debug] entity cell store initialized ok\n", .{});
            } else {
                std.debug.print("[debug] entity_cell_store_impl_serve is null after init\n", .{});
            }
        } else {
            std.debug.print("[debug] entity_lmdb_env_serve is null — entity stores disabled\n", .{});
        }

        // Octave-1 escalation content store. Comes up alongside the
        // entity cell store so the encode walker can spill >768B
        // payloads and the jobs store can deref them on replay.
        content_store_serve = content_store_local_fs_mod.ContentStoreLocalFs.init(allocator, data_dir_path) catch |e| blk: {
            try out.print("serve {s}: octave-1 content store init failed: {s} (large payloads will be rejected)\n", .{ domain, @errorName(e) });
            break :blk null;
        };
        if (content_store_serve) |*cs| {
            std.debug.print("[debug] octave-1 content store ready: {s}\n", .{cs.dir_path});
        }

        // C4 PR-H2b-1 — the §6b oddjobz store cluster (jobs/customers/sites/
        // visits/quotes/estimates/invoices/attachments/leads stores + their
        // dispatcher handlers) is now constructed ONCE by
        // cartridges/oddjobz/brain/zig/registration.zig (registerInto, invoked
        // by cartridge_seam.dispatchRegistrations — moved up to just below, before
        // the store consumers, in PR-H2b-2). The
        // cartridge publishes the store pointers into store_registry_serve; the
        // brain's remaining store consumers read them through that registry. The
        // `find jobs`→attachments[] late-bind + the NATS-producer attach (below)
        // moved into registerInto with the handlers. The NATS client/producer/
        // bridge stay here (substrate event spine); deps.nats_producer hands the
        // producer to the cartridge's jobs handler.

        // W7.3 — NATS event spine.  Best-effort: if NATS is not running the
        // daemon starts normally and FSM transitions skip the NATS emit lane.
        // op_pkh16 = '0' × 16 → W7.2 boot operator (zero prefix).
        nats_client_serve = nats_client_mod.NatsClient.init(
            allocator,
            .{ .host = "127.0.0.1", .port = 4222 },
        ) catch |e| blk: {
            try out.print("serve {s}: NATS unavailable ({s}); event spine disabled\n", .{ domain, @errorName(e) });
            break :blk null;
        };
        if (nats_client_serve) |*nc| {
            const op_pkh16 = [_]u8{'0'} ** 16;
            nats_producer_serve = nats_event_producer_mod.NatsEventProducer.init(
                allocator,
                nc,
                op_pkh16,
            );
            nats_producer_serve.?.ensureStream() catch |e| {
                try out.print("serve {s}: NATS ensureStream failed ({s}); continuing\n", .{ domain, @errorName(e) });
            };
            // C4 PR-H2b-1 — the jobs handler's attachNatsProducer moved into the
            // oddjobz cartridge's registerInto (deps.nats_producer hands it the
            // producer constructed here).
            try out.print("serve {s}: NATS event spine connected (op_pkh=0000000000000000)\n", .{domain});

            // 2026-05-13 — start the NATS→bus bridge.  Subscribes to
            // op.> on its own TCP connection; republishes fsm_transition
            // events to the OddjobzEventBus.  Best-effort: a connect
            // failure logs and continues (events stream WSS clients
            // upgrade fine but receive no events until NATS recovers).
            nats_event_bridge = nats_event_bridge_mod.Bridge.init(
                allocator,
                &oddjobz_event_bus,
                .{ .nats_host = "127.0.0.1", .nats_port = 4222, .subject_pattern = "op.>" },
            );
            nats_event_bridge.?.start() catch |e| {
                try out.print("serve {s}: NATS-to-bus bridge start failed ({s}); /api/v1/events upgrades will succeed but no events will flow until brain restart with NATS up\n", .{ domain, @errorName(e) });
                nats_event_bridge = null;
            };
            if (nats_event_bridge != null) {
                try out.print("serve {s}: NATS-to-bus bridge subscribed (subject=op.>; events flow to /api/v1/events)\n", .{domain});
            }
        }

        // C4 PR-H2b-1 — the attachments + leads stores/handlers (and the rest of
        // the §6b cluster above) now live in the oddjobz cartridge's
        // registerInto; the `find jobs`→attachments[] late-bind is restored
        // there (both pointers co-located).

        // Phase 3 (W0.3) — typed `intent_cells` resource.  LMDB-backed.
        {
            const ic_lmdb_path = try std.fs.path.join(
                allocator,
                &.{ data_dir_path, "intent_cells_lmdb" },
            );
            defer allocator.free(ic_lmdb_path);
            std.fs.makeDirAbsolute(ic_lmdb_path) catch |e| switch (e) {
                error.PathAlreadyExists => {},
                else => try out.print("serve {s}: intent-cells lmdb dir create failed: {s}\n", .{ domain, @errorName(e) }),
            };
            intent_cells_env_serve = lmdb_mod.Env.open(ic_lmdb_path, .{
                .open_flags = lmdb_config_mod.LmdbConfig.prod_flags,
                .map_size = lmdb_config_mod.LmdbConfig.default.map_size,
                .max_dbs = lmdb_config_mod.LmdbConfig.default.max_dbs,
                .mode = lmdb_config_mod.LmdbConfig.default.mode,
            }) catch |e| blk: {
                try out.print("serve {s}: --enable-repl: failed to open intent-cells LMDB env: {s} (submit-intent-cell disabled)\n", .{ domain, @errorName(e) });
                break :blk null;
            };
        }
        if (intent_cells_env_serve) |*env| {
            intent_cells_store_serve = intent_cell_lmdb_store_mod.IntentCellLmdbStore.init(env, allocator) catch |e| blk: {
                try out.print("serve {s}: --enable-repl: failed to open intent-cells store: {s} (submit-intent-cell disabled)\n", .{ domain, @errorName(e) });
                break :blk null;
            };
        }
        if (intent_cells_store_serve) |*ics| {
            const cert_ptr_serve_ic: ?*identity_certs_mod.CertStore = if (cert_store) |*cs| cs else null;
            intent_cells_handler_serve = intent_cells_handler_mod.Handler.initWithDeps(
                allocator,
                ics,
                cert_ptr_serve_ic,
                &helm_broker_serve,
                &disp_audit.?,
            );
            try dispatcher_inst.?.register(intent_cells_handler_serve.?.resourceHandler());
        }

        // W0.5 — Pask snapshot store boot/shutdown wiring.
        // Open a dedicated `pask_snapshots_lmdb/` env under data_dir_path
        // so Pask state is isolated from the entity cell stores.  Uses the
        // operator root cert ID (when available) as the snapshot key.  On
        // boot we call loadCurrent and log the result; on shutdown (defer
        // below) we call commitSnapshot with a stub blob.
        //
        // TODO(W0.5-green): replace the stub blob with actual Pask kernel
        // serialisation once pask_interact_run's serialise_state() surface
        // is wired through the runner.  The stub satisfies the store's magic
        // check and ensures the boot/shutdown lifecycle is exercised from day
        // one without blocking on the WASM serialisation API.
        {
            const pask_lmdb_path = try std.fs.path.join(
                allocator,
                &.{ data_dir_path, "pask_snapshots_lmdb" },
            );
            defer allocator.free(pask_lmdb_path);
            std.fs.makeDirAbsolute(pask_lmdb_path) catch |e| switch (e) {
                error.PathAlreadyExists => {},
                else => try out.print("serve {s}: pask-snapshots lmdb dir create failed: {s}\n", .{ domain, @errorName(e) }),
            };
            pask_snapshots_env_serve = lmdb_mod.Env.open(pask_lmdb_path, .{
                .open_flags = lmdb_config_mod.LmdbConfig.prod_flags,
                .map_size = lmdb_config_mod.LmdbConfig.default.map_size,
                .max_dbs = lmdb_config_mod.LmdbConfig.default.max_dbs,
                .mode = lmdb_config_mod.LmdbConfig.default.mode,
            }) catch |e| blk: {
                try out.print("serve {s}: --enable-repl: failed to open pask-snapshots LMDB env: {s} (pask persistence disabled)\n", .{ domain, @errorName(e) });
                break :blk null;
            };
        }
        if (pask_snapshots_env_serve) |*env| {
            pask_snapshot_store_serve = pask_snapshot_store_lmdb_mod.LmdbPaskSnapshotStore.init(env, allocator) catch |e| blk: {
                try out.print("serve {s}: --enable-repl: failed to init pask-snapshots store: {s} (pask persistence disabled)\n", .{ domain, @errorName(e) });
                break :blk null;
            };
        }
        // Boot restore: if a prior snapshot exists for the operator root
        // cert, load it.  On first boot this returns null (no snapshot yet).
        if (pask_snapshot_store_serve) |*ps| {
            const vtable = ps.store();
            // Use the operator root cert ID when available; fall back to
            // the domain string as a stable per-brain key.
            // rootId() returns ?[CERT_ID_HEX_LEN]u8 — we copy to a
            // local array so we can take a slice.
            var root_id_buf: [identity_certs_mod.CERT_ID_HEX_LEN]u8 = undefined;
            const snap_cert_id: []const u8 = blk: {
                if (cert_store) |*cs| {
                    if (cs.rootId()) |rid| {
                        root_id_buf = rid;
                        break :blk &root_id_buf;
                    }
                }
                break :blk domain;
            };
            const snap_opt = vtable.loadCurrent(snap_cert_id, allocator) catch |e| blk: {
                try out.print("serve {s}: pask boot-restore: loadCurrent failed: {s} (starting fresh)\n", .{ domain, @errorName(e) });
                break :blk null;
            };
            if (snap_opt) |blob| {
                defer allocator.free(blob);
                try out.print("serve {s}: pask boot-restore: prior snapshot loaded (len={})\n", .{ domain, blob.len });
            } else {
                try out.print("serve {s}: pask boot-restore: no prior snapshot (first boot)\n", .{domain});
            }
        }

        // ── C4 PR-H2b-2 — cartridge dispatch, MOVED here (boot cartridges early) ──
        // The §6b store carve, phase "consumers after": the oddjobz cartridge's
        // registerInto constructs + publishes the typed-store cluster. Running it
        // HERE — before the store consumers below (intent_router / ratify / query /
        // attention + the store-coupled HTTP acceptors) — means they read a
        // POPULATED store_registry_serve. This is the architecturally-pure
        // boot-then-consume order: cartridges are foundational, booted before the
        // substrate wires up things that consume their state. (Replaces the
        // end-of-cmdServe dispatch + the H2b-1 transient degrade.)
        //
        // The mint-context registry is constructed here too (hoisted from the
        // cell.create block below) so deps.mint_context_registry is ready for the
        // mnca cartridge's builder append. The mint HANDLER + setContextBuilder
        // stay below (they read the registry's children live at dispatch time).
        cells_mint_registry = .{};
        if (dynamic_setup) |*rt| {
            cells_mint_spv_header_store = rt.header_fs.store();
            cells_mint_spv_ctx_state = .{
                .headers = &cells_mint_spv_header_store.?,
            };
            cells_mint_registry.?.add(
                cells_mint_spv_context_mod.toBuilder(&cells_mint_spv_ctx_state.?),
            );
        } else {
            try out.print(
                "serve {s}: cells mint handler registry has no SPV builder (no dynamic runtime → no HeaderStore); bsv.spv.verify.intent mints will trap on host_verify_beef_spv until the dynamic runtime is wired. The MNCA-anchor-transition builder is appended separately by the mnca cartridge's registerInto (PR-E2), independent of dynamic_setup.\n",
                .{domain},
            );
        }
        if (entity_cell_store_serve) |*ecs_vt| {
            if (token_store) |*ts| {
                if (dispatcher_inst) |*disp| {
                    const manifests = extensions_mod.enumerateUserInstalled(allocator, data_dir_path) catch |e| blk: {
                        std.log.warn("cartridge_seam: manifest enumeration failed: {s} — skipping dispatch", .{@errorName(e)});
                        break :blk @as([]extension_manifest_loader.ExtensionManifest, &.{});
                    };
                    defer extension_manifest_loader.deinitManifests(allocator, @constCast(manifests));

                    // C4 CW-3 — load the operator profile so the cartridge chat
                    // route can bind its endpoint to operator policy. Best-effort:
                    // a missing/invalid profile.json null-degrades to the
                    // cartridge's default endpoint. Arena-owned by `allocator`
                    // (serve lifetime); no deinit (process exit reclaims).
                    // DO-1: assigns the function-scoped holder (the substrate `site`
                    // handler borrows it past this block) rather than shadowing it.
                    operator_profile_holder =
                        operator_profile_loader_mod.loadForDomain(allocator, data_dir_path, domain) catch null;

                    // CC-3 — resolve the operator's 16-byte cell ownerId from the
                    // operator root cert-id (32-hex → 16 bytes). Threaded into the
                    // cartridge so its job cells are OWNER-BOUND (UTXO-binding
                    // eligible). Null when no operator cert exists yet.
                    const operator_owner_id: ?[16]u8 = blk: {
                        const cs = if (cert_store) |*c| c else break :blk null;
                        const rid = cs.rootId() orelse break :blk null;
                        var owner: [16]u8 = [_]u8{0} ** 16;
                        var oi: usize = 0;
                        while (oi < 16 and (oi * 2 + 1) < rid.len) : (oi += 1) {
                            const hi = std.fmt.charToDigit(rid[oi * 2], 16) catch break;
                            const lo = std.fmt.charToDigit(rid[oi * 2 + 1], 16) catch break;
                            owner[oi] = (@as(u8, hi) << 4) | @as(u8, lo);
                        }
                        break :blk owner;
                    };
                    const deps = cartridge_seam.CartridgeDeps{
                        .cell_store = ecs_vt,
                        .broker = &helm_broker_serve,
                        .bearer_tokens = ts,
                        .audit_log = if (disp_audit) |*a| a else null,
                        .mint_context_registry = if (cells_mint_registry) |*r| r else null,
                        .route_registry = &route_registry_serve,
                        .site_data_dir = data_dir_path,
                        .content_store = if (content_store_serve) |*cs| cs else null,
                        .nats_producer = if (nats_producer_serve) |*np| np else null,
                        .store_registry = &store_registry_serve,
                        // C4 PR-J2 — the cell-decoder registry, for the cartridge
                        // to register its cell.query decoders.
                        .cell_decoder_registry = &cell_decoder_registry_serve,
                        // C4 PR-J4 — the attention-source registry (future
                        // cartridges register namespace-scoped signal sources).
                        .attention_source_registry = &attention_source_registry_serve,
                        // C4 PR-J5 — the ratify-builder registry (future
                        // cartridges register a graph builder per namespace).
                        .ratify_builder_registry = &ratify_builder_registry_serve,
                        // C4 PR-H7a — the identity cert store, for the oddjobz
                        // attachments-upload route's cell-signature verification
                        // (migrates over the seam in PR-H7b). Null-degrades.
                        .cert_store = if (cert_store) |*cs| cs else null,
                        // C4 CW-3 — operator-policy seam (chat route endpoint binding).
                        .operator_profile = if (operator_profile_holder) |*p| p else null,
                        // CC-3 — operator ownerId for owner-bound (UTXO-bindable) cells.
                        .operator_owner_id = operator_owner_id,
                        // DO-1 — the `do` verb registry (cartridges register their
                        // own do-verbs here; substrate verbs added at boot).
                        .do_verb_registry = &do_registry_serve,
                        // C4 PR-R3 — the cartridge REPL verb registry. Cartridges
                        // register `find jobs` / `find attention` / FSM transition /
                        // conversation verbs here; attached to repl_session below so
                        // they route over repl.eval (the unified channel), not just
                        // the CLI repl.
                        .repl_verb_registry = &repl_verb_registry_serve,
                    };
                    cartridge_seam.dispatchRegistrations(disp, allocator, &deps, manifests) catch |e| {
                        try out.print("cartridge_seam: dispatch failed: {s}\n", .{@errorName(e)});
                        return .config_error;
                    };
                    try out.print("  Cartridge seam: dispatched {d} loaded manifest(s)\n", .{manifests.len});
                }
            }
        }

        // Tier 3 — brain-side intent → jobs FSM router.  Subscribes
        // to the broker on init so a phone-typed `quote $500 for the
        // wattle street job` flips the matching job from `lead` to
        // `quoted` automatically.  Gated behind
        // `--enable-intent-action-router` (or `BRAIN_INTENT_ROUTER=1`)
        // — OFF by default.  Construction requires the dispatcher +
        // a live jobs store; both are stood up earlier in this
        // --enable-repl block, so we only need to test the gate +
        // jobs-store presence here.
        // C4 PR-H2b — reads the jobs store through the registry (§6b seam),
        // populated by the cartridge dispatch that now runs just above (PR-H2b-2
        // boot-cartridges-early), so the registry is filled by here.
        if (enable_intent_router) {
            if (store_registry_serve.jobs) |js| {
                intent_action_router_serve = intent_action_router_mod.Router.init(
                    allocator,
                    &helm_broker_serve,
                    js,
                    &dispatcher_inst.?,
                    &disp_audit.?,
                    true,
                ) catch |e| blk: {
                    try out.print(
                        "serve {s}: --enable-intent-action-router: failed to construct router: {s} (router disabled)\n",
                        .{ domain, @errorName(e) },
                    );
                    break :blk null;
                };
                if (intent_action_router_serve) |r| {
                    server.attachIntentRouter(r);
                    try out.print("[intent-router] subscribed to broker (gate=ON)\n", .{});
                }
                // Tier 3 follow-up — visit-rollup router. Shares the
                // intent-router gate. On `visit.transitioned`→completed
                // it rolls the parent job to `visited` via
                // jobs.transition (needs only broker + dispatcher).
                visit_rollup_router_serve = visit_rollup_router_mod.Router.init(
                    allocator,
                    &helm_broker_serve,
                    &dispatcher_inst.?,
                    &disp_audit.?,
                    true,
                ) catch |e| blk: {
                    try out.print(
                        "serve {s}: visit-rollup router: failed to construct: {s} (rollup disabled)\n",
                        .{ domain, @errorName(e) },
                    );
                    break :blk null;
                };
                if (visit_rollup_router_serve) |r| {
                    server.attachVisitRollupRouter(r);
                    try out.print("[visit-rollup] subscribed to broker (gate=ON)\n", .{});
                }
                // Slice 4 — quote-seed router. Shares the intent-router
                // gate. On `job.transitioned` qualified→quoted it seeds
                // a DRAFT Quote from the job's accepted ROM Estimate
                // (estimates.find → quotes.create via the dispatcher).
                quote_seed_router_serve = quote_seed_router_mod.Router.init(
                    allocator,
                    &helm_broker_serve,
                    &dispatcher_inst.?,
                    &disp_audit.?,
                    true,
                ) catch |e| blk: {
                    try out.print(
                        "serve {s}: quote-seed router: failed to construct: {s} (seed disabled)\n",
                        .{ domain, @errorName(e) },
                    );
                    break :blk null;
                };
                if (quote_seed_router_serve) |r| {
                    server.attachQuoteSeedRouter(r);
                    try out.print("[quote-seed] subscribed to broker (gate=ON)\n", .{});
                }
            } else {
                try out.print(
                    "serve {s}: --enable-intent-action-router requires the jobs store; skipping (router disabled)\n",
                    .{domain},
                );
            }
        }

        // C4 PR-H2b-1 — the sites store (and the rest of the §6b cluster) is now
        // constructed + published into store_registry_serve by the oddjobz
        // cartridge's registerInto (later in cmdServe, at dispatchRegistrations).
        // serve no longer constructs or publishes the cluster; the H2a publish
        // block is gone. The store consumers below read store_registry_serve,
        // which the cartridge fills at dispatch — they degrade transiently
        // (null) until PR-H2b-2 relocates them past the dispatch point.

        // D-brain-contacts-api — contact book backed by the entity cell store.
        // Best-effort: failure leaves contacts_acceptor null and the endpoints
        // return 404.  Requires entity_cell_store_serve to be available.
        // Acceptor wiring (bearer auth) runs later once conv_send_ctx is set.
        if (entity_cell_store_serve) |*ecs| {
            contact_book_store = contact_book_lmdb_mod.ContactBookStore.init(allocator, ecs, realClock) catch |e| blk: {
                try out.print("serve {s}: failed to open contact book store: {s} (contacts API disabled)\n", .{ domain, @errorName(e) });
                break :blk null;
            };
        }

        // D-brain-intent-classifier-api — /api/v1/intent/* acceptor.
        // Needs dispatcher (intent.classify / intent.taxonomy_snapshot)
        // + bearer tokens.  Best-effort: if the dispatcher isn't up yet,
        // endpoints return 404.
        if (dispatcher_inst != null and conv_send_ctx != null) {
            intent_acceptor = intent_http_mod.Acceptor{
                .allocator = allocator,
                .is_bearer_valid = convSendIsBearerValid,
                .is_bearer_valid_ctx = &conv_send_ctx.?,
                .classify = intentClassify,
                .classify_ctx = &dispatcher_inst.?,
                .get_taxonomy = intentTaxonomySnapshot,
                .get_taxonomy_ctx = &dispatcher_inst.?,
            };
            server.attachIntentEndpoint(&intent_acceptor.?);
            try out.print("  Intent:       POST /api/v1/intent/classify + GET /api/v1/intent/taxonomy (dispatcher wired)\n", .{});
        }

        // D-brain-identity-store-api — /api/v1/identity/* acceptor.
        // Wired when token_store is ready (bearer_tokens).  Derives
        // hat info from TokenRecord fields; cert_id gap deferred to T7.
        if (token_store) |*ts| {
            if (conv_send_ctx) |*csc| {
                identity_ctx = IdentityCtx{
                    .token_store = ts,
                    .allocator = allocator,
                };
                identity_acceptor = identity_http_mod.Acceptor{
                    .allocator = allocator,
                    .is_bearer_valid = convSendIsBearerValid,
                    .is_bearer_valid_ctx = csc,
                    .get_active_hat = identityGetActiveHat,
                    .get_active_hat_ctx = &identity_ctx.?,
                    .list_hats = identityListHats,
                    .list_hats_ctx = &identity_ctx.?,
                };
                server.attachIdentityEndpoint(&identity_acceptor.?);
                try out.print(
                    "  Identity: GET /api/v1/identity/hat + /hats + /cert\n",
                    .{},
                );
            }
        }

        // D-brain-loom-store-api — wire the typed loom-objects REST surface.
        // Requires token_store (bearer auth) + the dispatcher (find/find_by_id).
        if (token_store) |*ts| {
            if (dispatcher_inst) |*disp| {
                loom_store_acceptor = loom_store_http_mod.Acceptor{
                    .allocator = allocator,
                    .is_bearer_valid = loomIsBearerValid,
                    .is_bearer_valid_ctx = ts,
                    .find_objects = loomFindObjects,
                    .find_objects_ctx = disp,
                    .find_object_by_id = loomFindObjectById,
                    .find_object_by_id_ctx = disp,
                };
                server.attachLoomStoreEndpoint(&loom_store_acceptor.?);
                try out.print(
                    "  LoomStore: GET /api/v1/objects/{{type}}[/{{id}}]\n",
                    .{},
                );
            }
        }

        // D-brain-flow-runner-api — in-memory flow execution state machine.
        // Wired when token_store is available.  All run state is lost on
        // restart; durable storage deferred to phase-2.
        if (token_store) |*ts| {
            const fa = flow_arena.allocator();
            flow_run_store = FlowRunStore.init(fa);
            flow_acceptor = flow_http_mod.Acceptor{
                .allocator = allocator,
                .is_bearer_valid = flowIsBearerValid,
                .is_bearer_valid_ctx = ts,
                .start_flow = flowStartRun,
                .start_flow_ctx = &flow_run_store.?,
                .get_flow_state = flowGetState,
                .get_flow_state_ctx = &flow_run_store.?,
                .step_flow = flowStepRun,
                .step_flow_ctx = &flow_run_store.?,
            };
            server.attachFlowEndpoint(&flow_acceptor.?);
            try out.print(
                "  Flow: POST /api/v1/flow/run, GET/POST /api/v1/flow/{{runId}}[/step]\n",
                .{},
            );
        }

        // D-DOG.1.0c Phase 2A.4 — oddjobz Layer-2 ratify seam, graph-
        // walk rewrite.  Bring up AFTER the four typed view-stores
        // (sites + customers + jobs + attachments) are open so the
        // handler can hold direct pointers to all four.  No dispatcher
        // dependency anymore: the handler walks the SIRProgram +
        // payload_hint into a graph of cells (site + customers + job
        // + attachments) by calling each store's typed append /
        // lookup-or-mint API directly.
        //
        // Best-effort: a init failure (e.g. ratifications.jsonl perm
        // issue) leaves wss_backend.oddjobz_ratify null and the
        // `oddjobz.ratify_proposal` RPC returns -32603.  Stores that
        // failed to open above flow through as null pointers in the
        // RatifyStores bag; the handler refuses to mint a graph if
        // any required store is absent (returns store_append_failed).
        // D-DOG.1.0c Phase 4 row B.1 — bring up the hat-key BKDS
        // signer.  v0 sources the root from a deterministic seed
        // tied to the data_dir path so the same brain produces
        // stable signatures across restarts (idempotent re-sign of
        // the same cell content yields byte-identical signatures —
        // the matrix §2 recovery property).  Production will swap
        // this for a wallet-KEK-decrypted scalar once D-O5p's
        // operator-root-priv source lands; until then this is the
        // dogfood path.
        const hat_seed = try std.fmt.allocPrint(
            allocator,
            "oddjobz.hat-key-root/v0:{s}",
            .{data_dir_path},
        );
        defer allocator.free(hat_seed);
        var hat_signer: ?hat_bkds_mod.HatBkds = hat_bkds_mod.HatBkds.initFromSeed(hat_seed) catch |e| blk_hs: {
            try out.print(
                "serve {s}: --enable-repl: failed to bring up hat-key BKDS signer: {s} (cells will mint unsigned; brain resign-pending can backfill)\n",
                .{ domain, @errorName(e) },
            );
            break :blk_hs null;
        };
        defer if (hat_signer) |*h| h.deinit();

        // C4 PR-H2a — read the typed stores through the registry (the §6b seam)
        // rather than the serve-local vars. Identical pointers today; in H2b the
        // cartridge publishes them.
        const ratify_stores: oddjobz_ratify_handler_mod.RatifyStores = .{
            .sites = store_registry_serve.sites,
            .customers = store_registry_serve.customers,
            .jobs = store_registry_serve.jobs,
            .attachments = store_registry_serve.attachments,
            .hat_bkds = if (hat_signer) |*h| h else null,
        };
        oddjobz_ratify_serve = oddjobz_ratify_handler_mod.Handler.init(
            allocator,
            ratify_stores,
            data_dir_path,
            realClock,
        ) catch |e| blk: {
            try out.print(
                "serve {s}: --enable-repl: failed to bring up oddjobz ratify seam: {s} (oddjobz.ratify_proposal RPC disabled)\n",
                .{ domain, @errorName(e) },
            );
            break :blk null;
        };
        if (oddjobz_ratify_serve) |*h| {
            // C4 PR-J5b — oddjobz ratify is reached ONLY via the generic
            // namespace-routed `ratify.submit` now (the legacy
            // `oddjobz.ratify_proposal` method + `wss_backend.oddjobz_ratify`
            // field were retired). Register oddjobz as the "oddjobz" builder;
            // the thunk drives the same handler instance through the walker.
            ratify_builder_registry_serve.add(.{
                .namespace = "oddjobz",
                .label = "graph",
                .ctx = @ptrCast(h),
                .submit = oddjobzRatifySubmit,
            });
            ratify_submit_serve = ratify_submit_handler_mod.Handler{ .registry = &ratify_builder_registry_serve };
            wss_backend.?.ratify = &ratify_submit_serve.?;
        }

        // Generic verb dispatcher — construct the registry. (C4 PR-J5b: the
        // oddjobz_ratify walker registration was removed; ratification is
        // driven via the generic `ratify.submit` builder registry now, not
        // `verb.dispatch`. The registry stays for the other walkers
        // registered below + by cartridges.)
        verb_registry_serve = verb_dispatcher_mod.Registry.init(allocator);
        // Universal cartridge registration. THIS LOCATION (inside the
        // `--enable-repl` compilation-substrate block) is gate 1,
        // preserved verbatim from the legacy per-cartridge registerAll
        // calls (jambox, …) that lived right here. Gate 2 (per-cartridge
        // marketplace entitlement) defaults to grantAll — zero behaviour
        // change; the licensing mechanism is the §6b follow-up.
        if (cart_runtime) |*r| {
            // P3d — late-bind the entity CellStore into cartridge State
            // (the store comes up above, in this --enable-repl block,
            // AFTER constructAll at top scope). Cartridges that opt in
            // (via the boot table's bind_cell_store hook) persist minted
            // cells; those that don't are unaffected. Mirrors the
            // entity_encode_walker ecs wiring below; harmless for
            // un-registered cartridges (inert State). [no cartridge id
            // named here — greenfield gate keeps brain-core src/ clean]
            if (entity_cell_store_serve) |*ecs| r.bindCellStore(ecs);
            r.registerInto(&verb_registry_serve.?, cartridge_boot_mod.grantAll) catch |e| {
                std.debug.print(
                    "serve {s}: failed to register cartridge walkers: {s} (verb.dispatch will not route cartridge verbs)\n",
                    .{ domain, @errorName(e) },
                );
            };
        }
        // D-RTC.4 — wire the entity cell store into the entity.encode
        // walker state (when the store is up), then register the
        // walker. Registration succeeds even without the store —
        // walker returns persisted=false in that case.
        if (entity_cell_store_serve) |*ecs| {
            entity_encode_walker_state.cell_store = ecs;
        }
        if (content_store_serve) |*cs| {
            entity_encode_walker_state.content_store = cs;
        }
        entity_encode_walker_mod.registerInto(&verb_registry_serve.?, &entity_encode_walker_state) catch |e| {
            std.debug.print(
                "serve {s}: failed to register entity.encode walker: {s} (verb.dispatch will not route substrate/entity.encode)\n",
                .{ domain, @errorName(e) },
            );
        };
        // substrate.find_overdue_jobs — shares the entity cell store
        // pointer; degrades to store_unavailable when absent.
        if (entity_cell_store_serve) |*ecs| {
            overdue_jobs_walker_state.cell_store = ecs;
        }
        overdue_jobs_walker_mod.registerInto(&verb_registry_serve.?, &overdue_jobs_walker_state) catch |e| {
            std.debug.print(
                "serve {s}: failed to register find_overdue_jobs walker: {s} (verb.dispatch will not route substrate/find_overdue_jobs)\n",
                .{ domain, @errorName(e) },
            );
        };
        // substrate.find_pipeline_gaps — same shared cell store; the
        // Sunday "what's stuck before quoting" worklist.
        if (entity_cell_store_serve) |*ecs| {
            pipeline_gaps_walker_state.cell_store = ecs;
        }
        pipeline_gaps_walker_mod.registerInto(&verb_registry_serve.?, &pipeline_gaps_walker_state) catch |e| {
            std.debug.print(
                "serve {s}: failed to register find_pipeline_gaps walker: {s} (verb.dispatch will not route substrate/find_pipeline_gaps)\n",
                .{ domain, @errorName(e) },
            );
        };
        wss_backend.?.verb_registry = &verb_registry_serve.?;

        // Manifest registry — append-only JSONL log under
        // `<data_dir>/extensions/manifests.jsonl`. Installs survive
        // restart; field shells push their verified manifests to the
        // brain via manifest.install once pairing completes;
        // manifest.list returns the recorded set so other paired shells
        // discover them. Falls back to in-memory if the persistent
        // init fails (logged + the verb-dispatch path still works for
        // the current session).
        manifest_registry_serve = manifest_registry_mod.Registry.initPersistent(
            allocator,
            data_dir_path,
            realClock,
        ) catch |e| blk: {
            std.debug.print(
                "serve {s}: manifest registry persistence init failed: {s} (falling back to in-memory; installs will NOT survive restart)\n",
                .{ domain, @errorName(e) },
            );
            break :blk manifest_registry_mod.Registry.init(allocator, realClock);
        };
        wss_backend.?.manifest_registry = &manifest_registry_serve.?;

        // C4 PR-J3 — the bespoke oddjobz cross-store query handler + its
        // wss_backend.oddjobz_query seam were retired. Reads now go through the
        // generic cell.query/cell.get (below), keyed by typeHash alias; oddjobz
        // registers its decoders in registerInto. (oddjobz_query_handler.zig
        // stays — its *ToJson encoders are reused by those decoders.)

        // C4 PR-J2 — generic cell.query primitive: enumerates via the
        // cells_by_type index + dispatches to cartridge-registered decoders
        // (cell_decoder_registry, populated by the cartridge at dispatch below).
        // No longer wraps oddjobz_query. Holds the entity cell store + the
        // decoder-registry pointer (read at request time, after dispatch).
        if (entity_cell_store_serve) |*ecs| {
            cell_query_serve = cell_query_handler_mod.Handler{
                .cell_store = ecs,
                .registry = &cell_decoder_registry_serve,
            };
            wss_backend.?.cell_query = &cell_query_serve.?;
        }

        // Pre-register substrate methods on the unified WSS RPC channel now
        // that their backing handlers exist (stable addresses for cmdServe's
        // lifetime). cell.query is a read (no extra cap beyond a valid
        // upgrade); repl.eval dispatches FSM verbs so it requires the operator
        // capability (M0: any valid upgrade is admin-equivalent, so this passes
        // — the gate becomes load-bearing when cert→cap-set derivation lands).
        if (cell_query_serve) |*cq| {
            rpc_registry_serve.add(.{
                .name = "cell.query",
                .state = @ptrCast(cq),
                .handle = &wss_rpc_methods.cellQuery,
            });
            // B3 — single-cell-by-ref read. Same handler + read posture as
            // cell.query (no extra cap beyond a valid upgrade).
            rpc_registry_serve.add(.{
                .name = "cell.get",
                .state = @ptrCast(cq),
                .handle = &wss_rpc_methods.cellGet,
            });
            // Wire the same handler into the REPL session so the shell-native
            // `query <noun>` primitive (find → cell.query) reaches the substrate
            // over `repl.eval` + the interactive REPL.
            if (repl_session) |*rs| rs.cell_query_handler = cq;
        }
        if (repl_session) |*rs| {
            rpc_registry_serve.add(.{
                .name = "repl.eval",
                .required_cap = "cap.brain.admin",
                .state = @ptrCast(rs),
                .handle = &wss_rpc_methods.replEval,
            });
        }

        // Tier 2P Phase B — attention JSONL reader seam.  Best-effort:
        // if the oddjobz dir doesn't exist yet init creates it; failure
        // leaves the three attention verbs returning -32603 without
        // breaking any other endpoint.
        oddjobz_attention_serve = oddjobz_attention_handler_mod.Handler.init(
            allocator,
            data_dir_path,
            store_registry_serve.jobs,
        ) catch |e| blk: {
            try out.print(
                "serve {s}: --enable-repl: failed to bring up oddjobz attention seam: {s} (attention RPCs disabled)\n",
                .{ domain, @errorName(e) },
            );
            break :blk null;
        };
        if (oddjobz_attention_serve) |*h| {
            wss_backend.?.oddjobz_attention = h;

            // C4 PR-J4 — register oddjobz's 3 attention sources (namespace
            // "oddjobz") into the source registry, pointing at the handler above.
            // (Interim: serve registers them since the oddjobz attention handler
            // is serve-owned; moves into the cartridge's registerInto later.)
            const ah_ctx: *anyopaque = @ptrCast(h);
            attention_source_registry_serve.add(.{ .namespace = "oddjobz", .label = "dispatch", .ctx = ah_ctx, .collect = oddjobzDispatchSource });
            attention_source_registry_serve.add(.{ .namespace = "oddjobz", .label = "message", .ctx = ah_ctx, .collect = oddjobzMessageSource });
            attention_source_registry_serve.add(.{ .namespace = "oddjobz", .label = "job", .ctx = ah_ctx, .collect = oddjobzJobSource });
        }

        // SH7 / D15 — shell-native attention sources (namespace "shell"),
        // registered UNCONDITIONALLY (not cartridge-gated) so a pure-brain shell
        // still has a useful feed for attention.poll(ns=["shell"]).
        shell_identity_ctx = .{
            .token_store = if (token_store) |*ts| ts else null,
            .has_recovery = false, // no recovery-envelope store on main (C6b future)
        };
        attention_source_registry_serve.add(.{ .namespace = "shell", .label = "identity", .ctx = @ptrCast(&shell_identity_ctx), .collect = shellIdentitySource });
        attention_source_registry_serve.add(.{ .namespace = "shell", .label = "ratify", .ctx = @ptrCast(&shell_identity_ctx), .collect = shellRatifySource });

        // C4 PR-J4 — the generic namespace-scoped attention poll over the source
        // registry (read at request time, after dispatch + the registrations
        // above). wss_backend.attention serves the new attention.poll method.
        attention_poll_serve = attention_poll_handler_mod.Handler{ .registry = &attention_source_registry_serve };
        wss_backend.?.attention = &attention_poll_serve.?;

        // D-O5.followup-5 — site_config.read / site_config.write for
        // the helm SPA's editor view.  Routes into the same on-disk
        // <data_dir>/sites/<domain>/site.json that site_server.zig
        // serves routes from; helm reads/writes via /api/v1/repl
        // through this handler.  The sites_dir slice is heap-allocated
        // at the cmdServe-frame scope so it outlives the dispatcher.
        site_config_sites_dir_serve = try std.fs.path.join(
            allocator,
            &.{ data_dir_path, "sites" },
        );
        site_config_handler_serve = site_config_handler_mod.Handler.init(
            allocator,
            site_config_sites_dir_serve.?,
        );
        try dispatcher_inst.?.register(site_config_handler_serve.?.resourceHandler());

        // admin-create-cell Phase D.3 — generic cell.create resource.
        // Shares the same LmdbCellStore the entity stores use.
        if (entity_cell_store_serve) |*ecs| {
            // §11.10 order 3a PR-3a-bridge-2b — production wiring with
            // broker handle so the AnchorEmitter dispatches in .bsv
            // mode, publishing "cell.created" events for the wallet-
            // headers cartridge subscriber.
            cell_handler_serve = cell_handler_mod.Handler.initWithBroker(
                allocator,
                ecs,
                &helm_broker_serve,
            );
            try dispatcher_inst.?.register(cell_handler_serve.?.resourceHandler());

            // BRAIN-GENERIC-MINT-VERB M3 — REPL `cells mint` resource.
            // Same pipeline as the HTTP path (cells_mint_http +
            // substrate_entity.encodeFromTypeHash); operator CLI surface.
            cells_mint_handler_serve = cells_mint_handler_mod.Handler.init(
                allocator,
                ecs,
                &helm_broker_serve,
            );

            // Unblocker #40 — wire the cell-script ContextBuilder
            // composite for the mint handler. Pre-#40 this whole block
            // gated on `dynamic_setup` being non-null because the
            // PR-3e SPV builder needs the FsHeaderStore the dynamic
            // runtime owns. That coupling meant the MNCA builder
            // (which doesn't depend on the header store — it only
            // uses cell_store) was also gated, so a static-only site
            // config (e.g. the PR-8b-vii smoke harness) had to add a
            // throwaway `dynamic` stub route just to flip
            // `has_dynamic = true`. Now the two builders are wired
            // independently: MNCA always wires (cell-store is always
            // up by this point in cmdServe); SPV wires only when the
            // dynamic runtime is up.
            //
            // The composite's children slice is sized at runtime to
            // the actually-wired-builder count (1 = MNCA only, 2 =
            // MNCA + SPV). The composite walker tries each child in
            // declaration order; each builder gates on its own
            // typeHash and returns null on mismatch, so order is
            // functionally irrelevant for the composite-walker
            // dispatch path. We list MNCA first so static-only sites
            // see the same builder slot (slot 0) the SPV-equipped
            // sites do, in case future ordering invariants matter.
            //
            // C4 PR-H2b-2 — the mint-context registry (cells_mint_registry) + the
            // SPV builder add were HOISTED up to the cartridge-dispatch site
            // (boot cartridges early) so deps.mint_context_registry is ready when
            // the mnca cartridge appends its builder. The registry is already
            // constructed by here; the handler reads its children live, so this
            // setContextBuilder + register stay.
            cells_mint_handler_serve.?.setContextBuilder(
                cells_mint_registry.?.toBuilder(),
            );

            try dispatcher_inst.?.register(cells_mint_handler_serve.?.resourceHandler());
        }

        // C4 PR-H6 — the content-addressable blob store is now constructed +
        // owned by the oddjobz cartridge (registerInto, over deps.site_data_dir)
        // + published via the store registry. The blob-GET route moved to the
        // cartridge; the upload acceptor (wired after cert_store, below) reads
        // the blob store back through store_registry_serve.attachment_blobs.

        // Wire the dispatcher into the HTTP-REPL path's session so
        // POST /api/v1/repl `find jobs` / `find customers` traffic
        // from the helm SPA routes through the typed resources.
        // Without this the session.dispatcher is null and the verbs
        // fall back to the legacy "unknown command" arm — exactly the
        // bug D-O5.followup-1 was filed to close.
        repl_session.?.dispatcher = &dispatcher_inst.?;
        // Also wire repl shims so `status` / `help` over HTTP keep
        // working post-Phase-0 (the repl_session created via
        // makeSession() does not call registerReplShims itself).
        try repl_mod.registerReplShims(&dispatcher_inst.?, &repl_session.?);

        // DO-1 — register the substrate `site` operator resource (chat-widget
        // policy) + expose the `do` verb registry on the HTTP-REPL session so the
        // helm reaches `do manage site widget` over POST /api/v1/repl. The site
        // handler borrows the function-scoped operator profile (brain lifetime);
        // heap-allocated so the dispatcher's borrowed state outlives this block.
        const site_h = try allocator.create(site_handler_mod.Handler);
        site_h.* = site_handler_mod.Handler.init(
            allocator,
            if (operator_profile_holder) |*p| p else null,
            &helm_broker_serve,
            data_dir_path,
            domain,
        );
        try dispatcher_inst.?.register(site_h.resourceHandler());
        repl_session.?.do_verb_registry = &do_registry_serve;
        // C4 PR-R3 — attach the cartridge REPL verb registry the seam populated,
        // so repl.eval over /api/v1/rpc reaches `find jobs`/`find attention`/FSM/
        // conversation verbs (not just CLI repl). The registry is populated during
        // cartridge construction above; this hands the SAME instance to the session.
        repl_session.?.repl_verb_registry = &repl_verb_registry_serve;

        // ── D-W1 Phase 1 Part 2 — identity_certs resource ──
        // Same data_dir; identity-certs.log is the cert chain's log
        // sibling to bearer-tokens.log.  Best-effort init: failure is
        // surfaced as a startup error because D-O5p pairing depends on
        // it, but the rest of the daemon can still serve.
        cert_store = identity_certs_mod.CertStore.init(allocator, data_dir_path, realClock) catch |e| {
            try out.print("serve {s}: --enable-repl: failed to open identity-certs store: {s}\n", .{ domain, @errorName(e) });
            return .file_io;
        };
        cert_handler = identity_certs_handler_mod.Handler.init(allocator, &cert_store.?);
        try dispatcher_inst.?.register(cert_handler.?.resourceHandler());

        // Tracker T7 — wire the cert store into the reactor's cert +
        // capability auth gate.  Whenever the cert store is up, callers
        // may present BRC-52 cert-auth headers (X-Brain-Pubkey /
        // X-Brain-Cert-Sig / X-Brain-Cert-Ts) and the reactor gates
        // admin routes on the admin capability.  `BRAIN_REQUIRE_CERT_AUTH`
        // (set to "1"/"true") retires the legacy bearer fallback so a
        // valid cert credential becomes mandatory.
        const require_cert_auth = blk: {
            const v = std.posix.getenv("BRAIN_REQUIRE_CERT_AUTH") orelse break :blk false;
            break :blk std.mem.eql(u8, v, "1") or std.ascii.eqlIgnoreCase(v, "true");
        };
        server.attachCertAuth(if (cert_store) |*cs| cs else null, require_cert_auth);

        // D-O5p — install the operator priv on the dispatcher's
        // identity_certs handler so `issue_child` can verify BRC-42
        // derivations.  Same priv path as cmdDevicePair.  Best-effort
        // load: when the priv is missing the handler falls back to
        // closed-failed mode (`derivation_context_mismatch`), which
        // the operator surfaces during pair via the on-disk cert
        // chain inspection.
        const priv_load_path = try std.fs.path.join(allocator, &.{ data_dir_path, "operator-root-priv.hex" });
        defer allocator.free(priv_load_path);
        if (readOperatorPriv(allocator, priv_load_path)) |priv| {
            cert_handler.?.setOperatorRootPriv(priv);
            // Stand up the device-pair acceptor mirror — its
            // `accept()` path uses the same priv (we do NOT route
            // the production POST through the dispatcher's
            // resource handler because we already have the parsed
            // payload at the HTTP seam).
            device_pair_acceptor = device_pair_http_mod.Acceptor.init(allocator, &cert_store.?, data_dir_path);
            device_pair_acceptor.?.setOperatorRootPriv(priv);
            // Wire the bearer token store so the pair acceptor can
            // mint a bearer for the newly-paired device + return it
            // in the response.  Without this the mobile shell pairs
            // (cert recorded) but has no bearer to call /api/v1/repl.
            if (token_store) |*ts| {
                device_pair_acceptor.?.setTokenStore(ts);
            }
            server.attachDevicePairAcceptor(&device_pair_acceptor.?);
        } else |_| {
            try out.print("  (operator-root-priv.hex not found at {s}; D-O5p HTTP acceptor 503-fallback. Run `brain device init` or write the priv hex to enable.)\n", .{priv_load_path});
        }

        // D-network-ipv6-session-keys — Tier 1 + T3: assign /128s per contact.
        //
        // Requires: --ipv6-prefix <prefix> (e.g. 2404:9400:17e5:1e00::)
        //           --ipv6-iface <iface>    (default: eth0)
        //           operator-root-priv.hex  (for ECDH)
        //           contact_book_store      (to iterate contacts)
        //           CAP_NET_ADMIN / root    (to run `ip -6 addr add`)
        //
        // T1 IID: HMAC-SHA256(ECDH(my_priv, peer_pub).compressed, "brain-v6-t1")
        // T3 IID: SHA256("brain-v6-t3/" || my_pub.compressed)[0..8] (rendezvous)
        //
        // ECDH is symmetric — the peer brain derives the same T1 address from
        // ECDH(peer_priv, my_pub) with no out-of-band signalling beyond the /56 prefix.
        if (ipv6_prefix) |prefix_text| {
            const prefix_opt = session_addr_mod.parsePrefix(prefix_text) catch |e| blk: {
                try out.print("serve {s}: --ipv6-prefix invalid ({s}): {s}\n", .{ domain, prefix_text, @errorName(e) });
                break :blk null;
            };
            if (prefix_opt) |pfx| {
                const op_priv_path = try std.fs.path.join(allocator, &.{ data_dir_path, "operator-root-priv.hex" });
                defer allocator.free(op_priv_path);
                if (readOperatorPriv(allocator, op_priv_path)) |op_priv| {
                    ipv6_addr_table = ipv6_iface_mod.AddrTable.init(allocator, ipv6_iface) catch null;
                    if (ipv6_addr_table) |*tbl| {
                        // T3 rendezvous — own pubkey, no ECDH needed.
                        if (session_addr_mod.deriveIidT3FromPriv(op_priv)) |t3_iid| {
                            const t3_addr = session_addr_mod.buildAddr(pfx, t3_iid);
                            var t3_buf: [39]u8 = undefined;
                            const t3_text = session_addr_mod.fmtAddr(t3_addr, &t3_buf);
                            tbl.add(t3_text, "rendezvous-t3") catch |e| {
                                try out.print("serve {s}: ipv6 T3 add {s}: {s}\n", .{ domain, t3_text, @errorName(e) });
                            };
                            try out.print("  IPv6 T3:      [{s}] rendezvous (stable discovery, share in BRC-52 cert)\n", .{t3_text});
                        } else |_| {}

                        // T1 — one /128 per contact derived via ECDH.
                        if (contact_book_store) |*cbs| {
                            const contacts = cbs.listContacts(allocator) catch &.{};
                            defer allocator.free(contacts);
                            var t1_count: usize = 0;
                            for (contacts) |contact| {
                                const iid = session_addr_mod.deriveIidT1(op_priv, contact.publicKey) catch continue;
                                const addr = session_addr_mod.buildAddr(pfx, iid);
                                var addr_buf: [39]u8 = undefined;
                                const addr_text = session_addr_mod.fmtAddr(addr, &addr_buf);
                                tbl.add(addr_text, contact.certId) catch continue;
                                t1_count += 1;
                            }
                            try out.print("  IPv6 T1:      {d} per-contact /128s on {s} (peers derive same addr via ECDH)\n", .{ t1_count, ipv6_iface });
                        } else {
                            try out.print("serve {s}: ipv6 T1: contact_book_store not ready (--enable-repl required)\n", .{domain});
                        }
                    }
                } else |_| {
                    try out.print("serve {s}: ipv6 session keys: operator-root-priv.hex not found\n", .{domain});
                }
            }
        }

        // C4 PR-H7b — POST /api/v1/attachments/upload is now served by the oddjobz
        // cartridge over the route registry (reads the cartridge-owned
        // attachments + visits + blob stores; bearer + cert-sig verified via the
        // substrate token + cert stores handed through CartridgeDeps). The
        // serve.zig acceptor + SiteServer field + reactor branch are gone; the
        // blob store is now fully cartridge-internal.

        // T8a — /api/v1/info acceptor.  Bearer-gated GET that returns
        // brain pin + shard-proxy + theme so mobile apps can discover
        // brain config dynamically (D2 / no-hardcoded-workarounds).
        // Hard-deps: token_store.  Optional populates: cert_store
        // (brain pin), manifest_holder (shard-proxy + theme).  Absent
        // any of those → the corresponding field is empty / default.
        if (token_store) |*ts| {
            var brain_pin_cert_id_slice: []const u8 = "";
            var brain_pin_pubkey_hex_slice: []const u8 = "";
            if (cert_store) |*cs| {
                if (cs.rootId()) |rid| {
                    info_brain_pin_cert_id = rid;
                    brain_pin_cert_id_slice = &info_brain_pin_cert_id;
                    if (cs.get(&rid)) |root_record| {
                        bkds_mod.hexEncode(&root_record.pubkey, &info_brain_pin_pubkey_hex);
                        brain_pin_pubkey_hex_slice = &info_brain_pin_pubkey_hex;
                    } else |_| {}
                }
            }
            const shard_proxy: []const u8 = if (manifest_holder) |m| m.mesh_shard_proxy_endpoint else "";
            const shard_group: []const u8 = if (manifest_holder) |m| m.mesh_shard_group_id else "";
            const resolved_theme = if (manifest_holder) |m| m.resolvedTheme() else tenant_manifest_mod.ResolvedTheme{
                .primary_hex = "",
                .accent_hex = "",
                .logo_url = "",
                .font_family = "",
                .mode = "",
            };
            // CC2b — Brain→PWA cartridge discovery. Enumerate the
            // disk-installed cartridges (DLO.1c) and surface
            // id/role/experiencePackage on GET /api/v1/info so the PWA
            // shell renders against the manifest (C3 binding). The
            // manifest list + CartridgeInfo slice are process-lifetime
            // (the Acceptor borrows them for the server's run) — same
            // posture as the other borrowed acceptor slices above.
            // Non-fatal: any loader error ⇒ empty list (the endpoint
            // emits a valid `cartridges:[]`).
            const cart_infos: []const info_http_mod.CartridgeInfo = blk: {
                const mans = extensions_mod.enumerateUserInstalled(allocator, data_dir_path) catch {
                    break :blk &[_]info_http_mod.CartridgeInfo{};
                };
                const ci = allocator.alloc(info_http_mod.CartridgeInfo, mans.len) catch {
                    break :blk &[_]info_http_mod.CartridgeInfo{};
                };
                for (mans, 0..) |m, ci_idx| {
                    // SH1-B (DECISION D9) — map the loader's declarative ui
                    // fields onto the wire CartridgeInfo. Strings are borrowed
                    // (mans is process-lifetime, like ci). Best-effort: an OOM
                    // on a cartridge's verbs ⇒ it surfaces none (endpoint stays
                    // valid), same posture as the empty-on-loader-error path.
                    var verbs: []const info_http_mod.UiVerb = &[_]info_http_mod.UiVerb{};
                    if (m.ui_verbs.len > 0) {
                        if (allocator.alloc(info_http_mod.UiVerb, m.ui_verbs.len)) |vbuf| {
                            for (m.ui_verbs, 0..) |lv, vi| vbuf[vi] = .{
                                .modal = lv.modal,
                                .label = lv.label,
                                .intent_type = lv.intent_type,
                                .subtitle = lv.subtitle orelse "",
                                .icon = lv.icon orelse "",
                                .role = lv.role,
                            };
                            verbs = vbuf;
                        } else |_| {}
                    }
                    ci[ci_idx] = .{
                        .id = m.id,
                        .role = m.role orelse "",
                        .experience_package = m.experience_flutter_package orelse "",
                        .surfacing_mode = m.surfacing_mode orelse "",
                        .ui_verbs = verbs,
                    };
                }
                break :blk ci;
            };
            info_acceptor = info_http_mod.Acceptor{
                .allocator = allocator,
                .bearer_tokens = ts,
                .shard_proxy_endpoint = shard_proxy,
                .shard_group_id = shard_group,
                .brain_pin_cert_id = brain_pin_cert_id_slice,
                .brain_pin_pubkey_hex = brain_pin_pubkey_hex_slice,
                .server_version = "brain " ++ cli_lifecycle.VERSION,
                .theme = resolved_theme,
                .cartridges = cart_infos,
            };
            server.attachInfoAcceptor(&info_acceptor.?);
        }

        // D-LC1 — /api/v1/cell/<sha256hex> acceptor. Wired when the
        // entity cell store is up AND token_store is up. The acceptor
        // borrows the CellStore vtable wrapper (entity_cell_store_serve)
        // plus the token store — both outlive the SiteServer in
        // cmdServe's stack frame. Absent either → endpoint stays 404
        // (reactor handler returns {"error":"not_found"}). The vtable
        // wrapper itself is populated by `impl.store()` earlier in this
        // function (single shared CellStore for every read-path caller).
        if (entity_cell_store_serve) |*ecs_vt| {
            if (token_store) |*ts| {
                cell_raw_acceptor = cell_raw_http_mod.Acceptor{
                    .cell_store = ecs_vt,
                    .bearer_tokens = ts,
                };
                server.attachCellRawAcceptor(&cell_raw_acceptor.?);

                // BRAIN-GENERIC-MINT-VERB M1 — populate the cartridge
                // cellType registry from <data_dir>/extensions/*/cartridge.json
                // (each cartridge contributes its cellTypes[] with a
                // structured |8|8|8|8| typeHash computed via buildTypeHash),
                // then construct the generic mint acceptor sharing the
                // same cell_store + token_store + helm_broker the rest
                // of the brain already uses.  Best-effort: registry
                // population failures degrade the endpoint gracefully
                // (mint requests return `unknown_type_hash` 404 for
                // missing entries; the brain still serves everything
                // else).  Hard failures (collision / capacity / OOM)
                // surface — they're structural and must be fixed.
                const boot_summary = cartridge_cell_boot_mod.populateRegistryFromExtensionsDir(
                    &cartridge_boot_arena,
                    allocator,
                    data_dir_path,
                ) catch |e| switch (e) {
                    cartridge_cell_boot_mod.BootError.io_failed,
                    cartridge_cell_boot_mod.BootError.invalid_cartridge_json,
                    cartridge_cell_boot_mod.BootError.unknown_linearity,
                    cartridge_cell_boot_mod.BootError.handler_load_failed,
                    => blk: {
                        std.log.warn(
                            "cells_mint: cellType registry boot encountered soft error {s}; endpoint may serve 404s for un-registered typeHashes",
                            .{@errorName(e)},
                        );
                        break :blk cartridge_cell_boot_mod.BootSummary{
                            .cartridges_scanned = 0,
                            .cartridges_loaded = 0,
                            .cell_types_registered = 0,
                            .cartridges_skipped = 0,
                        };
                    },
                    cartridge_cell_boot_mod.BootError.type_hash_collision,
                    cartridge_cell_boot_mod.BootError.registry_full,
                    cartridge_cell_boot_mod.BootError.out_of_memory,
                    => return e,
                };
                std.log.info(
                    "cells_mint: cellType registry populated — {d} cellTypes from {d}/{d} cartridges ({d} skipped); scan dir: {s}/extensions/",
                    .{
                        boot_summary.cell_types_registered,
                        boot_summary.cartridges_loaded,
                        boot_summary.cartridges_scanned,
                        boot_summary.cartridges_skipped,
                        data_dir_path,
                    },
                );

                cells_mint_acceptor = cells_mint_http_mod.Acceptor{
                    .cell_store = ecs_vt,
                    .bearer_tokens = ts,
                    .broker = &helm_broker_serve,
                };
                // C7-B Option A — wire the cert store so the mint reactor
                // can verify operator signatures (sovereign mint). Null
                // when no cert store is configured; sig-bearing mints then
                // 401 (bearer-only mints are unaffected).
                cells_mint_acceptor.?.certs = if (cert_store) |*cs| cs else null;
                // PR-8b-ix — wire the cell-script handler dispatch hook so
                // the HTTP `POST /api/v1/cells` reactor runs the SAME
                // pipeline the REPL `cells mint` verb runs: lookup the
                // script-handler registry, build per-script Context via the
                // composite ScriptContextBuilder (PR-3d + PR-8b-iv), execute
                // the bytecode, walk the stack for emitted cells + persist
                // them. Without this, MNCA `transition.intent` mints land
                // as plain substrate cells and the `bsv.tx.sign.request` /
                // successor `mnca.anchor` cells the cleavage apparatus
                // depends on never get emitted. The REPL Handler holds
                // the composite builder (wired below in step
                // `setContextBuilder`); the thunk casts its opaque ctx
                // back to *Handler.
                if (cells_mint_handler_serve != null) {
                    cells_mint_acceptor.?.dispatch_input_cell_fn =
                        cells_mint_handler_mod.dispatchInputCellThunk;
                    cells_mint_acceptor.?.dispatch_ctx =
                        @ptrCast(&cells_mint_handler_serve.?);
                }
                // PR-anchor-on-mint — turn on auto-anchor for the
                // generic `POST /api/v1/cells` mint path when the
                // operator has BRAIN_ANCHOR_QUEUE_PATH set (the same
                // opt-in switch that gates the queue writer above).
                // Without this, NP OS substrate cells get persisted
                // but never anchored — Bridget Doran 2026-06-03
                // surfaced the gap: cell_handler.zig (legacy typed-
                // object path) already auto-anchors via
                // initWithBroker(.bsv) line 260; the generic mint
                // path the cleavage apparatus shipped on top of
                // (PR-8b-ix) didn't have the same wiring. This
                // closes it. Auto-anchor + handler-dispatch
                // (PR-8b-ix) are independent dimensions: the same
                // mint can do both.
                if (anchor_queue_path_opt != null) {
                    cells_mint_acceptor.?.auto_anchor_on_mint = true;
                }
                server.attachCellsMintAcceptor(&cells_mint_acceptor.?);

                // M1.7 — register `cells.mint` on the unified WSS RPC channel,
                // backed by the SAME acceptor the HTTP `POST /api/v1/cells`
                // path uses (stable address: just attached above). Both
                // transports drive `cells_mint_core.mintCellCore`, so their
                // mint behaviour can't drift. Admin-gated like the HTTP route
                // (M0: any valid upgrade is admin-equivalent, so this passes;
                // load-bearing once cert→cap-set derivation lands).
                rpc_registry_serve.add(.{
                    .name = "cells.mint",
                    .required_cap = "cap.brain.admin",
                    .state = @ptrCast(&cells_mint_acceptor.?),
                    .handle = &wss_rpc_methods.cellsMint,
                });

                // Betterment-practice pask sweep — GET /api/v1/betterment/sweep.
                // Wired here (inside the ecs_vt + ts block) so the acceptor
                // can borrow both pointers; script path gated separately.
                if (betterment_sweep_script) |script_path| {
                    betterment_sweep_acceptor = betterment_sweep_http_mod.Acceptor{
                        .cell_store = ecs_vt,
                        .bearer_tokens = ts,
                        .sweep_script = script_path,
                    };
                    server.attachBettermentSweepAcceptor(&betterment_sweep_acceptor.?);
                    try out.print(
                        "  Betterment sweep: GET /api/v1/betterment/sweep  (script={s})\n",
                        .{script_path},
                    );
                }
            }
        }

        // T8b — /api/v1/voice-extract acceptor.  Wired only when both
        // --voice-extract-script and --voice-extract-cwd are passed
        // AND cert_store + token_store are up.  Absent any → endpoint
        // stays 404.
        if (voice_extract_script) |script_path| {
            if (voice_extract_cwd) |cwd_path| {
                if (cert_store) |*cs| {
                    if (token_store) |*ts| {
                        voice_extract_shell = voice_extract_shell_mod.Shell{
                            .config = .{
                                .bun_path = voice_extract_bun,
                                .script_path = script_path,
                                .cwd = cwd_path,
                            },
                        };
                        // C4 PR-H6 — read the cartridge-owned blob store via the registry.
                        const blobs_ptr_opt: ?*const attachment_blobs_fs_mod.BlobStore =
                            store_registry_serve.attachment_blobs;
                        voice_extract_acceptor = voice_extract_http_mod.Acceptor{
                            .allocator = allocator,
                            .blobs = blobs_ptr_opt,
                            .certs = cs,
                            .bearer_tokens = ts,
                            .shell = voice_extract_shell.?.asInterface(),
                        };
                        server.attachVoiceExtractAcceptor(&voice_extract_acceptor.?);
                        try out.print(
                            "  Voice extract: POST /api/v1/voice-extract  (bun={s}, script={s})\n",
                            .{ voice_extract_bun, script_path },
                        );
                    } else {
                        try out.print("serve {s}: --voice-extract-script set but token_store absent → endpoint disabled\n", .{domain});
                    }
                } else {
                    try out.print("serve {s}: --voice-extract-script set but cert_store absent → endpoint disabled\n", .{domain});
                }
            } else {
                try out.print("serve {s}: --voice-extract-script set without --voice-extract-cwd → endpoint disabled\n", .{domain});
            }
        }

        // Betterment OCR — /api/v1/image-extract acceptor.  Wired only when
        // both --image-extract-script and --image-extract-cwd are passed AND
        // token_store is up (bearer-only; no cert store).  Absent any → 404.
        if (image_extract_script) |script_path| {
            if (image_extract_cwd) |cwd_path| {
                if (token_store) |*ts| {
                    image_extract_shell = image_extract_shell_mod.Shell{
                        .config = .{
                            .bun_path = image_extract_bun,
                            .script_path = script_path,
                            .cwd = cwd_path,
                        },
                    };
                    image_extract_acceptor = image_extract_http_mod.Acceptor{
                        .allocator = allocator,
                        .bearer_tokens = ts,
                        .shell = image_extract_shell.?.asInterface(),
                    };
                    server.attachImageExtractAcceptor(&image_extract_acceptor.?);
                    try out.print(
                        "  Image extract (OCR): POST /api/v1/image-extract  (bun={s}, script={s})\n",
                        .{ image_extract_bun, script_path },
                    );
                } else {
                    try out.print("serve {s}: --image-extract-script set but token_store absent → endpoint disabled\n", .{domain});
                }
            } else {
                try out.print("serve {s}: --image-extract-script set without --image-extract-cwd → endpoint disabled\n", .{domain});
            }
        }

        // Betterment voice — /api/v1/audio-extract acceptor (bun → whisper.cpp).
        // Wired when both --audio-extract-script and --audio-extract-cwd are set
        // AND token_store is up (bearer-only, no API key). Absent any → 404.
        if (audio_extract_script) |script_path| {
            if (audio_extract_cwd) |cwd_path| {
                if (token_store) |*ts| {
                    audio_extract_shell = audio_extract_shell_mod.Shell{
                        .config = .{
                            .bun_path = audio_extract_bun,
                            .script_path = script_path,
                            .cwd = cwd_path,
                        },
                    };
                    audio_extract_acceptor = audio_extract_http_mod.Acceptor{
                        .allocator = allocator,
                        .bearer_tokens = ts,
                        .shell = audio_extract_shell.?.asInterface(),
                    };
                    server.attachAudioExtractAcceptor(&audio_extract_acceptor.?);
                    try out.print(
                        "  Audio extract (voice): POST /api/v1/audio-extract  (bun={s}, script={s})\n",
                        .{ audio_extract_bun, script_path },
                    );
                } else {
                    try out.print("serve {s}: --audio-extract-script set but token_store absent → endpoint disabled\n", .{domain});
                }
            } else {
                try out.print("serve {s}: --audio-extract-script set without --audio-extract-cwd → endpoint disabled\n", .{domain});
            }
        }

        // C4 PR-G5 — POST /api/v1/conversation/turn/:id/approve MIGRATED to the
        // oddjobz cartridge (route registry + cartridge-owned script). The serve
        // attach + CLI flag are gone.

        // D-OJ-conv-identity-merge-endpoint — POST /api/v1/identity/merge.
        // Wired when token_store is up and --oddjobz-identity-merge-script is passed.
        // Absent either → endpoint stays 404.
        if (oddjobz_identity_merge_script) |script_path| {
            if (token_store != null) {
                server.attachIdentityMergeEndpoint(script_path);
                try out.print(
                    "  Identity merge: POST /api/v1/identity/merge  (script={s})\n",
                    .{script_path},
                );
            } else {
                try out.print("serve {s}: --oddjobz-identity-merge-script set but token_store absent → endpoint disabled\n", .{domain});
            }
        }

        // C4 PR-G6 — POST /api/v1/conversation/turn/:id/re-anchor MIGRATED to the
        // oddjobz cartridge (route registry + cartridge-owned script). The serve
        // attach + CLI flag are gone.

        // C4 PR-G4 — POST /api/v1/conversation/turn/propose MIGRATED to the
        // oddjobz cartridge (route registry + cartridge-owned script). The
        // serve attach + CLI flag are gone.

        // C4 PR-G2 — GET /api/v1/c/{token} customer-link-resolve MIGRATED to the
        // oddjobz cartridge (route registry + cartridge-owned script). The
        // serve-side attach + CLI flag are gone.

        // C4 PR-G3 — the HTTP route GET /api/v1/conversation/turns now lives in
        // the oddjobz cartridge (route registry + cartridge-owned script). The
        // operator flag + this var remain ONLY to feed the REPL's `find turns`
        // verb (rs.conv_turns_query_script) until the REPL-verb seam lands; the
        // SiteServer field + attach + the bearer-gated HTTP wiring are gone.
        if (oddjobz_conv_turns_query_script) |script_path| {
            if (repl_session) |*rs| {
                rs.conv_turns_query_script = script_path;
            }
        }

        // C4 PR-G7 — POST /api/v1/voice-note MIGRATED to the oddjobz cartridge
        // (route registry + cartridge-owned script). The serve attach + CLI flag
        // are gone.

        // T6 — /api/v1/push-register acceptor.  Wired by default when
        // cert_store + token_store are up.  Absent either → endpoint
        // stays 404.  Substrate scope per push_register_http.zig: this
        // endpoint persists the token onto the device cert record; the
        // actual APNs/FCM dispatchers are owned by push_dispatcher /
        // apns_dispatcher / fcm_dispatcher / unifiedpush_dispatcher
        // (already wired elsewhere; this endpoint only stamps the
        // device record as subscribable).
        if (cert_store) |*cs| {
            if (token_store) |*ts| {
                push_register_acceptor = push_register_http_mod.Acceptor{
                    .allocator = allocator,
                    .certs = cs,
                    .bearer_tokens = ts,
                    .now_iso_fn = defaultPushRegisterNowIso,
                };
                server.attachPushRegisterEndpoint(&push_register_acceptor.?);
                try out.print(
                    "  Push register: POST/DELETE /api/v1/push-register\n",
                    .{},
                );
            }
        }

        // conv_send_ctx — the shared bearer-validation context (token store).
        // C4 PR-I1: the conversation-send acceptor moved to the oddjobz cartridge
        // over the route registry; this block now only sets up conv_send_ctx (used
        // by the contacts/messagebox/attention/intent acceptors below) + wires the
        // substrate contacts acceptor.
        if (token_store) |*ts| {
            conv_send_ctx = ConvSendCtx{ .bearer_tokens = ts };

            // D-brain-contacts-api — wire the contacts acceptor now that conv_send_ctx
            // is set. Store was opened earlier; wiring was deferred because bearer-auth
            // validation requires conv_send_ctx (was null at the earlier init point).
            if (contact_book_store) |*cbs| {
                contacts_acceptor = contacts_http_mod.Acceptor{
                    .allocator = allocator,
                    .is_bearer_valid = convSendIsBearerValid,
                    .is_bearer_valid_ctx = &conv_send_ctx.?,
                    .list_contacts = contactsListAll,
                    .list_contacts_ctx = cbs,
                    .get_contact = contactsGetOne,
                    .get_contact_ctx = cbs,
                    .add_contact = contactsAdd,
                    .add_contact_ctx = cbs,
                    .add_edge = contactsAddEdge,
                    .add_edge_ctx = cbs,
                    .revoke_edge = contactsRevokeEdge,
                    .revoke_edge_ctx = cbs,
                };
                server.attachContactsEndpoint(&contacts_acceptor.?);
                try out.print(
                    "  Contacts: GET/POST /api/v1/contacts (+edges)\n",
                    .{},
                );
            }

            // C4 PR-I1 — POST /api/v1/conversation/:id/send (outbound SMS via
            // Twilio) is now served by the oddjobz cartridge over the route
            // registry: it loads the Twilio config + sets up the std.http sender +
            // reads the cartridge-owned customers store there. The serve.zig
            // acceptor + Twilio config load + SiteServer field + reactor branch
            // are gone.
        }

        // D-network-messagebox-first-class — /api/v1/messages/* acceptor.
        // LMDB-backed store persists envelopes across restarts.
        // emit_event fans out a "messagebox.received" event to every
        // /api/v1/events WSS subscriber so the phone receives a push
        // notification without polling.
        if (conv_send_ctx) |*csc| {
            const mb_lmdb_path = try std.fs.path.join(
                allocator, &.{ data_dir_path, "messagebox_lmdb" },
            );
            defer allocator.free(mb_lmdb_path);
            messagebox_lmdb_store = messagebox_lmdb_mod.MessageboxLmdbStore.init(
                allocator, mb_lmdb_path,
            ) catch |e| blk: {
                try out.print("serve {s}: failed to open messagebox LMDB env: {s} (messagebox disabled)\n", .{ domain, @errorName(e) });
                break :blk null;
            };
            if (messagebox_lmdb_store) |*mbs| {
                messagebox_emit_ctx = MessageboxEmitCtx{
                    .bus = &oddjobz_event_bus,
                    .hat_id = domain,
                };
                messagebox_acceptor = messagebox_http_mod.Acceptor{
                    .allocator = allocator,
                    .is_bearer_valid = convSendIsBearerValid,
                    .is_bearer_valid_ctx = csc,
                    .send_message = messagebox_lmdb_mod.MessageboxLmdbStore.send,
                    .send_message_ctx = mbs,
                    .list_messages = messagebox_lmdb_mod.MessageboxLmdbStore.list,
                    .list_messages_ctx = mbs,
                    .ack_message = messagebox_lmdb_mod.MessageboxLmdbStore.ack,
                    .ack_message_ctx = mbs,
                    .free_records = messagebox_lmdb_mod.MessageboxLmdbStore.freeRecords,
                    .free_records_ctx = mbs,
                    .emit_event = messageboxEmitEvent,
                    .emit_event_ctx = &messagebox_emit_ctx.?,
                };
                server.attachMessageboxEndpoint(&messagebox_acceptor.?);
                try out.print("  MessageBox:   POST /api/v1/messages/send, GET /api/v1/messages/list, POST /api/v1/messages/ack (LMDB-backed, events wired)\n", .{});
            }
        }

        // C4 PR-H3 — /api/v1/search/contacts is now served by the oddjobz
        // cartridge over the route registry (reads the cartridge-owned customers
        // + sites stores; bearer-validated via deps.bearer_tokens). The serve.zig
        // acceptor + SiteServer field + reactor branch are gone.

        // C4 PR-I2 — POST /api/v1/twilio/inbound (the inbound SMS webhook) is now
        // served by the oddjobz cartridge over the route registry: it reads the
        // cartridge-owned customers + jobs stores + execs the cartridge-SHIPPED
        // intake script (intake-handler.ts via cartridge_dir; was the operator
        // cfg.routes[].intake_script). The serve.zig acceptor + callbacks +
        // SiteServer field + reactor branch are gone.


        // D-O3 — bundled-extension capability mint pass.  Same boot
        // phase as the cert-store init above; no new top-level step
        // per §9.8.  No-op when the operator's root cert hasn't been
        // minted yet (first run before `brain device pair`); fires
        // automatically on every subsequent boot to merge any newly
        // declared cap names from updated extensions.
        extensions_mod.mintFirstBootCapabilities(
            allocator,
            &cert_store.?,
            null,
            // DLO.1c (Option C): disk-driven registry — enumerate
            // user-installed cartridge manifests under this data dir.
            data_dir_path,
        ) catch |e| switch (e) {
            // Pre-cert-mint state is the expected first-run shape;
            // log + carry on so the daemon can still serve.
            error.no_root_cert => {},
            else => try out.print("serve {s}: D-O3 cap mint pass: {s}\n", .{ domain, @errorName(e) }),
        };

        // D-W1 Phase 1 follow-up — `llm.complete` + stubs.  Boot
        // shape: load the operator's LlmConfig (the same one
        // `brain llm enable / set` writes), wrap it in
        // HttpLlmAdapter, then wrap THAT in the dispatcher resource
        // handler.  All three resources (`llm`, `llm.transcribe_
        // audio`, `llm.embed`) register on the same dispatcher.
        // Same boot phase as the cert + extensions mint pass; no
        // new top-level boot step (§9.8 acceptance gate).
        llm_cfg = llm_adapter.loadConfig(allocator, data_dir_path) catch |e| blk: {
            try out.print("serve {s}: --enable-repl: failed to load llm-config.json: {s} (using defaults)\n", .{ domain, @errorName(e) });
            break :blk llm_adapter.LlmConfig{};
        };
        llm_http_inst = llm_http_adapter_mod.HttpLlmAdapter.init(allocator, llm_cfg.?);
        llm_complete = llm_complete_handler_mod.Handler.init(allocator, &llm_http_inst.?, data_dir_path, realClock) catch |e| {
            try out.print("serve {s}: --enable-repl: failed to init llm.complete handler: {s}\n", .{ domain, @errorName(e) });
            return .file_io;
        };
        try dispatcher_inst.?.register(llm_complete.?.resourceHandler());

        // WP-2 — boot-seed the LLM rate-limit + daily-token budget from the
        // operator profile so the operator's `do manage site widget rate_limit=… /
        // daily_tokens=…` numbers bind (the public widget's anonymous-widget scope
        // shares this handler's limits). Applied at (re)start; unset/zero keeps the
        // handler default.
        if (operator_profile_holder) |*p| {
            if (p.widget_rate_limit_per_hour > 0) llm_complete.?.setRequestsPerHour(p.widget_rate_limit_per_hour);
            if (p.widget_tokens_per_day > 0) llm_complete.?.setTokensPerDay(p.widget_tokens_per_day);
        }

        llm_transcribe = llm_transcribe_audio_handler_mod.Handler.init();
        try dispatcher_inst.?.register(llm_transcribe.?.resourceHandler());

        llm_embed = llm_embed_handler_mod.Handler.init();
        try dispatcher_inst.?.register(llm_embed.?.resourceHandler());

        // C4 CW-1 — the D-O6a chat backend is retired; POST /api/v1/chat is now
        // a cartridge route_registry route (oddjobz registerInto → chatRouteHandler).

        // D-W1 Phase 4 — SignedBundle mesh receive seam.  Default
        // disabled; opt-in per deployment via
        // `--signed-bundle-endpoint <path>`.  The acceptor needs the
        // dispatcher (already up), the cert store (already up), and
        // the operator's root cert id as the addressed-bundle
        // recipient.  Until the operator-root cert is minted (i.e.
        // before the first `brain device init`), we still construct
        // the acceptor but leave its expected_recipient unset; it
        // will reject every bundle with a 503-style error until the
        // root cert appears.
        if (signed_bundle_endpoint) |ep| {
            bundle_acceptor = signed_bundle_transport_mod.BundleAcceptor.init(
                allocator,
                &dispatcher_inst.?,
                &cert_store.?,
                realClock,
            );
            if (cert_store.?.rootId()) |rid| {
                bundle_acceptor.?.setExpectedRecipient(rid);
            }
            server.attachBundleAcceptor(&bundle_acceptor.?, ep);
            try out.print("  Bundle accept: POST {s}        (D-W1 Phase 4 mesh transport — opt-in)\n", .{ep});
        }

        // D-W2 Phase 2 — extension-bundle frame receive seam.  Default
        // disabled; opt-in per deployment via
        // `--bundle-frame-endpoint <path>`.  Requires the tenant
        // manifest to carry a [trusted_signers] block (otherwise
        // there's no signer set to verify frames against — every
        // frame would reject as unknown_signer).
        if (bundle_frame_endpoint) |ep| {
            const mh: ?*const tenant_manifest_mod.TenantManifest = if (manifest_holder) |*m| m else null;
            if (mh == null or mh.?.trusted_signers.len == 0) {
                try out.print(
                    "  Bundle frame: SKIPPED — --bundle-frame-endpoint requires --tenant-manifest with [trusted_signers] entries.\n",
                    .{},
                );
            } else {
                // v0.1: SPV client is a deny-all stub.  An operator
                // wires a real BSV-node-backed lookup before trusting
                // production frames.  See `extension_subscriber.SpvClient`
                // for the seam shape and the operator runbook for the
                // production-deployment checklist.
                const spv_stub = extension_subscriber_mod.SpvClient{
                    .state = null,
                    .lookup_fn = stubSpvLookup,
                };
                frame_acceptor = extension_subscribe_mod.FrameAcceptor.init(
                    allocator,
                    mh.?.trusted_signers,
                    spv_stub,
                    &dispatcher_inst.?,
                    &disp_audit.?,
                    data_dir_path,
                );
                server.attachFrameAcceptor(&frame_acceptor.?, ep);
                try out.print(
                    "  Bundle frame: POST {s}     (D-W2 Phase 2 — opt-in; SPV stub)\n",
                    .{ep},
                );
                try out.print(
                    "                trusted signers: {d}\n",
                    .{mh.?.trusted_signers.len},
                );
            }
        }

        // D-O5m.followup-9 Phase B — push notification dispatchers.
        // Best-effort init: when push-config.json is missing OR the
        // file is `{}`, push is silently skipped (the broker's
        // PushHook stays null).  When the file exists with one or
        // both transports configured, we stand up the relevant
        // dispatcher(s), wire the bridge onto the broker, and log a
        // single boot line listing what's enabled.
        push_cfg = config.loadPushConfig(allocator, data_dir_path) catch |e| blk: {
            try out.print("serve {s}: --enable-repl: failed to load push-config.json: {s} (push disabled)\n", .{ domain, @errorName(e) });
            break :blk config.PushConfig{};
        };
        if (push_cfg) |*pc| {
            if (pc.isEmpty()) {
                try out.print("  Push:         (not configured — drop push-config.json into {s} to enable)\n", .{data_dir_path});
            } else {
                if (pc.apns) |a| {
                    const env: apns_dispatcher_mod.ApnsEnvironment =
                        if (std.mem.eql(u8, a.environment, "development"))
                            .development
                        else
                            .production;
                    apns_transport = .{};
                    apns_dispatcher = apns_dispatcher_mod.ApnsDispatcher.init(
                        allocator,
                        .{
                            .bundle_id = a.bundle_id,
                            .key_id = a.key_id,
                            .team_id = a.team_id,
                            .p8_key_path = a.p8_key_path,
                            .environment = env,
                        },
                        &cert_store.?,
                        &disp_audit.?,
                        apns_transport.?.transport(),
                    ) catch |e| blk2: {
                        try out.print("  Push (APNs):  init failed: {s} (APNs disabled)\n", .{@errorName(e)});
                        break :blk2 null;
                    };
                }
                if (pc.fcm) |f| {
                    fcm_transport = .{};
                    fcm_dispatcher = fcm_dispatcher_mod.FcmDispatcher.init(
                        allocator,
                        .{
                            .project_id = f.project_id,
                            .service_account_json_path = f.service_account_json_path,
                        },
                        &cert_store.?,
                        &disp_audit.?,
                        fcm_transport.?.transport(),
                    ) catch |e| blk2: {
                        try out.print("  Push (FCM):   init failed: {s} (FCM disabled)\n", .{@errorName(e)});
                        break :blk2 null;
                    };
                }
                // Sovereign-push D.3 — UnifiedPush always initialised
                // alongside the configured backends.  The dispatcher
                // has no signing material; per-cert it just POSTs the
                // wake envelope to the cert's stored UP endpoint.
                up_transport = .{};
                up_dispatcher = unifiedpush_dispatcher_mod.UnifiedPushDispatcher.init(
                    allocator,
                    &cert_store.?,
                    &disp_audit.?,
                    up_transport.?.transport(),
                );
                const apns_ptr: ?*apns_dispatcher_mod.ApnsDispatcher = if (apns_dispatcher) |*a| a else null;
                const fcm_ptr: ?*fcm_dispatcher_mod.FcmDispatcher = if (fcm_dispatcher) |*f| f else null;
                const up_ptr: ?*unifiedpush_dispatcher_mod.UnifiedPushDispatcher = if (up_dispatcher) |*u| u else null;
                if (apns_ptr != null or fcm_ptr != null or up_ptr != null) {
                    push_dispatcher = push_dispatcher_mod.PushDispatcher.init(
                        allocator,
                        apns_ptr,
                        fcm_ptr,
                        up_ptr,
                        &cert_store.?,
                        &disp_audit.?,
                    );
                    push_bridge = .{
                        .dispatcher = &push_dispatcher.?,
                        .cert_store = &cert_store.?,
                    };
                    helm_broker_serve.setPushHook(.{
                        .state = &push_bridge.?,
                        .resolve_fn = pushBridgeResolve,
                        .free_fn = pushBridgeFree,
                        .send_fn = pushBridgeSend,
                    });
                    try out.print(
                        "  Push:         apns={s} fcm={s} unifiedpush={s} (D-O5m.followup-9 Phase B + Sovereign-push D.3)\n",
                        .{
                            if (apns_ptr != null) "on" else "off",
                            if (fcm_ptr != null) "on" else "off",
                            if (up_ptr != null) "on" else "off",
                        },
                    );
                } else {
                    try out.print("  Push:         (config present but no transports came up)\n", .{});
                }
            }
        }

        unix_server = unix_socket_transport.Server.bind(
            allocator,
            data_dir_path,
            unix_socket_transport.currentUid(),
            &dispatcher_inst.?,
        ) catch |e| {
            try out.print("serve {s}: --enable-repl: Unix socket bind failed: {s}\n", .{ domain, @errorName(e) });
            return .file_io;
        };
        unix_thread = try std.Thread.spawn(.{}, runUnixServer, .{unix_server.?});

        try out.print("  HTTP REPL:    POST /api/v1/repl    ({d} bearer token(s) issued)\n", .{token_store.?.count()});
        try out.print("  WSS wallet:   GET  /api/v1/wallet   (Upgrade: websocket)\n", .{});
        try out.print("  Unix socket:  {s}                   (D-W1 Phase 1 dispatcher transport)\n", .{unix_server.?.socket_path});
        try out.print("  Identity certs: {d} cert(s) in chain (D-W1 P1.2; D-O5p pairing target)\n", .{cert_store.?.count()});
        // C4 CW-1 — the public chat endpoint is now a cartridge route
        // (POST /api/v1/chat via oddjobz registerInto), logged at boot by the
        // cartridge seam; the brain no longer counts D-O6a chat routes here.
    }

    // C4 PR-H2b-2 — the cartridge-extension dispatch (cartridge_seam.
    // dispatchRegistrations) MOVED UP into the --enable-repl block, before the
    // store consumers, so the cartridge populates store_registry_serve before
    // they read it (boot cartridges early — the pure §6b boot-then-consume
    // order). See the moved block near the intent_router setup above.

    try out.print("brain serve — {s}\n", .{cfg.domain});
    try out.print("  listening:    [::]:{d} (dual-stack IPv4+IPv6)\n", .{cfg.listen_port});
    try out.print("  content_root: {s}\n", .{cfg.content_root});
    try out.print("  routes:       {d}\n", .{cfg.routes.len});
    try out.print("  access log:   {s}\n", .{server.access_log_path});
    try out.print("\nCtrl-C to stop.\n", .{});
    flushOutput(out);

    server.serve(null) catch |e| {
        try out.print("serve: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    if (unix_server) |s| {
        try out.print("Unix socket closed: {s}\n", .{s.socket_path});
    }
    return .ok;
}

/// Worker entry point for the Unix socket accept thread spawned by
/// cmdServe.  Returns when the server's `stop()` flag flips.
fn runUnixServer(server: *unix_socket_transport.Server) void {
    server.serve();
}

// ─── D-O5m.followup-9 Phase B — push hook bridge ────────────────────
//
// The helm_event_broker's `PushHook` is transport-agnostic; the cli
// owns this bridge struct that ties the broker into the push
// dispatcher.  The resolver enumerates every cert with a registered
// push token (the v0.1 minimal-viable cert set — refinements like
// "only certs subscribing to <topic>" land in a follow-up when the
// broker carries a topic field).

const PushBrokerBridge = struct {
    dispatcher: *push_dispatcher_mod.PushDispatcher,
    cert_store: *identity_certs_mod.CertStore,
};

/// Resolve the cert ids that should receive a push for this event.
/// v0.1: every cert with `push_platform != .none`.  Returns an alloc-
/// owned slice of borrowed cert-id strings (the cert-id buffers live
/// inside the cert_store records — valid for the duration of the
/// publish call, which the hook contract pins).
fn pushBridgeResolve(
    state: ?*anyopaque,
    allocator: std.mem.Allocator,
    event: helm_event_broker_mod.Event,
) []const []const u8 {
    _ = event;
    const self: *PushBrokerBridge = @ptrCast(@alignCast(state.?));
    const records = self.cert_store.list(allocator) catch return &.{};
    defer allocator.free(records);

    // Two-pass count → alloc → fill so the slice we hand back is
    // exactly the right size (no over-allocation that the free path
    // has to track).
    var count: usize = 0;
    for (records) |rec| if (rec.push_platform != .none) {
        count += 1;
    };
    if (count == 0) return &.{};
    const out = allocator.alloc([]const u8, count) catch return &.{};
    var idx: usize = 0;
    for (records) |rec| if (rec.push_platform != .none) {
        out[idx] = rec.id[0..];
        idx += 1;
    };
    return out;
}

fn pushBridgeFree(
    state: ?*anyopaque,
    allocator: std.mem.Allocator,
    cert_ids: []const []const u8,
) void {
    _ = state;
    if (cert_ids.len > 0) allocator.free(cert_ids);
}

fn pushBridgeSend(
    state: ?*anyopaque,
    cert_ids: []const []const u8,
    payload_json: []const u8,
) void {
    const self: *PushBrokerBridge = @ptrCast(@alignCast(state.?));
    // Sovereign-push D.1 — wake-only.  The broker's envelope is
    // already opaque (event_id + ts + kind); we forward it verbatim
    // to APNs/FCM with NO operator content.
    self.dispatcher.sendToCerts(cert_ids, .{
        .payload_json = payload_json,
    });
}

fn countDynamicRoutes(cfg: *const site_config_mod.SiteConfig) u32 {
    var n: u32 = 0;
    for (cfg.routes) |r| if (r.kind == .dynamic) {
        n += 1;
    };
    return n;
}

/// WSITE2.5 — bundle the storage stack + audit log + broker + runner
/// the dynamic-handler dispatch needs.  Mirrors `cmdStart`'s plumbing
/// so handlers see the same broker policy gates wallet/headers modules
/// see (handlers are denied wallet/state/persist ops; allowed hashes).
const DynamicRuntime = struct {
    audit: audit_log_mod.AuditLog,
    audit_path: []u8,
    slot_fs: slot_store_fs_mod.FsSlotStore,
    state_fs: state_store_fs_mod.FsStateStore,
    header_fs: header_store_fs_mod.FsHeaderStore,
    broker: broker_mod.Broker,
    runner: runner_mod.Runner,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *DynamicRuntime) void {
        self.runner.deinit();
        self.audit.close();
        self.slot_fs.deinit();
        self.state_fs.deinit();
        self.header_fs.deinit();
        self.allocator.free(self.audit_path);
    }
};

fn setUpDynamicRuntime(allocator: std.mem.Allocator, data_dir: []const u8) !DynamicRuntime {
    var slot_fs = try slot_store_fs_mod.FsSlotStore.init(allocator, data_dir);
    errdefer slot_fs.deinit();
    var state_fs = try state_store_fs_mod.FsStateStore.init(allocator, data_dir);
    errdefer state_fs.deinit();
    var header_fs = try header_store_fs_mod.FsHeaderStore.init(allocator, data_dir);
    errdefer header_fs.deinit();

    var audit = audit_log_mod.AuditLog.init();
    errdefer audit.close();
    const audit_path = try std.fs.path.join(allocator, &.{ data_dir, "audit.log" });
    errdefer allocator.free(audit_path);
    try audit.open(audit_path);

    // The broker holds the stores by value once bound; we keep our
    // copies alive in the DynamicRuntime owner so deinit can tear them
    // down.  The runner takes a pointer to the broker, which lives
    // inside this struct — so `runner` borrows from `broker`, and both
    // get torn down together.
    var rt: DynamicRuntime = .{
        .audit = audit,
        .audit_path = audit_path,
        .slot_fs = slot_fs,
        .state_fs = state_fs,
        .header_fs = header_fs,
        .broker = undefined,
        .runner = undefined,
        .allocator = allocator,
    };
    rt.broker = broker_mod.Broker.init(
        allocator,
        rt.slot_fs.store(),
        rt.state_fs.store(),
        rt.header_fs.store(),
        &rt.audit,
    );
    rt.runner = runner_mod.Runner.init(allocator, &rt.broker);
    return rt;
}

/// Default BRAIN config location — `$HOME/.semantos/config.json`. Used by
/// `cmdServe --enable-repl` when no explicit `--repl-config-path` is
/// provided. Mirrors `main.resolveConfigPath`'s default-discovery, but
/// without the `--config-path` arg parsing (cmdServe does its own).
fn resolveDefaultConfigPath(allocator: std.mem.Allocator) ![]u8 {
    const home = std.process.getEnvVarOwned(allocator, "HOME") catch
        return allocator.dupe(u8, ".semantos/config.json");
    defer allocator.free(home);
    return std.fs.path.join(allocator, &.{ home, ".semantos", "config.json" });
}

// ─────────────────────────────────────────────────────────────────────
// Brain 4 / D-W1 Phase 1 — `brain bearer issue|list|revoke`
//
// Phase 1 reshape: each subcommand is a Unix-socket client of the
// running daemon, falling back to embedded-mode (in-process
// dispatcher + locally-opened TokenStore) when no socket is present.
// The print banner makes the chosen path visible to the operator —
// per issue #1's proposed fix — so "I issued via the CLI but the
// helm doesn't see it" is structurally impossible to misdiagnose.
// ─────────────────────────────────────────────────────────────────────


/// D-W2 Phase 2 — deny-all SPV-client stub.  v0.1 default for the
/// `--bundle-frame-endpoint` seam: every lookup returns null, which
/// the verifier translates into `spv_verify_failed`.  Production
/// deployments override this with a real BSV-node-backed adapter
/// (see the operator runbook for the wiring checklist).  The stub
/// keeps the daemon bootable + the apply-path code paths exercised
/// by the e2e conformance test, which uses its own SPV stub seeded
/// with the synthetic publish-tx fixture.
fn stubSpvLookup(
    state: ?*anyopaque,
    txid: [extension_subscriber_mod.TXID_LEN]u8,
) ?extension_subscriber_mod.SpvLookup {
    _ = state;
    _ = txid;
    return null;
}


```
