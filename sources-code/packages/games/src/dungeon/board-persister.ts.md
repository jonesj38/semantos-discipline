---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/board-persister.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.403737+00:00
---

# packages/games/src/dungeon/board-persister.ts

```ts
/**
 * Board persister — commits every accepted action's resulting board
 * snapshot as a RELEVANT cell, chained via `prevCell` so the history
 * forms a DAG.
 *
 * The legacy engine inlined this as `commitBoard()`. The split keeps
 * the side-effect behind a single entry point and threads the new
 * board / cell bytes / history through the caller's atoms instead of
 * mutating an instance field.
 */

import { GameEntityType } from '../../../game-sdk/src/types';
import type { GameCellEngine } from '../../../game-sdk/src/engine';

import type { DungeonBoard, DungeonGameStatus } from './types';

// ── Owner IDs (legacy parity) ──────────────────────────────────

const DUNGEON_OWNER = new Uint8Array(16);
DUNGEON_OWNER[0] = 0x40;

const RELEVANT = 3;

export interface BoardCommitArgs {
  /** Engine used to allocate the board cell. */
  engine: GameCellEngine;
  /** The board state to snapshot. */
  board: DungeonBoard;
  /** Game status — written to the cell's `state` field. */
  status: DungeonGameStatus;
  /** Bytes of the previous board cell (for `prevCell` chain). */
  previousCellBytes: Uint8Array | null;
}

export interface BoardCommitResult {
  /** Updated board (new `cellId`, `previousBoardCellId` set). */
  board: DungeonBoard;
  /** Bytes of the newly created cell — feed into the next commit. */
  cellBytes: Uint8Array;
  /** Cell id (also surfaced as `board.cellId`). */
  cellId: string;
}

/**
 * Allocate a new board cell snapshotting the current dungeon state.
 * Pure relative to `args.engine` — produces a fresh board object,
 * doesn't mutate `args.board`.
 */
export function commitBoardSnapshot(args: BoardCommitArgs): BoardCommitResult {
  const { engine, board, status, previousCellBytes } = args;
  const boardEntity = engine.createEntity({
    entityType: GameEntityType.STRUCTURE,
    ownerId: DUNGEON_OWNER,
    linearity: RELEVANT,
    metadata: {
      domain: 'dungeon',
      floor: board.floor,
      turn: board.turnNumber,
      playerPos: [board.player.position.x, board.player.position.y],
      playerHp: board.player.hp,
      prev: board.cellId,
    },
    state: status === 'playing' ? 'playing' : status,
    prevCell: previousCellBytes ?? undefined,
  });

  const nextBoard: DungeonBoard = {
    ...board,
    cellId: boardEntity.id,
    previousBoardCellId: board.cellId,
  };

  return {
    board: nextBoard,
    cellBytes: boardEntity.cell,
    cellId: boardEntity.id,
  };
}

```
