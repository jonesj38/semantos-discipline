---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/src/root.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.547928+00:00
---

# cartridges/oddjobz/brain/zig/src/root.zig

```zig
// Oddjobz cartridge — Zig root module.
//
// SCAFFOLD STATUS: empty. Lifted source files arrive via:
//   DLO.3 — Per-store StorageAdapter migration (jobs first, then
//           quotes/invoices/customers/leads/visits)
//   DLO.4 — Resource handlers + walker registration via verb_dispatcher
//   DLO.5 — REPL contributions + intent_action_router lift
//   DLO.6 — Brain-core no-oddjobz audit (grep returns zero)
//
// Each lift adds @import lines here and corresponding pub re-exports.
//
// See docs/prd/D-LIFT-ODDJOBZ.md for the full carve plan.

const std = @import("std");

pub const VERSION = "0.1.0";

test "scaffold builds" {
    try std.testing.expectEqualStrings("0.1.0", VERSION);
}

```
