---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/ONBOARDING.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.326514+00:00
---

# Semantos Core Onboarding

This is the practical orientation for a fresh contributor opening the repo today. It is intentionally grounded in the current filesystem, not only the aspirational architecture.

## What this repository is

`semantos-core` is a polyglot monorepo for the Semantos semantic-object platform. The core loop is:

```text
surface intent / policy
  -> SIR (semantic IR: authority, proof, governance, lexicon meaning)
  -> OIR (opcode IR in ANF)
  -> opcode bytes
  -> Zig/WASM cell engine
```

The implementation is a mix of:

- TypeScript packages for protocols, IRs, shell/runtime services, cartridges, tests, and app glue.
- Zig packages for the cell engine, node/runtime substrate, cartridge brain handlers, and embedded/server surfaces.
- Lean and TLA+ proofs/specifications for protocol invariants.
- Flutter/Vite/browser apps and demos.

## Quickstart

```bash
pnpm install
bun run check
bun run build
bun run gate
bun test tests/gates/import-boundaries.test.ts
```

Optional/native checks require extra toolchains:

```bash
# Zig/WASM kernel
cd core/cell-engine
zig build test
zig build -Doptimize=ReleaseSmall
zig build -Doptimize=ReleaseSmall -Dembedded=true

# Lean proofs
cd proofs/lean
lake build

# TLA+ models
cd proofs/tla
make setup
make check
```

If `zig` is not installed, the root Phase 0 gate skips the local Zig scaffold check. CI installs Zig and runs the native checks.

## Current active layout

| Path | Role | Notes |
|---|---|---|
| `core/` | Foundation/substrate packages | Cell engine, protocol types, constants, IR/SIR, semantic object types, state, lexicons, identity ports. Core should not depend on runtime/apps/cartridges. |
| `runtime/` | Headless runtime surfaces | Shell, node daemon, runtime services, intent pipeline, session/federation adapters, legacy ingest, verifier/brain runtimes. |
| `packages/` | Extension/domain libraries | CDM, extraction, metering, navigator, chain broadcast, content stores, dispatch, games, recovery, SCADA, etc. Some older docs call these `extensions/`. |
| `cartridges/` | Domain cartridges | Manifested verticals such as Oddjobz, Tessera, SCG, BSV anchor bundle, wallet headers, Jambox, chess. Often split into `brain/` and `web/`. |
| `apps/` | End-user apps/shells | Flutter/Vite/mobile/demo apps. App fixtures should not become runtime dependencies. |
| `proofs/` | Formal methods | Lean lexicons/theorems and TLA+ models. |
| `tests/gates/` | Architecture and phase gates | Mechanical checks for boundaries, constants, protocol phases, intent pipeline, etc. |
| `docs/` | Design/current docs | Prefer docs here over old archive notes for onboarding. |
| `archive/` | Historical experiments | Not built or imported by the active architecture. |
| `worktrees/` | Local developer worktrees | Should be treated as local-only scratch/checkouts, not part of onboarding or CI. |

## Important packages

### Core substrate

- `core/cell-engine` — Zig/WASM cell-graph kernel and 2-PDA executor.
- `core/constants` — source constants and generator for TS/Zig outputs.
- `core/protocol-types` — central TS protocol bridge/barrel for cell headers, routing, BSV/SPV formats, WASM contracts, etc.
- `core/cell-ops` — TS helpers for cell packing, hashes, envelopes, opcodes, vectors.
- `core/semantos-ir` — OIR and opcode emission.
- `core/semantos-sir` — semantic IR, authority checks, lexicons, and SIR -> OIR lowering.
- `core/semantic-objects`, `core/state`, `core/lexicon-core`, `core/identity-ports` — shared semantic/state/identity primitives.

### Runtime surfaces

- `runtime/shell` — `semantos-shell` CLI/REPL and one-shot command router.
- `runtime/services` — renderer-agnostic stores, verb registry, host-exec registry.
- `runtime/intent` — intent reducer/pipeline, federation, taxonomy, handoff policy.
- `runtime/node` — node daemon/admin API/native Zig runtime pieces.
- `runtime/session-protocol`, `runtime/peer-locator`, `runtime/ws-node-adapter` — multi-party session and WSS/federation seams.
- `runtime/semantos-brain` — large Zig brain/server runtime; active but still under-documented relative to its size.

### Dogfood verticals

- `cartridges/oddjobz/brain` — job/quote/visit/invoice FSMs, LMDB stores, conversation/intake logic.
- `cartridges/bsv-anchor-bundle/brain` — BSV header/payment/anchor support.
- `cartridges/tessera/brain`, `cartridges/scg/brain` — additional vertical cartridges.
- `apps/oddjobz-mobile`, `apps/oddjobtodd`, `apps/semantos` — user-facing/mobile/demo surfaces.

## Architectural boundaries

The intended dependency direction is:

```text
core -> core only
runtime -> core + runtime
packages/extensions -> core + runtime + packages/extensions
apps -> core + runtime + packages/extensions, never sibling apps
archive -> ignored
```

The gate is `tests/gates/import-boundaries.test.ts`.

A few tests/scripts use cross-tier fixtures to validate integration behavior. These must be explicitly documented in that gate rather than silently growing production dependencies.

## Local artifacts and secrets

Do not commit local operational state. In particular:

- `.env`, `.env.*` except checked-in examples
- `.bridge-wallet-key`
- `*.sqlite`, `*.sqlite-*`, `*.db`, `*.db-*`
- `.dogfood-logs/`
- `.cowork-backups/`
- `worktrees/`

If you need sample configuration, add `*.example` files with fake values.

## Before sharing the repo

Run at least:

```bash
git status --short
bun run gate
bun test tests/gates/import-boundaries.test.ts
bun run check
```

Then, if toolchains are available:

```bash
cd core/cell-engine && zig build test
cd proofs/lean && lake build
cd proofs/tla && make check
```

## Known rough edges

- Some older docs still use pre-restructure paths such as `packages/shell` for what is now `runtime/shell`, or `packages/semantos-ir` for `core/semantos-ir`.
- `packages/` currently contains many extension-like packages; older docs may call this tier `extensions/`.
- `runtime/semantos-brain` is substantial and deserves a focused architecture doc.
- Nested local `worktrees/` can confuse broad file searches and test runs if tools do not exclude them.
