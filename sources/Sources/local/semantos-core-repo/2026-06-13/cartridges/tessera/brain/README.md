---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.633449+00:00
---

# Tessera

Care-chain provenance cartridge. Grape-to-glass-shaped traceability over physically handed-off objects whose value depends on a verifiable care chain — wine, premium coffee, cold-chain pharma, art transit, and any future vertical where the value of a delivered object depends on its handling history.

## Status

**V0.2 scaffold** (pre-loader cohort) — cartridge skeleton only. The Phase 36A `ExtensionManifest` declares the surface; walker dispatch, octave registration, hat surfaces, and federation are deferred to later V-rows.

See [`docs/prd/TESSERA-CARTRIDGE.md`](../../docs/prd/TESSERA-CARTRIDGE.md) for the full plan and [`docs/canon/commissions/wave-tessera.md`](../../docs/canon/commissions/wave-tessera.md) for the wave manifest.

## Shape

Tessera is a substrate-consuming cartridge — it consumes the four Phase-26 adapter interfaces from `core/protocol-types/`:

| Interface           | Use                                                                |
|---------------------|--------------------------------------------------------------------|
| `StorageAdapter`    | Bottle / case / pallet / shipment / care-event cell stores         |
| `IdentityAdapter`   | BCA derivation + BRC-52 cert binding on every patch                |
| `AnchorAdapter`     | SPV-verifiable cell anchoring (consumer scan budget < 100 ms)      |
| `NetworkAdapter`    | Cross-operator `SignedBundle<TesseraPatch>` federation             |

Tessera consumes **only** these four interfaces. It does NOT import LMDB primitives, `@bsv/sdk`, `wallet-toolbox`, or any path under `runtime/semantos-brain/src/` directly. The CI gate [`tests/gates/tessera-adapter-consumption.test.ts`](../../tests/gates/tessera-adapter-consumption.test.ts) (lands in V0.5) enforces this; the CI gate [`tests/gates/no-tessera-in-brain-core.test.ts`](../../tests/gates/no-tessera-in-brain-core.test.ts) (landed in V0.1) enforces the greenfield-discipline complement that no tessera identifier ever appears in brain-core.

## Cartridge contract

Per [`docs/SHELL-CARTRIDGES-HATS.md`](../../docs/SHELL-CARTRIDGES-HATS.md) §4, tessera implements the five-part cartridge contract:

1. **Grammar** — Phase 36A `ExtensionManifest` at [`manifest.json`](manifest.json) (and typed companion at [`src/manifest.ts`](src/manifest.ts)). Declares the 13 verbs and the four substrate adapter interfaces consumed.
2. **Walkers** — twelve walkers under [`src/walkers/`](src/walkers) (V0.3, post-loader cohort) register with `verb_dispatcher.zig` at brain boot with `extensionId="tessera"`.
3. **Cell types** — nine cell types under [`src/object-types/`](src/object-types) (V0.5, post-loader cohort) declare linearity classes (LINEAR / AFFINE / RELEVANT / DEBUG).
4. **Lexicon re-export** — [`src/lexicon.ts`](src/lexicon.ts) (V0.4) re-exports from `core/semantos-sir/src/lexicons.ts` `ALL_LEXICONS`.
5. **Release config** — [`release.config.ts`](release.config.ts) declares the dual-artifact build for the repo-wide release pipeline.

## Hats

One cartridge, seven hats over one brain (per [`docs/prd/TESSERA-CARTRIDGE.md`](../../docs/prd/TESSERA-CARTRIDGE.md) §4):

| Hat                       | Domain sub-page | Notes                                            |
|---------------------------|-----------------|--------------------------------------------------|
| `tessera.producer`        | `0x00010401`    | Vineyard map, blending bench, bottling line      |
| `tessera.field-worker`    | `0x0001041A`    | Offline-first in-vineyard harvest entry          |
| `tessera.distributor`     | `0x00010402`    | Receiving dock, custody log, outbound dispatch   |
| `tessera.dock-handler`    | `0x0001042A`    | Single-screen scan-and-confirm                   |
| `tessera.retailer`        | `0x00010403`    | Inventory verification, wine-list export         |
| `tessera.club-member`     | `0x00010404`    | Allocation queue, cellar, Care Score timeline    |
| `tessera.consumer`        | `0x00010405`    | Anonymous NFC-tap PWA (no install, no login)     |

Sub-pages `0x1A` / `0x2A` are the canonical "a"-suffix hat byte allocation for the mobile/single-purpose hats that operate alongside their primary hat (field-worker alongside producer; dock-handler alongside distributor).

## Install / uninstall

```sh
# Once DLO.1 (generic cartridge loader) lands in main:
semantos vertical install tessera
semantos vertical uninstall tessera
```

Tessera is **not** in the default install bundle (per `D-Distro-default-install`) — the default bundle is reserved for substrate-exposing cartridges. Tessera is a domain cartridge; deployments elect it explicitly.

## Build

```sh
cd cartridges/tessera/brain && bun run build
cd cartridges/tessera/brain/zig && zig build       # V0.6 — pre-loader cohort
```

## Tests

```sh
bun test cartridges/tessera/brain/                  # cartridge-side tests
bun test tests/gates/no-tessera-in-brain-core # greenfield CI gate (V0.1)
bun test tests/gates/tessera-adapter-consumption # adapter discipline CI gate (V0.5)
```
