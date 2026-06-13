---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/go/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.412371+00:00
---

# packages/games/src/go/types.ts

```ts
/**
 * Go types -- semantic cell model for Go (Weiqi/Baduk).
 *
 * Every stone is an AFFINE cell (placed once, consumed on capture).
 * The board is a RELEVANT cell whose payload references intersections.
 * Each move produces a new board cell linked to the previous one (DAG).
 */

import type { GameEntity } from '../../../game-sdk/src/types';

// -- Stone Types ----------------------------------------------------------

export type StoneColor = 'black' | 'white';

/** A Go stone backed by an AFFINE GameEntity cell. */
export interface GoStone {
  /** The underlying GameEntity (1024-byte cell) */
  entity: GameEntity;
  color: StoneColor;
  /** Intersection index: 0 to size*size-1 */
  intersection: number;
}

// -- Board ----------------------------------------------------------------

export type BoardSize = 9 | 13 | 19;

/** The board is a semantic object (RELEVANT cell) containing intersection refs. */
export interface GoBoard {
  /** Board cell ID */
  cellId: string;
  /** Board dimension (9, 13, or 19) */
  size: BoardSize;
  /** Flat array of intersections: size*size entries, null = empty */
  intersections: (GoStone | null)[];
  /** Number of black stones captured (held by white) */
  capturedBlack: number;
  /** Number of white stones captured (held by black) */
  capturedWhite: number;
  /** Ko point intersection index, or null */
  koPoint: number | null;
  /** DAG link to previous board state cell */
  previousBoardCellId: string | null;
}

// -- Game Status ----------------------------------------------------------

export type GoGameStatus = 'playing' | 'scoring' | 'finished';

export interface GoMoveResult {
  board: GoBoard;
  captured: GoStone[];
  status: GoGameStatus;
}

export interface GoScore {
  blackTerritory: number;
  whiteTerritory: number;
  blackStones: number;
  whiteStones: number;
  capturedBlack: number;
  capturedWhite: number;
  /** Chinese scoring: territory + stones on board */
  blackTotal: number;
  whiteTotal: number;
  /** Standard komi for white */
  komi: number;
  /** Final score difference (positive = black wins) */
  result: number;
}

// -- Intersection Helpers -------------------------------------------------

/** Convert intersection index to row (0-based from top). */
export function intersectionRow(idx: number, size: number): number {
  return Math.floor(idx / size);
}

/** Convert intersection index to column (0-based from left). */
export function intersectionCol(idx: number, size: number): number {
  return idx % size;
}

/** Convert row and column to intersection index. */
export function toIntersection(row: number, col: number, size: number): number {
  return row * size + col;
}

/** Convert intersection index to Go coordinate string (e.g., "D4"). */
export function intersectionToCoord(idx: number, size: number): string {
  const col = intersectionCol(idx, size);
  const row = intersectionRow(idx, size);
  // Go coordinates skip 'I' to avoid confusion with 'J'
  const colLetter = String.fromCharCode(col < 8 ? 65 + col : 66 + col);
  const rowNum = size - row;
  return `${colLetter}${rowNum}`;
}

/** Convert Go coordinate string (e.g., "D4") to intersection index. */
export function coordToIntersection(coord: string, size: number): number {
  const colChar = coord.charCodeAt(0);
  // Account for skipped 'I'
  const col = colChar >= 74 ? colChar - 66 : colChar - 65; // 'J' and above shift
  const row = size - parseInt(coord.slice(1), 10);
  return toIntersection(row, col, size);
}

```
