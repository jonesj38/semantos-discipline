---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/go/engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.413458+00:00
---

# packages/games/src/go/engine.ts

```ts
/**
 * SemanticGoEngine -- full Go via semantic cells and compiled policies.
 *
 * Every stone is an AFFINE cell. The board is a RELEVANT cell.
 * Move legality is enforced by a Lisp policy compiled to opcodes
 * and evaluated in the WASM cell engine via OP_CALLHOST.
 * Game history is a DAG of board cells linked by previousBoardCellId.
 */

import { GameCellEngine, type CreateOptions } from '../../../game-sdk/src/engine';
import { GameEntityType, type GameEntity } from '../../../game-sdk/src/types';
import { HostFunctionRegistry } from '@semantos/cell-engine';
import {
  registerGoHostFunctions,
  getAdjacentIntersections,
  getGroup,
  getLiberties,
} from './host-functions';
import { compileGoPolicy, type CompiledGoPolicy } from './policies';
import type {
  GoStone,
  GoBoard,
  GoGameStatus,
  GoMoveResult,
  GoScore,
  StoneColor,
  BoardSize,
} from './types';

// -- Linearity Constants --------------------------------------------------

const AFFINE = 2;
const RELEVANT = 3;

// -- Owner IDs (16-byte identifiers for black/white) ----------------------

const BLACK_OWNER = new Uint8Array(16);
BLACK_OWNER[0] = 0x01;
const WHITE_OWNER = new Uint8Array(16);
WHITE_OWNER[0] = 0x02;

function ownerForColor(c: StoneColor): Uint8Array {
  return c === 'black' ? BLACK_OWNER : WHITE_OWNER;
}

// -- Board Slot (lightweight representation for host function context) ----

type BoardSlot = { color: string } | null;

function boardToSlots(board: GoBoard): BoardSlot[] {
  return board.intersections.map(s =>
    s ? { color: s.color } : null,
  );
}

// -- Sparse stone ID encoding (keeps board metadata within payload limit) --

function sparseStoneIds(intersections: (GoStone | null)[]): Record<string, string> {
  const map: Record<string, string> = {};
  for (let i = 0; i < intersections.length; i++) {
    const s = intersections[i];
    if (s) map[String(i)] = s.entity.id;
  }
  return map;
}

// -- SemanticGoEngine -----------------------------------------------------

export class SemanticGoEngine {
  private cellEngine: GameCellEngine;
  private registry: HostFunctionRegistry;
  private policy: CompiledGoPolicy;
  private currentBoard: GoBoard;
  private boardHistory: string[];
  private lastBoardCell: Uint8Array | null;
  private consumedCells: Set<string>;
  private consecutivePasses: number;
  private _status: GoGameStatus;

  private constructor(
    cellEngine: GameCellEngine,
    registry: HostFunctionRegistry,
    policy: CompiledGoPolicy,
    board: GoBoard,
    boardCellBytes: Uint8Array,
  ) {
    this.cellEngine = cellEngine;
    this.registry = registry;
    this.policy = policy;
    this.currentBoard = board;
    this.boardHistory = [board.cellId];
    this.lastBoardCell = boardCellBytes;
    this.consumedCells = new Set();
    this.consecutivePasses = 0;
    this._status = 'playing';
  }

  /** Initialize a new Go game with an empty board. */
  static async create(size: BoardSize = 19, opts?: CreateOptions): Promise<SemanticGoEngine> {
    const registry = new HostFunctionRegistry();
    registerGoHostFunctions(registry);

    const engine = await GameCellEngine.create({
      ...opts,
      hostRegistry: registry,
    } as CreateOptions & { hostRegistry: HostFunctionRegistry });

    const policy = compileGoPolicy();

    const totalIntersections = size * size;
    const intersections: (GoStone | null)[] = new Array(totalIntersections).fill(null);

    // Create board cell (RELEVANT -- can be referenced multiple times for history)
    const boardEntity = engine.createEntity({
      entityType: GameEntityType.STRUCTURE,
      ownerId: BLACK_OWNER,
      linearity: RELEVANT,
      metadata: {
        domain: 'go-board',
        size,
        capturedBlack: 0,
        capturedWhite: 0,
        koPoint: null,
        stones: {},
      },
      state: 'playing',
    });

    const board: GoBoard = {
      cellId: boardEntity.id,
      size,
      intersections,
      capturedBlack: 0,
      capturedWhite: 0,
      koPoint: null,
      previousBoardCellId: null,
    };

    return new SemanticGoEngine(engine, registry, policy, board, boardEntity.cell);
  }

  /** Get the current board state. */
  getBoard(): GoBoard {
    return this.currentBoard;
  }

  /** Get the game status. */
  status(): GoGameStatus {
    return this._status;
  }

  /** Get the cell DAG history (board cell IDs from oldest to newest). */
  history(): string[] {
    return [...this.boardHistory];
  }

  /**
   * Place a stone at the given intersection.
   * Validates via compiled Lisp policy, handles captures, creates new board cell.
   */
  play(intersection: number, color: StoneColor): GoMoveResult {
    if (this._status !== 'playing') {
      throw new Error(`Cannot play: game status is '${this._status}'`);
    }

    const b = this.currentBoard;
    const totalIntersections = b.size * b.size;

    if (intersection < 0 || intersection >= totalIntersections) {
      throw new Error(`Invalid intersection: ${intersection} (board is ${b.size}x${b.size})`);
    }

    // Validate via compiled Lisp policy (WASM execution)
    if (!this.isPolicyLegal(intersection, color)) {
      throw new Error(`Illegal move at intersection ${intersection}`);
    }

    // Reset consecutive passes
    this.consecutivePasses = 0;

    // Create AFFINE stone cell
    const stoneEntity = this.cellEngine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: ownerForColor(color),
      linearity: AFFINE,
      metadata: {
        color,
        intersection,
        domain: 'go-stone',
      },
      state: 'active',
    });

    const stone: GoStone = {
      entity: stoneEntity,
      color,
      intersection,
    };

    // Clone intersections
    const newIntersections: (GoStone | null)[] = [...b.intersections];
    newIntersections[intersection] = stone;

    // Handle captures: check opponent groups adjacent to placed stone
    const opponent: StoneColor = color === 'black' ? 'white' : 'black';
    const captured: GoStone[] = [];
    const slots = newIntersections.map(s => s ? { color: s.color } : null);

    const checkedGroups = new Set<number>();
    for (const adj of getAdjacentIntersections(intersection, b.size)) {
      if (checkedGroups.has(adj)) continue;
      const slot = slots[adj];
      if (slot && slot.color === opponent) {
        const group = getGroup(adj, opponent, slots, b.size);
        // Mark all stones in group as checked
        for (const idx of group) checkedGroups.add(idx);
        const liberties = getLiberties(group, slots, b.size);
        if (liberties.size === 0) {
          // Capture this group
          for (const idx of group) {
            const capturedStone = newIntersections[idx]!;
            captured.push(capturedStone);
            // Consume the captured stone cell (AFFINE destruction)
            this.consumedCells.add(capturedStone.entity.id);
            newIntersections[idx] = null;
            slots[idx] = null;
          }
        }
      }
    }

    // Update capture counts
    let newCapturedBlack = b.capturedBlack;
    let newCapturedWhite = b.capturedWhite;
    for (const cap of captured) {
      if (cap.color === 'black') newCapturedBlack++;
      else newCapturedWhite++;
    }

    // Determine ko point
    // Ko: exactly one stone captured AND the capturing stone has exactly one liberty
    let newKoPoint: number | null = null;
    if (captured.length === 1) {
      const capturingSlots = newIntersections.map(s => s ? { color: s.color } : null);
      const capturingGroup = getGroup(intersection, color, capturingSlots, b.size);
      if (capturingGroup.size === 1) {
        const capturingLiberties = getLiberties(capturingGroup, capturingSlots, b.size);
        if (capturingLiberties.size === 1) {
          newKoPoint = captured[0].intersection;
        }
      }
    }

    // Create new board cell (DAG append — prevCell chains binary header hashes)
    const boardEntity = this.cellEngine.createEntity({
      entityType: GameEntityType.STRUCTURE,
      ownerId: BLACK_OWNER,
      linearity: RELEVANT,
      metadata: {
        domain: 'go-board',
        size: b.size,
        capturedBlack: newCapturedBlack,
        capturedWhite: newCapturedWhite,
        koPoint: newKoPoint,
        stones: sparseStoneIds(newIntersections),
        previousBoardCellId: b.cellId,
      },
      state: 'playing',
      prevCell: this.lastBoardCell ?? undefined,
    });

    const newBoard: GoBoard = {
      cellId: boardEntity.id,
      size: b.size,
      intersections: newIntersections,
      capturedBlack: newCapturedBlack,
      capturedWhite: newCapturedWhite,
      koPoint: newKoPoint,
      previousBoardCellId: b.cellId,
    };

    this.currentBoard = newBoard;
    this.lastBoardCell = boardEntity.cell;
    this.boardHistory.push(boardEntity.id);

    return {
      board: newBoard,
      captured,
      status: this._status,
    };
  }

  /**
   * Pass (skip turn). Two consecutive passes transition to scoring.
   */
  pass(color: StoneColor): GoMoveResult {
    if (this._status !== 'playing') {
      throw new Error(`Cannot pass: game status is '${this._status}'`);
    }

    this.consecutivePasses++;

    const b = this.currentBoard;

    // Create new board cell with same state but no ko point (pass clears ko)
    const boardEntity = this.cellEngine.createEntity({
      entityType: GameEntityType.STRUCTURE,
      ownerId: BLACK_OWNER,
      linearity: RELEVANT,
      metadata: {
        domain: 'go-board',
        size: b.size,
        capturedBlack: b.capturedBlack,
        capturedWhite: b.capturedWhite,
        koPoint: null,
        stones: sparseStoneIds(b.intersections),
        previousBoardCellId: b.cellId,
        pass: color,
      },
      state: this.consecutivePasses >= 2 ? 'scoring' : 'playing',
      prevCell: this.lastBoardCell ?? undefined,
    });

    const newBoard: GoBoard = {
      cellId: boardEntity.id,
      size: b.size,
      intersections: [...b.intersections],
      capturedBlack: b.capturedBlack,
      capturedWhite: b.capturedWhite,
      koPoint: null,
      previousBoardCellId: b.cellId,
    };

    this.currentBoard = newBoard;
    this.lastBoardCell = boardEntity.cell;
    this.boardHistory.push(boardEntity.id);

    if (this.consecutivePasses >= 2) {
      this._status = 'scoring';
    }

    return {
      board: newBoard,
      captured: [],
      status: this._status,
    };
  }

  /** Get all legal intersections for a given color. */
  legalMoves(color: StoneColor): number[] {
    if (this._status !== 'playing') return [];

    const b = this.currentBoard;
    const total = b.size * b.size;
    const legal: number[] = [];

    for (let i = 0; i < total; i++) {
      if (this.isPolicyLegal(i, color)) {
        legal.push(i);
      }
    }

    return legal;
  }

  /**
   * Score the game using Chinese rules (area counting).
   * Komi: 7.5 points for white.
   */
  score(komi: number = 7.5): GoScore {
    const b = this.currentBoard;
    const total = b.size * b.size;
    const slots = boardToSlots(b);

    // Count stones on board
    let blackStones = 0;
    let whiteStones = 0;
    for (let i = 0; i < total; i++) {
      if (slots[i]?.color === 'black') blackStones++;
      else if (slots[i]?.color === 'white') whiteStones++;
    }

    // Determine territory: empty intersections reachable only by one color
    const visited = new Array(total).fill(false);
    let blackTerritory = 0;
    let whiteTerritory = 0;

    for (let i = 0; i < total; i++) {
      if (visited[i] || slots[i] !== null) continue;

      // Flood-fill to find connected empty region
      const region: number[] = [];
      const stack = [i];
      let touchesBlack = false;
      let touchesWhite = false;

      while (stack.length > 0) {
        const idx = stack.pop()!;
        if (visited[idx]) continue;
        if (slots[idx] !== null) {
          if (slots[idx]!.color === 'black') touchesBlack = true;
          else touchesWhite = true;
          continue;
        }
        visited[idx] = true;
        region.push(idx);
        for (const adj of getAdjacentIntersections(idx, b.size)) {
          if (!visited[adj]) {
            stack.push(adj);
          }
        }
      }

      // Territory belongs to one color only if it touches only that color
      if (touchesBlack && !touchesWhite) {
        blackTerritory += region.length;
      } else if (touchesWhite && !touchesBlack) {
        whiteTerritory += region.length;
      }
      // Neutral (dame) territory is not counted
    }

    // Chinese scoring: area = territory + stones on board
    const blackTotal = blackTerritory + blackStones;
    const whiteTotal = whiteTerritory + whiteStones + komi;
    const result = blackTotal - whiteTotal;

    this._status = 'finished';

    return {
      blackTerritory,
      whiteTerritory,
      blackStones,
      whiteStones,
      capturedBlack: b.capturedBlack,
      capturedWhite: b.capturedWhite,
      blackTotal,
      whiteTotal,
      komi,
      result,
    };
  }

  /** Check if a cell has been consumed (captured). */
  isConsumed(cellId: string): boolean {
    return this.consumedCells.has(cellId);
  }

  /** Get the underlying GameCellEngine. */
  getCellEngine(): GameCellEngine {
    return this.cellEngine;
  }

  // -- Policy Evaluation (WASM) -------------------------------------------

  private isPolicyLegal(intersection: number, color: StoneColor): boolean {
    const b = this.currentBoard;
    const slots = boardToSlots(b);

    // Set the frozen evaluation context
    this.registry.setContext({
      intersection,
      color,
      board: slots,
      koPoint: b.koPoint,
      size: b.size,
    });

    // Evaluate via WASM
    const result = this.cellEngine.evaluatePolicy(this.policy.placement.scriptBytes);
    this.registry.clearContext();
    return result;
  }
}

```
