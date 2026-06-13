---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/strategy/strategy-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.437115+00:00
---

# packages/games/src/chess-stakes/strategy/strategy-facade.ts

```ts
/**
 * Strategy facade — single re-export surface for the chess-stakes
 * strategy modules.
 *
 * Callers should import from this module (or the parent `../strategy.ts`
 * shim, which forwards here). Each named export is owned by one file
 * in this folder; the facade just bundles them.
 *
 * Layout:
 *   types.ts            — interfaces (PositionDistribution, OpponentModel,
 *                         CubeDecision, CubeStrategy)
 *   optimal-strategy.ts — OptimalStrategy
 *   bluffer-strategy.ts — BlufferStrategy (seeded LCG)
 *   shark-strategy.ts   — SharkStrategy (pressure + moveBonus)
 *   turtle-strategy.ts  — TurtleStrategy
 *   opponent-models.ts  — default / engine / nervous-human factories
 */

export type {
  PositionDistribution,
  OpponentModel,
  CubeDecision,
  CubeStrategy,
} from './types';

export { OptimalStrategy } from './optimal-strategy';
export { BlufferStrategy } from './bluffer-strategy';
export { SharkStrategy } from './shark-strategy';
export { TurtleStrategy } from './turtle-strategy';

export {
  defaultOpponentModel,
  engineOpponentModel,
  nervousHumanModel,
} from './opponent-models';

```
