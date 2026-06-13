---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/refactor-monoliths/23-room-actor-split.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.767588+00:00
---

# 23 — Split `apps/mud/src/room-actor.ts`

**Phase:** 8 (MUD + games) · **Depends on:** 22 · **Est. effort:** 1 day · **Branch:** `refactor/23-room-actor`

## Why

791 LOC single-threaded state owner for one MUD room: action queue, combat, inventory, doors/locks, movement, FOV-based look, policy evaluation, CellStore persistence, event emitter.

## Deliverables

Create under `apps/mud/src/room-actor/`:

- `action-processor.ts` — registry-based dispatcher replacing the big switch.
- `combat-system.ts` — `resolveCombatWithMonster`, `resolvePvP`, damage calc.
- `inventory-system.ts` — pickup, drop, use, equip, durability.
- `door-system.ts` — open/lock/key consumption.
- `movement-system.ts` — `handleMove`, treasure auto-pickup, position update.
- `policy-engine.ts` — thin kernel adapter via `policyPort`.
- `room-state-persister.ts` — batched CellStore writes via effect atom.
- `atoms.ts` — `roomStateAtom`, `playersAtom`, `consumedCellsAtom`.
- `room-actor-facade.ts` — orchestrator using the game-sdk engine base.
- `__tests__/*.test.ts`.

Edit:

- `apps/mud/src/room-actor.ts` → re-export facade.

## Acceptance criteria

- [ ] No file over 220 LOC.
- [ ] Every action handler independently unit-testable.
- [ ] Policy checks in one place (no sprinkled validation).
- [ ] Persistence is non-blocking (effect atom, batched).
- [ ] All existing MUD tests pass.
- [ ] `pnpm -r check` passes.

## Out of scope

- Changing MUD rules or combat math.

## Test plan

Replay a 100-action fixture; room state after every 10th action must match golden snapshot.
