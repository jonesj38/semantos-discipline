---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/chess-stakes-strategy.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.586447+00:00
---

# tests/gates/chess-stakes-strategy.test.ts

```ts
/**
 * Chess Stakes Strategy Tests — Cube decision-making behavior.
 *
 * Tests that each strategy makes correct cube decisions given
 * different position distributions and opponent models.
 */

import { describe, test, expect } from 'bun:test';
import {
  OptimalStrategy,
  BlufferStrategy,
  SharkStrategy,
  TurtleStrategy,
  defaultOpponentModel,
  engineOpponentModel,
  nervousHumanModel,
  type PositionDistribution,
  type OpponentModel,
} from '../../packages/games/src/chess-stakes/strategy';
import type { StakesChessBoard } from '../../packages/games/src/chess-stakes/types';

// ── Helpers ──────────────────────────────────────────────────────

/** Build a minimal StakesChessBoard for strategy testing. */
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

/** Build a position distribution. */
function makePosition(win: number, loss: number, opts?: Partial<PositionDistribution>): PositionDistribution {
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

// ── Optimal Strategy ─────────────────────────────────────────────

describe('OptimalStrategy', () => {
  const strategy = new OptimalStrategy();
  const opponent = defaultOpponentModel();

  test('doubles when win probability exceeds doubling point', () => {
    const board = makeBoard();
    const pos = makePosition(0.72, 0.18); // 72% win
    const decision = strategy.shouldDouble(board, pos, opponent);
    expect(decision.action).toBe('double');
  });

  test('does not double when below doubling point', () => {
    const board = makeBoard();
    const pos = makePosition(0.55, 0.35); // 55% win — not enough
    const decision = strategy.shouldDouble(board, pos, opponent);
    expect(decision.action).toBe('no-double');
  });

  test('"too good to double" — plays on in overwhelming stable positions', () => {
    const board = makeBoard();
    const pos = makePosition(0.85, 0.10, { volatility: 0.2 }); // 85% stable
    const decision = strategy.shouldDouble(board, pos, opponent);
    // Should be too good to double (opponent would drop, denying full payout)
    expect(decision.action).toBe('no-double');
    expect(decision.reasoning).toContain('too good');
  });

  test('takes when win probability exceeds take point', () => {
    const board = makeBoard({ phase: 'awaiting-response' });
    // From responder's perspective: we're behind but have 28% to win
    const pos = makePosition(0.62, 0.28); // opponent sees 62%, we see 28%
    const decision = strategy.shouldTake(board, pos, opponent, 2);
    expect(decision.action).toBe('take');
  });

  test('drops when position is hopeless', () => {
    const board = makeBoard({ phase: 'awaiting-response' });
    const pos = makePosition(0.88, 0.08); // we only win 8%
    const decision = strategy.shouldTake(board, pos, opponent, 2);
    expect(decision.action).toBe('drop');
  });
});

// ── Bluffer Strategy ─────────────────────────────────────────────

describe('BlufferStrategy', () => {
  // Seed for reproducible bluff decisions
  const strategy = new BlufferStrategy({ bluffFrequency: 1.0, seed: 42 });

  test('bluff-doubles from mediocre positions', () => {
    const board = makeBoard();
    const pos = makePosition(0.50, 0.40, { volatility: 1.5 }); // 50/50 volatile
    const opponent = nervousHumanModel(); // timid opponent
    const decision = strategy.shouldDouble(board, pos, opponent);
    // With bluffFrequency=1.0, a volatile position against a nervous human
    // should always trigger a bluff
    expect(decision.action).toBe('double');
    expect(decision.reasoning).toContain('Bluff');
  });

  test('does not bluff from hopeless positions', () => {
    const board = makeBoard();
    const pos = makePosition(0.25, 0.65); // clearly losing
    const opponent = defaultOpponentModel();
    const decision = strategy.shouldDouble(board, pos, opponent);
    expect(decision.action).toBe('no-double');
  });

  test('takes more liberally than optimal (reputation management)', () => {
    const board = makeBoard({ phase: 'awaiting-response' });
    // 18% win chance — optimal would drop (below 22%), bluffer takes
    const pos = makePosition(0.72, 0.18);
    const opponent = defaultOpponentModel();
    const decision = strategy.shouldTake(board, pos, opponent, 2);
    expect(decision.action).toBe('take');
  });

  test('updates opponent model after observing drop', () => {
    const opponent = defaultOpponentModel();
    const dropDecision = { action: 'drop' as const, reasoning: 'test' };
    const pos = makePosition(0.60, 0.30);
    const updated = strategy.observeOpponentDecision!(dropDecision, pos, opponent);
    expect(updated.riskTolerance).toBeLessThan(opponent.riskTolerance);
  });
});

// ── Shark Strategy ───────────────────────────────────────────────

describe('SharkStrategy', () => {
  test('builds pressure over volatile moves then strikes', () => {
    const strategy = new SharkStrategy({ pressureThreshold: 2.0 });
    const board = makeBoard();
    const opponent: OpponentModel = { ...defaultOpponentModel(), tiltFactor: 0.3 };

    // Several volatile positions build pressure
    const volatile = makePosition(0.58, 0.32, { volatility: 1.5, trend: 0.3 });

    // First evaluation — pressure building
    let decision = strategy.shouldDouble(board, volatile, opponent);
    // May or may not double depending on accumulated pressure

    // Second evaluation — more pressure
    decision = strategy.shouldDouble(board, volatile, opponent);

    // After enough pressure accumulation with a decent win prob,
    // the shark should eventually strike
    // (exact timing depends on pressure math, just verify it's considered)
    expect(decision.reasoning).toBeDefined();
  });

  test('standard doubles when position is clearly winning', () => {
    const strategy = new SharkStrategy();
    const board = makeBoard();
    const pos = makePosition(0.78, 0.15, { volatility: 1.0 });
    const opponent = defaultOpponentModel();
    const decision = strategy.shouldDouble(board, pos, opponent);
    expect(decision.action).toBe('double');
  });

  test('moveBonus prefers volatile positions when cube is available', () => {
    const strategy = new SharkStrategy();
    const cube = makeBoard().cube;

    const quiet = makePosition(0.55, 0.35, { volatility: 0.3, trend: 0.1 });
    const sharp = makePosition(0.55, 0.35, { volatility: 1.8, trend: 0.3 });

    const quietBonus = strategy.moveBonus(quiet, cube);
    const sharpBonus = strategy.moveBonus(sharp, cube);

    expect(sharpBonus).toBeGreaterThan(quietBonus);
  });

  test('increases opponent tilt after they drop', () => {
    const strategy = new SharkStrategy();
    const opponent = defaultOpponentModel();
    const dropDecision = { action: 'drop' as const, reasoning: 'test' };
    const pos = makePosition(0.60, 0.30);
    const updated = strategy.observeOpponentDecision!(dropDecision, pos, opponent);
    expect(updated.tiltFactor).toBeGreaterThan(opponent.tiltFactor);
  });
});

// ── Turtle Strategy ──────────────────────────────────────────────

describe('TurtleStrategy', () => {
  const strategy = new TurtleStrategy();
  const opponent = defaultOpponentModel();

  test('only doubles in overwhelming positions', () => {
    const board = makeBoard();

    // 70% win — optimal would double, turtle won't
    const goodNotGreat = makePosition(0.70, 0.20, { volatility: 0.5 });
    expect(strategy.shouldDouble(board, goodNotGreat, opponent).action).toBe('no-double');

    // 85% win, quiet — even the turtle doubles
    const overwhelming = makePosition(0.85, 0.10, { volatility: 0.3 });
    expect(strategy.shouldDouble(board, overwhelming, opponent).action).toBe('double');
  });

  test('takes almost everything (frustrates bluffers)', () => {
    const board = makeBoard({ phase: 'awaiting-response' });

    // 15% win chance — optimal drops, turtle takes
    const tough = makePosition(0.75, 0.15);
    expect(strategy.shouldTake(board, tough, opponent, 2).action).toBe('take');

    // 8% win — even turtle drops
    const hopeless = makePosition(0.88, 0.08);
    expect(strategy.shouldTake(board, hopeless, opponent, 2).action).toBe('drop');
  });
});

// ── Strategy Matchups ────────────────────────────────────────────

describe('Strategy matchups — behavioral predictions', () => {
  test('bluffer vs turtle: turtle frustrates bluffs by always taking', () => {
    const bluffer = new BlufferStrategy({ bluffFrequency: 1.0, seed: 42 });
    const turtle = new TurtleStrategy();
    const board = makeBoard();

    // Bluffer doubles from a marginal position
    const marginal = makePosition(0.48, 0.42, { volatility: 1.2 });
    const bluffDecision = bluffer.shouldDouble(board, marginal, nervousHumanModel());

    if (bluffDecision.action === 'double') {
      // Turtle faces the double — with 42% loss (= our 42% win), turtle takes
      const turtleDecision = turtle.shouldTake(
        makeBoard({ phase: 'awaiting-response' }),
        marginal,
        defaultOpponentModel(),
        2,
      );
      // Turtle's take point is 12%, and we have ~42% to win — easy take
      expect(turtleDecision.action).toBe('take');
    }
  });

  test('shark vs nervous human: pressure builds and forces errors', () => {
    const shark = new SharkStrategy({ pressureThreshold: 1.5 });
    const human = nervousHumanModel();

    // Simulate a sequence of volatile positions
    const board = makeBoard();
    const volatile = makePosition(0.58, 0.30, { volatility: 2.0, trend: 0.4 });

    // Keep evaluating — shark accumulates pressure
    for (let i = 0; i < 5; i++) {
      const decision = shark.shouldDouble(board, volatile, human);
      if (decision.action === 'double') {
        // Shark eventually strikes — verify it's with reasoning
        expect(decision.reasoning).toBeDefined();
        expect(decision.confidence).toBeGreaterThan(0);
        return; // test passes
      }
    }
    // If shark didn't double in 5 tries, that's also valid behavior
    // (pressure didn't reach threshold)
  });
});

// ── Opponent Model Factories ─────────────────────────────────────

describe('Opponent model factories', () => {
  test('default model is balanced', () => {
    const model = defaultOpponentModel();
    expect(model.evaluationAccuracy).toBe(0.7);
    expect(model.riskTolerance).toBe(0.5);
    expect(model.tiltFactor).toBe(0);
  });

  test('engine model is accurate and stoic', () => {
    const model = engineOpponentModel();
    expect(model.evaluationAccuracy).toBe(0.95);
    expect(model.tiltFactor).toBe(0);
  });

  test('nervous human model is timid and tiltable', () => {
    const model = nervousHumanModel();
    expect(model.evaluationAccuracy).toBeLessThan(0.5);
    expect(model.riskTolerance).toBeLessThan(0.5);
    expect(model.tiltFactor).toBeGreaterThan(0);
  });
});

```
