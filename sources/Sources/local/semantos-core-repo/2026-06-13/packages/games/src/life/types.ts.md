---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/life/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.406574+00:00
---

# packages/games/src/life/types.ts

```ts
/**
 * Game of Life Types
 *
 * Conway's Game of Life modeled with semantic cells.
 * Each alive cell is an AFFINE cell (created and consumed each generation).
 * The board is a RELEVANT cell forming a DAG of generations.
 */

import type { GameEntity } from '../../../game-sdk/src/types';

// ── Board ───────────────────────────────────────────────────────

export interface LifeBoard {
  /** Cell ID of this board state */
  cellId: string;
  /** Board width */
  width: number;
  /** Board height */
  height: number;
  /** Current generation number */
  generation: number;
  /** Alive cells indexed by flat position */
  alive: Map<number, LifeCell>;
  /** Link to previous generation's cell ID */
  previousBoardCellId: string | null;
}

// ── Cell ────────────────────────────────────────────────────────

export interface LifeCell {
  /** The underlying AFFINE cell entity */
  entity: GameEntity;
  /** Flat index on the board (row * width + col) */
  position: number;
}

// ── Step result ─────────────────────────────────────────────────

export interface LifeStepResult {
  /** New board state */
  board: LifeBoard;
  /** Number of cells born this step */
  born: number;
  /** Number of cells that died this step */
  died: number;
  /** Current generation number */
  generation: number;
  /** Population count */
  population: number;
}

// ── Known patterns ──────────────────────────────────────────────

export type PatternName =
  | 'blinker'
  | 'glider'
  | 'block'
  | 'beehive'
  | 'toad'
  | 'beacon'
  | 'rpentomino'
  | 'acorn';

/** Pattern as list of [row, col] offsets from top-left */
export const PATTERNS: Record<PatternName, [number, number][]> = {
  // Oscillators
  blinker: [[0, 0], [0, 1], [0, 2]],
  toad: [[0, 1], [0, 2], [0, 3], [1, 0], [1, 1], [1, 2]],
  beacon: [[0, 0], [0, 1], [1, 0], [2, 3], [3, 2], [3, 3]],

  // Still lifes
  block: [[0, 0], [0, 1], [1, 0], [1, 1]],
  beehive: [[0, 1], [0, 2], [1, 0], [1, 3], [2, 1], [2, 2]],

  // Spaceships
  glider: [[0, 1], [1, 2], [2, 0], [2, 1], [2, 2]],

  // Long-lived
  rpentomino: [[0, 1], [0, 2], [1, 0], [1, 1], [2, 1]],
  acorn: [[0, 1], [1, 3], [2, 0], [2, 1], [2, 4], [2, 5], [2, 6]],
};

```
