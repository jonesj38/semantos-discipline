---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/zig/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.564721+00:00
---

# cartridges/self/brain/zig — Zig-side brain code for the self cartridge

**Track**: C4 (Brain Cartridge Extraction). First move 2026-05-28.

This directory is the home for self-cartridge-specific Zig code that will be loaded into the canonical brain via the C5 extension-loader seam.

## Current state (C4 first move)

**Empty by design.** This README locks the slot; code lands in subsequent ticks per the extraction plan below.

What's NOT here yet:

| File (future location) | Currently lives at | Status |
|---|---|---|
| `release_handler.zig` (write path) | — | Not needed — the existing `runtime/semantos-brain/src/cells_mint_handler.zig` is a GENERIC write path that serves all cartridges. See "C7 slice write path" below. |
| `self_sweep_http.zig` (read path) | `runtime/semantos-brain/src/self_sweep_http.zig` | EXTRACTION CANDIDATE — currently lives in brain core; should move here. Pending C5 extension-loader contract + zig build integration. |
| `self_cell_specs.zig` (cell-type registry) | `cartridges/self/brain/self_cell_specs.zig` (one dir up) | Already cartridge-owned, just not under `zig/`. Move during the same C5-coordinated extraction. |

## C7 slice write path — already supported by brain core

The C7 golden slice (`do | self | release` mints a `self.practice.release` cell) does NOT require a self-specific write handler. The brain's generic mint handler already serves this:

```
POST /api/v1/repl
Authorization: Bearer <token>

{ "cmd": "cells mint",
  "args": { "typeHashHex": "<sha256('self.practice.release')[..32]>",
            "payload": {"rawText": "I'm letting go..."} } }

→ { "ok": true,
    "cellId": "<64hex>",
    "cartridgeId": "self",
    "cellType": "self.practice.release",
    "persistedAt": <unix-ms> }
```

Per `runtime/semantos-brain/src/cells_mint_handler.zig`:
- Validates the request body shape (cells_mint_http.parseRequestBody)
- Resolves typeHash → cartridge + cellType via cartridge_cell_registry
- Encodes the canonical 256-byte cell header via substrate_entity.encodeFromTypeHash
- Persists to LMDB via cell_store.put
- Publishes `cells.self.minted` to helm_event_broker

This means the C7 V1 slice's layer 7 (brain dispatch) is **closer to ready than the bespoke `do.new` shape in the v1_release.fixture.json suggests**. The fixture needs a follow-up update to reference `cells mint` instead of `do.new`. That's a C0 doc-tick (separate from C4 code work).

## C4 extraction plan (future ticks)

**Why extract self_sweep_http.zig and self_cell_specs.zig at all?** Per the canonicalization brief §3 + the matrix C4 cell:

> Move all cartridge-specific `.zig` files (currently statically compiled into the brain binary) out of `runtime/semantos-brain/src/` and into `cartridges/<name>/brain/zig/` so the brain itself is cartridge-agnostic.

For self specifically:
- `self_sweep_http.zig` is the GET `/api/v1/self/sweep` endpoint — runs `cartridges/self/brain/src/sweep_runner.ts` as a Bun subprocess to compute pask reductions over the operator's self.practice.* cells. Cartridge-specific; should live with the cartridge.
- `self_cell_specs.zig` is the Zig comptime mirror of `cartridges/self/cartridge.json`'s `cellTypes[]` — purely declarative. Move freely.

**Tick sequence (after C5 extension-loader lands):**

1. C5 defines the contract: `pub fn registerInto(disp: *Dispatcher) void` (and analogous for HTTP routes).
2. C4 tick 2: `git mv` `runtime/semantos-brain/src/self_sweep_http.zig` → `cartridges/self/brain/zig/sweep_http.zig`. Update its module name + add `registerInto` wrapper. Update `runtime/semantos-brain/build.zig` to include cartridge zig files via the extension-loader manifest. Update `runtime/semantos-brain/src/cli/serve.zig` to call `cartridges/self/brain/zig/sweep_http.zig`'s `registerInto` instead of the hardcoded route registration.
3. C4 tick 3: same pattern for any other self-specific files.

**Blocker for tick 2**: zig build integration — there's no existing pattern for compiling cartridge-side .zig modules into the brain binary. C5 has to invent this (referenced as `D-CANON-C5-A` in the matrix).

## Status vs C7 slice

Layer 7 (brain dispatch):
- **For the slice's write path**: already supported by `cells_mint_handler.zig` in brain core. No C4 code work blocks this — only a slice-fixture clarification (C0 doc-tick) and PWA-side wiring (C1 _BootstrapApp tick).
- **For the slice's read path (V2+ when querying back the minted cell)**: served by `self_sweep_http.zig` OR a generic cell-inspect handler. Either way, no C4 work strictly required for V1.

Updates D-CANON-C4-A: ✗ → ⚠ (cartridge zig/ slot now documented + plan locked; actual extraction pending C5 extension-loader contract).
