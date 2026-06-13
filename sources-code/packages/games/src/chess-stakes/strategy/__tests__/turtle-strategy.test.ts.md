---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/strategy/__tests__/turtle-strategy.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.439039+00:00
---

# packages/games/src/chess-stakes/strategy/__tests__/turtle-strategy.test.ts

```ts
/**
 * Unit tests for TurtleStrategy. Stateless, no PRNG — pure threshold checks.
 */

import { describe, expect, test } from 'bun:test';
import { TurtleStrategy } from '../turtle-strategy';
import { defaultOpponentModel } from '../opponent-models';
import type { PositionDistribution, StakesChessBoard } from '../types';

function makeBoard(overrides?: Partial<StakesChessBoard>): StakesChessBoard {
  return {
    chess: {
      cellId: 'test-board',
      squares: new Array(64).fill(null),
      activeColor: 'white',
      castlingRights: { whiteKingside: true, whiteQueenside: true, blackKingside: true, blackQueenside: true },
      enPassantTarget: null,
      halfMoveClock: 0,
      fullMoveNumber: 1,
      previousBoardCellId: null,
    },
    cube: {
      entity: { id: 'cube', entityType: 1, ownerId: new Uint8Array(16), linearity: 1, state: 'centered', metadata: {}, cell: new Uint8Array(1024), timestamp: BigInt(0) },
      value: 1,
      state: 'centered',
      holder: null,
      offeredBy: null,
    },
    phase: 'cube-or-move',
    ...overrides,
  } as StakesChessBoard;
}

function pos(win: number, loss: number, opts?: Partial<PositionDistribution>): PositionDistribution {
  return {
    winProbability: win,
    lossProbability: loss,
    drawProbability: 1.0 - win - loss,
    volatility: opts?.volatility ?? 0.5,
    trend: opts?.trend ?? 0,
    centipawns: opts?.centipawns ?? 0,
    sampleSize: opts?.sampleSize ?? 100,
  };
}

describe('TurtleStrategy', () => {
  const s = new TurtleStrategy();
  const opp = defaultOpponentModel();

  test('only doubles in overwhelming quiet positions', () => {
    expect(s.shouldDouble(makeBoard(), pos(0.7, 0.2, { volatility: 0.5 }), opp).action).toBe('no-double');
    expect(s.shouldDouble(makeBoard(), pos(0.85, 0.10, { volatility: 0.3 }), opp).action).toBe('double');
  });

  test('does not double when overwhelming but volatile', () => {
    expect(s.shouldDouble(makeBoard(), pos(0.85, 0.10, { volatility: 1.5 }), opp).action).toBe('no-double');
  });

  test('takes almost everything', () => {
    expect(s.shouldTake(makeBoard({ phase: 'awaiting-response' }), pos(0.75, 0.15), opp, 2).action).toBe('take');
  });

  test('drops only when truly hopeless', () => {
    expect(s.shouldTake(makeBoard({ phase: 'awaiting-response' }), pos(0.88, 0.08), opp, 2).action).toBe('drop');
  });

  test('refuses to double when not holding the cube', () => {
    const board = makeBoard({
      cube: {
        entity: { id: 'cube', entityType: 1, ownerId: new Uint8Array(16), linearity: 1, state: 'held', metadata: {}, cell: new Uint8Array(1024), timestamp: BigInt(0) },
        value: 2,
        state: 'held',
        holder: 'black',
        offeredBy: null,
      },
    });
    expect(s.shouldDouble(board, pos(0.95, 0.02, { volatility: 0.1 }), opp).action).toBe('no-double');
  });
});

```
