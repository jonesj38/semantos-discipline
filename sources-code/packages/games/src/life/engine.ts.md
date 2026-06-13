---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/life/engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.407687+00:00
---

# packages/games/src/life/engine.ts

```ts
/**
 * GameOfLifeEngine — Conway's Game of Life via semantic cells.
 *
 * Each alive cell is an AFFINE cell (created each generation, consumed on death).
 * The board is a RELEVANT cell. Generations form a DAG linked by previousBoardCellId.
 *
 * Conway's rules are enforced by a Lisp policy compiled to opcodes and
 * evaluated in the WASM cell engine via OP_CALLHOST:
 *   (or (and (alive?) (neighbors-2-or-3?))
 *       (and (dead?) (neighbors-eq-3?)))
 */

import { GameCellEngine, type CreateOptions } from '../../../game-sdk/src/engine';
import { GameEntityType } from '../../../game-sdk/src/types';
import { HostFunctionRegistry } from '@semantos/cell-engine';
import { registerLifeHostFunctions } from './host-functions';
import { compileLifePolicy, type CompiledLifePolicy } from './policies';
import type { LifeBoard, LifeCell, LifeStepResult, PatternName } from './types';
import { PATTERNS } from './types';

// ── Linearity Constants ─────────────────────────────────────────

const AFFINE = 2;
const RELEVANT = 3;

// ── Owner ID ────────────────────────────────────────────────────

const LIFE_OWNER = new Uint8Array(16);
LIFE_OWNER[0] = 0x10;

// ── Sparse encoding ────────────────────────────────────────────

function sparseAliveIds(alive: Map<number, LifeCell>): Record<string, string> {
  const map: Record<string, string> = {};
  for (const [pos, cell] of alive) {
    map[String(pos)] = cell.entity.id;
  }
  return map;
}

// ── GameOfLifeEngine ────────────────────────────────────────────

export class GameOfLifeEngine {
  private cellEngine: GameCellEngine;
  private registry: HostFunctionRegistry;
  private policy: CompiledLifePolicy;
  private currentBoard: LifeBoard;
  private boardHistory: string[];
  private consumedCells: Set<string>;
  private previousAlivePositions: Set<number> | null;
  private lastBoardCell: Uint8Array | null;

  private constructor(
    cellEngine: GameCellEngine,
    registry: HostFunctionRegistry,
    policy: CompiledLifePolicy,
    board: LifeBoard,
    boardCellBytes: Uint8Array,
  ) {
    this.cellEngine = cellEngine;
    this.registry = registry;
    this.policy = policy;
    this.currentBoard = board;
    this.boardHistory = [board.cellId];
    this.consumedCells = new Set();
    this.previousAlivePositions = null;
    this.lastBoardCell = boardCellBytes;
  }

  /**
   * Create a new Game of Life with the given dimensions.
   * Registers host functions, compiles Conway policy to WASM opcodes.
   * Board starts empty — use seed() or setAlive() to populate.
   */
  static async create(width = 20, height = 20, opts?: CreateOptions): Promise<GameOfLifeEngine> {
    const registry = new HostFunctionRegistry();
    registerLifeHostFunctions(registry);

    const engine = await GameCellEngine.create({
      ...opts,
      hostRegistry: registry,
    } as CreateOptions & { hostRegistry: HostFunctionRegistry });

    const policy = compileLifePolicy();

    const boardEntity = engine.createEntity({
      entityType: GameEntityType.STRUCTURE,
      ownerId: LIFE_OWNER,
      linearity: RELEVANT,
      metadata: {
        domain: 'game-of-life',
        width,
        height,
        generation: 0,
        alive: {},
      },
      state: 'running',
    });

    const board: LifeBoard = {
      cellId: boardEntity.id,
      width,
      height,
      generation: 0,
      alive: new Map(),
      previousBoardCellId: null,
    };

    return new GameOfLifeEngine(engine, registry, policy, board, boardEntity.cell);
  }

  /** Get the current board state. */
  getBoard(): LifeBoard {
    return this.currentBoard;
  }

  /** Get the generation history (board cell IDs). */
  history(): string[] {
    return [...this.boardHistory];
  }

  /** Current population count. */
  population(): number {
    return this.currentBoard.alive.size;
  }

  /** Current generation number. */
  generation(): number {
    return this.currentBoard.generation;
  }

  // ── Seeding ──────────────────────────────────────────────────

  /** Set a single cell alive at (row, col). */
  setAlive(row: number, col: number): void {
    const b = this.currentBoard;
    if (row < 0 || row >= b.height || col < 0 || col >= b.width) return;

    const pos = row * b.width + col;
    if (b.alive.has(pos)) return;

    const entity = this.cellEngine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: LIFE_OWNER,
      linearity: AFFINE,
      metadata: { domain: 'life-cell', row, col, generation: b.generation },
      state: 'alive',
    });

    b.alive.set(pos, { entity, position: pos });
  }

  /** Seed a named pattern centered at (row, col). */
  seed(pattern: PatternName, row: number, col: number): void {
    const offsets = PATTERNS[pattern];
    if (!offsets) throw new Error(`Unknown pattern: ${pattern}`);
    for (const [dr, dc] of offsets) {
      this.setAlive(row + dr, col + dc);
    }
  }

  /** Seed random cells with the given density (0-1). */
  seedRandom(density = 0.3): void {
    const b = this.currentBoard;
    for (let r = 0; r < b.height; r++) {
      for (let c = 0; c < b.width; c++) {
        if (Math.random() < density) {
          this.setAlive(r, c);
        }
      }
    }
  }

  // ── WASM Policy Evaluation ───────────────────────────────────

  /**
   * Evaluate Conway's rule for a single cell via OP_CALLHOST.
   * Returns true if the cell should be alive in the next generation.
   */
  private isAliveNextGen(position: number, isAlive: boolean, neighborCount: number): boolean {
    this.registry.setContext({
      position,
      isAlive,
      neighborCount,
    });

    const result = this.cellEngine.evaluatePolicy(this.policy.conway.scriptBytes);
    this.registry.clearContext();
    return result;
  }

  // ── Simulation ───────────────────────────────────────────────

  /** Advance one generation. Returns the step result. */
  step(): LifeStepResult {
    const b = this.currentBoard;
    const { width, height } = b;

    // Count neighbors for each cell that matters
    const neighborCounts = new Map<number, number>();

    for (const [pos] of b.alive) {
      const row = Math.floor(pos / width);
      const col = pos % width;

      for (let dr = -1; dr <= 1; dr++) {
        for (let dc = -1; dc <= 1; dc++) {
          if (dr === 0 && dc === 0) continue;
          const nr = row + dr;
          const nc = col + dc;
          if (nr < 0 || nr >= height || nc < 0 || nc >= width) continue;
          const npos = nr * width + nc;
          neighborCounts.set(npos, (neighborCounts.get(npos) ?? 0) + 1);
        }
      }
    }

    // Apply Conway's rule via WASM policy for each candidate cell
    const nextAlive = new Map<number, LifeCell>();
    let born = 0;
    let died = 0;

    for (const [pos, count] of neighborCounts) {
      const wasAlive = b.alive.has(pos);
      const willBeAlive = this.isAliveNextGen(pos, wasAlive, count);

      if (willBeAlive && wasAlive) {
        // Survives — keep existing AFFINE cell
        nextAlive.set(pos, b.alive.get(pos)!);
      } else if (willBeAlive && !wasAlive) {
        // Birth — create new AFFINE cell
        const row = Math.floor(pos / width);
        const col = pos % width;
        const entity = this.cellEngine.createEntity({
          entityType: GameEntityType.ITEM,
          ownerId: LIFE_OWNER,
          linearity: AFFINE,
          metadata: { domain: 'life-cell', row, col, generation: b.generation + 1 },
          state: 'alive',
        });
        nextAlive.set(pos, { entity, position: pos });
        born++;
      }
    }

    // Consume dead cells (AFFINE destruction)
    for (const [pos, cell] of b.alive) {
      if (!nextAlive.has(pos)) {
        this.consumedCells.add(cell.entity.id);
        died++;
      }
    }

    // Create new board cell (DAG append — prevCell chains binary header hashes)
    const boardEntity = this.cellEngine.createEntity({
      entityType: GameEntityType.STRUCTURE,
      ownerId: LIFE_OWNER,
      linearity: RELEVANT,
      metadata: {
        domain: 'game-of-life',
        width,
        height,
        generation: b.generation + 1,
        alive: sparseAliveIds(nextAlive),
        previousBoardCellId: b.cellId,
      },
      state: 'running',
      prevCell: this.lastBoardCell ?? undefined,
    });

    const newBoard: LifeBoard = {
      cellId: boardEntity.id,
      width,
      height,
      generation: b.generation + 1,
      alive: nextAlive,
      previousBoardCellId: b.cellId,
    };

    this.previousAlivePositions = new Set(b.alive.keys());
    this.currentBoard = newBoard;
    this.lastBoardCell = boardEntity.cell;
    this.boardHistory.push(boardEntity.id);

    return {
      board: newBoard,
      born,
      died,
      generation: newBoard.generation,
      population: nextAlive.size,
    };
  }

  /** Run multiple generations. Returns results for each step. */
  run(steps: number): LifeStepResult[] {
    const results: LifeStepResult[] = [];
    for (let i = 0; i < steps; i++) {
      results.push(this.step());
      if (this.population() === 0) break;
    }
    return results;
  }

  /** Check if the board has stabilized (identical to previous generation). */
  isStable(): boolean {
    if (!this.previousAlivePositions) return false;
    const current = new Set(this.currentBoard.alive.keys());
    if (current.size !== this.previousAlivePositions.size) return false;
    for (const p of current) {
      if (!this.previousAlivePositions.has(p)) return false;
    }
    return true;
  }
}

```
