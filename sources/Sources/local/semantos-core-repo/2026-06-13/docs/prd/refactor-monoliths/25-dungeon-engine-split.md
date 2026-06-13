---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/25-dungeon-engine-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.776330+00:00
---

# 25 — Split `extensions/games/src/dungeon/engine.ts`

**Phase:** 8 (MUD + games) · **Depends on:** 22 · **Est. effort:** 1 day · **Branch:** `refactor/25-dungeon-engine`

## Why

826 LOC roguelike with semantic cell entities, LINEAR/AFFINE/RELEVANT enforcement, floor generation, player state, combat, FOV (via rot.js), policy, board DAG, terminal event anchoring.

## Deliverables

Create under `extensions/games/src/dungeon/`:

- `action-dispatcher.ts` — registry for Move, Attack, Pickup, Use, OpenDoor, Descend.
- `combat-engine.ts` — attack resolution, damage calc, durability.
- `inventory-system.ts` — pickup/drop/use/equip. Reuse patterns from `apps/mud/room-actor/inventory-system.ts` (extract common helper to `game-sdk` if worthwhile).
- `movement-validator.ts` — uses `policyPort`.
- `floor-generator.ts` — pure `populateFloor(seed)`.
- `fov-system.ts` — `fovPort = port<FovProvider>('fov')`; default impl uses rot.js.
- `board-persister.ts` — effect atom; commits to CellStore.
- `terminal-event-emitter.ts` — anchors victory/death via `anchorPort`.
- `atoms.ts` — `boardStateAtom`, `boardHistoryAtom`, `consumedCellsAtom`.
- `dungeon-engine-facade.ts`.
- `__tests__/*.test.ts`.

Edit:

- `extensions/games/src/dungeon/engine.ts` → re-export facade.

## Acceptance criteria

- [ ] FOV provider injected via port (rot.js swappable).
- [ ] Terminal event list configurable (not hardcoded enum).
- [ ] All existing dungeon tests pass.
- [ ] `pnpm -r check` passes.

## Out of scope

- Changing dungeon mechanics.

## Test plan

Deterministic seed → replay 200-action run; board state and consumed cells identical.
