---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/strategy/optimal-strategy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.436461+00:00
---

# packages/games/src/chess-stakes/strategy/optimal-strategy.ts

```ts
/**
 * OptimalStrategy — game-theoretically correct cube handling.
 *
 * Pure module: no `Math.random`, no IO, no time-dependent logic.
 * The class holds three numeric thresholds (takePoint, doublingPoint,
 * cubeOwnershipBonus) and applies them deterministically.
 *
 * Uses the Janowski formula from backgammon theory:
 *   - Double when win probability ≥ doubling point
 *   - Take when win probability ≥ take point (≈ 25% in money play)
 *   - Adjusts for cube ownership (having the cube is worth ~2-4%)
 *
 * This is the "boring correct" strategy. It never bluffs.
 * Against another optimal player, it extracts maximum EV.
 * Against a human, it leaves psychological equity on the table.
 */

import type {
  CubeDecision,
  CubeStrategy,
  CubeValue,
  OpponentModel,
  PositionDistribution,
  StakesChessBoard,
} from './types';

export class OptimalStrategy implements CubeStrategy {
  readonly name = 'optimal';

  /**
   * The take point: minimum win probability to accept a double.
   * In backgammon money play this is 25%. In chess it might be
   * different because draws are more common (you don't lose the
   * full stakes on a draw).
   *
   * With draws: take point = L / (W + L) where W = win equity
   * gained, L = loss equity risked. For a pure double with draws
   * counting as half: take point ≈ 20-22%.
   */
  private takePoint: number;

  /**
   * The doubling point: minimum win probability to offer a double.
   * In backgammon this is ~70-76% for money play.
   * The window between the doubling point and 100% is where you
   * should double. Too early = opponent has an easy take. Too late
   * = you've given away equity by not doubling sooner.
   */
  private doublingPoint: number;

  /**
   * Cube ownership bonus: how much holding the cube is worth
   * in win probability points. Typically 2-4%.
   */
  private cubeOwnershipBonus: number;

  constructor(opts?: {
    takePoint?: number;
    doublingPoint?: number;
    cubeOwnershipBonus?: number;
  }) {
    // Defaults tuned for chess (more draws than backgammon)
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

    // Don't double if we don't hold the cube (and it's not centered)
    // This check is redundant with the policy but makes reasoning clear
    if (board.cube.state === 'held' && board.cube.holder !== board.chess.activeColor) {
      return { action: 'no-double', reasoning: 'Do not hold the cube' };
    }

    if (wp >= adjustedDoubling) {
      // Check for "too good to double" — if our win probability is
      // so high that we expect to win more by playing on (opponent
      // would correctly drop, denying us the higher payout)
      const tooGoodPoint = 1.0 - this.takePoint; // ~78%
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
    // From the responder's perspective, "winning" means the RESPONDER wins
    // So we use lossProbability as "our" win probability (we're the defending side)
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

```
