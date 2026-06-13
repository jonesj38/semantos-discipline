---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/mnca/brain/zig/registration.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.682188+00:00
---

# cartridges/mnca/brain/zig/registration.zig

```zig
// mnca cartridge brain registration — C4 PR-E2 cartridge_seam entry-point.
//
// Reference: docs/design/BRAIN-EXTENSION-LOADER.md §3 (registerInto
//            contract) + §6b (one-registerInto-per-cartridge convention).
//
// ── What this module is ──────────────────────────────────────────────
//
// The cartridge-bootstrap entry-point for the mnca cartridge. Called once
// at brain boot by cartridge_seam.dispatchRegistrations when
// cartridges/mnca/cartridge.json declares
// `brain.handlers: [{ "module": "registration" }]`.
//
// Unlike oddjobz (which registers dispatcher RESOURCES), mnca contributes a
// mint-context BUILDER: it constructs the MNCA-anchor-transition
// ScriptContextBuilder (cells_mint_mnca_context, moved out of the brain in
// PR-E2) and appends it to the substrate mint Handler's MintContextRegistry
// via deps.mint_context_registry. The brain's generic mint Handler then
// resolves the execution Context for `mnca.anchor.transition.intent` mints
// without serve.zig (or the Handler) naming MNCA.

const std = @import("std");
const dispatcher = @import("dispatcher");
const cartridge_seam = @import("cartridge_seam");
const cells_mint_mnca_context = @import("cells_mint_mnca_context");

/// Cartridge-bootstrap registerInto per §3 contract.
pub fn registerInto(
    disp: *dispatcher.Dispatcher,
    allocator: std.mem.Allocator,
    deps: *const cartridge_seam.CartridgeDeps,
) anyerror!void {
    // MNCA contributes a mint-context builder, not a dispatcher resource.
    _ = disp;

    // The mint Handler (and thus its registry) is only up on a site that
    // wired the cells-mint surface. Static-only sites leave
    // mint_context_registry null — skip cleanly (mnca.anchor.transition.intent
    // mints aren't served there anyway).
    const registry = deps.mint_context_registry orelse {
        std.log.info(
            "mnca.registerInto: no mint_context_registry (mint Handler not up) — MNCA builder not registered",
            .{},
        );
        return;
    };

    // Heap-allocate the builder State — the registry holds a pointer to it
    // (via ScriptContextBuilder.state) for the brain's lifetime. cell_store
    // comes from the substrate DI bag; `policy` defaults to the v1
    // mainnet-proven PushDrop shape. Intentional brain-lifetime leak (matches
    // the oddjobz registration posture per §3 #4 — registerInto errors halt
    // boot; cartridges are trusted code).
    const state = try allocator.create(cells_mint_mnca_context.State);
    errdefer allocator.destroy(state);
    state.* = .{ .cell_store = deps.cell_store };

    registry.add(cells_mint_mnca_context.toBuilder(state));

    std.log.info(
        "mnca.registerInto: MNCA-anchor-transition mint-context builder registered ({d} builder(s) in registry)",
        .{registry.count()},
    );
}

// ─────────────────────────────────────────────────────────────────────
// Inline test — module importability under `zig build test`. The
// registerInto behaviour (null-registry skip + builder append) is
// exercised by the brain boot integration; the MNCA build/verify logic
// is covered by cells_mint_mnca_context's own inline tests.
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "mnca registration module imports + registerInto is referenceable" {
    try testing.expect(@TypeOf(registerInto) == fn (
        *dispatcher.Dispatcher,
        std.mem.Allocator,
        *const cartridge_seam.CartridgeDeps,
    ) anyerror!void);
}

```
