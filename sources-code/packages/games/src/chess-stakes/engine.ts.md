---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/chess-stakes/engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.415485+00:00
---

# packages/games/src/chess-stakes/engine.ts

```ts
/**
 * StakesChessEngine — Chess with Backgammon Doubling Cube.
 *
 * Wraps SemanticChessEngine and adds a doubling cube as a LINEAR cell.
 * On your turn, before moving, you can offer to double the stakes.
 * Your opponent must take (accept, stakes double, they get the cube)
 * or drop (decline, forfeit at current stakes).
 *
 * The cube is a semantic entity with the same linearity enforcement
 * as chess pieces:
 *   - LINEAR: exactly one cube, cannot be duplicated
 *   - Ownership transfers via the SDK transfer primitive
 *   - State transitions governed by compiled Lisp policies
 *   - All cube predicates are zero-arity host functions
 *
 * Turn flow:
 *   1. Active player's turn begins in 'cube-or-move' phase
 *   2. Player can either:
 *      a. Offer a double → phase becomes 'awaiting-response'
 *         - Opponent takes → cube transfers, phase becomes 'must-move'
 *         - Opponent drops → game ends (forfeit at current stakes)
 *      b. Make a chess move → normal chess engine handles it
 *   3. Turn passes to opponent
 */

import { GameCellEngine, type CreateOptions } from '../../../game-sdk/src/engine';
import { GameEntityType } from '../../../game-sdk/src/types';
import { HostFunctionRegistry } from '@semantos/cell-engine';
import { registerChessHostFunctions } from '../chess/host-functions';
import { SemanticChessEngine } from '../chess/engine';
import type { Color, PieceType, GameStatus as ChessGameStatus } from '../chess/types';
import { registerCubeHostFunctions } from './host-functions';
import { compileCubePolicies, type CompiledCubePolicies } from './policies';
import {
  type DoublingCube,
  type CubeValue,
  type CubeState,
  type CubeAction,
  type CubeActionResult,
  type StakesGameResult,
  type StakesGameStatus,
  type StakesChessBoard,
  nextCubeValue,
} from './types';
import type { CubeStrategy, CubeDecision, OpponentModel, PositionDistribution } from './strategy';
import type { PositionEvaluator } from './evaluator';

// ── Linearity Constants ──────────────────────────────────────────

const LINEAR = 1;

// ── Owner IDs (must match chess engine's owner IDs) ──────────────

const WHITE_OWNER = new Uint8Array(16);
WHITE_OWNER[0] = 0x01;
const BLACK_OWNER = new Uint8Array(16);
BLACK_OWNER[0] = 0x02;

function ownerForColor(c: Color): Uint8Array {
  return c === 'white' ? WHITE_OWNER : BLACK_OWNER;
}

function oppositeColor(c: Color): Color {
  return c === 'white' ? 'black' : 'white';
}

// ── StakesChessEngine ────────────────────────────────────────────

export class StakesChessEngine {
  private chessEngine: SemanticChessEngine;
  private cellEngine: GameCellEngine;
  private registry: HostFunctionRegistry;
  private cubePolicies: CompiledCubePolicies;
  private cube: DoublingCube;
  private phase: 'cube-or-move' | 'awaiting-response' | 'must-move';

  /** Pluggable cube strategies for each player (null = manual/human). */
  private strategies: { white: CubeStrategy | null; black: CubeStrategy | null };
  /** Opponent models maintained by strategies. */
  private opponentModels: { white: OpponentModel; black: OpponentModel };
  /** Position evaluator for computing win probability distributions. */
  private evaluator: PositionEvaluator | null;

  private constructor(
    chessEngine: SemanticChessEngine,
    cellEngine: GameCellEngine,
    registry: HostFunctionRegistry,
    cubePolicies: CompiledCubePolicies,
    cube: DoublingCube,
  ) {
    this.chessEngine = chessEngine;
    this.cellEngine = cellEngine;
    this.registry = registry;
    this.cubePolicies = cubePolicies;
    this.cube = cube;
    this.phase = 'cube-or-move';
    this.strategies = { white: null, black: null };
    this.opponentModels = {
      white: { evaluationAccuracy: 0.7, riskTolerance: 0.5, tiltFactor: 0, estimatedOpponentWinProb: null },
      black: { evaluationAccuracy: 0.7, riskTolerance: 0.5, tiltFactor: 0, estimatedOpponentWinProb: null },
    };
    this.evaluator = null;
  }

  /**
   * Create a new stakes chess game.
   * Initializes standard chess + a LINEAR doubling cube cell (value 1, centered).
   */
  static async create(opts?: CreateOptions): Promise<StakesChessEngine> {
    // Create a shared registry with BOTH chess and cube predicates
    const registry = new HostFunctionRegistry();
    registerChessHostFunctions(registry);
    registerCubeHostFunctions(registry);

    // Create the underlying chess engine
    const chessEngine = await SemanticChessEngine.create({
      ...opts,
      hostRegistry: registry,
    } as CreateOptions & { hostRegistry: HostFunctionRegistry });

    const cellEngine = chessEngine.getCellEngine();

    // Compile cube policies
    const cubePolicies = compileCubePolicies();

    // Create the doubling cube as a LINEAR cell
    // Starts centered (no holder), value 1
    const cubeEntity = cellEngine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: WHITE_OWNER, // initial "owner" is arbitrary when centered
      linearity: LINEAR,
      metadata: {
        domain: 'chess-stakes',
        type: 'doubling-cube',
        value: 1,
        state: 'centered',
        holder: null,
        offeredBy: null,
      },
      state: 'centered',
    });

    const cube: DoublingCube = {
      entity: cubeEntity,
      value: 1,
      state: 'centered',
      holder: null,
      offeredBy: null,
    };

    return new StakesChessEngine(chessEngine, cellEngine, registry, cubePolicies, cube);
  }

  // ── Queries ─────────────────────────────────────────────────

  /** Get the full stakes board state. */
  getState(): StakesChessBoard {
    return {
      chess: this.chessEngine.getBoard(),
      cube: this.cube,
      phase: this.phase,
    };
  }

  /** Get the current cube state. */
  getCube(): DoublingCube {
    return this.cube;
  }

  /** Get the current turn phase. */
  getPhase(): 'cube-or-move' | 'awaiting-response' | 'must-move' {
    return this.phase;
  }

  /** Get the active color (whose turn it is to act). */
  activeColor(): Color {
    if (this.phase === 'awaiting-response') {
      // The responder is the opponent of whoever offered
      return oppositeColor(this.cube.offeredBy!);
    }
    return this.chessEngine.getBoard().activeColor;
  }

  /** Get game status including stakes-specific states. */
  status(): StakesGameStatus {
    return this.chessEngine.status();
  }

  /** Can the active player offer a double right now? */
  canDouble(): boolean {
    if (this.phase !== 'cube-or-move') return false;
    return this.evaluateCubePolicy('doubleOffer');
  }

  /** Get legal chess moves (only available in cube-or-move or must-move phase). */
  legalMoves(square: number): number[] {
    if (this.phase === 'awaiting-response') return [];
    return this.chessEngine.legalMoves(square);
  }

  // ── Actions ─────────────────────────────────────────────────

  /**
   * Execute a cube or move action.
   *
   * Turn flow:
   *   Phase 'cube-or-move':
   *     - { type: 'double' } → offer double, phase → 'awaiting-response'
   *     - { type: 'move', ... } → make chess move, phase → 'cube-or-move' (next turn)
   *   Phase 'awaiting-response':
   *     - { type: 'take' } → accept double, phase → 'must-move' (offerer must now move)
   *     - { type: 'drop' } → forfeit, game ends
   *   Phase 'must-move':
   *     - { type: 'move', ... } → make chess move, phase → 'cube-or-move' (next turn)
   */
  act(action: CubeAction): CubeActionResult {
    switch (action.type) {
      case 'double':
        return this.offerDouble();
      case 'take':
        return this.takeDouble();
      case 'drop':
        return this.dropDouble();
      case 'move':
        return this.makeMove(action.from, action.to, action.promotion);
    }
  }

  // ── Double Offer ────────────────────────────────────────────

  private offerDouble(): CubeActionResult {
    if (this.phase !== 'cube-or-move') {
      throw new Error(`Cannot offer double in phase '${this.phase}'`);
    }

    // Evaluate the double-offer policy via WASM
    if (!this.evaluateCubePolicy('doubleOffer')) {
      throw new Error('Double offer rejected by policy');
    }

    const offerer = this.chessEngine.getBoard().activeColor;
    const newValue = nextCubeValue(this.cube.value);
    if (newValue === null) {
      throw new Error('Cube already at maximum value (64)');
    }

    // Transition cube cell: state → offered
    const updatedEntity = this.cellEngine.updateEntity(this.cube.entity, {
      metadata: {
        ...this.cube.entity.metadata,
        state: 'offered',
        offeredBy: offerer,
        proposedValue: newValue,
      },
      state: 'offered',
    });

    this.cube = {
      entity: updatedEntity,
      value: this.cube.value, // value doesn't change until taken
      state: 'offered',
      holder: this.cube.holder,
      offeredBy: offerer,
    };

    this.phase = 'awaiting-response';

    return {
      cube: this.cube,
      board: this.chessEngine.getBoard(),
      gameResult: null,
      description: `${offerer} offers to double the stakes to ${newValue}`,
    };
  }

  // ── Take (Accept Double) ───────────────────────────────────

  private takeDouble(): CubeActionResult {
    if (this.phase !== 'awaiting-response') {
      throw new Error(`Cannot take in phase '${this.phase}'`);
    }

    // Evaluate the take policy via WASM
    if (!this.evaluateCubePolicy('take')) {
      throw new Error('Take rejected by policy');
    }

    const offerer = this.cube.offeredBy!;
    const taker = oppositeColor(offerer);
    const newValue = nextCubeValue(this.cube.value)!;

    // Transfer cube ownership to taker (LINEAR transfer)
    // The cube cell's ownerId is rewritten to the taker
    const updatedEntity = this.cellEngine.updateEntity(this.cube.entity, {
      metadata: {
        ...this.cube.entity.metadata,
        state: 'held',
        value: newValue,
        holder: taker,
        offeredBy: null,
        proposedValue: null,
      },
      state: 'held',
    });

    this.cube = {
      entity: updatedEntity,
      value: newValue,
      state: 'held',
      holder: taker,
      offeredBy: null,
    };

    // After taking, the player who OFFERED the double must now move
    // (they were the active player when they doubled)
    this.phase = 'must-move';

    return {
      cube: this.cube,
      board: this.chessEngine.getBoard(),
      gameResult: null,
      description: `${taker} takes the double. Stakes are now ${newValue}. ${offerer} to move.`,
    };
  }

  // ── Drop (Decline Double → Forfeit) ────────────────────────

  private dropDouble(): CubeActionResult {
    if (this.phase !== 'awaiting-response') {
      throw new Error(`Cannot drop in phase '${this.phase}'`);
    }

    // Evaluate the drop policy via WASM
    if (!this.evaluateCubePolicy('drop')) {
      throw new Error('Drop rejected by policy');
    }

    const offerer = this.cube.offeredBy!;
    const dropper = oppositeColor(offerer);

    // Game is over — dropper forfeits at CURRENT cube value
    // (the proposed double value is NOT applied since they declined)
    const gameResult: StakesGameResult = {
      status: 'forfeited',
      winner: offerer,
      cubeValue: this.cube.value,
      points: this.cube.value, // forfeit = 1 × cube value
    };

    // Update cube cell to reflect game end
    const updatedEntity = this.cellEngine.updateEntity(this.cube.entity, {
      metadata: {
        ...this.cube.entity.metadata,
        state: 'dropped',
        droppedBy: dropper,
        finalValue: this.cube.value,
      },
      state: 'dropped',
    });

    this.cube = {
      entity: updatedEntity,
      value: this.cube.value,
      state: 'offered', // terminal — game is over
      holder: this.cube.holder,
      offeredBy: this.cube.offeredBy,
    };

    return {
      cube: this.cube,
      board: this.chessEngine.getBoard(),
      gameResult,
      description: `${dropper} drops. ${offerer} wins ${this.cube.value} point${this.cube.value > 1 ? 's' : ''}.`,
    };
  }

  // ── Chess Move ─────────────────────────────────────────────

  private makeMove(from: number, to: number, promotion?: PieceType): CubeActionResult {
    if (this.phase === 'awaiting-response') {
      throw new Error('Cannot move while a double is pending — must take or drop');
    }

    // Execute the chess move through the semantic chess engine
    const moveResult = this.chessEngine.move(from, to, promotion);

    // Check if the chess game ended
    let gameResult: StakesGameResult | null = null;
    if (moveResult.status === 'checkmate') {
      const winner = oppositeColor(moveResult.board.activeColor);
      gameResult = {
        status: 'checkmate',
        winner,
        cubeValue: this.cube.value,
        points: this.cube.value, // checkmate = 1 × cube value
      };
    } else if (moveResult.status === 'stalemate' || moveResult.status === 'draw') {
      gameResult = {
        status: moveResult.status,
        winner: null,
        cubeValue: this.cube.value,
        points: 0, // draws are 0 points regardless of cube
      };
    }

    // Reset to cube-or-move for the next player's turn
    this.phase = 'cube-or-move';

    const description = gameResult
      ? `${moveResult.notation} — ${gameResult.status}! ${gameResult.winner ? gameResult.winner + ' wins ' + gameResult.points + ' points' : 'Draw'}.`
      : `${moveResult.notation}`;

    return {
      cube: this.cube,
      board: moveResult.board,
      gameResult,
      description,
    };
  }

  // ── Policy Evaluation ──────────────────────────────────────

  private evaluateCubePolicy(policyName: keyof CompiledCubePolicies): boolean {
    const policy = this.cubePolicies[policyName];
    if (!policy) return false;

    const board = this.chessEngine.getBoard();
    const chessStatus = this.chessEngine.status();

    // Set the frozen evaluation context for cube predicates
    this.registry.setContext({
      // Cube state
      cubeState: this.cube.state,
      cubeHolder: this.cube.holder,
      cubeValue: this.cube.value,
      offeredBy: this.cube.offeredBy,
      // Game state
      activeColor: this.activeColor(),
      respondingColor: this.cube.offeredBy
        ? oppositeColor(this.cube.offeredBy)
        : null,
      gameStatus: chessStatus,
    });

    const result = this.cellEngine.evaluatePolicy(policy.scriptBytes);
    this.registry.clearContext();
    return result;
  }

  // ── Strategy Configuration ──────────────────────────────────

  /**
   * Set a cube strategy for a player.
   * null = manual mode (human decides via act()).
   */
  setStrategy(color: Color, strategy: CubeStrategy | null): void {
    this.strategies[color] = strategy;
  }

  /** Set the position evaluator used by strategies. */
  setEvaluator(evaluator: PositionEvaluator): void {
    this.evaluator = evaluator;
  }

  /** Set the opponent model for a player (what we believe about them). */
  setOpponentModel(color: Color, model: OpponentModel): void {
    this.opponentModels[color] = model;
  }

  /** Get the current opponent model for a player. */
  getOpponentModel(color: Color): OpponentModel {
    return this.opponentModels[color];
  }

  /**
   * Get the strategy's cube recommendation for the active player.
   *
   * Returns null if no strategy is set for the active player
   * or no evaluator is configured.
   *
   * This is the bridge between the strategy layer and the game:
   * the strategy RECOMMENDS, but act() EXECUTES. A UI could
   * show the recommendation and let the human override it.
   */
  getRecommendation(): CubeDecision | null {
    const color = this.activeColor();
    const strategy = this.strategies[color];
    if (!strategy || !this.evaluator) return null;

    const position = this.evaluator.evaluate(this.chessEngine);
    const opponent = this.opponentModels[oppositeColor(color)];
    const state = this.getState();

    if (this.phase === 'cube-or-move' && this.canDouble()) {
      return strategy.shouldDouble(state, position, opponent);
    }

    if (this.phase === 'awaiting-response') {
      const proposedValue = nextCubeValue(this.cube.value);
      if (proposedValue) {
        return strategy.shouldTake(state, position, opponent, proposedValue);
      }
    }

    return null;
  }

  /**
   * Let the strategy decide and execute the cube action automatically.
   *
   * For engine-vs-engine play:
   *   1. Set strategies for both colors
   *   2. Set an evaluator
   *   3. Call autoAct() each turn — it decides double/take/drop
   *   4. Then make the chess move separately
   *
   * Returns the cube decision and result, or null if no strategy
   * action was taken (proceed to chess move).
   */
  autoAct(): { decision: CubeDecision; result: CubeActionResult } | null {
    const color = this.activeColor();
    const strategy = this.strategies[color];
    if (!strategy || !this.evaluator) return null;

    const position = this.evaluator.evaluate(this.chessEngine);
    const opponent = this.opponentModels[oppositeColor(color)];
    const state = this.getState();

    if (this.phase === 'cube-or-move' && this.canDouble()) {
      const decision = strategy.shouldDouble(state, position, opponent);
      if (decision.action === 'double') {
        const result = this.act({ type: 'double' });

        // Let the opponent's strategy observe this decision
        const oppStrategy = this.strategies[oppositeColor(color)];
        if (oppStrategy?.observeOpponentDecision) {
          this.opponentModels[color] = oppStrategy.observeOpponentDecision(
            decision, position, this.opponentModels[color],
          );
        }

        return { decision, result };
      }
      // Strategy chose not to double — fall through to chess move
      return null;
    }

    if (this.phase === 'awaiting-response') {
      const proposedValue = nextCubeValue(this.cube.value);
      if (!proposedValue) return null;

      const decision = strategy.shouldTake(state, position, opponent, proposedValue);

      if (decision.action === 'take') {
        const result = this.act({ type: 'take' });

        // Let the offerer's strategy observe this decision
        const offererStrategy = this.strategies[oppositeColor(color)];
        if (offererStrategy?.observeOpponentDecision) {
          this.opponentModels[color] = offererStrategy.observeOpponentDecision(
            decision, position, this.opponentModels[color],
          );
        }

        return { decision, result };
      }

      if (decision.action === 'drop') {
        const result = this.act({ type: 'drop' });
        return { decision, result };
      }
    }

    return null;
  }

  // ── Accessors for underlying engines ───────────────────────

  /** Get the underlying chess engine (for FEN export, history, etc.) */
  getChessEngine(): SemanticChessEngine {
    return this.chessEngine;
  }

  /** Get the underlying cell engine. */
  getCellEngine(): GameCellEngine {
    return this.cellEngine;
  }
}

```
