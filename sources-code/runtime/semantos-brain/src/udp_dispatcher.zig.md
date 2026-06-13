---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/udp_dispatcher.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.213925+00:00
---

# runtime/semantos-brain/src/udp_dispatcher.zig

```zig
// udp_dispatcher.zig — Phase U.2 UDP datagram reactor + multicast extension
//
// Reference: docs/prd/UDP-DATAGRAM-DISPATCH-BRIEF.md
//
// WHAT THIS FILE DOES
// -------------------
// Owns a single non-blocking UDP socket and dispatches incoming datagrams to
// type-specific host callbacks after HMAC verification + anti-replay check.
// Also provides an outbound API for unicast `sendTo` and multicast `broadcast`.
//
// The brief specifies unicast UDP (each peer's address tracked via HEARTBEAT
// datagrams). This module adds an optional multicast extension required for
// the 8-Pi LAN federation testbed:
//   - `Config.multicast_group` joins an IPv4 multicast group on init.
//   - `broadcast(...)` sends to that group; everyone in the group receives.
//   - `multicast_loopback = true` lets two processes on the same host (via
//     loopback or any iface) hear each other — useful for local smoke tests.
//
// HOW THE HOST USES IT
// --------------------
//   1. Construct via `init(allocator, config, self_cell_id, lookup, handlers)`.
//   2. Register `dispatcher.socket_fd` in the host's poll() set.
//   3. When poll() flags POLL.IN on that fd, call `handleDatagramReady()`.
//   4. To send: `sendTo(...)` for unicast or `broadcast(...)` for multicast.
//   5. On shutdown, `deinit()` closes the socket and frees the replay cache.
//
// HANDLERS ARE OPTIONAL
// --------------------
// Each datagram type has an optional callback. A datagram whose type lacks a
// handler is dropped silently (after HMAC + replay checks pass) — this lets
// tests verify framing without wiring full cell-DAG / broker machinery.
//
// RIP-OUT-MARKER (Phase U.2, 2026-05-21):
//   Delete this file + udp_protocol.zig + tests/udp_dispatcher_conformance.zig
//   and revert the optional `udp_dispatcher` field added to event_loop.zig.

const std = @import("std");
const proto = @import("udp_protocol");

const Allocator = std.mem.Allocator;

pub const CELL_ID_LEN = proto.CELL_ID_LEN;
pub const NONCE_LEN = proto.NONCE_LEN;

// ── Handlers ──────────────────────────────────────────────────────────────

pub const CellSyncFn = *const fn (
    peer_cell_id: *const [CELL_ID_LEN]u8,
    payload: []const u8,
    ud: *anyopaque,
) void;

pub const TopicBroadcastFn = *const fn (
    peer_cell_id: *const [CELL_ID_LEN]u8,
    payload: []const u8,
    ud: *anyopaque,
) void;

pub const HeartbeatFn = *const fn (
    peer_cell_id: *const [CELL_ID_LEN]u8,
    src_addr: *const std.posix.sockaddr,
    src_addr_len: std.posix.socklen_t,
    payload: []const u8,
    ud: *anyopaque,
) void;

pub const ReplyFn = *const fn (
    peer_cell_id: *const [CELL_ID_LEN]u8,
    nonce: *const [NONCE_LEN]u8,
    payload: []const u8,
    ud: *anyopaque,
) void;

pub const Handlers = struct {
    ud: *anyopaque,
    on_cell_sync: ?CellSyncFn = null,
    on_topic_broadcast: ?TopicBroadcastFn = null,
    on_heartbeat: ?HeartbeatFn = null,
    on_reply: ?ReplyFn = null,
};

// ── Anti-replay cache ─────────────────────────────────────────────────────
//
// Key = 32-byte peer cellId concatenated with 16-byte nonce.
// Value = millisecond timestamp of insertion.
//
// On every check we drop entries older than `max_age_ms`. v1 uses an O(n)
// linear sweep — fine for the expected N≤16 peers gossiping at single-digit
// Hz (a few hundred entries at most). A ring-buffer optimization is a future
// concern, not a v1 one.

pub const ReplayKey = [CELL_ID_LEN + NONCE_LEN]u8;

pub const AntiReplayCache = struct {
    allocator: Allocator,
    seen: std.AutoHashMap(ReplayKey, i64),
    max_age_ms: i64,

    pub fn init(allocator: Allocator, max_age_ms: i64) AntiReplayCache {
        return .{
            .allocator = allocator,
            .seen = std.AutoHashMap(ReplayKey, i64).init(allocator),
            .max_age_ms = max_age_ms,
        };
    }

    pub fn deinit(self: *AntiReplayCache) void {
        self.seen.deinit();
    }

    /// Returns true if this (peer, nonce) pair was seen within the window.
    /// On a fresh nonce, inserts it and returns false.
    pub fn checkAndRecord(
        self: *AntiReplayCache,
        peer_cell_id: *const [CELL_ID_LEN]u8,
        nonce: *const [NONCE_LEN]u8,
    ) !bool {
        const now = std.time.milliTimestamp();
        try self.evictOlderThan(now - self.max_age_ms);

        var key: ReplayKey = undefined;
        @memcpy(key[0..CELL_ID_LEN], peer_cell_id);
        @memcpy(key[CELL_ID_LEN..], nonce);

        if (self.seen.contains(key)) return true;
        try self.seen.put(key, now);
        return false;
    }

    fn evictOlderThan(self: *AntiReplayCache, cutoff_ms: i64) !void {
        // Two-pass to avoid mutating during iteration.
        var stale: std.ArrayList(ReplayKey) = .{};
        defer stale.deinit(self.allocator);

        var it = self.seen.iterator();
        while (it.next()) |kv| {
            if (kv.value_ptr.* < cutoff_ms) {
                try stale.append(self.allocator, kv.key_ptr.*);
            }
        }
        for (stale.items) |k| _ = self.seen.remove(k);
    }
};

// ── Dispatcher ────────────────────────────────────────────────────────────

pub const Config = struct {
    /// Local bind address. "::" for IPv6 wildcard. v6-only — no IPv4-mapped
    /// fallback (IPV6_V6ONLY is set to 1).
    bind_addr: []const u8 = "::",
    /// Local port.
    port: u16,
    /// Optional IPv6 multicast group, e.g. "ff15::5e:1" (transient site-local,
    /// "5e" = "SE" for Semantos as a convention; bitcoin-shard-proxy uses the
    /// permanent FF05::B:* range for BSV data plane and lives alongside us
    /// on different addresses). When set, the socket joins the group on init
    /// and `broadcast()` sends to it.
    multicast_group: ?[]const u8 = null,
    /// Multicast hop limit (the IPv6 analogue of TTL). 1 = same-subnet only,
    /// which is the right default for a LAN cluster.
    multicast_hops: u8 = 1,
    /// Optional iface name to bind multicast send/receive to (e.g. "en8" on
    /// macOS, "eth0" on Linux). Required when the host is dual-homed (Wi-Fi
    /// + Ethernet) and the kernel can't unambiguously pick which interface
    /// to use for site-local multicast. Resolved at init time via
    /// `if_nametoindex(3)`. When null, the kernel chooses (typically the
    /// default-route interface).
    multicast_iface: ?[]const u8 = null,
    /// Whether multicast sends echo back to this host's other sockets.
    /// True is useful for two-process localhost smoke tests.
    multicast_loopback: bool = true,
    /// Allow multiple processes to bind to the same port (multicast listeners).
    /// Required when running >1 dispatcher on the same host.
    reuse_port: bool = true,
    /// Anti-replay window. 5 seconds per brief.
    replay_window_ms: i64 = 5_000,
};

pub const Stats = struct {
    received: u64 = 0,
    dropped_short: u64 = 0,
    dropped_unknown_type: u64 = 0,
    dropped_no_peer_secret: u64 = 0,
    dropped_bad_hmac: u64 = 0,
    dropped_replay: u64 = 0,
    dispatched: u64 = 0,
    sent: u64 = 0,
    send_errors: u64 = 0,
};

pub const UdpDispatcher = struct {
    allocator: Allocator,
    socket_fd: std.posix.fd_t,
    bound_port: u16,
    self_cell_id: [CELL_ID_LEN]u8,
    secret_lookup: proto.PeerSharedSecretLookup,
    handlers: Handlers,
    replay_cache: AntiReplayCache,
    /// Set if multicast was enabled. Used as the default destination for
    /// `broadcast()` calls.
    multicast_dest: ?std.net.Address = null,
    stats: Stats = .{},

    pub fn init(
        allocator: Allocator,
        config: Config,
        self_cell_id: [CELL_ID_LEN]u8,
        secret_lookup: proto.PeerSharedSecretLookup,
        handlers: Handlers,
    ) !*UdpDispatcher {
        const sock = try std.posix.socket(
            std.posix.AF.INET6,
            std.posix.SOCK.DGRAM | std.posix.SOCK.NONBLOCK,
            std.posix.IPPROTO.UDP,
        );
        errdefer std.posix.close(sock);

        // SO_REUSEADDR + SO_REUSEPORT so multiple processes on this host can
        // bind to the same port (required for localhost multi-instance tests
        // and for multiple brains on the same Pi during development).
        try std.posix.setsockopt(
            sock,
            std.posix.SOL.SOCKET,
            std.posix.SO.REUSEADDR,
            &std.mem.toBytes(@as(c_int, 1)),
        );
        if (config.reuse_port) {
            try std.posix.setsockopt(
                sock,
                std.posix.SOL.SOCKET,
                std.posix.SO.REUSEPORT,
                &std.mem.toBytes(@as(c_int, 1)),
            );
        }

        // v6-only: reject IPv4-mapped addresses (::ffff:0:0/96). Aligned with
        // IPv6 Forum's call for v6-only as the substrate for the Internet of
        // Agents and with bitcoin-shard-proxy's pure-v6 namespace.
        try std.posix.setsockopt(
            sock,
            std.posix.IPPROTO.IPV6,
            ipv6V6only(),
            &std.mem.toBytes(@as(c_int, 1)),
        );

        const bind_addr = try std.net.Address.parseIp6(config.bind_addr, config.port);
        try std.posix.bind(sock, &bind_addr.any, bind_addr.getOsSockLen());

        var multicast_dest: ?std.net.Address = null;
        if (config.multicast_group) |group_str| {
            const group_addr = try std.net.Address.parseIp6(group_str, config.port);
            multicast_dest = group_addr;

            // Resolve the optional interface name to an OS index. 0 = kernel
            // picks default outbound iface (fine for single-homed hosts;
            // fails ambiguously on dual-homed hosts when site-local multicast
            // needs a specific iface to avoid wrong-NIC delivery).
            var iface_index: c_uint = 0;
            if (config.multicast_iface) |iface_name| {
                iface_index = try ifaceIndexByName(iface_name);
                try setMulticastIf(sock, iface_index);
            }

            try joinMulticastGroup(sock, group_addr, iface_index);
            try setMulticastHops(sock, config.multicast_hops);
            try setMulticastLoopback(sock, config.multicast_loopback);
        }

        const self = try allocator.create(UdpDispatcher);
        self.* = .{
            .allocator = allocator,
            .socket_fd = sock,
            .bound_port = config.port,
            .self_cell_id = self_cell_id,
            .secret_lookup = secret_lookup,
            .handlers = handlers,
            .replay_cache = AntiReplayCache.init(allocator, config.replay_window_ms),
            .multicast_dest = multicast_dest,
        };
        return self;
    }

    pub fn deinit(self: *UdpDispatcher) void {
        std.posix.close(self.socket_fd);
        self.replay_cache.deinit();
        self.allocator.destroy(self);
    }

    /// Drain the socket: recvfrom() in a loop until WouldBlock, dispatching
    /// each datagram. Designed to be called from the host's poll loop when
    /// POLL.IN fires on `socket_fd`.
    pub fn handleDatagramReady(self: *UdpDispatcher) !void {
        var buf: [proto.UDP_MAX_DATAGRAM]u8 = undefined;
        while (true) {
            var src_addr: std.posix.sockaddr = undefined;
            var src_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);
            const n = std.posix.recvfrom(
                self.socket_fd,
                &buf,
                0,
                &src_addr,
                &src_len,
            ) catch |err| switch (err) {
                error.WouldBlock => return,
                else => return err,
            };
            self.stats.received += 1;
            try self.dispatchDatagram(buf[0..n], &src_addr, src_len);
        }
    }

    fn dispatchDatagram(
        self: *UdpDispatcher,
        datagram: []const u8,
        src_addr: *const std.posix.sockaddr,
        src_len: std.posix.socklen_t,
    ) !void {
        const parsed = proto.parse(datagram) catch |err| {
            switch (err) {
                error.TooShort => self.stats.dropped_short += 1,
                error.UnknownType => self.stats.dropped_unknown_type += 1,
            }
            return;
        };

        // ── Identity loopback guard ────────────────────────────────────────
        // When multicast_loopback is on, we receive our own datagrams. Drop
        // anything whose sender_cell_id matches our own — saves cycles, avoids
        // adding self-nonces to the replay cache.
        if (std.mem.eql(u8, parsed.sender_cell_id, &self.self_cell_id)) return;

        // ── Look up shared secret ──────────────────────────────────────────
        var peer_cid: [CELL_ID_LEN]u8 = undefined;
        @memcpy(&peer_cid, parsed.sender_cell_id);
        const shared = self.secret_lookup.lookup(&peer_cid) orelse {
            self.stats.dropped_no_peer_secret += 1;
            return;
        };

        // ── HMAC verify (constant-time) ────────────────────────────────────
        const expected = proto.hmacSha256(&shared, parsed.authenticated_bytes);
        var got: [proto.HMAC_LEN]u8 = undefined;
        @memcpy(&got, parsed.hmac);
        if (!std.crypto.timing_safe.eql([proto.HMAC_LEN]u8, expected, got)) {
            self.stats.dropped_bad_hmac += 1;
            return;
        }

        // ── Replay check ───────────────────────────────────────────────────
        var nonce: [NONCE_LEN]u8 = undefined;
        @memcpy(&nonce, parsed.nonce);
        const replay = self.replay_cache.checkAndRecord(&peer_cid, &nonce) catch {
            // OOM in the replay cache — drop conservatively, do not invoke
            // the handler (better to lose a datagram than accept a replay).
            self.stats.dropped_replay += 1;
            return;
        };
        if (replay) {
            self.stats.dropped_replay += 1;
            return;
        }

        // ── Dispatch ───────────────────────────────────────────────────────
        switch (parsed.datagram_type) {
            .cell_sync => if (self.handlers.on_cell_sync) |h| {
                h(&peer_cid, parsed.payload, self.handlers.ud);
                self.stats.dispatched += 1;
            },
            .topic_broadcast => if (self.handlers.on_topic_broadcast) |h| {
                h(&peer_cid, parsed.payload, self.handlers.ud);
                self.stats.dispatched += 1;
            },
            .heartbeat => if (self.handlers.on_heartbeat) |h| {
                h(&peer_cid, src_addr, src_len, parsed.payload, self.handlers.ud);
                self.stats.dispatched += 1;
            },
            .reply => if (self.handlers.on_reply) |h| {
                h(&peer_cid, &nonce, parsed.payload, self.handlers.ud);
                self.stats.dispatched += 1;
            },
        }
    }

    /// Send a unicast datagram to `dest`. Caller provides the shared key
    /// directly (we don't go back through `secret_lookup` on the send path
    /// because the host may want to send to a peer it just discovered).
    pub fn sendTo(
        self: *UdpDispatcher,
        dtype: proto.DatagramType,
        payload: []const u8,
        shared_key: []const u8,
        dest: std.net.Address,
    ) !void {
        try self.sendInner(dtype, payload, shared_key, dest);
    }

    /// Send a datagram to the joined multicast group.
    /// Errors if `Config.multicast_group` was null at init time.
    pub fn broadcast(
        self: *UdpDispatcher,
        dtype: proto.DatagramType,
        payload: []const u8,
        shared_key: []const u8,
    ) !void {
        const dest = self.multicast_dest orelse return error.MulticastNotEnabled;
        try self.sendInner(dtype, payload, shared_key, dest);
    }

    fn sendInner(
        self: *UdpDispatcher,
        dtype: proto.DatagramType,
        payload: []const u8,
        shared_key: []const u8,
        dest: std.net.Address,
    ) !void {
        if (payload.len > proto.MAX_PAYLOAD) return error.PayloadTooLarge;

        var nonce: [NONCE_LEN]u8 = undefined;
        std.crypto.random.bytes(&nonce);

        var buf: [proto.UDP_MAX_DATAGRAM]u8 = undefined;
        const dgram = proto.buildDatagram(
            &buf,
            dtype,
            &nonce,
            &self.self_cell_id,
            payload,
            shared_key,
        );

        _ = std.posix.sendto(
            self.socket_fd,
            dgram,
            0,
            &dest.any,
            dest.getOsSockLen(),
        ) catch |err| {
            self.stats.send_errors += 1;
            return err;
        };
        self.stats.sent += 1;
    }
};

// ── IPv6 multicast socket setup helpers ───────────────────────────────────
//
// Zig 0.15's std.posix does not expose the IPv6 multicast / V6ONLY constants
// directly, so we reach for the kernel ABI values. Linux and Darwin disagree
// on most of them — branch on builtin.os.tag.
//
// Linux values: see /usr/include/linux/in6.h (IPPROTO_IPV6 socket options).
// Darwin values: see <netinet6/in6.h>.

const builtin = @import("builtin");

// ── Linux ─────────────────────────────────────────────────────────────────
const IPV6_MULTICAST_IF_LINUX: u32 = 17;
const IPV6_MULTICAST_HOPS_LINUX: u32 = 18;
const IPV6_MULTICAST_LOOP_LINUX: u32 = 19;
const IPV6_ADD_MEMBERSHIP_LINUX: u32 = 20; // also known as IPV6_JOIN_GROUP
const IPV6_V6ONLY_LINUX: u32 = 26;

// ── Darwin (macOS / iOS) ──────────────────────────────────────────────────
const IPV6_MULTICAST_IF_DARWIN: u32 = 9;
const IPV6_MULTICAST_HOPS_DARWIN: u32 = 10;
const IPV6_MULTICAST_LOOP_DARWIN: u32 = 11;
const IPV6_JOIN_GROUP_DARWIN: u32 = 12;
const IPV6_V6ONLY_DARWIN: u32 = 27;

fn isDarwin() bool {
    return builtin.os.tag == .macos or builtin.os.tag == .ios;
}

fn ipv6AddMembership() u32 {
    return if (isDarwin()) IPV6_JOIN_GROUP_DARWIN else IPV6_ADD_MEMBERSHIP_LINUX;
}

fn ipv6MulticastIf() u32 {
    return if (isDarwin()) IPV6_MULTICAST_IF_DARWIN else IPV6_MULTICAST_IF_LINUX;
}

fn ipv6MulticastHops() u32 {
    return if (isDarwin()) IPV6_MULTICAST_HOPS_DARWIN else IPV6_MULTICAST_HOPS_LINUX;
}

fn ipv6MulticastLoop() u32 {
    return if (isDarwin()) IPV6_MULTICAST_LOOP_DARWIN else IPV6_MULTICAST_LOOP_LINUX;
}

fn ipv6V6only() u32 {
    return if (isDarwin()) IPV6_V6ONLY_DARWIN else IPV6_V6ONLY_LINUX;
}

extern fn if_nametoindex(name: [*:0]const u8) c_uint;

/// Resolve an interface name like "en8" or "eth0" to its OS index.
/// Returns error.UnknownInterface if the OS doesn't recognize the name.
fn ifaceIndexByName(name: []const u8) !c_uint {
    // The C ABI wants a null-terminated string. Copy into a small fixed
    // buffer (IFNAMSIZ is 16 on Linux, 16 on Darwin; 32 here is plenty).
    var buf: [32]u8 = undefined;
    if (name.len >= buf.len) return error.UnknownInterface;
    @memcpy(buf[0..name.len], name);
    buf[name.len] = 0;
    const idx = if_nametoindex(@ptrCast(&buf));
    if (idx == 0) return error.UnknownInterface;
    return idx;
}

/// Set the outbound interface for IPv6 multicast. Pairs with the
/// `ipv6_mreq.interface` field on join — both need to point at the same
/// iface for full receive/send symmetry on dual-homed hosts.
fn setMulticastIf(sock: std.posix.fd_t, iface_index: c_uint) !void {
    try std.posix.setsockopt(
        sock,
        std.posix.IPPROTO.IPV6,
        ipv6MulticastIf(),
        &std.mem.toBytes(iface_index),
    );
}

/// IPv6 group-membership control structure for setsockopt
/// IPV6_ADD_MEMBERSHIP / IPV6_JOIN_GROUP. Matches `struct ipv6_mreq` from
/// <netinet/in.h> on both Linux and Darwin.
const Ipv6Mreq = extern struct {
    multiaddr: [16]u8, // in6_addr — network byte order, packed
    interface: u32, // interface index; 0 = kernel default
};

fn joinMulticastGroup(sock: std.posix.fd_t, group: std.net.Address, iface_index: c_uint) !void {
    var mreq = Ipv6Mreq{
        .multiaddr = undefined,
        .interface = iface_index, // 0 = kernel default; non-zero = bind to that iface
    };
    @memcpy(&mreq.multiaddr, &group.in6.sa.addr);
    try std.posix.setsockopt(
        sock,
        std.posix.IPPROTO.IPV6,
        ipv6AddMembership(),
        std.mem.asBytes(&mreq),
    );
}

fn setMulticastHops(sock: std.posix.fd_t, hops: u8) !void {
    // Linux + Darwin both accept c_int here; many kernels also accept u_char
    // (1 byte) but c_int is the portable form.
    const v: c_int = hops;
    try std.posix.setsockopt(
        sock,
        std.posix.IPPROTO.IPV6,
        ipv6MulticastHops(),
        &std.mem.toBytes(v),
    );
}

fn setMulticastLoopback(sock: std.posix.fd_t, on: bool) !void {
    const v: c_int = if (on) 1 else 0;
    try std.posix.setsockopt(
        sock,
        std.posix.IPPROTO.IPV6,
        ipv6MulticastLoop(),
        &std.mem.toBytes(v),
    );
}

// ── Embedded unit tests ───────────────────────────────────────────────────

const testing = std.testing;

test "AntiReplayCache: novel nonce returns false; replay returns true" {
    var cache = AntiReplayCache.init(testing.allocator, 5_000);
    defer cache.deinit();

    const peer: [CELL_ID_LEN]u8 = .{0xAA} ** CELL_ID_LEN;
    const nonce: [NONCE_LEN]u8 = .{0xBB} ** NONCE_LEN;

    try testing.expectEqual(false, try cache.checkAndRecord(&peer, &nonce));
    try testing.expectEqual(true, try cache.checkAndRecord(&peer, &nonce));
}

test "AntiReplayCache: distinct nonces from same peer both pass" {
    var cache = AntiReplayCache.init(testing.allocator, 5_000);
    defer cache.deinit();

    const peer: [CELL_ID_LEN]u8 = .{0xAA} ** CELL_ID_LEN;
    const a: [NONCE_LEN]u8 = .{0x01} ** NONCE_LEN;
    const b: [NONCE_LEN]u8 = .{0x02} ** NONCE_LEN;

    try testing.expectEqual(false, try cache.checkAndRecord(&peer, &a));
    try testing.expectEqual(false, try cache.checkAndRecord(&peer, &b));
}

test "AntiReplayCache: same nonce different peers both pass" {
    var cache = AntiReplayCache.init(testing.allocator, 5_000);
    defer cache.deinit();

    const peer_a: [CELL_ID_LEN]u8 = .{0xAA} ** CELL_ID_LEN;
    const peer_b: [CELL_ID_LEN]u8 = .{0xBB} ** CELL_ID_LEN;
    const nonce: [NONCE_LEN]u8 = .{0xCC} ** NONCE_LEN;

    try testing.expectEqual(false, try cache.checkAndRecord(&peer_a, &nonce));
    try testing.expectEqual(false, try cache.checkAndRecord(&peer_b, &nonce));
}

test "AntiReplayCache: eviction expires old entries" {
    // Use a zero-ms window so the very next insert sees the prior as expired.
    var cache = AntiReplayCache.init(testing.allocator, 0);
    defer cache.deinit();

    const peer: [CELL_ID_LEN]u8 = .{0xAA} ** CELL_ID_LEN;
    const nonce: [NONCE_LEN]u8 = .{0xBB} ** NONCE_LEN;

    try testing.expectEqual(false, try cache.checkAndRecord(&peer, &nonce));
    // Sleep 2ms to ensure cutoff strictly exceeds the recorded timestamp.
    std.Thread.sleep(2 * std.time.ns_per_ms);
    try testing.expectEqual(false, try cache.checkAndRecord(&peer, &nonce));
}

```
