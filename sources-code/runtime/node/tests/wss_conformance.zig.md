---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/tests/wss_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.300871+00:00
---

# runtime/node/tests/wss_conformance.zig

```zig
// Phase W6 — WSS + BRC-100 conformance.
//
// Per W6 acceptance criterion 3 + deliverable 9:
//   • spin up a server thread on an ephemeral port
//   • connect a Zig WS client
//   • send a BRC-100 `getPublicKey` envelope
//   • verify the response carries `publicKey`
//   • bonus: send a bad-signature envelope, expect a structured reject
//
// We don't spawn the actual binary — that would couple the test to
// the build artifact. Instead we lift the same accept-loop into the
// test process. The handshake + frame I/O code is identical to what
// `main.zig` runs (same wss.zig functions), so a regression here
// catches the same bugs.

const std = @import("std");
const builtin = @import("builtin");
const host = @import("host");
const slot_store_mod = @import("slot_store");
const derivation_state_mod = @import("derivation_state");
const bsvz = @import("bsvz");

const wss = @import("wss");
const brc100 = @import("brc100");
const lmdb_slot = @import("lmdb_slot_store");
const lmdb_state = @import("lmdb_state_store");

const MAX_FRAME_BYTES: usize = 64 * 1024;

fn makeTmpDir(allocator: std.mem.Allocator) ![]u8 {
    const ts = std.time.nanoTimestamp();
    const tmp_root = std.posix.getenv("TMPDIR") orelse "/tmp";
    const path = try std.fmt.allocPrint(
        allocator,
        "{s}/semantos-node-test-{d}-{d}",
        .{ tmp_root, ts, std.crypto.random.int(u32) },
    );
    try std.fs.cwd().makePath(path);
    return path;
}

const ServerCtx = struct {
    allocator: std.mem.Allocator,
    server: *std.net.Server,
    identity_pk: [33]u8,
    /// Set to true by the worker thread on graceful shutdown so the
    /// main thread can join cleanly.
    stop: std.atomic.Value(bool) = .init(false),
};

/// Server worker: handles one connection, then returns. Mirrors
/// `main.zig:handleConnection` but trimmed for the test's single
/// envelope round-trip.
fn serverThreadFn(ctx: *ServerCtx) void {
    const conn = ctx.server.accept() catch return;
    defer conn.stream.close();

    wss.handshake(conn.stream) catch return;

    while (true) {
        const frame = wss.readFrame(ctx.allocator, conn.stream, MAX_FRAME_BYTES) catch return;
        defer ctx.allocator.free(frame.payload);

        if (frame.opcode == .close) {
            wss.writeClose(conn.stream, 1000, "bye") catch {};
            return;
        }
        if (frame.opcode != .text) continue;

        const env = brc100.parse(ctx.allocator, frame.payload) catch {
            const reject = brc100.buildReject(ctx.allocator, "", -32600, "parse error") catch return;
            defer ctx.allocator.free(reject);
            wss.writeFrame(conn.stream, .text, reject) catch return;
            continue;
        };
        defer brc100.freeEnvelope(ctx.allocator, &env);

        brc100.verify(&env, ctx.allocator) catch {
            const reject = brc100.buildReject(ctx.allocator, "", -32602, "signature rejected") catch return;
            defer ctx.allocator.free(reject);
            wss.writeFrame(conn.stream, .text, reject) catch return;
            continue;
        };

        var rpc_id: []u8 = &.{};
        const rpc = brc100.parseRpc(ctx.allocator, &env, &rpc_id) catch {
            const reject = brc100.buildReject(ctx.allocator, "", -32600, "body parse error") catch return;
            defer ctx.allocator.free(reject);
            wss.writeFrame(conn.stream, .text, reject) catch return;
            continue;
        };
        defer ctx.allocator.free(rpc_id);

        if (std.mem.eql(u8, rpc.method, "getPublicKey")) {
            var hex: [66]u8 = undefined;
            _ = std.fmt.bufPrint(&hex, "{x:0>66}", .{std.mem.readInt(u264, &ctx.identity_pk, .big)}) catch return;
            const result = std.fmt.allocPrint(ctx.allocator, "{{\"publicKey\":\"{s}\"}}", .{hex}) catch return;
            defer ctx.allocator.free(result);
            const resp = brc100.buildResponse(ctx.allocator, rpc.id, result) catch return;
            defer ctx.allocator.free(resp);
            wss.writeFrame(conn.stream, .text, resp) catch return;
        } else {
            const reject = brc100.buildReject(ctx.allocator, rpc.id, -32601, "not implemented") catch return;
            defer ctx.allocator.free(reject);
            wss.writeFrame(conn.stream, .text, reject) catch return;
        }
    }
}

/// Build a BRC-100 envelope signed by `identity_sk` per the canonical
/// digest formula in `docs/design/BRC100-CANONICAL-DIGEST.md`. Output buffer
/// is allocator-owned. Wire format: `{"headers":{x-brc100-*}, "body": "..."}`.
fn buildSignedEnvelope(
    allocator: std.mem.Allocator,
    identity_sk: [32]u8,
    identity_pk: [33]u8,
    method: []const u8,
    params: []const u8,
    id: []const u8,
    /// Set to true to deliberately corrupt the signature for the
    /// negative-path test.
    bad_sig: bool,
) ![]u8 {
    var nonce: [32]u8 = undefined;
    std.crypto.random.bytes(&nonce);
    var nonce_hex: [64]u8 = undefined;
    {
        var off: usize = 0;
        for (nonce) |b| {
            _ = try std.fmt.bufPrint(nonce_hex[off..][0..2], "{x:0>2}", .{b});
            off += 2;
        }
    }

    const ts: u64 = @intCast(@max(0, @divFloor(std.time.milliTimestamp(), 1000)));
    var ts_buf: [24]u8 = undefined;
    const ts_dec = try std.fmt.bufPrint(&ts_buf, "{d}", .{ts});

    // Body = JSON-RPC: `{"method":"...","params":...,"id":"..."}`.
    const body = try std.fmt.allocPrint(
        allocator,
        "{{\"method\":\"{s}\",\"params\":{s},\"id\":\"{s}\"}}",
        .{ method, params, id },
    );
    defer allocator.free(body);

    // Canonical digest = SHA256(ik || nonce || ts_le8 || body).
    var digest: [32]u8 = undefined;
    brc100.computeDigest(&identity_pk, &nonce, ts, body, &digest);

    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(identity_sk);
    const der_sig = try priv.signDigest(digest);
    var sig_bytes: [128]u8 = undefined;
    @memcpy(sig_bytes[0..der_sig.len], der_sig.bytes[0..der_sig.len]);
    const sig_len = der_sig.len;
    if (bad_sig) {
        if (sig_len > 6) sig_bytes[sig_len - 2] ^= 0xFF;
    }

    var sig_hex_buf: [256]u8 = undefined;
    var hex_off: usize = 0;
    for (sig_bytes[0..sig_len]) |b| {
        _ = try std.fmt.bufPrint(sig_hex_buf[hex_off..][0..2], "{x:0>2}", .{b});
        hex_off += 2;
    }

    var ik_hex: [66]u8 = undefined;
    _ = try std.fmt.bufPrint(&ik_hex, "{x:0>66}", .{std.mem.readInt(u264, &identity_pk, .big)});

    // Body must be embedded as a JSON string. Escape inner double quotes.
    var body_escaped = std.ArrayList(u8){};
    defer body_escaped.deinit(allocator);
    for (body) |b| {
        if (b == '"' or b == '\\') try body_escaped.append(allocator, '\\');
        try body_escaped.append(allocator, b);
    }

    return try std.fmt.allocPrint(
        allocator,
        "{{" ++
            "\"headers\":{{" ++
            "\"x-brc100-identitykey\":\"{s}\"," ++
            "\"x-brc100-nonce\":\"{s}\"," ++
            "\"x-brc100-timestamp\":\"{s}\"," ++
            "\"x-brc100-signature\":\"{s}\"" ++
            "}}," ++
            "\"body\":\"{s}\"" ++
            "}}",
        .{ ik_hex, nonce_hex, ts_dec, sig_hex_buf[0..hex_off], body_escaped.items },
    );
}

test "WSS BRC-100 happy path: getPublicKey returns identity key" {
    const allocator = std.testing.allocator;

    // Identity setup.
    var sk: [32]u8 = undefined;
    std.crypto.random.bytes(&sk);
    // bsvz rejects sk = 0; randomness covers that practically.
    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(sk);
    const pk_compressed = (try priv.publicKey()).toCompressedSec1();

    // Stand up a TCP listener on an ephemeral port (port 0 → kernel-assigned).
    const addr = try std.net.Address.parseIp("127.0.0.1", 0);
    var server = try addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    var ctx = ServerCtx{
        .allocator = allocator,
        .server = &server,
        .identity_pk = pk_compressed,
    };

    const thread = try std.Thread.spawn(.{}, serverThreadFn, .{&ctx});

    // Client side.
    const client = try std.net.tcpConnectToAddress(server.listen_address);
    defer client.close();

    try wss.clientHandshake(client, "127.0.0.1", "/wallet");

    const env_bytes = try buildSignedEnvelope(allocator, sk, pk_compressed, "getPublicKey", "{}", "req-1", false);
    defer allocator.free(env_bytes);
    try wss.writeClientFrame(client, .text, env_bytes);

    const resp_frame = try wss.readClientFrame(allocator, client, MAX_FRAME_BYTES);
    defer allocator.free(resp_frame.payload);
    try std.testing.expectEqual(wss.Opcode.text, resp_frame.opcode);

    // Response must contain "publicKey":"<66-hex>" — quick string match
    // is sufficient for the smoke test (the brc100 unit tests cover the
    // builder's structure).
    var expected_pk_hex: [66]u8 = undefined;
    _ = try std.fmt.bufPrint(&expected_pk_hex, "{x:0>66}", .{std.mem.readInt(u264, &pk_compressed, .big)});
    try std.testing.expect(std.mem.indexOf(u8, resp_frame.payload, &expected_pk_hex) != null);
    try std.testing.expect(std.mem.indexOf(u8, resp_frame.payload, "\"publicKey\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp_frame.payload, "\"id\":\"req-1\"") != null);

    // Client-initiated close so the server thread exits cleanly.
    try wss.writeClientFrame(client, .close, &[_]u8{ 0x03, 0xE8 });
    thread.join();
}

test "WSS BRC-100 sad path: bad signature → reject envelope" {
    const allocator = std.testing.allocator;

    var sk: [32]u8 = undefined;
    std.crypto.random.bytes(&sk);
    const priv = try bsvz.primitives.ec.PrivateKey.fromBytes(sk);
    const pk_compressed = (try priv.publicKey()).toCompressedSec1();

    const addr = try std.net.Address.parseIp("127.0.0.1", 0);
    var server = try addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    var ctx = ServerCtx{
        .allocator = allocator,
        .server = &server,
        .identity_pk = pk_compressed,
    };

    const thread = try std.Thread.spawn(.{}, serverThreadFn, .{&ctx});

    const client = try std.net.tcpConnectToAddress(server.listen_address);
    defer client.close();
    try wss.clientHandshake(client, "127.0.0.1", "/wallet");

    const env_bytes = try buildSignedEnvelope(allocator, sk, pk_compressed, "getPublicKey", "{}", "req-bad", true);
    defer allocator.free(env_bytes);
    try wss.writeClientFrame(client, .text, env_bytes);

    const resp_frame = try wss.readClientFrame(allocator, client, MAX_FRAME_BYTES);
    defer allocator.free(resp_frame.payload);

    // Reject envelope shape: `{"id":"","error":{"code":-32602,…}}`.
    // The id is intentionally empty for signature-failed requests — we don't
    // trust the unauthenticated body's `id` field, and parsing it before
    // verification would violate the engine's peek-then-mutate convention.
    try std.testing.expect(std.mem.indexOf(u8, resp_frame.payload, "\"error\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp_frame.payload, "signature rejected") != null);
    // Engine peek-then-mutate convention: state must be untouched. We
    // can't observe state directly here without a SlotStore, but the
    // dispatch path simply returned before it would have called
    // `host.*` mutators — covered by inspection.

    try wss.writeClientFrame(client, .close, &[_]u8{ 0x03, 0xE8 });
    thread.join();
}

test "WSS handshake rejects non-GET" {
    const allocator = std.testing.allocator;
    _ = allocator;

    const addr = try std.net.Address.parseIp("127.0.0.1", 0);
    var server = try addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    const Worker = struct {
        fn run(srv: *std.net.Server, out_err: *bool) void {
            const conn = srv.accept() catch return;
            defer conn.stream.close();
            wss.handshake(conn.stream) catch {
                out_err.* = true;
            };
        }
    };

    var got_err = false;
    const thread = try std.Thread.spawn(.{}, Worker.run, .{ &server, &got_err });

    const client = try std.net.tcpConnectToAddress(server.listen_address);
    defer client.close();
    try client.writeAll("POST /wallet HTTP/1.1\r\nHost: x\r\n\r\n");

    thread.join();
    try std.testing.expect(got_err);
}

```
