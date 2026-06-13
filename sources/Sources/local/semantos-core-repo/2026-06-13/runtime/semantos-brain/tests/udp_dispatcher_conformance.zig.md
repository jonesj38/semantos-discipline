---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tests/udp_dispatcher_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.190699+00:00
---

# runtime/semantos-brain/tests/udp_dispatcher_conformance.zig

```zig
// udp_dispatcher_conformance.zig — Phase U.2 end-to-end tests
//
// Drives the dispatcher against real loopback UDP sockets to verify the
// full receive path (parse → HMAC verify → replay check → callback dispatch)
// and the multicast extension (two dispatchers in the same multicast group
// on localhost gossip via the loopback iface).
//
// These tests bind to ephemeral ports (port 0 → kernel-assigned) to avoid
// collisions in parallel test runs.

const std = @import("std");
const proto = @import("udp_protocol");
const dispatcher_mod = @import("udp_dispatcher");
const routing = @import("routing");
const mnca_tile = @import("mnca_tile");
const cell_transform = @import("cell_transform");

const UdpDispatcher = dispatcher_mod.UdpDispatcher;
const Handlers = dispatcher_mod.Handlers;
const Config = dispatcher_mod.Config;

const testing = std.testing;

// ── Test shared-secret table ──────────────────────────────────────────────
//
// In v1 the dispatcher looks up the per-peer ECDH-derived shared secret via
// `PeerSharedSecretLookup`. Tests install a fixed table mapping peer cellId
// → 32-byte key, plus an "unknown peer" case where lookup returns null.

const TestSecretTable = struct {
    pub const Entry = struct {
        cell_id: [proto.CELL_ID_LEN]u8,
        key: [32]u8,
    };
    entries: []const Entry,

    pub fn lookup(peer_cell_id: *const [proto.CELL_ID_LEN]u8, ud: *anyopaque) ?[32]u8 {
        const self: *TestSecretTable = @ptrCast(@alignCast(ud));
        for (self.entries) |e| {
            if (std.mem.eql(u8, &e.cell_id, peer_cell_id)) return e.key;
        }
        return null;
    }
};

// ── Test handler recorder ─────────────────────────────────────────────────
//
// Captures dispatched payloads so tests can assert on what arrived. One
// vector per type plus a counter so we can also verify "no spurious dispatch".

const Recorder = struct {
    cell_sync: std.ArrayList(u8) = .{},
    topic_broadcast: std.ArrayList(u8) = .{},
    heartbeat: std.ArrayList(u8) = .{},
    reply: std.ArrayList(u8) = .{},
    cell_sync_count: u32 = 0,
    topic_broadcast_count: u32 = 0,
    heartbeat_count: u32 = 0,
    reply_count: u32 = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Recorder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Recorder) void {
        self.cell_sync.deinit(self.allocator);
        self.topic_broadcast.deinit(self.allocator);
        self.heartbeat.deinit(self.allocator);
        self.reply.deinit(self.allocator);
    }

    fn onCellSync(_: *const [proto.CELL_ID_LEN]u8, payload: []const u8, ud: *anyopaque) void {
        const self: *Recorder = @ptrCast(@alignCast(ud));
        self.cell_sync_count += 1;
        self.cell_sync.appendSlice(self.allocator, payload) catch {};
    }

    fn onTopicBroadcast(_: *const [proto.CELL_ID_LEN]u8, payload: []const u8, ud: *anyopaque) void {
        const self: *Recorder = @ptrCast(@alignCast(ud));
        self.topic_broadcast_count += 1;
        self.topic_broadcast.appendSlice(self.allocator, payload) catch {};
    }

    fn onHeartbeat(
        _: *const [proto.CELL_ID_LEN]u8,
        _: *const std.posix.sockaddr,
        _: std.posix.socklen_t,
        payload: []const u8,
        ud: *anyopaque,
    ) void {
        const self: *Recorder = @ptrCast(@alignCast(ud));
        self.heartbeat_count += 1;
        self.heartbeat.appendSlice(self.allocator, payload) catch {};
    }

    fn onReply(
        _: *const [proto.CELL_ID_LEN]u8,
        _: *const [proto.NONCE_LEN]u8,
        payload: []const u8,
        ud: *anyopaque,
    ) void {
        const self: *Recorder = @ptrCast(@alignCast(ud));
        self.reply_count += 1;
        self.reply.appendSlice(self.allocator, payload) catch {};
    }

    pub fn handlers(self: *Recorder) Handlers {
        return .{
            .ud = self,
            .on_cell_sync = onCellSync,
            .on_topic_broadcast = onTopicBroadcast,
            .on_heartbeat = onHeartbeat,
            .on_reply = onReply,
        };
    }
};

// ── Helpers ───────────────────────────────────────────────────────────────

/// Wait up to `timeout_ms` for `dispatcher.socket_fd` to be readable, then
/// drain it once.  Used by every test to bound the time we'll wait for a
/// datagram before declaring failure.
fn pumpOnce(dispatcher: *UdpDispatcher, timeout_ms: i32) !void {
    var pfd = [_]std.posix.pollfd{.{
        .fd = dispatcher.socket_fd,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    const ready = try std.posix.poll(&pfd, timeout_ms);
    if (ready == 0) return; // timeout — caller decides if that's a failure
    try dispatcher.handleDatagramReady();
}

/// Bind a dispatcher to ::1 on an ephemeral port (port 0 → kernel assigns)
/// and return the resolved port via getsockname. IPv6-only since Phase U.2
/// went v6-only to align with the IPv6 Forum's call for v6-only as the
/// Agentic-AI substrate.
fn boundPort(d: *UdpDispatcher) !u16 {
    var addr: std.posix.sockaddr.in6 = undefined;
    var len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in6);
    try std.posix.getsockname(d.socket_fd, @ptrCast(&addr), &len);
    return std.mem.bigToNative(u16, addr.port);
}

// ── Tests ─────────────────────────────────────────────────────────────────

test "conformance: unicast round-trip — heartbeat dispatched to correct handler" {
    const allocator = testing.allocator;

    const cid_a: [proto.CELL_ID_LEN]u8 = .{0xAA} ** proto.CELL_ID_LEN;
    const cid_b: [proto.CELL_ID_LEN]u8 = .{0xBB} ** proto.CELL_ID_LEN;
    const shared: [32]u8 = .{0x42} ** 32;

    var table_b = TestSecretTable{
        .entries = &.{.{ .cell_id = cid_a, .key = shared }},
    };
    var rec_b = Recorder.init(allocator);
    defer rec_b.deinit();

    var d_b = try UdpDispatcher.init(
        allocator,
        .{ .port = 0, .reuse_port = false },
        cid_b,
        .{ .lookup_fn = TestSecretTable.lookup, .ud = &table_b },
        rec_b.handlers(),
    );
    defer d_b.deinit();

    const port_b = try boundPort(d_b);

    // Sender: dispatcher A that knows B's port via a Config.port=0 send-only
    // configuration. We don't actually need to bind A to a known port for
    // this test — we just need A to sendto B.
    var table_a = TestSecretTable{ .entries = &.{} };
    var rec_a = Recorder.init(allocator);
    defer rec_a.deinit();

    var d_a = try UdpDispatcher.init(
        allocator,
        .{ .port = 0, .reuse_port = false },
        cid_a,
        .{ .lookup_fn = TestSecretTable.lookup, .ud = &table_a },
        rec_a.handlers(),
    );
    defer d_a.deinit();

    const dest = try std.net.Address.parseIp6("::1", port_b);
    try d_a.sendTo(.heartbeat, "hello-b", &shared, dest);

    try pumpOnce(d_b, 500);

    try testing.expectEqual(@as(u32, 1), rec_b.heartbeat_count);
    try testing.expectEqualStrings("hello-b", rec_b.heartbeat.items);
    try testing.expectEqual(@as(u64, 1), d_b.stats.dispatched);
    try testing.expectEqual(@as(u64, 0), d_b.stats.dropped_bad_hmac);
}

test "conformance: bad HMAC dropped silently" {
    const allocator = testing.allocator;

    const cid_a: [proto.CELL_ID_LEN]u8 = .{0xAA} ** proto.CELL_ID_LEN;
    const cid_b: [proto.CELL_ID_LEN]u8 = .{0xBB} ** proto.CELL_ID_LEN;
    const correct_key: [32]u8 = .{0x42} ** 32;
    const wrong_key: [32]u8 = .{0x99} ** 32;

    var table_b = TestSecretTable{
        .entries = &.{.{ .cell_id = cid_a, .key = correct_key }},
    };
    var rec_b = Recorder.init(allocator);
    defer rec_b.deinit();

    var d_b = try UdpDispatcher.init(
        allocator,
        .{ .port = 0, .reuse_port = false },
        cid_b,
        .{ .lookup_fn = TestSecretTable.lookup, .ud = &table_b },
        rec_b.handlers(),
    );
    defer d_b.deinit();

    const port_b = try boundPort(d_b);

    // Hand-craft a datagram using the WRONG key (simulates an attacker who
    // doesn't share B's secret).
    var nonce: [proto.NONCE_LEN]u8 = .{0x01} ** proto.NONCE_LEN;
    var buf: [proto.UDP_MAX_DATAGRAM]u8 = undefined;
    const dgram = proto.buildDatagram(&buf, .cell_sync, &nonce, &cid_a, "evil", &wrong_key);

    const send_sock = try std.posix.socket(std.posix.AF.INET6, std.posix.SOCK.DGRAM, 0);
    defer std.posix.close(send_sock);
    const dest = try std.net.Address.parseIp6("::1", port_b);
    _ = try std.posix.sendto(send_sock, dgram, 0, &dest.any, dest.getOsSockLen());

    try pumpOnce(d_b, 500);

    try testing.expectEqual(@as(u32, 0), rec_b.cell_sync_count);
    try testing.expectEqual(@as(u64, 1), d_b.stats.dropped_bad_hmac);
    try testing.expectEqual(@as(u64, 0), d_b.stats.dispatched);
}

test "conformance: replayed nonce dropped on second arrival" {
    const allocator = testing.allocator;

    const cid_a: [proto.CELL_ID_LEN]u8 = .{0xAA} ** proto.CELL_ID_LEN;
    const cid_b: [proto.CELL_ID_LEN]u8 = .{0xBB} ** proto.CELL_ID_LEN;
    const key: [32]u8 = .{0x42} ** 32;

    var table_b = TestSecretTable{
        .entries = &.{.{ .cell_id = cid_a, .key = key }},
    };
    var rec_b = Recorder.init(allocator);
    defer rec_b.deinit();

    var d_b = try UdpDispatcher.init(
        allocator,
        .{ .port = 0, .reuse_port = false },
        cid_b,
        .{ .lookup_fn = TestSecretTable.lookup, .ud = &table_b },
        rec_b.handlers(),
    );
    defer d_b.deinit();

    const port_b = try boundPort(d_b);

    // Same nonce twice — second must be dropped.
    var nonce: [proto.NONCE_LEN]u8 = .{0xCC} ** proto.NONCE_LEN;
    var buf: [proto.UDP_MAX_DATAGRAM]u8 = undefined;
    const dgram = proto.buildDatagram(&buf, .topic_broadcast, &nonce, &cid_a, "replay-me", &key);

    const send_sock = try std.posix.socket(std.posix.AF.INET6, std.posix.SOCK.DGRAM, 0);
    defer std.posix.close(send_sock);
    const dest = try std.net.Address.parseIp6("::1", port_b);
    _ = try std.posix.sendto(send_sock, dgram, 0, &dest.any, dest.getOsSockLen());
    _ = try std.posix.sendto(send_sock, dgram, 0, &dest.any, dest.getOsSockLen());

    try pumpOnce(d_b, 500);
    try pumpOnce(d_b, 100);

    try testing.expectEqual(@as(u32, 1), rec_b.topic_broadcast_count);
    try testing.expectEqual(@as(u64, 1), d_b.stats.dropped_replay);
}

test "conformance: type dispatch — each type lands in its own handler" {
    const allocator = testing.allocator;

    const cid_a: [proto.CELL_ID_LEN]u8 = .{0xAA} ** proto.CELL_ID_LEN;
    const cid_b: [proto.CELL_ID_LEN]u8 = .{0xBB} ** proto.CELL_ID_LEN;
    const key: [32]u8 = .{0x42} ** 32;

    var table_b = TestSecretTable{
        .entries = &.{.{ .cell_id = cid_a, .key = key }},
    };
    var rec_b = Recorder.init(allocator);
    defer rec_b.deinit();

    var d_b = try UdpDispatcher.init(
        allocator,
        .{ .port = 0, .reuse_port = false },
        cid_b,
        .{ .lookup_fn = TestSecretTable.lookup, .ud = &table_b },
        rec_b.handlers(),
    );
    defer d_b.deinit();

    const port_b = try boundPort(d_b);

    var d_a = try UdpDispatcher.init(
        allocator,
        .{ .port = 0, .reuse_port = false },
        cid_a,
        .{ .lookup_fn = TestSecretTable.lookup, .ud = &table_b }, // not used on send path
        Handlers{ .ud = undefined },
    );
    defer d_a.deinit();

    const dest = try std.net.Address.parseIp6("::1", port_b);

    try d_a.sendTo(.cell_sync, "sync-payload", &key, dest);
    try d_a.sendTo(.topic_broadcast, "topic-payload", &key, dest);
    try d_a.sendTo(.heartbeat, "beat", &key, dest);
    try d_a.sendTo(.reply, "reply-payload", &key, dest);

    // Drain — call pumpOnce a few times with short timeout to ensure all
    // four datagrams are processed even if they arrive across poll cycles.
    var i: u8 = 0;
    while (i < 5) : (i += 1) try pumpOnce(d_b, 100);

    try testing.expectEqual(@as(u32, 1), rec_b.cell_sync_count);
    try testing.expectEqual(@as(u32, 1), rec_b.topic_broadcast_count);
    try testing.expectEqual(@as(u32, 1), rec_b.heartbeat_count);
    try testing.expectEqual(@as(u32, 1), rec_b.reply_count);
    try testing.expectEqualStrings("sync-payload", rec_b.cell_sync.items);
    try testing.expectEqualStrings("topic-payload", rec_b.topic_broadcast.items);
    try testing.expectEqualStrings("beat", rec_b.heartbeat.items);
    try testing.expectEqualStrings("reply-payload", rec_b.reply.items);
}

test "conformance: unknown peer (no shared secret) dropped" {
    const allocator = testing.allocator;

    const cid_a: [proto.CELL_ID_LEN]u8 = .{0xAA} ** proto.CELL_ID_LEN;
    const cid_b: [proto.CELL_ID_LEN]u8 = .{0xBB} ** proto.CELL_ID_LEN;
    const key: [32]u8 = .{0x42} ** 32;

    // B's table has NO entry for A → lookup returns null.
    var table_b = TestSecretTable{ .entries = &.{} };
    var rec_b = Recorder.init(allocator);
    defer rec_b.deinit();

    var d_b = try UdpDispatcher.init(
        allocator,
        .{ .port = 0, .reuse_port = false },
        cid_b,
        .{ .lookup_fn = TestSecretTable.lookup, .ud = &table_b },
        rec_b.handlers(),
    );
    defer d_b.deinit();

    const port_b = try boundPort(d_b);

    var nonce: [proto.NONCE_LEN]u8 = .{0x77} ** proto.NONCE_LEN;
    var buf: [proto.UDP_MAX_DATAGRAM]u8 = undefined;
    const dgram = proto.buildDatagram(&buf, .heartbeat, &nonce, &cid_a, "from-unknown", &key);

    const send_sock = try std.posix.socket(std.posix.AF.INET6, std.posix.SOCK.DGRAM, 0);
    defer std.posix.close(send_sock);
    const dest = try std.net.Address.parseIp6("::1", port_b);
    _ = try std.posix.sendto(send_sock, dgram, 0, &dest.any, dest.getOsSockLen());

    try pumpOnce(d_b, 500);

    try testing.expectEqual(@as(u32, 0), rec_b.heartbeat_count);
    try testing.expectEqual(@as(u64, 1), d_b.stats.dropped_no_peer_secret);
}

test "conformance: own datagrams (self-identity) are ignored on loopback" {
    const allocator = testing.allocator;

    const cid_self: [proto.CELL_ID_LEN]u8 = .{0xEE} ** proto.CELL_ID_LEN;
    const key: [32]u8 = .{0x42} ** 32;

    var table = TestSecretTable{
        .entries = &.{.{ .cell_id = cid_self, .key = key }}, // shouldn't matter
    };
    var rec = Recorder.init(allocator);
    defer rec.deinit();

    var d = try UdpDispatcher.init(
        allocator,
        .{ .port = 0, .reuse_port = false },
        cid_self,
        .{ .lookup_fn = TestSecretTable.lookup, .ud = &table },
        rec.handlers(),
    );
    defer d.deinit();

    const port = try boundPort(d);

    // d sends to itself.
    const dest = try std.net.Address.parseIp6("::1", port);
    try d.sendTo(.heartbeat, "self", &key, dest);

    try pumpOnce(d, 300);

    // Datagram was received (stats.received incremented) but the self-id
    // guard prevented dispatch.
    try testing.expectEqual(@as(u64, 1), d.stats.received);
    try testing.expectEqual(@as(u32, 0), rec.heartbeat_count);
    try testing.expectEqual(@as(u64, 0), d.stats.dispatched);
}

test "conformance: multicast loopback — two dispatchers in the same group see each other" {
    const allocator = testing.allocator;

    // Both dispatchers bind to the SAME multicast port; SO_REUSEPORT lets
    // them coexist on one host. Each joins the same admin-local IPv4
    // multicast group. multicast_loopback=true so localhost iface delivers
    // the sender's datagrams back to peer sockets in the group.
    const group = "ff15::5e:1";
    const port: u16 = 47100;

    const cid_a: [proto.CELL_ID_LEN]u8 = .{0xAA} ** proto.CELL_ID_LEN;
    const cid_b: [proto.CELL_ID_LEN]u8 = .{0xBB} ** proto.CELL_ID_LEN;
    const key: [32]u8 = .{0x42} ** 32;

    var table_pair = TestSecretTable{
        .entries = &.{
            .{ .cell_id = cid_a, .key = key },
            .{ .cell_id = cid_b, .key = key },
        },
    };

    var rec_a = Recorder.init(allocator);
    defer rec_a.deinit();
    var rec_b = Recorder.init(allocator);
    defer rec_b.deinit();

    var d_a = try UdpDispatcher.init(
        allocator,
        .{
            .port = port,
            .multicast_group = group,
            .multicast_loopback = true,
            .reuse_port = true,
        },
        cid_a,
        .{ .lookup_fn = TestSecretTable.lookup, .ud = &table_pair },
        rec_a.handlers(),
    );
    defer d_a.deinit();

    var d_b = try UdpDispatcher.init(
        allocator,
        .{
            .port = port,
            .multicast_group = group,
            .multicast_loopback = true,
            .reuse_port = true,
        },
        cid_b,
        .{ .lookup_fn = TestSecretTable.lookup, .ud = &table_pair },
        rec_b.handlers(),
    );
    defer d_b.deinit();

    // A broadcasts. Both A and B sockets receive (loopback on), but A's
    // self-identity guard drops its own datagram; only B dispatches.
    try d_a.broadcast(.topic_broadcast, "hello-mesh", &key);

    // Drain both — each socket independently.
    var i: u8 = 0;
    while (i < 5) : (i += 1) {
        try pumpOnce(d_a, 100);
        try pumpOnce(d_b, 100);
    }

    try testing.expectEqual(@as(u32, 0), rec_a.topic_broadcast_count);
    try testing.expectEqual(@as(u32, 1), rec_b.topic_broadcast_count);
    try testing.expectEqualStrings("hello-mesh", rec_b.topic_broadcast.items);
}

test "conformance: broadcast without multicast group returns error" {
    const allocator = testing.allocator;

    const cid: [proto.CELL_ID_LEN]u8 = .{0xCC} ** proto.CELL_ID_LEN;
    const key: [32]u8 = .{0x42} ** 32;
    var table = TestSecretTable{ .entries = &.{} };
    var rec = Recorder.init(allocator);
    defer rec.deinit();

    var d = try UdpDispatcher.init(
        allocator,
        .{ .port = 0, .reuse_port = false },
        cid,
        .{ .lookup_fn = TestSecretTable.lookup, .ud = &table },
        rec.handlers(),
    );
    defer d.deinit();

    try testing.expectError(error.MulticastNotEnabled, d.broadcast(.heartbeat, "x", &key));
}

// ════════════════════════════════════════════════════════════════════════════
// End-to-end source-routed cell traversal — the demo's heartbeat.
//
// A routed cell is EMITTED by an originator, FORWARDED by relay node(s), and
// DELIVERED at the final destination, over real IPv6 multicast loopback
// (the production multicast-and-filter path, brief §15.2). Each node runs
// `routing.processHop` in its cell_sync handler: not-my-hop drops silently,
// forward re-broadcasts, final-destination records delivery. This is the
// integration that flips L3-F from ⚠ to ✓.
// ════════════════════════════════════════════════════════════════════════════

/// A mesh node that relays/delivers source-routed cells, optionally running
/// a transform-on-hop (compute) before forwarding. Routes through
/// cell_transform.processHopWithTransform (the same path the mesh-node uses);
/// a PURE_RELAY registry => plain forwarding (the L3-F traversal case).
const RoutingNode = struct {
    own_bca: [16]u8,
    key: [32]u8,
    registry: cell_transform.TransformRegistry = cell_transform.PURE_RELAY,
    dispatcher: ?*UdpDispatcher = null,
    delivered: bool = false,
    delivered_cell: [routing.CELL_SIZE]u8 = undefined,
    forwarded_count: u32 = 0,
    transformed_count: u32 = 0,
    dropped_count: u32 = 0,

    fn onCellSync(
        _: *const [proto.CELL_ID_LEN]u8,
        payload: []const u8,
        ud: *anyopaque,
    ) void {
        const self: *RoutingNode = @ptrCast(@alignCast(ud));
        var out: [routing.CELL_SIZE]u8 = undefined;
        switch (cell_transform.processHopWithTransform(payload, &self.own_bca, &out, &self.registry)) {
            .not_routed => {},
            .delivered => {
                self.delivered = true;
                @memcpy(&self.delivered_cell, payload[0..routing.CELL_SIZE]);
            },
            .forwarded => |f| {
                self.forwarded_count += 1;
                if (f.transformed) self.transformed_count += 1;
                if (self.dispatcher) |d| {
                    d.broadcast(.cell_sync, out[0..routing.CELL_SIZE], &self.key) catch {};
                }
            },
            .dropped => self.dropped_count += 1,
        }
    }

    fn handlers(self: *RoutingNode) Handlers {
        return .{ .ud = self, .on_cell_sync = onCellSync };
    }
};

fn writeU32le(buf: []u8, off: usize, v: u32) void {
    std.mem.writeInt(u32, buf[off..][0..4], v, .little);
}

/// Pump O, R, D once each, up to `rounds` times, stopping when `dst.delivered`.
fn pumpUntilDelivered(nodes: []const *UdpDispatcher, dst: *const RoutingNode, rounds: u8) !void {
    var i: u8 = 0;
    while (i < rounds and !dst.delivered) : (i += 1) {
        for (nodes) |d| try pumpOnce(d, 100);
    }
}

test "conformance: single-relay routed cell traverses emit→forward→deliver" {
    const allocator = testing.allocator;
    const group = "ff15::5e:1";
    const port: u16 = 47131; // distinct from other multicast tests

    const cid_o: [proto.CELL_ID_LEN]u8 = .{0x0A} ** proto.CELL_ID_LEN;
    const cid_r: [proto.CELL_ID_LEN]u8 = .{0x0B} ** proto.CELL_ID_LEN;
    const cid_d: [proto.CELL_ID_LEN]u8 = .{0x0C} ** proto.CELL_ID_LEN;
    const key: [32]u8 = .{0x42} ** 32;
    const bca_r: [16]u8 = .{0xB1} ** 16;
    const bca_d: [16]u8 = .{0xD1} ** 16;

    var table = TestSecretTable{ .entries = &.{
        .{ .cell_id = cid_o, .key = key },
        .{ .cell_id = cid_r, .key = key },
        .{ .cell_id = cid_d, .key = key },
    } };

    var node_r = RoutingNode{ .own_bca = bca_r, .key = key };
    var node_d = RoutingNode{ .own_bca = bca_d, .key = key };

    const mc: Config = .{ .port = port, .multicast_group = group, .multicast_loopback = true, .reuse_port = true };

    var d_o = try UdpDispatcher.init(allocator, mc, cid_o, .{ .lookup_fn = TestSecretTable.lookup, .ud = &table }, .{ .ud = undefined });
    defer d_o.deinit();
    var d_r = try UdpDispatcher.init(allocator, mc, cid_r, .{ .lookup_fn = TestSecretTable.lookup, .ud = &table }, node_r.handlers());
    defer d_r.deinit();
    var d_d = try UdpDispatcher.init(allocator, mc, cid_d, .{ .lookup_fn = TestSecretTable.lookup, .ud = &table }, node_d.handlers());
    defer d_d.deinit();
    node_r.dispatcher = d_r;
    node_d.dispatcher = d_d;

    // Originator builds a 1-relay routed cell: NEXT_HOP=R, FINAL_DEST=D,
    // SEGMENTS_LEFT=1. Stamp a payload marker to prove the cell survives intact.
    var cell = [_]u8{0} ** routing.CELL_SIZE;
    cell[routing.OFF_ROUTING_MODE] = @intFromEnum(routing.RoutingMode.source_routed);
    writeU32le(&cell, routing.OFF_ROUTING_VERSION, routing.ROUTING_VERSION_V1);
    writeU32le(&cell, routing.OFF_SEGMENTS_LEFT, 1);
    writeU32le(&cell, routing.OFF_HOP_COUNT_BUDGET, 4);
    @memcpy(cell[routing.OFF_NEXT_HOP_BCA..][0..16], &bca_r);
    @memcpy(cell[routing.OFF_FINAL_DEST_BCA..][0..16], &bca_d);
    const marker = [_]u8{ 0xCA, 0xFE, 0xBA, 0xBE };
    @memcpy(cell[256..260], &marker);
    _ = routing.setRoutingChecksum(&cell);

    try d_o.broadcast(.cell_sync, &cell, &key);

    var pumps = [_]*UdpDispatcher{ d_o, d_r, d_d };
    try pumpUntilDelivered(&pumps, &node_d, 16);

    // The relay forwarded exactly once; the destination delivered.
    try testing.expectEqual(@as(u32, 1), node_r.forwarded_count);
    try testing.expect(node_d.delivered);
    // The delivered cell: SEGMENTS_LEFT spent to 0, NEXT_HOP rotated to D,
    // payload marker intact (the cell crossed two hops unre-encoded).
    try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, node_d.delivered_cell[routing.OFF_SEGMENTS_LEFT..][0..4], .little));
    try testing.expect(std.mem.eql(u8, node_d.delivered_cell[routing.OFF_NEXT_HOP_BCA..][0..16], &bca_d));
    try testing.expect(std.mem.eql(u8, node_d.delivered_cell[256..260], &marker));
}

test "conformance: two-relay routed cell rotates segments O→R1→R2→D" {
    const allocator = testing.allocator;
    const group = "ff15::5e:1";
    const port: u16 = 47132;

    const cid_o: [proto.CELL_ID_LEN]u8 = .{0x1A} ** proto.CELL_ID_LEN;
    const cid_r1: [proto.CELL_ID_LEN]u8 = .{0x1B} ** proto.CELL_ID_LEN;
    const cid_r2: [proto.CELL_ID_LEN]u8 = .{0x1C} ** proto.CELL_ID_LEN;
    const cid_d: [proto.CELL_ID_LEN]u8 = .{0x1D} ** proto.CELL_ID_LEN;
    const key: [32]u8 = .{0x42} ** 32;
    const bca_r1: [16]u8 = .{0x11} ** 16;
    const bca_r2: [16]u8 = .{0x22} ** 16;
    const bca_d: [16]u8 = .{0x33} ** 16;

    var table = TestSecretTable{ .entries = &.{
        .{ .cell_id = cid_o, .key = key },
        .{ .cell_id = cid_r1, .key = key },
        .{ .cell_id = cid_r2, .key = key },
        .{ .cell_id = cid_d, .key = key },
    } };

    var node_r1 = RoutingNode{ .own_bca = bca_r1, .key = key };
    var node_r2 = RoutingNode{ .own_bca = bca_r2, .key = key };
    var node_d = RoutingNode{ .own_bca = bca_d, .key = key };

    const mc: Config = .{ .port = port, .multicast_group = group, .multicast_loopback = true, .reuse_port = true };

    var d_o = try UdpDispatcher.init(allocator, mc, cid_o, .{ .lookup_fn = TestSecretTable.lookup, .ud = &table }, .{ .ud = undefined });
    defer d_o.deinit();
    var d_r1 = try UdpDispatcher.init(allocator, mc, cid_r1, .{ .lookup_fn = TestSecretTable.lookup, .ud = &table }, node_r1.handlers());
    defer d_r1.deinit();
    var d_r2 = try UdpDispatcher.init(allocator, mc, cid_r2, .{ .lookup_fn = TestSecretTable.lookup, .ud = &table }, node_r2.handlers());
    defer d_r2.deinit();
    var d_d = try UdpDispatcher.init(allocator, mc, cid_d, .{ .lookup_fn = TestSecretTable.lookup, .ud = &table }, node_d.handlers());
    defer d_d.deinit();
    node_r1.dispatcher = d_r1;
    node_r2.dispatcher = d_r2;
    node_d.dispatcher = d_d;

    // Two inline typed segments [R1, R2] (PATH_IN_PAYLOAD) so each relay
    // routes to the next; FINAL_DEST=D, SEGMENTS_LEFT=2. Type-hashes are
    // zeroed (validate_type=false in v1, no transform between hops).
    var cell = [_]u8{0} ** routing.CELL_SIZE;
    cell[routing.OFF_ROUTING_MODE] = @intFromEnum(routing.RoutingMode.source_routed);
    writeU32le(&cell, routing.OFF_ROUTING_VERSION, routing.ROUTING_VERSION_V1);
    writeU32le(&cell, routing.OFF_ROUTING_FLAGS, routing.FLAG_PATH_IN_PAYLOAD);
    writeU32le(&cell, routing.OFF_SEGMENTS_LEFT, 2);
    writeU32le(&cell, routing.OFF_HOP_COUNT_BUDGET, 6);
    @memcpy(cell[routing.OFF_NEXT_HOP_BCA..][0..16], &bca_r1);
    @memcpy(cell[routing.OFF_FINAL_DEST_BCA..][0..16], &bca_d);
    // Inline segments: N=2, payloadStartsAt=4+2*48=100, then (bca, typeHash) tuples.
    std.mem.writeInt(u16, cell[256..][0..2], 2, .little);
    std.mem.writeInt(u16, cell[258..][0..2], 100, .little);
    @memcpy(cell[260..][0..16], &bca_r1); // segment 0 BCA (typeHash bytes left 0)
    @memcpy(cell[308..][0..16], &bca_r2); // segment 1 BCA (offset 256+4+48)
    _ = routing.setRoutingChecksum(&cell);

    try d_o.broadcast(.cell_sync, &cell, &key);

    var pumps = [_]*UdpDispatcher{ d_o, d_r1, d_r2, d_d };
    try pumpUntilDelivered(&pumps, &node_d, 24);

    try testing.expectEqual(@as(u32, 1), node_r1.forwarded_count);
    try testing.expectEqual(@as(u32, 1), node_r2.forwarded_count);
    try testing.expect(node_d.delivered);
    try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, node_d.delivered_cell[routing.OFF_SEGMENTS_LEFT..][0..4], .little));
    try testing.expect(std.mem.eql(u8, node_d.delivered_cell[routing.OFF_NEXT_HOP_BCA..][0..16], &bca_d));
}

test "conformance: transform-on-hop — relay computes (stepTile) then forwards; dest gets the computed cell" {
    const allocator = testing.allocator;
    const group = "ff15::5e:1";
    const port: u16 = 47133;

    const cid_o: [proto.CELL_ID_LEN]u8 = .{0x2A} ** proto.CELL_ID_LEN;
    const cid_r: [proto.CELL_ID_LEN]u8 = .{0x2B} ** proto.CELL_ID_LEN;
    const cid_d: [proto.CELL_ID_LEN]u8 = .{0x2C} ** proto.CELL_ID_LEN;
    const key: [32]u8 = .{0x42} ** 32;
    const bca_r: [16]u8 = .{0xB2} ** 16;
    const bca_d: [16]u8 = .{0xD2} ** 16;

    var table = TestSecretTable{ .entries = &.{
        .{ .cell_id = cid_o, .key = key },
        .{ .cell_id = cid_r, .key = key },
        .{ .cell_id = cid_d, .key = key },
    } };

    // R is a tile-owner relay: registry maps mnca.tile.tick → mnca.snapshot
    // via the MNCA tile-advance transform (stepTile). D is a pure consumer.
    const entries = [_]cell_transform.TransformEntry{cell_transform.tileAdvanceEntry()};
    var node_r = RoutingNode{ .own_bca = bca_r, .key = key, .registry = .{ .entries = &entries } };
    var node_d = RoutingNode{ .own_bca = bca_d, .key = key };

    const mc: Config = .{ .port = port, .multicast_group = group, .multicast_loopback = true, .reuse_port = true };

    var d_o = try UdpDispatcher.init(allocator, mc, cid_o, .{ .lookup_fn = TestSecretTable.lookup, .ud = &table }, .{ .ud = undefined });
    defer d_o.deinit();
    var d_r = try UdpDispatcher.init(allocator, mc, cid_r, .{ .lookup_fn = TestSecretTable.lookup, .ud = &table }, node_r.handlers());
    defer d_r.deinit();
    var d_d = try UdpDispatcher.init(allocator, mc, cid_d, .{ .lookup_fn = TestSecretTable.lookup, .ud = &table }, node_d.handlers());
    defer d_d.deinit();
    node_r.dispatcher = d_r;
    node_d.dispatcher = d_d;

    // Originator: a tile.tick cell routed O→R→D with a 7x7 tile whose (3,3)
    // has exactly 3 alive Moore-neighbours → it should be BORN next tick.
    var cell = [_]u8{0} ** routing.CELL_SIZE;
    @memcpy(cell[routing.TYPE_HASH_OFFSET..][0..32], &cell_transform.mncaTypeHash("mnca.tile.tick"));
    cell[routing.OFF_ROUTING_MODE] = @intFromEnum(routing.RoutingMode.source_routed);
    std.mem.writeInt(u32, cell[routing.OFF_ROUTING_VERSION..][0..4], routing.ROUTING_VERSION_V1, .little);
    std.mem.writeInt(u32, cell[routing.OFF_SEGMENTS_LEFT..][0..4], 1, .little);
    std.mem.writeInt(u32, cell[routing.OFF_HOP_COUNT_BUDGET..][0..4], 4, .little);
    @memcpy(cell[routing.OFF_NEXT_HOP_BCA..][0..16], &bca_r);
    @memcpy(cell[routing.OFF_FINAL_DEST_BCA..][0..16], &bca_d);
    mnca_tile.writeHeader(cell[256..][0..768], 1, 2, 100, 7, 7, 1, 0);
    const state = 256 + mnca_tile.OFF_STATE;
    cell[state + 2 * 7 + 2] = 200; // (2,2)
    cell[state + 3 * 7 + 2] = 200; // (2,3)
    cell[state + 4 * 7 + 2] = 200; // (2,4)
    _ = routing.setRoutingChecksum(&cell);

    try d_o.broadcast(.cell_sync, &cell, &key);

    var pumps = [_]*UdpDispatcher{ d_o, d_r, d_d };
    try pumpUntilDelivered(&pumps, &node_d, 16);

    // The relay forwarded once AND ran the transform; D delivered the result.
    try testing.expectEqual(@as(u32, 1), node_r.forwarded_count);
    try testing.expectEqual(@as(u32, 1), node_r.transformed_count);
    try testing.expect(node_d.delivered);

    // The delivered cell is COMPUTED: type rotated tile.tick → snapshot, tile
    // tick 100 → 101, and grid-cell (3,3) born (0 → grow_step 64).
    try testing.expect(std.mem.eql(u8, node_d.delivered_cell[routing.TYPE_HASH_OFFSET..][0..32], &cell_transform.mncaTypeHash("mnca.snapshot")));
    const op = node_d.delivered_cell[256..][0..768];
    try testing.expectEqual(@as(u64, 101), mnca_tile.tick(op));
    try testing.expectEqual(@as(u8, 64), op[mnca_tile.OFF_STATE + 3 * 7 + 3]);
}

```
