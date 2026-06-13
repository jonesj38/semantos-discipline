---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/repl/device_cmds.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.296679+00:00
---

# runtime/semantos-brain/src/repl/device_cmds.zig

```zig
// REPL device + headers verbs extracted from src/repl.zig as
// Phase 4 of the modularize.  Pure code motion: no behaviour change.
//
// Owns: cmdDevice + cmdHeaders + sub-verbs (cmdDeviceList /
// cmdDeviceRevoke / cmdDevicePair / cmdDeviceClaim) + small helpers.

const std = @import("std");
const types = @import("types.zig");
const bkds_mod = @import("bkds");
const bsvz_mod = @import("bsvz");
const device_pair_mod = @import("device_pair");
const identity_certs_mod = @import("identity_certs");

const Session = types.Session;
const matches = types.matches;


// ─────────────────────────────────────────────────────────────────────
// D-W1 Phase 1 Part 2 — `device` REPL verb
//
// Reference: docs/design/BRAIN-DISPATCHER-UNIFICATION.md §3 (identity_certs);
//            docs/design/ODDJOBZ-EXTENSION-PLAN.md §3 Phase O5p.
//
// REPL-side mirror of `brain device list|revoke` — drives the identity_
// certs resource directly (the REPL transport's auth context is
// `in_process_root`, so capability checks bypass).  When no cert store
// is attached we point the operator at the CLI form rather than
// failing silently.
// ─────────────────────────────────────────────────────────────────────

pub fn cmdDevice(session: *Session, out: anytype, args: []const []const u8) !void {
    if (args.len < 1) {
        try out.print("usage: device pair <name> [caps] | device claim <token> | device list | device revoke <cert_id>\n", .{});
        return;
    }
    const sub = args[0];
    const store = session.cert_store orelse {
        try out.print("device: no cert store attached to this REPL session.\n", .{});
        try out.print("        run `brain device {s} ...` from a separate terminal — it will\n", .{sub});
        try out.print("        connect to the daemon's Unix socket (or fall back to embedded mode).\n", .{});
        return;
    };

    if (matches(sub, "list")) {
        return cmdDeviceList(store, out);
    }
    if (matches(sub, "revoke")) {
        if (args.len < 2) {
            try out.print("usage: device revoke <cert_id>\n", .{});
            return;
        }
        return cmdDeviceRevoke(store, out, args[1]);
    }
    if (matches(sub, "pair")) {
        return cmdDevicePair(session, out, args[1..]);
    }
    if (matches(sub, "claim")) {
        return cmdDeviceClaim(session, out, args[1..]);
    }
    try out.print("unknown device subcommand: {s}\n", .{sub});
}

// ─────────────────────────────────────────────────────────────────────
// D-W1 Phase 2 — `headers tip` REPL verb
// ─────────────────────────────────────────────────────────────────────

pub fn cmdHeaders(session: *Session, out: anytype, args: []const []const u8) !void {
    if (args.len < 1 or !matches(args[0], "tip")) {
        try out.print("usage: headers tip\n", .{});
        return;
    }
    if (session.header_store.tip()) |rec| {
        // Bitcoin hashes display in reverse byte order (block-explorer
        // convention).  Same byte-pair-reverse the CLI's `brain headers
        // tip` does so output is identical between surfaces.
        var hex_buf: [64]u8 = undefined;
        const hex_chars = "0123456789abcdef";
        for (rec.hash, 0..) |b, i| {
            const dst = 31 - i;
            hex_buf[dst * 2] = hex_chars[(b >> 4) & 0xf];
            hex_buf[dst * 2 + 1] = hex_chars[b & 0xf];
        }
        try out.print("tip:    height={d}\n", .{rec.height});
        try out.print("        hash={s}\n", .{hex_buf[0..]});
    } else {
        try out.print("(header store empty — run `brain headers sync`)\n", .{});
    }
}

pub fn cmdDeviceList(store: *identity_certs_mod.CertStore, out: anytype) !void {
    const allocator = std.heap.page_allocator;
    const items = store.list(allocator) catch |err| {
        try out.print("device list: store error: {s}\n", .{@errorName(err)});
        return;
    };
    defer allocator.free(items);

    if (items.len == 0) {
        try out.print("(no identity certs — pairing lands in D-O5p)\n", .{});
        return;
    }
    try out.print("{d} cert(s) in chain:\n", .{items.len});
    for (items) |rec| {
        const kind_label: []const u8 = if (rec.kind == .root) "root" else "child";
        try out.print("  {s} {s} (context_tag=0x{x:0>2}) label={s}\n", .{ kind_label, rec.id, rec.context_tag, rec.label });
    }
}

pub fn cmdDeviceRevoke(store: *identity_certs_mod.CertStore, out: anytype, id: []const u8) !void {
    if (id.len != identity_certs_mod.CERT_ID_HEX_LEN) {
        try out.print("device revoke: cert_id must be {d} hex chars (got {d})\n", .{ identity_certs_mod.CERT_ID_HEX_LEN, id.len });
        return;
    }
    store.revoke(id) catch |err| {
        try out.print("device revoke: {s}\n", .{@errorName(err)});
        return;
    };
    try out.print("revoked: {s}\n", .{id});
}

// ─────────────────────────────────────────────────────────────────────
// D-W1 Phase 1 follow-up — REPL `device pair` / `device claim`
// mirrors of the CLI verbs.  Same operator priv source
// (`<data_dir>/operator-root-priv.hex`) and same lab-fixture caveat
// on `claim`.  Args are positional (the REPL parser doesn't do
// flag-style args):
//
//   device pair <name> [caps]
//   device claim <token-or-url>
// ─────────────────────────────────────────────────────────────────────

pub fn cmdDevicePair(session: *Session, out: anytype, args: []const []const u8) !void {
    if (args.len < 1) {
        try out.print("usage: device pair <name> [minimal|full|cap.X,cap.Y,...]\n", .{});
        return;
    }
    const allocator = session.allocator;
    const data_dir = session.cfg.shell.data_dir;
    const store = session.cert_store.?;

    const label = device_pair_mod.sanitiseLabel(allocator, args[0]) catch |e| {
        try out.print("device pair: invalid name: {s}\n", .{@errorName(e)});
        return;
    };
    defer allocator.free(label);

    const caps_arg: []const u8 = if (args.len >= 2) args[1] else "minimal";
    const caps = device_pair_mod.resolveCaps(allocator, caps_arg) catch |e| {
        try out.print("device pair: invalid caps `{s}`: {s}\n", .{ caps_arg, @errorName(e) });
        return;
    };
    defer caps.deinit(allocator);

    const root_id_bytes = store.rootId() orelse {
        try out.print("device pair: no operator root cert minted yet — issue_root via `brain device init` (or the dispatcher) first.\n", .{});
        return;
    };
    const root_rec = store.get(&root_id_bytes) catch {
        try out.print("device pair: root cert id present but record missing.\n", .{});
        return;
    };

    const priv_path = try std.fs.path.join(allocator, &.{ data_dir, "operator-root-priv.hex" });
    defer allocator.free(priv_path);
    const operator_priv = readOperatorPrivRepl(allocator, priv_path) catch |e| {
        try out.print("device pair: cannot read operator-root-priv.hex: {s}\n", .{@errorName(e)});
        return;
    };

    // Used context tags.
    var tags: std.ArrayList(u8) = .{};
    defer tags.deinit(allocator);
    {
        const items = store.list(allocator) catch |e| {
            try out.print("device pair: store list failed: {s}\n", .{@errorName(e)});
            return;
        };
        defer allocator.free(items);
        for (items) |rec| if (rec.kind == .child) try tags.append(allocator, rec.context_tag);
    }
    const ctx_tag = device_pair_mod.allocateContextTag(tags.items) catch |e| {
        try out.print("device pair: cannot allocate context tag: {s}\n", .{@errorName(e)});
        return;
    };

    var nonce: [device_pair_mod.NONCE_LEN]u8 = undefined;
    std.crypto.random.bytes(&nonce);
    const now = std.time.timestamp();

    const caps_const = try allocator.alloc([]const u8, caps.items.len);
    defer allocator.free(caps_const);
    for (caps.items, 0..) |c, i| caps_const[i] = c;

    // REPL mirror of the CLI's brain-endpoint synthesis.  The REPL
    // is positional-args only, so we always derive defaults against
    // "localhost" — operators wanting a different surface should use
    // the CLI which exposes --brain-{pair,wss}-endpoint.
    const brain_domain: []const u8 = "localhost";
    const brain_pair_endpoint = try std.fmt.allocPrint(allocator, "https://{s}/api/v1/device-pair", .{brain_domain});
    defer allocator.free(brain_pair_endpoint);
    const brain_wss_endpoint = try std.fmt.allocPrint(allocator, "wss://{s}/api/v1/wallet", .{brain_domain});
    defer allocator.free(brain_wss_endpoint);

    const payload = device_pair_mod.PairPayload{
        .operator_root_cert_id = root_rec.id,
        .operator_root_pub = root_rec.pubkey,
        .context_tag = ctx_tag,
        .label = label,
        .capabilities = caps_const,
        .expires_at = now + device_pair_mod.PAYLOAD_TTL_SECONDS,
        .nonce = nonce,
        .brain_pair_endpoint = brain_pair_endpoint,
        .brain_wss_endpoint = brain_wss_endpoint,
        .brain_pin_cert_id = root_rec.id,
        .brain_pin_pubkey = root_rec.pubkey,
    };
    var token = device_pair_mod.signAndEncode(allocator, payload, operator_priv) catch |e| {
        try out.print("device pair: signing failed: {s}\n", .{@errorName(e)});
        return;
    };
    defer token.deinit(allocator);

    try out.print("Pairing payload for `{s}`:\n", .{label});
    try out.print("  context_tag=0x{x:0>2}, expires_at={d} (in {d}s)\n", .{ ctx_tag, payload.expires_at, device_pair_mod.PAYLOAD_TTL_SECONDS });
    try out.print("  capabilities ({d}):\n", .{caps.items.len});
    for (caps.items) |cap| try out.print("    - {s}\n", .{cap});
    try out.print("  brain pair endpoint: {s}\n", .{brain_pair_endpoint});
    try out.print("  brain wss endpoint:  {s}\n", .{brain_wss_endpoint});
    try out.print("  token: {s}\n", .{token.base64url});
}

pub fn cmdDeviceClaim(session: *Session, out: anytype, args: []const []const u8) !void {
    if (args.len < 1) {
        try out.print("usage: device claim <token-or-url>\n", .{});
        try out.print("       (LAB FIXTURE — production claim runs on the device's Flutter app, post-D-O5m)\n", .{});
        return;
    }
    const allocator = session.allocator;
    const data_dir = session.cfg.shell.data_dir;
    const store = session.cert_store.?;

    const bare_token = device_pair_mod.extractToken(args[0]);
    const now = std.time.timestamp();

    var parsed = device_pair_mod.parseAndVerify(allocator, bare_token, now) catch |e| {
        try out.print("device claim: payload rejected: {s}\n", .{@errorName(e)});
        return;
    };
    defer parsed.deinit(allocator);

    var ledger = device_pair_mod.NonceLedger.init(allocator, data_dir) catch |e| {
        try out.print("device claim: cannot open nonce ledger: {s}\n", .{@errorName(e)});
        return;
    };
    defer ledger.deinit();
    if (ledger.isConsumed(parsed.nonce)) {
        try out.print("device claim: payload already consumed (one-shot nonce)\n", .{});
        return;
    }

    var device_priv: [bkds_mod.PRIVKEY_LEN]u8 = undefined;
    std.crypto.random.bytes(&device_priv);
    const device_priv_obj = bsvz_mod.primitives.ec.PrivateKey.fromBytes(device_priv) catch {
        try out.print("device claim: random priv invalid; try again\n", .{});
        return;
    };
    const device_pub = (device_priv_obj.publicKey() catch unreachable).toCompressedSec1();

    const child_pub = bkds_mod.deriveChildPubkeyFromDevice(
        device_priv,
        parsed.operator_root_pub,
        parsed.context_tag,
        parsed.label,
    ) catch |e| {
        try out.print("device claim: BRC-42 derivation failed: {s}\n", .{@errorName(e)});
        return;
    };

    // Verify against the operator priv on disk before committing —
    // mirrors the dispatcher's identity_certs.issue_child path.
    const priv_path = try std.fs.path.join(allocator, &.{ data_dir, "operator-root-priv.hex" });
    defer allocator.free(priv_path);
    const operator_priv = readOperatorPrivRepl(allocator, priv_path) catch |e| {
        try out.print("device claim: cannot read operator-root-priv.hex: {s}\n", .{@errorName(e)});
        return;
    };
    bkds_mod.verifyDerivationProof(
        operator_priv,
        device_pub,
        parsed.context_tag,
        parsed.label,
        child_pub,
    ) catch |e| {
        try out.print("device claim: BRC-42 verify failed: {s}\n", .{@errorName(e)});
        return;
    };

    // Direct store call — we already verified.
    const caps_const = try allocator.alloc([]const u8, parsed.capabilities.len);
    defer allocator.free(caps_const);
    for (parsed.capabilities, 0..) |c, i| caps_const[i] = c;

    const child_rec = store.issueChild(
        &parsed.operator_root_cert_id,
        parsed.context_tag,
        child_pub,
        caps_const,
        parsed.label,
    ) catch |e| {
        try out.print("device claim: issueChild: {s}\n", .{@errorName(e)});
        return;
    };

    ledger.markConsumed(parsed.nonce) catch {};

    try out.print("Claimed: child cert {s} (context_tag=0x{x:0>2}, label={s})\n", .{ child_rec.id, child_rec.context_tag, child_rec.label });
}

fn readOperatorPrivRepl(allocator: std.mem.Allocator, path: []const u8) ![bkds_mod.PRIVKEY_LEN]u8 {
    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    var buf: [128]u8 = undefined;
    const n = try f.readAll(&buf);
    var hex_end: usize = n;
    while (hex_end > 0 and (buf[hex_end - 1] == '\n' or buf[hex_end - 1] == '\r' or buf[hex_end - 1] == ' ')) hex_end -= 1;
    if (hex_end != bkds_mod.PRIVKEY_LEN * 2) return error.bad_priv_format;
    var out: [bkds_mod.PRIVKEY_LEN]u8 = undefined;
    bkds_mod.hexDecode(buf[0..hex_end], &out) catch return error.bad_priv_format;
    _ = allocator;
    return out;
}

// ─────────────────────────────────────────────────────────────────────

```
