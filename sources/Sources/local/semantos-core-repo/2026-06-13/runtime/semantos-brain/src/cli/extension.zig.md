---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cli/extension.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.284709+00:00
---

# runtime/semantos-brain/src/cli/extension.zig

```zig
// Extension/signer/quarantine verbs (D-W2 Phases 1 + 3) extracted
// from src/cli.zig as Move 8 of the cli-modularize refactor.
// Pure code motion: no behaviour change.

const std = @import("std");
const cli_common = @import("common.zig");
const cli_device = @import("device.zig");
const extension_nullifier_mod = @import("extension_nullifier");
const extension_publish_mod = @import("extension_publish");
const extension_quarantine_mod = @import("extension_quarantine");
const tenant_manifest_mod = @import("tenant_manifest");
const bkds_mod = @import("bkds");
const bsvz_mod = @import("bsvz");

const Output = cli_common.Output;
const ExitCode = cli_common.ExitCode;
const resolveDataDir = cli_common.resolveDataDir;
const readOperatorPriv = cli_device.readOperatorPriv;

pub fn cmdExtension(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 1) {
        try printExtensionUsage(out);
        return .bad_args;
    }
    const sub = args[0];
    if (std.mem.eql(u8, sub, "publish")) return cmdExtensionPublish(allocator, out, args[1..]);
    if (std.mem.eql(u8, sub, "quarantine")) return cmdExtensionQuarantine(allocator, out, args[1..]);
    try out.print("extension: unknown subcommand `{s}`\n", .{sub});
    try printExtensionUsage(out);
    return .bad_args;
}

fn printExtensionUsage(out: *const Output) !void {
    try out.print(
        \\usage: brain extension <subcommand>
        \\
        \\subcommands:
        \\  publish <bundle-path> --namespace <ns> --version <v> --utxo <txid:vout:sat>
        \\                       [--signer <key-path>] [--arc-endpoint <url>]
        \\                       [--shard-proxy <host:port>] [--shard-bits <n>]
        \\                       [--change-address <addr>] [--dry-run]
        \\
        \\  quarantine list                     list current quarantine state per extension
        \\  quarantine evaluate <namespace>     re-evaluate quarantined extension post-rotation
        \\  quarantine remove <namespace>       hard-remove a quarantined extension
        \\
        \\
    , .{});
}

/// `brain extension publish` — D-W2 Phase 1.
///
/// Flow (per spec §5.1):
///   1. Validate args.  Load signer priv (default `<data_dir>/operator-
///      root-priv.hex`).
///   2. Compute bundle_hash.
///   3. Construct + sign the OP_RETURN-bearing publish tx.
///   4. Broadcast via ARC (skipped under --dry-run).
///   5. Derive shard_group_id; shell out to `bun cartridges/oddjobz/brain/
///      tools/publish-bundle.ts` with (bundle, txid, signer-pubkey,
///      shard-group-id) for the bundle-bytes push.
///   6. Final summary: `Published <ns>@<ver> — txid=<...>
///      shardGroupId=<...>`.
fn cmdExtensionPublish(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 1 or std.mem.startsWith(u8, args[0], "--")) {
        try printExtensionUsage(out);
        return .bad_args;
    }
    const bundle_path: []const u8 = args[0];

    var namespace: []const u8 = "";
    var version_str: []const u8 = "";
    var utxo_str: []const u8 = "";
    var signer_path: []const u8 = "";
    var arc_endpoint: []const u8 = extension_publish_mod.DEFAULT_ARC_URL;
    var shard_proxy: []const u8 = "localhost:9000";
    var shard_bits_str: []const u8 = "8";
    var change_address: []const u8 = "";
    var dry_run = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--namespace") and i + 1 < args.len) {
            namespace = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--version") and i + 1 < args.len) {
            version_str = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--utxo") and i + 1 < args.len) {
            utxo_str = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--signer") and i + 1 < args.len) {
            signer_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--arc-endpoint") and i + 1 < args.len) {
            arc_endpoint = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--shard-proxy") and i + 1 < args.len) {
            shard_proxy = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--shard-bits") and i + 1 < args.len) {
            shard_bits_str = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--change-address") and i + 1 < args.len) {
            change_address = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, a, "--dry-run")) {
            dry_run = true;
        } else {
            try out.print("extension publish: unknown arg `{s}`\n", .{a});
            return .bad_args;
        }
    }

    if (namespace.len == 0) {
        try out.print("extension publish: --namespace is required\n", .{});
        return .bad_args;
    }
    if (version_str.len == 0) {
        try out.print("extension publish: --version is required\n", .{});
        return .bad_args;
    }
    if (!validVersion(version_str)) {
        try out.print("extension publish: --version `{s}` is not a valid semver-shaped version (digits + dots, optional pre-release like `0.1.0-rc1`)\n", .{version_str});
        return .bad_args;
    }
    if (utxo_str.len == 0 and !dry_run) {
        try out.print("extension publish: --utxo <txid:vout:sat> is required (or pass --dry-run)\n", .{});
        return .bad_args;
    }

    // 2. Compute bundle hash.
    const bundle_hash = extension_publish_mod.computeBundleHash(allocator, bundle_path) catch |e| switch (e) {
        error.bundle_open_failed => {
            try out.print("extension publish: failed to open bundle `{s}`\n", .{bundle_path});
            return .file_io;
        },
        else => {
            try out.print("extension publish: bundle hash error: {s}\n", .{@errorName(e)});
            return .file_io;
        },
    };

    {
        var hex_buf: [64]u8 = undefined;
        extension_publish_mod.hexEncode(&bundle_hash, &hex_buf);
        try out.print("[publish] bundle_hash: {s}\n", .{hex_buf});
    }

    // 1. Load signer priv.
    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);
    const default_priv_path = try std.fs.path.join(allocator, &.{ data_dir, "operator-root-priv.hex" });
    defer allocator.free(default_priv_path);
    const priv_path = if (signer_path.len > 0) signer_path else default_priv_path;

    const signer_priv = readOperatorPriv(allocator, priv_path) catch |e| {
        try out.print("extension publish: failed to read signer priv at {s}: {s}\n", .{ priv_path, @errorName(e) });
        return .file_io;
    };

    if (dry_run) {
        try out.print("[publish] --dry-run: skipping tx construction + ARC broadcast + shard-proxy push\n", .{});
        try out.print("[publish] --dry-run: would invoke `bun cartridges/oddjobz/brain/tools/publish-bundle.ts`\n", .{});
        try out.print("Published {s}@{s} — DRY-RUN (no chain side effects)\n", .{ namespace, version_str });
        return .ok;
    }

    // 3. Parse UTXO.  Format: `<txid_hex>:<vout>:<satoshis>`.
    const utxo = parseUtxoArg(utxo_str) catch |e| {
        try out.print("extension publish: bad --utxo value `{s}`: {s}\n", .{ utxo_str, @errorName(e) });
        return .bad_args;
    };

    // Funding UTXO's locking script: in v0.1 we don't have a wallet
    // selector — the operator runs `brain extension publish` against a
    // single P2PKH UTXO they explicitly chose with `--utxo`.  We
    // reconstruct the UTXO's locking_script from the signer's pubkey
    // (P2PKH-to-self funding).  This is the simplest v0.1 shape; a
    // future PR adds wallet-side derivation-tracked selection.
    const locking_script = derivePub2PkhScript(signer_priv) catch {
        try out.print("extension publish: failed to derive P2PKH locking script from signer priv\n", .{});
        return .config_error;
    };

    // Derive change address — default = signer's own P2PKH address.
    const default_change = deriveChangeAddress(allocator, signer_priv) catch |e| {
        try out.print("extension publish: failed to derive change address from signer priv: {s}\n", .{@errorName(e)});
        return .config_error;
    };
    defer allocator.free(default_change);
    const change_addr_text = if (change_address.len > 0) change_address else default_change;

    const manifest = extension_publish_mod.BundleManifest{
        .extension_name = namespace,
        .version = version_str,
        .bundle_path = bundle_path,
        .signer_priv = signer_priv,
    };
    const built = extension_publish_mod.buildPublishTx(
        allocator,
        manifest,
        bundle_hash,
        .{
            .txid = utxo.txid,
            .vout = utxo.vout,
            .locking_script = &locking_script,
            .satoshis = utxo.satoshis,
        },
        change_addr_text,
        50,
    ) catch |e| {
        try out.print("extension publish: tx build failed: {s}\n", .{@errorName(e)});
        return switch (e) {
            error.bsvz_unavailable => .config_error,
            error.bad_priv_key, error.bad_change_address, error.bad_locking_script => .config_error,
            error.insufficient_funds => .config_error,
            else => .file_io,
        };
    };
    defer extension_publish_mod.freeBuiltTx(allocator, built);

    var txid_hex: [64]u8 = undefined;
    extension_publish_mod.hexEncode(&built.txid, &txid_hex);
    try out.print("[publish] tx built: txid={s} change_sats={d} fee_sats={d}\n", .{ txid_hex, built.change_satoshis, built.fee_satoshis });

    // 4. Broadcast.
    const outcome = extension_publish_mod.broadcastViaArc(allocator, built.tx_bytes, arc_endpoint, null) catch |e| {
        try out.print("extension publish: ARC broadcast failed: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer extension_publish_mod.freeBroadcastOutcome(allocator, outcome);
    if (!outcome.ok) {
        try out.print("[publish] tx broadcast: REJECTED (detail={s})\n", .{outcome.detail});
        return .file_io;
    }
    try out.print("[publish] tx broadcast: {s}\n", .{outcome.detail});

    // 5. Shell out to the TS shard-proxy publisher.
    const shard_group = extension_publish_mod.deriveShardGroupId(built.txid);
    var sg_hex: [64]u8 = undefined;
    extension_publish_mod.hexEncode(&shard_group, &sg_hex);

    invokeTsShardPublish(allocator, out, .{
        .bundle_path = bundle_path,
        .txid_hex = &txid_hex,
        .shard_group_hex = &sg_hex,
        .shard_proxy = shard_proxy,
        .shard_bits = shard_bits_str,
        .namespace = namespace,
        .version = version_str,
    }) catch |e| {
        try out.print("[publish] WARN: TS shard-proxy push failed: {s}\n", .{@errorName(e)});
        try out.print("[publish] tx is on-chain; subscribers will see the publish but bundle bytes weren't pushed.\n", .{});
        return .file_io;
    };
    try out.print("[publish] bundle published to shard group {s}\n", .{sg_hex});

    try out.print("Published {s}@{s} — txid={s} shardGroupId={s}\n", .{ namespace, version_str, txid_hex, sg_hex });
    return .ok;
}

const ParsedUtxo = struct {
    txid: [32]u8,
    vout: u32,
    satoshis: u64,
};

/// Parse `<txid_hex>:<vout>:<satoshis>` (txid in display order).
fn parseUtxoArg(arg: []const u8) !ParsedUtxo {
    var first_colon: ?usize = null;
    var second_colon: ?usize = null;
    var i: usize = 0;
    while (i < arg.len) : (i += 1) {
        if (arg[i] == ':') {
            if (first_colon == null) {
                first_colon = i;
            } else if (second_colon == null) {
                second_colon = i;
                break;
            }
        }
    }
    if (first_colon == null or second_colon == null) return error.bad_utxo_format;
    const txid_hex = arg[0..first_colon.?];
    if (txid_hex.len != 64) return error.bad_utxo_format;
    const vout_str = arg[first_colon.? + 1 .. second_colon.?];
    const sats_str = arg[second_colon.? + 1 ..];
    var txid: [32]u8 = undefined;
    var k: usize = 0;
    while (k < 32) : (k += 1) {
        const hi = parseHexNibble(txid_hex[k * 2]) catch return error.bad_utxo_format;
        const lo = parseHexNibble(txid_hex[k * 2 + 1]) catch return error.bad_utxo_format;
        txid[k] = (hi << 4) | lo;
    }
    const vout = std.fmt.parseInt(u32, vout_str, 10) catch return error.bad_utxo_format;
    const satoshis = std.fmt.parseInt(u64, sats_str, 10) catch return error.bad_utxo_format;
    return .{ .txid = txid, .vout = vout, .satoshis = satoshis };
}

fn parseHexNibble(c: u8) !u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => 10 + (c - 'a'),
        'A'...'F' => 10 + (c - 'A'),
        else => error.bad_hex,
    };
}

/// Validate a v0.1 version string: non-empty; ASCII; only digits, dots,
/// hyphens, and ASCII letters; no leading/trailing dot.  Tests pin this.
fn validVersion(s: []const u8) bool {
    if (s.len == 0 or s.len > 32) return false;
    if (s[0] == '.' or s[s.len - 1] == '.') return false;
    for (s) |c| {
        const ok = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '.' or c == '-' or c == '+';
        if (!ok) return false;
    }
    return true;
}

/// Derive a P2PKH locking script from the operator's signing priv.  Used
/// in v0.1 where the funding UTXO is assumed to be P2PKH-to-self (the
/// operator's own UTXO they're spending to fund the publish).
fn derivePub2PkhScript(priv: [32]u8) ![25]u8 {
    const bsvz_dep = @import("bsvz");
    const sk = try bsvz_dep.crypto.PrivateKey.fromBytes(priv);
    const pk = try sk.publicKey();
    const h160 = bsvz_dep.crypto.hash.hash160(&pk.bytes);
    var ls: [25]u8 = undefined;
    ls[0] = 0x76;
    ls[1] = 0xa9;
    ls[2] = 0x14;
    @memcpy(ls[3..23], &h160.bytes);
    ls[23] = 0x88;
    ls[24] = 0xac;
    return ls;
}

fn deriveChangeAddress(allocator: std.mem.Allocator, priv: [32]u8) ![]u8 {
    const bsvz_dep = @import("bsvz");
    const sk = try bsvz_dep.crypto.PrivateKey.fromBytes(priv);
    const pk = try sk.publicKey();
    return bsvz_dep.compat.address.encodeP2pkhFromPublicKey(allocator, .mainnet, pk);
}

const TsPublishArgs = struct {
    bundle_path: []const u8,
    txid_hex: *const [64]u8,
    shard_group_hex: *const [64]u8,
    shard_proxy: []const u8,
    shard_bits: []const u8,
    namespace: []const u8,
    version: []const u8,
};

/// Shell out to the TS shard-proxy publisher.
///
/// Cross-language seam, documented in the operator runbook:
///   `bun cartridges/oddjobz/brain/tools/publish-bundle.ts \
///       --bundle <path> --txid <hex> --shard-group <hex> \
///       --shard-proxy <host:port> --shard-bits <n> \
///       --namespace <ns> --version <v>`
///
/// We use absolute paths derived from the cwd of the Semantos Brain process — the
/// operator runs the verb from the repo root.  Production deployments
/// will carry the helper alongside the Semantos Brain binary; the runbook walks
/// the operator through the cross-language artifact layout.
fn invokeTsShardPublish(allocator: std.mem.Allocator, out: *const Output, args: TsPublishArgs) !void {
    var argv = std.ArrayList([]const u8){};
    defer argv.deinit(allocator);
    try argv.append(allocator, "bun");
    try argv.append(allocator, "cartridges/oddjobz/brain/tools/publish-bundle.ts");
    try argv.append(allocator, "--bundle");
    try argv.append(allocator, args.bundle_path);
    try argv.append(allocator, "--txid");
    try argv.append(allocator, args.txid_hex);
    try argv.append(allocator, "--shard-group");
    try argv.append(allocator, args.shard_group_hex);
    try argv.append(allocator, "--shard-proxy");
    try argv.append(allocator, args.shard_proxy);
    try argv.append(allocator, "--shard-bits");
    try argv.append(allocator, args.shard_bits);
    try argv.append(allocator, "--namespace");
    try argv.append(allocator, args.namespace);
    try argv.append(allocator, "--version");
    try argv.append(allocator, args.version);

    try out.print("[publish] invoking: bun cartridges/oddjobz/brain/tools/publish-bundle.ts ...\n", .{});

    var child = std.process.Child.init(argv.items, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;
    const term = try child.spawnAndWait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.ts_helper_failed,
        else => return error.ts_helper_failed,
    }
}

// ─────────────────────────────────────────────────────────────────────
// D-W2 Phase 3 — `brain signer <subcommand>`
//
// Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md
//   §4.2 (Nullifier Publication), §4.3 (Rotation Authority), §7
//   Phase 3.
//
// Two verbs:
//   • revoke   — pure revocation (no replacement key).  Used when a
//                key is permanently retired.
//   • rotate   — atomic revoke + promote.  Used for planned key
//                rotation OR known-compromised-but-recoverable.
//
// Both verbs construct + sign + broadcast a Plexus nullifier tx
// whose OP_RETURN payload commits the spec layout from §4.2-§4.3.
// `rotate` additionally signs the (revoked || replacement || ts)
// preimage with the rotation-authority key, which the receive
// pipeline verifies against the signer's `recovery_enrolment_id`.
//
// The TS shard-proxy push is shared with Phase 1 — same
// `cartridges/oddjobz/brain/tools/publish-bundle.ts` helper, with a new
// `--frame-kind nullifier` flag (carried in the helper's argv when
// we shell out).  Subscribers receive the nullifier frame on the
// signer's shard group + run the receive pipeline's nullifier
// branch.
// ─────────────────────────────────────────────────────────────────────

pub fn cmdSigner(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 1) {
        try printSignerUsage(out);
        return .bad_args;
    }
    const sub = args[0];
    if (std.mem.eql(u8, sub, "revoke")) return cmdSignerRevoke(allocator, out, args[1..]);
    if (std.mem.eql(u8, sub, "rotate")) return cmdSignerRotate(allocator, out, args[1..]);
    try out.print("signer: unknown subcommand `{s}`\n", .{sub});
    try printSignerUsage(out);
    return .bad_args;
}

fn printSignerUsage(out: *const Output) !void {
    try out.print(
        \\usage: brain signer <subcommand>
        \\
        \\subcommands:
        \\  revoke --signer <name> --reason <compromised|superseded|voluntary|breach>
        \\         [--utxo <txid:vout:sat>] [--signer-priv <path>] [--manifest <path>]
        \\         [--arc-endpoint <url>] [--dry-run]
        \\
        \\  rotate --signer <name> --new-pubkey <hex>
        \\         --rotation-priv <path>
        \\         [--utxo <txid:vout:sat>] [--signer-priv <path>] [--manifest <path>]
        \\         [--arc-endpoint <url>] [--dry-run]
        \\
        \\Both verbs build + sign a Plexus nullifier tx; subscribed
        \\brains apply the revocation (and, for rotate, promote the
        \\replacement key) on receive.
        \\
        \\
    , .{});
}

const SignerVerbCommon = struct {
    signer_name: []const u8 = "",
    utxo_str: []const u8 = "",
    signer_priv_path: []const u8 = "",
    manifest_path: []const u8 = "",
    arc_endpoint: []const u8 = extension_publish_mod.DEFAULT_ARC_URL,
    change_address: []const u8 = "",
    dry_run: bool = false,
};

fn parseSignerCommonArg(
    common: *SignerVerbCommon,
    arg: []const u8,
    next: ?[]const u8,
) !bool {
    if (std.mem.eql(u8, arg, "--signer") and next != null) {
        common.signer_name = next.?;
        return true;
    }
    if (std.mem.eql(u8, arg, "--utxo") and next != null) {
        common.utxo_str = next.?;
        return true;
    }
    if (std.mem.eql(u8, arg, "--signer-priv") and next != null) {
        common.signer_priv_path = next.?;
        return true;
    }
    if (std.mem.eql(u8, arg, "--manifest") and next != null) {
        common.manifest_path = next.?;
        return true;
    }
    if (std.mem.eql(u8, arg, "--arc-endpoint") and next != null) {
        common.arc_endpoint = next.?;
        return true;
    }
    if (std.mem.eql(u8, arg, "--change-address") and next != null) {
        common.change_address = next.?;
        return true;
    }
    if (std.mem.eql(u8, arg, "--dry-run")) {
        common.dry_run = true;
        return true;
    }
    return false;
}

/// Look up the signer's pubkey in the manifest at `manifest_path`.
/// Returns error.signer_not_found when absent.
fn loadSignerPubkeyFromManifest(
    allocator: std.mem.Allocator,
    manifest_path: []const u8,
    signer_name: []const u8,
) ![extension_nullifier_mod.PUBKEY_LEN]u8 {
    var m = try tenant_manifest_mod.loadFromPath(allocator, manifest_path);
    defer m.deinit();
    for (m.trusted_signers) |s| {
        if (std.mem.eql(u8, s.name, signer_name)) {
            return parseHexPubkey33(s.pubkey_hex);
        }
    }
    return error.signer_not_found;
}

fn parseHexPubkey33(hex: []const u8) ![extension_nullifier_mod.PUBKEY_LEN]u8 {
    if (hex.len != extension_nullifier_mod.PUBKEY_LEN * 2) return error.bad_pubkey_hex;
    var out: [extension_nullifier_mod.PUBKEY_LEN]u8 = undefined;
    var i: usize = 0;
    while (i < extension_nullifier_mod.PUBKEY_LEN) : (i += 1) {
        const hi = try parseHexNibble(hex[i * 2]);
        const lo = try parseHexNibble(hex[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
    }
    return out;
}

fn parsePrivKeyHexFile(allocator: std.mem.Allocator, path: []const u8) ![32]u8 {
    return readOperatorPriv(allocator, path);
}

fn currentTimestamp() u64 {
    return @intCast(std.time.timestamp());
}

/// `brain signer revoke` — D-W2 Phase 3.
fn cmdSignerRevoke(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    var common = SignerVerbCommon{};
    var reason_str: []const u8 = "";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        const next: ?[]const u8 = if (i + 1 < args.len) args[i + 1] else null;
        if (try parseSignerCommonArg(&common, a, next)) {
            // Did this arg consume a follower?
            if (next != null and !std.mem.eql(u8, a, "--dry-run")) i += 1;
            continue;
        }
        if (std.mem.eql(u8, a, "--reason") and next != null) {
            reason_str = next.?;
            i += 1;
            continue;
        }
        try out.print("signer revoke: unknown arg `{s}`\n", .{a});
        return .bad_args;
    }

    if (common.signer_name.len == 0) {
        try out.print("signer revoke: --signer is required\n", .{});
        return .bad_args;
    }
    if (reason_str.len == 0) {
        try out.print("signer revoke: --reason is required (one of: compromised, superseded, voluntary, breach)\n", .{});
        return .bad_args;
    }
    const reason = extension_nullifier_mod.parseReasonCode(reason_str) orelse {
        try out.print("signer revoke: invalid --reason `{s}` (one of: compromised, superseded, voluntary, breach)\n", .{reason_str});
        return .bad_args;
    };

    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);

    // Resolve manifest path: either explicit, or default at <data_dir>/tenant.toml.
    const default_manifest = try std.fs.path.join(allocator, &.{ data_dir, "tenant.toml" });
    defer allocator.free(default_manifest);
    const manifest_path = if (common.manifest_path.len > 0) common.manifest_path else default_manifest;

    const revoked_pubkey = loadSignerPubkeyFromManifest(allocator, manifest_path, common.signer_name) catch |e| {
        try out.print("signer revoke: failed to load signer `{s}` from manifest at {s}: {s}\n", .{ common.signer_name, manifest_path, @errorName(e) });
        return .config_error;
    };

    {
        var hex_buf: [66]u8 = undefined;
        extension_publish_mod.hexEncode(&revoked_pubkey, &hex_buf);
        try out.print("[revoke] target signer={s} pubkey={s} reason={s}\n", .{ common.signer_name, hex_buf, reason.name() });
    }

    const payload = extension_nullifier_mod.NullifierPayload{
        .revoked_pubkey = revoked_pubkey,
        .reason_code = reason,
        .timestamp = currentTimestamp(),
    };

    if (common.dry_run) {
        const bytes = extension_nullifier_mod.encodeNullifierPayload(allocator, payload) catch |e| {
            try out.print("signer revoke: encode failed: {s}\n", .{@errorName(e)});
            return .config_error;
        };
        defer allocator.free(bytes);
        const hex_payload = try allocator.alloc(u8, bytes.len * 2);
        defer allocator.free(hex_payload);
        extension_publish_mod.hexEncode(bytes, hex_payload);
        try out.print("[revoke] --dry-run: payload_len={d} payload_hex={s}\n", .{ bytes.len, hex_payload });
        try out.print("Revoked {s} — DRY-RUN (no chain side effects)\n", .{common.signer_name});
        return .ok;
    }

    if (common.utxo_str.len == 0) {
        try out.print("signer revoke: --utxo <txid:vout:sat> is required (or pass --dry-run)\n", .{});
        return .bad_args;
    }

    return signerBroadcastNullifier(allocator, out, .{
        .common = common,
        .data_dir = data_dir,
        .payload = payload,
        .signer_name = common.signer_name,
        .verb = "revoke",
    });
}

/// `brain signer rotate` — D-W2 Phase 3.
fn cmdSignerRotate(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    var common = SignerVerbCommon{};
    var new_pubkey_hex: []const u8 = "";
    var rotation_priv_path: []const u8 = "";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        const next: ?[]const u8 = if (i + 1 < args.len) args[i + 1] else null;
        if (try parseSignerCommonArg(&common, a, next)) {
            if (next != null and !std.mem.eql(u8, a, "--dry-run")) i += 1;
            continue;
        }
        if (std.mem.eql(u8, a, "--new-pubkey") and next != null) {
            new_pubkey_hex = next.?;
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, a, "--rotation-priv") and next != null) {
            rotation_priv_path = next.?;
            i += 1;
            continue;
        }
        try out.print("signer rotate: unknown arg `{s}`\n", .{a});
        return .bad_args;
    }

    if (common.signer_name.len == 0) {
        try out.print("signer rotate: --signer is required\n", .{});
        return .bad_args;
    }
    if (new_pubkey_hex.len == 0) {
        try out.print("signer rotate: --new-pubkey is required (66-char hex compressed-SEC1)\n", .{});
        return .bad_args;
    }
    if (rotation_priv_path.len == 0) {
        try out.print("signer rotate: --rotation-priv is required (path to the rotation-authority priv-key hex file)\n", .{});
        return .bad_args;
    }

    const replacement_pubkey = parseHexPubkey33(new_pubkey_hex) catch {
        try out.print("signer rotate: --new-pubkey must be 66 hex chars (compressed-SEC1)\n", .{});
        return .bad_args;
    };

    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);

    const default_manifest = try std.fs.path.join(allocator, &.{ data_dir, "tenant.toml" });
    defer allocator.free(default_manifest);
    const manifest_path = if (common.manifest_path.len > 0) common.manifest_path else default_manifest;

    const revoked_pubkey = loadSignerPubkeyFromManifest(allocator, manifest_path, common.signer_name) catch |e| {
        try out.print("signer rotate: failed to load signer `{s}` from manifest at {s}: {s}\n", .{ common.signer_name, manifest_path, @errorName(e) });
        return .config_error;
    };

    const rotation_priv = parsePrivKeyHexFile(allocator, rotation_priv_path) catch |e| {
        try out.print("signer rotate: failed to read rotation-authority priv at {s}: {s}\n", .{ rotation_priv_path, @errorName(e) });
        return .file_io;
    };

    const ts = currentTimestamp();
    const sig = extension_nullifier_mod.signRotationAuthority(rotation_priv, revoked_pubkey, replacement_pubkey, ts) catch |e| {
        try out.print("signer rotate: rotation-authority sign failed: {s}\n", .{@errorName(e)});
        return .config_error;
    };

    const payload = extension_nullifier_mod.NullifierPayload{
        .revoked_pubkey = revoked_pubkey,
        .reason_code = .superseded,
        .timestamp = ts,
        .replacement_pubkey = replacement_pubkey,
        .rotation_authority_signature = sig,
    };

    {
        var revoked_hex: [66]u8 = undefined;
        var replacement_hex: [66]u8 = undefined;
        extension_publish_mod.hexEncode(&revoked_pubkey, &revoked_hex);
        extension_publish_mod.hexEncode(&replacement_pubkey, &replacement_hex);
        try out.print("[rotate] target signer={s} revoked={s} replacement={s} ts={d}\n", .{ common.signer_name, revoked_hex, replacement_hex, ts });
    }

    if (common.dry_run) {
        const bytes = extension_nullifier_mod.encodeNullifierPayload(allocator, payload) catch |e| {
            try out.print("signer rotate: encode failed: {s}\n", .{@errorName(e)});
            return .config_error;
        };
        defer allocator.free(bytes);
        const hex_payload = try allocator.alloc(u8, bytes.len * 2);
        defer allocator.free(hex_payload);
        extension_publish_mod.hexEncode(bytes, hex_payload);
        try out.print("[rotate] --dry-run: payload_len={d} payload_hex={s}\n", .{ bytes.len, hex_payload });
        try out.print("Rotated {s} — DRY-RUN (no chain side effects)\n", .{common.signer_name});
        return .ok;
    }

    if (common.utxo_str.len == 0) {
        try out.print("signer rotate: --utxo <txid:vout:sat> is required (or pass --dry-run)\n", .{});
        return .bad_args;
    }

    return signerBroadcastNullifier(allocator, out, .{
        .common = common,
        .data_dir = data_dir,
        .payload = payload,
        .signer_name = common.signer_name,
        .verb = "rotate",
    });
}

const SignerBroadcastArgs = struct {
    common: SignerVerbCommon,
    data_dir: []const u8,
    payload: extension_nullifier_mod.NullifierPayload,
    signer_name: []const u8,
    verb: []const u8,
};

fn signerBroadcastNullifier(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: SignerBroadcastArgs,
) !ExitCode {
    const common = args.common;

    // Load signer priv (default = operator-root-priv.hex).
    const default_priv_path = try std.fs.path.join(allocator, &.{ args.data_dir, "operator-root-priv.hex" });
    defer allocator.free(default_priv_path);
    const priv_path = if (common.signer_priv_path.len > 0) common.signer_priv_path else default_priv_path;
    const signer_priv = readOperatorPriv(allocator, priv_path) catch |e| {
        try out.print("signer {s}: failed to read funding-signer priv at {s}: {s}\n", .{ args.verb, priv_path, @errorName(e) });
        return .file_io;
    };

    // Parse UTXO.
    const utxo = parseUtxoArg(common.utxo_str) catch |e| {
        try out.print("signer {s}: bad --utxo value `{s}`: {s}\n", .{ args.verb, common.utxo_str, @errorName(e) });
        return .bad_args;
    };

    const locking_script = derivePub2PkhScript(signer_priv) catch {
        try out.print("signer {s}: failed to derive P2PKH locking script from signer priv\n", .{args.verb});
        return .config_error;
    };

    const default_change = deriveChangeAddress(allocator, signer_priv) catch |e| {
        try out.print("signer {s}: failed to derive change address: {s}\n", .{ args.verb, @errorName(e) });
        return .config_error;
    };
    defer allocator.free(default_change);
    const change_addr_text = if (common.change_address.len > 0) common.change_address else default_change;

    const built = extension_nullifier_mod.buildNullifierTx(
        allocator,
        args.payload,
        signer_priv,
        .{
            .txid = utxo.txid,
            .vout = utxo.vout,
            .locking_script = &locking_script,
            .satoshis = utxo.satoshis,
        },
        change_addr_text,
        50,
    ) catch |e| {
        try out.print("signer {s}: tx build failed: {s}\n", .{ args.verb, @errorName(e) });
        return switch (e) {
            error.bsvz_unavailable, error.bad_priv_key, error.bad_change_address, error.bad_locking_script, error.insufficient_funds => .config_error,
            else => .file_io,
        };
    };
    defer extension_nullifier_mod.freeBuiltTx(allocator, built);

    var txid_hex: [64]u8 = undefined;
    extension_publish_mod.hexEncode(&built.txid, &txid_hex);
    try out.print("[{s}] tx built: txid={s} change_sats={d} fee_sats={d}\n", .{ args.verb, txid_hex, built.change_satoshis, built.fee_satoshis });

    const outcome = extension_nullifier_mod.broadcastViaArc(allocator, built.tx_bytes, common.arc_endpoint, null) catch |e| {
        try out.print("signer {s}: ARC broadcast failed: {s}\n", .{ args.verb, @errorName(e) });
        return .file_io;
    };
    defer extension_nullifier_mod.freeBroadcastOutcome(allocator, outcome);
    if (!outcome.ok) {
        try out.print("[{s}] tx broadcast: REJECTED (detail={s})\n", .{ args.verb, outcome.detail });
        return .file_io;
    }
    try out.print("[{s}] tx broadcast: {s}\n", .{ args.verb, outcome.detail });

    if (std.mem.eql(u8, args.verb, "revoke")) {
        try out.print("Revoked {s} — txid={s}\n", .{ args.signer_name, txid_hex });
    } else {
        try out.print("Rotated {s} — txid={s}\n", .{ args.signer_name, txid_hex });
    }
    return .ok;
}

// ─────────────────────────────────────────────────────────────────────
// D-W2 Phase 4 — `brain extension quarantine <list|evaluate|remove>`
//
// Reference: docs/design/BRAIN-EXTENSION-DELIVERY-AND-REVOCATION.md
// §7 Phase 4 + docs/operator-runbooks/extension-quarantine.md.
//
// Operator surface for the quarantine state machine.  All three
// verbs are read-mostly + side-effects-on-disk; no chain
// interaction (the chain side runs through `brain signer revoke`).
// ─────────────────────────────────────────────────────────────────────

fn cmdExtensionQuarantine(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 1) {
        try printExtensionUsage(out);
        return .bad_args;
    }
    const sub = args[0];
    if (std.mem.eql(u8, sub, "list")) return cmdExtensionQuarantineList(allocator, out, args[1..]);
    if (std.mem.eql(u8, sub, "evaluate")) return cmdExtensionQuarantineEvaluate(allocator, out, args[1..]);
    if (std.mem.eql(u8, sub, "remove")) return cmdExtensionQuarantineRemove(allocator, out, args[1..]);
    try out.print("extension quarantine: unknown subcommand `{s}`\n", .{sub});
    try printExtensionUsage(out);
    return .bad_args;
}

/// `brain extension quarantine list` — print the latest record per
/// extension in the quarantine index.  Empty output when the index
/// is empty/missing (the brain has no quarantine history).
fn cmdExtensionQuarantineList(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    _ = args;
    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);

    const records = extension_quarantine_mod.loadLatestRecords(allocator, data_dir) catch |err| {
        try out.print("extension quarantine list: failed to read index: {s}\n", .{@errorName(err)});
        return .file_io;
    };
    defer extension_quarantine_mod.freeRecords(allocator, records);

    if (records.len == 0) {
        try out.print("(no quarantine records — nothing has been quarantined on this brain)\n", .{});
        return .ok;
    }

    try out.print("EXTENSION                            VERSION       STATE          REASON                          PUBKEY-PREFIX  AT\n", .{});
    for (records) |r| {
        const pk_prefix = if (r.signer_pubkey_hex.len >= 12) r.signer_pubkey_hex[0..12] else r.signer_pubkey_hex;
        try out.print("{s:<36} {s:<13} {s:<14} {s:<31} {s:<14} {d}\n", .{
            r.extension_name,
            r.version,
            r.state.name(),
            r.reason.name(),
            pk_prefix,
            r.quarantined_at,
        });
    }
    return .ok;
}

/// `brain extension quarantine evaluate <namespace>` — runs
/// `evaluateQuarantine` for the named extension.  Loads the current
/// manifest from `<data_dir>/tenant.toml` (or --manifest if supplied)
/// and consults its `[trusted_signers]` list.
fn cmdExtensionQuarantineEvaluate(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    if (args.len < 1) {
        try out.print("usage: brain extension quarantine evaluate <namespace> [--manifest <path>]\n", .{});
        return .bad_args;
    }
    const namespace = args[0];
    var manifest_path_arg: []const u8 = "";
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--manifest") and i + 1 < args.len) {
            manifest_path_arg = args[i + 1];
            i += 1;
        } else {
            try out.print("extension quarantine evaluate: unknown arg `{s}`\n", .{args[i]});
            return .bad_args;
        }
    }

    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);
    const default_manifest = try std.fs.path.join(allocator, &.{ data_dir, "tenant.toml" });
    defer allocator.free(default_manifest);
    const manifest_path = if (manifest_path_arg.len > 0) manifest_path_arg else default_manifest;

    var manifest = tenant_manifest_mod.loadFromPath(allocator, manifest_path) catch |err| {
        try out.print("extension quarantine evaluate: failed to load manifest at {s}: {s}\n", .{ manifest_path, @errorName(err) });
        return .config_error;
    };
    defer manifest.deinit();

    const outcome = extension_quarantine_mod.evaluateQuarantine(
        allocator,
        data_dir,
        namespace,
        manifest.trusted_signers,
        null, // dispatcher: not connected to a running daemon from CLI
        null, // audit: same
    ) catch |err| {
        try out.print("extension quarantine evaluate: error: {s}\n", .{@errorName(err)});
        return .file_io;
    };

    try out.print("evaluate {s}: state={s} transitioned_to_active={s} no_op={s}\n  detail: {s}\n", .{
        namespace,
        outcome.state.name(),
        if (outcome.transitioned_to_active) "true" else "false",
        if (outcome.no_op) "true" else "false",
        outcome.detail,
    });
    return .ok;
}

/// `brain extension quarantine remove <namespace>` — operator-driven
/// hard remove of a previously quarantined extension.  Requires the
/// extension to be in the quarantine index already (use `brain
/// extension quarantine list` to see candidates); the call walks
/// every version directory under the namespace, deletes the bundle
/// + meta.json, and appends a `removed` record to the index.
fn cmdExtensionQuarantineRemove(
    allocator: std.mem.Allocator,
    out: *const Output,
    args: []const [:0]u8,
) !ExitCode {
    if (args.len < 1) {
        try out.print("usage: brain extension quarantine remove <namespace>\n", .{});
        return .bad_args;
    }
    const namespace = args[0];

    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);

    // Find the latest record for this namespace.
    const records = extension_quarantine_mod.loadLatestRecords(allocator, data_dir) catch |err| {
        try out.print("extension quarantine remove: failed to read index: {s}\n", .{@errorName(err)});
        return .file_io;
    };
    defer extension_quarantine_mod.freeRecords(allocator, records);

    var matched: ?extension_quarantine_mod.QuarantineRecord = null;
    for (records) |r| {
        if (std.mem.eql(u8, r.extension_name, namespace)) {
            matched = r;
            break;
        }
    }
    if (matched == null) {
        try out.print("extension quarantine remove: no quarantine record for `{s}`\n", .{namespace});
        return .config_error;
    }
    if (matched.?.state == .active) {
        try out.print("extension quarantine remove: `{s}` is currently active; quarantine it first or rotate the signer.\n", .{namespace});
        return .config_error;
    }

    // Build the remove record.  Use the current latest record's
    // install_path + version + signer_pubkey for audit fidelity.
    const removal = extension_quarantine_mod.QuarantineRecord{
        .extension_name = matched.?.extension_name,
        .version = matched.?.version,
        .signer_pubkey_hex = matched.?.signer_pubkey_hex,
        .state = .removed,
        .quarantined_at = std.time.timestamp(),
        .reason = .operator_remove,
        .original_install_path = matched.?.original_install_path,
        .previous_state = matched.?.state,
    };

    extension_quarantine_mod.hardRemove(
        allocator,
        data_dir,
        removal,
        null, // dispatcher: CLI is detached from running daemon
        null, // audit
    ) catch |err| {
        try out.print("extension quarantine remove: hard-remove failed: {s}\n", .{@errorName(err)});
        return .file_io;
    };

    try out.print("Removed {s} (version {s}) — bundle deleted, dispatcher unmarked, index record appended.\n", .{
        namespace,
        matched.?.version,
    });
    return .ok;
}


```
