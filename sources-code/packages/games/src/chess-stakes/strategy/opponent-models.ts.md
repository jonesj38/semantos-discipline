---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/strategy/opponent-models.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.436178+00:00
---

# packages/games/src/chess-stakes/strategy/opponent-models.ts

```ts
/**
 * Opponent model factories — pre-canned `OpponentModel` instances
 * for common archetypes (default human, strong engine, nervous human).
 *
 * Pure module: each factory returns a fresh literal so callers can
 * mutate freely without aliasing.
 */

import type { OpponentModel } from './types';

/** Create a default opponent model (assumes a competent, neutral player). */
export function defaultOpponentModel(): OpponentModel {
  return {
    evaluationAccuracy: 0.7,
    riskTolerance: 0.5,
    tiltFactor: 0.0,
    estimatedOpponentWinProb: null,
  };
}

/** Create an opponent model for a strong engine. */
export function engineOpponentModel(): OpponentModel {
  return {
    evaluationAccuracy: 0.95,
    riskTolerance: 0.7, // engines are emotionless, take when correct
    tiltFactor: 0.0,    // engines don't tilt
    estimatedOpponentWinProb: null,
  };
}

/** Create an opponent model for a nervous human. */
export function nervousHumanModel(): OpponentModel {
  return {
    evaluationAccuracy: 0.4,
    riskTolerance: 0.25,
    tiltFactor: 0.3,
    estimatedOpponentWinProb: null,
  };
}

```
