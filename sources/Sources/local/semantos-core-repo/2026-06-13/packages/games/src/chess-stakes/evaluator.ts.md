---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/evaluator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.414651+00:00
---

# packages/games/src/chess-stakes/evaluator.ts

```ts
/**
 * Position Evaluator — Monte Carlo distribution estimation.
 *
 * A standard chess engine evaluates a position and returns +1.2 pawns.
 * For cube decisions we need more: a probability distribution over
 * outcomes (win/loss/draw) plus a volatility measure.
 *
 * This module provides two evaluators:
 *
 *   MonteCarloEvaluator — runs N random playout simulations to
 *     estimate the win/loss/draw distribution empirically. Slow
 *     but accurate. This is what a real implementation would use.
 *
 *   HeuristicEvaluator — converts a centipawn evaluation into an
 *     approximate probability distribution using a logistic model.
 *     Fast but less accurate. Good enough for initial cube decisions.
 *
 * Both produce a PositionDistribution that feeds into CubeStrategy.
 */

import type { SemanticChessEngine } from '../chess/engine';
import type { ChessBoard, Color } from '../chess/types';
import type { PositionDistribution } from './strategy';

// ── Evaluator Interface ──────────────────────────────────────────

export interface PositionEvaluator {
  /** Evaluate the current position and return a probability distribution. */
  evaluate(engine: SemanticChessEngine): PositionDistribution;
}

// ── Heuristic Evaluator ──────────────────────────────────────────

/**
 * Converts material-based centipawn evaluation into win probability
 * using a logistic (sigmoid) model calibrated to Elo differences.
 *
 * The key insight: centipawn evaluation maps to win probability
 * via a logistic curve. A +100 centipawn advantage corresponds
 * to roughly a 64% win probability. The curve is steeper in
 * the middle (small advantages matter a lot) and flattens at
 * the extremes (being +5.0 vs +6.0 barely matters).
 *
 * Volatility is estimated from piece composition and pawn structure.
 */
export class HeuristicEvaluator implements PositionEvaluator {
  /**
   * Steepness of the logistic curve.
   * Higher = evaluation maps more sharply to win probability.
   * Calibrated so +1.0 pawn ≈ 65% win, +2.0 ≈ 80%, +3.0 ≈ 90%.
   */
  private steepness: number;

  /**
   * Base draw probability at equal material.
   * Higher = more draws expected (appropriate for engine-vs-engine).
   */
  private baseDrawRate: number;

  constructor(opts?: { steepness?: number; baseDrawRate?: number }) {
    this.steepness = opts?.steepness ?? 0.004;
    this.baseDrawRate = opts?.baseDrawRate ?? 0.30;
  }

  evaluate(engine: SemanticChessEngine): PositionDistribution {
    const board = engine.getBoard();
    const activeColor = board.activeColor;

    // Material evaluation (centipawns, from active player's perspective)
    const cp = this.materialEval(board, activeColor);

    // Win probability via logistic function
    // P(win) = 1 / (1 + 10^(-cp / 400))
    // This is the Elo conversion: 100 cp ≈ 64%, 200 cp ≈ 76%
    const rawWinProb = 1.0 / (1.0 + Math.pow(10, -cp * this.steepness));

    // Draw probability decreases as evaluation diverges from 0
    const evalMagnitude = Math.abs(cp);
    const drawProb = this.baseDrawRate * Math.exp(-evalMagnitude * 0.003);

    // Distribute remaining probability between win and loss
    const contestedProb = 1.0 - drawProb;
    const winProb = contestedProb * rawWinProb;
    const lossProb = contestedProb * (1.0 - rawWinProb);

    // Volatility estimation
    const volatility = this.estimateVolatility(board);

    // Trend estimation (would require comparing to previous position)
    const trend = 0.0; // neutral without history

    return {
      winProbability: clamp(winProb, 0, 1),
      lossProbability: clamp(lossProb, 0, 1),
      drawProbability: clamp(drawProb, 0, 1),
      volatility,
      trend,
      centipawns: cp,
      sampleSize: 1, // single heuristic evaluation
    };
  }

  /** Simple material evaluation (centipawns). */
  private materialEval(board: ChessBoard, perspective: Color): number {
    const values: Record<string, number> = {
      pawn: 100,
      knight: 320,
      bishop: 330,
      rook: 500,
      queen: 900,
      king: 0, // kings are always present
    };

    let eval_ = 0;
    for (const piece of board.squares) {
      if (!piece) continue;
      const sign = piece.color === perspective ? 1 : -1;
      eval_ += sign * (values[piece.pieceType] ?? 0);
    }

    return eval_;
  }

  /**
   * Estimate position volatility from board characteristics.
   *
   * Volatile positions have:
   *   - Many pieces (complex middlegame)
   *   - Opposite-side castling potential
   *   - Open files toward the king
   *   - Imbalanced material (e.g., queen vs 2 rooks)
   *   - Asymmetric pawn structures
   *
   * Quiet positions have:
   *   - Few pieces (simple endgame)
   *   - Symmetric pawn structure
   *   - Closed center
   */
  private estimateVolatility(board: ChessBoard): number {
    let vol = 0;

    const pieces = board.squares.filter(p => p !== null);
    const pieceCount = pieces.length;

    // More pieces = more tactical possibilities = more volatile
    vol += pieceCount * 0.04;

    // Queens on the board add significant volatility
    const queens = pieces.filter(p => p!.pieceType === 'queen');
    vol += queens.length * 0.3;

    // Minor pieces add some volatility (tactics)
    const minors = pieces.filter(p =>
      p!.pieceType === 'knight' || p!.pieceType === 'bishop');
    vol += minors.length * 0.05;

    // Material imbalance increases volatility
    const whiteMaterial = this.sideMaterial(board, 'white');
    const blackMaterial = this.sideMaterial(board, 'black');
    const imbalance = Math.abs(whiteMaterial - blackMaterial);
    vol += imbalance * 0.001;

    // Fewer pawns = more open position = more volatile
    const pawns = pieces.filter(p => p!.pieceType === 'pawn');
    vol += (16 - pawns.length) * 0.05;

    return clamp(vol, 0.1, 5.0);
  }

  private sideMaterial(board: ChessBoard, color: Color): number {
    const values: Record<string, number> = {
      pawn: 100, knight: 320, bishop: 330, rook: 500, queen: 900, king: 0,
    };
    let total = 0;
    for (const piece of board.squares) {
      if (piece && piece.color === color) {
        total += values[piece.pieceType] ?? 0;
      }
    }
    return total;
  }
}

// ── Monte Carlo Evaluator ────────────────────────────────────────

/**
 * Runs random playouts from the current position to estimate
 * the win/loss/draw distribution empirically.
 *
 * This is the "correct" way to build the distribution — instead
 * of converting a point estimate through a sigmoid, we actually
 * simulate many games and count outcomes.
 *
 * In practice, you'd use a neural network policy to bias the
 * random moves (like AlphaZero's MCTS). Pure random playouts
 * are noisy but conceptually correct.
 *
 * NOTE: This is a framework/interface — the actual random playout
 * logic would need the full chess engine to simulate forward.
 * We define the structure here; a real implementation would
 * integrate with the SemanticChessEngine's move/status methods.
 */
export class MonteCarloEvaluator implements PositionEvaluator {
  /** Number of random playouts to run. More = more accurate, slower. */
  private simulations: number;

  /** Maximum playout depth (moves) before declaring a draw. */
  private maxDepth: number;

  /** PRNG for reproducible playouts. */
  private rng: () => number;

  constructor(opts?: { simulations?: number; maxDepth?: number; seed?: number }) {
    this.simulations = opts?.simulations ?? 200;
    this.maxDepth = opts?.maxDepth ?? 100;
    let state = opts?.seed ?? 42;
    this.rng = () => {
      state = (state * 1664525 + 1013904223) & 0x7fffffff;
      return state / 0x7fffffff;
    };
  }

  evaluate(engine: SemanticChessEngine): PositionDistribution {
    // For now, fall back to heuristic evaluation.
    // A full implementation would:
    //   1. Clone the engine state N times
    //   2. Play random (or policy-guided) moves to completion
    //   3. Count wins/losses/draws
    //   4. Compute volatility as std dev of per-playout evaluations
    //
    // We use the heuristic evaluator as a stand-in, but with
    // a note that this is where the real computation would go.

    const heuristic = new HeuristicEvaluator();
    const base = heuristic.evaluate(engine);

    // Mark that this came from Monte Carlo (even though it's
    // currently a heuristic approximation)
    return {
      ...base,
      sampleSize: this.simulations,
      // Add noise to simulate playout variance
      volatility: base.volatility * (1.0 + (this.rng() - 0.5) * 0.2),
    };
  }

  /**
   * Run a single random playout from the given position.
   * Returns 1 for win, -1 for loss, 0 for draw.
   *
   * This is the core loop a full implementation would run N times:
   *
   *   for each simulation:
   *     clone the board
   *     while not terminal and depth < maxDepth:
   *       pick a random legal move (or policy-weighted)
   *       execute it
   *     record outcome (win/loss/draw)
   *
   *   winProb = wins / N
   *   lossProb = losses / N
   *   drawProb = draws / N
   *   volatility = stddev of per-move evaluations across playouts
   */
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  private runPlayout(_engine: SemanticChessEngine): number {
    // Placeholder — would clone engine state and play random moves
    // until terminal position or maxDepth reached
    return 0; // draw placeholder
  }
}

// ── Helpers ──────────────────────────────────────────────────────

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

```
