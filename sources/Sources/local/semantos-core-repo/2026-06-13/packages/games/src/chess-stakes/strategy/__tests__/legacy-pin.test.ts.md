---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/strategy/__tests__/legacy-pin.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.438724+00:00
---

# packages/games/src/chess-stakes/strategy/__tests__/legacy-pin.test.ts

```ts
/**
 * Legacy-pin test — byte-identical decision pin against the original
 * monolithic strategy.ts.
 *
 * The four legacy strategies are inlined verbatim below (with `Legacy`
 * prefix). For 50 deterministic fixture positions, we run the same
 * inputs through legacy and new implementations and assert deep-equal
 * CubeDecision outputs (including `confidence` floats, `reasoning`
 * strings, and pressure-sequence side effects).
 *
 * This is the prompt-26 analogue of the prompt-16 deterministic-shuffle
 * pin: a hard guarantee that the refactor introduced zero behavioral
 * drift. If a future "improvement" changes a threshold, a string
 * format, or the LCG step, this test will fail.
 *
 * NEVER modify the legacy block below to "match" a refactored impl.
 * Instead, treat any failure here as a regression in the new code.
 */

import { describe, expect, test } from 'bun:test';
import {
  OptimalStrategy,
  BlufferStrategy,
  SharkStrategy,
  TurtleStrategy,
} from '../strategy-facade';
import type {
  CubeDecision,
  CubeStrategy,
  CubeValue,
  DoublingCube,
  OpponentModel,
  PositionDistribution,
  StakesChessBoard,
} from '../types';

// ═══════════════════════════════════════════════════════════════════
// Legacy verbatim copies (do not edit)
// ═══════════════════════════════════════════════════════════════════

class LegacyOptimalStrategy implements CubeStrategy {
  readonly name = 'optimal';
  private takePoint: number;
  private doublingPoint: number;
  private cubeOwnershipBonus: number;

  constructor(opts?: {
    takePoint?: number;
    doublingPoint?: number;
    cubeOwnershipBonus?: number;
  }) {
    this.takePoint = opts?.takePoint ?? 0.22;
    this.doublingPoint = opts?.doublingPoint ?? 0.68;
    this.cubeOwnershipBonus = opts?.cubeOwnershipBonus ?? 0.03;
  }

  shouldDouble(
    board: StakesChessBoard,
    position: PositionDistribution,
    _opponent: OpponentModel,
  ): CubeDecision {
    const wp = position.winProbability;
    const adjustedDoubling = this.doublingPoint;

    if (board.cube.state === 'held' && board.cube.holder !== board.chess.activeColor) {
      return { action: 'no-double', reasoning: 'Do not hold the cube' };
    }

    if (wp >= adjustedDoubling) {
      const tooGoodPoint = 1.0 - this.takePoint;
      if (wp >= tooGoodPoint && position.volatility < 0.5) {
        return {
          action: 'no-double',
          reasoning: `Win prob ${(wp * 100).toFixed(1)}% — too good to double in stable position, play on for full point`,
        };
      }

      return {
        action: 'double',
        confidence: Math.min((wp - adjustedDoubling) / (1.0 - adjustedDoubling), 1.0),
        reasoning: `Win prob ${(wp * 100).toFixed(1)}% exceeds doubling point ${(adjustedDoubling * 100).toFixed(1)}%`,
      };
    }

    return {
      action: 'no-double',
      reasoning: `Win prob ${(wp * 100).toFixed(1)}% below doubling point ${(adjustedDoubling * 100).toFixed(1)}%`,
    };
  }

  shouldTake(
    _board: StakesChessBoard,
    position: PositionDistribution,
    _opponent: OpponentModel,
    _proposedValue: CubeValue,
  ): CubeDecision {
    const ourWinProb = position.lossProbability + (position.drawProbability * 0.5);
    const adjustedTake = this.takePoint - this.cubeOwnershipBonus;

    if (ourWinProb >= adjustedTake) {
      return {
        action: 'take',
        confidence: Math.min((ourWinProb - adjustedTake) / (0.5 - adjustedTake), 1.0),
        reasoning: `Our win prob ${(ourWinProb * 100).toFixed(1)}% exceeds take point ${(adjustedTake * 100).toFixed(1)}% (includes cube ownership bonus)`,
      };
    }

    return {
      action: 'drop',
      reasoning: `Our win prob ${(ourWinProb * 100).toFixed(1)}% below take point ${(adjustedTake * 100).toFixed(1)}%`,
    };
  }
}

class LegacyBlufferStrategy implements CubeStrategy {
  readonly name = 'bluffer';
  private bluffFrequency: number;
  private bluffFloor: number;
  private rng: () => number;

  constructor(opts?: { bluffFrequency?: number; bluffFloor?: number; seed?: number }) {
    this.bluffFrequency = opts?.bluffFrequency ?? 0.28;
    this.bluffFloor = opts?.bluffFloor ?? 0.38;
    let state = opts?.seed ?? Date.now();
    this.rng = () => {
      state = (state * 1664525 + 1013904223) & 0x7fffffff;
      return state / 0x7fffffff;
    };
  }

  shouldDouble(
    board: StakesChessBoard,
    position: PositionDistribution,
    opponent: OpponentModel,
  ): CubeDecision {
    const wp = position.winProbability;

    if (board.cube.state === 'held' && board.cube.holder !== board.chess.activeColor) {
      return { action: 'no-double', reasoning: 'Do not hold the cube' };
    }

    if (wp >= 0.65) {
      return {
        action: 'double',
        confidence: wp,
        reasoning: `Genuine double: win prob ${(wp * 100).toFixed(1)}%`,
      };
    }

    if (wp >= this.bluffFloor && wp < 0.65) {
      const adjustedFreq = this.bluffFrequency * (1.0 + (1.0 - opponent.riskTolerance) * 0.5);
      const volatilityBonus = Math.min(position.volatility * 0.1, 0.15);
      const finalFreq = Math.min(adjustedFreq + volatilityBonus, 0.6);

      if (this.rng() < finalFreq) {
        return {
          action: 'double',
          confidence: 0.3 + (wp - this.bluffFloor) * 0.5,
          reasoning: `Bluff double: win prob only ${(wp * 100).toFixed(1)}% but position is volatile (${position.volatility.toFixed(2)}) and opponent risk tolerance is ${opponent.riskTolerance.toFixed(2)}`,
        };
      }
    }

    return {
      action: 'no-double',
      reasoning: `No double: win prob ${(wp * 100).toFixed(1)}%, no bluff this time`,
    };
  }

  shouldTake(
    _board: StakesChessBoard,
    position: PositionDistribution,
    _opponent: OpponentModel,
    _proposedValue: CubeValue,
  ): CubeDecision {
    const ourWinProb = position.lossProbability + (position.drawProbability * 0.5);
    const liberalTakePoint = 0.16;

    if (ourWinProb >= liberalTakePoint) {
      return {
        action: 'take',
        confidence: ourWinProb,
        reasoning: `Take (liberal): ${(ourWinProb * 100).toFixed(1)}% — can't be seen dropping or our bluffs lose credibility`,
      };
    }

    return {
      action: 'drop',
      reasoning: `Even a bluffer knows when to fold: ${(ourWinProb * 100).toFixed(1)}%`,
    };
  }

  observeOpponentDecision(
    decision: CubeDecision,
    _position: PositionDistribution,
    opponent: OpponentModel,
  ): OpponentModel {
    if (decision.action === 'drop') {
      return { ...opponent, riskTolerance: Math.max(0, opponent.riskTolerance - 0.05) };
    }
    if (decision.action === 'take') {
      return { ...opponent, riskTolerance: Math.min(1, opponent.riskTolerance + 0.05) };
    }
    return opponent;
  }
}

class LegacySharkStrategy implements CubeStrategy {
  readonly name = 'shark';
  private pressure: number = 0;
  private pressureThreshold: number;
  private volatilityWeight: number;

  constructor(opts?: { pressureThreshold?: number; volatilityWeight?: number }) {
    this.pressureThreshold = opts?.pressureThreshold ?? 3.0;
    this.volatilityWeight = opts?.volatilityWeight ?? 0.8;
  }

  shouldDouble(
    board: StakesChessBoard,
    position: PositionDistribution,
    opponent: OpponentModel,
  ): CubeDecision {
    const wp = position.winProbability;

    if (board.cube.state === 'held' && board.cube.holder !== board.chess.activeColor) {
      return { action: 'no-double', reasoning: 'Do not hold the cube' };
    }

    this.pressure += position.volatility * this.volatilityWeight;
    if (position.trend > 0.2) this.pressure += position.trend * 0.5;
    this.pressure += opponent.tiltFactor * 0.3;

    const shouldStrike =
      wp >= 0.55 && this.pressure >= this.pressureThreshold && position.volatility >= 0.8;
    const standardDouble = wp >= 0.72;

    if (shouldStrike) {
      const decision: CubeDecision = {
        action: 'double',
        confidence: Math.min(wp + this.pressure * 0.05, 0.99),
        reasoning: `Shark strike: pressure ${this.pressure.toFixed(1)} built over volatile position (vol=${position.volatility.toFixed(2)}), wp=${(wp * 100).toFixed(1)}%, opponent tilt=${opponent.tiltFactor.toFixed(2)}`,
      };
      this.pressure = 0;
      return decision;
    }

    if (standardDouble) {
      const decision: CubeDecision = {
        action: 'double',
        confidence: wp,
        reasoning: `Standard shark double: wp=${(wp * 100).toFixed(1)}% — no need to wait for pressure`,
      };
      this.pressure = 0;
      return decision;
    }

    return {
      action: 'no-double',
      reasoning: `Building pressure (${this.pressure.toFixed(1)}/${this.pressureThreshold.toFixed(1)}), wp=${(wp * 100).toFixed(1)}%`,
    };
  }

  shouldTake(
    _board: StakesChessBoard,
    position: PositionDistribution,
    _opponent: OpponentModel,
    _proposedValue: CubeValue,
  ): CubeDecision {
    const ourWinProb = position.lossProbability + (position.drawProbability * 0.5);
    const sharkTakePoint = 0.24;
    const volatilityAdjust = Math.min(position.volatility * 0.03, 0.06);

    if (ourWinProb >= sharkTakePoint - volatilityAdjust) {
      return {
        action: 'take',
        confidence: ourWinProb,
        reasoning: `Shark take: ${(ourWinProb * 100).toFixed(1)}% with volatility bonus — there's counterplay in this mess`,
      };
    }

    return {
      action: 'drop',
      reasoning: `Position too clean for the opponent: ${(ourWinProb * 100).toFixed(1)}% — no shark eats a dead fish`,
    };
  }

  moveBonus(resultingPosition: PositionDistribution, cubeState: DoublingCube): number {
    let bonus = 0;
    if (cubeState.state !== 'offered') bonus += resultingPosition.volatility * 0.1;
    bonus += resultingPosition.trend * 0.15;
    if (resultingPosition.winProbability > 0.5 && resultingPosition.volatility > 1.0) bonus += 0.2;
    return bonus;
  }
}

class LegacyTurtleStrategy implements CubeStrategy {
  readonly name = 'turtle';

  shouldDouble(
    board: StakesChessBoard,
    position: PositionDistribution,
    _opponent: OpponentModel,
  ): CubeDecision {
    if (board.cube.state === 'held' && board.cube.holder !== board.chess.activeColor) {
      return { action: 'no-double', reasoning: 'Do not hold the cube' };
    }
    if (position.winProbability >= 0.80 && position.volatility < 1.0) {
      return {
        action: 'double',
        confidence: position.winProbability,
        reasoning: `Even a turtle doubles at ${(position.winProbability * 100).toFixed(1)}% in a quiet position`,
      };
    }
    return {
      action: 'no-double',
      reasoning: `Turtle holds steady at ${(position.winProbability * 100).toFixed(1)}% — just play chess`,
    };
  }

  shouldTake(
    _board: StakesChessBoard,
    position: PositionDistribution,
    _opponent: OpponentModel,
    _proposedValue: CubeValue,
  ): CubeDecision {
    const ourWinProb = position.lossProbability + (position.drawProbability * 0.5);
    const turtleTakePoint = 0.12;
    if (ourWinProb >= turtleTakePoint) {
      return {
        action: 'take',
        confidence: ourWinProb,
        reasoning: `Turtle takes at ${(ourWinProb * 100).toFixed(1)}% — make them prove it over the board`,
      };
    }
    return {
      action: 'drop',
      reasoning: `Even a turtle drops at ${(ourWinProb * 100).toFixed(1)}% — this position is beyond repair`,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════
// Fixture generation — 50 deterministic positions
// ═══════════════════════════════════════════════════════════════════

/** Tiny seeded PRNG for fixture generation only — not the strategy LCG. */
function fixtureRng(seed: number) {
  let s = seed;
  return () => {
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    return s / 0x7fffffff;
  };
}

interface Scenario {
  board: StakesChessBoard;
  position: PositionDistribution;
  opponent: OpponentModel;
  proposedValue: CubeValue;
}

function makeScenarios(count: number): Scenario[] {
  const rng = fixtureRng(0xC0FFEE);
  const out: Scenario[] = [];
  for (let i = 0; i < count; i++) {
    const win = rng() * 0.95 + 0.02;          // 0.02..0.97
    const lossSpace = 1.0 - win - 0.02;
    const loss = rng() * Math.max(lossSpace, 0); // remainder is draw
    const volatility = rng() * 4.0;            // 0..4
    const trend = (rng() - 0.5) * 1.0;         // -0.5..0.5
    const tiltFactor = rng();
    const riskTolerance = rng();
    const evaluationAccuracy = rng();
    const cubeHeld = rng() < 0.3;
    const cubeOpponent = cubeHeld && rng() < 0.5;

    const board: StakesChessBoard = {
      chess: {
        cellId: `fix-${i}`,
        squares: new Array(64).fill(null),
        activeColor: 'white',
        castlingRights: { whiteKingside: true, whiteQueenside: true, blackKingside: true, blackQueenside: true },
        enPassantTarget: null,
        halfMoveClock: 0,
        fullMoveNumber: 1,
        previousBoardCellId: null,
      },
      cube: {
        entity: { id: `cube-${i}`, entityType: 1, ownerId: new Uint8Array(16), linearity: 1, state: cubeHeld ? 'held' : 'centered', metadata: {}, cell: new Uint8Array(1024), timestamp: BigInt(0) },
        value: cubeHeld ? 2 : 1,
        state: cubeHeld ? 'held' : 'centered',
        holder: cubeHeld ? (cubeOpponent ? 'black' : 'white') : null,
        offeredBy: null,
      },
      phase: 'cube-or-move',
    } as StakesChessBoard;

    out.push({
      board,
      position: {
        winProbability: win,
        lossProbability: loss,
        drawProbability: 1.0 - win - loss,
        volatility,
        trend,
        centipawns: Math.round((win - 0.5) * 200),
        sampleSize: 100,
      },
      opponent: {
        evaluationAccuracy,
        riskTolerance,
        tiltFactor,
        estimatedOpponentWinProb: null,
      },
      proposedValue: 2,
    });
  }
  return out;
}

const SCENARIOS = makeScenarios(50);

// ═══════════════════════════════════════════════════════════════════
// Pin tests
// ═══════════════════════════════════════════════════════════════════

describe('Legacy pin — OptimalStrategy', () => {
  test('shouldDouble identical across 50 fixtures', () => {
    const legacy = new LegacyOptimalStrategy();
    const next = new OptimalStrategy();
    for (const s of SCENARIOS) {
      expect(next.shouldDouble(s.board, s.position, s.opponent)).toEqual(
        legacy.shouldDouble(s.board, s.position, s.opponent),
      );
    }
  });

  test('shouldTake identical across 50 fixtures', () => {
    const legacy = new LegacyOptimalStrategy();
    const next = new OptimalStrategy();
    const respondBoard = (b: StakesChessBoard): StakesChessBoard => ({ ...b, phase: 'awaiting-response' } as StakesChessBoard);
    for (const s of SCENARIOS) {
      const b = respondBoard(s.board);
      expect(next.shouldTake(b, s.position, s.opponent, s.proposedValue)).toEqual(
        legacy.shouldTake(b, s.position, s.opponent, s.proposedValue),
      );
    }
  });
});

describe('Legacy pin — BlufferStrategy (seeded)', () => {
  test('shouldDouble identical across 50 fixtures', () => {
    const legacy = new LegacyBlufferStrategy({ seed: 12345 });
    const next = new BlufferStrategy({ seed: 12345 });
    for (const s of SCENARIOS) {
      expect(next.shouldDouble(s.board, s.position, s.opponent)).toEqual(
        legacy.shouldDouble(s.board, s.position, s.opponent),
      );
    }
  });

  test('shouldTake identical across 50 fixtures', () => {
    const legacy = new LegacyBlufferStrategy({ seed: 7 });
    const next = new BlufferStrategy({ seed: 7 });
    for (const s of SCENARIOS) {
      expect(next.shouldTake(s.board, s.position, s.opponent, s.proposedValue)).toEqual(
        legacy.shouldTake(s.board, s.position, s.opponent, s.proposedValue),
      );
    }
  });

  test('observeOpponentDecision identical', () => {
    const legacy = new LegacyBlufferStrategy({ seed: 1 });
    const next = new BlufferStrategy({ seed: 1 });
    for (const s of SCENARIOS) {
      const drop: CubeDecision = { action: 'drop', reasoning: 'x' };
      const take: CubeDecision = { action: 'take', confidence: 0.5, reasoning: 'x' };
      expect(next.observeOpponentDecision(drop, s.position, s.opponent)).toEqual(
        legacy.observeOpponentDecision(drop, s.position, s.opponent),
      );
      expect(next.observeOpponentDecision(take, s.position, s.opponent)).toEqual(
        legacy.observeOpponentDecision(take, s.position, s.opponent),
      );
    }
  });
});

describe('Legacy pin — SharkStrategy (stateful pressure)', () => {
  test('shouldDouble sequence identical across 50 fixtures', () => {
    // Stateful: feed scenarios in order to both legacy and new instance.
    const legacy = new LegacySharkStrategy();
    const next = new SharkStrategy();
    for (const s of SCENARIOS) {
      expect(next.shouldDouble(s.board, s.position, s.opponent)).toEqual(
        legacy.shouldDouble(s.board, s.position, s.opponent),
      );
    }
  });

  test('shouldTake identical across 50 fixtures (stateless path)', () => {
    const legacy = new LegacySharkStrategy();
    const next = new SharkStrategy();
    for (const s of SCENARIOS) {
      expect(next.shouldTake(s.board, s.position, s.opponent, s.proposedValue)).toEqual(
        legacy.shouldTake(s.board, s.position, s.opponent, s.proposedValue),
      );
    }
  });

  test('moveBonus identical across 50 fixtures', () => {
    const legacy = new LegacySharkStrategy();
    const next = new SharkStrategy();
    for (const s of SCENARIOS) {
      expect(next.moveBonus(s.position, s.board.cube)).toBe(
        legacy.moveBonus(s.position, s.board.cube),
      );
    }
  });
});

describe('Legacy pin — TurtleStrategy', () => {
  test('shouldDouble identical across 50 fixtures', () => {
    const legacy = new LegacyTurtleStrategy();
    const next = new TurtleStrategy();
    for (const s of SCENARIOS) {
      expect(next.shouldDouble(s.board, s.position, s.opponent)).toEqual(
        legacy.shouldDouble(s.board, s.position, s.opponent),
      );
    }
  });

  test('shouldTake identical across 50 fixtures', () => {
    const legacy = new LegacyTurtleStrategy();
    const next = new TurtleStrategy();
    for (const s of SCENARIOS) {
      expect(next.shouldTake(s.board, s.position, s.opponent, s.proposedValue)).toEqual(
        legacy.shouldTake(s.board, s.position, s.opponent, s.proposedValue),
      );
    }
  });
});

```
