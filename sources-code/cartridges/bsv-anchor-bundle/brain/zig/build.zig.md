---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/zig/build.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.444952+00:00
---

# cartridges/bsv-anchor-bundle/brain/zig/build.zig

```zig
// BSV Anchor Bundle — Zig build entry.
//
// SCAFFOLD STATUS: empty target tree. The wallet/payment/refund/headers
// source files lift in via DLBA.2/.3/.4 per docs/prd/D-LIFT-BSV-ANCHOR.md.
// Today this build.zig defines only the test step; real targets (static lib
// for native consumers, wasm32-freestanding for cartridge release) arrive
// when the lifted source files land.
//
// Build:
//   zig build              # default = test (empty scaffold)
//   zig build test         # native unit tests
//
// Later (post-DLBA.2):
//   zig build              # native static lib
//   zig build wasm         # wasm32-freestanding artifact for cartridge release

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Unit tests — scaffold + per-module inline tests. The wider
    // headers_sync conformance tests live in
    // `runtime/semantos-brain/tests/` because they need brain's
    // `header_store` + `headers` modules; those are exercised via
    // brain's build.zig.
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_tests = b.addRunArtifact(tests);

    // D-LC5 — `reorg_sink.zig` is a leaf module (only depends on
    // `std`); its inline tests exercise the `StubReorgSink` shape so
    // the cartridge gets a standalone signal of the callback
    // interface's stability.
    const reorg_sink_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/reorg_sink.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_reorg_sink_tests = b.addRunArtifact(reorg_sink_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_reorg_sink_tests.step);
    b.default_step.dependOn(test_step);
}

```
