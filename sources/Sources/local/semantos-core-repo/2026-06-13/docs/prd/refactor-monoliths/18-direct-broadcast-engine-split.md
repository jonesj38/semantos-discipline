---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/18-direct-broadcast-engine-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.776579+00:00
---

# 18 — Split `apps/poker-agent/src/direct-broadcast-engine.ts`

**Phase:** 7 (Poker stack) · **Depends on:** 14, 16 · **Est. effort:** 1 day · **Branch:** `refactor/18-direct-broadcast-engine`

## Why

782 LOC: local keypair management, UTXO pre-splitting, stream-based partition, CellToken tx building + signing, ARC broadcast with fire-and-forget, stats tracking. Today `ARC` is instantiated inline with URL+apiKey constructor.

## Deliverables

Create under `apps/poker-agent/src/direct-broadcast/`:

- `local-keypair-manager.ts` — WIF storage, address derivation, key lifecycle. Atom: `localKeyAtom`.
- `utxo-pool-manager.ts` — pre-split, stream partition, consume/return. Atom: `utxoPoolsAtom = atom<Map<number, FundingUtxo[]>>`.
- `celltoken-tx-builder.ts` — pure: `createCellToken`, `transitionCellToken`. Uses `shared/beef-codec.ts`.
- `arc-broadcaster.ts` — implements `broadcasterPort` for ARC. `new ARC(...)` moves here.
- `tx-stats-collector.ts` — event-bus driven: emits `BroadcastEvent` regardless of mode; stats atom aggregates.
- `direct-broadcast-engine.ts` — facade orchestrating the modules.
- `__tests__/*.test.ts`.

Edit:

- `apps/poker-agent/src/direct-broadcast-engine.ts` → re-export facade.

## Acceptance criteria

- [ ] `new ARC` appears exactly once in `arc-broadcaster.ts`.
- [ ] Fire-and-forget and awaited modes both emit `BroadcastEvent` with timing.
- [ ] Stats via atom selector, not mutable class fields.
- [ ] All existing tests pass.
- [ ] `pnpm -r check` passes.

## Out of scope

- Changing broadcast throughput characteristics.
- Swapping ARC for another broadcaster.

## Test plan

Stub `broadcasterPort` with a recorder; run 100 broadcasts; compare ordering and frequency vs. pre-refactor recording.
