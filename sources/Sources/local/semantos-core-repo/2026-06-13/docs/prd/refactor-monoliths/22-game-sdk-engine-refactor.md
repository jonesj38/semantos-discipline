---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/22-game-sdk-engine-refactor.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.777082+00:00
---

# 22 — Refactor `extensions/game-sdk/src/engine.ts`

**Phase:** 8 (MUD + games) · **Depends on:** 01 · **Est. effort:** 1 day · **Branch:** `refactor/22-game-sdk-engine`

## Why

679 LOC shared base engine for dungeon, risk, chess, go, poker. All five game extensions inherit — refactor the base first so the downstream engines benefit.

## Deliverables

Create under `extensions/game-sdk/src/engine/`:

- `reducer-base.ts` — generic `<S, A>(reducer, initial) → EngineSlice<S, A>` with pure state transitions.
- `action-dispatcher.ts` — `Registry<ActionHandler>` pattern.
- `policy-hook.ts` — `policyPort = port<PolicyEvaluator>('policy')`; pre-action gate.
- `persistence-hook.ts` — `cellStorePort = port<CellStoreFacade>('cell-store')`; subscribes to state changes.
- `event-emitter.ts` — `gameEventBus<E>()` shared factory.
- `engine-facade.ts` — orchestrator combining the above.
- `__tests__/*.test.ts`.

Edit:

- `extensions/game-sdk/src/engine.ts` → re-export facade + template helpers.

## Acceptance criteria

- [ ] Base engine file ≤ 250 LOC.
- [ ] All five downstream engines still compile unchanged (even before they migrate to the new shape).
- [ ] `pnpm -r check` passes.
- [ ] At least one extension (pick the smallest — probably `go`) spot-migrated as a sanity check and reverted in a follow-up PR.

## Out of scope

- Migrating dungeon/room-actor/chess to the new shape (their own prompts).

## Test plan

Contract test: run existing game-sdk test suite; all pass. Plus: construct a toy engine using the new base + test-double ports; verify reducer + policy + persist + event emit all fire in the expected order.
