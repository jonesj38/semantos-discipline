---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/tools/mesh-node/main.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.270174+00:00
---

# runtime/semantos-brain/tools/mesh-node/main.zig

```zig
// mesh-node — Phase U.2 standalone multicast gossip binary.
//
// Loads a `node-XX.json` blob (schema `u2-mesh-identity/v2`) produced by
// `tools/u2-mesh/gen-identities.ts`, joins the configured multicast group,
// emits HEARTBEAT datagrams every N milliseconds, and logs every verified
// HEARTBEAT it receives from peers.
//
// This is the smallest standalone consumer of the U.2 dispatcher — proves
// the wire is alive without needing the full brain to be running. It is
// also the target binary for the SD-card-flashing flow (one per Pi, with
// its own node-XX.json baked into /boot).
//
// Usage:
//   mesh-node --config /path/to/node-01.json
//   mesh-node --config /path/to/node-01.json --heartbeat-ms 1000

const std = @import("std");
const config_mod = @import("config.zig");
const dispatcher_mod = @import("udp_dispatcher");
const proto = @import("udp_protocol");
const routing = @import("routing");
const mnca = @import("mnca_tile");
const pask_mesh = @import("pask_integration.zig");
const mnca_cell = @import("mnca_cell");

const Config = config_mod.Config;
const UdpDispatcher = dispatcher_mod.UdpDispatcher;
const Handlers = dispatcher_mod.Handlers;
const CELL_ID_LEN = config_mod.CELL_ID_LEN;

// ── Source-routing relay (Phase U.2 Half B; brief §15.2) ───────────────────
//
// The dispatcher stays transport-pure; routing lives here in the cell_sync
// handler. A node's 16-byte routing BCA is, for v1, SHA-256(cellId)[0..16] —
// a documented stand-in until U.3 brings asymmetric (pubkey-derived) identity
// per Ducroux. processHop only compares NEXT_HOP_BCA bytes for equality, so
// any stable 16-byte node tag works for the demo; the derivation swaps out
// without touching the routing logic.

/// v1 routing BCA: SHA-256(cellId)[0..16]. Stand-in until U.3 pubkey identity.
fn deriveOwnBca(cell_id: *const [CELL_ID_LEN]u8) [16]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(cell_id, &digest, .{});
    var bca: [16]u8 = undefined;
    @memcpy(&bca, digest[0..16]);
    return bca;
}

/// Callback the relay invokes to re-transmit a forwarded cell.
const EmitFn = *const fn (cell: []const u8, ud: *anyopaque) void;

const RouteDecision = union(enum) {
    /// Not a source-routed cell — caller handles it as a plain cell_sync.
    not_routed,
    /// This node is the final destination (process the payload locally).
    delivered,
    /// Expected rejection — dropped (silently for not_my_hop, §11.4).
    dropped: routing.HopRejectReason,
    /// Forwarded to the next hop via `emit`.
    forwarded,
};

/// Decide what to do with a received cell and (on forward) emit the advanced
/// copy. Pure decision logic over `processHop`, with the emit injected so it's
/// unit-testable with a capturing stub.
///
/// `validate_type` is false for v1: the cell-engine transform isn't executed
/// between hops yet, so a forwarded cell keeps its inbound typeHash and a type
/// check would reject at the second hop. Flips to true when transform
/// execution lands.
fn routeReceivedCell(
    cell: []const u8,
    own_bca: *const [16]u8,
    out_buf: []u8,
    emit: EmitFn,
    emit_ud: *anyopaque,
) RouteDecision {
    // A canonical routed cell is exactly CELL_SIZE bytes; anything shorter or
    // not flagged source-routed is a plain cell_sync.
    if (cell.len < routing.CELL_SIZE or !routing.isRouted(cell)) return .not_routed;

    switch (routing.processHop(cell, own_bca, out_buf, false)) {
        .final_destination => return .delivered,
        .reject => |reason| return .{ .dropped = reason },
        .forward => {
            emit(out_buf[0..routing.CELL_SIZE], emit_ud);
            return .forwarded;
        },
    }
}

// ── Signal handling ───────────────────────────────────────────────────────
//
// Standard "atomic bool set by signal handler, polled by main loop" pattern.
// Zig has no async signal-safe ABI for the dispatch path; the handler does
// nothing but set the flag.

var shutdown_requested = std.atomic.Value(bool).init(false);

fn handleSigint(_: c_int) callconv(.c) void {
    shutdown_requested.store(true, .release);
}

fn installSigintHandler() !void {
    var empty_mask: std.posix.sigset_t = undefined;
    @memset(@as([*]u8, @ptrCast(&empty_mask))[0..@sizeOf(std.posix.sigset_t)], 0);
    var act = std.posix.Sigaction{
        .handler = .{ .handler = handleSigint },
        .mask = empty_mask,
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &act, null);
    std.posix.sigaction(std.posix.SIG.TERM, &act, null);
}

// ── CLI parsing ───────────────────────────────────────────────────────────

const CliArgs = struct {
    config_path: []const u8,
    heartbeat_ms: u64 = 2_000,
    iface: ?[]const u8 = null,
    /// MNCA tile stepping + broadcast cadence (ms). 0 disables tile mode.
    tile_ms: u64 = 0,
    /// This node's tile coordinate in the global tiling (for the composite grid).
    tile_x: u16 = 0,
    tile_y: u16 = 0,
    /// Tile side (W=H, includes halo). 18×18 with halo 3 → 12×12 interior.
    tile_side: u8 = 18,
    /// D-SRS-pask-in-mesh: enable Pask live graph (>0 enables; value = planned ring
    /// capacity, currently unused — all peers are registered on startup).
    /// 0 = disabled (default). Set to e.g. 16 to enable.
    pask_cells: u16 = 0,
};

const CliError = error{ MissingConfigFlag, MissingConfigValue, BadHeartbeatValue, MissingIfaceValue, BadTileValue, BadPaskValue };

fn parseArgs(allocator: std.mem.Allocator) !CliArgs {
    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    var config_path: ?[]const u8 = null;
    var heartbeat_ms: u64 = 2_000;
    var iface: ?[]const u8 = null;
    var tile_ms: u64 = 0;
    var tile_x: u16 = 0;
    var tile_y: u16 = 0;
    var tile_side: u8 = 18;
    var pask_cells: u16 = 0;

    var i: usize = 1;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        if (std.mem.eql(u8, arg, "--config")) {
            if (i + 1 >= argv.len) return error.MissingConfigValue;
            i += 1;
            config_path = try allocator.dupe(u8, argv[i]);
        } else if (std.mem.eql(u8, arg, "--heartbeat-ms")) {
            if (i + 1 >= argv.len) return error.BadHeartbeatValue;
            i += 1;
            heartbeat_ms = std.fmt.parseInt(u64, argv[i], 10) catch return error.BadHeartbeatValue;
        } else if (std.mem.eql(u8, arg, "--iface")) {
            if (i + 1 >= argv.len) return error.MissingIfaceValue;
            i += 1;
            iface = try allocator.dupe(u8, argv[i]);
        } else if (std.mem.eql(u8, arg, "--tile-ms")) {
            if (i + 1 >= argv.len) return error.BadTileValue;
            i += 1;
            tile_ms = std.fmt.parseInt(u64, argv[i], 10) catch return error.BadTileValue;
        } else if (std.mem.eql(u8, arg, "--tile-x")) {
            if (i + 1 >= argv.len) return error.BadTileValue;
            i += 1;
            tile_x = std.fmt.parseInt(u16, argv[i], 10) catch return error.BadTileValue;
        } else if (std.mem.eql(u8, arg, "--tile-y")) {
            if (i + 1 >= argv.len) return error.BadTileValue;
            i += 1;
            tile_y = std.fmt.parseInt(u16, argv[i], 10) catch return error.BadTileValue;
        } else if (std.mem.eql(u8, arg, "--tile-side")) {
            if (i + 1 >= argv.len) return error.BadTileValue;
            i += 1;
            tile_side = std.fmt.parseInt(u8, argv[i], 10) catch return error.BadTileValue;
        } else if (std.mem.eql(u8, arg, "--pask-cells")) {
            if (i + 1 >= argv.len) return error.BadPaskValue;
            i += 1;
            pask_cells = std.fmt.parseInt(u16, argv[i], 10) catch return error.BadPaskValue;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printHelp();
            std.process.exit(0);
        }
    }

    return .{
        .config_path = config_path orelse return error.MissingConfigFlag,
        .heartbeat_ms = heartbeat_ms,
        .iface = iface,
        .tile_ms = tile_ms,
        .tile_x = tile_x,
        .tile_y = tile_y,
        .tile_side = tile_side,
        .pask_cells = pask_cells,
    };
}

fn printHelp() void {
    // std.debug.print writes to stderr unbuffered — fine for help output.
    std.debug.print(
        \\mesh-node — Phase U.2 multicast gossip binary
        \\
        \\Usage:
        \\  mesh-node --config <path>              Path to node-XX.json (required)
        \\  mesh-node --heartbeat-ms <ms>          Heartbeat emission interval (default 2000)
        \\  mesh-node --tile-ms <ms>               MNCA tile step+broadcast interval (0=off)
        \\  mesh-node --tile-x <n> --tile-y <n>    This node's tile coord in the grid
        \\  mesh-node --tile-side <n>              Tile side incl. halo (default 18)
        \\  mesh-node --pask-cells <n>             Enable Pask live graph (n>0; default 0=off)
        \\
        \\With --pask-cells 16: every received tile tick feeds the Pask graph.
        \\Stability convergence events are logged to stderr.
        \\
        \\Logs to stderr; one line per emitted heartbeat and per verified
        \\peer heartbeat received. Exits cleanly on SIGINT or SIGTERM.
        \\
    , .{});
}

// ── Handler context ───────────────────────────────────────────────────────
//
// The dispatcher calls into here when a datagram is verified + dispatched.
// We log to stderr — that's the entire production-side surface for v1.

const HandlerCtx = struct {
    config: *const Config,
    /// This node's 16-byte routing BCA (SHA-256(cellId)[0..16] for v1).
    own_bca: [16]u8 = [_]u8{0} ** 16,
    /// Set after dispatcher init so the cell_sync handler can re-broadcast
    /// forwarded cells. Null until then.
    dispatcher: ?*UdpDispatcher = null,
    received_count: u64 = 0,

    fn labelForCell(self: *HandlerCtx, cell_id: *const [CELL_ID_LEN]u8) []const u8 {
        for (self.config.peers) |p| {
            if (std.mem.eql(u8, &p.cell_id, cell_id)) return p.label;
        }
        return "<unknown>";
    }
};

/// Production emit: re-broadcast the forwarded cell as a new cell_sync,
/// HMAC'd with this node's own broadcast secret.
fn emitForward(cell: []const u8, ud: *anyopaque) void {
    const ctx: *HandlerCtx = @ptrCast(@alignCast(ud));
    const d = ctx.dispatcher orelse return;
    d.broadcast(proto.DatagramType.cell_sync, cell, &ctx.config.self_broadcast_secret) catch |err| {
        std.log.warn("forward broadcast error: {s}", .{@errorName(err)});
    };
}

fn onHeartbeat(
    peer_cell_id: *const [CELL_ID_LEN]u8,
    _: *const std.posix.sockaddr,
    _: std.posix.socklen_t,
    payload: []const u8,
    ud: *anyopaque,
) void {
    const ctx: *HandlerCtx = @ptrCast(@alignCast(ud));
    ctx.received_count += 1;
    std.log.info(
        "RX heartbeat from {s} ({d} bytes payload, total {d})",
        .{ ctx.labelForCell(peer_cell_id), payload.len, ctx.received_count },
    );
}

fn onCellSync(
    peer_cell_id: *const [CELL_ID_LEN]u8,
    payload: []const u8,
    ud: *anyopaque,
) void {
    const ctx: *HandlerCtx = @ptrCast(@alignCast(ud));
    const label = ctx.labelForCell(peer_cell_id);

    var out_buf: [routing.CELL_SIZE]u8 = undefined;
    switch (routeReceivedCell(payload, &ctx.own_bca, &out_buf, emitForward, ud)) {
        .not_routed => {
            std.log.info("RX cell_sync from {s} ({d} bytes)", .{ label, payload.len });
            // D-SRS-pask-in-mesh: if the payload looks like a tile, feed Pask.
            // Tile payloads are exactly mnca.PAYLOAD_SIZE (768) bytes; check
            // both size and that the header magic is plausible (width/height > 0).
            if (payload.len >= mnca.PAYLOAD_SIZE) {
                const tile_payload = payload[0..mnca.PAYLOAD_SIZE];
                const width = tile_payload[mnca.OFF_WIDTH];
                const height = tile_payload[mnca.OFF_HEIGHT];
                if (width > 0 and height > 0) {
                    // Extract tile tick (u64 LE at OFF_TICK=4).
                    const tick_bytes = tile_payload[mnca.OFF_TICK..][0..8];
                    const tile_tick = std.mem.readInt(u64, tick_bytes, .little);
                    const now_ms: u64 = @intCast(std.time.milliTimestamp());
                    _ = pask_mesh.onTileTick(peer_cell_id, tile_tick, now_ms);
                }
            }
        },
        .delivered => std.log.info(
            "RX cell_sync from {s}: routed cell DELIVERED (final destination)",
            .{label},
        ),
        .dropped => |reason| std.log.info(
            "RX cell_sync from {s}: routed cell dropped ({s})",
            .{ label, @tagName(reason) },
        ),
        .forwarded => std.log.info(
            "RX cell_sync from {s}: routed cell FORWARDED to next hop",
            .{label},
        ),
    }
}

fn onTopicBroadcast(
    peer_cell_id: *const [CELL_ID_LEN]u8,
    payload: []const u8,
    ud: *anyopaque,
) void {
    const ctx: *HandlerCtx = @ptrCast(@alignCast(ud));
    std.log.info(
        "RX topic_broadcast from {s} ({d} bytes)",
        .{ ctx.labelForCell(peer_cell_id), payload.len },
    );
}

// ── PeerSharedSecretLookup adapter ────────────────────────────────────────

fn lookupSecretFromConfig(
    peer_cell_id: *const [CELL_ID_LEN]u8,
    ud: *anyopaque,
) ?[32]u8 {
    const cfg: *const Config = @ptrCast(@alignCast(ud));
    return cfg.lookupPeerSecret(peer_cell_id);
}

// ── Main ──────────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cli = parseArgs(allocator) catch |err| {
        std.debug.print("error: {s}\n\n", .{@errorName(err)});
        printHelp();
        std.process.exit(2);
    };
    defer allocator.free(cli.config_path);

    var cfg = try config_mod.loadFromFile(allocator, cli.config_path);
    defer cfg.deinit();

    std.log.info(
        "mesh-node up — label={s} group={s}:{d} peers={d} heartbeat-ms={d}",
        .{
            cfg.self_label,
            cfg.multicast.group,
            cfg.multicast.port,
            cfg.peers.len,
            cli.heartbeat_ms,
        },
    );

    // D-SRS-pask-in-mesh: initialize Pask live graph when --pask-cells > 0.
    if (cli.pask_cells > 0) {
        // Build peer cell_id + label slices from the loaded config.
        var peer_cids = try allocator.alloc([config_mod.CELL_ID_LEN]u8, cfg.peers.len);
        defer allocator.free(peer_cids);
        var peer_lbls = try allocator.alloc([]const u8, cfg.peers.len);
        defer allocator.free(peer_lbls);
        for (cfg.peers, 0..) |p, i| {
            peer_cids[i] = p.cell_id;
            peer_lbls[i] = p.label;
        }
        pask_mesh.init(&cfg.self_cell_id, peer_cids, peer_lbls);
    }

    try installSigintHandler();

    var handler_ctx = HandlerCtx{
        .config = &cfg,
        .own_bca = deriveOwnBca(&cfg.self_cell_id),
    };

    var dispatcher = try UdpDispatcher.init(
        allocator,
        .{
            .port = cfg.multicast.port,
            .multicast_group = cfg.multicast.group,
            .multicast_hops = cfg.multicast.hops,
            .multicast_iface = cli.iface,
            .multicast_loopback = cfg.multicast.loopback,
            .reuse_port = true,
        },
        cfg.self_cell_id,
        .{
            .lookup_fn = lookupSecretFromConfig,
            .ud = @ptrCast(&cfg),
        },
        .{
            .ud = &handler_ctx,
            .on_heartbeat = onHeartbeat,
            .on_cell_sync = onCellSync,
            .on_topic_broadcast = onTopicBroadcast,
        },
    );
    defer dispatcher.deinit();

    // The cell_sync handler re-broadcasts forwarded cells through the
    // dispatcher; wire the back-reference now that it's initialised.
    handler_ctx.dispatcher = dispatcher;
    std.log.info("routing BCA (v1 = SHA-256(cellId)[0..16]): {x}", .{handler_ctx.own_bca});

    // ── Main loop ─────────────────────────────────────────────────────────
    //
    // poll() with a deadline-driven timeout: we want to wake either when a
    // datagram arrives or when it's time to emit the next heartbeat.

    var next_heartbeat_at_ms: i64 = std.time.milliTimestamp();
    var emitted: u64 = 0;

    // MNCA tile state (double-buffered). Enabled when --tile-ms > 0.
    const tile_enabled = cli.tile_ms > 0;
    var tile_cur: [mnca.PAYLOAD_SIZE]u8 = undefined;
    var tile_next: [mnca.PAYLOAD_SIZE]u8 = undefined;
    var next_tile_at_ms: i64 = std.time.milliTimestamp();
    var tile_tick: u64 = 0;
    var static_ticks: u32 = 0; // consecutive ticks where interior didn't change
    if (tile_enabled) {
        seedTile(&tile_cur, cli.tile_x, cli.tile_y, cli.tile_side, &cfg.self_cell_id);
        std.log.info(
            "MNCA tile enabled — coord=({d},{d}) {d}x{d} halo=3, step every {d}ms",
            .{ cli.tile_x, cli.tile_y, cli.tile_side, cli.tile_side, cli.tile_ms },
        );
    }

    while (!shutdown_requested.load(.acquire)) {
        const now = std.time.milliTimestamp();
        var next_deadline = next_heartbeat_at_ms;
        if (tile_enabled and next_tile_at_ms < next_deadline) next_deadline = next_tile_at_ms;
        const wait_ms_signed = next_deadline - now;
        const wait_ms: i32 = if (wait_ms_signed <= 0) 0 else @intCast(@min(wait_ms_signed, 1_000));

        var pfd = [_]std.posix.pollfd{.{
            .fd = dispatcher.socket_fd,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};
        const ready = std.posix.poll(&pfd, wait_ms) catch |err| {
            if (err == error.SignalInterrupt) continue;
            return err;
        };

        if (ready > 0 and (pfd[0].revents & std.posix.POLL.IN) != 0) {
            dispatcher.handleDatagramReady() catch |err| {
                std.log.warn("dispatch error: {s}", .{@errorName(err)});
            };
        }

        // Heartbeat emission — fires every heartbeat_ms regardless of inbound
        // traffic; the deadline-driven poll keeps the cadence stable.
        const after_now = std.time.milliTimestamp();
        if (after_now >= next_heartbeat_at_ms) {
            emitHeartbeat(dispatcher, &cfg, emitted) catch |err| {
                std.log.warn("heartbeat send error: {s}", .{@errorName(err)});
            };
            emitted += 1;
            next_heartbeat_at_ms = after_now + @as(i64, @intCast(cli.heartbeat_ms));
        }

        // MNCA tile: broadcast the current generation, then step to the next.
        if (tile_enabled and after_now >= next_tile_at_ms) {
            broadcastTile(dispatcher, &cfg, &tile_cur) catch |err| {
                std.log.warn("tile send error: {s}", .{@errorName(err)});
            };
            mnca.stepTilePayload(&tile_cur, &tile_next, mnca.DEFAULT_MNCA_RULE);
            // Convergence guard: if the interior hasn't changed in 5 consecutive
            // ticks (~2.5 s at 500 ms/tick), the MNCA has reached a fixed-point
            // attractor (still-life). Inject noise to restart dynamics.
            if (!interiorChanged(&tile_cur, &tile_next)) {
                static_ticks += 1;
                if (static_ticks >= 5) {
                    injectNoise(&tile_next, &cfg.self_cell_id, tile_tick);
                    static_ticks = 0;
                    std.log.info(
                        "tile ({d},{d}) fixed-point — noise injected at tick {d}",
                        .{ cli.tile_x, cli.tile_y, tile_tick },
                    );
                }
            } else {
                static_ticks = 0;
            }
            @memcpy(&tile_cur, &tile_next);
            tile_tick += 1;
            std.log.info("TX tile ({d},{d}) tick={d}", .{ cli.tile_x, cli.tile_y, tile_tick });
            next_tile_at_ms = after_now + @as(i64, @intCast(cli.tile_ms));
        }
    }

    std.log.info(
        "shutdown — emitted={d} received={d}",
        .{ emitted, handler_ctx.received_count },
    );
}

fn emitHeartbeat(dispatcher: *UdpDispatcher, cfg: *const Config, seq: u64) !void {
    var payload_buf: [64]u8 = undefined;
    const payload = try std.fmt.bufPrint(&payload_buf, "hb#{d}@{s}", .{ seq, cfg.self_label });

    try dispatcher.broadcast(
        proto.DatagramType.heartbeat,
        payload,
        &cfg.self_broadcast_secret,
    );
    std.log.info("TX heartbeat #{d}", .{seq});
}

// ── MNCA tile (Phase L4 — compute on the mesh) ─────────────────────────────
//
// Each node owns one tile of the global MNCA at (tile_x, tile_y), seeds it
// deterministically from its cellId, steps the interior one generation every
// `tile_ms`, and broadcasts the full 768-byte tile payload as a cell_sync. A
// bridge collects every node's tile to render the composite grid. Halo refresh
// from neighbour tiles is a later slice; for now the border is the fixed seed.

/// Seed an MNCA tile deterministically from the node's cellId (~38% alive),
/// header tagged with the tile coordinate. Distinct per node, reproducible.
fn seedTile(out: *[mnca.PAYLOAD_SIZE]u8, tile_x: u16, tile_y: u16, side: u8, cell_id: *const [CELL_ID_LEN]u8) void {
    @memset(out, 0);
    const halo: u8 = 3; // = DEFAULT_MNCA_RULE.outer_radius (margin for the interior)
    mnca.writeHeader(out, tile_x, tile_y, 0, side, side, halo, 0);
    var seed: u64 = 0;
    for (cell_id[0..8]) |b| seed = (seed << 8) | b;
    if (seed == 0) seed = 0x9E3779B97F4A7C15;
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();
    const n: usize = @as(usize, side) * @as(usize, side);
    var i: usize = 0;
    while (i < n) : (i += 1) out[mnca.OFF_STATE + i] = if (r.float(f32) < 0.38) 255 else 0;
}

/// True when any interior cell differs between two tile payloads.
/// Halo ring is ignored (it's carried over unchanged in stepTilePayload).
fn interiorChanged(a: *const [mnca.PAYLOAD_SIZE]u8, b: *const [mnca.PAYLOAD_SIZE]u8) bool {
    const w: usize = mnca.width(a);
    const h: usize = mnca.height(a);
    const r: usize = mnca.haloRadius(a);
    var y: usize = r;
    while (y < h - r) : (y += 1) {
        var x: usize = r;
        while (x < w - r) : (x += 1) {
            if (a[mnca.OFF_STATE + y * w + x] != b[mnca.OFF_STATE + y * w + x]) return true;
        }
    }
    return false;
}

/// Inject random noise into ~15% of interior cells to break MNCA fixed-point
/// attractors (still-lifes). Deterministic: seeded from tick_val + cell_id so
/// each node perturbs different cells at the same convergence moment.
fn injectNoise(tile: *[mnca.PAYLOAD_SIZE]u8, cell_id: *const [CELL_ID_LEN]u8, tick_val: u64) void {
    const w: usize = mnca.width(tile);
    const h: usize = mnca.height(tile);
    const r: usize = mnca.haloRadius(tile);
    if (h <= 2 * r or w <= 2 * r) return;

    // Mix tick + first 8 bytes of cellId into a deterministic seed.
    var seed: u64 = tick_val ^ 0x6C62272E07BB0142;
    for (cell_id[0..8]) |b| {
        seed = seed *% 6364136223846793005 +% @as(u64, b) +% 1442695040888963407;
    }
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();

    // Flip ~15% of interior cells (at least 3) to fresh binary values.
    const interior_w = w - 2 * r;
    const interior_h = h - 2 * r;
    const n_noise: usize = @max(3, (interior_w * interior_h * 3) / 20);
    var i: usize = 0;
    while (i < n_noise) : (i += 1) {
        const ix = r + rng.uintLessThan(usize, interior_w);
        const iy = r + rng.uintLessThan(usize, interior_h);
        tile[mnca.OFF_STATE + iy * w + ix] = if (rng.boolean()) 255 else 0;
    }
}

fn broadcastTile(dispatcher: *UdpDispatcher, cfg: *const Config, tile: *const [mnca.PAYLOAD_SIZE]u8) !void {
    // Plain cell_sync (768 bytes) — consumed by mesh-bridge and older observers.
    try dispatcher.broadcast(proto.DatagramType.cell_sync, tile, &cfg.self_broadcast_secret);

    // D-SRS-typed-cell: also broadcast the 1024-byte typed cell (cell_sync with
    // 1024-byte payload). Bridge distinguishes by payload.length:
    //   768  → plain tile (old format)
    //   1024 → typed cell (256-byte header + 768-byte tile)
    // The typeHash field (header bytes [30..62)) = SHA-256("mnca.tile.tick").
    const now_ms: u64 = @intCast(std.time.milliTimestamp());
    var typed_buf: [mnca_cell.CELL_SIZE]u8 = undefined;
    mnca_cell.wrapTile(&typed_buf, tile, now_ms);
    try dispatcher.broadcast(proto.DatagramType.cell_sync, &typed_buf, &cfg.self_broadcast_secret);
}

// ── Embedded unit test ────────────────────────────────────────────────────
// Smoke-test that the handler context plumbing types check; the binary
// itself is exercised by the localhost smoke runbook entry.

const testing = std.testing;

test "HandlerCtx.labelForCell finds peer label" {
    const json =
        \\{
        \\  "self": {
        \\    "label": "node-01",
        \\    "cellId": "0101010101010101010101010101010101010101010101010101010101010101",
        \\    "broadcastSecret": "0202020202020202020202020202020202020202020202020202020202020202"
        \\  },
        \\  "multicast": { "group": "ff15::5e:1", "port": 47100, "hops": 1, "loopback": true },
        \\  "peers": [
        \\    {
        \\      "label": "node-02",
        \\      "cellId": "0303030303030303030303030303030303030303030303030303030303030303",
        \\      "broadcastSecret": "0404040404040404040404040404040404040404040404040404040404040404"
        \\    }
        \\  ],
        \\  "meta": { "generatedAt": "x", "schema": "u2-mesh-identity/v2", "meshSize": 2 }
        \\}
    ;
    var cfg = try config_mod.parseSlice(testing.allocator, json);
    defer cfg.deinit();

    var ctx = HandlerCtx{ .config = &cfg };
    const peer_cid: [CELL_ID_LEN]u8 = .{0x03} ** CELL_ID_LEN;
    try testing.expectEqualStrings("node-02", ctx.labelForCell(&peer_cid));

    const unknown: [CELL_ID_LEN]u8 = .{0xFF} ** CELL_ID_LEN;
    try testing.expectEqualStrings("<unknown>", ctx.labelForCell(&unknown));
}

// ── Source-routing relay tests ─────────────────────────────────────────────

const CaptureCtx = struct { buf: []u8, len: usize = 0, called: bool = false };

fn captureEmit(cell: []const u8, ud: *anyopaque) void {
    const c: *CaptureCtx = @ptrCast(@alignCast(ud));
    @memcpy(c.buf[0..cell.len], cell);
    c.len = cell.len;
    c.called = true;
}

fn writeU32le(buf: []u8, off: usize, v: u32) void {
    std.mem.writeInt(u32, buf[off..][0..4], v, .little);
}

test "deriveOwnBca is deterministic + 16 bytes from the cellId" {
    const cid: [CELL_ID_LEN]u8 = .{0xAB} ** CELL_ID_LEN;
    const a = deriveOwnBca(&cid);
    const b = deriveOwnBca(&cid);
    try testing.expectEqualSlices(u8, &a, &b);
    // Distinct cellId → distinct BCA.
    const cid2: [CELL_ID_LEN]u8 = .{0xCD} ** CELL_ID_LEN;
    try testing.expect(!std.mem.eql(u8, &a, &deriveOwnBca(&cid2)));
}

test "routeReceivedCell: not_routed for short or unrouted payloads" {
    const own: [16]u8 = .{0xAB} ** 16;
    var out: [routing.CELL_SIZE]u8 = undefined;
    var cap = CaptureCtx{ .buf = &out };

    const short = [_]u8{0} ** 10;
    try testing.expect(routeReceivedCell(&short, &own, &out, captureEmit, &cap) == .not_routed);

    var full = [_]u8{0} ** routing.CELL_SIZE; // ROUTING_MODE = 0 → unrouted
    try testing.expect(routeReceivedCell(&full, &own, &out, captureEmit, &cap) == .not_routed);
    try testing.expect(!cap.called);
}

test "routeReceivedCell: delivered at the final destination" {
    const own: [16]u8 = .{0xAB} ** 16;
    var out: [routing.CELL_SIZE]u8 = undefined;
    var cap = CaptureCtx{ .buf = &out };

    var cell = [_]u8{0} ** routing.CELL_SIZE;
    cell[routing.OFF_ROUTING_MODE] = @intFromEnum(routing.RoutingMode.source_routed);
    @memcpy(cell[routing.OFF_NEXT_HOP_BCA..][0..16], &own);
    writeU32le(&cell, routing.OFF_SEGMENTS_LEFT, 0); // final dest
    _ = routing.setRoutingChecksum(&cell);

    try testing.expect(routeReceivedCell(&cell, &own, &out, captureEmit, &cap) == .delivered);
    try testing.expect(!cap.called);
}

test "routeReceivedCell: dropped not_my_hop when NEXT_HOP_BCA isn't us" {
    const own: [16]u8 = .{0xAB} ** 16;
    const other: [16]u8 = .{0x11} ** 16;
    var out: [routing.CELL_SIZE]u8 = undefined;
    var cap = CaptureCtx{ .buf = &out };

    var cell = [_]u8{0} ** routing.CELL_SIZE;
    cell[routing.OFF_ROUTING_MODE] = @intFromEnum(routing.RoutingMode.source_routed);
    @memcpy(cell[routing.OFF_NEXT_HOP_BCA..][0..16], &other);
    writeU32le(&cell, routing.OFF_SEGMENTS_LEFT, 1);
    _ = routing.setRoutingChecksum(&cell);

    const d = routeReceivedCell(&cell, &own, &out, captureEmit, &cap);
    try testing.expect(d == .dropped);
    try testing.expect(d.dropped == .not_my_hop);
    try testing.expect(!cap.called);
}

test "routeReceivedCell: forwards to the next hop and emits the advanced cell" {
    const own: [16]u8 = .{0xAB} ** 16;
    const final_dest: [16]u8 = .{0xCD} ** 16;
    var out: [routing.CELL_SIZE]u8 = undefined;
    // Separate capture buffer — emit copies out_buf into it, so it must not
    // alias `out` (overlapping @memcpy is UB / debug-panics).
    var captured: [routing.CELL_SIZE]u8 = undefined;
    var cap = CaptureCtx{ .buf = &captured };

    var cell = [_]u8{0} ** routing.CELL_SIZE;
    cell[routing.OFF_ROUTING_MODE] = @intFromEnum(routing.RoutingMode.source_routed);
    @memcpy(cell[routing.OFF_NEXT_HOP_BCA..][0..16], &own);
    @memcpy(cell[routing.OFF_FINAL_DEST_BCA..][0..16], &final_dest);
    writeU32le(&cell, routing.OFF_SEGMENTS_LEFT, 1); // last forwarding hop
    writeU32le(&cell, routing.OFF_HOP_COUNT_BUDGET, 4);
    _ = routing.setRoutingChecksum(&cell);

    try testing.expect(routeReceivedCell(&cell, &own, &out, captureEmit, &cap) == .forwarded);
    try testing.expect(cap.called);
    try testing.expectEqual(@as(usize, routing.CELL_SIZE), cap.len);
    // The forwarded cell: SEGMENTS_LEFT decremented to 0, NEXT_HOP = final dest.
    try testing.expectEqual(@as(u32, 0), std.mem.readInt(u32, out[routing.OFF_SEGMENTS_LEFT..][0..4], .little));
    try testing.expect(std.mem.eql(u8, out[routing.OFF_NEXT_HOP_BCA..][0..16], &final_dest));
    try testing.expect(routing.verifyRoutingChecksum(&out));
}

// ── MNCA tile tests ─────────────────────────────────────────────────────────

test "seedTile: header tagged, deterministic, distinct per cellId, steps cleanly" {
    const cid: [CELL_ID_LEN]u8 = .{0x7A} ** CELL_ID_LEN;
    var a: [mnca.PAYLOAD_SIZE]u8 = undefined;
    var b: [mnca.PAYLOAD_SIZE]u8 = undefined;
    seedTile(&a, 2, 3, 18, &cid);
    seedTile(&b, 2, 3, 18, &cid);
    try testing.expectEqualSlices(u8, &a, &b); // deterministic
    try testing.expectEqual(@as(u16, 2), mnca.tileX(&a));
    try testing.expectEqual(@as(u16, 3), mnca.tileY(&a));
    try testing.expectEqual(@as(u8, 18), mnca.width(&a));
    try testing.expectEqual(@as(u8, 3), mnca.haloRadius(&a));

    // Step one generation: tick increments, no panic.
    var nxt: [mnca.PAYLOAD_SIZE]u8 = undefined;
    mnca.stepTilePayload(&a, &nxt, mnca.DEFAULT_MNCA_RULE);
    try testing.expectEqual(@as(u64, 1), mnca.tick(&nxt));

    // Distinct cellId → distinct seed.
    const cid2: [CELL_ID_LEN]u8 = .{0x10} ** CELL_ID_LEN;
    var c: [mnca.PAYLOAD_SIZE]u8 = undefined;
    seedTile(&c, 2, 3, 18, &cid2);
    try testing.expect(!std.mem.eql(u8, a[mnca.OFF_STATE .. mnca.OFF_STATE + 324], c[mnca.OFF_STATE .. mnca.OFF_STATE + 324]));
}

```
