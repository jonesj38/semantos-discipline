---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/cartridge_boot.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.028063+00:00
---

# runtime/semantos-brain/cartridge_boot.zig

```zig
// cartridge_boot — the universal multi-cartridge boot sequence.
//
// Design: docs/design/UNIVERSAL-CARTRIDGE-BOOT.md
// Replaces the N×3 hand-edited per-cartridge blocks in
// src/cli/serve.zig with one declarative table + one generic pass.
//
// GREENFIELD: this file lives at runtime/semantos-brain/ — OUTSIDE
// src/ — exactly like build.zig, so the no-X-in-brain-core gate
// (which greps runtime/semantos-brain/src/) is satisfied while the
// table still names cartridge modules. It is generic loader infra,
// not hand-baked cartridge logic (build.zig precedent, design §4).
//
// Two gates (design §3.5), both PRESERVING current behaviour:
//   1. Compilation-substrate gate — the caller invokes registerInto
//      only inside the same `--enable-repl` condition as today (the
//      REPL is how conversation compiles to executables; intentional).
//      constructAll runs unconditionally at top cmdServe scope, as the
//      per-cartridge inits do today, so store lifetimes are unchanged.
//   2. Entitlement gate — per-cartridge marketplace hook. Ships
//      defaulting to .granted (zero behaviour change); the licensing
//      mechanism is a named follow-up (design §6b).

const std = @import("std");
const verb_dispatcher = @import("verb_dispatcher");
// P3d — the substrate entity CellStore interface (late-bound at boot
// for cartridges that persist minted cells). Interface only; the
// LMDB impl is brain-core's, injected by serve.zig.
const cell_store = @import("cell_store");

// Cartridge brain modules (named here, in the out-of-src loader infra,
// never in src/ — the whole point of this file's location).
const jambox_walkers = @import("jambox_walkers");
const jam_clip_state_store = @import("jam_clip_state_store");
const chess_walkers = @import("chess_walkers");
const chess_game_store = @import("chess_game_store");
const chess_wallet_port = @import("chess_wallet_port");
const tessera_walkers = @import("tessera_walkers");
const tessera_store = @import("tessera_store");
// P3b — tessera's entity-type SPECs for the generic cell-mint path.
const tessera_cell_specs = @import("tessera_cell_specs");
const substrate_entity = @import("substrate_entity"); // P3b test assertion
// P-boot-rebuild — replay CellStore into the tessera domain-id index
// (closes the unknown_predecessor window P4c hits at fresh boot
// before any walker mint has run).
const tessera_index_rebuild = @import("tessera_index_rebuild");

// swarm cartridge — paid file-distribution cold-path control plane (M5).
// In-memory tracker + 4 RPC walkers; M6 binds the CellStore for persistence.
const swarm_walkers = @import("swarm_walkers");
const swarm_tracker = @import("swarm_tracker");
const swarm_index_rebuild = @import("swarm_index_rebuild");

pub const Surface = enum { walkers, cells };

/// Marketplace gate result (design §3.5 / §6b). The mechanism that
/// decides this (license cells, revocation, …) is a separate design;
/// here it is only the enforcement seam.
pub const Entitlement = enum { granted, restricted, absent };
pub const EntitlementFn = *const fn (id: []const u8) Entitlement;

pub fn grantAll(_: []const u8) Entitlement {
    return .granted;
}

pub const BootDeps = struct {
    allocator: std.mem.Allocator,
    /// Production Unix-seconds clock (cli_common.realClock in serve).
    clock_fn: *const fn () i64,
    /// Optional Phase-2 chess wallet wiring. ALL four must be present to
    /// activate; any null → chess store stays Phase-1 (no money). Tests
    /// leave them null; serve.zig wires them at production boot.
    chess_manifest_json: ?[]const u8 = null,
    chess_queue_dir: ?[]const u8 = null,
    chess_consumer_cert: ?[]const u8 = null,
    /// Production threads `chess_native_bridge.nativeConsumeFn()` here
    /// so the port's kernel-consume primitive resolves to the real
    /// `semantos_linear_consume` extern at link time.
    chess_consume_fn: ?chess_wallet_port.KernelConsumeFn = null,
};

/// One declarative cartridge entry. The fn pointers are type-erased
/// over each cartridge's heterogeneous Store/State shapes — the
/// per-cartridge `Spec` structs below own the concrete types.
const Spec = struct {
    id: []const u8,
    surface: Surface,
    /// Heap-allocate {Store,State}; return an opaque owned handle whose
    /// address is stable for the wss_backend lifetime.
    construct: *const fn (BootDeps) anyerror!*anyopaque,
    /// Register this cartridge's verbs into the dispatcher.
    register: *const fn (*anyopaque, *verb_dispatcher.Registry) anyerror!void,
    /// Tear down the handle (store.deinit + destroy).
    destroy: *const fn (std.mem.Allocator, *anyopaque) void,
    /// P3b — optional: register this cartridge's entity-type SPECs into
    /// the substrate registry so its cells are mintable via
    /// `entity.encode`. Static per cartridge (no handle needed),
    /// idempotent, called under the same gate as `register`.
    register_cells: ?*const fn () anyerror!void = null,
    /// P3d — optional: late-bind the entity CellStore into this
    /// cartridge's State so minted cells persist. Called from
    /// serve.zig's --enable-repl block AFTER the store is up (it does
    /// not exist at constructAll time). No-op for cartridges that
    /// don't persist.
    bind_cell_store: ?*const fn (*anyopaque, *const cell_store.CellStore) void = null,
};

// ── jambox (P1 proof — behaviour-identical to serve.zig ~860/~1686) ──
const JamboxSpec = struct {
    const Bundle = struct {
        store: jam_clip_state_store.Store,
        state: jambox_walkers.State,
    };
    fn construct(d: BootDeps) anyerror!*anyopaque {
        const b = try d.allocator.create(Bundle);
        b.store = jam_clip_state_store.Store.init(d.allocator, d.clock_fn);
        // State holds &b.store — stable because b is heap-allocated and
        // owned by CartridgeRuntime for the wss_backend lifetime.
        b.state = .{ .clock_fn = d.clock_fn, .jam_clip_store = &b.store };
        return b;
    }
    fn register(h: *anyopaque, reg: *verb_dispatcher.Registry) anyerror!void {
        const b: *Bundle = @ptrCast(@alignCast(h));
        try jambox_walkers.registerAll(reg, &b.state);
    }
    fn destroy(a: std.mem.Allocator, h: *anyopaque) void {
        const b: *Bundle = @ptrCast(@alignCast(h));
        b.store.deinit();
        a.destroy(b);
    }
};

// ── chess (P2 — boot wiring + optional Phase-2 wallet attach) ────────
const ChessSpec = struct {
    const Bundle = struct {
        store: chess_game_store.Store,
        state: chess_walkers.State,
        // Phase-2 wallet wiring: filled iff all four chess BootDeps
        // fields are non-null. Bundle is heap-allocated once, so
        // taking &bundle.manifest / &bundle.port is stable for the
        // Port.ctx / WalletPort.ctx pointers.
        manifest: chess_wallet_port.Manifest = .{},
        port: chess_wallet_port.Port = undefined,
        wallet_active: bool = false,
    };
    fn construct(d: BootDeps) anyerror!*anyopaque {
        const b = try d.allocator.create(Bundle);
        b.* = .{
            .store = chess_game_store.Store.init(d.allocator, d.clock_fn),
            .state = undefined,
        };
        b.state = .{ .store = &b.store };

        // Attach the Phase-2 wallet iff every field is wired. Any null
        // → chess stays Phase-1 (Store's optional WalletPort seam handles
        // it; verbs work, just no real escrow).
        if (d.chess_manifest_json) |json|
            if (d.chess_queue_dir) |qdir|
                if (d.chess_consumer_cert) |cert|
                    if (d.chess_consume_fn) |consume_fn| {
                        b.manifest = chess_wallet_port.loadManifestJson(d.allocator, json) catch |err| {
                            std.debug.print("chess: manifest parse failed ({any}); skipping wallet attach\n", .{err});
                            return b;
                        };
                        b.port = chess_wallet_port.Port.init(
                            d.allocator,
                            &b.manifest,
                            qdir,
                            cert,
                            consume_fn,
                            d.clock_fn,
                        );
                        b.store.attachWallet(b.port.portInterface());
                        b.wallet_active = true;
                    };
        return b;
    }
    fn register(h: *anyopaque, reg: *verb_dispatcher.Registry) anyerror!void {
        const b: *Bundle = @ptrCast(@alignCast(h));
        try chess_walkers.registerAll(reg, &b.state);
    }
    fn destroy(a: std.mem.Allocator, h: *anyopaque) void {
        const b: *Bundle = @ptrCast(@alignCast(h));
        b.store.deinit();
        a.destroy(b);
    }
};

// ── tessera (P2 — first boot wiring; greenfield: this loader is the
//    ONLY place tessera is named brain-side, and it is OUTSIDE src/) ─
const TesseraSpec = struct {
    const Bundle = struct {
        store: tessera_store.Store,
        state: tessera_walkers.State,
    };
    fn construct(d: BootDeps) anyerror!*anyopaque {
        const b = try d.allocator.create(Bundle);
        // tessera_store.Store.init takes no clock (in-memory provenance
        // state machine; deterministic, no wall-clock dependency).
        b.store = tessera_store.Store.init(d.allocator);
        b.state = .{ .store = &b.store };
        return b;
    }
    fn register(h: *anyopaque, reg: *verb_dispatcher.Registry) anyerror!void {
        const b: *Bundle = @ptrCast(@alignCast(h));
        try tessera_walkers.registerAll(reg, &b.state);
    }
    fn destroy(a: std.mem.Allocator, h: *anyopaque) void {
        const b: *Bundle = @ptrCast(@alignCast(h));
        b.store.deinit();
        a.destroy(b);
    }
    /// P3d — late-bind the entity CellStore so harvest (and future
    /// minting verbs) persist. The handle/State is the same heap
    /// Bundle constructAll created; setting the field is safe because
    /// nothing dispatches before serve.zig finishes the boot block.
    ///
    /// P-boot-rebuild — once the CellStore is bound, replay it into
    /// the per-cartridge domain-id index so the P4c consume helpers
    /// can resolve predecessors that were minted in a prior process
    /// run. Best-effort: any error logs and the boot continues
    /// (binding is still in place; the index just stays at whatever
    /// state the rebuild reached before the error).
    fn bindCellStore(h: *anyopaque, ecs: *const cell_store.CellStore) void {
        const b: *Bundle = @ptrCast(@alignCast(h));
        b.state.cell_store = ecs;
        tessera_index_rebuild.rebuildFromCellStore(b.store.allocator, &b.store, ecs) catch |e| {
            std.log.warn("cartridge_boot: domain-id index rebuild failed: {s}", .{@errorName(e)});
        };
    }
};

// ── swarm (M5 — paid file-distribution; cold-path tracker + settlement) ──
// Mirrors the tessera shape minus persistence (M6 adds bind_cell_store). The
// tracker is in-memory; construct needs no CellStore (bound later).
const SwarmSpec = struct {
    const Bundle = struct {
        tracker: swarm_tracker.Tracker,
        state: swarm_walkers.State,
    };
    fn construct(d: BootDeps) anyerror!*anyopaque {
        const b = try d.allocator.create(Bundle);
        b.tracker = swarm_tracker.Tracker.init(d.allocator);
        // State holds &b.tracker — stable because b is heap-allocated and
        // owned by CartridgeRuntime for the wss_backend lifetime.
        b.state = .{ .tracker = &b.tracker, .clock_fn = d.clock_fn };
        return b;
    }
    fn register(h: *anyopaque, reg: *verb_dispatcher.Registry) anyerror!void {
        const b: *Bundle = @ptrCast(@alignCast(h));
        // Legacy "swarm.*" + the canonical "transfer.*" primitive — same tracker.
        try swarm_walkers.registerAllAs(reg, &b.state, "swarm");
        try swarm_walkers.registerAllAs(reg, &b.state, "transfer");
    }
    fn destroy(a: std.mem.Allocator, h: *anyopaque) void {
        const b: *Bundle = @ptrCast(@alignCast(h));
        b.tracker.deinit();
        a.destroy(b);
    }
    /// M6 — late-bind the CellStore so publish persists manifests + settle mints
    /// receipts, then replay persisted manifests into the tracker so a restarted
    /// node answers swarm.locate without re-downloading. Best-effort rebuild.
    fn bindCellStore(h: *anyopaque, ecs: *const cell_store.CellStore) void {
        const b: *Bundle = @ptrCast(@alignCast(h));
        b.state.cell_store = ecs;
        swarm_index_rebuild.rebuildTrackerFromCellStore(b.tracker.allocator, &b.tracker, ecs) catch |e| {
            std.log.warn("cartridge_boot: swarm tracker rebuild failed: {s}", .{@errorName(e)});
        };
    }
};

/// THE TABLE. Adding a cartridge = one row (P4: generated from
/// cartridge.json). chess + tessera were the deferred shared-boot-path
/// items — now just two more rows (the whole point of this design).
const TABLE = [_]Spec{
    .{
        .id = "jambox",
        .surface = .walkers,
        .construct = JamboxSpec.construct,
        .register = JamboxSpec.register,
        .destroy = JamboxSpec.destroy,
    },
    .{
        .id = "chess",
        .surface = .walkers,
        .construct = ChessSpec.construct,
        .register = ChessSpec.register,
        .destroy = ChessSpec.destroy,
    },
    .{
        .id = "tessera",
        .surface = .walkers,
        .construct = TesseraSpec.construct,
        .register = TesseraSpec.register,
        .destroy = TesseraSpec.destroy,
        // P3b — contribute tessera's 10 entity-type SPECs at boot.
        .register_cells = tessera_cell_specs.registerAll,
        // P3d — late-bind the entity CellStore so harvest persists.
        .bind_cell_store = TesseraSpec.bindCellStore,
    },
    .{
        .id = "swarm",
        .surface = .walkers,
        .construct = SwarmSpec.construct,
        .register = SwarmSpec.register,
        .destroy = SwarmSpec.destroy,
        // M6 — persist manifests + receipts; rebuild tracker from the store.
        .bind_cell_store = SwarmSpec.bindCellStore,
    },
};

const Live = struct {
    id: []const u8,
    surface: Surface,
    handle: *anyopaque,
    register: *const fn (*anyopaque, *verb_dispatcher.Registry) anyerror!void,
    destroy: *const fn (std.mem.Allocator, *anyopaque) void,
    register_cells: ?*const fn () anyerror!void,
    bind_cell_store: ?*const fn (*anyopaque, *const cell_store.CellStore) void,
};

pub const CartridgeRuntime = struct {
    allocator: std.mem.Allocator,
    live: std.ArrayList(Live),

    /// Construct every table cartridge (heap-owned, stable addresses).
    /// UNCONDITIONAL — mirrors the per-cartridge top-scope inits in
    /// cmdServe today; gate 1 is enforced by WHERE the caller invokes
    /// registerInto, not here.
    pub fn constructAll(deps: BootDeps) !CartridgeRuntime {
        var rt = CartridgeRuntime{
            .allocator = deps.allocator,
            .live = .{},
        };
        errdefer rt.deinit();
        for (TABLE) |spec| {
            const handle = try spec.construct(deps);
            try rt.live.append(deps.allocator, .{
                .id = spec.id,
                .surface = spec.surface,
                .handle = handle,
                .register = spec.register,
                .destroy = spec.destroy,
                .register_cells = spec.register_cells,
                .bind_cell_store = spec.bind_cell_store,
            });
        }
        return rt;
    }

    /// Register granted cartridges' verbs. Called from the SAME
    /// compilation-substrate condition as the legacy hand-written
    /// registerAll calls (gate 1, preserved). Per-cartridge entitlement
    /// is gate 2: restricted/absent are skipped here — the
    /// "visible-but-inert stub" UX is the deferred licensing design
    /// (§6b); the seam (this switch) is what ships now.
    pub fn registerInto(
        self: *CartridgeRuntime,
        reg: *verb_dispatcher.Registry,
        entitlement: EntitlementFn,
    ) !void {
        for (self.live.items) |lc| {
            switch (entitlement(lc.id)) {
                .granted => {
                    try lc.register(lc.handle, reg);
                    // P3b — same gate as verbs: a cartridge's cell-type
                    // SPECs only matter if its verbs route. Idempotent.
                    if (lc.register_cells) |rc| try rc();
                },
                .restricted, .absent => {}, // §6b follow-up
            }
        }
    }

    /// P3d — late-bind the entity CellStore into every cartridge that
    /// opts in (`bind_cell_store`). Called from serve.zig's
    /// --enable-repl block once the store is up (it does not exist at
    /// constructAll time). Unconditional by design: binding a store
    /// into a cartridge's heap State is inert if the cartridge's verbs
    /// were not registered (entitlement gate still governs routing);
    /// keeping it ungated avoids coupling boot order to the gate.
    pub fn bindCellStore(self: *CartridgeRuntime, ecs: *const cell_store.CellStore) void {
        for (self.live.items) |lc| {
            if (lc.bind_cell_store) |bind| bind(lc.handle, ecs);
        }
    }

    pub fn deinit(self: *CartridgeRuntime) void {
        for (self.live.items) |lc| lc.destroy(self.allocator, lc.handle);
        self.live.deinit(self.allocator);
    }
};

// ─── Tests ───────────────────────────────────────────────────────────

const testing = std.testing;

fn testClock() i64 {
    return 1_000_000;
}

fn hasId(rt: *CartridgeRuntime, id: []const u8) bool {
    for (rt.live.items) |lc| if (std.mem.eql(u8, lc.id, id)) return true;
    return false;
}

test "constructAll builds every table cartridge with stable handles" {
    var rt = try CartridgeRuntime.constructAll(.{
        .allocator = testing.allocator,
        .clock_fn = testClock,
    });
    defer rt.deinit();
    try testing.expectEqual(TABLE.len, rt.live.items.len);
    // Order-independent: every declared cartridge constructed.
    try testing.expect(hasId(&rt, "jambox"));
    try testing.expect(hasId(&rt, "chess"));
    try testing.expect(hasId(&rt, "tessera"));
}

test "registerInto with grantAll registers ALL table cartridges through the real Registry" {
    var rt = try CartridgeRuntime.constructAll(.{
        .allocator = testing.allocator,
        .clock_fn = testClock,
    });
    defer rt.deinit();
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try rt.registerInto(&reg, grantAll);
    try testing.expect(reg.hasExtension("jambox")); // launch_clip + record_take
    try testing.expect(reg.hasExtension("chess")); // 7 verbs
    try testing.expect(reg.hasExtension("tessera")); // 14 verbs
    // jambox 2 + chess 7 + tessera 14 = 23 (lower-bounded to stay
    // robust if a cartridge adds verbs).
    try testing.expect(reg.count() >= 23);
}

test "entitlement gate: restricted/absent cartridges are not registered" {
    const S = struct {
        fn deny(_: []const u8) Entitlement {
            return .restricted;
        }
    };
    var rt = try CartridgeRuntime.constructAll(.{
        .allocator = testing.allocator,
        .clock_fn = testClock,
    });
    defer rt.deinit();
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try rt.registerInto(&reg, S.deny);
    try testing.expectEqual(@as(usize, 0), reg.count());
    try testing.expect(!reg.hasExtension("jambox"));
}

test "constructAll is unconditional; registerInto is the gated step (lifetime split)" {
    // Mirrors serve.zig: construct at top scope (always), register only
    // inside the compilation-substrate condition. A runtime can be
    // constructed and torn down WITHOUT ever registering.
    var rt = try CartridgeRuntime.constructAll(.{
        .allocator = testing.allocator,
        .clock_fn = testClock,
    });
    rt.deinit(); // no registerInto call — must be clean (no leak/crash)
}

test "P3b: registerInto(grantAll) also contributes cartridge cell SPECs" {
    substrate_entity.resetRegisteredSpecsForTest();
    defer substrate_entity.resetRegisteredSpecsForTest();
    var rt = try CartridgeRuntime.constructAll(.{
        .allocator = testing.allocator,
        .clock_fn = testClock,
    });
    defer rt.deinit();
    // Before registration the tessera cell tag is unknown to the
    // substrate mint path.
    try testing.expectEqual(
        @as(?substrate_entity.EntityTypeSpec, null),
        substrate_entity.specByTag(tessera_cell_specs.TESSERA_CELL_TAG_BASE),
    );
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try rt.registerInto(&reg, grantAll);
    // The registerCells pass ran under the granted gate: tessera's
    // cell SPECs are now resolvable via the generic mint lookup.
    const s = substrate_entity.specByTag(tessera_cell_specs.TESSERA_CELL_TAG_BASE).?;
    try testing.expectEqualStrings("tessera.grape-lot", s.type_path);
}

test "P3b: restricted cartridge contributes NO cell SPECs (gate 2 holds)" {
    const S = struct {
        fn deny(_: []const u8) Entitlement {
            return .restricted;
        }
    };
    substrate_entity.resetRegisteredSpecsForTest();
    defer substrate_entity.resetRegisteredSpecsForTest();
    var rt = try CartridgeRuntime.constructAll(.{
        .allocator = testing.allocator,
        .clock_fn = testClock,
    });
    defer rt.deinit();
    var reg = verb_dispatcher.Registry.init(testing.allocator);
    defer reg.deinit();
    try rt.registerInto(&reg, S.deny);
    // Entitlement-restricted ⇒ neither verbs nor cell SPECs registered.
    try testing.expectEqual(
        @as(?substrate_entity.EntityTypeSpec, null),
        substrate_entity.specByTag(tessera_cell_specs.TESSERA_CELL_TAG_BASE),
    );
}

test "chess: full chess BootDeps wires the wallet via the optional seam" {
    const fixture =
        \\{
        \\  "version": 1,
        \\  "anchors": [
        \\    {
        \\      "game_id": "boot-test",
        \\      "color": "white",
        \\      "type_hash_hex": "1100000000000000000000000000000000000000000000000000000000000022",
        \\      "anchor_index": 1,
        \\      "outpoint": { "txid_be": "abababababababababababababababababababababababababababababababab", "vout": 1 },
        \\      "satoshis": 500,
        \\      "owner_pk_hex": "02ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        \\      "derived_pk_hex": "031111111111111111111111111111111111111111111111111111111111111111"
        \\    }
        \\  ]
        \\}
    ;
    const StubConsume = struct {
        fn call(_: []const u8, _: []const u8) chess_wallet_port.ConsumeError!void {
            return {};
        }
    };
    var rt = try CartridgeRuntime.constructAll(.{
        .allocator = testing.allocator,
        .clock_fn = testClock,
        .chess_manifest_json = fixture,
        .chess_queue_dir = ".",
        .chess_consumer_cert = "cert",
        .chess_consume_fn = StubConsume.call,
    });
    defer rt.deinit();
    var found = false;
    for (rt.live.items) |lc| {
        if (std.mem.eql(u8, lc.id, "chess")) {
            const b: *ChessSpec.Bundle = @ptrCast(@alignCast(lc.handle));
            try testing.expect(b.wallet_active);
            try testing.expectEqual(@as(usize, 1), b.manifest.len);
            found = true;
        }
    }
    try testing.expect(found);
}

test "chess: no chess BootDeps ⇒ wallet stays unattached (Phase-1 preserved)" {
    var rt = try CartridgeRuntime.constructAll(.{
        .allocator = testing.allocator,
        .clock_fn = testClock,
    });
    defer rt.deinit();
    for (rt.live.items) |lc| {
        if (std.mem.eql(u8, lc.id, "chess")) {
            const b: *ChessSpec.Bundle = @ptrCast(@alignCast(lc.handle));
            try testing.expect(!b.wallet_active);
        }
    }
}

```
