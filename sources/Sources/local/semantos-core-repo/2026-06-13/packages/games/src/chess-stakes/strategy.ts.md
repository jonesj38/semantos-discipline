---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/strategy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.415209+00:00
---

# packages/games/src/chess-stakes/strategy.ts

```ts
/**
 * @deprecated Import from `./strategy/strategy-facade` (or any of the
 * sub-modules under `./strategy/`) directly. This file is kept as a
 * thin compatibility shim so existing callers continue to work after
 * the refactor that split this 764-LOC monolith into focused modules.
 *
 * The real implementations now live in:
 *   ./strategy/types.ts            — shared interfaces
 *   ./strategy/optimal-strategy.ts — Janowski-formula reference impl
 *   ./strategy/bluffer-strategy.ts — seeded-LCG bluff cadence
 *   ./strategy/shark-strategy.ts   — pressure accumulator + moveBonus
 *   ./strategy/turtle-strategy.ts  — conservative impl
 *   ./strategy/opponent-models.ts  — opponent-model factories
 *
 * See `docs/prd/refactor-monoliths/26-chess-stakes-strategy-split.md`
 * (prompt 26) for context.
 */

export type {
  PositionDistribution,
  OpponentModel,
  CubeDecision,
  CubeStrategy,
} from './strategy/strategy-facade';

export {
  OptimalStrategy,
  BlufferStrategy,
  SharkStrategy,
  TurtleStrategy,
  defaultOpponentModel,
  engineOpponentModel,
  nervousHumanModel,
} from './strategy/strategy-facade';

```
