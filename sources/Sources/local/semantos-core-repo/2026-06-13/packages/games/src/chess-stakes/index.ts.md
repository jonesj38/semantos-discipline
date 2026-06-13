---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.413800+00:00
---

# packages/games/src/chess-stakes/index.ts

```ts
/**
 * Double Mate — Chess with Backgammon Doubling Cube
 *
 * A chess variant where players can offer to double the stakes
 * before making their move. The opponent must take (accept, stakes
 * double) or drop (decline, forfeit at current stakes).
 *
 * Every concept is a semantic cell:
 *   - Chess pieces: LINEAR cells (cannot be duplicated)
 *   - Doubling cube: LINEAR cell (exactly one, ownership transfers)
 *   - Board state: RELEVANT cell (DAG history)
 *   - Move legality: compiled Lisp policies → opcodes
 *   - Cube actions: compiled Lisp policies → opcodes
 *
 * Strategy layer:
 *   - CubeStrategy interface for pluggable cube decision-making
 *   - PositionDistribution for win probability with confidence intervals
 *   - OpponentModel for psychological/behavioral modeling
 *   - Four reference strategies: Optimal, Bluffer, Shark, Turtle
 *   - HeuristicEvaluator and MonteCarloEvaluator for position assessment
 */

// ── Core Engine ──────────────────────────────────────────────────
export { StakesChessEngine } from './engine';

// ── Types ────────────────────────────────────────────────────────
export {
  type DoublingCube,
  type CubeValue,
  type CubeState,
  type CubeAction,
  type CubeActionResult,
  type StakesGameResult,
  type StakesGameStatus,
  type StakesChessBoard,
  CUBE_VALUES,
  CUBE_STATE_MACHINE,
  nextCubeValue,
} from './types';

// ── Policies ─────────────────────────────────────────────────────
export {
  DOUBLE_OFFER_POLICY,
  TAKE_POLICY,
  DROP_POLICY,
  compileCubePolicies,
} from './policies';

// ── Host Functions ───────────────────────────────────────────────
export { registerCubeHostFunctions } from './host-functions';

// ── Strategy ─────────────────────────────────────────────────────
export {
  type CubeStrategy,
  type CubeDecision,
  type OpponentModel,
  type PositionDistribution,
  OptimalStrategy,
  BlufferStrategy,
  SharkStrategy,
  TurtleStrategy,
  defaultOpponentModel,
  engineOpponentModel,
  nervousHumanModel,
} from './strategy';

// ── Evaluator ────────────────────────────────────────────────────
export {
  type PositionEvaluator,
  HeuristicEvaluator,
  MonteCarloEvaluator,
} from './evaluator';

```
