---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/29-cdm-lifecycle-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.775823+00:00
---

# 29 — Split `extensions/cdm/src/lifecycle.ts`

**Phase:** 9 (Game extensions) · **Depends on:** 01 · **Est. effort:** 0.5 day · **Branch:** `refactor/29-cdm-lifecycle`

## Why

523 LOC ISDA CDM lifecycle module: trade event handling, state transitions, event persistence, novation/termination flows.

## Deliverables

Create under `extensions/cdm/src/lifecycle/`:

- `event-reducer.ts` — pure `(tradeState, event) → tradeState`.
- `trade-events.ts` — `TradeEvent` union; per-event validators.
- `novation.ts`, `termination.ts`, `increase.ts`, `decrease.ts` — one file per flow.
- `persistence.ts` — effect atom subscribing to state changes.
- `lifecycle-facade.ts`.
- `__tests__/*.test.ts`.

Edit:

- `extensions/cdm/src/lifecycle.ts` → re-export facade.

## Acceptance criteria

- [ ] Reducer pure; all flow-specific logic independently tested.
- [ ] Golden CDM fixture (sample trade + 20 events) produces identical final state.
- [ ] `pnpm -r check` passes.

## Out of scope

- Changing the CDM event set or trade state model.

## Test plan

Replay `PHASE-28-ISDA-CDM.md` demo events; state sequence identical.
