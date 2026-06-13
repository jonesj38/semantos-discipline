---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/build.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.797649+00:00
---

# core/pask/build.zig

```zig
const std = @import("std");

fn createModules(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) struct {
    config: *std.Build.Module,
    types: *std.Build.Module,
    store: *std.Build.Module,
    propagation: *std.Build.Module,
    stability: *std.Build.Module,
    pruner: *std.Build.Module,
} {
    const config_mod = b.createModule(.{
        .root_source_file = b.path("src/config.zig"),
        .target = target,
        .optimize = optimize,
    });

    const types_mod = b.createModule(.{
        .root_source_file = b.path("src/types.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = config_mod },
        },
    });

    const store_mod = b.createModule(.{
        .root_source_file = b.path("src/store.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = config_mod },
            .{ .name = "types", .module = types_mod },
        },
    });

    const propagation_mod = b.createModule(.{
        .root_source_file = b.path("src/propagation.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = config_mod },
            .{ .name = "types", .module = types_mod },
            .{ .name = "store", .module = store_mod },
        },
    });

    const stability_mod = b.createModule(.{
        .root_source_file = b.path("src/stability.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = config_mod },
            .{ .name = "types", .module = types_mod },
            .{ .name = "store", .module = store_mod },
        },
    });

    const pruner_mod = b.createModule(.{
        .root_source_file = b.path("src/pruner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = config_mod },
            .{ .name = "types", .module = types_mod },
            .{ .name = "store", .module = store_mod },
        },
    });

    return .{
        .config = config_mod,
        .types = types_mod,
        .store = store_mod,
        .propagation = propagation_mod,
        .stability = stability_mod,
        .pruner = pruner_mod,
    };
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const wasm_optimize: std.builtin.OptimizeMode = if (optimize == .Debug) .ReleaseSmall else optimize;

    // ── wasm32-freestanding (browser/embedded) ──
    const wasm_freestanding_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const wasm_free_mods = createModules(b, wasm_freestanding_target, wasm_optimize);

    const wasm_main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = wasm_freestanding_target,
        .optimize = wasm_optimize,
    });
    wasm_main_mod.addImport("config", wasm_free_mods.config);
    wasm_main_mod.addImport("types", wasm_free_mods.types);
    wasm_main_mod.addImport("store", wasm_free_mods.store);
    wasm_main_mod.addImport("propagation", wasm_free_mods.propagation);
    wasm_main_mod.addImport("stability", wasm_free_mods.stability);
    wasm_main_mod.addImport("pruner", wasm_free_mods.pruner);

    const wasm_freestanding = b.addExecutable(.{
        .name = "pask",
        .root_module = wasm_main_mod,
    });
    wasm_freestanding.entry = .disabled;
    wasm_freestanding.rdynamic = true;
    wasm_freestanding.stack_size = 256 * 1024;
    // Static state (nodes 5.2 MB + edges 2 MB + delta-ring 1.5 MB +
    // snapshot buffer ~9 MB) lands around 18 MB. Round up to 24 MB initial
    // and keep a 64 MB ceiling for callers that want to grow.
    wasm_freestanding.initial_memory = 384 * 65536; // 24 MB
    wasm_freestanding.max_memory = 1024 * 65536; // 64 MB ceiling
    b.installArtifact(wasm_freestanding);

    // ── wasm32-wasi (sovereign-node / settlement) ──
    const wasm_wasi_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
    });
    const wasm_wasi_mods = createModules(b, wasm_wasi_target, wasm_optimize);

    const wasi_main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = wasm_wasi_target,
        .optimize = wasm_optimize,
    });
    wasi_main_mod.addImport("config", wasm_wasi_mods.config);
    wasi_main_mod.addImport("types", wasm_wasi_mods.types);
    wasi_main_mod.addImport("store", wasm_wasi_mods.store);
    wasi_main_mod.addImport("propagation", wasm_wasi_mods.propagation);
    wasi_main_mod.addImport("stability", wasm_wasi_mods.stability);
    wasi_main_mod.addImport("pruner", wasm_wasi_mods.pruner);

    const wasm_wasi = b.addExecutable(.{
        .name = "pask-wasi",
        .root_module = wasi_main_mod,
    });
    wasm_wasi.entry = .disabled;
    wasm_wasi.rdynamic = true;
    const wasi_step = b.step("wasm-wasi", "Build wasm32-wasi target");
    wasi_step.dependOn(&b.addInstallArtifact(wasm_wasi, .{}).step);

    // ── native test target ──
    const native_target = b.standardTargetOptions(.{});
    const native_mods = createModules(b, native_target, optimize);

    const store_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/store_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "config", .module = native_mods.config },
                .{ .name = "types", .module = native_mods.types },
                .{ .name = "store", .module = native_mods.store },
            },
        }),
    });

    const propagation_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/propagation_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "config", .module = native_mods.config },
                .{ .name = "types", .module = native_mods.types },
                .{ .name = "store", .module = native_mods.store },
                .{ .name = "propagation", .module = native_mods.propagation },
            },
        }),
    });

    const stability_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/stability_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "config", .module = native_mods.config },
                .{ .name = "types", .module = native_mods.types },
                .{ .name = "store", .module = native_mods.store },
                .{ .name = "stability", .module = native_mods.stability },
            },
        }),
    });

    const pruner_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/pruner_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "config", .module = native_mods.config },
                .{ .name = "types", .module = native_mods.types },
                .{ .name = "store", .module = native_mods.store },
                .{ .name = "pruner", .module = native_mods.pruner },
            },
        }),
    });

    const interact_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/interact_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "config", .module = native_mods.config },
                .{ .name = "types", .module = native_mods.types },
                .{ .name = "store", .module = native_mods.store },
                .{ .name = "propagation", .module = native_mods.propagation },
                .{ .name = "stability", .module = native_mods.stability },
                .{ .name = "pruner", .module = native_mods.pruner },
            },
        }),
    });

    const determinism_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/determinism_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "config", .module = native_mods.config },
                .{ .name = "types", .module = native_mods.types },
                .{ .name = "store", .module = native_mods.store },
                .{ .name = "propagation", .module = native_mods.propagation },
                .{ .name = "stability", .module = native_mods.stability },
                .{ .name = "pruner", .module = native_mods.pruner },
            },
        }),
    });

    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&b.addRunArtifact(store_test).step);
    test_step.dependOn(&b.addRunArtifact(propagation_test).step);
    test_step.dependOn(&b.addRunArtifact(stability_test).step);
    test_step.dependOn(&b.addRunArtifact(pruner_test).step);
    test_step.dependOn(&b.addRunArtifact(interact_test).step);
    test_step.dependOn(&b.addRunArtifact(determinism_test).step);

    // ── Release pipeline ─────────────────────────────────────────────
    //
    // emit_spec is a tiny native exe that reads types/config and writes
    // spec.json to stdout. The release script captures stdout to disk
    // and combines it with the wasm file hashes to produce the final
    // pask-X.Y.Z.json release manifest.

    const emit_spec_mod = b.createModule(.{
        .root_source_file = b.path("tools/emit_spec.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = native_mods.config },
            .{ .name = "types", .module = native_mods.types },
        },
    });
    const emit_spec = b.addExecutable(.{
        .name = "emit_spec",
        .root_module = emit_spec_mod,
    });

    const run_emit = b.addRunArtifact(emit_spec);
    // Pipe stdout to zig-out/release/pask-spec.json.
    const spec_out = run_emit.captureStdOut();

    const install_spec = b.addInstallFile(spec_out, "release/pask-spec.json");

    const release_step = b.step(
        "release-spec",
        "Emit zig-out/release/pask-spec.json (machine-derived API surface)",
    );
    release_step.dependOn(&install_spec.step);

    // Chess conformance — opt-in (requires twic1500.pgn corpus).
    // zig build chess
    const chess_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/chess_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "config", .module = native_mods.config },
                .{ .name = "types", .module = native_mods.types },
                .{ .name = "store", .module = native_mods.store },
                .{ .name = "propagation", .module = native_mods.propagation },
                .{ .name = "stability", .module = native_mods.stability },
                .{ .name = "pruner", .module = native_mods.pruner },
            },
        }),
    });
    const chess_step = b.step("chess", "Run the chess-PGN empirical conformance test (slow).");
    chess_step.dependOn(&b.addRunArtifact(chess_test).step);
}

```
