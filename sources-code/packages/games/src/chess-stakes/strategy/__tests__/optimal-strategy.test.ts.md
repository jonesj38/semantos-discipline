---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/strategy/__tests__/optimal-strategy.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.439361+00:00
---

# packages/games/src/chess-stakes/strategy/__tests__/optimal-strategy.test.ts

```ts
/**
 * Unit tests for OptimalStrategy. Exercises the Janowski-formula
 * thresholds (doublingPoint, takePoint, cubeOwnershipBonus) and the
 * "too good to double" branch.
 */

import { describe, expect, test } from 'bun:test';
import { OptimalStrategy } from '../optimal-strategy';
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

describe('OptimalStrategy', () => {
  const opponent = defaultOpponentModel();

  test('doubles when wp ≥ doubling point and not too-good', () => {
    const s = new OptimalStrategy();
    const decision = s.shouldDouble(makeBoard(), pos(0.72, 0.18), opponent);
    expect(decision.action).toBe('double');
  });

  test('does not double below doubling point', () => {
    const s = new OptimalStrategy();
    const decision = s.shouldDouble(makeBoard(), pos(0.55, 0.35), opponent);
    expect(decision.action).toBe('no-double');
  });

  test('"too good to double" — stable overwhelming positions', () => {
    const s = new OptimalStrategy();
    const decision = s.shouldDouble(makeBoard(), pos(0.85, 0.10, { volatility: 0.2 }), opponent);
    expect(decision.action).toBe('no-double');
    if (decision.action === 'no-double') {
      expect(decision.reasoning).toContain('too good');
    }
  });

  test('volatile overwhelming positions — still doubles', () => {
    // wp=0.85 but volatility=2.0 → not "too good", should double
    const s = new OptimalStrategy();
    const decision = s.shouldDouble(makeBoard(), pos(0.85, 0.10, { volatility: 2.0 }), opponent);
    expect(decision.action).toBe('double');
  });

  test('refuses to double when not holding the cube', () => {
    const s = new OptimalStrategy();
    const board = makeBoard({
      cube: {
        entity: { id: 'cube', entityType: 1, ownerId: new Uint8Array(16), linearity: 1, state: 'held', metadata: {}, cell: new Uint8Array(1024), timestamp: BigInt(0) },
        value: 2,
        state: 'held',
        holder: 'black',
        offeredBy: null,
      },
    });
    const decision = s.shouldDouble(board, pos(0.9, 0.05), opponent);
    expect(decision.action).toBe('no-double');
    expect(decision.reasoning).toContain('Do not hold');
  });

  test('takes when wp ≥ adjusted take point', () => {
    const s = new OptimalStrategy();
    const decision = s.shouldTake(
      makeBoard({ phase: 'awaiting-response' }),
      pos(0.62, 0.28),
      opponent,
      2,
    );
    expect(decision.action).toBe('take');
  });

  test('drops when wp below take point', () => {
    const s = new OptimalStrategy();
    const decision = s.shouldTake(
      makeBoard({ phase: 'awaiting-response' }),
      pos(0.88, 0.08),
      opponent,
      2,
    );
    expect(decision.action).toBe('drop');
  });

  test('custom thresholds change behavior', () => {
    const tight = new OptimalStrategy({ doublingPoint: 0.9 });
    const decision = tight.shouldDouble(makeBoard(), pos(0.72, 0.18), opponent);
    expect(decision.action).toBe('no-double');
  });
});

```
