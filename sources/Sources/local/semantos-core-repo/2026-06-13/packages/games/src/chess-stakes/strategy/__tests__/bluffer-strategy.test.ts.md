---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/strategy/__tests__/bluffer-strategy.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.439659+00:00
---

# packages/games/src/chess-stakes/strategy/__tests__/bluffer-strategy.test.ts

```ts
/**
 * Unit tests for BlufferStrategy. The seeded LCG makes the bluff-zone
 * decisions reproducible.
 */

import { describe, expect, test } from 'bun:test';
import { BlufferStrategy } from '../bluffer-strategy';
import { defaultOpponentModel, nervousHumanModel } from '../opponent-models';
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

describe('BlufferStrategy', () => {
  test('genuine double at wp ≥ 0.65', () => {
    const s = new BlufferStrategy({ seed: 1 });
    const decision = s.shouldDouble(makeBoard(), pos(0.7, 0.2), defaultOpponentModel());
    expect(decision.action).toBe('double');
    if (decision.action === 'double') {
      expect(decision.reasoning).toContain('Genuine');
    }
  });

  test('always bluffs at frequency 1.0 in the bluff zone vs nervous human', () => {
    const s = new BlufferStrategy({ bluffFrequency: 1.0, seed: 42 });
    const decision = s.shouldDouble(makeBoard(), pos(0.5, 0.4, { volatility: 1.5 }), nervousHumanModel());
    expect(decision.action).toBe('double');
    if (decision.action === 'double') {
      expect(decision.reasoning).toContain('Bluff');
    }
  });

  test('never bluffs at frequency 0', () => {
    const s = new BlufferStrategy({ bluffFrequency: 0, seed: 42 });
    const decision = s.shouldDouble(makeBoard(), pos(0.5, 0.4, { volatility: 1.5 }), defaultOpponentModel());
    expect(decision.action).toBe('no-double');
  });

  test('does not bluff from hopeless positions', () => {
    const s = new BlufferStrategy({ bluffFrequency: 1.0, seed: 7 });
    const decision = s.shouldDouble(makeBoard(), pos(0.25, 0.65), defaultOpponentModel());
    expect(decision.action).toBe('no-double');
  });

  test('takes liberally at our-wp ≥ 0.16', () => {
    const s = new BlufferStrategy({ seed: 1 });
    // ourWinProb = 0.18 + 0 * 0.5 = 0.18 (no draws)
    const decision = s.shouldTake(makeBoard(), pos(0.72, 0.18), defaultOpponentModel(), 2);
    expect(decision.action).toBe('take');
  });

  test('drops below 0.16', () => {
    const s = new BlufferStrategy({ seed: 1 });
    const decision = s.shouldTake(makeBoard(), pos(0.85, 0.10), defaultOpponentModel(), 2);
    expect(decision.action).toBe('drop');
  });

  test('observeOpponentDecision shifts riskTolerance on drop / take', () => {
    const s = new BlufferStrategy({ seed: 1 });
    const m = defaultOpponentModel();
    const afterDrop = s.observeOpponentDecision({ action: 'drop', reasoning: '' }, pos(0.5, 0.4), m);
    expect(afterDrop.riskTolerance).toBeLessThan(m.riskTolerance);
    const afterTake = s.observeOpponentDecision({ action: 'take', confidence: 0.5, reasoning: '' }, pos(0.5, 0.4), m);
    expect(afterTake.riskTolerance).toBeGreaterThan(m.riskTolerance);
  });

  test('seeded LCG is deterministic', () => {
    const a = new BlufferStrategy({ bluffFrequency: 0.5, seed: 999 });
    const b = new BlufferStrategy({ bluffFrequency: 0.5, seed: 999 });
    const board = makeBoard();
    const opp = defaultOpponentModel();
    const p = pos(0.5, 0.4, { volatility: 1.0 });
    for (let i = 0; i < 20; i++) {
      const da = a.shouldDouble(board, p, opp);
      const db = b.shouldDouble(board, p, opp);
      expect(da).toEqual(db);
    }
  });
});

```
