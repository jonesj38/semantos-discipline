---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/build.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.804497+00:00
---

# core/cell-engine/build.zig

```zig
const std = @import("std");

/// Create the cell-engine module graph for a given target.
/// When `embedded` is true, BSVZ is not linked and crypto uses host externs / std stubs.
/// When `embedded` is false (default), BSVZ provides native crypto and SPV for all targets.
///
/// Made `pub` for the FFI build (`src/ffi/build.zig`, D-O5m.followup-1):
/// the FFI surface needs the full cell-engine module graph (executor, pda,
/// linearity, standard, macro, plexus, hostcall, allocator, sighash, host)
/// so `semantos_execute_script` can call the real 2-PDA in place of its
/// previous syntactic-only validator. Callers should pass `embedded=true`
/// because the FFI library has its own host-side crypto wiring and does
/// not depend on BSVZ.
pub fn createModules(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    embedded: bool,
) struct {
    constants: *std.Build.Module,
    errors: *std.Build.Module,
    commerce: *std.Build.Module,
    cell: *std.Build.Module,
    multicell: *std.Build.Module,
    host: *std.Build.Module,
    bca: *std.Build.Module,
    // Phase 3 modules
    allocator: *std.Build.Module,
    pda: *std.Build.Module,
    sighash: *std.Build.Module,
    /// PR-3b: host_compute_sighash registered hostcall handler
    host_compute_sighash: *std.Build.Module,
    /// PR-4: host_resolve_script_template registered hostcall handler
    host_resolve_script_template: *std.Build.Module,
    /// PR-5: host_verify_partial_sig registered hostcall handler
    host_verify_partial_sig: *std.Build.Module,
    /// PR-5: host_compute_preimage_hashes (3 named hostcalls)
    host_compute_preimage_hashes: *std.Build.Module,
    /// PR-5b: host_assemble_tx registered hostcall handler
    host_assemble_tx: *std.Build.Module,
    /// PR-7a: host_verify_beef_spv registered hostcall handler.
    /// Null in `embedded` profile (no bsvz / no beef parser).
    host_verify_beef_spv: ?*std.Build.Module,
    /// PR-8b-i: host_mnca_verify_transition registered hostcall handler.
    host_mnca_verify_transition: *std.Build.Module,
    standard: *std.Build.Module,
    macro: *std.Build.Module,
    executor: *std.Build.Module,
    // Phase 4 modules
    linearity: *std.Build.Module,
    plexus: *std.Build.Module,
    // Phase 25.5 modules
    hostcall: *std.Build.Module,
    // Routing opcodes (0xE0..0xEF) — OP_BRANCHONOUTPUT
    routing: *std.Build.Module,
    // Phase 5 modules (null when embedded)
    beef: ?*std.Build.Module,
    bsvz: ?*std.Build.Module,
    // Phase 6 modules
    octave: *std.Build.Module,
    pointer: *std.Build.Module,
    // D-OCT-escalation-descriptor (step 1/5) — shared by multicell + tests
    escalation_descriptor: *std.Build.Module,
    // D-OCT-merkle-hierarchy (step 3/5) — rung-2 cell merkle + inclusion-proof verifier
    cell_merkle: *std.Build.Module,
    // D-OCT-path-merkle-unify (step 4/5) — routing path-merkle overload
    path_merkle: *std.Build.Module,
    // Phase W3.5
    derivation_state: *std.Build.Module,
    output_store: *std.Build.Module,
    // Phase W4
    slot_store: *std.Build.Module,
    // Phase WH1 / WH2 / WH5 — Trustless SPV
    headers: *std.Build.Module,
    header_store: *std.Build.Module,
    local_chain_tracker: *std.Build.Module,
    // Shared build options module
    build_options: *std.Build.Module,
} {
    const constants_mod = b.createModule(.{
        .root_source_file = b.path("src/constants.zig"),
        .target = target,
        .optimize = optimize,
    });

    const errors_mod = b.createModule(.{
        .root_source_file = b.path("src/errors.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Build options for host.zig and main.zig compile-time dispatch
    const options = b.addOptions();
    options.addOption(bool, "embedded", embedded);
    const options_mod = options.createModule();

    // Full profile: resolve BSVZ dependency
    const bsvz_mod: ?*std.Build.Module = if (!embedded) blk: {
        const bsvz_dep = b.dependency("bsvz", .{ .target = target, .optimize = optimize });
        break :blk bsvz_dep.module("bsvz");
    } else null;

    // RIPEMD160 module (pure Zig, no BSVZ — used by embedded profile for real HASH160)
    const ripemd160_mod = b.createModule(.{
        .root_source_file = b.path("src/ripemd160.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Phase W3.5: DerivationStateStore module (used by host.zig).
    const derivation_state_mod = b.createModule(.{
        .root_source_file = b.path("src/derivation_state.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Phase WA2: OutputStore module — pluggable UTXO store mirroring
    // DerivationStateStore. v0.1 ships LocalOutputStore (in-memory native /
    // IndexedDB browser). The browser binds to this vtable indirectly via
    // cartridges/wallet-headers/brain/src/output-store.ts; this module exists for
    // sovereign-node + native conformance tests.
    const output_store_mod = b.createModule(.{
        .root_source_file = b.path("src/output_store.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Phase W4: SlotStore module (used by host.zig for at-rest cell persistence).
    const slot_store_mod = b.createModule(.{
        .root_source_file = b.path("src/slot_store.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Phase WH1: pure-Zig BSV PoW verifier (parser + DAA + chain validation).
    // No deps — used by both browser and native builds.
    const headers_mod = b.createModule(.{
        .root_source_file = b.path("src/headers.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Phase WH2: HeaderStore vtable + LocalHeaderStore — depends on `headers`.
    const header_store_mod = b.createModule(.{
        .root_source_file = b.path("src/header_store.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "headers", .module = headers_mod },
        },
    });

    // Phase WH5: LocalHeaderChainTracker — wraps HeaderStore for bsvz BEEF
    // verification. No bsvz dep here (we use anytype for the Hash256 type).
    const local_chain_tracker_mod = b.createModule(.{
        .root_source_file = b.path("src/local_chain_tracker.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "headers", .module = headers_mod },
            .{ .name = "header_store", .module = header_store_mod },
        },
    });

    // Host module: build_options + optional bsvz + ripemd160 + derivation_state + slot_store
    const host_mod = b.createModule(.{
        .root_source_file = b.path("src/host.zig"),
        .target = target,
        .optimize = optimize,
    });
    host_mod.addImport("build_options", options_mod);
    host_mod.addImport("ripemd160", ripemd160_mod);
    host_mod.addImport("derivation_state", derivation_state_mod);
    host_mod.addImport("slot_store", slot_store_mod);
    if (bsvz_mod) |bsvz| {
        host_mod.addImport("bsvz", bsvz);
    }

    const commerce_mod = b.createModule(.{
        .root_source_file = b.path("src/commerce.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
        },
    });

    const cell_mod = b.createModule(.{
        .root_source_file = b.path("src/cell.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
            .{ .name = "errors", .module = errors_mod },
            .{ .name = "commerce", .module = commerce_mod },
        },
    });

    // ── Phase 6 modules (moved up: multicell now depends on octave) ──

    const octave_mod = b.createModule(.{
        .root_source_file = b.path("src/octave.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
        },
    });

    // escalation_descriptor module (self-contained, std-only) — used by multicell.
    // Defined here (before multicell) because multicell now imports it for rung-1 writes.
    const escalation_descriptor_mod = b.createModule(.{
        .root_source_file = b.path("src/escalation_descriptor.zig"),
        .target = target,
        .optimize = optimize,
    });

    const multicell_mod = b.createModule(.{
        .root_source_file = b.path("src/multicell.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
            .{ .name = "cell", .module = cell_mod },
            .{ .name = "octave", .module = octave_mod },
            .{ .name = "escalation_descriptor", .module = escalation_descriptor_mod },
        },
    });

    // D-OCT-merkle-hierarchy (step 3/5) — rung-2 cell merkle.
    // Depends on: constants, escalation_descriptor, multicell (for backward-compat tests).
    const cell_merkle_mod = b.createModule(.{
        .root_source_file = b.path("src/cell_merkle.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
            .{ .name = "escalation_descriptor", .module = escalation_descriptor_mod },
            .{ .name = "multicell", .module = multicell_mod },
        },
    });

    // D-OCT-path-merkle-unify (step 4/5): routing path-merkle overload.
    // Imports cell_merkle for the shared verifyInclusion primitive.
    const path_merkle_mod = b.createModule(.{
        .root_source_file = b.path("src/path_merkle.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "cell_merkle", .module = cell_merkle_mod },
        },
    });

    const bca_mod = b.createModule(.{
        .root_source_file = b.path("src/bca.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
            .{ .name = "host", .module = host_mod },
        },
    });

    // ── Phase 4 modules ──

    const linearity_mod = b.createModule(.{
        .root_source_file = b.path("src/linearity.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
        },
    });

    const pointer_mod = b.createModule(.{
        .root_source_file = b.path("src/pointer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
            .{ .name = "multicell", .module = multicell_mod },
            .{ .name = "octave", .module = octave_mod },
        },
    });

    // ── Phase 3 modules ──

    const allocator_mod = b.createModule(.{
        .root_source_file = b.path("src/allocator.zig"),
        .target = target,
        .optimize = optimize,
    });

    const pda_mod = b.createModule(.{
        .root_source_file = b.path("src/pda.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "build_options", .module = options_mod },
            .{ .name = "constants", .module = constants_mod },
            .{ .name = "errors", .module = errors_mod },
            .{ .name = "linearity", .module = linearity_mod },
        },
    });

    const sighash_mod = b.createModule(.{
        .root_source_file = b.path("src/sighash.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "build_options", .module = options_mod },
            .{ .name = "constants", .module = constants_mod },
            .{ .name = "errors", .module = errors_mod },
            .{ .name = "host", .module = host_mod },
            .{ .name = "allocator", .module = allocator_mod },
        },
    });

    // PR-3b: host_compute_sighash — the cell-engine-facing handler
    // for the dual-algorithm sighash hostcall. Registers itself via
    // host.registerHostCall at brain boot; reads tx + subscript +
    // sighash_type from the brain-set execution context.
    const host_compute_sighash_mod = b.createModule(.{
        .root_source_file = b.path("src/host_compute_sighash.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "host", .module = host_mod },
            .{ .name = "sighash", .module = sighash_mod },
        },
    });

    // PR-4: host_resolve_script_template — template substitution
    // hostcall covering both lockScript and unlockScript regions
    // (one mechanism, gated by cap.tx.build).
    const host_resolve_script_template_mod = b.createModule(.{
        .root_source_file = b.path("src/host_resolve_script_template.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "host", .module = host_mod },
        },
    });

    // PR-5: host_verify_partial_sig — ECDSA verification for partial-tx
    // contribution handlers. Thin wrapper around host.checksig with the
    // hostcall + capability gating (cap.tx.sign).
    const host_verify_partial_sig_mod = b.createModule(.{
        .root_source_file = b.path("src/host_verify_partial_sig.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "host", .module = host_mod },
        },
    });

    // PR-5: host_compute_preimage_hashes — three named SHA256d hostcalls
    // (prevouts/sequence/outputs) used to build BIP-143 sighash
    // arguments. No capability gate (pure helpers).
    const host_compute_preimage_hashes_mod = b.createModule(.{
        .root_source_file = b.path("src/host_compute_preimage_hashes.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "host", .module = host_mod },
        },
    });

    // PR-5b: host_assemble_tx — final tx serialization for the
    // cap.tx.build hostcall surface. Stitches (version, inputs[],
    // outputs[], nLockTime) into wire-format bytes ready for broadcast.
    const host_assemble_tx_mod = b.createModule(.{
        .root_source_file = b.path("src/host_assemble_tx.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "host", .module = host_mod },
        },
    });

    const standard_mod = b.createModule(.{
        .root_source_file = b.path("src/opcodes/standard.zig"),
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
        .root_source_file = b.path("src/opcodes/macro.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pda", .module = pda_mod },
            .{ .name = "host", .module = host_mod },
        },
    });

    const plexus_mod = b.createModule(.{
        .root_source_file = b.path("src/opcodes/plexus.zig"),
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

    // Phase 25.5: Host function dispatch opcode
    const hostcall_mod = b.createModule(.{
        .root_source_file = b.path("src/opcodes/hostcall.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pda", .module = pda_mod },
            .{ .name = "host", .module = host_mod },
        },
    });

    // Routing opcodes (0xE0..0xEF) — OP_BRANCHONOUTPUT et al.
    // Spec: docs/design/OP-BRANCHONOUTPUT-SPEC.md
    const routing_mod = b.createModule(.{
        .root_source_file = b.path("src/opcodes/routing.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "constants", .module = constants_mod },
            .{ .name = "pda", .module = pda_mod },
            .{ .name = "sighash", .module = sighash_mod },
        },
    });

    const executor_mod = b.createModule(.{
        .root_source_file = b.path("src/executor.zig"),
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

    // ── Phase 5: BEEF/BUMP module (full profile only) ──

    const beef_mod: ?*std.Build.Module = if (!embedded and bsvz_mod != null) blk: {
        break :blk b.createModule(.{
            .root_source_file = b.path("src/beef.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "host", .module = host_mod },
                .{ .name = "errors", .module = errors_mod },
                .{ .name = "allocator", .module = allocator_mod },
                .{ .name = "bsvz", .module = bsvz_mod.? },
            },
        });
    } else null;

    // PR-7a: host_verify_beef_spv — cell-engine native hostcall wrapper
    // around beef.verifyBeefSpv. Gated on the beef module being present
    // (embedded profile has no bsvz, hence no BEEF parser, hence no
    // hostcall to register). cap.bsv.beef.verify enforced brain-side.
    const host_verify_beef_spv_mod: ?*std.Build.Module = if (beef_mod) |beef| blk: {
        break :blk b.createModule(.{
            .root_source_file = b.path("src/host_verify_beef_spv.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "host", .module = host_mod },
                .{ .name = "beef", .module = beef },
            },
        });
    } else null;

    // PR-8b-i: shared mnca_tile module — also used by tile_script_equivalence
    // test. Self-contained (std only), compiles for any target.
    const mnca_tile_shared_mod = b.createModule(.{
        .root_source_file = b.path("src/mnca_tile.zig"),
        .target = target,
        .optimize = optimize,
    });

    // PR-8b-i: host_mnca_verify_transition — cell-engine native hostcall
    // wrapper around mnca_tile.stepTilePayload as the MNCA-transition
    // determinism oracle. cap.mnca.verify enforced brain-side.
    const host_mnca_verify_transition_mod = b.createModule(.{
        .root_source_file = b.path("src/host_mnca_verify_transition.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "host", .module = host_mod },
            .{ .name = "mnca_tile", .module = mnca_tile_shared_mod },
        },
    });

    return .{
        .constants = constants_mod,
        .errors = errors_mod,
        .commerce = commerce_mod,
        .cell = cell_mod,
        .multicell = multicell_mod,
        .host = host_mod,
        .bca = bca_mod,
        .allocator = allocator_mod,
        .pda = pda_mod,
        .sighash = sighash_mod,
        .host_compute_sighash = host_compute_sighash_mod,
        .host_resolve_script_template = host_resolve_script_template_mod,
        .host_verify_partial_sig = host_verify_partial_sig_mod,
        .host_compute_preimage_hashes = host_compute_preimage_hashes_mod,
        .host_verify_beef_spv = host_verify_beef_spv_mod,
        .host_mnca_verify_transition = host_mnca_verify_transition_mod,
        .host_assemble_tx = host_assemble_tx_mod,
        .standard = standard_mod,
        .macro = macro_mod,
        .executor = executor_mod,
        .linearity = linearity_mod,
        .plexus = plexus_mod,
        .hostcall = hostcall_mod,
        .routing = routing_mod,
        .beef = beef_mod,
        .bsvz = bsvz_mod,
        .octave = octave_mod,
        .pointer = pointer_mod,
        .escalation_descriptor = escalation_descriptor_mod,
        .cell_merkle = cell_merkle_mod,
        .path_merkle = path_merkle_mod,
        .derivation_state = derivation_state_mod,
        .output_store = output_store_mod,
        .slot_store = slot_store_mod,
        .headers = headers_mod,
        .header_store = header_store_mod,
        .local_chain_tracker = local_chain_tracker_mod,
        .build_options = options_mod,
    };
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const wasm_optimize: std.builtin.OptimizeMode = if (optimize == .Debug) .ReleaseSmall else optimize;
    const embedded = b.option(bool, "embedded", "Build embedded profile (no BSVZ, host-delegated crypto)") orelse false;

    // ── Default: wasm32-freestanding ──
    const wasm_freestanding_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const wasm_free_mods = createModules(b, wasm_freestanding_target, wasm_optimize, embedded);

    const wasm_name = if (embedded) "cell-engine-embedded" else "cell-engine";

    const wasm_main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = wasm_freestanding_target,
        .optimize = wasm_optimize,
    });
    // Add all imports to main module
    wasm_main_mod.addImport("constants", wasm_free_mods.constants);
    wasm_main_mod.addImport("errors", wasm_free_mods.errors);
    wasm_main_mod.addImport("commerce", wasm_free_mods.commerce);
    wasm_main_mod.addImport("cell", wasm_free_mods.cell);
    wasm_main_mod.addImport("multicell", wasm_free_mods.multicell);
    wasm_main_mod.addImport("bca", wasm_free_mods.bca);
    wasm_main_mod.addImport("host", wasm_free_mods.host);
    wasm_main_mod.addImport("allocator", wasm_free_mods.allocator);
    wasm_main_mod.addImport("pda", wasm_free_mods.pda);
    wasm_main_mod.addImport("sighash", wasm_free_mods.sighash);
    wasm_main_mod.addImport("standard", wasm_free_mods.standard);
    wasm_main_mod.addImport("macro", wasm_free_mods.macro);
    wasm_main_mod.addImport("executor", wasm_free_mods.executor);
    wasm_main_mod.addImport("linearity", wasm_free_mods.linearity);
    wasm_main_mod.addImport("plexus", wasm_free_mods.plexus);
    wasm_main_mod.addImport("octave", wasm_free_mods.octave);
    wasm_main_mod.addImport("pointer", wasm_free_mods.pointer);
    wasm_main_mod.addImport("build_options", wasm_free_mods.build_options);
    wasm_main_mod.addImport("headers", wasm_free_mods.headers);
    if (wasm_free_mods.beef) |beef| {
        wasm_main_mod.addImport("beef", beef);
    }

    const wasm_freestanding = b.addExecutable(.{
        .name = wasm_name,
        .root_module = wasm_main_mod,
    });
    wasm_freestanding.entry = .disabled;
    wasm_freestanding.rdynamic = true;
    // Embedded targets shrink both: the call stack (256KB → 32KB is plenty
    // for a 29KB module's recursion depth) and the initial linear memory
    // (8MB → 256KB once PDA stacks are trimmed via build_options.embedded
    // through pda.zig). Desktop/server keep the original generous sizes.
    if (embedded) {
        // Carved 2026-05-21 for ESP32-C6 mesh integration: needed total
        // linear memory ≤ 64 KB (one page) so the engine fits alongside
        // ESP-NOW/WiFi on the C6's 329 KB SRAM. Stack down from 32 KB
        // (Bitcoin-script call depth doesn't go anywhere near that on a
        // sane workload), plus the matching trims in build_options
        // (ARENA_BUF / MAIN_STACK_DEPTH / SNAPSHOT_BUF).
        wasm_freestanding.stack_size     =  16 * 1024;
        wasm_freestanding.initial_memory =   1 * 65536; // 64KB — one page
    } else {
        wasm_freestanding.stack_size     = 256 * 1024;
        wasm_freestanding.initial_memory = 128 * 65536; // 8MB
    }

    b.installArtifact(wasm_freestanding);

    // ── Named step: wasm32-wasi (server) ──
    const wasm_wasi_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
    });

    const wasm_wasi_mods = createModules(b, wasm_wasi_target, wasm_optimize, embedded);

    const wasi_name = if (embedded) "cell-engine-wasi-embedded" else "cell-engine-wasi";
    const wasi_main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = wasm_wasi_target,
        .optimize = wasm_optimize,
    });
    wasi_main_mod.addImport("constants", wasm_wasi_mods.constants);
    wasi_main_mod.addImport("errors", wasm_wasi_mods.errors);
    wasi_main_mod.addImport("commerce", wasm_wasi_mods.commerce);
    wasi_main_mod.addImport("cell", wasm_wasi_mods.cell);
    wasi_main_mod.addImport("multicell", wasm_wasi_mods.multicell);
    wasi_main_mod.addImport("bca", wasm_wasi_mods.bca);
    wasi_main_mod.addImport("host", wasm_wasi_mods.host);
    wasi_main_mod.addImport("allocator", wasm_wasi_mods.allocator);
    wasi_main_mod.addImport("pda", wasm_wasi_mods.pda);
    wasi_main_mod.addImport("sighash", wasm_wasi_mods.sighash);
    wasi_main_mod.addImport("standard", wasm_wasi_mods.standard);
    wasi_main_mod.addImport("macro", wasm_wasi_mods.macro);
    wasi_main_mod.addImport("executor", wasm_wasi_mods.executor);
    wasi_main_mod.addImport("linearity", wasm_wasi_mods.linearity);
    wasi_main_mod.addImport("plexus", wasm_wasi_mods.plexus);
    wasi_main_mod.addImport("octave", wasm_wasi_mods.octave);
    wasi_main_mod.addImport("pointer", wasm_wasi_mods.pointer);
    wasi_main_mod.addImport("build_options", wasm_wasi_mods.build_options);
    wasi_main_mod.addImport("headers", wasm_wasi_mods.headers);
    if (wasm_wasi_mods.beef) |beef| {
        wasi_main_mod.addImport("beef", beef);
    }

    const wasm_wasi = b.addExecutable(.{
        .name = wasi_name,
        .root_module = wasi_main_mod,
    });
    wasm_wasi.entry = .disabled;
    wasm_wasi.rdynamic = true;

    const wasi_step = b.step("wasm-wasi", "Build wasm32-wasi target");
    wasi_step.dependOn(&b.addInstallArtifact(wasm_wasi, .{}).step);

    // ── Test: native ──
    const native_target = b.standardTargetOptions(.{});
    const native_mods = createModules(b, native_target, optimize, embedded);

    // M1.1 — LMDB binding module (links against system liblmdb).
    const lmdb_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/lmdb/lmdb.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    lmdb_mod.linkSystemLibrary("lmdb", .{});

    // M1.1 — LMDB conformance smoke test (registered to test_step below).
    const lmdb_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/lmdb_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lmdb", .module = lmdb_mod },
            },
        }),
    });
    const test_lmdb_step = b.step("test-lmdb", "Run M1.1 LMDB binding smoke tests");
    test_lmdb_step.dependOn(&b.addRunArtifact(lmdb_test).step);

    // M1.2 — LmdbHeaderStore conformance tests.
    const lmdb_header_store_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/lmdb/header_store_lmdb.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "lmdb", .module = lmdb_mod },
            .{ .name = "header_store", .module = native_mods.header_store },
        },
    });
    const lmdb_header_store_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/lmdb_header_store_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lmdb", .module = lmdb_mod },
                .{ .name = "header_store", .module = native_mods.header_store },
                .{ .name = "headers", .module = native_mods.headers },
                .{ .name = "lmdb_header_store", .module = lmdb_header_store_mod },
            },
        }),
    });
    const test_lmdb_header_store_step = b.step(
        "test-lmdb-header-store",
        "Run M1.2 LmdbHeaderStore conformance tests",
    );
    test_lmdb_header_store_step.dependOn(&b.addRunArtifact(lmdb_header_store_test).step);

    // M1.3 — LmdbOutputStore conformance tests.
    const lmdb_output_store_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/lmdb/output_store_lmdb.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "lmdb", .module = lmdb_mod },
            .{ .name = "output_store", .module = native_mods.output_store },
        },
    });
    const lmdb_output_store_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/lmdb_output_store_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lmdb", .module = lmdb_mod },
                .{ .name = "output_store", .module = native_mods.output_store },
                .{ .name = "lmdb_output_store", .module = lmdb_output_store_mod },
            },
        }),
    });
    const test_lmdb_output_store_step = b.step(
        "test-lmdb-output-store",
        "Run M1.3 LmdbOutputStore conformance tests",
    );
    test_lmdb_output_store_step.dependOn(&b.addRunArtifact(lmdb_output_store_test).step);

    // M1.4 — LmdbDerivationStateStore conformance tests.
    const lmdb_derivation_state_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/lmdb/derivation_state_store_lmdb.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "lmdb", .module = lmdb_mod },
            .{ .name = "derivation_state", .module = native_mods.derivation_state },
        },
    });
    const lmdb_derivation_state_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/lmdb_derivation_state_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lmdb", .module = lmdb_mod },
                .{ .name = "derivation_state", .module = native_mods.derivation_state },
                .{ .name = "lmdb_derivation_state", .module = lmdb_derivation_state_mod },
            },
        }),
    });
    const test_lmdb_derivation_state_step = b.step(
        "test-lmdb-derivation-state",
        "Run M1.4 LmdbDerivationStateStore conformance tests",
    );
    test_lmdb_derivation_state_step.dependOn(&b.addRunArtifact(lmdb_derivation_state_test).step);

    // M1.5 — LmdbCellStore conformance tests.
    const cell_store_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/lmdb/cell_store.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    const lmdb_cell_store_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/lmdb/cell_store_lmdb.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "lmdb", .module = lmdb_mod },
            .{ .name = "cell_store", .module = cell_store_mod },
            // 2026-05-20 — cell_store_lmdb.zig added `@import("constants")`
            // for SemantosDomainFlags. Wire it through here so the
            // conformance test compiles.
            .{ .name = "constants", .module = native_mods.constants },
        },
    });
    const lmdb_cell_store_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/lmdb_cell_store_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lmdb", .module = lmdb_mod },
                .{ .name = "cell_store", .module = cell_store_mod },
                .{ .name = "lmdb_cell_store", .module = lmdb_cell_store_mod },
            },
        }),
    });
    const test_lmdb_cell_store_step = b.step(
        "test-lmdb-cell-store",
        "Run M1.5 LmdbCellStore conformance tests",
    );
    test_lmdb_cell_store_step.dependOn(&b.addRunArtifact(lmdb_cell_store_test).step);

    // M1.10 — CursorHost conformance tests (cursor streaming, peak-heap bound).
    const cursor_host_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/cursor_host.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "cell_store", .module = cell_store_mod },
        },
    });
    const cursor_host_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cursor_host_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lmdb", .module = lmdb_mod },
                .{ .name = "cell_store", .module = cell_store_mod },
                .{ .name = "lmdb_cell_store", .module = lmdb_cell_store_mod },
                .{ .name = "cursor_host", .module = cursor_host_mod },
            },
        }),
    });
    const test_cursor_host_step = b.step(
        "test-cursor-host",
        "Run M1.10 CursorHost conformance tests (cursor streaming, peak-heap bound)",
    );
    test_cursor_host_step.dependOn(&b.addRunArtifact(cursor_host_test).step);

    // M1.11 — LmdbPaskSnapshotStore conformance tests.
    const pask_snapshot_store_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/lmdb/pask_snapshot_store.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    const lmdb_pask_snapshot_store_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/lmdb/pask_snapshot_store_lmdb.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "lmdb", .module = lmdb_mod },
            .{ .name = "pask_snapshot_store", .module = pask_snapshot_store_mod },
        },
    });
    const lmdb_pask_snapshot_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/lmdb_pask_snapshot_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lmdb", .module = lmdb_mod },
                .{ .name = "pask_snapshot_store", .module = pask_snapshot_store_mod },
                .{ .name = "lmdb_pask_snapshot_store", .module = lmdb_pask_snapshot_store_mod },
            },
        }),
    });
    const test_lmdb_pask_snapshot_step = b.step(
        "test-lmdb-pask-snapshot",
        "Run M1.11 LmdbPaskSnapshotStore conformance tests",
    );
    test_lmdb_pask_snapshot_step.dependOn(&b.addRunArtifact(lmdb_pask_snapshot_test).step);

    // M6.2 — LmdbRegistryCacheStore conformance tests.
    const registry_cache_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/lmdb/registry_cache.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    const registry_cache_lmdb_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/lmdb/registry_cache_lmdb.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "lmdb", .module = lmdb_mod },
            .{ .name = "registry_cache", .module = registry_cache_mod },
        },
    });
    const registry_cache_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/registry_cache_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lmdb", .module = lmdb_mod },
                .{ .name = "registry_cache", .module = registry_cache_mod },
                .{ .name = "registry_cache_lmdb", .module = registry_cache_lmdb_mod },
            },
        }),
    });
    const test_registry_cache_step = b.step(
        "test-registry-cache",
        "Run M6.2 LmdbRegistryCacheStore conformance tests",
    );
    test_registry_cache_step.dependOn(&b.addRunArtifact(registry_cache_test).step);

    // M6.5 — DriftDetector conformance tests.
    const drift_detector_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/lmdb/drift_detector.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "lmdb", .module = lmdb_mod },
            .{ .name = "registry_cache", .module = registry_cache_mod },
            .{ .name = "registry_cache_lmdb", .module = registry_cache_lmdb_mod },
        },
    });
    const drift_detector_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/drift_detector_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lmdb", .module = lmdb_mod },
                .{ .name = "registry_cache", .module = registry_cache_mod },
                .{ .name = "registry_cache_lmdb", .module = registry_cache_lmdb_mod },
                .{ .name = "drift_detector", .module = drift_detector_mod },
            },
        }),
    });
    const test_drift_detector_step = b.step(
        "test-drift-detector",
        "Run M6.5 DriftDetector conformance tests",
    );
    test_drift_detector_step.dependOn(&b.addRunArtifact(drift_detector_test).step);

    // M4.1 — ContentStoreLocalFs conformance tests.
    const content_store_local_fs_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/content_store_local_fs.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    const content_store_local_fs_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/content_store_local_fs_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "content_store_local_fs", .module = content_store_local_fs_mod },
            },
        }),
    });
    const test_content_store_local_fs_step = b.step(
        "test-content-store-local-fs",
        "Run M4.1 ContentStoreLocalFs conformance tests",
    );
    test_content_store_local_fs_step.dependOn(&b.addRunArtifact(content_store_local_fs_test).step);

    // M4.5 — storeWithEscalation conformance tests.
    const escalation_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/escalation.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "content_store_local_fs", .module = content_store_local_fs_mod },
        },
    });
    const escalation_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/escalation_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "escalation", .module = escalation_mod },
                .{ .name = "content_store_local_fs", .module = content_store_local_fs_mod },
            },
        }),
    });
    const test_escalation_step = b.step(
        "test-escalation",
        "Run M4.5 storeWithEscalation conformance tests",
    );
    test_escalation_step.dependOn(&b.addRunArtifact(escalation_test).step);

    // M4.6 — CellRegistry dual-addressing conformance tests.
    const cell_registry_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/cell_registry.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "octave", .module = native_mods.octave },
        },
    });
    const cell_registry_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cell_registry_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cell_registry", .module = cell_registry_mod },
                .{ .name = "octave", .module = native_mods.octave },
            },
        }),
    });
    const test_cell_registry_step = b.step(
        "test-cell-registry",
        "Run M4.6 CellRegistry dual-addressing conformance tests",
    );
    test_cell_registry_step.dependOn(&b.addRunArtifact(cell_registry_test).step);

    // M4.2 — UhrpHttpStore octave-2 conformance tests.
    const uhrp_http_store_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/content_store_uhrp_http.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    const uhrp_http_store_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/uhrp_http_store_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "uhrp_http_store", .module = uhrp_http_store_mod },
            },
        }),
    });
    const test_uhrp_http_store_step = b.step(
        "test-uhrp-http-store",
        "Run M4.2 UhrpHttpStore octave-2 conformance tests",
    );
    test_uhrp_http_store_step.dependOn(&b.addRunArtifact(uhrp_http_store_test).step);

    // M1.6 — CompositeWrite conformance tests.
    const composite_write_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/lmdb/composite_write.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "lmdb", .module = lmdb_mod },
            .{ .name = "cell_store", .module = cell_store_mod },
            .{ .name = "cell_store_lmdb", .module = lmdb_cell_store_mod },
            .{ .name = "output_store_lmdb", .module = lmdb_output_store_mod },
            .{ .name = "header_store_lmdb", .module = lmdb_header_store_mod },
        },
    });
    const composite_write_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/composite_write_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "lmdb", .module = lmdb_mod },
                .{ .name = "cell_store", .module = cell_store_mod },
                .{ .name = "composite_write", .module = composite_write_mod },
            },
        }),
    });
    const test_composite_write_step = b.step(
        "test-composite-write",
        "Run M1.6 CompositeWrite conformance tests",
    );
    test_composite_write_step.dependOn(&b.addRunArtifact(composite_write_test).step);

    // M3.2 — PravegatClient unit tests (mock HTTP server, no real Pravega).
    const pravega_client_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/pravega_client.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    const pravega_client_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/tests/pravega_client_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pravega_client", .module = pravega_client_mod },
            },
        }),
    });
    const test_pravega_client_step = b.step(
        "test-pravega-client",
        "Run M3.2 PravegatClient unit tests (mock HTTP, no Pravega required)",
    );
    test_pravega_client_step.dependOn(&b.addRunArtifact(pravega_client_test).step);

    // M3.3 — RegionTickProducer unit tests (mock HTTP server, no real Pravega).
    const region_tick_producer_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/region_tick_producer.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pravega_client", .module = pravega_client_mod },
        },
    });
    const region_tick_producer_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/tests/region_tick_producer_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pravega_client", .module = pravega_client_mod },
                .{ .name = "region_tick_producer", .module = region_tick_producer_mod },
            },
        }),
    });
    const test_region_tick_producer_step = b.step(
        "test-region-tick-producer",
        "Run M3.3 RegionTickProducer unit tests (mock HTTP, no Pravega required)",
    );
    test_region_tick_producer_step.dependOn(&b.addRunArtifact(region_tick_producer_test).step);

    // M3.4 — IdentityEventProducer unit tests (mock HTTP server, no real Pravega).
    const identity_event_producer_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/identity_event_producer.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pravega_client", .module = pravega_client_mod },
        },
    });
    const identity_event_producer_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/tests/identity_event_producer_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pravega_client", .module = pravega_client_mod },
                .{ .name = "identity_event_producer", .module = identity_event_producer_mod },
            },
        }),
    });
    const test_identity_event_producer_step = b.step(
        "test-identity-event-producer",
        "Run M3.4 IdentityEventProducer conformance tests (mock HTTP, no Pravega required)",
    );
    test_identity_event_producer_step.dependOn(&b.addRunArtifact(identity_event_producer_test).step);

    // M3.6 — MfpTickProducer unit tests (mock HTTP server, no real Pravega).
    const mfp_tick_producer_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/mfp_tick_producer.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pravega_client", .module = pravega_client_mod },
        },
    });
    const mfp_tick_producer_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/tests/mfp_tick_producer_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mfp_tick_producer", .module = mfp_tick_producer_mod },
                .{ .name = "pravega_client", .module = pravega_client_mod },
            },
        }),
    });
    const test_mfp_tick_producer_step = b.step(
        "test-mfp-tick-producer",
        "Run M3.6 MfpTickProducer HMAC tick stream tests (mock HTTP, no Pravega required)",
    );
    test_mfp_tick_producer_step.dependOn(&b.addRunArtifact(mfp_tick_producer_test).step);

    // M4.3 — MfpMeter metering tests (mock HTTP server, no real Pravega).
    const mfp_metering_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/mfp_metering.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "mfp_tick_producer", .module = mfp_tick_producer_mod },
        },
    });
    const mfp_metering_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/tests/mfp_metering_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "mfp_metering", .module = mfp_metering_mod },
                .{ .name = "mfp_tick_producer", .module = mfp_tick_producer_mod },
                .{ .name = "pravega_client", .module = pravega_client_mod },
            },
        }),
    });
    const test_mfp_metering_step = b.step(
        "test-mfp-metering",
        "Run M4.3 MfpMeter metering tick tests (mock HTTP, no Pravega required)",
    );
    test_mfp_metering_step.dependOn(&b.addRunArtifact(mfp_metering_test).step);

    // M3.7 — PravegatSubscriber unit tests (mock HTTP server, no real Pravega).
    const pravega_subscriber_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/pravega_subscriber.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pravega_client", .module = pravega_client_mod },
        },
    });
    const pravega_subscriber_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/tests/pravega_subscriber_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pravega_client", .module = pravega_client_mod },
                .{ .name = "pravega_subscriber", .module = pravega_subscriber_mod },
            },
        }),
    });
    const test_pravega_subscriber_step = b.step(
        "test-pravega-subscriber",
        "Run M3.7 PravegatSubscriber adapter-side subscriber tests (mock HTTP, no Pravega required)",
    );
    test_pravega_subscriber_step.dependOn(&b.addRunArtifact(pravega_subscriber_test).step);

    // M3.8 — PravegatSubscriber snapshot + replay-from-tick tests (mock HTTP server, no real Pravega).
    const pravega_replay_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/tests/pravega_replay_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pravega_client", .module = pravega_client_mod },
                .{ .name = "pravega_subscriber", .module = pravega_subscriber_mod },
            },
        }),
    });
    const test_pravega_replay_step = b.step(
        "test-pravega-replay",
        "Run M3.8 PravegatSubscriber snapshot + replay-from-tick tests (mock HTTP, no Pravega required)",
    );
    test_pravega_replay_step.dependOn(&b.addRunArtifact(pravega_replay_test).step);

    // M3.9 — PaskInteractionProducer unit tests (mock HTTP server, no real Pravega).
    const pask_interaction_producer_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/pask_interaction_producer.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pravega_client", .module = pravega_client_mod },
        },
    });
    const pask_interaction_producer_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/tests/pask_interaction_producer_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pask_interaction_producer", .module = pask_interaction_producer_mod },
                .{ .name = "pravega_client", .module = pravega_client_mod },
            },
        }),
    });
    const test_pask_interaction_producer_step = b.step(
        "test-pask-interaction-producer",
        "Run M3.9 PaskInteractionProducer unit tests (mock HTTP, no Pravega required)",
    );
    test_pask_interaction_producer_step.dependOn(&b.addRunArtifact(pask_interaction_producer_test).step);

    // M3.10 — PaskReplayTool: Pravega replay → Pask snapshot derivation.
    // Pask kernel modules (native target, from core/pask/src/).
    const pask_config_mod = b.createModule(.{
        .root_source_file = b.path("../../core/pask/src/config.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    const pask_types_mod = b.createModule(.{
        .root_source_file = b.path("../../core/pask/src/types.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = pask_config_mod },
        },
    });
    const pask_store_mod = b.createModule(.{
        .root_source_file = b.path("../../core/pask/src/store.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = pask_config_mod },
            .{ .name = "types", .module = pask_types_mod },
        },
    });
    const pask_propagation_mod = b.createModule(.{
        .root_source_file = b.path("../../core/pask/src/propagation.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = pask_config_mod },
            .{ .name = "types", .module = pask_types_mod },
            .{ .name = "store", .module = pask_store_mod },
        },
    });
    const pask_stability_mod = b.createModule(.{
        .root_source_file = b.path("../../core/pask/src/stability.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = pask_config_mod },
            .{ .name = "types", .module = pask_types_mod },
            .{ .name = "store", .module = pask_store_mod },
        },
    });
    const pask_pruner_mod = b.createModule(.{
        .root_source_file = b.path("../../core/pask/src/pruner.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "config", .module = pask_config_mod },
            .{ .name = "types", .module = pask_types_mod },
            .{ .name = "store", .module = pask_store_mod },
        },
    });
    const pask_replay_tool_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/pask_replay_tool.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pravega_subscriber", .module = pravega_subscriber_mod },
            .{ .name = "pask_store", .module = pask_store_mod },
            .{ .name = "pask_config", .module = pask_config_mod },
            .{ .name = "pask_types", .module = pask_types_mod },
            .{ .name = "pask_propagation", .module = pask_propagation_mod },
            .{ .name = "pask_stability", .module = pask_stability_mod },
            .{ .name = "pask_pruner", .module = pask_pruner_mod },
        },
    });
    const pask_replay_tool_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/tests/pask_replay_tool_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pravega_client", .module = pravega_client_mod },
                .{ .name = "pravega_subscriber", .module = pravega_subscriber_mod },
                .{ .name = "pask_replay_tool", .module = pask_replay_tool_mod },
            },
        }),
    });
    const test_pask_replay_tool_step = b.step(
        "test-pask-replay-tool",
        "Run M3.10 PaskReplayTool Pravega replay → Pask snapshot determinism tests",
    );
    test_pask_replay_tool_step.dependOn(&b.addRunArtifact(pask_replay_tool_test).step);

    // M3-T-Pask: Pask kernel throughput + determinism benchmark suite.
    // Pure Zig executable — no external dependencies beyond the Pask kernel modules.
    // Run via: zig build bench-pask
    const bench_pask_exe = b.addExecutable(.{
        .name = "bench-pask",
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/bench/bench_pask.zig"),
            .target = native_target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "pask_store", .module = pask_store_mod },
                .{ .name = "pask_config", .module = pask_config_mod },
                .{ .name = "pask_types", .module = pask_types_mod },
                .{ .name = "pask_propagation", .module = pask_propagation_mod },
                .{ .name = "pask_stability", .module = pask_stability_mod },
                .{ .name = "pask_pruner", .module = pask_pruner_mod },
            },
        }),
    });
    const bench_pask_step = b.step(
        "bench-pask",
        "Build and run the Pask kernel throughput + determinism benchmark suite",
    );
    bench_pask_step.dependOn(&b.addRunArtifact(bench_pask_exe).step);

    // Phase 0: Smoke tests
    const smoke_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/smoke_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
            },
        }),
    });

    // Phase 1: Cell conformance tests
    const cell_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cell_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "cell", .module = native_mods.cell },
                // `commerce` import removed in RM-042 — the
                // Commerce/OnChainBinding-specific tests in this file
                // have been deleted.
            },
        }),
    });

    // Phase 1: Commerce conformance tests — REMOVED in RM-032b /
    // RM-042. The Commerce extension + OnChainBinding surfaces those
    // tests covered have been stripped; commerce_conformance.zig is
    // deleted. The `commerce` module remains as a (currently empty)
    // stub for back-compat with build.zig wiring; a follow-up can
    // remove that wiring entirely.

    // Phase 1: Multi-cell conformance tests
    const multicell_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/multicell_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "cell", .module = native_mods.cell },
                .{ .name = "multicell", .module = native_mods.multicell },
            },
        }),
    });

    // Phase 2: BCA conformance tests
    const bca_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/bca_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "bca", .module = native_mods.bca },
            },
        }),
    });

    // Phase 3: Allocator conformance tests
    const allocator_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/allocator_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "allocator", .module = native_mods.allocator },
            },
        }),
    });

    // Phase 3: PDA conformance tests
    const pda_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/pda_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "errors", .module = native_mods.errors },
                .{ .name = "pda", .module = native_mods.pda },
            },
        }),
    });

    // Phase 3: Opcode conformance tests
    const opcodes_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/opcodes_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "errors", .module = native_mods.errors },
                .{ .name = "pda", .module = native_mods.pda },
                .{ .name = "host", .module = native_mods.host },
                .{ .name = "standard", .module = native_mods.standard },
                .{ .name = "allocator", .module = native_mods.allocator },
                .{ .name = "sighash", .module = native_mods.sighash },
            },
        }),
    });

    // Phase 3: Macro conformance tests
    const macro_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/macro_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "errors", .module = native_mods.errors },
                .{ .name = "pda", .module = native_mods.pda },
                .{ .name = "host", .module = native_mods.host },
                .{ .name = "macro", .module = native_mods.macro },
            },
        }),
    });

    // Phase 3: Executor conformance tests
    const executor_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/executor_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "errors", .module = native_mods.errors },
                .{ .name = "pda", .module = native_mods.pda },
                .{ .name = "host", .module = native_mods.host },
                .{ .name = "standard", .module = native_mods.standard },
                .{ .name = "macro", .module = native_mods.macro },
                .{ .name = "plexus", .module = native_mods.plexus },
                .{ .name = "linearity", .module = native_mods.linearity },
                .{ .name = "allocator", .module = native_mods.allocator },
                .{ .name = "sighash", .module = native_mods.sighash },
                .{ .name = "executor", .module = native_mods.executor },
            },
        }),
    });

    // Macro legacy-lowering equivalence: native 0xB0 macros vs the TS
    // unroller's legacy-opcode expansions (script-macro.ts) ⇒ same PDA stack.
    const macro_legacy_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/macro_legacy_equivalence.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "errors", .module = native_mods.errors },
                .{ .name = "pda", .module = native_mods.pda },
                .{ .name = "host", .module = native_mods.host },
                .{ .name = "standard", .module = native_mods.standard },
                .{ .name = "macro", .module = native_mods.macro },
                .{ .name = "plexus", .module = native_mods.plexus },
                .{ .name = "linearity", .module = native_mods.linearity },
                .{ .name = "allocator", .module = native_mods.allocator },
                .{ .name = "sighash", .module = native_mods.sighash },
                .{ .name = "executor", .module = native_mods.executor },
            },
        }),
    });

    // tile-script equivalence: the TS `stepTile`-in-Script compiler's emitted
    // bytecode, executed in the engine, vs the native MNCA rule (mnca_tile).
    const mnca_tile_mod = b.createModule(.{
        .root_source_file = b.path("src/mnca_tile.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    const tile_script_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/tile_script_equivalence.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "errors", .module = native_mods.errors },
                .{ .name = "pda", .module = native_mods.pda },
                .{ .name = "host", .module = native_mods.host },
                .{ .name = "standard", .module = native_mods.standard },
                .{ .name = "macro", .module = native_mods.macro },
                .{ .name = "plexus", .module = native_mods.plexus },
                .{ .name = "linearity", .module = native_mods.linearity },
                .{ .name = "allocator", .module = native_mods.allocator },
                .{ .name = "sighash", .module = native_mods.sighash },
                .{ .name = "executor", .module = native_mods.executor },
                .{ .name = "mnca_tile", .module = mnca_tile_mod },
            },
        }),
    });

    // Phase 4: Linearity conformance tests
    const linearity_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/linearity_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "errors", .module = native_mods.errors },
                .{ .name = "pda", .module = native_mods.pda },
                .{ .name = "linearity", .module = native_mods.linearity },
            },
        }),
    });

    // Phase 4: Plexus conformance tests
    const plexus_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/plexus_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "errors", .module = native_mods.errors },
                .{ .name = "pda", .module = native_mods.pda },
                .{ .name = "linearity", .module = native_mods.linearity },
                .{ .name = "plexus", .module = native_mods.plexus },
            },
        }),
    });

    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&b.addRunArtifact(lmdb_test).step);
    test_step.dependOn(&b.addRunArtifact(smoke_test).step);
    test_step.dependOn(&b.addRunArtifact(cell_test).step);
    // commerce_test wiring removed in RM-032b/RM-042 alongside the
    // commerce_conformance.zig deletion (see line ~1202).
    test_step.dependOn(&b.addRunArtifact(multicell_test).step);
    test_step.dependOn(&b.addRunArtifact(bca_test).step);
    test_step.dependOn(&b.addRunArtifact(allocator_test).step);
    test_step.dependOn(&b.addRunArtifact(pda_test).step);
    test_step.dependOn(&b.addRunArtifact(opcodes_test).step);
    test_step.dependOn(&b.addRunArtifact(macro_test).step);
    test_step.dependOn(&b.addRunArtifact(macro_legacy_test).step);
    test_step.dependOn(&b.addRunArtifact(tile_script_test).step);
    test_step.dependOn(&b.addRunArtifact(executor_test).step);
    test_step.dependOn(&b.addRunArtifact(linearity_test).step);
    test_step.dependOn(&b.addRunArtifact(plexus_test).step);

    // PR-3b: host_compute_sighash inline tests.
    const host_compute_sighash_test = b.addTest(.{
        .root_module = native_mods.host_compute_sighash,
    });
    test_step.dependOn(&b.addRunArtifact(host_compute_sighash_test).step);

    // PR-4: host_resolve_script_template inline tests.
    const host_resolve_script_template_test = b.addTest(.{
        .root_module = native_mods.host_resolve_script_template,
    });
    test_step.dependOn(&b.addRunArtifact(host_resolve_script_template_test).step);

    // PR-5: host_verify_partial_sig inline tests.
    const host_verify_partial_sig_test = b.addTest(.{
        .root_module = native_mods.host_verify_partial_sig,
    });
    test_step.dependOn(&b.addRunArtifact(host_verify_partial_sig_test).step);

    // PR-5: host_compute_preimage_hashes inline tests.
    const host_compute_preimage_hashes_test = b.addTest(.{
        .root_module = native_mods.host_compute_preimage_hashes,
    });
    test_step.dependOn(&b.addRunArtifact(host_compute_preimage_hashes_test).step);

    // PR-5b: host_assemble_tx inline tests.
    const host_assemble_tx_test = b.addTest(.{
        .root_module = native_mods.host_assemble_tx,
    });
    test_step.dependOn(&b.addRunArtifact(host_assemble_tx_test).step);

    // PR-7a: host_verify_beef_spv inline tests. Gated — only runs in
    // the full (non-embedded) profile when bsvz + beef are wired in.
    if (native_mods.host_verify_beef_spv) |mod| {
        const host_verify_beef_spv_test = b.addTest(.{ .root_module = mod });
        test_step.dependOn(&b.addRunArtifact(host_verify_beef_spv_test).step);
    }

    // PR-8b-i: host_mnca_verify_transition inline tests. Available in
    // every profile (mnca_tile is std-only, no bsvz dependency).
    const host_mnca_verify_transition_test = b.addTest(.{
        .root_module = native_mods.host_mnca_verify_transition,
    });
    test_step.dependOn(&b.addRunArtifact(host_mnca_verify_transition_test).step);

    // ── cellsh: native CLI shell ──
    // Builds a native executable that links directly to the kernel modules.
    // Usage: zig build cellsh && ./zig-out/bin/cellsh
    const cellsh_mod = b.createModule(.{
        .root_source_file = b.path("src/cellsh.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    cellsh_mod.addImport("constants", native_mods.constants);
    cellsh_mod.addImport("errors", native_mods.errors);
    cellsh_mod.addImport("cell", native_mods.cell);
    cellsh_mod.addImport("multicell", native_mods.multicell);
    cellsh_mod.addImport("pda", native_mods.pda);
    cellsh_mod.addImport("executor", native_mods.executor);
    cellsh_mod.addImport("allocator", native_mods.allocator);
    cellsh_mod.addImport("sighash", native_mods.sighash);
    cellsh_mod.addImport("linearity", native_mods.linearity);
    cellsh_mod.addImport("octave", native_mods.octave);
    cellsh_mod.addImport("pointer", native_mods.pointer);

    const cellsh_exe = b.addExecutable(.{
        .name = "cellsh",
        .root_module = cellsh_mod,
    });
    // NOTE: cellsh excluded from default install due to Zig 0.15 I/O API break.
    // Build explicitly via: zig build cellsh
    // b.installArtifact(cellsh_exe);

    const cellsh_step = b.step("cellsh", "Build cellsh — Semantos Plane native shell");
    cellsh_step.dependOn(&b.addInstallArtifact(cellsh_exe, .{}).step);

    // Named test steps for individual suites
    const test_linearity_step = b.step("test-linearity", "Run linearity conformance tests");
    test_linearity_step.dependOn(&b.addRunArtifact(linearity_test).step);

    const test_plexus_step = b.step("test-plexus", "Run plexus conformance tests");
    test_plexus_step.dependOn(&b.addRunArtifact(plexus_test).step);

    // Phase 12: Fuzz harnesses
    const fuzz_linearity = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("fuzz/linearity_fuzz.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "pda", .module = native_mods.pda },
                .{ .name = "linearity", .module = native_mods.linearity },
            },
        }),
    });
    const fuzz_linearity_step = b.step("fuzz-linearity", "Run linearity fuzz harness");
    fuzz_linearity_step.dependOn(&b.addRunArtifact(fuzz_linearity).step);
    test_step.dependOn(&b.addRunArtifact(fuzz_linearity).step);

    const fuzz_opcodes = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("fuzz/opcode_fuzz.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "pda", .module = native_mods.pda },
                .{ .name = "linearity", .module = native_mods.linearity },
                .{ .name = "plexus", .module = native_mods.plexus },
            },
        }),
    });
    const fuzz_opcodes_step = b.step("fuzz-opcodes", "Run opcode fuzz harness");
    fuzz_opcodes_step.dependOn(&b.addRunArtifact(fuzz_opcodes).step);
    test_step.dependOn(&b.addRunArtifact(fuzz_opcodes).step);

    const fuzz_stack = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("fuzz/stack_bounds_fuzz.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "pda", .module = native_mods.pda },
            },
        }),
    });
    const fuzz_stack_step = b.step("fuzz-stack", "Run stack bounds fuzz harness");
    fuzz_stack_step.dependOn(&b.addRunArtifact(fuzz_stack).step);
    test_step.dependOn(&b.addRunArtifact(fuzz_stack).step);

    const fuzz_plexus = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("fuzz/plexus_atomic_fuzz.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "pda", .module = native_mods.pda },
                .{ .name = "linearity", .module = native_mods.linearity },
                .{ .name = "plexus", .module = native_mods.plexus },
            },
        }),
    });
    const fuzz_plexus_step = b.step("fuzz-plexus", "Run plexus atomicity fuzz harness");
    fuzz_plexus_step.dependOn(&b.addRunArtifact(fuzz_plexus).step);
    test_step.dependOn(&b.addRunArtifact(fuzz_plexus).step);

    // Phase 12: Differential conformance tests (Lean ↔ Zig)
    const differential_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/differential_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "errors", .module = native_mods.errors },
                .{ .name = "pda", .module = native_mods.pda },
                .{ .name = "linearity", .module = native_mods.linearity },
                .{ .name = "plexus", .module = native_mods.plexus },
            },
        }),
    });
    const test_differential_step = b.step("test-differential", "Run differential conformance tests");
    test_differential_step.dependOn(&b.addRunArtifact(differential_test).step);
    test_step.dependOn(&b.addRunArtifact(differential_test).step);

    // D-LC2 — Load proofs/vectors/plexus-vectors.json and dispatch each
    // vector through plexus.executePlexus. Makes the JSON the literal source
    // of truth for the K2/K3 plexus conformance check (vs the hand-coded
    // table in differential_conformance.zig). Cwd-relative read of
    // ../../proofs/vectors/; runs from the repo root via `zig build test`.
    const lean_vector_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/lean_vector_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "errors", .module = native_mods.errors },
                .{ .name = "pda", .module = native_mods.pda },
                .{ .name = "linearity", .module = native_mods.linearity },
                .{ .name = "plexus", .module = native_mods.plexus },
            },
        }),
    });
    const test_lean_vector_step = b.step("test-lean-vectors", "Run Lean JSON-vector conformance (D-LC2)");
    test_lean_vector_step.dependOn(&b.addRunArtifact(lean_vector_test).step);
    test_step.dependOn(&b.addRunArtifact(lean_vector_test).step);

    // Phase 6: Octave conformance tests
    const octave_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/octave_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "octave", .module = native_mods.octave },
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "pointer", .module = native_mods.pointer },
            },
        }),
    });
    const test_octave_step = b.step("test-octave", "Run octave conformance tests");
    test_octave_step.dependOn(&b.addRunArtifact(octave_test).step);
    test_step.dependOn(&b.addRunArtifact(octave_test).step);

    // Phase 5: Crypto conformance tests (available in both profiles)
    const crypto_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/crypto_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "host", .module = native_mods.host },
            },
        }),
    });
    const test_crypto_step = b.step("test-crypto", "Run crypto conformance tests");
    test_crypto_step.dependOn(&b.addRunArtifact(crypto_test).step);
    test_step.dependOn(&b.addRunArtifact(crypto_test).step);

    // Phase W1: OP_SIGN conformance + bsvz differential (full profile only)
    if (native_mods.bsvz) |bsvz_mod_inner| {
        const sign_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("tests/sign_conformance.zig"),
                .target = native_target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "constants", .module = native_mods.constants },
                    .{ .name = "linearity", .module = native_mods.linearity },
                    .{ .name = "pda", .module = native_mods.pda },
                    .{ .name = "plexus", .module = native_mods.plexus },
                    .{ .name = "host", .module = native_mods.host },
                    .{ .name = "bsvz", .module = bsvz_mod_inner },
                },
            }),
        });
        const test_sign_step = b.step("test-sign", "Run OP_SIGN conformance + bsvz differential");
        test_sign_step.dependOn(&b.addRunArtifact(sign_test).step);
        test_step.dependOn(&b.addRunArtifact(sign_test).step);

        // Phase W3: OP_DECREMENT_BUDGET / OP_REFILL_BUDGET conformance.
        const budget_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("tests/budget_conformance.zig"),
                .target = native_target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "constants", .module = native_mods.constants },
                    .{ .name = "linearity", .module = native_mods.linearity },
                    .{ .name = "pda", .module = native_mods.pda },
                    .{ .name = "plexus", .module = native_mods.plexus },
                    .{ .name = "host", .module = native_mods.host },
                    .{ .name = "bsvz", .module = bsvz_mod_inner },
                },
            }),
        });
        const test_budget_step = b.step("test-budget", "Run OP_DECREMENT_BUDGET + OP_REFILL_BUDGET conformance");
        test_budget_step.dependOn(&b.addRunArtifact(budget_test).step);
        test_step.dependOn(&b.addRunArtifact(budget_test).step);

        // Phase W3.5: DerivationStateStore + host_derive_leaf + host_state_next_index conformance.
        const derivation_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("tests/derivation_conformance.zig"),
                .target = native_target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "host", .module = native_mods.host },
                    .{ .name = "derivation_state", .module = native_mods.derivation_state },
                    .{ .name = "bsvz", .module = bsvz_mod_inner },
                },
            }),
        });
        const test_derivation_step = b.step("test-derivation", "Run BRC-42 derivation + state-store conformance");
        test_derivation_step.dependOn(&b.addRunArtifact(derivation_test).step);
        test_step.dependOn(&b.addRunArtifact(derivation_test).step);

        // Phase WA2: OutputStore inline tests — exercises the LocalOutputStore
        // vtable + add/get/markSpent/listOutputs/prune/snapshot/replay paths.
        const output_store_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/output_store.zig"),
                .target = native_target,
                .optimize = optimize,
            }),
        });
        const test_output_store_step = b.step("test-output-store", "Run WA2 OutputStore vtable conformance");
        test_output_store_step.dependOn(&b.addRunArtifact(output_store_test).step);
        test_step.dependOn(&b.addRunArtifact(output_store_test).step);

        // Phase W4: SlotStore + host_unlock_tier / host_persist_cell /
        // host_load_cell conformance (at-rest tier-key persistence).
        const storage_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("tests/storage_conformance.zig"),
                .target = native_target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "host", .module = native_mods.host },
                    .{ .name = "slot_store", .module = native_mods.slot_store },
                    .{ .name = "bsvz", .module = bsvz_mod_inner },
                },
            }),
        });
        const test_storage_step = b.step("test-storage", "Run W4 SlotStore + at-rest tier-cell conformance");
        test_storage_step.dependOn(&b.addRunArtifact(storage_test).step);
        test_step.dependOn(&b.addRunArtifact(storage_test).step);

        // Phase W11: Tier-3 vault multisig + nSequence cooldown conformance.
        // Reuses host.checkmultisig — no new opcodes. Reference: design §4.3,
        // §4.4, and docs/design/VAULT-MULTISIG-NSEQUENCE.md.
        const vault_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("tests/vault_conformance.zig"),
                .target = native_target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "constants", .module = native_mods.constants },
                    .{ .name = "linearity", .module = native_mods.linearity },
                    .{ .name = "pda", .module = native_mods.pda },
                    .{ .name = "plexus", .module = native_mods.plexus },
                    .{ .name = "host", .module = native_mods.host },
                    .{ .name = "bsvz", .module = bsvz_mod_inner },
                },
            }),
        });
        const test_vault_step = b.step("test-vault", "Run W11 vault multisig + nSequence conformance");
        test_vault_step.dependOn(&b.addRunArtifact(vault_test).step);
        test_step.dependOn(&b.addRunArtifact(vault_test).step);
    }

    // Phase WH1: pure-Zig PoW verifier conformance (no bsvz dep — runs in
    // both embedded and full profiles).
    const headers_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/headers_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "headers", .module = native_mods.headers },
            },
        }),
    });
    const test_headers_step = b.step("test-headers", "Run WH1 PoW verifier conformance tests");
    test_headers_step.dependOn(&b.addRunArtifact(headers_test).step);
    test_step.dependOn(&b.addRunArtifact(headers_test).step);

    // Phase WH2: HeaderStore conformance.
    const header_store_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/header_store_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "headers", .module = native_mods.headers },
                .{ .name = "header_store", .module = native_mods.header_store },
            },
        }),
    });
    const test_header_store_step = b.step("test-header-store", "Run WH2 HeaderStore conformance tests");
    test_header_store_step.dependOn(&b.addRunArtifact(header_store_test).step);
    test_step.dependOn(&b.addRunArtifact(header_store_test).step);

    // Phase WH5: LocalHeaderChainTracker conformance.
    const local_chain_tracker_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/local_chain_tracker.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "headers", .module = native_mods.headers },
                .{ .name = "header_store", .module = native_mods.header_store },
            },
        }),
    });
    const test_local_chain_tracker_step = b.step(
        "test-local-chain-tracker",
        "Run WH5 LocalHeaderChainTracker conformance tests",
    );
    test_local_chain_tracker_step.dependOn(&b.addRunArtifact(local_chain_tracker_test).step);
    test_step.dependOn(&b.addRunArtifact(local_chain_tracker_test).step);

    // M7.1 — SlotRouter conformance tests.
    const slot_router_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/federation/slot_router.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    const slot_router_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/tests/slot_router_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "slot_router", .module = slot_router_mod },
            },
        }),
    });
    const test_slot_router_step = b.step(
        "test-slot-router",
        "Run M7.1 SlotRouter conformance tests",
    );
    test_slot_router_step.dependOn(&b.addRunArtifact(slot_router_test).step);

    // M7.2 — FederatedSemantosOutputStore conformance tests.
    const rpc_log_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/federation/rpc_log.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    const federated_output_store_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/federation/federated_output_store.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "output_store", .module = native_mods.output_store },
            .{ .name = "slot_router", .module = slot_router_mod },
            .{ .name = "rpc_log", .module = rpc_log_mod },
        },
    });
    const federated_output_store_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/tests/federated_output_store_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "output_store", .module = native_mods.output_store },
                .{ .name = "federated_output_store", .module = federated_output_store_mod },
                .{ .name = "rpc_log", .module = rpc_log_mod },
                .{ .name = "slot_router", .module = slot_router_mod },
            },
        }),
    });
    const test_federated_output_store_step = b.step(
        "test-federated-output-store",
        "Run M7.2 FederatedSemantosOutputStore conformance tests",
    );
    test_federated_output_store_step.dependOn(&b.addRunArtifact(federated_output_store_test).step);

    // M7.5 — PeerRegistry reputation + onboarding tests.
    const peer_registry_mod_build = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/federation/peer_registry.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    const peer_registry_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/tests/peer_registry_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "peer_registry", .module = peer_registry_mod_build },
            },
        }),
    });
    const test_peer_registry_step = b.step(
        "test-peer-registry",
        "Run M7.5 PeerRegistry reputation + onboarding tests",
    );
    test_peer_registry_step.dependOn(&b.addRunArtifact(peer_registry_test).step);

    // M7.4 — FederatedSemantosStateStore conformance tests.
    const federated_state_store_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/federation/federated_state_store.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "derivation_state", .module = native_mods.derivation_state },
            .{ .name = "slot_router", .module = slot_router_mod },
            .{ .name = "rpc_log", .module = rpc_log_mod },
        },
    });
    const federated_state_store_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/tests/federated_state_store_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "derivation_state", .module = native_mods.derivation_state },
                .{ .name = "federated_state_store", .module = federated_state_store_mod },
                .{ .name = "rpc_log", .module = rpc_log_mod },
                .{ .name = "slot_router", .module = slot_router_mod },
            },
        }),
    });
    const test_federated_state_store_step = b.step(
        "test-federated-state-store",
        "Run M7.4 FederatedSemantosStateStore conformance tests",
    );
    test_federated_state_store_step.dependOn(&b.addRunArtifact(federated_state_store_test).step);

    // M7.3 — FederatedSemantosHeaderStore conformance tests.
    const federated_header_store_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/federation/federated_header_store.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "header_store", .module = native_mods.header_store },
            .{ .name = "slot_router", .module = slot_router_mod },
            .{ .name = "rpc_log", .module = rpc_log_mod },
        },
    });
    const federated_header_store_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/tests/federated_header_store_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "header_store", .module = native_mods.header_store },
                .{ .name = "headers", .module = native_mods.headers },
                .{ .name = "federated_header_store", .module = federated_header_store_mod },
                .{ .name = "rpc_log", .module = rpc_log_mod },
                .{ .name = "slot_router", .module = slot_router_mod },
            },
        }),
    });
    const test_federated_header_store_step = b.step(
        "test-federated-header-store",
        "Run M7.3 FederatedSemantosHeaderStore conformance tests",
    );
    test_federated_header_store_step.dependOn(&b.addRunArtifact(federated_header_store_test).step);

    // M3.5 — UtxoChangeProducer unit tests (mock HTTP server, no real Pravega).
    const utxo_change_producer_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/utxo_change_producer.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pravega_client", .module = pravega_client_mod },
        },
    });
    const utxo_change_producer_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/tests/utxo_change_producer_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "utxo_change_producer", .module = utxo_change_producer_mod },
                .{ .name = "pravega_client", .module = pravega_client_mod },
            },
        }),
    });
    const test_utxo_change_producer_step = b.step(
        "test-utxo-change-producer",
        "Run M3.5 UtxoChangeProducer unit tests (mock HTTP, no Pravega required)",
    );
    test_utxo_change_producer_step.dependOn(&b.addRunArtifact(utxo_change_producer_test).step);

    // M6.3 — RegistryChangeProducer unit tests (mock HTTP server, no real Pravega).
    const registry_change_producer_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/registry_change_producer.zig"),
        .target = native_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "pravega_client", .module = pravega_client_mod },
        },
    });
    const registry_change_producer_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/tests/registry_change_producer_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "registry_change_producer", .module = registry_change_producer_mod },
                .{ .name = "pravega_client", .module = pravega_client_mod },
            },
        }),
    });
    const test_registry_change_producer_step = b.step(
        "test-registry-change-producer",
        "Run M6.3 RegistryChangeProducer unit tests (mock HTTP, no Pravega required)",
    );
    test_registry_change_producer_step.dependOn(&b.addRunArtifact(registry_change_producer_test).step);

    // M5.14 — Action-cell teachback: sir_program_hash in phase-0x06 payload.
    const action_cell_teachback_mod = b.createModule(.{
        .root_source_file = b.path("../../runtime/semantos-brain/src/action_cell_teachback.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    const action_cell_teachback_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/tests/action_cell_teachback_test.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "action_cell_teachback", .module = action_cell_teachback_mod },
            },
        }),
    });
    const test_action_cell_teachback_step = b.step(
        "test-action-cell-teachback",
        "Run M5.14 action-cell teachback sir_program_hash tests",
    );
    test_action_cell_teachback_step.dependOn(&b.addRunArtifact(action_cell_teachback_test).step);

    // Phase 5: SPV conformance tests (full profile only)
    if (native_mods.beef) |beef| {
        const spv_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("tests/spv_conformance.zig"),
                .target = native_target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "host", .module = native_mods.host },
                    .{ .name = "errors", .module = native_mods.errors },
                    .{ .name = "allocator", .module = native_mods.allocator },
                    .{ .name = "beef", .module = beef },
                },
            }),
        });
        const test_spv_step = b.step("test-spv", "Run SPV conformance tests");
        test_spv_step.dependOn(&b.addRunArtifact(spv_test).step);
        test_step.dependOn(&b.addRunArtifact(spv_test).step);

        // Phase 5: Capability conformance tests
        const capability_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("tests/capability_conformance.zig"),
                .target = native_target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "constants", .module = native_mods.constants },
                    .{ .name = "errors", .module = native_mods.errors },
                    .{ .name = "host", .module = native_mods.host },
                    .{ .name = "pda", .module = native_mods.pda },
                    .{ .name = "linearity", .module = native_mods.linearity },
                    .{ .name = "allocator", .module = native_mods.allocator },
                    .{ .name = "sighash", .module = native_mods.sighash },
                    .{ .name = "standard", .module = native_mods.standard },
                    .{ .name = "macro", .module = native_mods.macro },
                    .{ .name = "plexus", .module = native_mods.plexus },
                    .{ .name = "executor", .module = native_mods.executor },
                },
            }),
        });
        const test_capability_step = b.step("test-capability", "Run capability conformance tests");
        test_capability_step.dependOn(&b.addRunArtifact(capability_test).step);
        test_step.dependOn(&b.addRunArtifact(capability_test).step);
    }

    // WI-D2 — CognitionBounty inline tests (verified_weight_output_match).
    const cognition_bounty_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cognition_bounty.zig"),
            .target = native_target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(cognition_bounty_test).step);

    // D-OCT-escalation-descriptor — escalation descriptor wire format (step 1/5).
    // Self-contained (std only), mirrors core/protocol-types/src/escalation-descriptor.ts.
    const escalation_descriptor_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/escalation_descriptor.zig"),
            .target = native_target,
            .optimize = optimize,
        }),
    });
    const test_escalation_descriptor_step = b.step(
        "test-escalation-descriptor",
        "Run D-OCT-escalation-descriptor conformance tests (oracle<->mirror)",
    );
    test_escalation_descriptor_step.dependOn(&b.addRunArtifact(escalation_descriptor_test).step);
    test_step.dependOn(&b.addRunArtifact(escalation_descriptor_test).step);

    // T1 — canonical structured typeHash construction (kernel primitive).
    // Self-contained (std only); parity-tested against TS mirror at
    // core/protocol-types/src/type-hash.ts.  See docs/design/STRUCTURED-TYPEHASH-CANONICAL.md.
    const type_hash_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/type_hash.zig"),
            .target = native_target,
            .optimize = optimize,
        }),
    });
    const test_type_hash_step = b.step(
        "test-type-hash",
        "Run T1 typeHash parity tests (Zig side; TS mirror runs under bun)",
    );
    test_type_hash_step.dependOn(&b.addRunArtifact(type_hash_test).step);
    test_step.dependOn(&b.addRunArtifact(type_hash_test).step);

    // T3.b — MNCA cell-type spec parity (Zig comptime mirror of
    // cartridges/mnca/cartridge.json).  Depends on type_hash module.
    const type_hash_mod = b.createModule(.{
        .root_source_file = b.path("src/type_hash.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    const mnca_specs_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../cartridges/mnca/brain/mnca_cell_specs.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "type_hash", .module = type_hash_mod },
            },
        }),
    });
    const test_mnca_specs_step = b.step(
        "test-mnca-specs",
        "Run T3.b MNCA cell-spec parity tests (Zig comptime vs manifest)",
    );
    test_mnca_specs_step.dependOn(&b.addRunArtifact(mnca_specs_test).step);
    test_step.dependOn(&b.addRunArtifact(mnca_specs_test).step);

    // T6 — betterment cell-type spec parity (Zig comptime mirror of
    // cartridges/betterment/cartridge.json).  Same shape as mnca_specs_test.
    const betterment_specs_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../cartridges/betterment/brain/zig/betterment_cell_specs.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "type_hash", .module = type_hash_mod },
            },
        }),
    });
    const test_betterment_specs_step = b.step(
        "test-betterment-specs",
        "Run T6 betterment cell-spec parity tests (Zig comptime vs manifest)",
    );
    test_betterment_specs_step.dependOn(&b.addRunArtifact(betterment_specs_test).step);
    test_step.dependOn(&b.addRunArtifact(betterment_specs_test).step);

    // D-OCT-data-octave-bump — octave-0/1 escalation conformance tests (step 2/5).
    // Tests: compat regression (rung-0 byte-identical), escalation to rung-1,
    // round-trip, O-1 header total_size semantics, canonical oracle↔mirror vector.
    // Uses native_mods.escalation_descriptor (the same module instance already
    // wired into native_mods.multicell) to avoid the "file belongs to two modules"
    // compile error that arises from creating a second module for the same file.
    const multicell_octave_bump_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/multicell_octave_bump_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "cell", .module = native_mods.cell },
                .{ .name = "multicell", .module = native_mods.multicell },
                .{ .name = "escalation_descriptor", .module = native_mods.escalation_descriptor },
            },
        }),
    });
    const test_multicell_octave_bump_step = b.step(
        "test-multicell-octave-bump",
        "Run D-OCT-data-octave-bump conformance tests (octave-0/1 escalation)",
    );
    test_multicell_octave_bump_step.dependOn(&b.addRunArtifact(multicell_octave_bump_test).step);
    test_step.dependOn(&b.addRunArtifact(multicell_octave_bump_test).step);

    // ── D-OCT-merkle-hierarchy (step 3/5): cell merkle conformance tests ──────
    //
    // Tests: rung-0/1 backward-compat, canonical root (oracle↔mirror), inclusion proof
    // verify/fail, pack/unpack round-trip, isMerkleHierarchy, edge cases.
    //
    // Uses native_mods.cell_merkle (already uses native_mods.multicell via its imports)
    // to avoid "file belongs to two modules" compile error.
    //
    // Run: zig build test-cell-merkle -j1 --summary all
    const cell_merkle_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/cell_merkle_conformance.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "constants", .module = native_mods.constants },
                .{ .name = "cell", .module = native_mods.cell },
                .{ .name = "multicell", .module = native_mods.multicell },
                .{ .name = "cell_merkle", .module = native_mods.cell_merkle },
                .{ .name = "escalation_descriptor", .module = native_mods.escalation_descriptor },
            },
        }),
    });
    const test_cell_merkle_step = b.step(
        "test-cell-merkle",
        "Run D-OCT-merkle-hierarchy conformance tests (rung-2 cell merkle)",
    );
    test_cell_merkle_step.dependOn(&b.addRunArtifact(cell_merkle_test).step);
    test_step.dependOn(&b.addRunArtifact(cell_merkle_test).step);

    // ── D-OCT-path-merkle-unify (step 4/5): routing path-merkle overload ─────
    //
    // Tests: segment tuple encoding, path-merkle root computation, inclusion proof
    // generation/verification, encode/decode round-trip, canonical oracle↔Zig vector.
    //
    // Uses native_mods.path_merkle (which already imports native_mods.cell_merkle).
    //
    // Run: zig build test-path-merkle -j1 --summary all
    const path_merkle_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/path_merkle.zig"),
            .target = native_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cell_merkle", .module = native_mods.cell_merkle },
            },
        }),
    });
    const test_path_merkle_step = b.step(
        "test-path-merkle",
        "Run D-OCT-path-merkle-unify conformance tests (routing path-merkle overload)",
    );
    test_path_merkle_step.dependOn(&b.addRunArtifact(path_merkle_test).step);
    test_step.dependOn(&b.addRunArtifact(path_merkle_test).step);

    // ── D-OCT-path-merkle-unify (step 4/5): routing.zig overload tests ────────
    //
    // Tests: processHop with FLAG_PATH_MERKLE_OVERLOAD — canonical root, full 3-hop
    // walk, tamper rejections (type-mismatch, budget-exhausted, not-my-hop, checksum),
    // non-mutation. Also includes all pre-existing inline FLAG_PATH_IN_PAYLOAD tests.
    //
    // routing.zig is self-contained (std only, no cell_merkle import) so it runs
    // as a standalone zig test.
    //
    // Run: zig build test-routing -j1 --summary all
    const routing_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/routing.zig"),
            .target = native_target,
            .optimize = optimize,
        }),
    });
    const test_routing_step = b.step(
        "test-routing",
        "Run routing.zig inline tests (inline path + PATH_MERKLE_OVERLOAD)",
    );
    test_routing_step.dependOn(&b.addRunArtifact(routing_test).step);
    test_step.dependOn(&b.addRunArtifact(routing_test).step);

    // ── LMDB throughput benchmark suite ───────────────────────────────────────
    //
    // Usage: zig build bench-lmdb
    //
    // Prerequisites:
    //   macOS:          brew install lmdb
    //   Debian/Ubuntu:  apt-get install liblmdb-dev
    //
    // Prints a formatted results table comparing 10K / 100K / 1M cell workloads
    // against the M1-T torture-test targets (50K writes/s, 200K reads/s).
    const bench_lmdb_exe = b.addExecutable(.{
        .name = "bench-lmdb",
        .root_module = b.createModule(.{
            .root_source_file = b.path("../../runtime/semantos-brain/bench/bench_lmdb.zig"),
            .target = native_target,
            .optimize = .ReleaseFast,
            .imports = &.{
                .{ .name = "lmdb", .module = lmdb_mod },
            },
        }),
    });
    bench_lmdb_exe.linkLibC();
    const bench_lmdb_step = b.step("bench-lmdb", "Run LMDB throughput benchmarks");
    bench_lmdb_step.dependOn(&b.addRunArtifact(bench_lmdb_exe).step);
}

```
