---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/test_fixture/brain/zig/registration.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.560926+00:00
---

# cartridges/test_fixture/brain/zig/registration.zig

```zig
// test_fixture cartridge — integration test for the C5 cartridge_seam.
//
// Reference: docs/design/BRAIN-EXTENSION-LOADER.md §6b (one-registerInto-
// per-cartridge convention) + §8 (test strategy — "a tiny cartridges/
// test_fixture/ with one no-op handler whose registerInto flags itself
// as called").
//
// ── What this module is ──────────────────────────────────────────────
//
// The smallest possible test of the C5 seam in production boot: a
// no-op registerInto that logs "test_fixture: registerInto called!"
// and increments an export-visible counter.  When cli/serve.zig boot
// hits cartridge_seam.dispatchRegistrations, this entry-point fires
// IF the operator has staged the test_fixture cartridge into
// <data_dir>/extensions/test_fixture/ + the cartridge_seam.registrations
// table has an entry pointing here.
//
// Production deployments don't ship this cartridge — it's loaded
// only when explicitly staged.  The brain binary INCLUDES the module
// (so the comptime registrations table can reference it) but the
// runtime cartridge.json gate (extension_manifest_loader.loadAll)
// determines whether it's actually dispatched.
//
// What this PR-4b-3 PROVES end-to-end:
//   1. cartridge.json with brain.handlers[{module:"registration"}] is
//      parsed correctly by extension_manifest_loader.zig
//   2. cartridge_seam.dispatchRegistrations finds the matching
//      registrations entry + calls registerInto
//   3. registerInto executes in the production boot path with the
//      real CartridgeDeps the brain assembles
//   4. The "Cartridge seam: dispatched N loaded manifest(s)" log line
//      in serve.zig accurately reflects the number invoked
//
// NEXT PR (PR-4b-3-attachments): same registration.zig pattern at
// cartridges/oddjobz/brain/zig/registration.zig — constructs real
// stores + registers a real handler.

const std = @import("std");
const dispatcher = @import("dispatcher");
const cartridge_seam = @import("cartridge_seam");

/// Test-visible counter — exported so integration tests can assert
/// the count went up by 1 after dispatchRegistrations runs.  Reset
/// per-test via direct write.  Production boot just logs the
/// invocation; the counter is unused in that path.
pub var register_calls: u32 = 0;

/// The cartridge-bootstrap entry-point per §6b convention.  Today
/// this cartridge has nothing real to register — it just records
/// the call + logs.  Real cartridges in this slot construct shared
/// stores + register handlers/walkers.
pub fn registerInto(
    disp: *dispatcher.Dispatcher,
    allocator: std.mem.Allocator,
    deps: *const cartridge_seam.CartridgeDeps,
) anyerror!void {
    _ = disp;
    _ = allocator;
    _ = deps;
    register_calls += 1;
    std.log.info("test_fixture: registerInto called! (calls = {d})", .{register_calls});
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — the registerInto contract is exercised by
// cartridge_seam.zig's existing test_fixture-shaped tests (those use
// a local-only registration list rather than the production
// registrations table).  Here we just smoke-check that registerInto
// is callable + increments the counter.
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "test_fixture.registerInto: increments counter + can be called" {
    register_calls = 0;
    try registerInto(undefined, testing.allocator, undefined);
    try testing.expectEqual(@as(u32, 1), register_calls);
    try registerInto(undefined, testing.allocator, undefined);
    try testing.expectEqual(@as(u32, 2), register_calls);
}

```
