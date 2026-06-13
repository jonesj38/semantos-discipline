---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/node/build.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.029793+00:00
---

# runtime/node/build.zig

```zig
// Phase W6 — `semantos-node` daemon build script.
//
// Produces:
//   zig-out/bin/semantos-node            — native daemon binary (default)
//   zig build test                       — runs all tests under runtime/node/tests/
//
// Module sourcing strategy:
//   The cell-engine modules we depend on (`host`, `slot_store`,
//   `derivation_state`) live at `../../core/cell-engine/src/*.zig`. The
//   cell-engine's own build.zig does not currently expose them via
//   `b.addModule` (it builds a wasm artifact + a native test runner
//   internally). Rather than mutate that build script — which is
//   load-bearing for the proof-artifact pipeline (W1–W4) — we replicate
//   the relevant subset here using `b.createModule(.{ .root_source_file
//   = b.path("../../core/cell-engine/src/foo.zig") })`. Cell-engine
//   stays the single source of truth; we just wire the modules into
//   our own dependency graph.
//
//   `bsvz` we pull in via the same package manifest mechanism as
//   cell-engine (build.zig.zon — see this directory's manifest).
//
// Profile:
//   The daemon target is always FULL profile (`embedded=false`), per
//   design §10.2: BSVZ provides crypto natively, no host externs.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── Cell-engine module sourcing ──────────────────────────────────
    // Relative paths into the cell-engine source tree. We import the
    // minimum subset needed by the daemon (the BRC-100 endpoint hands
    // requests to host-level helpers, not to the full executor).

    const cell_engine_src = "../../core/cell-engine/src";

    // build_options shim — host.zig reads `build_options.embedded`. The
    // daemon is full-profile only, so we pin embedded=false at compile
    // time via an Options module.
    const options = b.addOptions();
    options.addOption(bool, "embedded", false);
    const options_mod = options.createModule();

    // bsvz dependency — same source the cell-engine pins.
    const bsvz_dep = b.dependency("bsvz", .{ .target = target, .optimize = optimize });
    const bsvz_mod = bsvz_dep.module("bsvz");

    // ripemd160 module. host.zig's `embedded=true` branches reference
    // it; `embedded=false` does not. But Zig's build graph still walks
    // every `@import` declaration regardless of branch reachability, so
    // we register it. (Trivially small; pulls no transitive deps.)
    const ripemd160_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_src ++ "/ripemd160.zig"),
        .target = target,
        .optimize = optimize,
    });

    const derivation_state_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_src ++ "/derivation_state.zig"),
        .target = target,
        .optimize = optimize,
    });

    const slot_store_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_src ++ "/slot_store.zig"),
        .target = target,
        .optimize = optimize,
    });

    const host_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_src ++ "/host.zig"),
        .target = target,
        .optimize = optimize,
    });
    host_mod.addImport("build_options", options_mod);
    host_mod.addImport("ripemd160", ripemd160_mod);
    host_mod.addImport("derivation_state", derivation_state_mod);
    host_mod.addImport("slot_store", slot_store_mod);
    host_mod.addImport("bsvz", bsvz_mod);

    // ── Daemon-local modules ─────────────────────────────────────────
    // Promoted to first-class modules so the test files (which live
    // outside `src/`) can import them by name. Zig 0.15 forbids
    // cross-module relative `@import("../src/x.zig")` paths.

    const wss_mod = b.createModule(.{
        .root_source_file = b.path("src/wss.zig"),
        .target = target,
        .optimize = optimize,
    });

    const brc100_mod = b.createModule(.{
        .root_source_file = b.path("src/brc100.zig"),
        .target = target,
        .optimize = optimize,
    });
    brc100_mod.addImport("host", host_mod);

    const lmdb_slot_mod = b.createModule(.{
        .root_source_file = b.path("src/lmdb_slot_store.zig"),
        .target = target,
        .optimize = optimize,
    });
    lmdb_slot_mod.addImport("slot_store", slot_store_mod);

    const lmdb_state_mod = b.createModule(.{
        .root_source_file = b.path("src/lmdb_state_store.zig"),
        .target = target,
        .optimize = optimize,
    });
    lmdb_state_mod.addImport("derivation_state", derivation_state_mod);

    // ── Daemon executable ────────────────────────────────────────────

    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_mod.addImport("host", host_mod);
    main_mod.addImport("slot_store", slot_store_mod);
    main_mod.addImport("derivation_state", derivation_state_mod);
    main_mod.addImport("bsvz", bsvz_mod);
    main_mod.addImport("wss", wss_mod);
    main_mod.addImport("brc100", brc100_mod);
    main_mod.addImport("lmdb_slot_store", lmdb_slot_mod);
    main_mod.addImport("lmdb_state_store", lmdb_state_mod);

    const exe = b.addExecutable(.{
        .name = "semantos-node",
        .root_module = main_mod,
    });
    b.installArtifact(exe);

    // Convenience: `zig build run -- --listen 127.0.0.1:8421` etc.
    const run_step = b.step("run", "Run the daemon");
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    run_step.dependOn(&run_cmd.step);

    // ── Tests ────────────────────────────────────────────────────────

    const test_step = b.step("test", "Run all daemon tests");

    // Helper: build one test artifact pulling in the standard module
    // graph. Each test file lives under `tests/`.
    const TestSpec = struct { name: []const u8, src: []const u8 };
    const test_specs = [_]TestSpec{
        .{ .name = "lmdb-round-trip", .src = "tests/lmdb_round_trip.zig" },
        .{ .name = "wss-conformance", .src = "tests/wss_conformance.zig" },
        .{ .name = "wss-unit", .src = "src/wss.zig" },
        .{ .name = "brc100-unit", .src = "src/brc100.zig" },
        .{ .name = "brc100-vectors", .src = "tests/brc100_vectors.zig" },
        // Phase W11: Tier-3 vault cell at-rest round-trip (multisig +
        // nSequence layout). No new slot-store contract — just verifies the
        // extended payload survives encrypt/decrypt at the storage boundary.
        .{ .name = "vault-round-trip", .src = "tests/vault_round_trip.zig" },
    };

    for (test_specs) |spec| {
        const t_mod = b.createModule(.{
            .root_source_file = b.path(spec.src),
            .target = target,
            .optimize = optimize,
        });
        t_mod.addImport("host", host_mod);
        t_mod.addImport("slot_store", slot_store_mod);
        t_mod.addImport("derivation_state", derivation_state_mod);
        t_mod.addImport("bsvz", bsvz_mod);
        t_mod.addImport("wss", wss_mod);
        t_mod.addImport("brc100", brc100_mod);
        t_mod.addImport("lmdb_slot_store", lmdb_slot_mod);
        t_mod.addImport("lmdb_state_store", lmdb_state_mod);

        const t = b.addTest(.{ .root_module = t_mod });
        const run_t = b.addRunArtifact(t);
        const named = b.step(spec.name, b.fmt("Run {s}", .{spec.name}));
        named.dependOn(&run_t.step);
        test_step.dependOn(&run_t.step);
    }
}

```
