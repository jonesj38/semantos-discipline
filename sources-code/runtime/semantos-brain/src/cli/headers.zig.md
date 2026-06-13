---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cli/headers.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.284080+00:00
---

# runtime/semantos-brain/src/cli/headers.zig

```zig
// Headers cluster (BRAIN-Headers — tip / sync / reset / serve)
// extracted from src/cli.zig as Move 5 of the cli-modularize refactor.
// Pure code motion: no behaviour change.

const std = @import("std");
const cli_common = @import("common.zig");
const audit_log_mod = @import("audit_log");
const dispatcher_mod = @import("dispatcher");
const headers_handler_mod = @import("headers_handler");
const headers_http_mod = @import("headers_http");
const headers_mod_pub = @import("headers");
const headers_sync_mod = @import("headers_sync");
const p2p_wire_mod = @import("p2p_wire");
const header_store_fs_mod = @import("header_store_fs");
const reorg_sink_mod = @import("reorg_sink");
const reorg_sink_cell_store_mod = @import("reorg_sink_cell_store");
const lmdb_mod = @import("lmdb");
const lmdb_cell_store_mod = @import("lmdb_cell_store");
const lmdb_config_mod = @import("lmdb_config");

const Output = cli_common.Output;
const ExitCode = cli_common.ExitCode;
const resolveDataDir = cli_common.resolveDataDir;
const flushOutput = cli_common.flushOutput;

const DEFAULT_HEADERS_PEER = "seed.bitcoinsv.io:8333";

pub fn cmdHeaders(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    if (args.len < 1) {
        try printHeadersUsage(out);
        return .bad_args;
    }
    const sub = args[0];
    if (std.mem.eql(u8, sub, "tip")) return cmdHeadersTip(allocator, out);
    if (std.mem.eql(u8, sub, "sync")) return cmdHeadersSync(allocator, out, args[1..]);
    if (std.mem.eql(u8, sub, "reset")) return cmdHeadersReset(allocator, out, args[1..]);
    if (std.mem.eql(u8, sub, "serve")) return cmdHeadersServe(allocator, out, args[1..]);
    try out.print("unknown headers subcommand: {s}\n", .{sub});
    try printHeadersUsage(out);
    return .bad_args;
}

fn printHeadersUsage(out: *const Output) !void {
    try out.print("usage:\n", .{});
    try out.print("  brain headers tip\n", .{});
    try out.print("  brain headers sync [--peer host:port] [--max-rounds N]\n", .{});
    try out.print("  brain headers reset [--yes]\n", .{});
}

/// D-W1 Phase 2 — `brain headers tip` rewires through
/// `dispatcher.dispatch(headers, tip, {})`.  Output is byte-identical
/// to the pre-Phase-2 path: `tip:    height=N\n        hash=<be-hex>\n`
/// or `(header store empty — run `brain headers sync`)\n`.
fn cmdHeadersTip(allocator: std.mem.Allocator, out: *const Output) !ExitCode {
    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);

    var fs = header_store_fs_mod.FsHeaderStore.init(allocator, data_dir) catch |e| {
        try out.print("headers tip: cannot open store at {s}: {s}\n", .{ data_dir, @errorName(e) });
        return .file_io;
    };
    defer fs.deinit();
    const handle = fs.store();

    var audit = audit_log_mod.AuditLog.init();
    defer audit.close();
    const audit_path = try std.fs.path.join(allocator, &.{ data_dir, "audit.log" });
    defer allocator.free(audit_path);
    audit.open(audit_path) catch {};

    var handler = headers_handler_mod.Handler.init(allocator, &handle);
    var disp = dispatcher_mod.Dispatcher.init(allocator, &audit);
    defer disp.deinit();
    try disp.register(handler.resourceHandler());

    const ctx = dispatcher_mod.DispatchContext{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "cli-headers-tip", .transport_label = "embedded" },
    };
    var result = disp.dispatch(&ctx, "headers", "tip", "{}") catch |e| {
        try out.print("headers tip: dispatch failed: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer result.deinit();

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, result.payload, .{}) catch {
        try out.print("headers tip: malformed dispatcher response\n", .{});
        return .file_io;
    };
    defer parsed.deinit();
    if (parsed.value != .object) return .file_io;
    const present_v = parsed.value.object.get("present") orelse return .file_io;
    if (present_v != .bool) return .file_io;
    if (!present_v.bool) {
        try out.print("(header store empty — run `brain headers sync`)\n", .{});
        return .ok;
    }
    const height_v = parsed.value.object.get("height") orelse return .file_io;
    const hash_v = parsed.value.object.get("hash") orelse return .file_io;
    if (height_v != .integer or hash_v != .string) return .file_io;
    if (hash_v.string.len != 64) return .file_io;

    // The handler returns hash in internal-byte-order hex; the legacy
    // CLI prints reverse-byte-order (block-explorer convention).  Do
    // the byte-pair reverse here so output is byte-identical to the
    // pre-Phase-2 path.
    var be_hex: [64]u8 = undefined;
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        const src = i * 2;
        const dst = (31 - i) * 2;
        be_hex[dst] = hash_v.string[src];
        be_hex[dst + 1] = hash_v.string[src + 1];
    }
    try out.print("tip:    height={d}\n", .{height_v.integer});
    try out.print("        hash={s}\n", .{be_hex[0..]});
    return .ok;
}

/// std.net.tcpConnectToHost resolves all addresses but stops after the
/// first non-ConnectionRefused failure.  Bitcoin DNS seeds routinely
/// return a mixed peer set, so try every resolved address before
/// surfacing the last connection error.
fn tcpConnectToHostAllAddresses(
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
) !std.net.Stream {
    const list = try std.net.getAddressList(allocator, host, port);
    defer list.deinit();
    if (list.addrs.len == 0) return error.UnknownHostName;

    var last_err: anyerror = error.ConnectionRefused;
    for (list.addrs) |addr| {
        return std.net.tcpConnectToAddress(addr) catch |err| {
            last_err = err;
            continue;
        };
    }
    return last_err;
}

fn cmdHeadersSync(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    var peer: []const u8 = DEFAULT_HEADERS_PEER;
    var max_rounds: u32 = 32;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--peer") and i + 1 < args.len) {
            peer = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--max-rounds") and i + 1 < args.len) {
            max_rounds = std.fmt.parseInt(u32, args[i + 1], 10) catch {
                try out.print("headers sync: invalid --max-rounds `{s}`\n", .{args[i + 1]});
                return .bad_args;
            };
            i += 1;
        }
    }

    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);
    var fs = header_store_fs_mod.FsHeaderStore.init(allocator, data_dir) catch |e| {
        try out.print("headers sync: cannot open store at {s}: {s}\n", .{ data_dir, @errorName(e) });
        return .file_io;
    };
    defer fs.deinit();
    const handle = fs.store();

    // Resolve host + port from `host:port`.
    const colon = std.mem.lastIndexOfScalar(u8, peer, ':') orelse {
        try out.print("headers sync: --peer must be host:port (got {s})\n", .{peer});
        return .bad_args;
    };
    const host = peer[0..colon];
    const port_str = peer[colon + 1 ..];
    const port = std.fmt.parseInt(u16, port_str, 10) catch {
        try out.print("headers sync: invalid port in {s}\n", .{peer});
        return .bad_args;
    };

    try out.print("headers sync: connecting to {s}:{d} ...\n", .{ host, port });
    flushOutput(out);

    const stream = tcpConnectToHostAllAddresses(allocator, host, port) catch |e| {
        try out.print("headers sync: connect failed: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    defer stream.close();

    const start_height: i32 = if (handle.tip()) |t| @intCast(t.height) else 0;

    // BSV mainnet handshake.
    var nonce_bytes: [8]u8 = undefined;
    std.crypto.random.bytes(&nonce_bytes);
    const nonce = std.mem.readInt(u64, &nonce_bytes, .little);
    const ts = std.time.timestamp();

    var read_buf: [4096]u8 = undefined;
    var write_buf: [4096]u8 = undefined;
    var stream_reader = stream.reader(&read_buf);
    var stream_writer = stream.writer(&write_buf);
    const reader = stream_reader.interface();
    const writer = &stream_writer.interface;

    headers_sync_mod.handshake(
        writer,
        reader,
        p2p_wire_mod.MAGIC_MAINNET,
        nonce,
        "/brain:0.1.0/",
        start_height,
        ts,
    ) catch |e| {
        try out.print("headers sync: handshake failed: {s}\n", .{@errorName(e)});
        flushOutput(out);
        return .file_io;
    };
    try out.print("  ✓ handshake complete; requesting headers...\n", .{});
    flushOutput(out);

    // Tee the wire-message log to stderr so the operator sees what
    // each round actually negotiated.  Costs ~one line per inbound
    // message; cheap.
    var stderr_buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const trace_w: *std.Io.Writer = &stderr_writer.interface;

    var rounds: u32 = 0;
    var total_appended: u32 = 0;
    while (rounds < max_rounds) : (rounds += 1) {
        const got = headers_sync_mod.fetchOneRound(
            allocator,
            writer,
            reader,
            p2p_wire_mod.MAGIC_MAINNET,
            &handle,
            headers_mod_pub.POW_LIMIT_BITS,
            trace_w,
        ) catch |e| {
            try out.print("headers sync: round {d} failed: {s}\n", .{ rounds + 1, @errorName(e) });
            flushOutput(out);
            return .file_io;
        };
        total_appended += got;
        try out.print("  round {d}: +{d} headers\n", .{ rounds + 1, got });
        flushOutput(out);
        if (got < 2000) break;
    }
    if (handle.tip()) |t| {
        try out.print("\nhead store tip: height {d}\n", .{t.height});
    }
    try out.print("appended:       {d} headers across {d} round(s)\n", .{ total_appended, rounds + 1 });
    return .ok;
}

fn cmdHeadersReset(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    var confirmed = false;
    for (args) |a| {
        if (std.mem.eql(u8, a, "--yes")) confirmed = true;
    }
    if (!confirmed) {
        try out.print("headers reset: pass --yes to confirm — this wipes <data-dir>/headers.bin and headers.idx\n", .{});
        return .bad_args;
    }

    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);
    const headers_bin = try std.fs.path.join(allocator, &.{ data_dir, "headers.bin" });
    defer allocator.free(headers_bin);
    const headers_idx = try std.fs.path.join(allocator, &.{ data_dir, "headers.idx" });
    defer allocator.free(headers_idx);

    var deleted: u32 = 0;
    if (std.fs.cwd().deleteFile(headers_bin)) |_| {
        deleted += 1;
    } else |_| {}
    if (std.fs.cwd().deleteFile(headers_idx)) |_| {
        deleted += 1;
    } else |_| {}
    try out.print("headers reset: deleted {d} file(s)\n", .{deleted});
    return .ok;
}

// ─────────────────────────────────────────────────────────────────────
// WH-Producer phase 2 — `brain headers serve`
// Long-running mode: spins a background tip-subscription thread that
// runs `headers sync` style fetches every `--sync-interval-secs` (60
// by default), and a foreground HTTP server exposing the
// BHS-compatible API the browser bundle's `header-source-adapter.ts`
// hits.
// ─────────────────────────────────────────────────────────────────────

const ServeContext = struct {
    allocator: std.mem.Allocator,
    peer: []const u8,
    sync_interval_secs: u32,
    cancel: *std.atomic.Value(bool),
    tip_log: std.fs.File,
    /// Shared store — the same instance the HTTP server reads from.
    /// Protected by `mutex`; hold the lock whenever calling any store method.
    fs: *header_store_fs_mod.FsHeaderStore,
    mutex: *std.Thread.Mutex,
    /// Index into DEFAULT_REORG_SCHEDULE. Advances each time a rollback
    /// at the current depth still produces a reorg on the following poll.
    /// Resets to 0 after a clean sync (got > 0 headers without a reorg).
    reorg_depth_idx: usize = 0,
    /// D-LC5 — cartridge → brain reorg sweep callback. When non-null,
    /// `attemptReorgRecovery` invokes this after a successful header-
    /// store rollback so brain's per-cell anchor-status projection
    /// gets its `.pending` entries at heights >= rollback_floor
    /// cleared. Null means no sweep (e.g. early-deploy brains where
    /// the entity LMDB env couldn't be opened, or tests).
    ///
    /// Lifetime: the sink's backing `ReorgSinkCellStore` is owned by
    /// `cmdHeadersServe`'s stack frame and outlives this context.
    reorg_sink: ?*const reorg_sink_mod.ReorgSink = null,
};

fn cmdHeadersServe(allocator: std.mem.Allocator, out: *const Output, args: []const [:0]u8) !ExitCode {
    var http_port: u16 = 8334;
    var peer: []const u8 = DEFAULT_HEADERS_PEER;
    var sync_interval_secs: u32 = 60;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--http-port") and i + 1 < args.len) {
            http_port = std.fmt.parseInt(u16, args[i + 1], 10) catch {
                try out.print("headers serve: invalid --http-port `{s}`\n", .{args[i + 1]});
                return .bad_args;
            };
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--peer") and i + 1 < args.len) {
            peer = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--sync-interval-secs") and i + 1 < args.len) {
            sync_interval_secs = std.fmt.parseInt(u32, args[i + 1], 10) catch {
                try out.print("headers serve: invalid --sync-interval-secs `{s}`\n", .{args[i + 1]});
                return .bad_args;
            };
            i += 1;
        }
    }

    const data_dir = try resolveDataDir(allocator);
    defer allocator.free(data_dir);

    var fs = header_store_fs_mod.FsHeaderStore.init(allocator, data_dir) catch |e| {
        try out.print("headers serve: cannot open store at {s}: {s}\n", .{ data_dir, @errorName(e) });
        return .file_io;
    };
    defer fs.deinit();
    const handle = fs.store();

    try out.print("brain headers serve\n", .{});
    try out.print("  data_dir:           {s}\n", .{data_dir});
    try out.print("  http listen:        0.0.0.0:{d}\n", .{http_port});
    try out.print("  peer:               {s}\n", .{peer});
    try out.print("  sync interval:      {d}s\n", .{sync_interval_secs});
    if (handle.tip()) |t| {
        try out.print("  starting tip:       height {d}\n", .{t.height});
    } else {
        try out.print("  starting tip:       empty (will sync from genesis)\n", .{});
    }
    try out.print("\nCtrl-C to stop.\n", .{});
    flushOutput(out);

    var cancel: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
    var mutex: std.Thread.Mutex = .{};

    // D-LC5 — open the entity LMDB env and wrap its `LmdbCellStore`
    // in a `ReorgSinkCellStore`. The sink lets `attemptReorgRecovery`
    // clear `.pending` anchor projections at heights >= rollback_floor
    // without the cartridge crossing into brain's source tree.
    //
    // Best-effort: if the env / store init fails, we leave `reorg_sink`
    // null and the recovery path runs unchanged (no sweep). The chain
    // rollback always completes; the only observable downgrade is that
    // `.pending` entries from a reorged-away attestation remain until
    // the next attestation observer pass re-confirms or clears them.
    // This matches the early-deploy posture (V1 production is test
    // data per project memory).
    const entity_lmdb_path = try std.fs.path.join(
        allocator,
        &.{ data_dir, "entity_cells_lmdb" },
    );
    defer allocator.free(entity_lmdb_path);
    std.fs.makeDirAbsolute(entity_lmdb_path) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => {
            try out.print("headers serve: anchor-sweep dir create failed: {s} (sweep disabled)\n", .{@errorName(e)});
        },
    };

    var entity_env: ?lmdb_mod.Env = lmdb_mod.Env.open(entity_lmdb_path, .{
        .open_flags = lmdb_config_mod.LmdbConfig.prod_flags,
        .map_size = lmdb_config_mod.LmdbConfig.default.map_size,
        .max_dbs = lmdb_config_mod.LmdbConfig.default.max_dbs,
        .mode = lmdb_config_mod.LmdbConfig.default.mode,
    }) catch |e| blk: {
        try out.print("headers serve: anchor-sweep LMDB env open failed: {s} (sweep disabled)\n", .{@errorName(e)});
        break :blk null;
    };
    defer if (entity_env) |*env| env.close();

    var cell_store_impl: ?lmdb_cell_store_mod.LmdbCellStore = null;
    if (entity_env) |*env| {
        cell_store_impl = lmdb_cell_store_mod.LmdbCellStore.init(env, allocator) catch |e| blk: {
            try out.print("headers serve: anchor-sweep cell-store init failed: {s} (sweep disabled)\n", .{@errorName(e)});
            break :blk null;
        };
    }

    var sink_wrapper: ?reorg_sink_cell_store_mod.ReorgSinkCellStore = null;
    if (cell_store_impl) |*impl| {
        sink_wrapper = reorg_sink_cell_store_mod.ReorgSinkCellStore.init(impl);
    }
    // The vtable shape (`*const ReorgSink`) needs a stable pointer; the
    // sink struct lives in `sink_wrapper`'s value, so we stash the
    // sink view in a local that survives until `cmdHeadersServe`
    // returns. Both `sink_wrapper` and `sink_view` outlive `ctx`.
    var sink_view: ?reorg_sink_mod.ReorgSink = null;
    if (sink_wrapper) |*w| {
        sink_view = w.sink();
    }

    var ctx: ServeContext = .{
        .allocator = allocator,
        .peer = peer,
        .sync_interval_secs = sync_interval_secs,
        .cancel = &cancel,
        .tip_log = std.fs.File.stderr(),
        .fs = &fs,
        .mutex = &mutex,
        .reorg_sink = if (sink_view) |*sv| sv else null,
    };
    const thread = try std.Thread.spawn(.{}, tipSubscriptionLoop, .{&ctx});
    defer {
        cancel.store(true, .release);
        thread.join();
    }

    var http = headers_http_mod.HeadersHttp.init(allocator, &handle, http_port);
    http.mutex = &mutex;
    http.serve(&cancel) catch |e| {
        try out.print("headers serve: HTTP listener died: {s}\n", .{@errorName(e)});
        return .file_io;
    };
    return .ok;
}

/// Background loop: every `sync_interval_secs`, reconnect to `peer`
/// and run one round of fetchOneRound.  Logs results to stderr.
/// Exits when `cancel.load(.acquire) == true`.
fn tipSubscriptionLoop(ctx: *ServeContext) void {
    while (!ctx.cancel.load(.acquire)) {
        runOneTipPoll(ctx) catch |err| {
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "[headers serve] tip poll: {s}\n", .{@errorName(err)}) catch "tip poll error\n";
            _ = ctx.tip_log.write(msg) catch {};
        };
        var slept: u32 = 0;
        while (slept < ctx.sync_interval_secs and !ctx.cancel.load(.acquire)) {
            std.Thread.sleep(std.time.ns_per_s);
            slept += 1;
        }
    }
}

fn runOneTipPoll(ctx: *ServeContext) !void {
    // Use the shared store so the HTTP server sees updates immediately.
    // Hold the mutex for the entire poll — P2P IO happens outside the lock
    // (connect + handshake), then we lock only for the store-mutating work.
    const colon = std.mem.lastIndexOfScalar(u8, ctx.peer, ':') orelse return error.bad_peer;
    const host = ctx.peer[0..colon];
    const port = std.fmt.parseInt(u16, ctx.peer[colon + 1 ..], 10) catch return error.bad_peer;

    const stream = try tcpConnectToHostAllAddresses(ctx.allocator, host, port);
    defer stream.close();

    var read_buf: [4096]u8 = undefined;
    var write_buf: [4096]u8 = undefined;
    var stream_reader = stream.reader(&read_buf);
    var stream_writer = stream.writer(&write_buf);
    const reader = stream_reader.interface();
    const writer = &stream_writer.interface;

    var nonce_bytes: [8]u8 = undefined;
    std.crypto.random.bytes(&nonce_bytes);
    const nonce = std.mem.readInt(u64, &nonce_bytes, .little);
    const ts = std.time.timestamp();

    ctx.mutex.lock();
    const handle = ctx.fs.store();
    const start_height: i32 = if (handle.tip()) |t| @intCast(t.height) else 0;
    ctx.mutex.unlock();

    try headers_sync_mod.handshake(
        writer,
        reader,
        p2p_wire_mod.MAGIC_MAINNET,
        nonce,
        "/brain:0.1.0/",
        start_height,
        ts,
    );

    // Lock around fetchOneRound + rollback so the HTTP server sees a
    // consistent store state. The lock covers network receive too — that's
    // bounded to the peer's response time (< 1s typical) and avoids the
    // complexity of splitting locator-build from append.
    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    const locked_handle = ctx.fs.store();
    const got = headers_sync_mod.fetchOneRound(
        ctx.allocator,
        writer,
        reader,
        p2p_wire_mod.MAGIC_MAINNET,
        &locked_handle,
        headers_mod_pub.POW_LIMIT_BITS,
        null,
    ) catch |err| switch (err) {
        error.reorg_detected => {
            // Use the persistent schedule index so each successive reorg
            // on the same chain escalates to a deeper rollback rather than
            // retrying depth=1 forever. Index resets to 0 after a clean sync.
            const schedule = headers_sync_mod.DEFAULT_REORG_SCHEDULE;
            const idx = ctx.reorg_depth_idx;
            const depth = schedule[if (idx < schedule.len) idx else schedule.len - 1];
            // D-LC5 — pass the cartridge → brain anchor-status sweep
            // sink. When `ctx.reorg_sink` is null (no LmdbCellStore was
            // opened — e.g. early-deploy brains without anchor data,
            // or tests), the recovery still completes; the sweep is a
            // no-op. Sweep failures don't fail the recovery — they
            // surface in the report so we can log them.
            const report = headers_sync_mod.attemptReorgRecovery(
                &locked_handle,
                depth,
                ctx.reorg_sink,
            ) catch {
                var buf: [160]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "[headers serve] reorg detected: rollback at depth={d} failed\n", .{depth}) catch return;
                _ = ctx.tip_log.write(msg) catch {};
                return;
            };
            if (report.rolled > 0) {
                // Advance schedule for the next poll — if the reorg persists
                // we will try a deeper rollback rather than looping at depth=1.
                ctx.reorg_depth_idx = if (idx + 1 < schedule.len) idx + 1 else schedule.len - 1;
                var buf: [160]u8 = undefined;
                const msg = std.fmt.bufPrint(
                    &buf,
                    "[headers serve] reorg detected: rolled back {d} headers (depth={d}); next poll will re-sync\n",
                    .{ report.rolled, depth },
                ) catch return;
                _ = ctx.tip_log.write(msg) catch {};
                // D-LC5 — log the anchor-status sweep result. The
                // sweep call already happened inside
                // attemptReorgRecovery (under the same store mutex);
                // here we just narrate what landed. Three possible
                // shapes:
                //   * sweep != null      → sink ran cleanly
                //   * sweep_error != null → sink errored (recovery
                //     still succeeded; pending entries may be stale
                //     until the next attestation observer pass)
                //   * both null           → no sink attached (early-
                //     deploy / test brain)
                if (report.sweep) |s| {
                    var sb: [200]u8 = undefined;
                    const m = std.fmt.bufPrint(
                        &sb,
                        "[headers serve] reorg sweep: swept={d} kept={d} from_height={?d}\n",
                        .{ s.swept, s.kept, report.from_height },
                    ) catch return;
                    _ = ctx.tip_log.write(m) catch {};
                } else if (report.sweep_error) |e| {
                    var sb: [200]u8 = undefined;
                    const m = std.fmt.bufPrint(
                        &sb,
                        "[headers serve] reorg sweep failed: {s} (recovery still completed; pending projections may remain until re-sync)\n",
                        .{@errorName(e)},
                    ) catch return;
                    _ = ctx.tip_log.write(m) catch {};
                }
            } else {
                // depth was already deeper than the chain — log and bail.
                var buf: [160]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "[headers serve] reorg detected: could not roll back to a recoverable depth\n", .{}) catch return;
                _ = ctx.tip_log.write(msg) catch {};
            }
            return;
        },
        else => return err,
    };
    if (got > 0) {
        ctx.reorg_depth_idx = 0; // clean sync — reset escalation
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "[headers serve] tip poll: +{d} headers\n", .{got}) catch return;
        _ = ctx.tip_log.write(msg) catch {};
    }
}


```
