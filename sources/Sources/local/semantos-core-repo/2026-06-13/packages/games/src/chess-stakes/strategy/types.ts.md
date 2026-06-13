---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/strategy/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.436753+00:00
---

# packages/games/src/chess-stakes/strategy/types.ts

```ts
/**
 * Strategy types — shared interfaces for cube decision-making.
 *
 * Pure type module. No runtime logic, no side effects. The split
 * mirrors the spec's "evaluation pure" requirement: the data shapes
 * (PositionDistribution, OpponentModel, CubeDecision) are defined here
 * once and referenced by every strategy implementation.
 *
 * See `./strategy-facade.ts` for the bundled re-export surface and
 * `../strategy.ts` for the legacy entry point (deprecated shim).
 */

import type { DoublingCube, CubeValue, StakesChessBoard } from '../types';

// ── Position Distribution ────────────────────────────────────────

/**
 * A probability distribution over game outcomes from the current position.
 *
 * This is the fundamental new data structure that doesn't exist in
 * standard chess engines. A normal engine returns a centipawn score.
 * A stakes engine needs to know the SHAPE of the outcome distribution.
 *
 * Two positions can both evaluate to +1.0 but have wildly different
 * distributions:
 *   - Stable: 70% win, 5% lose, 25% draw (quiet endgame, pawn up)
 *   - Volatile: 55% win, 35% lose, 10% draw (opposite-side castling attack)
 *
 * The volatile position is worse for doubling because the opponent
 * knows they have counterplay. The stable position is ideal for doubling
 * because the opponent faces a grim take-or-drop decision.
 */
export interface PositionDistribution {
  /** Probability of winning from this position (0.0–1.0) */
  winProbability: number;
  /** Probability of losing (0.0–1.0) */
  lossProbability: number;
  /** Probability of draw (0.0–1.0, sum of all three = 1.0) */
  drawProbability: number;

  /**
   * Volatility — standard deviation of the evaluation across
   * Monte Carlo simulations. High volatility = tactical chaos.
   * Low volatility = technical grind.
   *
   * Range: 0.0 (completely determined) to ~5.0+ (total chaos)
   * Typical values: 0.2–0.5 (quiet), 1.0–2.0 (sharp), 3.0+ (wild)
   */
  volatility: number;

  /**
   * Trend — is the position getting better or worse for the active player
   * over the next N moves? Positive = improving, negative = deteriorating.
   *
   * This matters for cube timing: you want to double when you're at
   * peak advantage or when the trend is about to reverse (opponent
   * is about to consolidate). You do NOT want to double when your
   * advantage is still growing — wait for the peak.
   */
  trend: number;

  /**
   * Centipawn evaluation (traditional engine eval).
   * Provided for reference — the distribution is what matters for cube.
   */
  centipawns: number;

  /**
   * Number of simulations used to compute this distribution.
   * Higher = more confident in the probabilities.
   */
  sampleSize: number;
}

// ── Opponent Model ───────────────────────────────────────────────

/**
 * What we believe about the opponent's decision-making.
 *
 * Against a perfect opponent, bluffing is pointless — they compute
 * the same win probability you do and take/drop correctly.
 * Against a human (or an engine with a different eval), there's
 * an information gap you can exploit.
 */
export interface OpponentModel {
  /**
   * How accurately the opponent evaluates positions.
   * 1.0 = perfect (top engine), 0.0 = random.
   * Against a weaker opponent, you can double from thinner margins
   * because they'll misjudge the take/drop threshold.
   */
  evaluationAccuracy: number;

  /**
   * Opponent's risk tolerance.
   * 1.0 = will take anything that's mathematically close.
   * 0.0 = drops at the first sign of trouble.
   * Aggressive opponents are harder to bluff (they always take).
   * Timid opponents are great bluff targets (they drop too easily).
   */
  riskTolerance: number;

  /**
   * How much the opponent tilts under pressure.
   * 0.0 = ice cold, 1.0 = prone to panic.
   * A tilting opponent plays worse after being doubled, making
   * the shark strategy more effective.
   */
  tiltFactor: number;

  /**
   * Opponent's estimated win probability for the current position.
   * null if unknown (we model what we think they think).
   * When this diverges from our own estimate, there's an
   * information edge to exploit.
   */
  estimatedOpponentWinProb: number | null;
}

// ── Cube Decision ────────────────────────────────────────────────

/** The possible cube decisions a strategy can recommend. */
export type CubeDecision =
  | { action: 'double'; confidence: number; reasoning: string }
  | { action: 'no-double'; reasoning: string }
  | { action: 'take'; confidence: number; reasoning: string }
  | { action: 'drop'; reasoning: string };

// ── CubeStrategy Interface ───────────────────────────────────────

/**
 * A pluggable cube decision-maker.
 *
 * The engine calls shouldDouble() before each move and
 * shouldTake() when facing a double. The strategy returns
 * a decision with a confidence level and human-readable reasoning.
 *
 * Strategies can be stateful — they may track the opponent's
 * past cube behavior to update their opponent model.
 */
export interface CubeStrategy {
  /** Human-readable strategy name. */
  readonly name: string;

  /**
   * Should we double before making our move?
   *
   * Called when phase is 'cube-or-move' and doubling is legal.
   * The strategy sees the full board state, cube state, position
   * distribution, and opponent model.
   */
  shouldDouble(
    board: StakesChessBoard,
    position: PositionDistribution,
    opponent: OpponentModel,
  ): CubeDecision;

  /**
   * Should we take or drop a proposed double?
   *
   * Called when phase is 'awaiting-response'.
   * The strategy sees the same info plus the proposed new cube value.
   */
  shouldTake(
    board: StakesChessBoard,
    position: PositionDistribution,
    opponent: OpponentModel,
    proposedValue: CubeValue,
  ): CubeDecision;

  /**
   * Update the opponent model based on observed behavior.
   * Called after the opponent makes a cube decision, so the
   * strategy can learn their tendencies over a match.
   */
  observeOpponentDecision?(
    decision: CubeDecision,
    position: PositionDistribution,
    opponent: OpponentModel,
  ): OpponentModel;
}

// Re-export DoublingCube for callers that import shark moveBonus.
export type { DoublingCube, CubeValue, StakesChessBoard };

```
