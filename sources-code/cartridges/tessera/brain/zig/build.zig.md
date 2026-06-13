---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/zig/build.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.641021+00:00
---

# cartridges/tessera/brain/zig/build.zig

```zig
// Tessera cartridge — Zig build entry.
//
// V0.6 SCAFFOLD STATUS: empty target tree. Real walker bodies and
// FSM implementations arrive via the post-loader cohort:
//   V0.3 — Twelve walker bodies + verb_dispatcher.zig registration
//          with extensionId="tessera"
//   V0.5 — Nine cell-type schemas + octave registration +
//          StorageAdapter consumption wrappers (no direct LMDB)
//   V3   — NATS producer wiring per walker
//   V4   — Hardware peer integration (NFC tag bootstrap,
//          temp logger sync, tamper-loop, thermo flag)
//
// Build:
//   zig build              # default = test (V0.6 vacuous)
//   zig build test         # native unit tests
//
// Later (post-V0.3+):
//   zig build              # native static lib + WASM target per
//                            release.config.ts artifacts
//   zig build test         # full conformance suite for walkers
//                            (incl. K1 LINEAR/AFFINE/RELEVANT
//                            enforcement on tessera cell types)
//
// Greenfield discipline (TESSERA-CARTRIDGE.md §0.1): this tree is
// the entire surface tessera ever touches in Zig. No file under
// runtime/semantos-brain/src/ gains the literal string `tessera`;
// the no-tessera-in-brain-core CI gate enforces that on every PR.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Unit tests — scaffold only today. The walker bodies that arrive
    // via V0.3 + V0.5 add `test "..."` blocks under src/ and the test
    // runner picks them up automatically.
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
    b.default_step.dependOn(test_step);
}

```
