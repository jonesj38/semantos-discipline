---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.835129+00:00
---

# archive/apps-mud/src/room-actor.ts

```ts
/**
 * @deprecated The single-file `room-actor.ts` has been split into the
 * `room-actor/` sub-folder under prompt-23 of the monolith decomp.
 *
 * Public API is unchanged: `RoomActor` re-exports the facade. New
 * code should import from `./room-actor` (the barrel) or directly
 * from individual system modules
 * (`./room-actor/combat-system`, `./room-actor/inventory-system`,
 * `./room-actor/door-system`, `./room-actor/movement-system`,
 * `./room-actor/policy-engine`, `./room-actor/room-state-persister`).
 *
 * Per-system modules are independently unit-testable; the facade owns
 * lifecycle, atoms, and event fan-out only.
 */

export { RoomActor } from './room-actor/room-actor-facade';

```
