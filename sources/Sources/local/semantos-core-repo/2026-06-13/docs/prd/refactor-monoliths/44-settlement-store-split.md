---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/44-settlement-store-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.766325+00:00
---

# 44 — Split `apps/settlement/src/store.ts`

**Phase:** 12 (Session protocol + cell ops) · **Depends on:** 01 · **Est. effort:** 1 day · **Branch:** `refactor/44-settlement-store`

## Why

501 LOC store mixes node/edge CRDT-ish state, delta log, stability tracking, pruning, and query surface. High-leverage for the settlement app; easier to reason about once split by concern.

## Deliverables

Create under `apps/settlement/src/store/`:

- `node-index.ts` — `{ nodeId → NodeRecord }`; add/update/get; no side effects.
- `edge-index.ts` — `{ edgeId → EdgeRecord }`; forward and reverse adjacency.
- `delta-log.ts` — append-only log of applied deltas; pure ring-buffer or array with cursor.
- `stability.ts` — computes `stable | pending | rejected` state per node/edge from delta log.
- `pruner.ts` — removes stale/confirmed-stable entries beyond retention window.
- `query.ts` — read-only query functions over node/edge/delta.
- `settlement-store.ts` — atom-based facade (≤180 LOC) exposing the same public surface as today.
- `__tests__/*.test.ts`.

Edit:

- `apps/settlement/src/store.ts` → re-export facade.

## Acceptance criteria

- [ ] No file over 200 LOC.
- [ ] Each index has no knowledge of the others (cross-concern logic lives in `settlement-store.ts`).
- [ ] Existing settlement app tests pass.
- [ ] `pnpm --filter @semantos/settlement check` passes.

## Out of scope

- Changing settlement semantics or on-disk format (if any).

## Test plan

Replay a recorded delta fixture (≥1k deltas) → identical final node/edge state + identical stability output. Pruning unit tests with 5 retention-boundary scenarios.
