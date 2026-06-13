---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/build.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.478928+00:00
---

# cartridges/oddjobz/brain/zig/build.zig

```zig
// Oddjobz cartridge — Zig build entry.
//
// SCAFFOLD STATUS: empty target tree. The brain-core oddjobz code lifts
// in via DLO.3 (stores) + DLO.4 (handlers) + DLO.5 (REPL + intent_action_router)
// per docs/prd/D-LIFT-ODDJOBZ.md. Today this build.zig defines only the
// test step against an empty root module; real targets arrive when the
// lifted source files land.
//
// Build:
//   zig build              # default = test (empty scaffold)
//   zig build test         # native unit tests (empty today)
//
// Later (post-DLO.3+):
//   zig build              # native static lib
//   zig build test         # full conformance suite for lifted code

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Unit tests — scaffold only today. Lifted source files add their
    // conformance tests under src/ via the standard `test "..."` block.
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
