---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cli/lifecycle.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.284392+00:00
---

# runtime/semantos-brain/src/cli/lifecycle.zig

```zig
// Lifecycle verbs extracted from src/cli.zig as Move 2 of the
// cli-modularize refactor.  Pure code motion: no behaviour change.
//
// Owns: VERSION, HELP_TEXT, the lifecycle cmd verbs (help, version,
// init, status, hash, start, stop), and the small helpers cmdStart
// uses (StoreBackend, parseStoreBackend, parseDataDir).
//
// Source cli.zig re-exports every pub symbol so external callers
// (main.zig, tests/*.zig) keep reaching them as cli.X.

const std = @import("std");
const cli_common = @import("common.zig");
const config = @import("config");
const module_loader = @import("module_loader");
const audit_log_mod = @import("audit_log");
const dispatcher_mod = @import("dispatcher");
const modules_handler_mod = @import("modules_handler");
const runner_mod = @import("runner");
const broker_mod = @import("broker");
const instance_manager = @import("instance_manager");
const slot_store_fs_mod = @import("slot_store_fs");
const state_store_fs_mod = @import("state_store_fs");
const header_store_fs_mod = @import("header_store_fs");
const lmdb_config_mod = @import("lmdb_config");
const lmdb_mod = @import("lmdb");
const lmdb_header_store_mod = @import("lmdb_header_store");
const lmdb_derivation_state_mod = @import("lmdb_derivation_state");

const Output = cli_common.Output;
const ExitCode = cli_common.ExitCode;

pub const VERSION = "0.1.0-brain1";

pub const HELP_TEXT =
    \\brain — Semantos sovereign-node host shell
    \\
    \\USAGE:
    \\    brain <command> [args...]
    \\
    \\COMMANDS:
    \\    init [--config-path <path>]      Create a default config file
    \\    status [--config-path <path>]    Show module health + hash status
    \\    hash <wasm_file>                  Print SHA-256 of a WASM file
    \\    start [--config-path <path>]    Verify modules + boot (wasmtime: Brain 2)
    \\    stop                              Stop the running shell (Brain 2.5+)
    \\    repl [--config-path <path>]     Open the interactive REPL (Brain 3)
    \\    site <subcommand> [args...]      Manage sites (WSITE1)
    \\                                     init <domain>     scaffold ~/.semantos/sites/<domain>/
    \\                                     validate <domain> check site config
    \\                                     list              list configured sites
    \\    serve <domain> [--port N] [--enable-repl] [--repl-config-path <path>] [--signed-bundle-endpoint <path>] [--bundle-frame-endpoint <path>] [--enable-intent-action-router]
    \\                                     Start the HTTP site server (WSITE2). With --enable-repl,
    \\                                     POST /api/v1/repl dispatches into the same Session as `brain repl`,
    \\                                     and GET /api/v1/wallet upgrades to a BRC-100 WSS endpoint
    \\                                     (Brain 4 / Brain 4.5) — both bearer-gated by `brain bearer issue`.
    \\    repl [--llm]                     Interactive REPL. With --llm, modal-verb-prefixed lines
    \\                                     (`do `, `find `, `talk `) route through the configured LLM
    \\                                     (Brain 5.2). Always confirms before dispatch.
    \\    revenue <domain> [--since N] [--verified-only]
    \\                                     Show payment ledger summary (WSITE4 / WSITE4.5)
    \\    sweep <domain>                   Re-verify pending payment claims via stored BEEFs (WSITE4.5)
    \\    outputs <domain> [--basket NAME] [--include-spent]
    \\                                     List internalized UTXOs the admin's wallet owns (WSITE4.6)
    \\    sessions <domain> [--all]        List active sessions (WSITE5)
    \\    sessions revoke <domain> <id>    Revoke a session by id (WSITE5)
    \\    refund <domain> <txid> [--reason TEXT]
    \\                                     Record a refund intent against a verified payment (WSITE5)
    \\    headers <subcommand>             Manage the trustless-SPV header chain (WH-Producer)
    \\                                     tip                              show current header tip
    \\                                     sync [--peer host:port] [--max-rounds N]
    \\                                                                      sync to peer's tip via P2P
    \\                                     serve [--http-port N] [--peer host:port] [--sync-interval-secs N]
    \\                                                                      long-running tip subscription + BHS-compatible HTTP
    \\                                     reset                            wipe + ready for re-sync
    \\    bearer <subcommand>              Manage bearer tokens for the remote-access surfaces (Brain 4 / D-W1 P1)
    \\                                     issue --label NAME [--ttl-seconds N]   create + print a token
    \\                                     list                                  list issued tokens
    \\                                     revoke <id>                           revoke a token by id
    \\                                     (talks to the running daemon over the Unix socket if present;
    \\                                      falls back to embedded mode otherwise — banner shows which path ran)
    \\    device <subcommand>              Manage paired device certs (D-W1 P1.2 + Phase 1 follow-up)
    \\                                     init [--label NAME] [--data-dir PATH]  bootstrap operator-root priv + root cert (run once before `brain serve`)
    \\                                     pair --device-name NAME [--data-dir PATH] [--caps minimal|full|cap.X,cap.Y,...] [--brain-domain DOMAIN]
    \\                                                                          build + sign a 5-min one-shot pairing payload + emit URL+token
    \\                                     claim --token TOKEN                  LAB FIXTURE: simulate device side of pairing handshake
    \\                                     list                                  list root + child certs
    \\                                     revoke --id <cert_id>                 revoke a child cert by id
    \\                                     (same socket-or-embedded path as `bearer`)
    \\    llm <subcommand>                 Manage LLM adapter for natural-language → typed command (Brain 5)
    \\                                     status                               show enabled state + backend
    \\                                     enable                               enable the adapter
    \\                                     disable                              disable the adapter
    \\                                     set <key> <value>                    set backend|endpoint|model|api_key_env
    \\    provision-tenant <manifest.toml> [--operator-priv <path>] [--platform-plexus-identity-tx <hex>] [--dry-run]
    \\                                     Provision a new tenant brain from an operator-authored manifest (D-O10).
    \\                                     Validates the manifest, allocates a port, lays down /var/lib/semantos/<domain>/,
    \\                                     mints capability tokens, copies bundles, writes the per-tenant systemd unit +
    \\                                     Caddy block, runs first-boot, emits a pairing URL.  D-W2 Phase 0:
    \\                                     auto-injects [trusted_signers.platform] with the operator's pubkey before the
    \\                                     manifest is written to /etc/semantos/tenants/<domain>.toml.
    \\                                     (Future: a `semantos node provision-tenant` wrapper will be the canonical alias.)
    \\    extension <subcommand>           D-W2 Phase 1 — extension delivery operator surface.
    \\                                     publish <bundle-path> --namespace <ns> --version <v> --utxo <txid:vout:sat>
    \\                                                          [--signer <key-path>] [--arc-endpoint <url>]
    \\                                                          [--shard-proxy <host:port>] [--shard-bits <n>] [--dry-run]
    \\                                                          Construct + sign + broadcast the OP_RETURN-bearing publish tx;
    \\                                                          shell out to the TS shard-proxy helper for the bundle bytes push.
    \\    signer <subcommand>              D-W2 Phase 3 — extension key revocation + rotation.
    \\                                     revoke --signer <name> --reason <compromised|superseded|voluntary|breach>
    \\                                            [--utxo <txid:vout:sat>] [--manifest <path>] [--dry-run]
    \\                                                          Pure revocation: publishes a Plexus nullifier tx that
    \\                                                          subscribed brains apply atomically.
    \\                                     rotate --signer <name> --new-pubkey <hex> --rotation-priv <key-path>
    \\                                            [--utxo <txid:vout:sat>] [--manifest <path>] [--dry-run]
    \\                                                          Atomic revoke + promote: nullifier tx carries the
    \\                                                          replacement pubkey signed by the rotation authority.
    \\    export-operator <op_pkh_hex> --output <path> [--data-dir <path>]
    \\                                     W7.7 — write a deterministic TAR archive of an operator's LMDB
    \\                                     cells + optional Pask snapshot.  <op_pkh_hex> is 16 hex chars
    \\                                     (8 raw bytes).  Archive layout: export/cells/<sha256>, export/
    \\                                     pask_snapshot.bin (optional), export/manifest.json.
    \\    exit-operator <op_pkh_hex> [--grace-dir <path>] [--data-dir <path>]
    \\                                     [--nats-host <host>] [--nats-port <port>] [--dry-run]
    \\                                     W7.8 — operator exit sequence: export grace TAR → delete LMDB
    \\                                     cells → delete LMDB Pask snapshots → delete NATS stream
    \\                                     (best-effort).  Prints NEXT STEPS for Postgres + Caddy cleanup.
    \\                                     --dry-run exports the tarball but skips all deletions.
    \\    orphan-streams --known-pkh-list <pkh1,pkh2,...> [--nats-host <host>] [--nats-port <port>]
    \\                                     [--delete] [--dry-run]
    \\                                     W7.13 — list NATS streams in the op_<pkh16> namespace that do
    \\                                     not appear in --known-pkh-list.  --delete purges them.
    \\                                     Intended to be called nightly by the semantos-orphan-streams
    \\                                     systemd timer; the timer queries Postgres for active op_pkhs
    \\                                     and feeds them here.  --dry-run prints without deleting.
    \\    domain-allow <fqdn> [--data-dir <path>]
    \\                                     W7.14 — add a brain_domain FQDN to the Caddy on-demand TLS
    \\                                     allowlist.  Caddy's ask endpoint returns 200 for listed domains.
    \\                                     Called automatically at operator provisioning; also usable
    \\                                     manually.  File: <data-dir>/domain_allowlist.
    \\    domain-disallow <fqdn> [--data-dir <path>]
    \\                                     W7.14 — remove a domain from the allowlist.  Caddy will refuse
    \\                                     to issue or renew certs for the domain after next ask.  Called
    \\                                     automatically at operator exit.
    \\    caddy-ask [--port <port>] [--data-dir <path>]
    \\                                     W7.14 — run the Caddy on-demand TLS ask server (blocks).
    \\                                     Listens on 127.0.0.1:<port> (default 2020).  Caddy calls
    \\                                     GET /caddy/ask?domain=<fqdn>; returns 200 if domain is in
    \\                                     the allowlist, 403 otherwise.  Run as a systemd service
    \\                                     alongside `brain serve`.  Global Caddy config:
    \\                                       { on_demand_tls { ask http://127.0.0.1:2020/caddy/ask } }
    \\    sni-map <subcommand> [--data-dir <path>]
    \\                                     W7.15 — manage the SNI domain → op_pkh resolution map
    \\                                     ($data_dir/sni_domain_map.json).  Used by WSS auth (W7.4) to
    \\                                     bind operator context from the incoming Host header.
    \\                                     Subcommands:
    \\                                       set <brain_domain> <op_pkh_hex>  add/update entry
    \\                                       remove <brain_domain>             remove entry
    \\                                       show                              print all entries
    \\                                     Called automatically at provisioning (W7.9) and exit (W7.8).
    \\    wrapped-dek <subcommand> [--data-dir <path>]
    \\                                     W7.5 — manage per-operator wrapped DEK blobs
    \\                                     ($data_dir/operators/<op_pkh>/wrapped_dek).  The device
    \\                                     generates a random DEK and wraps it under a BRC-42-derived KEK;
    \\                                     the brain stores the opaque blob and returns it via
    \\                                     wallet.getWrappedDek after WSS auth.
    \\                                     Subcommands:
    \\                                       set <op_pkh_hex> <wrapped_dek_hex>  store/overwrite
    \\                                       show <op_pkh_hex>                   print current value
    \\                                       delete <op_pkh_hex>                 remove (called at exit)
    \\    resign-pending [--data-dir <path>]
    \\                                     D-DOG.1.0c Phase 4 — backfill BKDS signatures over Phase-2-era
    \\                                     unsigned cells.  Walks the four oddjobz view stores
    \\                                     (sites/customers/jobs/attachments) under <data-dir>, finds rows
    \\                                     with signedBy=null, signs each via the same hat-key BKDS the
    \\                                     graph-walk handler uses, and appends a `"signed"` event line per
    \\                                     row.  Deterministic + idempotent: a re-run is a no-op (no rows
    \\                                     re-signed; nothing reaches disk).  Stop the daemon before running
    \\                                     so the in-memory view-store indices don't fall behind the log.
    \\    site-preview [<domain_or_path>] [--data-dir <path>] [--output <path>]
    \\                                     S12 — render the operator site HTML and write it to --output
    \\                                     (or stdout if omitted).  <domain_or_path> may be a domain name
    \\                                     (looks up $data_dir/sites/<domain>/profile.json) or a direct
    \\                                     path to a profile.json file.  If omitted, uses the built-in
    \\                                     Oddjobz sample profile.
    \\    site-publish <domain> [--data-dir <path>] [--from <profile.json>]
    \\                                     S13 — write a profile.json to $data_dir/sites/<domain>/profile.json.
    \\                                     JSON is read from --from <file> or from stdin when omitted.
    \\                                     The file is validated (parse check) before writing.
    \\    help                              Print this message
    \\    version                           Print brain version
    \\
    \\Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md
    \\
;

// M1.7 — Store backend selector.  `fs` is the default (existing behaviour);
// `lmdb` routes through the LMDB vtable stack.
const StoreBackend = enum { fs, lmdb };

/// Parse `--store-backend <fs|lmdb>` from a trailing-args slice.
/// Returns `.fs` if the flag is absent or unrecognised.
fn parseStoreBackend(args: []const [:0]u8) StoreBackend {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--store-backend") and i + 1 < args.len) {
            i += 1;
            if (std.mem.eql(u8, args[i], "lmdb")) return .lmdb;
            return .fs;
        }
        // Support `--store-backend=lmdb` single-token form.
        if (std.mem.startsWith(u8, a, "--store-backend=")) {
            const val = a["--store-backend=".len..];
            if (std.mem.eql(u8, val, "lmdb")) return .lmdb;
            return .fs;
        }
    }
    return .fs;
}

/// Parse `--data-dir <path>` from a trailing-args slice.
/// Returns null if absent (caller falls back to cfg.shell.data_dir).
fn parseDataDir(args: []const [:0]u8) ?[]const u8 {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--data-dir") and i + 1 < args.len) {
            return args[i + 1];
        }
        if (std.mem.startsWith(u8, a, "--data-dir=")) {
            return a["--data-dir=".len..];
        }
    }
    return null;
}

pub fn cmdHelp(out: *const Output) !ExitCode {
    try out.print("{s}", .{HELP_TEXT});
    return .ok;
}

pub fn cmdVersion(out: *const Output) !ExitCode {
    try out.print("brain {s}\n", .{VERSION});
    return .ok;
}

pub fn cmdInit(allocator: std.mem.Allocator, out: *const Output, config_path: []const u8) !ExitCode {
    // If the file exists, refuse to clobber.
    if (std.fs.cwd().openFile(config_path, .{})) |f| {
        f.close();
        try out.print("config already exists at {s} — refusing to overwrite\n", .{config_path});
        return .config_error;
    } else |_| {}

    // Make parent dirs as needed.
    if (std.fs.path.dirname(config_path)) |parent| {
        std.fs.cwd().makePath(parent) catch |e| {
            try out.print("failed to create parent dir {s}: {s}\n", .{ parent, @errorName(e) });
            return .file_io;
        };
    }

    const tmpl = config.defaultJsonTemplate(allocator) catch return .config_error;
    defer allocator.free(tmpl);

    const file = std.fs.cwd().createFile(config_path, .{}) catch |e| {
        try out.print("failed to create config: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer file.close();
    file.writeAll(tmpl) catch |e| {
        try out.print("failed to write config: {s}\n", .{@errorName(e)});
        return .file_io;
    };

    try out.print("Wrote default config to {s}\n", .{config_path});
    try out.print("Next steps:\n", .{});
    try out.print("  1. Run `brain status` to verify the native-first config\n", .{});
    try out.print("  2. Run `brain serve --enable-repl` to start the HTTP/REPL node\n", .{});
    try out.print("  3. Optional: add hash-pinned WASM modules later when built\n", .{});
    return .ok;
}

pub fn cmdStatus(
    allocator: std.mem.Allocator,
    out: *const Output,
    config_path: []const u8,
) !ExitCode {
    var cfg = config.loadFromPath(allocator, config_path) catch |e| {
        try out.print("failed to load config from {s}: {s}\n", .{ config_path, @errorName(e) });
        return .config_error;
    };
    defer cfg.deinit();

    try out.print("brain status — config {s}\n", .{config_path});
    try out.print("  data_dir:    {s}\n", .{cfg.shell.data_dir});
    try out.print("  modules_dir: {s}\n\n", .{cfg.shell.modules_dir});

    var any_mismatch = false;
    for (cfg.modules) |m| {
        const expected = try module_loader.formatHashHex(allocator, &m.sha256);
        defer allocator.free(expected);

        // Resolve `path`: relative paths join with `modules_dir`.
        const full_path = if (std.fs.path.isAbsolute(m.path))
            try allocator.dupe(u8, m.path)
        else
            try std.fs.path.join(allocator, &.{ cfg.shell.modules_dir, m.path });
        defer allocator.free(full_path);

        const file_status: enum { matches, mismatches, missing, not_wasm } = blk: {
            const file = std.fs.cwd().openFile(full_path, .{}) catch break :blk .missing;
            defer file.close();
            const stat = file.stat() catch break :blk .missing;
            if (stat.size > module_loader.MAX_MODULE_BYTES) break :blk .missing;
            const buf = allocator.alloc(u8, stat.size) catch break :blk .missing;
            defer allocator.free(buf);
            _ = file.readAll(buf) catch break :blk .missing;
            if (!module_loader.isValidWasmShape(buf)) break :blk .not_wasm;
            const actual = module_loader.computeSha256(buf);
            break :blk if (std.mem.eql(u8, &actual, &m.sha256)) .matches else .mismatches;
        };

        const status_str = switch (file_status) {
            .matches => "✓ matches",
            .mismatches => "✗ MISMATCH",
            .missing => "✗ missing",
            .not_wasm => "✗ not WASM",
        };
        if (file_status != .matches) any_mismatch = true;

        try out.print("  module: {s}\n", .{m.name});
        try out.print("    path:     {s}\n", .{full_path});
        try out.print("    expected: {s}\n", .{expected});
        try out.print("    file:     {s}\n", .{status_str});
        try out.print("    memory:   {d} bytes\n\n", .{m.max_memory_bytes});
    }
    return if (any_mismatch) ExitCode.hash_mismatch else ExitCode.ok;
}

/// `brain hash <wasm_file>` — D-W1 Phase 2 rewire.
///
/// Reference: BRAIN-DISPATCHER-UNIFICATION.md §3 (the `modules` row),
///            §8 Phase 2.
///
/// Output is byte-identical to the pre-Phase-2 path:
///
///   • `<sha256-hex>  <path>\n` on success.
///   • `warning: <path> doesn't have WASM magic bytes\n` prefix when
///     the file isn't WASM (followed by the hash line).
///   • `failed to open ...\n` / `file too large ...\n` on the error
///     paths the dispatcher's typed errors map to.
///
/// Dispatch path: in-process dispatcher with the modules_handler
/// registered, AuthContext.in_process_root.  No Unix socket round-
/// trip — `get_hash` is a stateless read against the operator's local
/// filesystem; daemon vs no-daemon makes no difference to the result,
/// and the embedded path keeps `brain hash` working in environments
/// where the daemon isn't running yet (e.g. CI fixtures, first-boot).
pub fn cmdHash(
    allocator: std.mem.Allocator,
    out: *const Output,
    wasm_path: []const u8,
) !ExitCode {
    var audit = audit_log_mod.AuditLog.init();
    defer audit.close();
    var disp = dispatcher_mod.Dispatcher.init(allocator, &audit);
    defer disp.deinit();

    var handler = modules_handler_mod.Handler.init(allocator, null);
    try disp.register(handler.resourceHandler());

    const args = try std.fmt.allocPrint(allocator,
        \\{{"path":"{s}"}}
    , .{wasm_path});
    defer allocator.free(args);

    const ctx = dispatcher_mod.DispatchContext{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "cli-hash", .transport_label = "embedded" },
    };
    var result = disp.dispatch(&ctx, "modules", "get_hash", args) catch |err| switch (err) {
        modules_handler_mod.HandlerError.not_found => {
            try out.print("failed to open {s}: FileNotFound\n", .{wasm_path});
            return .file_io;
        },
        modules_handler_mod.HandlerError.file_too_large => {
            try out.print("file too large (cap {d})\n", .{module_loader.MAX_MODULE_BYTES});
            return .file_io;
        },
        else => {
            try out.print("failed to open {s}: {s}\n", .{ wasm_path, @errorName(err) });
            return .file_io;
        },
    };
    defer result.deinit();

    // Pull sha256 + valid_wasm_shape out of the JSON.
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, result.payload, .{}) catch {
        try out.print("hash: malformed dispatcher response\n", .{});
        return .file_io;
    };
    defer parsed.deinit();
    if (parsed.value != .object) return .file_io;
    const sha_v = parsed.value.object.get("sha256") orelse return .file_io;
    if (sha_v != .string) return .file_io;
    const valid_v = parsed.value.object.get("valid_wasm_shape") orelse return .file_io;

    const valid_shape = (valid_v == .bool) and valid_v.bool;
    if (!valid_shape) {
        try out.print("warning: {s} doesn't have WASM magic bytes\n", .{wasm_path});
    }
    try out.print("{s}  {s}\n", .{ sha_v.string, wasm_path });
    return .ok;
}

pub fn cmdStart(
    allocator: std.mem.Allocator,
    out: *const Output,
    config_path: []const u8,
    // M1.7: trailing args so --store-backend / --data-dir can be parsed.
    extra_args: []const [:0]u8,
) !ExitCode {
    const store_backend = parseStoreBackend(extra_args);
    const data_dir_override = parseDataDir(extra_args);

    var cfg = config.loadFromPath(allocator, config_path) catch |e| {
        try out.print("failed to load config: {s}\n", .{@errorName(e)});
        return .config_error;
    };
    defer cfg.deinit();

    // Effective data dir: CLI override wins, then config.
    const data_dir: []const u8 = data_dir_override orelse cfg.shell.data_dir;

    // ── Verify every configured module's hash + WASM shape ───────────
    var manager = instance_manager.InstanceManager.init(allocator);
    defer manager.deinit();

    var loaded_list = std.ArrayList(module_loader.LoadedModule){};
    defer {
        for (loaded_list.items) |*lm| lm.deinit();
        loaded_list.deinit(allocator);
    }
    // Pre-reserve so appends never relocate — the instance manager holds
    // raw pointers into this list and a relocation would invalidate them.
    try loaded_list.ensureTotalCapacityPrecise(allocator, cfg.modules.len);

    for (cfg.modules) |m| {
        const full_path = if (std.fs.path.isAbsolute(m.path))
            try allocator.dupe(u8, m.path)
        else
            try std.fs.path.join(allocator, &.{ cfg.shell.modules_dir, m.path });
        defer allocator.free(full_path);

        const lm = module_loader.loadAndVerify(allocator, m.name, full_path, &m.sha256) catch |e| {
            try out.print("module {s}: {s}\n", .{ m.name, @errorName(e) });
            return .hash_mismatch;
        };
        try loaded_list.append(allocator, lm);
        try manager.register(&loaded_list.items[loaded_list.items.len - 1]);
        try out.print("verified module: {s} ({d} bytes)\n", .{ m.name, lm.bytes.len });
    }

    // ── Brain 2 / M1.7: stand up the host-import broker ─────────────────
    // Select fs (default) or lmdb backend based on --store-backend flag.
    std.fs.cwd().makePath(data_dir) catch {};

    // ── fs backend (default, existing behaviour) ──────────────────────

    // Slot store is always fs-backed for now (no LmdbSlotStore yet).
    var slot_fs = slot_store_fs_mod.FsSlotStore.init(allocator, data_dir) catch |e| {
        try out.print("slot store init failed: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer slot_fs.deinit();

    var audit = audit_log_mod.AuditLog.init();
    defer audit.close();
    const audit_path = try std.fs.path.join(allocator, &.{ data_dir, "audit.log" });
    defer allocator.free(audit_path);
    audit.open(audit_path) catch |e| {
        try out.print("audit log open failed: {s}\n", .{@errorName(e)});
        return .file_io;
    };

    // ── Backend selection ─────────────────────────────────────────────

    // Mutable state + vtable handles — populated by the chosen backend.
    var state_fs: state_store_fs_mod.FsStateStore = undefined;
    var header_fs: header_store_fs_mod.FsHeaderStore = undefined;
    var lmdb_env: lmdb_mod.Env = undefined;
    var lmdb_header: lmdb_header_store_mod.LmdbHeaderStore = undefined;
    var lmdb_deriv: lmdb_derivation_state_mod.LmdbDerivationStateStore = undefined;

    var state_vtable: @import("derivation_state").DerivationStateStore = undefined;
    var header_vtable: @import("header_store").HeaderStore = undefined;

    var fs_backend_active = false;
    var lmdb_backend_active = false;

    if (store_backend == .lmdb) {
        // M1.9: use prod_flags (NOTLS|NOMETASYNC) — see LMDB-TUNING.md.
        lmdb_env = lmdb_mod.Env.open(data_dir, .{
            .open_flags = lmdb_config_mod.LmdbConfig.prod_flags,
            .map_size = lmdb_config_mod.LmdbConfig.default.map_size,
            .max_dbs = lmdb_config_mod.LmdbConfig.default.max_dbs,
            .mode = lmdb_config_mod.LmdbConfig.default.mode,
        }) catch |e| {
            try out.print("lmdb env open failed ({s}): {s}\n", .{ data_dir, @errorName(e) });
            return .file_io;
        };
        lmdb_header = lmdb_header_store_mod.LmdbHeaderStore.init(&lmdb_env, allocator) catch |e| {
            lmdb_env.close();
            try out.print("lmdb header store init failed: {s}\n", .{@errorName(e)});
            return .file_io;
        };
        lmdb_deriv = lmdb_derivation_state_mod.LmdbDerivationStateStore.init(&lmdb_env, allocator) catch |e| {
            lmdb_env.close();
            try out.print("lmdb derivation state store init failed: {s}\n", .{@errorName(e)});
            return .file_io;
        };
        state_vtable = lmdb_deriv.store();
        header_vtable = lmdb_header.store();
        lmdb_backend_active = true;
        try out.print("store-backend:    lmdb (data_dir={s})\n", .{data_dir});
    } else {
        state_fs = state_store_fs_mod.FsStateStore.init(allocator, data_dir) catch |e| {
            try out.print("state store init failed: {s}\n", .{@errorName(e)});
            return .file_io;
        };
        header_fs = header_store_fs_mod.FsHeaderStore.init(allocator, data_dir) catch |e| {
            state_fs.deinit();
            try out.print("header store init failed: {s}\n", .{@errorName(e)});
            return .file_io;
        };
        state_vtable = state_fs.store();
        header_vtable = header_fs.store();
        fs_backend_active = true;
        try out.print("store-backend:    fs (data_dir={s})\n", .{data_dir});
    }
    defer {
        if (lmdb_backend_active) lmdb_env.close();
        if (fs_backend_active) {
            state_fs.deinit();
            header_fs.deinit();
        }
    }

    var broker = broker_mod.Broker.init(
        allocator,
        slot_fs.store(),
        state_vtable,
        header_vtable,
        &audit,
    );

    try out.print("\nbroker:           ready (data_dir={s})\n", .{data_dir});
    try out.print("audit log:        {s}\n", .{audit_path});
    try out.print("modules loaded:   {d}\n", .{loaded_list.items.len});
    if (header_vtable.tip()) |tip| {
        try out.print("header store tip: height {d}\n", .{tip.height});
    } else {
        try out.print("header store tip: empty\n", .{});
    }

    // ── Brain 2.5 — wasmtime instantiation ──────────────────────────────
    var runner = runner_mod.Runner.init(allocator, &broker);
    defer runner.deinit();

    if (!runner.wasmtimeEnabled()) {
        try out.print("\nwasmtime:         disabled (build with -Denable-wasmtime=true)\n", .{});
        try out.print("\nAll modules verified.  Broker, stores, and audit log are wired.\n", .{});
        try out.print("Rebuild with `-Denable-wasmtime=true` to instantiate the WASM modules.\n", .{});
        return .ok;
    }

    try out.print("\nwasmtime:         enabled — instantiating modules\n", .{});
    var instances = std.ArrayList(runner_mod.Instance){};
    defer {
        for (instances.items) |*inst| inst.deinit();
        instances.deinit(allocator);
    }
    for (loaded_list.items, 0..) |*lm, i| {
        // For v0.1 the first module is the wallet engine, the second the
        // headers verifier — matches the default config order.  When the
        // config lets the operator name modules freely we'll match by
        // canonical name instead.
        const kind: broker_mod.Module = if (i == 0) .wallet_engine else .headers_verifier;
        const inst = runner.instantiate(lm, kind) catch |e| {
            try out.print("  ✗ {s}: instantiate failed ({s})\n", .{ lm.name, @errorName(e) });
            return .config_error;
        };
        try instances.append(allocator, inst);
        try out.print("  ✓ instantiated {s} as {s}\n", .{ lm.name, @tagName(kind) });
    }
    try out.print("\nAll modules instantiated.  REPL surface lands in Brain 3.\n", .{});
    return .ok;
}

pub fn cmdStop(out: *const Output) !ExitCode {
    try out.print("brain stop: no running daemon to stop (Brain 2 will track a PID file).\n", .{});
    return .ok;
}

```
