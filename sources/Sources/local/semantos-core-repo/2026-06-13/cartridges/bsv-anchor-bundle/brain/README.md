---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/brain/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.441607+00:00
---

# `cartridges/bsv-anchor-bundle/brain/` — BSV anchor backend cartridge

A first-party substrate-exposing cartridge that implements the Phase 26C
`AnchorAdapter` interface using BSV as the underlying timestamping +
verification chain. Bundles wallet (BRC-42 derivation + signing),
payment policy (HTTP 402 challenge + ledger), refund tx construction,
and SPV header sync into one cartridge.

This is the substrate-exposing cartridge that the default Semantos node
install ships pre-loaded by default. With the bundle loaded, every other
cartridge's anchor needs are satisfied through it. Without the bundle,
brain runs in "anchor-unverified-mode" — cells get stub proofs, downstream
consumers see the unverified state, and a back-fill reconciliation pass
runs when the cartridge eventually loads.

## Status

**Scaffold only.** Real lift of brain-core wallet/headers/payment code into
this cartridge happens across DLBA.2 (wallet) + DLBA.3 (payment) +
DLBA.4 (headers) + DLBA.5 (fallback wiring + back-fill reconciliation)
per [`docs/prd/D-LIFT-BSV-ANCHOR.md`](../../docs/prd/D-LIFT-BSV-ANCHOR.md).
Today the cartridge declares its boundaries but contains no lifted code.

## What this cartridge will provide (once full lift lands)

- **AnchorAdapter implementation** — published per Phase 26C's
  `core/protocol-types/src/anchor.ts` interface.
- **Wallet protocol** — registered against the brain-core WSS substrate
  primitive (`runtime/semantos-brain/src/wss_subprotocol_registry.zig` —
  shipped by DLBA.1b) as subprotocol `wallet.v1`. Brain owns the transport;
  this cartridge owns the protocol.
- **Verbs** routed through `verb_dispatcher.zig` (registered at cartridge
  boot per the walker pattern from `extensions/oddjobz/`):
  - `anchor.write` — emit an anchor for a cell state hash
  - `anchor.read` — verify a previously-anchored proof
  - `wallet.sign` — sign a BSV transaction
  - `wallet.derive` — BRC-42 derivation under the operator's identity cert
  - `payment.verify` — verify a cited payment txid via PoW-verified header store
  - `payment.refund` — construct + broadcast a refund tx (per WSITE5.5)
  - `headers.sync` — sync BSV headers from a P2P peer (PoW-verified)
  - `headers.serve` — long-running BHS-compatible header server

## What this cartridge does NOT provide

- **Identity primitives** — substrate concern. Brain-core owns bearer
  tokens, identity certs, hats, device pairing, the DEK store. This
  cartridge consumes those via `IdentityAdapter` (Phase 26A/B).
- **Storage substrate** — brain-core's LMDB primitives + the four
  shipped `StorageAdapter` implementations stay substrate. This cartridge
  consumes `StorageAdapter` for output-store + derivation-state + header
  storage.
- **WSS transport** — brain-core owns `wss_codec`, `wss_frame_parser`,
  `wss_operator_auth`. This cartridge registers a subprotocol handler
  against the substrate registry.
- **Operator-site** — that's `D-Lift-wsite`, a separate carve. WSITE
  cartridge will consume this `bsv-anchor-bundle` for payment + refund
  flows once both lifts complete.

## Layout

```
cartridges/bsv-anchor-bundle/brain/
├── README.md                       (this file)
├── package.json                    (TypeScript package metadata)
├── manifest.json                   (Phase 36A ExtensionManifest — config.json shape)
├── tsconfig.json
├── release.config.ts               (release pipeline declaration)
├── src/                            (TypeScript side — AnchorAdapter delegation + capabilities)
│   ├── index.ts                    (entry point)
│   ├── manifest.ts                 (in-code manifest for capability-mint parity test)
│   └── capabilities.ts             (capability declarations + page-aligned domain-flag assignments)
└── zig/                            (Zig side — actual signing + headers + payment + refund code, lifted in DLBA.2/.3/.4)
    ├── build.zig
    ├── build.zig.zon
    └── src/                        (lifted source files arrive here)
```

## Build

```bash
# TypeScript half
cd cartridges/bsv-anchor-bundle/brain
bun install
bun run check
bun run build

# Zig half
cd cartridges/bsv-anchor-bundle/brain/zig
zig build
zig build test
```

Today both build steps succeed against the empty scaffold; real code
lands across DLBA.2/.3/.4.

## References

- [`docs/prd/D-LIFT-BSV-ANCHOR.md`](../../docs/prd/D-LIFT-BSV-ANCHOR.md) — the carve PRD
- [`docs/prd/PHASE-26C-ANCHOR-ADAPTER.md`](../../docs/prd/PHASE-26C-ANCHOR-ADAPTER.md) — the AnchorAdapter interface contract
- [`docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md`](../../docs/CARTRIDGE-DISTRO-GAP-ANALYSIS.md) — cartridge distro pattern + Phase 26 four-adapter overlay
- [`docs/SHELL-CARTRIDGES-HATS.md`](../../docs/SHELL-CARTRIDGES-HATS.md) §4 — the clean cartridge contract (five parts)
- [`extensions/oddjobz/`](../oddjobz/) — exemplar operational cartridge (template for the manifest + capabilities + walker-registration pattern)
