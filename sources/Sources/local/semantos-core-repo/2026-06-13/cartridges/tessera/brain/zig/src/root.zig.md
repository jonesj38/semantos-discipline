---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/zig/src/root.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.641480+00:00
---

# cartridges/tessera/brain/zig/src/root.zig

```zig
// Tessera cartridge — Zig root module.
//
// V0.6 SCAFFOLD STATUS: empty. The Zig surface arrives via:
//   V0.3 — Twelve walker bodies registered with verb_dispatcher.zig
//          (one per non-self-authorising tessera verb). Each is
//          (allocator, ctx, params_json) → result_json shape.
//          Lands under src/walkers/.
//   V0.5 — Nine cell-type schemas with linearity classes
//          (LINEAR / AFFINE / RELEVANT / DEBUG) registered into the
//          octave registry via the generic loader. Stores consume
//          StorageAdapter (NOT direct LMDB — §0.1 #2). Lands under
//          src/object_types/ + src/stores/.
//   V3.1 — `attachNatsProducer` wiring per walker for the seven
//          tessera event kinds (bottle_minted, care_event_recorded,
//          custody_transferred, tamper_broken, consumer_scanned,
//          case_assembled, shipment_closed). Lands under src/events/.
//   V4   — Hardware peer integration: NFC tag bootstrap via
//          IdentityAdapter, temp-logger sync handler, tamper-loop
//          event ingestion (K1 LINEAR enforcement), thermo sticker
//          manual flag. Lands under src/hardware/.
//
// Each post-loader V-row adds @import lines here and corresponding
// pub re-exports. The walker-registration entry point that the
// generic loader (DLO.1) calls at brain boot lands here as
// `pub fn registerTesseraWalkers(...)` in V0.3.
//
// See docs/prd/TESSERA-CARTRIDGE.md and
// docs/canon/commissions/wave-tessera.md for the wave manifest.

const std = @import("std");

/// Tessera cartridge version (matches package.json + manifest.json).
pub const VERSION = "0.0.1";

/// Canonical extension id under which tessera registers walkers via
/// `verb_dispatcher.zig` (V0.3) and cell types via the octave
/// registry (V0.5). Single source of truth; brain-core consumes this
/// string at boot time through the generic cartridge loader.
pub const EXTENSION_ID = "tessera";

test "scaffold builds" {
    try std.testing.expectEqualStrings("0.0.1", VERSION);
}

test "extension id matches manifest" {
    try std.testing.expectEqualStrings("tessera", EXTENSION_ID);
}

```
