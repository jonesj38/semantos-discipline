---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/strategy/turtle-strategy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.437737+00:00
---

# packages/games/src/chess-stakes/strategy/turtle-strategy.ts

```ts
/**
 * TurtleStrategy — conservative cube handling. Rarely doubles, almost
 * always takes.
 *
 * The turtle's philosophy: chess skill wins games, not cube tricks.
 * By rarely doubling, the turtle keeps stakes low and reduces
 * variance. By almost always taking, the turtle forces the opponent
 * to actually win the game on the board.
 *
 * Effective against bluffers (never folds to bluffs) and in
 * situations where you're the stronger chess player and just need
 * to grind out wins without variance spikes.
 *
 * Pure module — stateless, no PRNG, no IO.
 */

import type {
  CubeDecision,
  CubeStrategy,
  CubeValue,
  OpponentModel,
  PositionDistribution,
  StakesChessBoard,
} from './types';

export class TurtleStrategy implements CubeStrategy {
  readonly name = 'turtle';

  shouldDouble(
    board: StakesChessBoard,
    position: PositionDistribution,
    _opponent: OpponentModel,
  ): CubeDecision {
    if (board.cube.state === 'held' && board.cube.holder !== board.chess.activeColor) {
      return { action: 'no-double', reasoning: 'Do not hold the cube' };
    }

    // Only double when it's overwhelming — 80%+ win probability
    // in a stable position. The turtle doesn't gamble.
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

    // The turtle almost always takes. Only drops when it's truly hopeless.
    // This frustrates bluffers and forces the opponent to prove it on the board.
    const turtleTakePoint = 0.12; // much lower than optimal

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

```
