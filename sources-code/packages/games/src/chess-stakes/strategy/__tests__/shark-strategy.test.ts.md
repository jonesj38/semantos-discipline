---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/strategy/__tests__/shark-strategy.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.438408+00:00
---

# packages/games/src/chess-stakes/strategy/__tests__/shark-strategy.test.ts

```ts
/**
 * Unit tests for SharkStrategy. Covers pressure accumulation, the
 * standard-double branch, the moveBonus integration hook, and
 * observe-driven tilt updates.
 */

import { describe, expect, test } from 'bun:test';
import { SharkStrategy } from '../shark-strategy';
import { defaultOpponentModel } from '../opponent-models';
import type { PositionDistribution, StakesChessBoard } from '../types';

function makeBoard(): StakesChessBoard {
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

describe('SharkStrategy', () => {
  test('standard double at wp ≥ 0.72', () => {
    const s = new SharkStrategy();
    const decision = s.shouldDouble(makeBoard(), pos(0.78, 0.15, { volatility: 1.0 }), defaultOpponentModel());
    expect(decision.action).toBe('double');
  });

  test('builds pressure then strikes in volatile positions', () => {
    const s = new SharkStrategy({ pressureThreshold: 1.0, volatilityWeight: 1.0 });
    const board = makeBoard();
    const opp = { ...defaultOpponentModel(), tiltFactor: 0.5 };
    const volatile = pos(0.6, 0.3, { volatility: 1.5, trend: 0.4 });

    // First call accumulates pressure to >= 1.0 → strikes
    const decision = s.shouldDouble(board, volatile, opp);
    expect(decision.action).toBe('double');
    if (decision.action === 'double') {
      expect(decision.reasoning).toContain('Shark strike');
    }
  });

  test('does not double in low-volatility positions even with pressure', () => {
    const s = new SharkStrategy({ pressureThreshold: 0.1 });
    const board = makeBoard();
    const opp = defaultOpponentModel();
    const decision = s.shouldDouble(board, pos(0.6, 0.3, { volatility: 0.3 }), opp);
    expect(decision.action).toBe('no-double');
  });

  test('moveBonus prefers volatile positive-trend positions', () => {
    const s = new SharkStrategy();
    const cube = makeBoard().cube;
    const quiet = pos(0.55, 0.35, { volatility: 0.3, trend: 0.1 });
    const sharp = pos(0.55, 0.35, { volatility: 1.8, trend: 0.4 });
    expect(s.moveBonus(sharp, cube)).toBeGreaterThan(s.moveBonus(quiet, cube));
  });

  test('moveBonus skips volatility bonus when cube is offered', () => {
    const s = new SharkStrategy();
    const offeredCube = { ...makeBoard().cube, state: 'offered' as const };
    const sharp = pos(0.55, 0.35, { volatility: 1.8, trend: 0.0 });
    // With state='offered', the volatility * 0.1 term is skipped.
    // trend=0 → bonus = 0; wp>0.5 && vol>1.0 → +0.2 only.
    expect(s.moveBonus(sharp, offeredCube)).toBeCloseTo(0.2, 5);
  });

  test('observeOpponentDecision raises tilt on drop, lowers on take', () => {
    const s = new SharkStrategy();
    const m = defaultOpponentModel();
    const dropped = s.observeOpponentDecision({ action: 'drop', reasoning: '' }, pos(0.5, 0.4), m);
    expect(dropped.tiltFactor).toBeGreaterThan(m.tiltFactor);
    const taken = s.observeOpponentDecision({ action: 'take', confidence: 0.5, reasoning: '' }, pos(0.5, 0.4), m);
    expect(taken.tiltFactor).toBeLessThanOrEqual(m.tiltFactor);
  });

  test('refuses to double when not holding the cube', () => {
    const s = new SharkStrategy();
    const board: StakesChessBoard = {
      ...makeBoard(),
      cube: {
        entity: { id: 'cube', entityType: 1, ownerId: new Uint8Array(16), linearity: 1, state: 'held', metadata: {}, cell: new Uint8Array(1024), timestamp: BigInt(0) },
        value: 2,
        state: 'held',
        holder: 'black',
        offeredBy: null,
      },
    } as StakesChessBoard;
    const decision = s.shouldDouble(board, pos(0.95, 0.02), defaultOpponentModel());
    expect(decision.action).toBe('no-double');
  });
});

```
