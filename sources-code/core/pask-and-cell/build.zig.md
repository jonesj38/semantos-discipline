---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask-and-cell/build.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.810173+00:00
---

# core/pask-and-cell/build.zig

```zig
// Combined-build target: cell-engine + pask in a single WASM.
//
// Damian's ask: "ideally there's a build option that allows applied lib +
// kernel into 1 wasm with some zero copy interface". That's this target.
//
// We replicate cell-engine's createModules() and pask's createModules()
// here, then plug both `main.zig` files into a tiny combined entry point
// that just keeps the exports alive. The linker emits one wasm with
// every kernel_* and pask_* export, sharing one linear memory.
//
// Defaults to the embedded profile (no BSVZ) — full profile + bsvz can
// be enabled with -Dembedded=false.

const std = @import("std");

const CELL_ENGINE_PATH = "../cell-engine";
const PASK_PATH = "../pask";

fn cellPath(b: *std.Build, sub: []const u8) std.Build.LazyPath {
    return b.path(b.pathJoin(&.{ CELL_ENGINE_PATH, sub }));
}

fn paskPath(b: *std.Build, sub: []const u8) std.Build.LazyPath {
    return b.path(b.pathJoin(&.{ PASK_PATH, sub }));
}

const CellModules = struct {
    main: *std.Build.Module,
    // Sub-modules exposed for native test linking
    constants: *std.Build.Module,
    errors: *std.Build.Module,
    pda: *std.Build.Module,
    executor: *std.Build.Module,
    allocator: *std.Build.Module,
};

fn buildCellEngineMain(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    embedded: bool,
) CellModules {
    const constants = b.createModule(.{ .root_source_file = cellPath(b, "src/constants.zig"), .target = target, .optimize = optimize });
    const errors = b.createModule(.{ .root_source_file = cellPath(b, "src/errors.zig"), .target = target, .optimize = optimize });

    const options = b.addOptions();
    options.addOption(bool, "embedded", embedded);
    const options_mod = options.createModule();

    const ripemd160 = b.createModule(.{ .root_source_file = cellPath(b, "src/ripemd160.zig"), .target = target, .optimize = optimize });
    const derivation_state = b.createModule(.{ .root_source_file = cellPath(b, "src/derivation_state.zig"), .target = target, .optimize = optimize });
    const slot_store = b.createModule(.{ .root_source_file = cellPath(b, "src/slot_store.zig"), .target = target, .optimize = optimize });
    const headers = b.createModule(.{ .root_source_file = cellPath(b, "src/headers.zig"), .target = target, .optimize = optimize });

    const host = b.createModule(.{ .root_source_file = cellPath(b, "src/host.zig"), .target = target, .optimize = optimize });
    host.addImport("build_options", options_mod);
    host.addImport("ripemd160", ripemd160);
    host.addImport("derivation_state", derivation_state);
    host.addImport("slot_store", slot_store);

    const commerce = b.createModule(.{
        .root_source_file = cellPath(b, "src/commerce.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "constants", .module = constants }},
    });
    const cell = b.createModule(.{
        .root_source_file = cellPath(b, "src/cell.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants },
            .{ .name = "errors", .module = errors },
            .{ .name = "commerce", .module = commerce },
        },
    });
    const multicell = b.createModule(.{
        .root_source_file = cellPath(b, "src/multicell.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants },
            .{ .name = "cell", .module = cell },
        },
    });
    const bca = b.createModule(.{
        .root_source_file = cellPath(b, "src/bca.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants },
            .{ .name = "host", .module = host },
        },
    });
    const linearity = b.createModule(.{
        .root_source_file = cellPath(b, "src/linearity.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "constants", .module = constants }},
    });
    const octave = b.createModule(.{
        .root_source_file = cellPath(b, "src/octave.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "constants", .module = constants }},
    });
    const pointer = b.createModule(.{
        .root_source_file = cellPath(b, "src/pointer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants },
            .{ .name = "multicell", .module = multicell },
            .{ .name = "octave", .module = octave },
        },
    });
    const allocator = b.createModule(.{ .root_source_file = cellPath(b, "src/allocator.zig"), .target = target, .optimize = optimize });
    const pda = b.createModule(.{
        .root_source_file = cellPath(b, "src/pda.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants },
            .{ .name = "errors", .module = errors },
            .{ .name = "linearity", .module = linearity },
        },
    });
    const sighash = b.createModule(.{
        .root_source_file = cellPath(b, "src/sighash.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants },
            .{ .name = "errors", .module = errors },
            .{ .name = "host", .module = host },
            .{ .name = "allocator", .module = allocator },
        },
    });
    const standard = b.createModule(.{
        .root_source_file = cellPath(b, "src/opcodes/standard.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants },
            .{ .name = "pda", .module = pda },
            .{ .name = "host", .module = host },
            .{ .name = "sighash", .module = sighash },
            .{ .name = "allocator", .module = allocator },
        },
    });
    const macro = b.createModule(.{
        .root_source_file = cellPath(b, "src/opcodes/macro.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pda", .module = pda },
            .{ .name = "host", .module = host },
        },
    });
    const plexus = b.createModule(.{
        .root_source_file = cellPath(b, "src/opcodes/plexus.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants },
            .{ .name = "pda", .module = pda },
            .{ .name = "linearity", .module = linearity },
            .{ .name = "pointer", .module = pointer },
            .{ .name = "host", .module = host },
        },
    });
    const hostcall = b.createModule(.{
        .root_source_file = cellPath(b, "src/opcodes/hostcall.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pda", .module = pda },
            .{ .name = "host", .module = host },
        },
    });
    const executor = b.createModule(.{
        .root_source_file = cellPath(b, "src/executor.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants },
            .{ .name = "errors", .module = errors },
            .{ .name = "pda", .module = pda },
            .{ .name = "standard", .module = standard },
            .{ .name = "macro", .module = macro },
            .{ .name = "plexus", .module = plexus },
            .{ .name = "hostcall", .module = hostcall },
            .{ .name = "allocator", .module = allocator },
            .{ .name = "sighash", .module = sighash },
        },
    });

    const main_mod = b.createModule(.{
        .root_source_file = cellPath(b, "src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_mod.addImport("constants", constants);
    main_mod.addImport("errors", errors);
    main_mod.addImport("commerce", commerce);
    main_mod.addImport("cell", cell);
    main_mod.addImport("multicell", multicell);
    main_mod.addImport("bca", bca);
    main_mod.addImport("host", host);
    main_mod.addImport("allocator", allocator);
    main_mod.addImport("pda", pda);
    main_mod.addImport("sighash", sighash);
    main_mod.addImport("standard", standard);
    main_mod.addImport("macro", macro);
    main_mod.addImport("executor", executor);
    main_mod.addImport("linearity", linearity);
    main_mod.addImport("plexus", plexus);
    main_mod.addImport("octave", octave);
    main_mod.addImport("pointer", pointer);
    main_mod.addImport("build_options", options_mod);
    main_mod.addImport("headers", headers);

    return .{
        .main = main_mod,
        .constants = constants,
        .errors = errors,
        .pda = pda,
        .executor = executor,
        .allocator = allocator,
    };
}

const PaskModules = struct {
    main: *std.Build.Module,
    // Sub-modules exposed for native test linking
    config: *std.Build.Module,
    types: *std.Build.Module,
    store: *std.Build.Module,
    propagation: *std.Build.Module,
    stability: *std.Build.Module,
    pruner: *std.Build.Module,
};

fn buildPaskMain(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) PaskModules {
    const cfg = b.createModule(.{ .root_source_file = paskPath(b, "src/config.zig"), .target = target, .optimize = optimize });
    const types = b.createModule(.{
        .root_source_file = paskPath(b, "src/types.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "config", .module = cfg }},
    });
    const store = b.createModule(.{
        .root_source_file = paskPath(b, "src/store.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = cfg },
            .{ .name = "types", .module = types },
        },
    });
    const propagation = b.createModule(.{
        .root_source_file = paskPath(b, "src/propagation.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = cfg },
            .{ .name = "types", .module = types },
            .{ .name = "store", .module = store },
        },
    });
    const stability = b.createModule(.{
        .root_source_file = paskPath(b, "src/stability.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = cfg },
            .{ .name = "types", .module = types },
            .{ .name = "store", .module = store },
        },
    });
    const pruner = b.createModule(.{
        .root_source_file = paskPath(b, "src/pruner.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = cfg },
            .{ .name = "types", .module = types },
            .{ .name = "store", .module = store },
        },
    });

    const main_mod = b.createModule(.{
        .root_source_file = paskPath(b, "src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_mod.addImport("config", cfg);
    main_mod.addImport("types", types);
    main_mod.addImport("store", store);
    main_mod.addImport("propagation", propagation);
    main_mod.addImport("stability", stability);
    main_mod.addImport("pruner", pruner);

    return .{
        .main = main_mod,
        .config = cfg,
        .types = types,
        .store = store,
        .propagation = propagation,
        .stability = stability,
        .pruner = pruner,
    };
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const wasm_optimize: std.builtin.OptimizeMode = if (optimize == .Debug) .ReleaseSmall else optimize;
    // Combined build defaults to embedded for portability — full profile
    // requires bsvz which makes the wasm bigger and pulls more imports.
    const embedded = b.option(bool, "embedded", "Build with embedded cell-engine profile") orelse true;

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const cell_mods = buildCellEngineMain(b, wasm_target, wasm_optimize, embedded);
    const pask_mods = buildPaskMain(b, wasm_target, wasm_optimize);

    const combined = b.createModule(.{
        .root_source_file = b.path("src/combined.zig"),
        .target = wasm_target,
        .optimize = wasm_optimize,
    });
    combined.addImport("cell_main", cell_mods.main);
    combined.addImport("pask_main", pask_mods.main);

    const wasm = b.addExecutable(.{
        .name = "pask-and-cell",
        .root_module = combined,
    });
    wasm.entry = .disabled;
    wasm.rdynamic = true;
    wasm.stack_size = 256 * 1024;
    wasm.initial_memory = 512 * 65536; // 32 MB — pask static state + cell state
    wasm.max_memory = 1024 * 65536; // 64 MB ceiling
    b.installArtifact(wasm);

    // ── M1.12 conformance tests (native target) ──────────────────────────
    //
    // The conformance tests run against the combined module graph natively
    // so we can exercise both kernel stacks without a WASM runtime. The
    // same code paths are compiled into the WASM binary above.

    const native_target = b.standardTargetOptions(.{});
    const native_cell_mods = buildCellEngineMain(b, native_target, optimize, true);
    const native_pask_mods = buildPaskMain(b, native_target, optimize);

    const conformance_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/combined_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                // Cell engine modules
                .{ .name = "pda", .module = native_cell_mods.pda },
                .{ .name = "executor", .module = native_cell_mods.executor },
                .{ .name = "allocator", .module = native_cell_mods.allocator },
                .{ .name = "constants", .module = native_cell_mods.constants },
                .{ .name = "errors", .module = native_cell_mods.errors },
                // Pask modules
                .{ .name = "config", .module = native_pask_mods.config },
                .{ .name = "types", .module = native_pask_mods.types },
                .{ .name = "store", .module = native_pask_mods.store },
                .{ .name = "stability", .module = native_pask_mods.stability },
            },
        }),
    });

    const test_combined_step = b.step("test-combined", "Run M1.12 combined kernel conformance tests");
    test_combined_step.dependOn(&b.addRunArtifact(conformance_test).step);

    // ── WI-C1 two-kernel harness ──────────────────────────────────────────
    const two_kernel_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/two_kernel_harness.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "config",      .module = native_pask_mods.config },
                .{ .name = "types",       .module = native_pask_mods.types },
                .{ .name = "store",       .module = native_pask_mods.store },
                .{ .name = "propagation", .module = native_pask_mods.propagation },
                .{ .name = "stability",   .module = native_pask_mods.stability },
                .{ .name = "pruner",      .module = native_pask_mods.pruner },
            },
        }),
    });

    const test_two_kernel_step = b.step("test-two-kernel", "Run WI-C1 two-kernel convergence harness");
    test_two_kernel_step.dependOn(&b.addRunArtifact(two_kernel_test).step);
}

```
