---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/ffi/build.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.401445+00:00
---

# src/ffi/build.zig

```zig
const std = @import("std");

// ── D-O5m.followup-1: cell-engine module graph wired in by hand ─────────
//
// We replicate the embedded-profile slice of `core/cell-engine/build.zig:
// createModules` for native targets so `semantos_execute_script` can call
// the real 2-PDA executor (`core/cell-engine/src/executor.zig`) instead of
// the previous syntactic-only `validateOpcodeStream` walker.
//
// Why inline rather than `@import("../../core/cell-engine/build.zig")`?
// In Zig 0.15.2 a build.zig cannot directly import another build.zig
// without a `build.zig.zon` dependency entry. Adding such a dep would force
// the bsvz toolchain pin onto every FFI consumer even though we only need
// the embedded-profile slice (no BSVZ — host externs cover crypto). The
// inline copy mirrors the relevant parts of `createModules` verbatim;
// `core/cell-engine/build.zig:createModules` is now `pub` so a follow-up
// can switch to a proper dependency without touching cell-engine again.
//
// Embedded profile only: BSVZ is not linked (the FFI library has its own
// host-side crypto callbacks), and `host.zig` falls back to std.crypto for
// hashes / returns sane no-op values for `host_log` and friends on native.
// The wasm32-wasi target keeps the syntactic validator for now — wiring
// the cell-engine "host" extern namespace into the wallet-browser host
// loader is a separate piece of work tracked under D-O5m.followup-1
// "Phase 2 (browser)".
//
// Reference: ../../core/cell-engine/build.zig (the canonical module graph
// — keep this slice in sync if the canonical graph adds new dependencies
// the executor pulls in).

const cell_engine_root = "../../core/cell-engine/src";

/// The cell-engine modules the FFI executor surface depends on.
const CellEngineModules = struct {
    constants: *std.Build.Module,
    errors: *std.Build.Module,
    linearity: *std.Build.Module,
    pda: *std.Build.Module,
    allocator: *std.Build.Module,
    host: *std.Build.Module,
    sighash: *std.Build.Module,
    standard: *std.Build.Module,
    macro: *std.Build.Module,
    plexus: *std.Build.Module,
    hostcall: *std.Build.Module,
    executor: *std.Build.Module,
};

fn buildCellEngineEmbedded(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) CellEngineModules {
    // Build options: embedded=true so host.zig falls back to std.crypto on
    // native and to host externs on WASM. We also need a build_options
    // module that host.zig imports.
    const options = b.addOptions();
    options.addOption(bool, "embedded", true);
    const build_options_mod = options.createModule();

    const constants_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/constants.zig"),
        .target = target,
        .optimize = optimize,
    });

    const errors_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/errors.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ripemd160_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/ripemd160.zig"),
        .target = target,
        .optimize = optimize,
    });

    // The host module needs a derivation_state and slot_store import even
    // though the FFI doesn't use them directly — their pointer types are
    // referenced inside host.zig's vtable storage.
    const derivation_state_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/derivation_state.zig"),
        .target = target,
        .optimize = optimize,
    });
    const slot_store_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/slot_store.zig"),
        .target = target,
        .optimize = optimize,
    });

    const host_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/host.zig"),
        .target = target,
        .optimize = optimize,
    });
    host_mod.addImport("build_options", build_options_mod);
    host_mod.addImport("ripemd160", ripemd160_mod);
    host_mod.addImport("derivation_state", derivation_state_mod);
    host_mod.addImport("slot_store", slot_store_mod);
    // No bsvz import — embedded profile.

    const linearity_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/linearity.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
        },
    });

    const pda_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/pda.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
            .{ .name = "errors", .module = errors_mod },
            .{ .name = "linearity", .module = linearity_mod },
            // pda.zig uses build_options.embedded for stack-depth carving;
            // same options module wired to host_mod above.
            .{ .name = "build_options", .module = build_options_mod },
        },
    });

    const allocator_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/allocator.zig"),
        .target = target,
        .optimize = optimize,
    });

    const sighash_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/sighash.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
            .{ .name = "errors", .module = errors_mod },
            .{ .name = "host", .module = host_mod },
            .{ .name = "allocator", .module = allocator_mod },
            // sighash.zig uses build_options.embedded for sizing MAX_INPUTS etc.
            .{ .name = "build_options", .module = build_options_mod },
        },
    });

    const standard_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/opcodes/standard.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
            .{ .name = "pda", .module = pda_mod },
            .{ .name = "host", .module = host_mod },
            .{ .name = "sighash", .module = sighash_mod },
            .{ .name = "allocator", .module = allocator_mod },
        },
    });

    const macro_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/opcodes/macro.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pda", .module = pda_mod },
            .{ .name = "host", .module = host_mod },
        },
    });

    // Plexus + pointer + multicell + commerce + cell + octave for plexus's
    // opCellCreate / opDerefPointer transitive imports.
    const commerce_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/commerce.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
        },
    });

    const cell_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/cell.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
            .{ .name = "errors", .module = errors_mod },
            .{ .name = "commerce", .module = commerce_mod },
        },
    });

    const multicell_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/multicell.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
            .{ .name = "cell", .module = cell_mod },
        },
    });

    const octave_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/octave.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
        },
    });

    const pointer_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/pointer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
            .{ .name = "multicell", .module = multicell_mod },
            .{ .name = "octave", .module = octave_mod },
        },
    });

    const plexus_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/opcodes/plexus.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
            .{ .name = "pda", .module = pda_mod },
            .{ .name = "linearity", .module = linearity_mod },
            .{ .name = "pointer", .module = pointer_mod },
            .{ .name = "host", .module = host_mod },
        },
    });

    const hostcall_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/opcodes/hostcall.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pda", .module = pda_mod },
            .{ .name = "host", .module = host_mod },
        },
    });

    // executor.zig imports `routing` (opcodes/routing.zig) — mirror the brain
    // build's `ce_routing_mod` (constants/pda/sighash deps). Without this the
    // FFI cross-compile fails: "no module named 'routing' available within
    // module 'executor'". Leaf-ish; reuses modules already defined above.
    const routing_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/opcodes/routing.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
            .{ .name = "pda", .module = pda_mod },
            .{ .name = "sighash", .module = sighash_mod },
        },
    });

    const executor_mod = b.createModule(.{
        .root_source_file = b.path(cell_engine_root ++ "/executor.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
            .{ .name = "errors", .module = errors_mod },
            .{ .name = "pda", .module = pda_mod },
            .{ .name = "standard", .module = standard_mod },
            .{ .name = "macro", .module = macro_mod },
            .{ .name = "plexus", .module = plexus_mod },
            .{ .name = "hostcall", .module = hostcall_mod },
            .{ .name = "routing", .module = routing_mod },
            .{ .name = "allocator", .module = allocator_mod },
            .{ .name = "sighash", .module = sighash_mod },
        },
    });

    return .{
        .constants = constants_mod,
        .errors = errors_mod,
        .linearity = linearity_mod,
        .pda = pda_mod,
        .allocator = allocator_mod,
        .host = host_mod,
        .sighash = sighash_mod,
        .standard = standard_mod,
        .macro = macro_mod,
        .plexus = plexus_mod,
        .hostcall = hostcall_mod,
        .executor = executor_mod,
    };
}

/// Wire the cell-engine `executor`, `pda`, `allocator`, and `linearity`
/// modules into the given exports module. These are the four modules
/// `exports.zig` references at the call site.
fn wireCellEngine(exports_mod: *std.Build.Module, ce: CellEngineModules) void {
    exports_mod.addImport("executor", ce.executor);
    exports_mod.addImport("pda", ce.pda);
    exports_mod.addImport("allocator", ce.allocator);
    exports_mod.addImport("linearity", ce.linearity);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── Callbacks module (Phase 30B) ──
    const callbacks_mod = b.createModule(.{
        .root_source_file = b.path("callbacks.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ── Cell-engine modules for native build (D-O5m.followup-1) ──
    const native_ce = buildCellEngineEmbedded(b, target, optimize);

    // ── Exports module (imports callbacks for storage routing) ──
    const exports_mod = b.createModule(.{
        .root_source_file = b.path("exports.zig"),
        .target = target,
        .optimize = optimize,
    });
    exports_mod.addImport("callbacks", callbacks_mod);
    wireCellEngine(exports_mod, native_ce);

    // ── Platform wallet architecture §P2 — wallet_exports module ─────────
    // Desktop-native only: bsvz for P2PKH tx building, BRC-42 key
    // derivation, and ARC broadcast. The static lib gets both exports +
    // wallet_exports linked in via addImport on the root module.
    // RM-122 — OMIT on the Android/iOS "embedded" cross profile (bsvz
    // does not cross-compile there and oddjobz Home/jobs need no wallet
    // tx; matches scripts/build-android-libs.sh's documented "BSVZ
    // omitted" profile). exports.zig's comptime guard mirrors this.
    const is_wasm_target = target.result.cpu.arch == .wasm32;
    // Use isAndroid() to cover both .android (arm64) and .androideabi (arm32).
    const is_mobile_target = target.result.abi.isAndroid() or
        target.result.os.tag == .ios;
    if (!is_wasm_target and !is_mobile_target) {
        const bsvz_dep = b.dependency("bsvz", .{ .target = target, .optimize = optimize });
        const wallet_exports_mod = b.createModule(.{
            .root_source_file = b.path("wallet_exports.zig"),
            .target = target,
            .optimize = optimize,
        });
        wallet_exports_mod.addImport("bsvz", bsvz_dep.module("bsvz"));
        // Pull wallet exports into the root exports module so the linker
        // sees all C ABI symbols in a single artifact.
        exports_mod.addImport("wallet_exports", wallet_exports_mod);
    }

    // ── Static library: libsemantos.a (linkable from C / XCFramework) ──
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "semantos",
        .root_module = exports_mod,
    });
    b.installArtifact(lib);

    // ══════════════════════════════════════════════════════════════════
    // Phase 30E: wasm32-wasi WASM module
    //
    // WASI preview version: wasi_snapshot_preview1
    // Rationale: Most widely supported across Node.js, wasmtime, wasmer,
    // and browser WASI polyfills. Preview2 (component model) not yet stable.
    //
    // Optimization: ReleaseSafe — bounds checking ON, assertions ON.
    // This matches the security posture of the kernel: never trust host input.
    //
    // NOTE (D-O5m.followup-1): the wasm32-wasi build keeps the syntactic
    // validator path inside `validateOpcodeStream` for now. Wiring the
    // real cell-engine 2-PDA into the WASM target needs the wallet-browser
    // host loader to surface the cell-engine "host" namespace imports
    // (host_log / host_get_blocktime / host_call_by_name / host_fetch_cell
    // / host_unlock_tier / host_persist_cell / host_load_cell). That's
    // tracked as a follow-up; the phone (native dylib / static_lib) is the
    // primary surface this PR closes.
    // ══════════════════════════════════════════════════════════════════

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
    });

    // WASM callbacks module
    const wasm_callbacks_mod = b.createModule(.{
        .root_source_file = b.path("callbacks.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSafe,
    });

    // WASM imports module (extern "env" declarations)
    const wasm_imports_mod = b.createModule(.{
        .root_source_file = b.path("wasm_imports.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSafe,
    });

    // WASM exports module (same source as native — zero conditional compilation in source)
    const wasm_exports_mod = b.createModule(.{
        .root_source_file = b.path("exports.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSafe,
    });
    wasm_exports_mod.addImport("callbacks", wasm_callbacks_mod);
    wasm_exports_mod.addImport("wasm_imports", wasm_imports_mod);
    // Wire the cell-engine module graph for the WASM target as well.
    // The cell-engine "host" extern namespace becomes WASM imports
    // resolved at instantiation time by the JS host.
    const wasm_ce = buildCellEngineEmbedded(b, wasm_target, .ReleaseSafe);
    wireCellEngine(wasm_exports_mod, wasm_ce);

    // WASM memory helpers module
    const wasm_memory_mod = b.createModule(.{
        .root_source_file = b.path("wasm_memory.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSafe,
    });

    // WASM executable: semantos.wasm
    const wasm_exe = b.addExecutable(.{
        .name = "semantos",
        .root_module = wasm_exports_mod,
    });
    wasm_exe.entry = .disabled;
    wasm_exe.rdynamic = true;
    // Link wasm_memory exports into the same module
    wasm_exe.root_module.addImport("wasm_memory", wasm_memory_mod);

    const wasm_step = b.step("wasm", "Build wasm32-wasi WASM module (Phase 30E)");
    wasm_step.dependOn(&b.addInstallArtifact(wasm_exe, .{}).step);

    // ── Shared library: libsemantos.dylib/.so (Phase 30G — Dart FFI) ──
    const dylib_mod = b.createModule(.{
        .root_source_file = b.path("exports.zig"),
        .target = target,
        .optimize = optimize,
    });
    dylib_mod.addImport("callbacks", callbacks_mod);
    const dylib_ce = buildCellEngineEmbedded(b, target, optimize);
    wireCellEngine(dylib_mod, dylib_ce);

    const dylib = b.addLibrary(.{
        .name = "semantos",
        .root_module = dylib_mod,
        .linkage = .dynamic,
    });
    const install_dylib = b.addInstallArtifact(dylib, .{});
    const dylib_step = b.step("dylib", "Build shared library for Dart FFI (Phase 30G)");
    dylib_step.dependOn(&install_dylib.step);

    // ── Static library: libsemantos.a (for iOS/Android linking) ──
    //
    // D-OPS.mobile-smoke-test (2026-05-02): when the target is Android
    // we apply two NDK-compatibility tweaks to the module:
    //
    //   * `single_threaded = true` — Android does not link against
    //     `__tls_get_addr` from a NDK-built shared library wrapper,
    //     so any Zig-emitted threadlocal (e.g. the std.debug panic
    //     state, std.crypto's stack-allocated CSPRNG) breaks at the
    //     wrapping `add_library(semantos SHARED ...)` step in the
    //     Flutter FFI plugin's CMakeLists.  Single-threaded mode
    //     tells Zig to bind threadlocals to ordinary globals (no
    //     TLS at all), and is safe for the FFI surface because
    //     every entrypoint runs on the calling Dart isolate's thread
    //     synchronously.
    //   * `stack_check = false` — Zig's stack-probe path emits a
    //     reference to the `__zig_probe_stack` runtime helper.  That
    //     symbol is normally provided by the host-binary's compiler-rt
    //     linkage, but the NDK linker's `--no-undefined` posture for
    //     SHARED libraries refuses to leave it dangling.  Stack
    //     probing is a defence-in-depth measure for very-large frames
    //     (4 KB+); the FFI surface uses none, so it's safe to skip.
    //
    // iOS, macOS, Linux native: leave the multi-threaded default and
    // keep stack probing on.
    const target_is_android = target.result.abi.isAndroid();
    const static_mod = b.createModule(.{
        .root_source_file = b.path("exports.zig"),
        .target = target,
        .optimize = optimize,
        .single_threaded = if (target_is_android) true else null,
        .stack_check = if (target_is_android) false else null,
    });
    static_mod.addImport("callbacks", callbacks_mod);
    const static_ce = buildCellEngineEmbedded(b, target, optimize);
    wireCellEngine(static_mod, static_ce);

    const static_lib = b.addLibrary(.{
        .name = "semantos",
        .root_module = static_mod,
        .linkage = .static,
    });
    const install_static = b.addInstallArtifact(static_lib, .{});
    const static_step = b.step("static", "Build static library for iOS/Android (Phase 30G)");
    static_step.dependOn(&install_static.step);

    // ── Phase 30A tests ──
    const test_mod = b.createModule(.{
        .root_source_file = b.path("tests/core_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("exports", exports_mod);

    const unit_tests = b.addTest(.{
        .root_module = test_mod,
    });
    const run_tests = b.addRunArtifact(unit_tests);

    // ── Phase 30B callback tests ──
    const cb_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/callback_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    cb_test_mod.addImport("exports", exports_mod);
    cb_test_mod.addImport("callbacks", callbacks_mod);

    const cb_tests = b.addTest(.{
        .root_module = cb_test_mod,
    });
    const run_cb_tests = b.addRunArtifact(cb_tests);

    // ── Phase 30C capability + linearity tests ──
    const cap_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/capability_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    cap_test_mod.addImport("exports", exports_mod);
    cap_test_mod.addImport("callbacks", callbacks_mod);

    const cap_tests = b.addTest(.{
        .root_module = cap_test_mod,
    });
    const run_cap_tests = b.addRunArtifact(cap_tests);

    // ── Phase 30D anchor tests ──
    const anchor_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/anchor_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    anchor_test_mod.addImport("exports", exports_mod);
    anchor_test_mod.addImport("callbacks", callbacks_mod);

    const anchor_tests = b.addTest(.{
        .root_module = anchor_test_mod,
    });
    const run_anchor_tests = b.addRunArtifact(anchor_tests);

    // ── Phase 30G+: execute_script tests
    // (D-O5m.followup-3 Phase 3 + D-O5m.followup-1 K1-K4 enforcement) ──
    const exec_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/execute_script_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    exec_test_mod.addImport("exports", exports_mod);
    // The execute-script tests construct cell-engine cells directly to
    // exercise K1/K2/K3/K4 enforcement, so they need the same module graph
    // exports.zig sees.
    exec_test_mod.addImport("constants", native_ce.constants);
    exec_test_mod.addImport("linearity", native_ce.linearity);

    const exec_tests = b.addTest(.{
        .root_module = exec_test_mod,
    });
    const run_exec_tests = b.addRunArtifact(exec_tests);

    const test_step = b.step("test", "Run FFI gate tests (Phase 30A + 30B + 30C + 30D + 30E + Phase 3 execute_script + D-O5m.followup-1 K1-K4)");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_cb_tests.step);
    test_step.dependOn(&run_cap_tests.step);
    test_step.dependOn(&run_anchor_tests.step);
    test_step.dependOn(&run_exec_tests.step);
}

```
