---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/strategy/bluffer-strategy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.438029+00:00
---

# packages/games/src/chess-stakes/strategy/bluffer-strategy.ts

```ts
/**
 * BlufferStrategy — doubles aggressively from positions where you shouldn't.
 *
 * The theory: if the opponent can't perfectly evaluate the position,
 * an early double from a slightly worse or equal position creates
 * doubt. "Why did they double? Do they see something I don't?"
 *
 * Against strong opponents this bleeds EV. Against humans who
 * second-guess themselves, it prints money.
 *
 * The bluffer also takes more liberally than optimal — if they're
 * going to bluff-double, they can't be seen dropping constantly
 * or the bluffs stop working.
 *
 * Determinism: the seeded LCG below is byte-identical to the
 * legacy implementation in `../strategy.ts`. Do not "improve"
 * it — the pin test in `__tests__/legacy-pin.test.ts` will fail.
 */

import type {
  CubeDecision,
  CubeStrategy,
  CubeValue,
  OpponentModel,
  PositionDistribution,
  StakesChessBoard,
} from './types';

export class BlufferStrategy implements CubeStrategy {
  readonly name = 'bluffer';

  /**
   * How often to bluff-double from a non-doubling position.
   * 0.0 = never bluff (degenerates to optimal). 1.0 = always.
   * Sweet spot is ~0.2-0.35 — enough to be unpredictable,
   * not so much that you hemorrhage points.
   */
  private bluffFrequency: number;

  /**
   * Minimum win probability to even consider bluffing.
   * Below this, the position is too bad — a bluff just
   * accelerates the loss. Usually ~35-40%.
   */
  private bluffFloor: number;

  /** PRNG state for bluff decisions (deterministic for testing). */
  private rng: () => number;

  constructor(opts?: {
    bluffFrequency?: number;
    bluffFloor?: number;
    seed?: number;
  }) {
    this.bluffFrequency = opts?.bluffFrequency ?? 0.28;
    this.bluffFloor = opts?.bluffFloor ?? 0.38;
    // Simple seeded LCG for reproducible bluff decisions
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

    // Real doubles — when we actually have the goods
    if (wp >= 0.65) {
      return {
        action: 'double',
        confidence: wp,
        reasoning: `Genuine double: win prob ${(wp * 100).toFixed(1)}%`,
      };
    }

    // Bluff zone: position is mediocre but not hopeless
    if (wp >= this.bluffFloor && wp < 0.65) {
      // Bluff more against timid opponents, less against aggressive takers
      const adjustedFreq = this.bluffFrequency * (1.0 + (1.0 - opponent.riskTolerance) * 0.5);

      // Bluff more in volatile positions (harder for opponent to evaluate)
      const volatilityBonus = Math.min(position.volatility * 0.1, 0.15);
      const finalFreq = Math.min(adjustedFreq + volatilityBonus, 0.6);

      if (this.rng() < finalFreq) {
        return {
          action: 'double',
          confidence: 0.3 + (wp - this.bluffFloor) * 0.5, // fake confidence
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

    // Bluffers take more liberally — if you're seen dropping a lot,
    // opponents stop believing your doubles. Reputation management.
    const liberalTakePoint = 0.16; // lower than optimal's 0.22

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
    // Track opponent tendencies to calibrate future bluffs
    if (decision.action === 'drop') {
      // They dropped — maybe they're more timid than we thought
      return {
        ...opponent,
        riskTolerance: Math.max(0, opponent.riskTolerance - 0.05),
      };
    }
    if (decision.action === 'take') {
      // They took — they're braver than expected, bluff less
      return {
        ...opponent,
        riskTolerance: Math.min(1, opponent.riskTolerance + 0.05),
      };
    }
    return opponent;
  }
}

```
