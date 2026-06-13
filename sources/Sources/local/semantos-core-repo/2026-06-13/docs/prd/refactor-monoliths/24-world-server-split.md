---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/24-world-server-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.774316+00:00
---

# 24 — Split `apps/mud/src/world-server.ts`

**Phase:** 8 (MUD + games) · **Depends on:** 23 · **Est. effort:** 0.5 day · **Branch:** `refactor/24-world-server`

## Why

633 LOC supervisor for room actor pool + player session binding: world generation, player sessions, cross-room transfer, event subscription.

## Deliverables

Create under `apps/mud/src/world-server/`:

- `world-generator.ts` — pure topology + monster/item placement; accepts seed.
- `player-session-manager.ts` — join, create player entity, session lifecycle.
- `room-pool-manager.ts` — room actor lifecycle; atom-backed pool.
- `player-transfer.ts` — cross-room movement coordinator.
- `world-persistence.ts` — config/topology/session persistence.
- `item-pool-helper.ts` — floor-based item selection.
- `world-server-facade.ts` — orchestrator.
- `__tests__/*.test.ts`.

Edit:

- `apps/mud/src/world-server.ts` → re-export facade.

## Acceptance criteria

- [ ] Session ID derived from max existing ID on load (not in-memory counter).
- [ ] Storage creation accepted as a parameter (testable without filesystem).
- [ ] All existing tests pass.
- [ ] `pnpm -r check` passes.

## Out of scope

- Changing the generated world's seed or distribution.

## Test plan

Fixture seed → identical world layout pre- and post-refactor.
