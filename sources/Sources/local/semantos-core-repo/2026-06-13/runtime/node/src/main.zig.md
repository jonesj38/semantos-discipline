---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/src/main.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.302552+00:00
---

# runtime/node/src/main.zig

```zig
// Phase W6 — `semantos-node` daemon entry point.
//
// Design ref: `docs/design/WALLET-TIER-CUSTODY.md` §10.2 (sovereign-node
// topology). Caddy terminates TLS upstream and proxies the WSS path
// `/wallet` to this daemon's plain-WS listener on a localhost port (or
// Unix socket; see §11 Q6 — this v0.1 ships TCP localhost, Unix socket
// is a one-line addition once Caddy's `reverse_proxy unix//…` is wired).
//
// Lifecycle (synchronous, single-thread v0.1):
//
//   1. parse CLI: --listen <addr:port> --data-dir <path>
//   2. open the lmdb-backed SlotStore + DerivationStateStore
//   3. install both via `host.setSlotStore` / `host.setDerivationStateStore`
//   4. derive (or read) the wallet identity seed under `<data-dir>/identity.bin`
//   5. bind a TCP listener; loop on accept → handshake → per-frame dispatch
//
// SIGTERM / Ctrl-C closes the listener; the lmdb stores' destructors
// flush nothing (every mutation already persisted) so a hard kill is
// safe — the daemon is restart-tolerant by construction (acceptance
// criterion 4).

const std = @import("std");
const builtin = @import("builtin");
const host = @import("host");
const slot_store_mod = @import("slot_store");
const derivation_state_mod = @import("derivation_state");
const bsvz = @import("bsvz");

const lmdb_slot_store = @import("lmdb_slot_store");
const lmdb_state_store = @import("lmdb_state_store");
const wss = @import("wss");
const brc100 = @import("brc100");

const DEFAULT_LISTEN = "127.0.0.1:8421";
const DEFAULT_DATA_DIR = ".semantos";
const MAX_FRAME_BYTES: usize = 64 * 1024;

const Args = struct {
    listen: []const u8 = DEFAULT_LISTEN,
    data_dir: []const u8 = DEFAULT_DATA_DIR,
};

fn parseArgs(allocator: std.mem.Allocator) !Args {
    var args = Args{};
    var arg_it = try std.process.argsWithAllocator(allocator);
    defer arg_it.deinit();
    _ = arg_it.next(); // exe name
    while (arg_it.next()) |a| {
        if (std.mem.eql(u8, a, "--listen")) {
            const v = arg_it.next() orelse return error.MissingArg;
            args.listen = try allocator.dupe(u8, v);
        } else if (std.mem.eql(u8, a, "--data-dir")) {
            const v = arg_it.next() orelse return error.MissingArg;
            args.data_dir = try allocator.dupe(u8, v);
        } else if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            std.debug.print(
                "usage: semantos-node [--listen 127.0.0.1:8421] [--data-dir ~/.semantos]\n" ++
                    "\n" ++
                    "  --listen   Plain-WS bind address (TLS terminates at Caddy upstream).\n" ++
                    "  --data-dir Persistence root: identity, slots/, state.bin land here.\n",
                .{},
            );
            std.process.exit(0);
        } else {
            std.debug.print("unknown arg: {s}\n", .{a});
            return error.BadArgs;
        }
    }
    // Env var fallbacks (per W6 task brief: "or reads env").
    if (std.mem.eql(u8, args.listen, DEFAULT_LISTEN)) {
        if (std.process.getEnvVarOwned(allocator, "SEMANTOS_NODE_LISTEN")) |v| {
            args.listen = v;
        } else |_| {}
    }
    if (std.mem.eql(u8, args.data_dir, DEFAULT_DATA_DIR)) {
        if (std.process.getEnvVarOwned(allocator, "SEMANTOS_NODE_DATA_DIR")) |v| {
            args.data_dir = v;
        } else |_| {}
    }
    return args;
}

/// Parse "host:port" into an Address. Supports IPv4 only for v0.1 —
/// IPv6 needs bracket-syntax, deferred.
fn parseListen(s: []const u8) !std.net.Address {
    const colon = std.mem.lastIndexOfScalar(u8, s, ':') orelse return error.BadAddress;
    const host_str = s[0..colon];
    const port = try std.fmt.parseInt(u16, s[colon + 1 ..], 10);
    return std.net.Address.parseIp(host_str, port);
}

/// Read or create the daemon's identity private key under
/// `<data-dir>/identity.bin`. v0.1 generates a random 32-byte secret on
/// first run; future versions integrate BIP-39 mnemonic flow (W9).
fn loadOrCreateIdentity(allocator: std.mem.Allocator, data_dir: []const u8) ![32]u8 {
    std.fs.cwd().makePath(data_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    const path = try std.fs.path.join(allocator, &.{ data_dir, "identity.bin" });
    defer allocator.free(path);

    if (std.fs.cwd().openFile(path, .{})) |f| {
        defer f.close();
        var buf: [32]u8 = undefined;
        const n = try f.readAll(&buf);
        if (n != 32) return error.CorruptIdentity;
        return buf;
    } else |err| switch (err) {
        error.FileNotFound => {
            // First run — generate a fresh secret.
            var sk: [32]u8 = undefined;
            std.crypto.random.bytes(&sk);
            // Atomic write: tmp + rename so a crash mid-write doesn't
            // leave a half-formed identity. Mirrors the lmdb_*_store pattern.
            const tmp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{path});
            defer allocator.free(tmp_path);
            const tf = try std.fs.cwd().createFile(tmp_path, .{ .truncate = true });
            tf.writeAll(&sk) catch {
                tf.close();
                std.fs.cwd().deleteFile(tmp_path) catch {};
                return error.WriteFailed;
            };
            tf.sync() catch {};
            tf.close();
            try std.fs.cwd().rename(tmp_path, path);
            return sk;
        },
        else => return err,
    }
}

/// Compute SEC1-compressed pubkey for the daemon identity (33 bytes).
fn identityPubkey(sk: [32]u8) ![33]u8 {
    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(sk);
    const pub_key = try priv.publicKey();
    return pub_key.toCompressedSec1();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try parseArgs(allocator);

    // ── Stores: lmdb-backed v0.1 (file-per-slot + binary state.bin) ──
    var slot_backing = try lmdb_slot_store.LmdbSlotStore.init(allocator, args.data_dir);
    defer slot_backing.deinit();
    const slot_iface = slot_backing.store();
    host.setSlotStore(&slot_iface);
    defer host.clearSlotStore();

    var state_backing = try lmdb_state_store.LmdbStateStore.init(allocator, args.data_dir);
    defer state_backing.deinit();
    const state_iface = state_backing.store();
    host.setDerivationStateStore(&state_iface);
    defer host.clearDerivationStateStore();

    // ── Identity ──
    const identity_sk = try loadOrCreateIdentity(allocator, args.data_dir);
    const identity_pk = try identityPubkey(identity_sk);

    // ── Listener ──
    const addr = try parseListen(args.listen);
    var server = try addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    std.debug.print(
        "[semantos-node] listening on {s} (data-dir={s})\n" ++
            "[semantos-node] identity={x:0>66}\n" ++
            "[semantos-node] (TLS terminates at Caddy — see runtime/node/Caddyfile)\n",
        .{ args.listen, args.data_dir, identityPubkeyAsBigInt(&identity_pk) },
    );

    // Accept loop (single-threaded v0.1; one connection at a time is fine
    // for a personal sovereign node — design §10.2's wallet UI is the
    // primary client).
    while (true) {
        const conn = server.accept() catch |err| {
            std.debug.print("[semantos-node] accept failed: {}\n", .{err});
            continue;
        };
        handleConnection(allocator, conn, &identity_sk, &identity_pk) catch |err| {
            std.debug.print("[semantos-node] connection error: {}\n", .{err});
        };
        conn.stream.close();
    }
}

fn identityPubkeyAsBigInt(pk: *const [33]u8) u264 {
    return std.mem.readInt(u264, pk, .big);
}

/// Per-connection lifecycle: handshake, then loop on inbound frames.
fn handleConnection(
    allocator: std.mem.Allocator,
    conn: std.net.Server.Connection,
    identity_sk: *const [32]u8,
    identity_pk: *const [33]u8,
) !void {
    wss.handshake(conn.stream) catch |err| {
        std.debug.print("[semantos-node] handshake failed: {}\n", .{err});
        return;
    };

    while (true) {
        const frame = wss.readFrame(allocator, conn.stream, MAX_FRAME_BYTES) catch |err| switch (err) {
            error.Eof => return,
            error.NotMasked, error.Fragmented, error.UnsupportedOpcode => {
                wss.writeClose(conn.stream, 1002, "protocol error") catch {};
                return;
            },
            error.PayloadTooLarge => {
                wss.writeClose(conn.stream, 1009, "frame too large") catch {};
                return;
            },
            else => return err,
        };
        defer allocator.free(frame.payload);

        switch (frame.opcode) {
            .close => {
                wss.writeClose(conn.stream, 1000, "bye") catch {};
                return;
            },
            .ping => {
                wss.writeFrame(conn.stream, .pong, frame.payload) catch return;
                continue;
            },
            .pong => continue,
            .text => {
                handleEnvelope(allocator, conn.stream, frame.payload, identity_sk, identity_pk) catch |err| {
                    std.debug.print("[semantos-node] envelope error: {}\n", .{err});
                };
            },
            else => {
                wss.writeClose(conn.stream, 1003, "unsupported opcode") catch {};
                return;
            },
        }
    }
}

/// Handle one BRC-100 text frame. Per the engine-wide peek-then-mutate
/// convention, we run parse → verify → dispatch in that order, and on
/// any failure we emit a structured reject with no state mutation.
fn handleEnvelope(
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    payload: []const u8,
    identity_sk: *const [32]u8,
    identity_pk: *const [33]u8,
) !void {
    const env = brc100.parse(allocator, payload) catch |err| {
        const msg = switch (err) {
            error.InvalidJson => "invalid json",
            error.MissingHeaders => "missing headers",
            error.MissingBody => "missing body",
            error.BodyNotString => "body must be a string",
            error.InvalidIdentityKey => "invalid identityKey",
            error.InvalidNonce => "invalid nonce",
            error.InvalidTimestamp => "invalid timestamp",
            error.InvalidSignature => "invalid signature encoding",
            error.OutOfMemory => "out of memory",
        };
        const reject = try brc100.buildReject(allocator, "", -32600, msg);
        defer allocator.free(reject);
        try wss.writeFrame(stream, .text, reject);
        return;
    };
    defer brc100.freeEnvelope(allocator, &env);

    brc100.verify(&env, allocator) catch {
        const reject = try brc100.buildReject(allocator, "", -32602, "signature rejected");
        defer allocator.free(reject);
        try wss.writeFrame(stream, .text, reject);
        return;
    };

    // Body parsed AFTER signature verification — failure-atomicity dictates
    // we never commit to a request whose authenticity isn't established.
    var rpc_id: []u8 = &.{};
    const rpc = brc100.parseRpc(allocator, &env, &rpc_id) catch {
        const reject = try brc100.buildReject(allocator, "", -32600, "body must be JSON-RPC {method,params,id}");
        defer allocator.free(reject);
        try wss.writeFrame(stream, .text, reject);
        return;
    };
    defer allocator.free(rpc_id);

    // Dispatch. v0.1 implements `getPublicKey` end-to-end; everything
    // else returns 501.
    if (std.mem.eql(u8, rpc.method, "getPublicKey")) {
        try dispatchGetPublicKey(allocator, stream, &rpc, identity_sk, identity_pk);
    } else {
        const reject = try brc100.buildReject(allocator, rpc.id, -32601, "method not implemented");
        defer allocator.free(reject);
        try wss.writeFrame(stream, .text, reject);
    }
}

fn dispatchGetPublicKey(
    allocator: std.mem.Allocator,
    stream: std.net.Stream,
    rpc: *const brc100.RpcRequest,
    identity_sk: *const [32]u8,
    identity_pk: *const [33]u8,
) !void {
    _ = identity_sk;
    var hex: [66]u8 = undefined;
    _ = std.fmt.bufPrint(&hex, "{x:0>66}", .{std.mem.readInt(u264, identity_pk, .big)}) catch unreachable;

    const result_json = try std.fmt.allocPrint(allocator, "{{\"publicKey\":\"{s}\"}}", .{hex});
    defer allocator.free(result_json);

    const resp = try brc100.buildResponse(allocator, rpc.id, result_json);
    defer allocator.free(resp);

    try wss.writeFrame(stream, .text, resp);
}

```
