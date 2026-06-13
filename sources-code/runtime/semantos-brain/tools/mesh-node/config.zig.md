---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tools/mesh-node/config.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.270482+00:00
---

# runtime/semantos-brain/tools/mesh-node/config.zig

```zig
// mesh-node config loader — parses `node-XX.json` blobs produced by
// `tools/u2-mesh/gen-identities.ts` into the shape the UdpDispatcher needs.
//
// Schema: `u2-mesh-identity/v2` (per-sender broadcast secret model).
// Older `v1` (NxN pairwise matrix) is rejected — that schema does not
// authenticate multicast correctly. Re-run `gen-identities.ts` to upgrade.

const std = @import("std");

pub const CELL_ID_LEN: usize = 32;
pub const SECRET_LEN: usize = 32;

pub const Peer = struct {
    label: []const u8, // owned by Config.arena
    cell_id: [CELL_ID_LEN]u8,
    broadcast_secret: [SECRET_LEN]u8,
};

pub const MulticastConfig = struct {
    /// IPv6 multicast group, e.g. "ff15::5e:1" (transient site-local, the
    /// `5e` byte is a convention for "SE"mantos). v6-only — IPv4 groups are
    /// rejected by the config loader.
    group: []const u8, // owned by Config.arena
    port: u16,
    /// IPv6 multicast hop limit (the v6 analogue of v4 TTL).
    hops: u8,
    loopback: bool,
};

pub const Config = struct {
    arena: std.heap.ArenaAllocator,
    self_label: []const u8,
    self_cell_id: [CELL_ID_LEN]u8,
    self_broadcast_secret: [SECRET_LEN]u8,
    multicast: MulticastConfig,
    peers: []Peer,

    pub fn deinit(self: *Config) void {
        self.arena.deinit();
    }

    /// Look up a peer's broadcast secret for HMAC verification of an inbound
    /// datagram whose sender_cell_id matches one of `peers`.
    ///
    /// Wrapped behind the `PeerSharedSecretLookup` callback in main.zig.
    pub fn lookupPeerSecret(self: *const Config, sender_cell_id: *const [CELL_ID_LEN]u8) ?[SECRET_LEN]u8 {
        for (self.peers) |p| {
            if (std.mem.eql(u8, &p.cell_id, sender_cell_id)) return p.broadcast_secret;
        }
        return null;
    }
};

pub const LoadError = error{
    FileTooLarge,
    InvalidJson,
    MissingField,
    BadHexLength,
    BadHexChar,
    UnsupportedSchema,
    BadMulticastGroup,
    BadPort,
    BadTtl,
} || std.fs.File.OpenError || std.mem.Allocator.Error || std.fs.File.ReadError;

const MAX_CONFIG_BYTES: usize = 1 * 1024 * 1024; // 1 MiB — generous for N≤256 peers

/// Read and parse a mesh-identity v2 JSON config from `path`.
/// The returned `Config` owns all heap allocations via its arena; call
/// `deinit()` to release them.
pub fn loadFromFile(parent_allocator: std.mem.Allocator, path: []const u8) LoadError!Config {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    if (stat.size > MAX_CONFIG_BYTES) return error.FileTooLarge;

    const raw = try parent_allocator.alloc(u8, @intCast(stat.size));
    defer parent_allocator.free(raw);
    _ = try file.readAll(raw);

    return try parseSlice(parent_allocator, raw);
}

/// Parse a JSON blob from memory. Mostly used directly by tests; production
/// code calls `loadFromFile`.
pub fn parseSlice(parent_allocator: std.mem.Allocator, json_bytes: []const u8) LoadError!Config {
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    errdefer arena.deinit();
    const aa = arena.allocator();

    var parsed = std.json.parseFromSlice(std.json.Value, aa, json_bytes, .{}) catch {
        return error.InvalidJson;
    };
    defer parsed.deinit();
    const root = parsed.value;

    // ── meta.schema ────────────────────────────────────────────────────────
    const meta = (root.object.get("meta") orelse return error.MissingField).object;
    const schema = (meta.get("schema") orelse return error.MissingField).string;
    if (!std.mem.eql(u8, schema, "u2-mesh-identity/v2")) return error.UnsupportedSchema;

    // ── self ───────────────────────────────────────────────────────────────
    const self_obj = (root.object.get("self") orelse return error.MissingField).object;
    const self_label_src = (self_obj.get("label") orelse return error.MissingField).string;
    const self_label = try aa.dupe(u8, self_label_src);

    var self_cell_id: [CELL_ID_LEN]u8 = undefined;
    try decodeHex(
        (self_obj.get("cellId") orelse return error.MissingField).string,
        &self_cell_id,
    );

    var self_secret: [SECRET_LEN]u8 = undefined;
    try decodeHex(
        (self_obj.get("broadcastSecret") orelse return error.MissingField).string,
        &self_secret,
    );

    // ── multicast ──────────────────────────────────────────────────────────
    const mc_obj = (root.object.get("multicast") orelse return error.MissingField).object;
    const group_src = (mc_obj.get("group") orelse return error.MissingField).string;
    const group = try aa.dupe(u8, group_src);
    // Validate by re-parsing — IPv6 only as of v3 (the IPv6 Forum's call for
    // v6-only as the Agentic-AI substrate; aligned with bitcoin-shard-proxy).
    const parsed_addr = std.net.Address.parseIp6(group, 0) catch return error.BadMulticastGroup;
    // First byte of an IPv6 multicast address is always 0xFF (FF00::/8).
    if (parsed_addr.in6.sa.addr[0] != 0xFF) return error.BadMulticastGroup;

    const port_val = (mc_obj.get("port") orelse return error.MissingField).integer;
    if (port_val < 1 or port_val > 65535) return error.BadPort;
    // Optional "hops" field (IPv6 multicast hop limit; analogue of IPv4 TTL).
    // Tolerate the older "ttl" field name for backward-compat with configs
    // generated by gen-identities < 2026-05-21.
    const hops_v = mc_obj.get("hops") orelse mc_obj.get("ttl") orelse return error.MissingField;
    const hops_val = hops_v.integer;
    if (hops_val < 1 or hops_val > 255) return error.BadTtl;
    const loopback = (mc_obj.get("loopback") orelse return error.MissingField).bool;

    // ── peers ──────────────────────────────────────────────────────────────
    const peers_arr = (root.object.get("peers") orelse return error.MissingField).array;
    var peers = try aa.alloc(Peer, peers_arr.items.len);
    for (peers_arr.items, 0..) |peer_v, i| {
        const peer_obj = peer_v.object;
        const label_src = (peer_obj.get("label") orelse return error.MissingField).string;
        peers[i].label = try aa.dupe(u8, label_src);
        try decodeHex(
            (peer_obj.get("cellId") orelse return error.MissingField).string,
            &peers[i].cell_id,
        );
        try decodeHex(
            (peer_obj.get("broadcastSecret") orelse return error.MissingField).string,
            &peers[i].broadcast_secret,
        );
    }

    return .{
        .arena = arena,
        .self_label = self_label,
        .self_cell_id = self_cell_id,
        .self_broadcast_secret = self_secret,
        .multicast = .{
            .group = group,
            .port = @intCast(port_val),
            .hops = @intCast(hops_val),
            .loopback = loopback,
        },
        .peers = peers,
    };
}

/// Decode a hex string into a fixed-size byte buffer.
/// Returns `error.BadHexLength` if the input doesn't have exactly 2*N chars,
/// or `error.BadHexChar` on a non-[0-9a-fA-F] byte.
fn decodeHex(hex: []const u8, out: []u8) LoadError!void {
    if (hex.len != out.len * 2) return error.BadHexLength;
    var i: usize = 0;
    while (i < out.len) : (i += 1) {
        const hi = nibble(hex[i * 2]) orelse return error.BadHexChar;
        const lo = nibble(hex[i * 2 + 1]) orelse return error.BadHexChar;
        out[i] = (hi << 4) | lo;
    }
}

fn nibble(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => null,
    };
}

// ── Embedded unit tests ───────────────────────────────────────────────────

const testing = std.testing;

const SAMPLE_V2_JSON =
    \\{
    \\  "self": {
    \\    "label": "node-01",
    \\    "cellId": "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",
    \\    "broadcastSecret": "21222324252627282930313233343536373839404142434445464748494a4b4c"
    \\  },
    \\  "multicast": {
    \\    "group": "ff15::5e:1",
    \\    "port": 47100,
    \\    "hops": 1,
    \\    "loopback": true
    \\  },
    \\  "peers": [
    \\    {
    \\      "label": "node-02",
    \\      "cellId": "a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0",
    \\      "broadcastSecret": "c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0"
    \\    }
    \\  ],
    \\  "meta": {
    \\    "generatedAt": "2026-05-21T00:00:00Z",
    \\    "schema": "u2-mesh-identity/v2",
    \\    "meshSize": 2
    \\  }
    \\}
;

test "config: parses a v2 IPv6 blob end-to-end" {
    var cfg = try parseSlice(testing.allocator, SAMPLE_V2_JSON);
    defer cfg.deinit();

    try testing.expectEqualStrings("node-01", cfg.self_label);
    try testing.expectEqualStrings("ff15::5e:1", cfg.multicast.group);
    try testing.expectEqual(@as(u16, 47100), cfg.multicast.port);
    try testing.expectEqual(@as(u8, 1), cfg.multicast.hops);
    try testing.expectEqual(true, cfg.multicast.loopback);
    try testing.expectEqual(@as(usize, 1), cfg.peers.len);
    try testing.expectEqualStrings("node-02", cfg.peers[0].label);

    // First byte of self.cellId should be 0x01, last should be 0x20.
    try testing.expectEqual(@as(u8, 0x01), cfg.self_cell_id[0]);
    try testing.expectEqual(@as(u8, 0x20), cfg.self_cell_id[31]);
    // First byte of self.broadcastSecret should be 0x21.
    try testing.expectEqual(@as(u8, 0x21), cfg.self_broadcast_secret[0]);
}

test "config: lookupPeerSecret returns peer's broadcast secret" {
    var cfg = try parseSlice(testing.allocator, SAMPLE_V2_JSON);
    defer cfg.deinit();

    const peer_cid = cfg.peers[0].cell_id;
    const found = cfg.lookupPeerSecret(&peer_cid);
    try testing.expect(found != null);
    try testing.expectEqual(@as(u8, 0xc1), found.?[0]);

    const unknown: [CELL_ID_LEN]u8 = .{0xFF} ** CELL_ID_LEN;
    try testing.expect(cfg.lookupPeerSecret(&unknown) == null);
}

test "config: rejects v1 schema (NxN pairwise) with UnsupportedSchema" {
    const v1_json =
        \\{
        \\  "self": { "label": "x", "cellId": "00".repeat(32), "broadcastSecret": "00".repeat(32) },
        \\  "multicast": { "group": "ff15::5e:1", "port": 47100, "hops": 1, "loopback": false },
        \\  "peers": [],
        \\  "meta": { "generatedAt": "x", "schema": "u2-mesh-identity/v1", "meshSize": 1 }
        \\}
    ;
    try testing.expectError(error.InvalidJson, parseSlice(testing.allocator, v1_json));
}

test "config: rejects bad hex length" {
    const bad_json =
        \\{
        \\  "self": { "label": "x", "cellId": "deadbeef", "broadcastSecret": "0000000000000000000000000000000000000000000000000000000000000000" },
        \\  "multicast": { "group": "ff15::5e:1", "port": 47100, "hops": 1, "loopback": false },
        \\  "peers": [],
        \\  "meta": { "generatedAt": "x", "schema": "u2-mesh-identity/v2", "meshSize": 1 }
        \\}
    ;
    try testing.expectError(error.BadHexLength, parseSlice(testing.allocator, bad_json));
}

test "config: rejects IPv4 multicast group" {
    const v4_json =
        \\{
        \\  "self": { "label": "x", "cellId": "0000000000000000000000000000000000000000000000000000000000000000", "broadcastSecret": "0000000000000000000000000000000000000000000000000000000000000000" },
        \\  "multicast": { "group": "239.42.42.42", "port": 47100, "hops": 1, "loopback": false },
        \\  "peers": [],
        \\  "meta": { "generatedAt": "x", "schema": "u2-mesh-identity/v2", "meshSize": 1 }
        \\}
    ;
    try testing.expectError(error.BadMulticastGroup, parseSlice(testing.allocator, v4_json));
}

test "config: rejects non-multicast IPv6 group" {
    const unicast_json =
        \\{
        \\  "self": { "label": "x", "cellId": "0000000000000000000000000000000000000000000000000000000000000000", "broadcastSecret": "0000000000000000000000000000000000000000000000000000000000000000" },
        \\  "multicast": { "group": "2001:db8::1", "port": 47100, "hops": 1, "loopback": false },
        \\  "peers": [],
        \\  "meta": { "generatedAt": "x", "schema": "u2-mesh-identity/v2", "meshSize": 1 }
        \\}
    ;
    try testing.expectError(error.BadMulticastGroup, parseSlice(testing.allocator, unicast_json));
}

```
