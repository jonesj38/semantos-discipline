---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.405665+00:00
---

# packages/games/src/dungeon/engine.ts

```ts
/**
 * @deprecated — use the split modules under
 * `packages/games/src/dungeon/` instead. This file is now a thin
 * re-export shim of `dungeon-engine-facade.ts`.
 *
 * Prompt 25 split this 826-LOC monolith into:
 *
 *   action-dispatcher.ts      — Move/Attack/Pickup/Use/OpenDoor/Descend
 *   combat-engine.ts          — resolveCombat + applyXpAndLevelUp
 *   inventory-system.ts       — pickup/use/openDoor mutations
 *   movement-validator.ts     — central WASM policy gate + audit
 *   floor-generator.ts        — populateFloor (cell allocation)
 *   fov-system.ts             — fovPort + passableForFloor
 *   default-bindings.ts       — rot.js FOV factory
 *   board-persister.ts        — DAG-chained board commits
 *   terminal-event-emitter.ts — anchor on dead/victory
 *   atoms.ts                  — board / history / consumed atoms
 *   dungeon-engine-facade.ts  — public class — wires everything
 *
 * Existing imports of `DungeonEngine` continue to resolve via this
 * re-export. New code should import from `./dungeon-engine-facade`
 * directly (or via the package barrel `packages/games/src/index.ts`).
 */

export { DungeonEngine } from './dungeon-engine-facade';
export type { DungeonEngineCreateOptions } from './dungeon-engine-facade';

```
