---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cli/operator.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.288074+00:00
---

# runtime/semantos-brain/src/cli/operator.zig

```zig
// Operator-facing verbs (LLM config, tenant provisioning, resign-pending,
// operator export/exit, orphan-streams, domain allowlist, caddy-ask,
// SNI map, wrapped DEK, site preview/publish) extracted from src/cli.zig
// as Move 9 of the cli-modularize refactor.  Pure code motion: no
// behaviour change.

const std = @import("std");
const cli_common = @import("common.zig");
const cli_device = @import("device.zig");
const llm_adapter = @import("llm_adapter");
const tenant_manifest_mod = @import("tenant_manifest");
const provision_tenant_mod = @import("provision_tenant");
const sites_store_fs_mod = @import("sites_store_fs");
const customers_store_fs_mod = @import("customers_store_fs");
const jobs_store_fs_mod = @import("jobs_store_fs");
const attachments_store_fs_mod = @import("attachments_store_fs");
const hat_bkds_mod = @import("hat_bkds");
// C4 — resign-pending backfills oddjobz cells; sign under the oddjobz scope so
// re-signed cells match the cartridge mint (oddjobz_ratify_handler.signOne).
const oddjobz_scope_mod = @import("oddjobz_scope");
const lmdb_mod = @import("lmdb");
const lmdb_config_mod = @import("lmdb_config");
const lmdb_cell_store_mod = @import("lmdb_cell_store");
const pask_snapshot_store_lmdb_mod = @import("pask_snapshot_store_lmdb");
const operator_export_mod = @import("operator_export");
const operator_exit_mod = @import("operator_exit");
const nats_client_mod = @import("nats_client");
const nats_event_producer_mod = @import("nats_event_producer");
const nats_orphan_detector_mod = @import("nats_orphan_detector");
const domain_allowlist_mod = @import("domain_allowlist");
const caddy_ask_server_mod = @import("caddy_ask_server");
const sni_domain_map_mod = @import("sni_domain_map");
const wrapped_dek_store_mod = @import("wrapped_dek_store");
const operator_profile_mod = @import("operator_profile");
const operator_profile_loader_mod = @import("operator_profile_loader");
const operator_site_renderer_mod = @import("operator_site_renderer");
const bkds_mod = @import("bkds");

const Output = cli_common.Output;
const ExitCode = cli_common.ExitCode;
const resolveDataDir = cli_common.resolveDataDir;
const readOperatorPriv = cli_device.readOperatorPriv;
const realClock = cli_common.realClock;

pub fn cmdLlm(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 1) {
        try out.print("usage: brain llm <status|enable|disable|set> [args...]\n", .{});
        return .bad_args;
    }
    const sub = args[0];
    if (std.mem.eql(u8, sub, "status")) return try cmdLlmStatus(allocator, out);
    if (std.mem.eql(u8, sub, "enable")) return try cmdLlmEnable(allocator, out, true);
    if (std.mem.eql(u8, sub, "disable")) return try cmdLlmEnable(allocator, out, false);
    if (std.mem.eql(u8, sub, "set")) {
        if (args.len < 3) {
            try out.print("usage: brain llm set <backend|endpoint|model|api_key_env> <value>\n", .{});
            return .bad_args;
        }
        return try cmdLlmSet(allocator, out, args[1], args[2]);
    }
    try out.print("unknown llm subcommand: {s}\n", .{sub});
    return .bad_args;
}

fn cmdLlmStatus(allocator: std.mem.Allocator, out: *const Output) !ExitCode {
    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);
    var cfg = llm_adapter.loadConfig(allocator, data_dir) catch |e| {
        try out.print("llm status: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer allocator.free(cfg.endpoint);
    defer allocator.free(cfg.model);
    defer allocator.free(cfg.api_key_env);

    try out.print("LLM adapter (Brain 5)\n", .{});
    try out.print("  enabled:     {s}\n", .{if (cfg.enabled) "yes" else "no (default)"});
    try out.print("  backend:     {s}\n", .{cfg.backend.toString()});
    try out.print("  endpoint:    {s}\n", .{if (cfg.endpoint.len == 0) "(unset)" else cfg.endpoint});
    try out.print("  model:       {s}\n", .{if (cfg.model.len == 0) "(unset)" else cfg.model});
    try out.print("  api_key_env: {s}\n", .{if (cfg.api_key_env.len == 0) "(unset)" else cfg.api_key_env});
    if (cfg.enabled and cfg.backend == .none) {
        try out.print("\n  warning: enabled but backend is `none` — set backend with `brain llm set backend <local|openai|anthropic>`\n", .{});
    }
    return .ok;
}

fn cmdLlmEnable(allocator: std.mem.Allocator, out: *const Output, enable: bool) !ExitCode {
    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);
    var cfg = llm_adapter.loadConfig(allocator, data_dir) catch |e| {
        try out.print("llm: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer allocator.free(cfg.endpoint);
    defer allocator.free(cfg.model);
    defer allocator.free(cfg.api_key_env);
    cfg.enabled = enable;
    llm_adapter.saveConfig(allocator, data_dir, cfg) catch |e| {
        try out.print("llm: failed to save config: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    try out.print("LLM adapter {s}.\n", .{if (enable) "enabled" else "disabled"});
    return .ok;
}

fn cmdLlmSet(allocator: std.mem.Allocator, out: *const Output, key: []const u8, value: []const u8) !ExitCode {
    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);
    var cfg = llm_adapter.loadConfig(allocator, data_dir) catch |e| {
        try out.print("llm set: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    // Build a fresh config swapping in the new field; free the old field
    // string we're replacing.
    if (std.mem.eql(u8, key, "backend")) {
        const b = llm_adapter.Backend.fromString(value) orelse {
            try out.print("llm set: unknown backend `{s}` (choose: none|local|openai|anthropic)\n", .{value});
            allocator.free(cfg.endpoint);
            allocator.free(cfg.model);
            allocator.free(cfg.api_key_env);
            return .bad_args;
        };
        cfg.backend = b;
    } else if (std.mem.eql(u8, key, "endpoint")) {
        allocator.free(cfg.endpoint);
        cfg.endpoint = try allocator.dupe(u8, value);
    } else if (std.mem.eql(u8, key, "model")) {
        allocator.free(cfg.model);
        cfg.model = try allocator.dupe(u8, value);
    } else if (std.mem.eql(u8, key, "api_key_env")) {
        allocator.free(cfg.api_key_env);
        cfg.api_key_env = try allocator.dupe(u8, value);
    } else {
        try out.print("llm set: unknown key `{s}` (choose: backend|endpoint|model|api_key_env)\n", .{key});
        allocator.free(cfg.endpoint);
        allocator.free(cfg.model);
        allocator.free(cfg.api_key_env);
        return .bad_args;
    }
    llm_adapter.saveConfig(allocator, data_dir, cfg) catch |e| {
        try out.print("llm set: failed to save config: {s}\n", .{@errorName(e)});
        allocator.free(cfg.endpoint);
        allocator.free(cfg.model);
        allocator.free(cfg.api_key_env);
        return .file_io;
    };
    try out.print("set {s} = {s}\n", .{ key, value });
    allocator.free(cfg.endpoint);
    allocator.free(cfg.model);
    allocator.free(cfg.api_key_env);
    return .ok;
}

// ─────────────────────────────────────────────────────────────────────
// D-O10 — `brain provision-tenant <manifest.toml>`
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §11 (operator flow);
// docs/canon/deliverables.yml D-O10; provision_tenant.zig (the core
// flow) + docs/operator-runbooks/provision-tenant.md.
//
// Thin shim — argv parsing + delegation to provision_tenant.provision().
// Keeps cli.zig focused on argv handling; the heavy lifting lives in
// provision_tenant.zig where it's directly unit-testable.
//
// (D-O10 ships as `brain provision-tenant`; a future `semantos node
// provision-tenant` wrapper is documented as TODO in the runbook.)
// ─────────────────────────────────────────────────────────────────────

pub fn cmdProvisionTenant(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    if (args.len < 1 or std.mem.startsWith(u8, args[0], "--")) {
        try out.print("usage: brain provision-tenant <manifest.toml> [--operator-priv <path>] [--platform-plexus-identity-tx <hex>] [--dry-run]\n", .{});
        return .bad_args;
    }
    const manifest_path: []const u8 = args[0];

    var operator_priv_path: []const u8 = "";
    var platform_tx_hex: []const u8 = "";
    var dry_run = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--operator-priv") and i + 1 < args.len) {
            operator_priv_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--platform-plexus-identity-tx") and i + 1 < args.len) {
            platform_tx_hex = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--dry-run")) {
            dry_run = true;
        } else {
            try out.print("provision-tenant: unknown arg `{s}`\n", .{args[i]});
            return .bad_args;
        }
    }

    const opts = provision_tenant_mod.ProvisionOptions{
        .manifest_path = manifest_path,
        .operator_priv_path = operator_priv_path,
        .platform_plexus_identity_tx_hex = platform_tx_hex,
        .dry_run = dry_run,
        .clock = realClock,
    };

    // Adapter: provision_tenant.Writer mirrors cli.Output; we share
    // the underlying buffer + allocator so the operator sees the
    // [provision] log lines on the same stream as the command's own
    // banner.
    const pt_writer = provision_tenant_mod.Writer{
        .buffer = out.buffer,
        .allocator = out.allocator,
    };

    var result = provision_tenant_mod.provision(allocator, &pt_writer, opts) catch |e| {
        // Step lines are emitted by provision_tenant before the error
        // bubbles up; here we just translate the typed error into an
        // exit code.
        return switch (e) {
            error.manifest_validation_failed,
            error.manifest_parse_failed,
            error.owner_cert_unreadable,
            error.recovery_enrolment_invalid,
            error.operator_priv_unreadable,
            error.operator_edited_platform_immutable,
            error.immutable_signer_changed,
            => ExitCode.config_error,
            error.port_allocation_failed,
            error.data_dir_layout_failed,
            error.systemd_write_failed,
            error.caddy_write_failed,
            error.service_start_failed,
            error.first_boot_failed,
            error.cap_mint_failed,
            error.extension_bundle_missing,
            error.pairing_payload_failed,
            error.io_failed,
            => ExitCode.file_io,
            error.out_of_memory => ExitCode.file_io,
        };
    };
    defer result.deinit(allocator);
    return .ok;
}

// ─────────────────────────────────────────────────────────────────────
// D-DOG.1.0c Phase 4 row B.4 — `brain resign-pending`
// ─────────────────────────────────────────────────────────────────────
//
// Backfills BKDS signatures over Phase-2-era unsigned rows.  Walks
// the four oddjobz view stores (sites/customers/jobs/attachments)
// rooted at `--data-dir <path>` (default: `$HOME/.semantos`), opens
// each store's log for replay, and for every row with `signedBy:
// null` calls hat_bkds.signCell(&cellId) → appends a `"signed"`
// event line via the store's appendSigned API.  Deterministic +
// idempotent: re-running over an already-signed corpus is a no-op
// (rows with signedBy != null are skipped).
//
// CRITICAL: stop `brain serve` before running.  The in-memory view-
// store indices in the running daemon don't share memory with the
// CLI's freshly-opened store instances, so a CLI-side append while
// the daemon is also writing leaves the daemon's indices stale until
// it restarts.  The verb refuses to run if it detects a `brain.sock`
// listener (TODO: implement that liveness check; v0 just documents
// the expectation).

pub fn cmdResignPending(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    // Parse args.
    var data_dir: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--data-dir") and i + 1 < args.len) {
            data_dir = args[i + 1];
            i += 1;
        } else {
            try out.print("resign-pending: unknown arg `{s}`\n", .{args[i]});
            return .bad_args;
        }
    }
    // Default data_dir: $HOME/.semantos.
    const resolved_data_dir: []const u8 = blk: {
        if (data_dir) |d| break :blk try allocator.dupe(u8, d);
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch
            return .bad_args;
        defer allocator.free(home);
        break :blk try std.fs.path.join(allocator, &.{ home, ".semantos" });
    };
    defer allocator.free(resolved_data_dir);

    // Bring up the hat-key BKDS signer.  Same seed shape as cmdServe
    // so signatures over the same cellId are byte-identical across
    // (cmdServe-mint) + (cmdResignPending-backfill) paths.
    const hat_seed = try std.fmt.allocPrint(
        allocator,
        "oddjobz.hat-key-root/v0:{s}",
        .{resolved_data_dir},
    );
    defer allocator.free(hat_seed);
    var hat_signer = hat_bkds_mod.HatBkds.initFromSeed(hat_seed) catch |e| {
        try out.print("resign-pending: failed to bring up hat-key BKDS signer: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer hat_signer.deinit();

    // Open the shared LMDB env for the entity cell stores.
    const resign_entity_lmdb_path = try std.fs.path.join(
        allocator,
        &.{ resolved_data_dir, "entity_cells_lmdb" },
    );
    defer allocator.free(resign_entity_lmdb_path);
    std.fs.makeDirAbsolute(resign_entity_lmdb_path) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => {
            try out.print("resign-pending: entity-cells lmdb dir create failed: {s}\n", .{@errorName(e)});
            return .file_io;
        },
    };
    var resign_entity_env = lmdb_mod.Env.open(resign_entity_lmdb_path, .{
        .open_flags = lmdb_config_mod.LmdbConfig.prod_flags,
        .map_size = lmdb_config_mod.LmdbConfig.default.map_size,
        .max_dbs = lmdb_config_mod.LmdbConfig.default.max_dbs,
        .mode = lmdb_config_mod.LmdbConfig.default.mode,
    }) catch |e| {
        try out.print("resign-pending: failed to open entity-cells LMDB env: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer resign_entity_env.close();
    var resign_entity_cs_impl = lmdb_cell_store_mod.LmdbCellStore.init(&resign_entity_env, allocator) catch |e| {
        try out.print("resign-pending: failed to init entity cell store: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    const resign_entity_cs = resign_entity_cs_impl.store();

    // Open the four view stores rooted at data_dir.  Failures here
    // are fatal — there's no useful work without the stores.
    // W6.2: sites_store now reads from the LMDB entity cell store.
    var sites = sites_store_fs_mod.SitesStore.init(allocator, &resign_entity_cs, realClock) catch |e| {
        try out.print("resign-pending: failed to open sites store: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer sites.deinit();
    var customers = customers_store_fs_mod.CustomersStore.init(allocator, &resign_entity_cs, realClock) catch |e| {
        try out.print("resign-pending: failed to open customers store: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer customers.deinit();
    // W0.1: jobs_store now reads from the LMDB entity cell store.
    var jobs = jobs_store_fs_mod.JobsStore.init(allocator, &resign_entity_cs, realClock) catch |e| {
        try out.print("resign-pending: failed to open jobs store: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer jobs.deinit();
    var attachments = attachments_store_fs_mod.AttachmentsStore.init(allocator, &resign_entity_cs, realClock) catch |e| {
        try out.print("resign-pending: failed to open attachments store: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer attachments.deinit();

    // Walk each store.  For every row with signedBy == null, sign
    // its cellId and append a `"signed"` event.
    const sites_signed = try resignSites(allocator, &sites, &hat_signer);
    const customers_signed = try resignCustomers(allocator, &customers, &hat_signer);
    const jobs_signed = try resignJobs(allocator, &jobs, &hat_signer);
    const attachments_signed = try resignAttachments(allocator, &attachments, &hat_signer);

    try out.print(
        "resign-pending: signed {d} sites, {d} customers, {d} jobs, {d} attachments\n",
        .{ sites_signed, customers_signed, jobs_signed, attachments_signed },
    );
    return .ok;
}

/// Walk the SitesStore and append a "signed" event for every row
/// with signedBy == null.  Returns the count of rows signed.
/// Public so tests/brain_resign_pending_conformance.zig can drive the
/// helper without spawning a child `brain resign-pending` process.
pub fn resignSites(
    allocator: std.mem.Allocator,
    sites: *sites_store_fs_mod.SitesStore,
    hat: *hat_bkds_mod.HatBkds,
) !usize {
    const all = try sites.listAll(allocator);
    defer allocator.free(all);
    var signed_count: usize = 0;
    for (all) |row| {
        if (row.signedBy != null) continue;
        const result = hat.signCellScoped(&row.cellId, &row.cellId, oddjobz_scope_mod.CELL_SIGN_PROTOCOL_ID, hat_bkds_mod.CONTEXT_TAG_CELL_SIGN) catch continue;
        try sites.appendSigned(row.cellId, result.derived_pubkey, result.signature);
        signed_count += 1;
    }
    return signed_count;
}

pub fn resignCustomers(
    allocator: std.mem.Allocator,
    customers: *customers_store_fs_mod.CustomersStore,
    hat: *hat_bkds_mod.HatBkds,
) !usize {
    const all = try customers.listAll(allocator);
    defer allocator.free(all);
    var signed_count: usize = 0;
    for (all) |row| {
        if (row.signedBy != null) continue;
        // v1 rows have no cellId — skip them (the v1 schema predates
        // the cell-DAG and there's nothing to sign over).
        const cid = row.cellId orelse continue;
        const result = hat.signCellScoped(&cid, &cid, oddjobz_scope_mod.CELL_SIGN_PROTOCOL_ID, hat_bkds_mod.CONTEXT_TAG_CELL_SIGN) catch continue;
        try customers.appendSigned(cid, result.derived_pubkey, result.signature);
        signed_count += 1;
    }
    return signed_count;
}

pub fn resignJobs(
    allocator: std.mem.Allocator,
    jobs: *jobs_store_fs_mod.JobsStore,
    hat: *hat_bkds_mod.HatBkds,
) !usize {
    const all = try jobs.listAll(allocator);
    defer allocator.free(all);
    var signed_count: usize = 0;
    for (all) |row| {
        if (row.signedBy != null) continue;
        const cid = row.cellId orelse continue;
        const result = hat.signCellScoped(&cid, &cid, oddjobz_scope_mod.CELL_SIGN_PROTOCOL_ID, hat_bkds_mod.CONTEXT_TAG_CELL_SIGN) catch continue;
        try jobs.appendSigned(cid, result.derived_pubkey, result.signature);
        signed_count += 1;
    }
    return signed_count;
}

pub fn resignAttachments(
    allocator: std.mem.Allocator,
    attachments: *attachments_store_fs_mod.AttachmentsStore,
    hat: *hat_bkds_mod.HatBkds,
) !usize {
    const all = try attachments.findAll(allocator);
    defer allocator.free(all);
    var signed_count: usize = 0;
    for (all) |row| {
        if (row.signedBy != null) continue;
        const cid = row.cellId orelse continue;
        const result = hat.signCellScoped(&cid, &cid, oddjobz_scope_mod.CELL_SIGN_PROTOCOL_ID, hat_bkds_mod.CONTEXT_TAG_CELL_SIGN) catch continue;
        try attachments.appendSigned(cid, result.derived_pubkey, result.signature);
        signed_count += 1;
    }
    return signed_count;
}

// W7.7 — `brain export-operator`
// ─────────────────────────────────────────────────────────────────────
//
// Writes a deterministic TAR archive of all LMDB cells + optional Pask
// snapshot for a single operator to the file at `--output <path>`.
//
// Usage:
//   brain export-operator <op_pkh_hex> --output <path> [--data-dir <path>]
//
// <op_pkh_hex>: 16 hex chars = 8 raw bytes (the operator's pubkey-hash
// prefix used in all LMDB key namespacing).
//
// The archive is deterministic: cells are emitted in LMDB key order.
// A peer node can import the archive to reconstruct the operator's data
// byte-identically (W7.8 uses the same archive format for operator exit).

pub fn cmdExportOperator(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    var op_pkh_hex_arg: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;
    var data_dir: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--output") and i + 1 < args.len) {
            output_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--data-dir") and i + 1 < args.len) {
            data_dir = args[i + 1];
            i += 1;
        } else if (op_pkh_hex_arg == null) {
            op_pkh_hex_arg = args[i];
        } else {
            try out.print("export-operator: unknown arg `{s}`\n", .{args[i]});
            return .bad_args;
        }
    }

    const hex = op_pkh_hex_arg orelse {
        try out.print("usage: brain export-operator <op_pkh_hex> --output <path> [--data-dir <path>]\n", .{});
        return .bad_args;
    };
    if (hex.len != 16) {
        try out.print("export-operator: op_pkh_hex must be 16 hex chars (8 bytes), got {d}\n", .{hex.len});
        return .bad_args;
    }
    var op_pkh: [8]u8 = undefined;
    _ = std.fmt.hexToBytes(&op_pkh, hex) catch {
        try out.print("export-operator: invalid hex in op_pkh: {s}\n", .{hex});
        return .bad_args;
    };

    const out_path = output_path orelse {
        try out.print("export-operator: --output <path> is required\n", .{});
        return .bad_args;
    };

    // Resolve data dir ($HOME/.semantos by default).
    const resolved_data_dir: []const u8 = blk: {
        if (data_dir) |d| break :blk try allocator.dupe(u8, d);
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch return .bad_args;
        defer allocator.free(home);
        break :blk try std.fs.path.join(allocator, &.{ home, ".semantos" });
    };
    defer allocator.free(resolved_data_dir);

    // ── Entity cell store ────────────────────────────────────────────

    const entity_lmdb_path = try std.fs.path.join(allocator, &.{ resolved_data_dir, "entity_cells_lmdb" });
    defer allocator.free(entity_lmdb_path);
    std.fs.makeDirAbsolute(entity_lmdb_path) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => {
            try out.print("export-operator: entity-cells lmdb dir create failed: {s}\n", .{@errorName(e)});
            return .file_io;
        },
    };
    var entity_env = lmdb_mod.Env.open(entity_lmdb_path, .{
        .open_flags = lmdb_config_mod.LmdbConfig.prod_flags,
        .map_size = lmdb_config_mod.LmdbConfig.default.map_size,
        .max_dbs = lmdb_config_mod.LmdbConfig.default.max_dbs,
        .mode = lmdb_config_mod.LmdbConfig.default.mode,
    }) catch |e| {
        try out.print("export-operator: failed to open entity-cells LMDB env: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer entity_env.close();

    var cell_store_impl = lmdb_cell_store_mod.LmdbCellStore.initForOperator(&entity_env, allocator, op_pkh) catch |e| {
        try out.print("export-operator: failed to init cell store: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer cell_store_impl.deinit();

    // ── Pask snapshot store (optional) ──────────────────────────────

    const pask_lmdb_path = try std.fs.path.join(allocator, &.{ resolved_data_dir, "pask_snapshots_lmdb" });
    defer allocator.free(pask_lmdb_path);

    var pask_env: ?lmdb_mod.Env = null;
    var pask_store: ?pask_snapshot_store_lmdb_mod.LmdbPaskSnapshotStore = null;
    defer if (pask_env) |*env| env.close();

    {
        std.fs.makeDirAbsolute(pask_lmdb_path) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => {},
        };
        pask_env = lmdb_mod.Env.open(pask_lmdb_path, .{
            .open_flags = lmdb_config_mod.LmdbConfig.prod_flags,
            .map_size = lmdb_config_mod.LmdbConfig.default.map_size,
            .max_dbs = lmdb_config_mod.LmdbConfig.default.max_dbs,
            .mode = lmdb_config_mod.LmdbConfig.default.mode,
        }) catch null;
        if (pask_env) |*env| {
            pask_store = pask_snapshot_store_lmdb_mod.LmdbPaskSnapshotStore.initForOperator(
                env,
                allocator,
                op_pkh,
            ) catch null;
        }
    }

    // ── Write TAR archive ────────────────────────────────────────────

    const tar_file = std.fs.cwd().createFile(out_path, .{}) catch |e| {
        try out.print("export-operator: failed to create output file {s}: {s}\n", .{ out_path, @errorName(e) });
        return .file_io;
    };
    defer tar_file.close();

    var write_buf: [65536]u8 = undefined;
    var fw = tar_file.writer(&write_buf);
    const tar_io: *std.Io.Writer = &fw.interface;

    const manifest = operator_export_mod.writeTar(
        allocator,
        &op_pkh,
        &cell_store_impl,
        if (pask_store) |*ps| ps else null,
        tar_io,
    ) catch |e| {
        try out.print("export-operator: export failed: {s}\n", .{@errorName(e)});
        return .file_io;
    };

    try out.print(
        "export-operator: op={s} cells={d} pask_snapshot={s} output={s}\n",
        .{
            manifest.op_pkh_hex,
            manifest.cell_count,
            if (manifest.has_pask_snapshot) "yes" else "no",
            out_path,
        },
    );
    return .ok;
}

// W7.8 — `brain exit-operator`
// ─────────────────────────────────────────────────────────────────────
//
// Operator exit sequence (ordered):
//   1. Export grace TAR archive to <grace_dir>/<op_pkh_hex>_<ts_ns>.tar
//   2. Delete all LMDB entity cells for the operator
//   3. Delete all LMDB Pask snapshots for the operator
//   4. Delete the NATS JetStream stream (best-effort)
//
// Postgres + Caddy cleanup is NOT done here.  The function prints
// a NEXT STEPS checklist for the operator to follow manually.
//
// Usage:
//   brain exit-operator <op_pkh_hex> [--grace-dir <path>] [--data-dir <path>]
//                                    [--nats-host <host>] [--nats-port <port>]
//                                    [--dry-run]
//
// --dry-run  exports the grace tarball but skips all LMDB/NATS deletions.
// --grace-dir defaults to <data-dir>/grace_tarballs/
// --data-dir  defaults to $HOME/.semantos
// --nats-host defaults to 127.0.0.1 (NATS connection best-effort)
// --nats-port defaults to 4222

pub fn cmdExitOperator(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    var op_pkh_hex_arg: ?[]const u8 = null;
    var grace_dir_arg: ?[]const u8 = null;
    var data_dir_arg: ?[]const u8 = null;
    var nats_host_arg: ?[]const u8 = null;
    var nats_port_arg: ?[]const u8 = null;
    var dry_run = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--grace-dir") and i + 1 < args.len) {
            grace_dir_arg = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--data-dir") and i + 1 < args.len) {
            data_dir_arg = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--nats-host") and i + 1 < args.len) {
            nats_host_arg = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--nats-port") and i + 1 < args.len) {
            nats_port_arg = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--dry-run")) {
            dry_run = true;
        } else if (op_pkh_hex_arg == null) {
            op_pkh_hex_arg = args[i];
        } else {
            try out.print("exit-operator: unknown arg `{s}`\n", .{args[i]});
            return .bad_args;
        }
    }

    const hex = op_pkh_hex_arg orelse {
        try out.print(
            "usage: brain exit-operator <op_pkh_hex> [--grace-dir <path>] [--data-dir <path>]\n" ++
            "                                        [--nats-host <host>] [--nats-port <port>] [--dry-run]\n",
            .{},
        );
        return .bad_args;
    };
    if (hex.len != 16) {
        try out.print("exit-operator: op_pkh_hex must be 16 hex chars (8 bytes), got {d}\n", .{hex.len});
        return .bad_args;
    }
    var op_pkh: [8]u8 = undefined;
    _ = std.fmt.hexToBytes(&op_pkh, hex) catch {
        try out.print("exit-operator: invalid hex in op_pkh: {s}\n", .{hex});
        return .bad_args;
    };

    // Resolve data dir ($HOME/.semantos by default).
    const resolved_data_dir: []const u8 = blk: {
        if (data_dir_arg) |d| break :blk try allocator.dupe(u8, d);
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch return .bad_args;
        defer allocator.free(home);
        break :blk try std.fs.path.join(allocator, &.{ home, ".semantos" });
    };
    defer allocator.free(resolved_data_dir);

    // Resolve grace dir (<data_dir>/grace_tarballs/ by default).
    const resolved_grace_dir: []const u8 = blk: {
        if (grace_dir_arg) |d| break :blk try allocator.dupe(u8, d);
        break :blk try std.fs.path.join(allocator, &.{ resolved_data_dir, "grace_tarballs" });
    };
    defer allocator.free(resolved_grace_dir);

    // Ensure grace dir exists.
    std.fs.makeDirAbsolute(resolved_grace_dir) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => {
            try out.print("exit-operator: grace-dir create failed: {s}\n", .{@errorName(e)});
            return .file_io;
        },
    };

    // ── Entity cell store ────────────────────────────────────────────

    const entity_lmdb_path = try std.fs.path.join(allocator, &.{ resolved_data_dir, "entity_cells_lmdb" });
    defer allocator.free(entity_lmdb_path);
    std.fs.makeDirAbsolute(entity_lmdb_path) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => {
            try out.print("exit-operator: entity-cells lmdb dir create failed: {s}\n", .{@errorName(e)});
            return .file_io;
        },
    };
    var entity_env = lmdb_mod.Env.open(entity_lmdb_path, .{
        .open_flags = lmdb_config_mod.LmdbConfig.prod_flags,
        .map_size = lmdb_config_mod.LmdbConfig.default.map_size,
        .max_dbs = lmdb_config_mod.LmdbConfig.default.max_dbs,
        .mode = lmdb_config_mod.LmdbConfig.default.mode,
    }) catch |e| {
        try out.print("exit-operator: failed to open entity-cells LMDB env: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer entity_env.close();

    var cell_store_impl = lmdb_cell_store_mod.LmdbCellStore.initForOperator(&entity_env, allocator, op_pkh) catch |e| {
        try out.print("exit-operator: failed to init cell store: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer cell_store_impl.deinit();

    // ── Pask snapshot store (optional) ──────────────────────────────

    const pask_lmdb_path = try std.fs.path.join(allocator, &.{ resolved_data_dir, "pask_snapshots_lmdb" });
    defer allocator.free(pask_lmdb_path);

    var pask_env: ?lmdb_mod.Env = null;
    var pask_store: ?pask_snapshot_store_lmdb_mod.LmdbPaskSnapshotStore = null;
    defer if (pask_env) |*env| env.close();

    {
        std.fs.makeDirAbsolute(pask_lmdb_path) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => {},
        };
        pask_env = lmdb_mod.Env.open(pask_lmdb_path, .{
            .open_flags = lmdb_config_mod.LmdbConfig.prod_flags,
            .map_size = lmdb_config_mod.LmdbConfig.default.map_size,
            .max_dbs = lmdb_config_mod.LmdbConfig.default.max_dbs,
            .mode = lmdb_config_mod.LmdbConfig.default.mode,
        }) catch null;
        if (pask_env) |*env| {
            pask_store = pask_snapshot_store_lmdb_mod.LmdbPaskSnapshotStore.initForOperator(
                env,
                allocator,
                op_pkh,
            ) catch null;
        }
    }

    // ── NATS (best-effort) ───────────────────────────────────────────

    const nats_host = nats_host_arg orelse "127.0.0.1";
    const nats_port: u16 = blk: {
        if (nats_port_arg) |ps| {
            break :blk std.fmt.parseInt(u16, ps, 10) catch {
                try out.print("exit-operator: invalid --nats-port value: {s}\n", .{ps});
                return .bad_args;
            };
        }
        break :blk 4222;
    };

    var nats_client: ?nats_client_mod.NatsClient = nats_client_mod.NatsClient.init(
        allocator,
        .{ .host = nats_host, .port = nats_port },
    ) catch null;
    defer if (nats_client) |*nc| nc.deinit();

    const op_pkh16: [16]u8 = std.fmt.bytesToHex(&op_pkh, .lower);
    var nats_producer: ?nats_event_producer_mod.NatsEventProducer = null;
    if (nats_client) |*nc| {
        nats_producer = nats_event_producer_mod.NatsEventProducer.init(allocator, nc, op_pkh16);
    }

    // ── Build grace tarball path ─────────────────────────────────────

    const ts_ns = std.time.nanoTimestamp();
    const tar_name = try std.fmt.allocPrint(allocator, "{s}_{d}.tar", .{ hex, ts_ns });
    defer allocator.free(tar_name);
    const tar_path = try std.fs.path.join(allocator, &.{ resolved_grace_dir, tar_name });
    defer allocator.free(tar_path);

    // ── Open tarball file and get writer ─────────────────────────────

    const tar_file = std.fs.cwd().createFile(tar_path, .{}) catch |e| {
        try out.print("exit-operator: failed to create grace tarball {s}: {s}\n", .{ tar_path, @errorName(e) });
        return .file_io;
    };
    defer tar_file.close();

    var write_buf: [65536]u8 = undefined;
    var fw = tar_file.writer(&write_buf);
    const tar_io: *std.Io.Writer = &fw.interface;

    // ── Run exit sequence ────────────────────────────────────────────

    const summary = operator_exit_mod.runExit(
        allocator,
        &op_pkh,
        &cell_store_impl,
        if (pask_store) |*ps| ps else null,
        if (nats_producer) |*np| np else null,
        tar_io,
        dry_run,
    ) catch |e| switch (e) {
        error.export_failed => {
            try out.print("exit-operator: grace tarball export failed\n", .{});
            return .file_io;
        },
        error.delete_cells_failed => {
            try out.print("exit-operator: LMDB cell deletion failed (grace tarball written to {s})\n", .{tar_path});
            return .file_io;
        },
        error.delete_pask_failed => {
            try out.print("exit-operator: LMDB pask snapshot deletion failed (grace tarball written to {s})\n", .{tar_path});
            return .file_io;
        },
        error.out_of_memory => return error.OutOfMemory,
    };

    // ── Print summary ────────────────────────────────────────────────

    try out.print(
        "exit-operator: op={s} cells_exported={d} cells_deleted={s} pask_deleted={s} nats={s} grace={s}\n",
        .{
            summary.op_pkh_hex,
            summary.cells_exported,
            if (summary.cells_deleted) "yes" else if (dry_run) "dry-run" else "no",
            if (summary.pask_deleted) "yes" else if (dry_run) "dry-run" else "no",
            if (summary.nats_stream_deleted) "yes" else if (dry_run) "dry-run" else "no",
            tar_path,
        },
    );

    try out.print(
        \\
        \\NEXT STEPS (manual):
        \\  1. Copy grace tarball to B2:
        \\     rclone copy {s} b2:semantos-grace-tarballs/
        \\  2. Run Postgres cleanup:
        \\     psql $BRAIN_DB_URL -c "SELECT operator_exit('{s}');"
        \\  3. Remove domain from Caddy allow-list (W7.14 — not yet implemented).
        \\
    , .{ tar_path, hex });

    return .ok;
}

// W7.13 — `brain orphan-streams`
// ─────────────────────────────────────────────────────────────────────
//
// List (and optionally delete) JetStream streams in the op_<pkh16> namespace
// whose pkh16 does not appear in --known-pkh-list.
//
// Usage:
//   brain orphan-streams --known-pkh-list <pkh1,pkh2,...>
//                        [--nats-host <host>] [--nats-port <port>]
//                        [--delete] [--dry-run]
//
// --known-pkh-list  comma-separated 16-char hex op_pkh values; obtained from
//                   Postgres by the nightly systemd timer script.
// --delete          delete orphan streams (default: list only).
// --dry-run         print what would be done without deleting.

pub fn cmdOrphanStreams(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    var known_pkh_list_arg: ?[]const u8 = null;
    var nats_host_arg: ?[]const u8 = null;
    var nats_port_arg: ?[]const u8 = null;
    var do_delete = false;
    var dry_run = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--known-pkh-list") and i + 1 < args.len) {
            known_pkh_list_arg = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--nats-host") and i + 1 < args.len) {
            nats_host_arg = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--nats-port") and i + 1 < args.len) {
            nats_port_arg = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--delete")) {
            do_delete = true;
        } else if (std.mem.eql(u8, args[i], "--dry-run")) {
            dry_run = true;
        } else {
            try out.print("orphan-streams: unknown arg `{s}`\n", .{args[i]});
            return .bad_args;
        }
    }

    const pkh_list_str = known_pkh_list_arg orelse {
        try out.print(
            "usage: brain orphan-streams --known-pkh-list <pkh1,pkh2,...>\n" ++
            "                            [--nats-host <host>] [--nats-port <port>]\n" ++
            "                            [--delete] [--dry-run]\n",
            .{},
        );
        return .bad_args;
    };

    // Parse comma-separated list of op_pkh16 values.
    var known: std.ArrayList([]const u8) = .{};
    defer known.deinit(allocator);

    if (pkh_list_str.len > 0) {
        var it = std.mem.splitScalar(u8, pkh_list_str, ',');
        while (it.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t\r\n");
            if (trimmed.len == 0) continue;
            if (trimmed.len != 16) {
                try out.print("orphan-streams: bad pkh16 `{s}` (must be 16 hex chars)\n", .{trimmed});
                return .bad_args;
            }
            try known.append(allocator, trimmed);
        }
    }

    // Connect to NATS.
    const nats_host = nats_host_arg orelse "127.0.0.1";
    const nats_port: u16 = blk: {
        if (nats_port_arg) |ps| {
            break :blk std.fmt.parseInt(u16, ps, 10) catch {
                try out.print("orphan-streams: invalid --nats-port: {s}\n", .{ps});
                return .bad_args;
            };
        }
        break :blk 4222;
    };

    var nc = nats_client_mod.NatsClient.init(
        allocator,
        .{ .host = nats_host, .port = nats_port },
    ) catch |e| {
        try out.print("orphan-streams: NATS connect failed ({s}); cannot list streams\n", .{@errorName(e)});
        return .file_io;
    };
    defer nc.deinit();

    if (do_delete and !dry_run) {
        // Purge mode.
        const report = nats_orphan_detector_mod.purgeOrphans(
            allocator,
            &nc,
            known.items,
        ) catch |e| {
            try out.print("orphan-streams: detection failed ({s})\n", .{@errorName(e)});
            return .file_io;
        };
        try out.print(
            "orphan-streams: detected={d} purged={d} failed={d}\n",
            .{ report.detected, report.purged, report.failed },
        );
        if (report.failed > 0) return .file_io;
    } else {
        // List-only (or dry-run) mode.
        const orphan_list = nats_orphan_detector_mod.detectOrphans(
            allocator,
            &nc,
            known.items,
        ) catch |e| {
            try out.print("orphan-streams: detection failed ({s})\n", .{@errorName(e)});
            return .file_io;
        };
        defer orphan_list.deinit();

        try out.print(
            "orphan-streams: {d} orphan(s) detected{s}\n",
            .{ orphan_list.names.len, if (dry_run and do_delete) " (dry-run; not deleted)" else "" },
        );
        for (orphan_list.names) |name| {
            try out.print("  {s}\n", .{name});
        }
    }

    return .ok;
}

// W7.14 — `brain domain-allow` / `brain domain-disallow`
// ─────────────────────────────────────────────────────────────────────
//
// Manage the Caddy on-demand TLS domain allowlist.
// File: <data_dir>/domain_allowlist (one FQDN per line).
//
// Usage:
//   brain domain-allow <fqdn> [--data-dir <path>]
//   brain domain-disallow <fqdn> [--data-dir <path>]

pub fn cmdDomainAllow(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    return domainAllowImpl(allocator, out, args, true);
}

pub fn cmdDomainDisallow(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    return domainAllowImpl(allocator, out, args, false);
}

fn domainAllowImpl(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
    add: bool,
) !ExitCode {
    var fqdn_arg: ?[]const u8 = null;
    var data_dir_arg: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--data-dir") and i + 1 < args.len) {
            data_dir_arg = args[i + 1];
            i += 1;
        } else if (fqdn_arg == null) {
            fqdn_arg = args[i];
        } else {
            try out.print("domain-{s}: unknown arg `{s}`\n", .{ if (add) "allow" else "disallow", args[i] });
            return .bad_args;
        }
    }

    const fqdn = fqdn_arg orelse {
        try out.print("usage: brain domain-{s} <fqdn> [--data-dir <path>]\n", .{if (add) "allow" else "disallow"});
        return .bad_args;
    };

    const data_dir: []const u8 = blk: {
        if (data_dir_arg) |d| break :blk try allocator.dupe(u8, d);
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch return .bad_args;
        defer allocator.free(home);
        break :blk try std.fs.path.join(allocator, &.{ home, ".semantos" });
    };
    defer allocator.free(data_dir);

    if (add) {
        domain_allowlist_mod.add(allocator, data_dir, fqdn) catch |e| {
            try out.print("domain-allow: failed to add {s}: {s}\n", .{ fqdn, @errorName(e) });
            return .file_io;
        };
        try out.print("domain-allow: added {s}\n", .{fqdn});
    } else {
        domain_allowlist_mod.remove(allocator, data_dir, fqdn) catch |e| {
            try out.print("domain-disallow: failed to remove {s}: {s}\n", .{ fqdn, @errorName(e) });
            return .file_io;
        };
        try out.print("domain-disallow: removed {s}\n", .{fqdn});
    }

    return .ok;
}

// W7.14 — `brain caddy-ask`
// ─────────────────────────────────────────────────────────────────────
//
// Run the Caddy on-demand TLS ask server.  Blocks; intended to run as
// a systemd service alongside `brain serve`.
//
// Global Caddy config (e.g. /etc/caddy/conf.d/00-globals.conf):
//   {
//       on_demand_tls {
//           ask http://127.0.0.1:2020/caddy/ask
//       }
//   }

pub fn cmdCaddyAsk(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    var port_arg: ?[]const u8 = null;
    var data_dir_arg: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
            port_arg = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--data-dir") and i + 1 < args.len) {
            data_dir_arg = args[i + 1];
            i += 1;
        } else {
            try out.print("caddy-ask: unknown arg `{s}`\n", .{args[i]});
            return .bad_args;
        }
    }

    const port: u16 = blk: {
        if (port_arg) |ps| {
            break :blk std.fmt.parseInt(u16, ps, 10) catch {
                try out.print("caddy-ask: invalid --port: {s}\n", .{ps});
                return .bad_args;
            };
        }
        break :blk 2020;
    };

    const data_dir: []const u8 = blk: {
        if (data_dir_arg) |d| break :blk try allocator.dupe(u8, d);
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch return .bad_args;
        defer allocator.free(home);
        break :blk try std.fs.path.join(allocator, &.{ home, ".semantos" });
    };
    defer allocator.free(data_dir);

    try out.print("caddy-ask: listening on 127.0.0.1:{d} data_dir={s}\n", .{ port, data_dir });

    caddy_ask_server_mod.run(port, data_dir, allocator) catch |e| {
        try out.print("caddy-ask: bind failed on port {d}: {s}\n", .{ port, @errorName(e) });
        return .file_io;
    };

    return .ok; // unreachable in practice; server loops forever
}

// W7.15 — `brain sni-map`
// ─────────────────────────────────────────────────────────────────────
//
// Manage the file-backed SNI domain → op_pkh resolution map.
// File: <data_dir>/sni_domain_map.json
//
// Usage:
//   brain sni-map set <brain_domain> <op_pkh_hex> [--data-dir <path>]
//   brain sni-map remove <brain_domain> [--data-dir <path>]
//   brain sni-map show [--data-dir <path>]

pub fn cmdSniMap(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    var data_dir_arg: ?[]const u8 = null;
    var sub: ?[]const u8 = null;
    var pos_args: [2]?[]const u8 = .{ null, null };
    var pos_idx: usize = 0;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--data-dir") and i + 1 < args.len) {
            data_dir_arg = args[i + 1];
            i += 1;
        } else if (sub == null) {
            sub = args[i];
        } else if (pos_idx < 2) {
            pos_args[pos_idx] = args[i];
            pos_idx += 1;
        } else {
            try out.print("sni-map: unexpected arg `{s}`\n", .{args[i]});
            return .bad_args;
        }
    }

    const subcommand = sub orelse {
        try out.print(
            "usage: brain sni-map <set|remove|show> [args] [--data-dir <path>]\n",
            .{},
        );
        return .bad_args;
    };

    const data_dir: []const u8 = blk: {
        if (data_dir_arg) |d| break :blk try allocator.dupe(u8, d);
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch return .bad_args;
        defer allocator.free(home);
        break :blk try std.fs.path.join(allocator, &.{ home, ".semantos" });
    };
    defer allocator.free(data_dir);

    var m = sni_domain_map_mod.DomainMap.init(allocator);
    defer m.deinit();
    m.loadFromFile(data_dir) catch |e| switch (e) {
        error.file_io => {
            try out.print("sni-map: failed to read {s}/sni_domain_map.json\n", .{data_dir});
            return .file_io;
        },
        error.malformed_json => {
            try out.print("sni-map: malformed JSON in {s}/sni_domain_map.json\n", .{data_dir});
            return .file_io;
        },
        error.out_of_memory => return error.OutOfMemory,
    };

    if (std.mem.eql(u8, subcommand, "show")) {
        var it = m.entries.iterator();
        var count: u32 = 0;
        while (it.next()) |entry| {
            try out.print("{s} -> {s}\n", .{ entry.key_ptr.*, &entry.value_ptr.* });
            count += 1;
        }
        if (count == 0) try out.print("sni-map: (empty)\n", .{});
        return .ok;
    }

    if (std.mem.eql(u8, subcommand, "set")) {
        const brain_domain = pos_args[0] orelse {
            try out.print("usage: brain sni-map set <brain_domain> <op_pkh_hex>\n", .{});
            return .bad_args;
        };
        const hex = pos_args[1] orelse {
            try out.print("usage: brain sni-map set <brain_domain> <op_pkh_hex>\n", .{});
            return .bad_args;
        };
        if (hex.len != 16) {
            try out.print("sni-map: op_pkh_hex must be 16 hex chars, got {d}\n", .{hex.len});
            return .bad_args;
        }
        var pkh16: [16]u8 = undefined;
        @memcpy(&pkh16, hex[0..16]);

        m.set(brain_domain, pkh16) catch return error.OutOfMemory;
        m.saveToFile(data_dir) catch {
            try out.print("sni-map: failed to write {s}/sni_domain_map.json\n", .{data_dir});
            return .file_io;
        };
        try out.print("sni-map: set {s} -> {s}\n", .{ brain_domain, &pkh16 });
        return .ok;
    }

    if (std.mem.eql(u8, subcommand, "remove")) {
        const brain_domain = pos_args[0] orelse {
            try out.print("usage: brain sni-map remove <brain_domain>\n", .{});
            return .bad_args;
        };
        m.remove(brain_domain);
        m.saveToFile(data_dir) catch {
            try out.print("sni-map: failed to write {s}/sni_domain_map.json\n", .{data_dir});
            return .file_io;
        };
        try out.print("sni-map: removed {s}\n", .{brain_domain});
        return .ok;
    }

    try out.print("sni-map: unknown subcommand `{s}`\n", .{subcommand});
    return .bad_args;
}

// W7.5 — `brain wrapped-dek`
//
//   brain wrapped-dek set <op_pkh_hex> <wrapped_dek_hex> [--data-dir <path>]
//   brain wrapped-dek show <op_pkh_hex> [--data-dir <path>]
//   brain wrapped-dek delete <op_pkh_hex> [--data-dir <path>]
//
// Manages the per-operator wrapped DEK blob at
// $data_dir/operators/<op_pkh16>/wrapped_dek.  Called at provisioning (set)
// and operator exit (delete).
pub fn cmdWrappedDek(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    var subcommand: ?[]const u8 = null;
    var data_dir_arg: ?[]const u8 = null;
    var pos_args: [2]?[]const u8 = .{ null, null };
    var pos_idx: usize = 0;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--data-dir") and i + 1 < args.len) {
            i += 1;
            data_dir_arg = args[i];
        } else if (subcommand == null) {
            subcommand = a;
        } else if (pos_idx < 2) {
            pos_args[pos_idx] = a;
            pos_idx += 1;
        } else {
            try out.print("wrapped-dek: unexpected arg `{s}`\n", .{a});
            return .bad_args;
        }
    }

    const subcmd = subcommand orelse {
        try out.print(
            "usage: brain wrapped-dek <set|show|delete> [args] [--data-dir <path>]\n",
            .{},
        );
        return .bad_args;
    };

    const data_dir: []const u8 = blk: {
        if (data_dir_arg) |d| break :blk try allocator.dupe(u8, d);
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch return .bad_args;
        defer allocator.free(home);
        break :blk try std.fs.path.join(allocator, &.{ home, ".semantos" });
    };
    defer allocator.free(data_dir);

    if (std.mem.eql(u8, subcmd, "set")) {
        const op_pkh_arg = pos_args[0] orelse {
            try out.print("usage: brain wrapped-dek set <op_pkh_hex> <wrapped_dek_hex>\n", .{});
            return .bad_args;
        };
        const dek_hex = pos_args[1] orelse {
            try out.print("usage: brain wrapped-dek set <op_pkh_hex> <wrapped_dek_hex>\n", .{});
            return .bad_args;
        };
        if (op_pkh_arg.len != 16) {
            try out.print("wrapped-dek: op_pkh_hex must be exactly 16 hex chars\n", .{});
            return .bad_args;
        }
        var op_pkh16: [16]u8 = undefined;
        @memcpy(&op_pkh16, op_pkh_arg[0..16]);

        wrapped_dek_store_mod.save(allocator, data_dir, op_pkh16, dek_hex) catch |err| {
            const msg = switch (err) {
                error.bad_format => "wrapped_dek_hex must be even-length all-hex string",
                error.file_io => "file I/O error writing wrapped_dek",
                error.out_of_memory => "out of memory",
                else => "error",
            };
            try out.print("wrapped-dek set: {s}\n", .{msg});
            return .file_io;
        };
        try out.print("wrapped-dek: stored for op_pkh={s}\n", .{op_pkh_arg});
        return .ok;
    }

    if (std.mem.eql(u8, subcmd, "show")) {
        const op_pkh_arg = pos_args[0] orelse {
            try out.print("usage: brain wrapped-dek show <op_pkh_hex>\n", .{});
            return .bad_args;
        };
        if (op_pkh_arg.len != 16) {
            try out.print("wrapped-dek: op_pkh_hex must be exactly 16 hex chars\n", .{});
            return .bad_args;
        }
        var op_pkh16: [16]u8 = undefined;
        @memcpy(&op_pkh16, op_pkh_arg[0..16]);

        const hex = wrapped_dek_store_mod.load(allocator, data_dir, op_pkh16) catch |err| {
            const msg = switch (err) {
                error.not_found => "no wrapped DEK stored for this operator",
                error.bad_format => "stored file has unexpected format",
                error.file_io => "file I/O error",
                error.out_of_memory => "out of memory",
            };
            try out.print("wrapped-dek show: {s}\n", .{msg});
            return .file_io;
        };
        defer allocator.free(hex);
        try out.print("{s}\n", .{hex});
        return .ok;
    }

    if (std.mem.eql(u8, subcmd, "delete")) {
        const op_pkh_arg = pos_args[0] orelse {
            try out.print("usage: brain wrapped-dek delete <op_pkh_hex>\n", .{});
            return .bad_args;
        };
        if (op_pkh_arg.len != 16) {
            try out.print("wrapped-dek: op_pkh_hex must be exactly 16 hex chars\n", .{});
            return .bad_args;
        }
        var op_pkh16: [16]u8 = undefined;
        @memcpy(&op_pkh16, op_pkh_arg[0..16]);

        wrapped_dek_store_mod.delete(allocator, data_dir, op_pkh16) catch {
            try out.print("wrapped-dek delete: file I/O error\n", .{});
            return .file_io;
        };
        try out.print("wrapped-dek: deleted for op_pkh={s}\n", .{op_pkh_arg});
        return .ok;
    }

    try out.print("wrapped-dek: unknown subcommand `{s}`\n", .{subcmd});
    return .bad_args;
}

// S12 — `brain site-preview`
// ─────────────────────────────────────────────────────────────────────
//
// Renders the operator site HTML for a given profile and writes it to
// --output <path> (or stdout when omitted).
//
// Usage:
//   brain site-preview [<domain_or_path>] [--data-dir <path>] [--output <path>]
//
// <domain_or_path>:
//   - A domain name (contains ".") → load $data_dir/sites/<domain>/profile.json
//   - A file path → load profile from that path directly
//   - Omitted → use the built-in Oddjobz sample profile (defaultProfile)
//
// TODO(S11): file-based profile loading lands when operator_profile_loader ships.
// Until then, defaultProfile() is always used regardless of <domain_or_path>.

pub fn cmdSitePreview(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    var domain_or_path: ?[]const u8 = null;
    var data_dir_arg: ?[]const u8 = null;
    var output_path: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--data-dir") and i + 1 < args.len) {
            data_dir_arg = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--output") and i + 1 < args.len) {
            output_path = args[i + 1];
            i += 1;
        } else if (domain_or_path == null and args[i].len > 0 and args[i][0] != '-') {
            domain_or_path = args[i];
        } else {
            try out.print("site-preview: unknown arg `{s}`\n", .{args[i]});
            return .bad_args;
        }
    }

    const label = domain_or_path orelse "default profile";
    const data_dir = data_dir_arg orelse ".";

    const profile = if (domain_or_path) |dop| blk: {
        if (std.mem.indexOfScalar(u8, dop, '.') != null) {
            // Looks like a domain — resolve via data_dir
            break :blk operator_profile_loader_mod.loadForDomain(allocator, data_dir, dop) catch |err| switch (err) {
                error.file_not_found => try operator_profile_mod.defaultProfile(allocator),
                else => {
                    try out.print("site-preview: failed to load profile for '{s}': {s}\n", .{ dop, @errorName(err) });
                    return .file_io;
                },
            };
        } else {
            // Direct file path
            break :blk operator_profile_loader_mod.loadFromFile(allocator, dop) catch |err| switch (err) {
                error.file_not_found => {
                    try out.print("site-preview: profile not found: {s}\n", .{dop});
                    return .file_io;
                },
                else => {
                    try out.print("site-preview: failed to load profile: {s}\n", .{@errorName(err)});
                    return .file_io;
                },
            };
        }
    } else try operator_profile_mod.defaultProfile(allocator);

    // Render HTML into a buffer, then write to the requested destination.
    var html_buf = std.ArrayList(u8){};
    defer html_buf.deinit(allocator);

    operator_site_renderer_mod.renderSite(html_buf.writer(allocator), profile, null) catch |err| {
        try out.print("site-preview: render failed: {s}\n", .{@errorName(err)});
        return .file_io;
    };

    if (output_path) |path| {
        const file = std.fs.createFileAbsolute(path, .{ .truncate = true }) catch |err| {
            try out.print("site-preview: cannot open output file `{s}`: {s}\n", .{ path, @errorName(err) });
            return .file_io;
        };
        defer file.close();
        file.writeAll(html_buf.items) catch |err| {
            try out.print("site-preview: write failed: {s}\n", .{@errorName(err)});
            return .file_io;
        };
        // Summary to stderr so it doesn't pollute the file-output path.
        var sum_buf: [512]u8 = undefined;
        var sum_writer = std.fs.File.stderr().writer(&sum_buf);
        try sum_writer.interface.print("// site-preview: rendered {s} to {s}\n", .{ label, path });
        try sum_writer.interface.flush();
    } else {
        try out.print("{s}", .{html_buf.items});
        // Summary to stderr so it doesn't pollute the HTML stream.
        var sum_buf: [512]u8 = undefined;
        var sum_writer = std.fs.File.stderr().writer(&sum_buf);
        try sum_writer.interface.print("// site-preview: rendered {s} to stdout\n", .{label});
        try sum_writer.interface.flush();
    }

    return .ok;
}

// S13 — `brain site-publish`
// ─────────────────────────────────────────────────────────────────────
//
// Writes a validated profile.json to $data_dir/sites/<domain>/profile.json,
// creating the directory if needed.  JSON is read from --from <file> or
// from stdin when omitted.
//
// Usage:
//   brain site-publish <domain> [--data-dir <path>] [--from <profile.json>]

pub fn cmdSitePublish(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    var domain: ?[]const u8 = null;
    var data_dir: []const u8 = ".";
    var from_path: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--data-dir") and i + 1 < args.len) {
            data_dir = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--from") and i + 1 < args.len) {
            from_path = args[i + 1];
            i += 1;
        } else if (domain == null and args[i].len > 0 and args[i][0] != '-') {
            domain = args[i];
        } else {
            try out.print("site-publish: unknown arg `{s}`\n", .{args[i]});
            return .bad_args;
        }
    }

    const dom = domain orelse {
        try out.print("site-publish: missing required argument <domain>\n", .{});
        return .bad_args;
    };

    // Read JSON from --from <file> or stdin.
    const MAX_JSON = 64 * 1024;
    const json_bytes: []const u8 = if (from_path) |fp| blk: {
        const file = std.fs.cwd().openFile(fp, .{}) catch |err| {
            try out.print("site-publish: cannot open '{s}': {s}\n", .{ fp, @errorName(err) });
            return .file_io;
        };
        defer file.close();
        const stat = file.stat() catch return .file_io;
        if (stat.size > MAX_JSON) {
            try out.print("site-publish: profile file too large (max 64 KB)\n", .{});
            return .bad_args;
        }
        const buf = allocator.alloc(u8, stat.size) catch return .oom;
        const n = file.readAll(buf) catch return .file_io;
        break :blk buf[0..n];
    } else blk: {
        // Read up to MAX_JSON bytes from stdin.
        const buf = allocator.alloc(u8, MAX_JSON) catch return .oom;
        const n = std.fs.File.stdin().readAll(buf) catch return .file_io;
        break :blk buf[0..n];
    };

    // Validate: parse to OperatorProfile (and discard — just checking the schema).
    _ = operator_profile_loader_mod.parseProfileJson(allocator, json_bytes) catch |err| {
        try out.print("site-publish: invalid profile JSON: {s}\n", .{@errorName(err)});
        return .bad_args;
    };

    // Ensure $data_dir/sites/<domain>/ exists.
    const site_dir_path = std.fs.path.join(allocator, &.{ data_dir, "sites", dom }) catch return .oom;
    std.fs.cwd().makePath(site_dir_path) catch |err| {
        try out.print("site-publish: cannot create directory '{s}': {s}\n", .{ site_dir_path, @errorName(err) });
        return .file_io;
    };

    // Write to $data_dir/sites/<domain>/profile.json.
    const dest_path = std.fs.path.join(allocator, &.{ site_dir_path, "profile.json" }) catch return .oom;
    const dest = std.fs.cwd().createFile(dest_path, .{ .truncate = true }) catch |err| {
        try out.print("site-publish: cannot write '{s}': {s}\n", .{ dest_path, @errorName(err) });
        return .file_io;
    };
    defer dest.close();
    dest.writeAll(json_bytes) catch |err| {
        try out.print("site-publish: write failed: {s}\n", .{@errorName(err)});
        return .file_io;
    };

    try out.print("site-publish: wrote {d} bytes → {s}\n", .{ json_bytes.len, dest_path });
    return .ok;
}

```
