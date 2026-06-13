---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cli/device.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.283747+00:00
---

# runtime/semantos-brain/src/cli/device.zig

```zig
// Device verbs (D-W1 Phase 1 Part 2 — brain device list / revoke /
// init / pair / claim) extracted from src/cli.zig as Move 6 of the
// cli-modularize refactor.  Pure code motion: no behaviour change.

const std = @import("std");
const cli_common = @import("common.zig");
const audit_log_mod = @import("audit_log");
const dispatcher_mod = @import("dispatcher");
const unix_socket_transport = @import("unix_socket");
const identity_certs_mod = @import("identity_certs");
const identity_certs_handler_mod = @import("identity_certs_handler");
const bkds_mod = @import("bkds");
const device_pair_mod = @import("device_pair");
const qr_render = @import("qr_render");
const bsvz_mod = @import("bsvz");

const Output = cli_common.Output;
const ExitCode = cli_common.ExitCode;
const resolveDataDir = cli_common.resolveDataDir;
const jsonStringField = cli_common.jsonStringField;
const realClock = cli_common.realClock;
const daemonErrorAsZigError = cli_common.daemonErrorAsZigError;

const DeviceOutcome = struct {
    result_json: []u8,
    mode: Mode,
    socket_path: []u8 = &.{},
    data_dir: []u8 = &.{},

    const Mode = enum { socket, embedded };

    fn deinit(self: *DeviceOutcome, allocator: std.mem.Allocator) void {
        allocator.free(self.result_json);
        if (self.socket_path.len > 0) allocator.free(self.socket_path);
        if (self.data_dir.len > 0) allocator.free(self.data_dir);
    }
};

fn dispatchDevice(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    cmd: []const u8,
    args_json: []const u8,
) !DeviceOutcome {
    // ── Socket mode ──
    if (unix_socket_transport.Client.connect(allocator, data_dir)) |client_val| {
        var client = client_val;
        defer client.close();
        var resp = try client.dispatch("identity_certs", cmd, args_json, "cli");
        defer resp.deinit();
        if (resp.response.err) |e| {
            return daemonErrorAsZigError(e);
        }
        const sock_path = try std.fs.path.join(allocator, &.{ data_dir, unix_socket_transport.SOCKET_BASENAME });
        errdefer allocator.free(sock_path);
        return .{
            .result_json = try allocator.dupe(u8, resp.response.result_json),
            .mode = .socket,
            .socket_path = sock_path,
            .data_dir = &.{},
        };
    } else |_| {}

    // ── Embedded mode ──
    var audit = audit_log_mod.AuditLog.init();
    const audit_path = try std.fs.path.join(allocator, &.{ data_dir, "audit.log" });
    defer allocator.free(audit_path);
    audit.open(audit_path) catch {};
    defer audit.close();

    var store = identity_certs_mod.CertStore.init(allocator, data_dir, realClock) catch |e| return e;
    defer store.deinit();
    var handler = identity_certs_handler_mod.Handler.init(allocator, &store);
    var disp = dispatcher_mod.Dispatcher.init(allocator, &audit);
    defer disp.deinit();
    try disp.register(handler.resourceHandler());

    const ctx = dispatcher_mod.DispatchContext{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "cli-embedded", .transport_label = "embedded" },
    };
    var result = try disp.dispatch(&ctx, "identity_certs", cmd, args_json);
    defer result.deinit();

    const dd = try allocator.dupe(u8, data_dir);
    errdefer allocator.free(dd);
    return .{
        .result_json = try allocator.dupe(u8, result.payload),
        .mode = .embedded,
        .data_dir = dd,
        .socket_path = &.{},
    };
}

pub fn cmdDevice(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 1) {
        try out.print("usage: brain device <init|pair|claim|list|revoke> [args...]\n", .{});
        return .bad_args;
    }
    const sub = args[0];
    if (std.mem.eql(u8, sub, "init")) return try cmdDeviceInit(allocator, out, args[1..]);
    if (std.mem.eql(u8, sub, "list")) return try cmdDeviceList(allocator, out);
    if (std.mem.eql(u8, sub, "revoke")) return try cmdDeviceRevoke(allocator, out, args[1..]);
    if (std.mem.eql(u8, sub, "pair")) return try cmdDevicePair(allocator, out, args[1..]);
    if (std.mem.eql(u8, sub, "claim")) return try cmdDeviceClaim(allocator, out, args[1..]);
    try out.print("unknown device subcommand: {s}\n", .{sub});
    return .bad_args;
}

// ─────────────────────────────────────────────────────────────────────
// Smoke-test pass #1, fix #8 — `brain device init`.
//
// Pre-fix: error messages in cmdServe + cmdDevicePair told operators
// to "run `brain device init` first" — but that subcommand never
// existed.  Operators had to write the priv hex by hand + dispatch
// `identity_certs.issue_root` via the REPL to get a root cert.
//
// This subcommand bootstraps the operator-root identity in one step:
//   1. Generate a fresh secp256k1 priv via CSPRNG.
//   2. Persist as <data_dir>/operator-root-priv.hex (mode 0600,
//      64 ASCII hex chars + newline).
//   3. Derive the SEC1-compressed pubkey.
//   4. Open the on-disk CertStore + call issueRoot(pubkey, label).
//   5. Print the cert id so the operator can pin it on the device side.
//
// Idempotent: if the priv already exists on disk we refuse to overwrite
// it — the operator must move it aside explicitly.  If the priv exists
// but no root cert is recorded yet (interrupted bootstrap), the
// existing priv is reused and the root cert is minted from it.
// ─────────────────────────────────────────────────────────────────────

fn cmdDeviceInit(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    var label: []const u8 = "operator-root";
    var data_dir_flag: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--label") and i + 1 < args.len) {
            label = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--data-dir") and i + 1 < args.len) {
            data_dir_flag = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--help")) {
            try out.print(
                \\usage: brain device init [--label <name>] [--data-dir <path>]
                \\
                \\Bootstrap the operator-root identity:
                \\  - generates a fresh secp256k1 priv via CSPRNG
                \\  - writes it to <data_dir>/operator-root-priv.hex (mode 0600)
                \\  - derives the pubkey + mints the root cert in the on-disk store
                \\
                \\Idempotent: if a priv already exists on disk it is reused.  If
                \\both the priv and a root cert exist, prints the existing cert id
                \\and exits 0.
                \\
                \\--data-dir overrides $BRAIN_DATA_DIR and the config-file default.
                \\Use it when invoking via sudo (which strips environment variables)
                \\to ensure init writes to the same directory as `brain serve`.
                \\Example: sudo -u semantos brain device init --data-dir /var/lib/semantos
                \\
            , .{});
            return .ok;
        } else {
            try out.print("device init: unknown flag {s}\n", .{args[i]});
            return .bad_args;
        }
    }

    const data_dir: []const u8 = if (data_dir_flag) |d|
        try allocator.dupe(u8, d)
    else
        try resolveDataDir(allocator);
    defer allocator.free(data_dir);
    std.fs.cwd().makePath(data_dir) catch |e| {
        try out.print("device init: cannot create data dir {s}: {s}\n", .{ data_dir, @errorName(e) });
        return .file_io;
    };

    const priv_path = try std.fs.path.join(allocator, &.{ data_dir, "operator-root-priv.hex" });
    defer allocator.free(priv_path);

    // Step 1+2: load existing priv or mint + persist a fresh one.
    var priv: [bkds_mod.PRIVKEY_LEN]u8 = undefined;
    var was_existing = false;
    if (readOperatorPriv(allocator, priv_path)) |existing| {
        priv = existing;
        was_existing = true;
        try out.print("device init: priv exists at {s}; reusing\n", .{priv_path});
    } else |_| {
        std.crypto.random.bytes(&priv);
        // ASCII hex + newline.
        var hex_buf: [bkds_mod.PRIVKEY_LEN * 2 + 1]u8 = undefined;
        const hex_chars = "0123456789abcdef";
        for (priv, 0..) |b, j| {
            hex_buf[j * 2] = hex_chars[b >> 4];
            hex_buf[j * 2 + 1] = hex_chars[b & 0x0f];
        }
        hex_buf[bkds_mod.PRIVKEY_LEN * 2] = '\n';
        // Create with 0600 — Zig's createFile honours the mode arg on
        // posix.  We use createFile + truncate=true; an existing-priv
        // case is already handled above so this branch only fires when
        // the file was absent.
        const f = std.fs.cwd().createFile(priv_path, .{ .mode = 0o600 }) catch |e| {
            try out.print("device init: cannot write priv {s}: {s}\n", .{ priv_path, @errorName(e) });
            return .file_io;
        };
        defer f.close();
        f.writeAll(&hex_buf) catch |e| {
            try out.print("device init: write failed: {s}\n", .{@errorName(e)});
            return .file_io;
        };
        try out.print("device init: wrote operator priv to {s} (mode 0600)\n", .{priv_path});
    }

    // Step 3: derive pubkey.
    const priv_obj = bsvz_mod.primitives.ec.PrivateKey.fromBytes(priv) catch {
        try out.print("device init: priv is not a valid scalar — delete {s} and retry\n", .{priv_path});
        return .file_io;
    };
    const pub_obj = priv_obj.publicKey() catch {
        try out.print("device init: cannot derive pubkey from priv\n", .{});
        return .file_io;
    };
    const pub_sec1 = pub_obj.toCompressedSec1();

    // Step 4: open the cert store + issue root.
    var cert_store = identity_certs_mod.CertStore.init(allocator, data_dir, realClock) catch |e| {
        try out.print("device init: cannot open cert store at {s}: {s}\n", .{ data_dir, @errorName(e) });
        return .file_io;
    };
    defer cert_store.deinit();

    const rec = cert_store.issueRoot(pub_sec1, label) catch |e| {
        try out.print("device init: issueRoot failed: {s}\n", .{@errorName(e)});
        return .file_io;
    };

    if (was_existing and cert_store.count() > 0) {
        // Already-bootstrapped path — the issueRoot call above is idempotent.
        try out.print("device init: existing root cert id={s}\n", .{&rec.id});
    } else {
        try out.print("device init: minted root cert id={s} label=\"{s}\"\n", .{ &rec.id, label });
    }
    try out.print("device init: ready — `brain serve` can now stand up the D-O5p HTTP acceptor.\n", .{});
    return .ok;
}

// ─────────────────────────────────────────────────────────────────────
// D-W1 Phase 1 follow-up — `brain device pair --device-name <name>
// --caps <minimal|full|cap.X,cap.Y,...>` builds + signs a 5-minute
// one-shot pairing payload, persists the nonce, and emits both URL
// + token forms for the operator to share with the device.
//
// IMPORTANT — operator priv source: the brain's root priv is read from
// `<data_dir>/operator-root-priv.hex` (mode 0600, 64 hex chars), the
// same path the (eventual) D-O5p Plexus-recipe wiring populates.
// Without it `pair` fails closed with `operator_root_priv_missing`.
// We do NOT mint a new root cert here — that's `brain device init`
// (separate command, not in scope for this PR; today the test
// fixture writes the priv + root pubkey directly via the dispatcher's
// identity_certs.issue_root path).
// ─────────────────────────────────────────────────────────────────────

fn cmdDevicePair(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    var device_name_arg: ?[]const u8 = null;
    var caps_arg: []const u8 = "minimal";
    var brain_domain_arg: []const u8 = "localhost";
    var brain_pair_endpoint_arg: ?[]const u8 = null;
    var brain_wss_endpoint_arg: ?[]const u8 = null;
    var qr_mode: QrMode = .ascii;
    var data_dir_flag: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--device-name") and i + 1 < args.len) {
            device_name_arg = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--caps") and i + 1 < args.len) {
            caps_arg = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--brain-domain") and i + 1 < args.len) {
            brain_domain_arg = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--brain-pair-endpoint") and i + 1 < args.len) {
            brain_pair_endpoint_arg = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--brain-wss-endpoint") and i + 1 < args.len) {
            brain_wss_endpoint_arg = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--data-dir") and i + 1 < args.len) {
            data_dir_flag = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--qr") and i + 1 < args.len) {
            const v = args[i + 1];
            if (std.mem.eql(u8, v, "ascii")) {
                qr_mode = .ascii;
            } else if (std.mem.eql(u8, v, "off") or std.mem.eql(u8, v, "none")) {
                qr_mode = .off;
            } else {
                try out.print("device pair: unknown --qr mode `{s}` (use ascii|off)\n", .{v});
                return .bad_args;
            }
            i += 1;
        } else {
            try out.print("device pair: unknown arg `{s}`\n", .{args[i]});
            return .bad_args;
        }
    }
    if (device_name_arg == null) {
        try out.print("usage: brain device pair --device-name <name> [--data-dir <path>] [--caps <minimal|full|cap.X,cap.Y,...>] [--brain-domain <domain>] [--brain-pair-endpoint <https-url>] [--brain-wss-endpoint <wss-url>] [--qr ascii|off]\n", .{});
        return .bad_args;
    }

    const data_dir: []const u8 = if (data_dir_flag) |d|
        try allocator.dupe(u8, d)
    else
        try resolveDataDir(allocator);
    defer allocator.free(data_dir);

    // Sanitise label.
    const label = device_pair_mod.sanitiseLabel(allocator, device_name_arg.?) catch |e| {
        try out.print("device pair: invalid --device-name: {s}\n", .{@errorName(e)});
        return .bad_args;
    };
    defer allocator.free(label);

    // Resolve cap allowlist.
    const caps = device_pair_mod.resolveCaps(allocator, caps_arg) catch |e| {
        try out.print("device pair: invalid --caps `{s}`: {s}\n", .{ caps_arg, @errorName(e) });
        return .bad_args;
    };
    defer caps.deinit(allocator);

    // Open cert store; need root cert + the operator priv.
    var store = identity_certs_mod.CertStore.init(allocator, data_dir, realClock) catch |e| {
        try out.print("device pair: failed to open cert store: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer store.deinit();

    const root_id_bytes = store.rootId() orelse {
        try out.print("device pair: no operator root cert minted yet — run `brain device init` first (or, in tests, issue_root via the dispatcher).\n", .{});
        return .config_error;
    };
    const root_rec = store.get(&root_id_bytes) catch {
        try out.print("device pair: root cert id present but record missing (corrupt store?)\n", .{});
        return .file_io;
    };

    // Read operator priv from disk.
    const priv_path = try std.fs.path.join(allocator, &.{ data_dir, "operator-root-priv.hex" });
    defer allocator.free(priv_path);
    const operator_priv = readOperatorPriv(allocator, priv_path) catch |e| {
        try out.print("device pair: cannot read operator-root-priv.hex at {s}: {s}\n", .{ priv_path, @errorName(e) });
        try out.print("            (production wiring lands in D-O5p Plexus recipe; for tests, write the 64-hex priv to that path with mode 0600.)\n", .{});
        return .config_error;
    };

    // Allocate next context tag.
    const used_tags = collectUsedTags(allocator, &store) catch |e| {
        try out.print("device pair: cannot enumerate used context tags: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer allocator.free(used_tags);
    const ctx_tag = device_pair_mod.allocateContextTag(used_tags) catch |e| {
        try out.print("device pair: cannot allocate context tag: {s}\n", .{@errorName(e)});
        return .file_io;
    };

    // Generate nonce.
    var nonce: [device_pair_mod.NONCE_LEN]u8 = undefined;
    std.crypto.random.bytes(&nonce);

    const now = realClock();
    const expires_at = now + device_pair_mod.PAYLOAD_TTL_SECONDS;

    const caps_const: []const []const u8 = blk: {
        var s = try allocator.alloc([]const u8, caps.items.len);
        for (caps.items, 0..) |c, j| s[j] = c;
        break :blk s;
    };
    defer allocator.free(caps_const);

    // Build brain endpoint URLs.  If the operator passed
    // --brain-pair-endpoint / --brain-wss-endpoint we use those
    // verbatim; otherwise we synthesise sensible defaults from
    // --brain-domain.  The defaults assume a Caddy fronted at port
    // 443 — the common production shape — but the operator can
    // override for local-dev (e.g. http://localhost:8080/api/v1/
    // device-pair) by passing the args explicitly.
    const default_pair_endpoint = try std.fmt.allocPrint(allocator, "https://{s}/api/v1/device-pair", .{brain_domain_arg});
    defer allocator.free(default_pair_endpoint);
    const default_wss_endpoint = try std.fmt.allocPrint(allocator, "wss://{s}/api/v1/wallet", .{brain_domain_arg});
    defer allocator.free(default_wss_endpoint);
    const brain_pair_endpoint: []const u8 = brain_pair_endpoint_arg orelse default_pair_endpoint;
    const brain_wss_endpoint: []const u8 = brain_wss_endpoint_arg orelse default_wss_endpoint;

    if (!device_pair_mod.isValidBrainUrl(brain_pair_endpoint, "https://") and
        !device_pair_mod.isValidBrainUrl(brain_pair_endpoint, "http://"))
    {
        try out.print("device pair: --brain-pair-endpoint must be an http(s):// URL ≤{d} bytes\n", .{device_pair_mod.MAX_BRAIN_URL_LEN});
        return .bad_args;
    }
    if (!device_pair_mod.isValidBrainUrl(brain_wss_endpoint, "wss://") and
        !device_pair_mod.isValidBrainUrl(brain_wss_endpoint, "ws://"))
    {
        try out.print("device pair: --brain-wss-endpoint must be a ws(s):// URL ≤{d} bytes\n", .{device_pair_mod.MAX_BRAIN_URL_LEN});
        return .bad_args;
    }

    const payload = device_pair_mod.PairPayload{
        .operator_root_cert_id = root_rec.id,
        .operator_root_pub = root_rec.pubkey,
        .context_tag = ctx_tag,
        .label = label,
        .capabilities = caps_const,
        .expires_at = expires_at,
        .nonce = nonce,
        .brain_pair_endpoint = brain_pair_endpoint,
        .brain_wss_endpoint = brain_wss_endpoint,
        .brain_pin_cert_id = root_rec.id,
        .brain_pin_pubkey = root_rec.pubkey,
    };

    var token = device_pair_mod.signAndEncode(allocator, payload, operator_priv) catch |e| {
        try out.print("device pair: signing failed: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer token.deinit(allocator);

    const url = device_pair_mod.pairUrl(allocator, brain_domain_arg, token.base64url) catch |e| {
        try out.print("device pair: URL build failed: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer allocator.free(url);

    try out.print("Pairing payload generated for device `{s}`\n\n", .{label});
    try out.print("  Context tag:    0x{x:0>2}\n", .{ctx_tag});
    try out.print("  Capabilities:   {d}\n", .{caps.items.len});
    for (caps.items) |c| try out.print("                   - {s}\n", .{c});
    try out.print("  Expires at:     {d} (in {d}s)\n", .{ expires_at, device_pair_mod.PAYLOAD_TTL_SECONDS });
    try out.print("  Brain pair URL: {s}\n", .{brain_pair_endpoint});
    try out.print("  Brain WSS URL:  {s}\n", .{brain_wss_endpoint});
    try out.print("\n  URL form:\n    {s}\n\n", .{url});
    try out.print("  Token form (base64url):\n    {s}\n\n", .{token.base64url});

    if (qr_mode == .ascii) {
        const qr = qr_render.renderUrlAsciiQr(allocator, url) catch |e| {
            try out.print("  (QR render failed: {s} — paste the URL form above into any QR generator)\n", .{@errorName(e)});
            return .ok;
        };
        defer allocator.free(qr);
        try out.print("  Pairing QR (scan with the device app):\n\n{s}\n", .{qr});
    } else {
        try out.print("  (QR rendering disabled via --qr off; paste the URL form into any QR generator if you need a scan target.)\n", .{});
    }

    return .ok;
}

/// QR rendering mode for `brain device pair`.
pub const QrMode = enum {
    /// ASCII QR printed to the terminal.  Default; the typical shape
    /// for the operator on a TTY.
    ascii,
    /// QR rendering suppressed.  Only the URL/token lines are
    /// emitted.  Useful for non-TTY contexts (CI, scripting, log
    /// capture).
    off,
};

/// Read the operator priv from `<data_dir>/operator-root-priv.hex`.
/// File is exactly 64 hex chars (optionally trailing newline).  Mode
/// is ignored at read; the caller (operator) is responsible for the
/// 0600 invariant on disk.
pub fn readOperatorPriv(allocator: std.mem.Allocator, path: []const u8) ![bkds_mod.PRIVKEY_LEN]u8 {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    var buf: [128]u8 = undefined;
    const n = try f.readAll(&buf);
    var hex_end: usize = n;
    while (hex_end > 0 and (buf[hex_end - 1] == '\n' or buf[hex_end - 1] == '\r' or buf[hex_end - 1] == ' ')) {
        hex_end -= 1;
    }
    if (hex_end != bkds_mod.PRIVKEY_LEN * 2) return error.bad_priv_format;
    var out: [bkds_mod.PRIVKEY_LEN]u8 = undefined;
    bkds_mod.hexDecode(buf[0..hex_end], &out) catch return error.bad_priv_format;
    _ = allocator;
    return out;
}

/// Walk the cert store + return the list of context tags currently
/// in use across child certs.  Caller frees the slice.
fn collectUsedTags(allocator: std.mem.Allocator, store: *identity_certs_mod.CertStore) ![]u8 {
    const items = try store.list(allocator);
    defer allocator.free(items);
    var tags: std.ArrayList(u8) = .{};
    errdefer tags.deinit(allocator);
    for (items) |rec| {
        if (rec.kind == .child) try tags.append(allocator, rec.context_tag);
    }
    return tags.toOwnedSlice(allocator);
}

// ─────────────────────────────────────────────────────────────────────
// `brain device claim --token <base64url>` — lab fixture.
//
// Documented as: this is NOT how production claim works.  In
// production the Flutter app on the device runs the device-side half
// (D-O5m).  This CLI verb exists so an operator can drive both halves
// of the pairing handshake from one process for tests + lab use.
//
// Steps:
//   1. Parse + verify the inbound token (signature, expiry, version).
//   2. Check the one-shot nonce ledger.
//   3. Generate a fresh device priv (same shape as `bkds.privFromSeed`
//      but seeded from CSPRNG so each lab claim is distinct).
//   4. Derive expected child pubkey via BRC-42 ECDH symmetry — same
//      algorithm `bkds.deriveChildPubkeyFromDevice` exposes for the
//      device-side reference path.
//   5. POST `identity_certs.issue_child` against the dispatcher with
//      the (parent_cert_id, context_tag, capabilities, label,
//      derivation_pubkey, derivation_proof) tuple.
//   6. Persist the nonce as consumed.
// ─────────────────────────────────────────────────────────────────────

fn cmdDeviceClaim(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    var token_arg: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--token") and i + 1 < args.len) {
            token_arg = args[i + 1];
            i += 1;
        } else {
            try out.print("device claim: unknown arg `{s}`\n", .{args[i]});
            return .bad_args;
        }
    }
    if (token_arg == null) {
        try out.print("usage: brain device claim --token <base64url-or-url>\n", .{});
        try out.print("\n  NOTE: `brain device claim` is a LAB FIXTURE — production claim runs on the\n", .{});
        try out.print("        device's Flutter app (D-O5m), not the brain.  Use this verb to\n", .{});
        try out.print("        exercise both halves of the pair flow in one CLI process for tests.\n", .{});
        return .bad_args;
    }
    const bare_token = device_pair_mod.extractToken(token_arg.?);

    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);

    const now = realClock();

    var parsed = device_pair_mod.parseAndVerify(allocator, bare_token, now) catch |e| {
        try out.print("device claim: payload rejected: {s}\n", .{@errorName(e)});
        return switch (e) {
            error.pairing_payload_expired,
            error.pairing_payload_invalid_signature,
            error.pairing_payload_invalid_format,
            error.pairing_payload_unknown_version,
            error.pairing_payload_invalid_capability,
            error.pairing_payload_label_too_long,
            => .bad_args,
            else => .file_io,
        };
    };
    defer parsed.deinit(allocator);

    // One-shot nonce check.
    var ledger = device_pair_mod.NonceLedger.init(allocator, data_dir) catch |e| {
        try out.print("device claim: cannot open nonce ledger: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer ledger.deinit();
    if (ledger.isConsumed(parsed.nonce)) {
        try out.print("device claim: payload already consumed (one-shot nonce)\n", .{});
        return .bad_args;
    }

    // Generate a fresh device priv via CSPRNG.
    var device_priv: [bkds_mod.PRIVKEY_LEN]u8 = undefined;
    std.crypto.random.bytes(&device_priv);
    // Derive its pubkey.
    const device_priv_obj = bsvz_mod.primitives.ec.PrivateKey.fromBytes(device_priv) catch {
        try out.print("device claim: random priv generation produced an invalid scalar — try again\n", .{});
        return .file_io;
    };
    const device_pub_obj = device_priv_obj.publicKey() catch {
        try out.print("device claim: cannot derive device pubkey\n", .{});
        return .file_io;
    };
    const device_pub_sec1 = device_pub_obj.toCompressedSec1();

    // Compute child pubkey via the device-side BRC-42 path.
    const child_pub = bkds_mod.deriveChildPubkeyFromDevice(
        device_priv,
        parsed.operator_root_pub,
        parsed.context_tag,
        parsed.label,
    ) catch |e| {
        try out.print("device claim: BRC-42 derivation failed: {s}\n", .{@errorName(e)});
        return .file_io;
    };

    var child_pub_hex: [bkds_mod.KEY_LEN * 2]u8 = undefined;
    bkds_mod.hexEncode(&child_pub, &child_pub_hex);
    var device_pub_hex: [bkds_mod.PROOF_LEN * 2]u8 = undefined;
    bkds_mod.hexEncode(&device_pub_sec1, &device_pub_hex);

    // Build issue_child args JSON.
    var args_buf: std.ArrayList(u8) = .{};
    defer args_buf.deinit(allocator);
    try args_buf.appendSlice(allocator, "{\"parent_cert_id\":\"");
    try args_buf.appendSlice(allocator, &parsed.operator_root_cert_id);
    try args_buf.print(allocator, "\",\"context_tag\":{d},\"capabilities\":[", .{parsed.context_tag});
    for (parsed.capabilities, 0..) |c, j| {
        if (j != 0) try args_buf.append(allocator, ',');
        const enc = try std.json.Stringify.valueAlloc(allocator, c, .{});
        defer allocator.free(enc);
        try args_buf.appendSlice(allocator, enc);
    }
    try args_buf.appendSlice(allocator, "],\"label\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, parsed.label, .{});
        defer allocator.free(enc);
        try args_buf.appendSlice(allocator, enc);
    }
    try args_buf.appendSlice(allocator, ",\"derivation_pubkey\":\"");
    try args_buf.appendSlice(allocator, &child_pub_hex);
    try args_buf.appendSlice(allocator, "\",\"derivation_proof\":\"");
    try args_buf.appendSlice(allocator, &device_pub_hex);
    try args_buf.appendSlice(allocator, "\"}");

    var outcome = dispatchDeviceWithOperatorPriv(allocator, data_dir, "issue_child", args_buf.items, operator_priv_for_claim(allocator, data_dir)) catch |e| {
        try out.print("device claim: dispatch issue_child failed: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer outcome.deinit(allocator);

    // Mark the nonce consumed only after a successful claim.
    ledger.markConsumed(parsed.nonce) catch |e| {
        try out.print("device claim: child cert issued but nonce-mark failed: {s} (token may be reusable until cleanup)\n", .{@errorName(e)});
        return .file_io;
    };

    switch (outcome.mode) {
        .socket => try out.print("Claimed (via daemon at {s}):\n", .{outcome.socket_path}),
        .embedded => try out.print("Claimed (embedded mode — data_dir: {s}):\n", .{outcome.data_dir}),
    }
    try out.print("  {s}\n", .{outcome.result_json});
    try out.print("\n  NOTE: this `claim` is a LAB FIXTURE.  In production the device's Flutter\n", .{});
    try out.print("        app (D-O5m) runs this same logic with its own persistent priv.\n", .{});

    return .ok;
}

/// Helper: read operator priv for the claim flow.  Returns null if
/// the file is missing — the embedded dispatcher's handler will then
/// fail closed with `derivation_context_mismatch`, which is the
/// correct failure mode (matches the production-without-priv path).
fn operator_priv_for_claim(allocator: std.mem.Allocator, data_dir: []const u8) ?[bkds_mod.PRIVKEY_LEN]u8 {
    const path = std.fs.path.join(allocator, &.{ data_dir, "operator-root-priv.hex" }) catch return null;
    defer allocator.free(path);
    return readOperatorPriv(allocator, path) catch return null;
}

/// Variant of `dispatchDevice` that accepts an optional operator
/// priv to install on the embedded dispatcher's identity_certs
/// handler before dispatching.  Required for the `claim` flow —
/// without the priv installed, BRC-42 verification fails closed.
/// The socket path is unchanged: the daemon already holds the priv.
fn dispatchDeviceWithOperatorPriv(
    allocator: std.mem.Allocator,
    data_dir: []const u8,
    cmd: []const u8,
    args_json: []const u8,
    operator_priv: ?[bkds_mod.PRIVKEY_LEN]u8,
) !DeviceOutcome {
    // ── Socket mode ──
    if (unix_socket_transport.Client.connect(allocator, data_dir)) |client_val| {
        var client = client_val;
        defer client.close();
        var resp = try client.dispatch("identity_certs", cmd, args_json, "cli");
        defer resp.deinit();
        if (resp.response.err) |e| {
            return daemonErrorAsZigError(e);
        }
        const sock_path = try std.fs.path.join(allocator, &.{ data_dir, unix_socket_transport.SOCKET_BASENAME });
        errdefer allocator.free(sock_path);
        return .{
            .result_json = try allocator.dupe(u8, resp.response.result_json),
            .mode = .socket,
            .socket_path = sock_path,
            .data_dir = &.{},
        };
    } else |_| {}

    // ── Embedded mode ──
    var audit = audit_log_mod.AuditLog.init();
    const audit_path = try std.fs.path.join(allocator, &.{ data_dir, "audit.log" });
    defer allocator.free(audit_path);
    audit.open(audit_path) catch {};
    defer audit.close();

    var store = identity_certs_mod.CertStore.init(allocator, data_dir, realClock) catch |e| return e;
    defer store.deinit();
    var handler = identity_certs_handler_mod.Handler.init(allocator, &store);
    if (operator_priv) |p| handler.setOperatorRootPriv(p);
    var disp = dispatcher_mod.Dispatcher.init(allocator, &audit);
    defer disp.deinit();
    try disp.register(handler.resourceHandler());

    const ctx = dispatcher_mod.DispatchContext{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "cli-embedded", .transport_label = "embedded" },
    };
    var result = try disp.dispatch(&ctx, "identity_certs", cmd, args_json);
    defer result.deinit();

    const dd = try allocator.dupe(u8, data_dir);
    errdefer allocator.free(dd);
    return .{
        .result_json = try allocator.dupe(u8, result.payload),
        .mode = .embedded,
        .data_dir = dd,
        .socket_path = &.{},
    };
}

fn cmdDeviceList(allocator: std.mem.Allocator, out: *const Output) !ExitCode {
    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);

    var outcome = dispatchDevice(allocator, data_dir, "list", "{}") catch |e| {
        try out.print("device list: dispatch failed: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer outcome.deinit(allocator);

    switch (outcome.mode) {
        .socket => try out.print("(via daemon at {s})\n\n", .{outcome.socket_path}),
        .embedded => try out.print("(embedded mode — data_dir: {s})\n\n", .{outcome.data_dir}),
    }

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, outcome.result_json, .{}) catch {
        try out.print("device list: malformed daemon response\n", .{});
        return .file_io;
    };
    defer parsed.deinit();
    if (parsed.value != .object) return .file_io;
    const certs_v = parsed.value.object.get("certs") orelse {
        try out.print("device list: malformed response (no certs field)\n", .{});
        return .file_io;
    };
    if (certs_v != .array) return .file_io;
    const certs = certs_v.array.items;

    if (certs.len == 0) {
        try out.print("(no identity certs — `brain device pair` lands in D-O5p; pre-pair root via the dispatcher API)\n", .{});
        return .ok;
    }

    try out.print("{d} cert(s) in chain:\n\n", .{certs.len});
    for (certs) |c| {
        if (c != .object) continue;
        const obj = c.object;
        const kind = (obj.get("kind") orelse continue).string;
        const id = (obj.get("cert_id") orelse continue).string;
        const label = (obj.get("label") orelse continue).string;
        const ctx_tag = (obj.get("context_tag") orelse continue).integer;
        const issued_at = (obj.get("issued_at") orelse continue).integer;
        try out.print("  cert_id:     {s}\n", .{id});
        try out.print("  kind:        {s}\n", .{kind});
        try out.print("  label:       {s}\n", .{label});
        try out.print("  context_tag: 0x{x:0>2}\n", .{@as(u8, @intCast(ctx_tag))});
        try out.print("  issued_at:   {d}\n", .{issued_at});
        if (obj.get("parent_cert_id")) |p| {
            if (p == .string) try out.print("  parent:      {s}\n", .{p.string});
        }
        if (obj.get("capabilities")) |caps| {
            if (caps == .array and caps.array.items.len > 0) {
                try out.print("  capabilities:\n", .{});
                for (caps.array.items) |cap| {
                    if (cap == .string) try out.print("    - {s}\n", .{cap.string});
                }
            }
        }
        try out.print("\n", .{});
    }
    return .ok;
}

fn cmdDeviceRevoke(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    var id_arg: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--id") and i + 1 < args.len) {
            id_arg = args[i + 1];
            i += 1;
        } else {
            try out.print("device revoke: unknown arg `{s}`\n", .{args[i]});
            return .bad_args;
        }
    }
    if (id_arg == null) {
        try out.print("usage: brain device revoke --id <cert_id>\n", .{});
        return .bad_args;
    }
    if (id_arg.?.len != identity_certs_mod.CERT_ID_HEX_LEN) {
        try out.print("device revoke: cert_id must be {d} hex chars (got {d})\n", .{ identity_certs_mod.CERT_ID_HEX_LEN, id_arg.?.len });
        return .bad_args;
    }

    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);

    const args_json = try std.fmt.allocPrint(allocator,
        \\{{"cert_id":"{s}"}}
    , .{id_arg.?});
    defer allocator.free(args_json);

    var outcome = dispatchDevice(allocator, data_dir, "revoke", args_json) catch |e| {
        try out.print("device revoke: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer outcome.deinit(allocator);

    switch (outcome.mode) {
        .socket => try out.print("revoked: {s} (via daemon at {s})\n", .{ id_arg.?, outcome.socket_path }),
        .embedded => try out.print("revoked: {s} (embedded mode — data_dir: {s})\n", .{ id_arg.?, outcome.data_dir }),
    }
    return .ok;
}



```
