---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tools/sx/build.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.993431+00:00
---

# core/cell-engine/tools/sx/build.zig

```zig
//! Build script for the `.sx` Zig dialect toolchain.
//!
//! PR-1 scope:
//!   - `sx` static library (lexer + AST node types)
//!   - `parity-tokenise` test executable driving the lexer against vendored
//!     fixtures from bitcoinsx
//!
//! PR-4 will add a WASM build step and an npm-packageable artifact.
//!
//! Run:
//!   zig build               # build the static library
//!   zig build test          # run parity tests
//!   zig build test -- --filter "tokeniser:nop"   # one case (when wired)

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // -------------------------------------------------------------------
    // The `sx` module — exposes Lexer, Node, NodeType, TokeniserError.
    // -------------------------------------------------------------------
    const sx_mod = b.addModule("sx", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Static lib build (consumers in the brain, in `tools/asm.zig`'s sibling
    // dialect-registry work, and the future WASM target all link this).
    const sx_lib = b.addLibrary(.{
        .name = "sx",
        .root_module = sx_mod,
        .linkage = .static,
    });
    b.installArtifact(sx_lib);

    // -------------------------------------------------------------------
    // Parity test against bitcoinsx tokeniser test cases.
    // -------------------------------------------------------------------
    const parity_tokenise_mod = b.createModule(.{
        .root_source_file = b.path("tests/parity_tokenise.zig"),
        .target = target,
        .optimize = optimize,
    });
    parity_tokenise_mod.addImport("sx", sx_mod);

    const parity_tokenise = b.addTest(.{
        .name = "parity-tokenise",
        .root_module = parity_tokenise_mod,
    });

    const run_parity_tokenise = b.addRunArtifact(parity_tokenise);

    // -------------------------------------------------------------------
    // Parity test against bitcoinsx parser test cases (PR-2 scope).
    // -------------------------------------------------------------------
    const parity_parse_mod = b.createModule(.{
        .root_source_file = b.path("tests/parity_parse.zig"),
        .target = target,
        .optimize = optimize,
    });
    parity_parse_mod.addImport("sx", sx_mod);

    const parity_parse = b.addTest(.{
        .name = "parity-parse",
        .root_module = parity_parse_mod,
    });
    const run_parity_parse = b.addRunArtifact(parity_parse);

    // -------------------------------------------------------------------
    // Parity test for the lowerer — hex-output comparison against
    // hand-crafted goldens (PR-3 skeleton). PR-3.x extends this to drive
    // his full src/sx/contracts/ corpus.
    // -------------------------------------------------------------------
    const parity_lower_mod = b.createModule(.{
        .root_source_file = b.path("tests/parity_lower.zig"),
        .target = target,
        .optimize = optimize,
    });
    parity_lower_mod.addImport("sx", sx_mod);

    const parity_lower = b.addTest(.{
        .name = "parity-lower",
        .root_module = parity_lower_mod,
    });
    const run_parity_lower = b.addRunArtifact(parity_lower);

    // -------------------------------------------------------------------
    // End-to-end compile parity vs bitcoinsx — measurement harness.
    // Vendors his compiler.test.ts cases + converts his ASM goldens to
    // hex; runs them through our pipeline; categorises each as PASS /
    // BLOCKED(feature) / FAIL. Coverage report printed at end.
    // -------------------------------------------------------------------
    const parity_compile_mod = b.createModule(.{
        .root_source_file = b.path("tests/parity_compile.zig"),
        .target = target,
        .optimize = optimize,
    });
    parity_compile_mod.addImport("sx", sx_mod);

    const parity_compile = b.addTest(.{
        .name = "parity-compile",
        .root_module = parity_compile_mod,
    });
    const run_parity_compile = b.addRunArtifact(parity_compile);

    // -------------------------------------------------------------------
    // Real-contract parity — drives bitcoinsx's actual src/sx/contracts/
    // sources through our pipeline. Hand-derived goldens for unambiguous
    // contracts, sanity-only for complex ones.
    // -------------------------------------------------------------------
    const parity_contracts_mod = b.createModule(.{
        .root_source_file = b.path("tests/parity_contracts.zig"),
        .target = target,
        .optimize = optimize,
    });
    parity_contracts_mod.addImport("sx", sx_mod);

    const parity_contracts = b.addTest(.{
        .name = "parity-contracts",
        .root_module = parity_contracts_mod,
    });
    const run_parity_contracts = b.addRunArtifact(parity_contracts);

    const test_step = b.step("test", "Run parity tests against bitcoinsx fixtures");
    test_step.dependOn(&run_parity_tokenise.step);
    test_step.dependOn(&run_parity_parse.step);
    test_step.dependOn(&run_parity_lower.step);
    test_step.dependOn(&run_parity_compile.step);
    test_step.dependOn(&run_parity_contracts.step);
}

```
