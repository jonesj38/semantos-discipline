---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/strategy/shark-strategy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.437441+00:00
---

# packages/games/src/chess-stakes/strategy/shark-strategy.ts

```ts
/**
 * SharkStrategy — plays sharp, volatile lines specifically to create
 * doubling pressure.
 *
 * The shark doesn't just decide when to double — it influences
 * which CHESS MOVES to play based on cube implications. This is
 * the deepest integration of cube strategy with chess strategy.
 *
 * Key behaviors:
 *   1. Prefers volatile positions where the eval can swing wildly
 *   2. Times doubles at the moment of maximum opponent discomfort
 *   3. Doubles when the opponent is in time trouble or after a
 *      sequence of only-moves (psychological pressure)
 *   4. Maintains a "pressure score" that accumulates and releases
 *
 * The shark is not about bluffing — it's about creating positions
 * where the objectively correct double is also psychologically
 * devastating. You double not because you're ahead, but because
 * you're ahead AND the position is terrifying to defend.
 *
 * Stakes integration: `moveBonus()` is the hook that the chess search
 * can consult to bias move selection toward shark-friendly resulting
 * positions. The score it returns is added to the base evaluation.
 */

import type {
  CubeDecision,
  CubeStrategy,
  CubeValue,
  DoublingCube,
  OpponentModel,
  PositionDistribution,
  StakesChessBoard,
} from './types';

export class SharkStrategy implements CubeStrategy {
  readonly name = 'shark';

  /**
   * Pressure accumulator. Builds up as we play sharp moves,
   * the opponent makes near-only-moves, and the position
   * becomes more complex. Released when we double.
   */
  private pressure: number = 0;

  /**
   * Pressure threshold for triggering a double.
   * Higher = more patient shark, waits for perfect moment.
   */
  private pressureThreshold: number;

  /**
   * How much volatility adds to pressure per move.
   */
  private volatilityWeight: number;

  constructor(opts?: {
    pressureThreshold?: number;
    volatilityWeight?: number;
  }) {
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

    // Accumulate pressure based on position characteristics
    this.pressure += position.volatility * this.volatilityWeight;

    // Extra pressure from negative trend for opponent
    if (position.trend > 0.2) {
      this.pressure += position.trend * 0.5;
    }

    // Extra pressure from opponent's tilt factor
    this.pressure += opponent.tiltFactor * 0.3;

    // The shark doubles when:
    // 1. We have at least a slight advantage (wp ≥ 0.55)
    // 2. Pressure has built up past the threshold
    // 3. Position is volatile (opponent faces hard decisions)
    const shouldStrike =
      wp >= 0.55 &&
      this.pressure >= this.pressureThreshold &&
      position.volatility >= 0.8;

    // Or standard doubling when position is just good
    const standardDouble = wp >= 0.72;

    if (shouldStrike) {
      const decision: CubeDecision = {
        action: 'double',
        confidence: Math.min(wp + this.pressure * 0.05, 0.99),
        reasoning: `Shark strike: pressure ${this.pressure.toFixed(1)} built over volatile position (vol=${position.volatility.toFixed(2)}), wp=${(wp * 100).toFixed(1)}%, opponent tilt=${opponent.tiltFactor.toFixed(2)}`,
      };
      this.pressure = 0; // release pressure after doubling
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
    opponent: OpponentModel,
    _proposedValue: CubeValue,
  ): CubeDecision {
    const ourWinProb = position.lossProbability + (position.drawProbability * 0.5);

    // Sharks take based on position, not pride. Slightly tighter than
    // optimal because a shark respects when another shark doubles.
    const sharkTakePoint = 0.24;

    // But in volatile positions, take more liberally — a shark knows
    // volatility means counterplay exists
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

  observeOpponentDecision(
    decision: CubeDecision,
    _position: PositionDistribution,
    opponent: OpponentModel,
  ): OpponentModel {
    // After opponent drops, they may tilt (frustrated)
    if (decision.action === 'drop') {
      return {
        ...opponent,
        tiltFactor: Math.min(1, opponent.tiltFactor + 0.1),
        riskTolerance: Math.max(0, opponent.riskTolerance - 0.03),
      };
    }
    // After opponent takes, they showed resolve — less tilt
    if (decision.action === 'take') {
      return {
        ...opponent,
        tiltFactor: Math.max(0, opponent.tiltFactor - 0.05),
        riskTolerance: Math.min(1, opponent.riskTolerance + 0.03),
      };
    }
    return opponent;
  }

  /**
   * The shark also influences move selection.
   *
   * Given a set of candidate chess moves with their resulting
   * position distributions, the shark prefers moves that:
   *   1. Maintain or increase volatility
   *   2. Create positions where the opponent has few options
   *   3. Set up future doubling opportunities
   *
   * Returns a score adjustment to add to each move's base eval.
   * The chess engine would add this to its normal evaluation
   * to bias move selection toward shark-friendly positions.
   */
  moveBonus(
    resultingPosition: PositionDistribution,
    cubeState: DoublingCube,
  ): number {
    let bonus = 0;

    // Prefer volatile positions when we might double soon
    if (cubeState.state !== 'offered') {
      bonus += resultingPosition.volatility * 0.1;
    }

    // Prefer positions with positive trend (getting better for us)
    bonus += resultingPosition.trend * 0.15;

    // Slight bonus for positions that are "doubly sharp" —
    // high volatility AND we're slightly ahead
    if (resultingPosition.winProbability > 0.5 && resultingPosition.volatility > 1.0) {
      bonus += 0.2;
    }

    return bonus;
  }
}

```
