---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.307815+00:00
---

# @semantos/core

A polyglot monorepo for the Semantos semantic-object platform. The repository is organised into purpose-bound tiers — **core**, **runtime**, **packages/extensions**, **cartridges**, **apps**, and **archive** — with a mechanical import-boundary gate that enforces who is allowed to depend on whom.

For a current contributor-oriented map of the repo, start with [docs/ONBOARDING.md](docs/ONBOARDING.md). It reflects the active filesystem layout and calls out places where older docs still use pre-restructure paths.

## Quickstart

```bash
bun install
bun run check                      # type-check
bun run build                      # emit TS artifacts
bun run gate                       # phase0 gate (Zig + WASM + constants)
bun test tests/gates/import-boundaries.test.ts   # architectural import gate
```

### WASM kernel for browsers / art projects

If you just want the cell engine in a browser scene (Three.js, A-Frame, OffscreenCanvas, …), the embedded profile is 29 KB with host-provided crypto:

```js
import { REQUIRED_WASM_EXPORTS } from "@semantos/protocol-types/browser";

const { instance } = await WebAssembly.instantiateStreaming(
  fetch("./cell-engine-embedded.wasm"),
  { env: { /* host-provided sha256, ripemd160, secp256k1 */ } },
);

instance.exports.kernel_init();
instance.exports.kernel_load_script(scriptPtr, scriptLen);
instance.exports.kernel_execute();
```

Artifact lives at [core/cell-engine/zig-out/bin/cell-engine-embedded.wasm](core/cell-engine/zig-out/bin/cell-engine-embedded.wasm). The 13 required export names are listed in [core/protocol-types/src/wasm-contract.ts](core/protocol-types/src/wasm-contract.ts).

A worked Three.js demo is shipped at [apps/demo-wasm-threejs/](apps/demo-wasm-threejs/) with a paste-into-anywhere minimal loader (~80 lines, zero deps).

To build the WASM yourself:

```bash
cd core/cell-engine
zig build                          # full profile (185 KB, native crypto)
zig build -Dprofile=embedded       # embedded profile (29 KB, host crypto)
```

## Layout

```
core/         imports nothing outside core/
  cell-engine cell-ops semantos-ir semantos-sir
  protocol-types constants plexus-contracts plexus-vendor-sdk

runtime/      imports core/ + runtime/
  shell node services

packages/     imports core/ + runtime/ + packages/
  policy-runtime cdm extraction metering recovery scada
  navigation navigator dispatch content stores

cartridges/   domain bundles with manifests and optional brain/web packages
  oddjobz tessera scg bsv-anchor-bundle wallet-headers jambox chess

apps/         imports core/ + runtime/ + packages/, never another app
  loom-react loom loom-svelte demo-wasm-threejs
  games game-sdk mud piggybank poker-agent settlement
  navigation_app

archive/      not built, not imported (consciousness)

tests/gates/  cross-package gate tests
```

The boundary rules are enforced by a CI gate at [tests/gates/import-boundaries.test.ts](tests/gates/import-boundaries.test.ts) — see *Import-boundary gate* below.

### Core (sellable foundation)

| Package | Status | Purpose |
|---|---|---|
| [`cell-engine`](core/cell-engine/) | built | Zig/WASM 2-PDA kernel + TS bindings |
| [`cell-ops`](core/cell-ops/) | built | Type hash registry, cell packing, merkle envelopes, opcode enum |
| [`protocol-types`](core/protocol-types/) | built | Bridge types between TS and the WASM contract; central package (most importers) |
| [`constants`](core/constants/) | built | Codegen utility: `constants.json` → `constants.zig` + `constants.ts` |
| [`semantos-ir`](core/semantos-ir/) | built | OIR (opcode IR) in ANF; `lower()` and `emit()` |
| [`semantos-sir`](core/semantos-sir/) | built | SIR (semantic IR); `lowerSIR()` + `compileToSIR()` seam (Phase 3d) |
| [`plexus-contracts`](core/plexus-contracts/) | built | Plexus type definitions (local stand-in for Dusk Inc package) |
| [`plexus-vendor-sdk`](core/plexus-vendor-sdk/) | built | Plexus vendor SDK (local stand-in with real BRC-42 + SQLite) |

### Runtime (entry surfaces built on core)

| Package | Status | Purpose |
|---|---|---|
| [`shell`](runtime/shell/) | built | `semantos-shell` REPL + one-shot CLI + 30+ verbs |
| [`node`](runtime/node/) | built | Semantos node daemon, admin API, CLI |
| [`services`](runtime/services/) | built | `@semantos/runtime-services` — renderer-agnostic stores (LoomStore, FlowRunner, IdentityStore, ConfigStore, EmbeddingService, IntentTaxonomy, …) shared by every UI |
| [`session-protocol`](runtime/session-protocol/) | built | `@semantos/session-protocol` — domain-neutral multi-party session skeleton (Phase 35A). `SessionRuntime` + `MulticastAdapter` + `LoopbackAdapter` + `Signer` / `BCAProvider` seams. Consumed by any vertical that needs a state-machine-driven multi-party session (poker, voice, CDM lifecycle, SCADA events). |
| [`peer-locator`](runtime/peer-locator/) | built | `@semantos/peer-locator` — BCA → wss endpoint resolution for Phase 35B federation. `StaticPeerLocator` (map-backed) + `DnsPeerLocator` (`_semantos-node.<host>` TXT records with injectable resolver + TTL cache). 35B.3 will add a federated-registry locator on the same interface. |
| [`ws-node-adapter`](runtime/ws-node-adapter/) | built | `@semantos/ws-node-adapter` — `NetworkAdapter` over WSS with license-handshake envelope auth (Phase 35B.1). Node-to-node federation transport: dial + listen via Bun, CBOR envelope codec, per-peer state machine, `/.well-known/semantos-node` discovery endpoint. |

### Extensions (domain algorithms extending core)

| Package | Status | Purpose |
|---|---|---|
| [`policy-runtime`](extensions/policy-runtime/) | built | Routes extension grammar policies through the WASM 2-PDA kernel |
| [`cdm`](extensions/cdm/) | built | ISDA CDM lifecycle engine, regulatory reporting, FpML bridge |
| [`extraction`](extensions/extraction/) | built | Semantic extraction pipeline: fetch, parse, typecheck, infer, commit |
| [`metering`](extensions/metering/) | gate-only | 8-state payment-channel FSM, tick proofs, settlement |
| [`chain-broadcast`](extensions/chain-broadcast/) | built | `@semantos/chain-broadcast` — bulk on-chain anchoring (Phase 35A). `ChainBroadcaster` facade composing `CellTxBuilder` + `MapiBroadcaster` (ARC/MAPI injectable) + `ChainTipManager` + `BeefStore`. Reusable by any extension that needs to push cells to BSV at scale. |
| [`recovery`](extensions/recovery/) | gate-only | Recovery export payload + challenge-response protocol |
| [`scada`](extensions/scada/) | gate-only | SCADA industrial-control integration |
| [`navigator`](extensions/navigator/) | built | Core navigation layer (renders extension types via tower model) |
| [`navigation`](extensions/navigation/) | **deprecated** | Superseded by `navigator`; pending removal |

### Apps (standalone end-user products)

| Package | Status | Purpose |
|---|---|---|
| [`loom-react`](apps/loom-react/) | built | `@semantos/loom-react` — three-panel React workbench (Helm dock, voice input, host.exec lifecycle). Consumes `@semantos/runtime-services`. |
| [`loom`](apps/loom/) | shim | Deprecated `@semantos/loom` compat shim; re-exports from `@semantos/runtime-services`. Removable once consumers migrate. |
| [`loom-svelte`](apps/loom-svelte/) | built | Minimal Svelte UI proving the framework-quarantine boundary holds. |
| [`demo-wasm-threejs`](apps/demo-wasm-threejs/) | built | Three.js scene driven by cell-engine WASM; paste-into-anywhere loader. |
| [`games`](apps/games/) + [`game-sdk`](apps/game-sdk/) | built | Game engine and example games over the cell engine. *(Promotion to `extensions/` is on the cleanup backlog — they're libraries, not apps.)* |
| [`mud`](apps/mud/) | app | Multi-user dungeon over Semantos |
| [`piggybank`](apps/piggybank/) | app | BSV piggybank protocol with ESP32 firmware + Flutter app + web dashboard |
| [`poker-agent`](apps/poker-agent/) | app | Claude-powered poker agents with on-chain state anchoring |
| [`settlement`](apps/settlement/) | app | BSV settlement layer: border-router aggregation, CBOR, Merkle batching |
| [`navigation_app`](apps/navigation_app/) | app | Flutter navigation client |

### Archive

| Package | Status | Notes |
|---|---|---|
| [`consciousness`](archive/consciousness/) | archived | Consciousness-era experiment; not built, not imported |

### Cross-package gates

| Path | Purpose |
|---|---|
| [`tests/gates/`](tests/gates/) | Phase gate tests (constants/Zig/WASM, type hashes, Lean, TLA+, per-phase contracts) **plus** the import-boundary gate from Phase 3e |

## The pipeline

```
Surface grammar
   Lisp ✓        LaTeX ✗     Lean-ish ✗    Ricardian ✗   EDI ✗
        \         |              |              |          /
         \________|______________|______________|_________/
                              │
                              ▼
                  SIR  (semantic IR)            ← compileToSIR() wraps Lisp
                              │                  with neutral governance
                              ▼  lowerSIR()     ← seam wired Phase 3d;
                              │                  α-equivalent to direct lower()
                  OIR  (opcode IR, ANF)         ← live; golden-file tested
                              │
                              ▼  emit()
                              │
                  Opcode bytes (0x4C–0xD0)
                              │
                              ▼
                  Cell engine (Zig/WASM, 2-PDA)
```

Live components today:

- **Lisp surface** → [runtime/shell/src/lisp/parser.ts](runtime/shell/src/lisp/parser.ts), [runtime/shell/src/lisp/compiler.ts](runtime/shell/src/lisp/compiler.ts)
- **OIR + emit** → [core/semantos-ir/](core/semantos-ir/)
- **SIR seam** → [core/semantos-sir/src/compile-to-sir.ts](core/semantos-sir/src/compile-to-sir.ts) + [lower-sir.ts](core/semantos-sir/src/lower-sir.ts) (10-program α-equivalence corpus in [`__tests__/equivalence.test.ts`](core/semantos-sir/src/__tests__/equivalence.test.ts))
- **2-PDA execution** → [core/cell-engine/](core/cell-engine/) (Zig source under `src/`, WASM build under `zig-out/bin/`)
- **Lean lexicons** for jural / circuit / project-management / property-management / risk-assessment / bills-of-lading / CDM / control-systems vocabularies → [proofs/lean/Semantos/Lexicons/](proofs/lean/Semantos/Lexicons/) (with the substrate at [proofs/lean/Semantos/Substrate/](proofs/lean/Semantos/Substrate/) and legal-card semantics at [proofs/lean/Semantos/LegalCards/](proofs/lean/Semantos/LegalCards/))

Detailed walkthrough: [docs/PIPELINE.md](docs/PIPELINE.md). SIR seam design: [docs/PIPELINE-SIR-WIRING.md](docs/PIPELINE-SIR-WIRING.md).

## Cell engine (Zig/WASM)

A dual-stack pushdown automaton (2-PDA) executing Bitcoin Script with semantic extensions. Custom opcode range `0xC0–0xCF` adds VM-level type enforcement: `OP_CHECKLINEARTYPE`, `OP_ASSERTLINEAR`, `OP_PUSHCELLTYPEHASH`, etc.

| Profile | Size | Crypto | Use case |
|---|---|---|---|
| **Full** | ~185 KB | Native (SHA-256, RIPEMD-160, secp256k1) | Standalone, server, CLI |
| **Embedded** | ~29 KB | Host-provided via WASM imports | Browser apps with their own crypto |

Source under [core/cell-engine/src/](core/cell-engine/src/) (~4,900 LOC of Zig). 29 WASM exports cover kernel ops, debug helpers, cell packing, BCA validation, SPV verification, and capability checks. 9 host imports for crypto.

## Semantic object type system

Every stored object is one of three linear types:

| Type | Rule | Examples |
|---|---|---|
| **LINEAR** | Consumed exactly once | Capability UTXOs, payment-channel states |
| **AFFINE** | Consumed or discarded | Transfer records, proof-of-custody, identity |
| **RELEVANT** | Always valid, never consumed | Certificates, schema definitions |

Plus: functional domain flags (uint32 namespace), capability token types (6 variants), transfer records, recovery export payload structure, metering channel types. See [src/types/](src/types/).

Domain flags map to BRC-43 `protocolID` via `toProtocolId()` for `@bsv/sdk` interop. Well-known low byte:

```
0x01 EDGE_CREATION    0x06 CHILD_CREATION
0x02 SIGNING          0x07 PERMISSION_GRANT
0x03 ENCRYPTION       0x08 DATA_SOVEREIGNTY
0x04 MESSAGING        0x09 SCHEMA_SIGNING
0x05 ATTESTATION      0x0A METERING
0x0B HOST_EXEC        (Phase 38)
```

## Shell

`semantos-shell` is the typed CLI/REPL over the cell engine. Three modes: REPL (`semantos-shell`), one-shot CLI (`semantos-shell <verb> <args>`), watch (`StoreBridgeServer`, currently a stub).

Walkthrough and verb reference: [docs/SHELL.md](docs/SHELL.md), [docs/SHELL-VERBS.md](docs/SHELL-VERBS.md).

## Import-boundary gate

[tests/gates/import-boundaries.test.ts](tests/gates/import-boundaries.test.ts) mechanically enforces:

| Tier | May import from |
|---|---|
| `core/` | `core/` only |
| `runtime/` | `core/`, `runtime/` |
| `extensions/` | `core/`, `runtime/`, `extensions/` |
| `apps/` | `core/`, `runtime/`, `extensions/` — **never another app** |
| `archive/` | (not enforced) |

The gate walks every `.ts`/`.tsx` file under the four active tiers, extracts both workspace-spec (`@semantos/X`) and relative-path imports, maps each to a tier via the workspace package map, and reports any unauthorized crossing.

A documented `ALLOWLIST` captures known pre-existing violations with `TODO: ...` migration notes — each entry is a named architectural debt. Watch the allowlist shrink as refactors land.

```bash
bun test tests/gates/import-boundaries.test.ts
```

## What's NOT here (by design)

| Concern | Where it lives |
|---|---|
| Key derivation (BRC-42 / BKDS) | `@bsv/sdk` `KeyDeriver` |
| ECDH, ECDSA signing | `@bsv/sdk` `ProtoWallet` |
| BRC-100 wallet interface | `@bsv/sdk` + `wallet-toolbox` |
| BEEF/BUMP SPV validation (JS) | `@bsv/sdk` |
| Payment-channel protocol on the wire | `cashlanes` repo |

## Formal verification

- **Lean 4** kernel proofs for invariants K1 (linearity), K2 (auth), K3 (isolation), K4 (atomicity), K5 (termination), K7 (immutability) — under [proofs/lean/Semantos/Theorems/](proofs/lean/Semantos/Theorems/).
- **Lean 4 lexicons** for domain vocabularies (jural, circuit, project-management, property-management, risk-assessment, bills-of-lading, CDM, control-systems) at [proofs/lean/Semantos/Lexicons/](proofs/lean/Semantos/Lexicons/), with the formal substrate at [proofs/lean/Semantos/Substrate/](proofs/lean/Semantos/Substrate/) and legal-card semantics at [proofs/lean/Semantos/LegalCards/](proofs/lean/Semantos/LegalCards/).
- **TLA+** distributed-protocol models — 7 specs under [proofs/tla/](proofs/tla/) covering type-system safety, metering FSM, certificate revocation, and more.

## Documentation

- [docs/RESTRUCTURING-PLAN.md](docs/RESTRUCTURING-PLAN.md) — the strategy doc that drove Phases 1–3 of this layout
- [docs/PIPELINE.md](docs/PIPELINE.md) — NL → SIR → OIR → opcodes → cell engine
- [docs/PIPELINE-SIR-WIRING.md](docs/PIPELINE-SIR-WIRING.md) — SIR seam design (now wired in Phase 3d)
- [docs/SHELL.md](docs/SHELL.md), [docs/SHELL-VERBS.md](docs/SHELL-VERBS.md) — shell entry point + verb reference
- [docs/prd/](docs/prd/) — phase PRDs
- [docs/worktree-audit-2026-04.md](docs/worktree-audit-2026-04.md) — record of the 27 worktrees pruned at the start of the restructure
- [docs/recovered-orphans-2026-04.md](docs/recovered-orphans-2026-04.md) — catalog of 63 dangling commits preserved as `refs/recovery/<short-hash>`

## Setup

```bash
bun install
bun run check                      # type-check
bun run build                      # emit dist/
bun run generate-constants         # regenerate constants.zig + constants.ts from JSON
bun run gate                       # phase0 gate
bun test tests/gates/import-boundaries.test.ts   # architectural gate
```

Peer dependency: `@bsv/sdk ^2.0.0`. Target runtime: **Bun**.
