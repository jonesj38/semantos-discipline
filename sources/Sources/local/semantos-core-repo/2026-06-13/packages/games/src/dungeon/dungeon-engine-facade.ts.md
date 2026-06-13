---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/dungeon/dungeon-engine-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.402611+00:00
---

# packages/games/src/dungeon/dungeon-engine-facade.ts

```ts
/**
 * DungeonEngine facade — thin orchestrator that wires the split
 * dungeon modules together behind the legacy `DungeonEngine` shape:
 *
 *   action-dispatcher → handler registry (Move/Attack/Pickup/Use/Open/Descend)
 *   movement-validator → policy gate (WASM kernel via host-functions)
 *   combat-engine     → resolveCombat + applyXpAndLevelUp
 *   inventory-system  → pickup / use / openDoor mutations
 *   floor-generator   → populateFloor (RNG + cell allocation)
 *   board-persister   → DAG-chained RELEVANT board cells
 *   terminal-event-emitter → anchor on dead/victory
 *   fov-system        → fovPort (rot.js by default)
 *   atoms             → boardStateAtom / boardHistoryAtom / consumedCellsAtom
 *
 * Public API matches the legacy `DungeonEngine` class exactly: `create`,
 * `move`, `attack`, `pickup`, `useItem`, `openDoor`, `descend`,
 * `getBoard`, `status`, `history`, `getVisibleTiles`, `getExploredTiles`,
 * `lastPolicyResult`. CLI/host callers see no behavioural change.
 */

import { GameCellEngine, type CreateOptions } from '../../../game-sdk/src/engine';
import { GameEntityType } from '../../../game-sdk/src/types';
import { HostFunctionRegistry } from '@semantos/cell-engine';
import type { PolicyResult } from '../../../policy-runtime/src/types';

import { set } from '@semantos/state';

import {
  dispatchDungeonAction,
  type DispatcherContext,
  type DungeonAction,
} from './action-dispatcher';
import { getDungeonAtoms, type DungeonAtoms } from './atoms';
import { commitBoardSnapshot } from './board-persister';
import { bindDefaultFovProvider } from './default-bindings';
import {
  applyVisibility,
  passableForFloor,
  resolveFovFactory,
  type FovProvider,
} from './fov-system';
import { generateFloor, populateFloor } from './floor-generator';
import { registerDungeonHostFunctions } from './host-functions';
import {
  makePolicyEvaluator,
  type DungeonPolicyEvaluator,
} from './movement-validator';
import { compileDungeonPolicies, type CompiledDungeonPolicies } from './policies';
import {
  DEFAULT_TERMINAL_EVENTS,
  makeTerminalEventEmitter,
  type TerminalEventEmitter,
} from './terminal-event-emitter';
import {
  XP_PER_LEVEL,
  ITEM_TEMPLATES,
  MAX_FLOORS,
  type ActionResult,
  type Direction,
  type DungeonBoard,
  type DungeonFloor,
  type DungeonGameStatus,
  type DungeonItem,
  type DungeonPlayer,
} from './types';

// ── Linearity Constants ────────────────────────────────────────

const RELEVANT = 3;
const AFFINE = 2;

// ── Owner IDs (legacy parity) ──────────────────────────────────

const DUNGEON_OWNER = new Uint8Array(16);
DUNGEON_OWNER[0] = 0x40;

const PLAYER_OWNER = new Uint8Array(16);
PLAYER_OWNER[0] = 0x41;

let nextEngineId = 0;

export interface DungeonEngineCreateOptions extends CreateOptions {
  /** Override the terminal-event list (default: dead + victory). */
  terminalEvents?: readonly DungeonGameStatus[];
}

/**
 * Roguelike dungeon engine — split rebuild. See module docstring for
 * the architectural overview. Public surface is byte-identical with
 * the legacy `engine.ts` `DungeonEngine` class.
 */
export class DungeonEngine {
  private readonly engineId: string;
  private readonly cellEngine: GameCellEngine;
  private readonly registry: HostFunctionRegistry;
  private readonly policies: CompiledDungeonPolicies;
  private readonly policy: DungeonPolicyEvaluator;
  private readonly terminalEmitter: TerminalEventEmitter;
  private readonly atoms: DungeonAtoms;

  private currentBoard: DungeonBoard;
  private boardHistory: string[];
  private consumedCells: Set<string>;
  private lastBoardCell: Uint8Array | null;
  private _status: DungeonGameStatus;

  // FOV state
  private fov: FovProvider;
  private visibleTiles: Set<string>;
  private exploredTiles: Set<string>;

  /**
   * Single mutable context bag the dispatcher writes through.
   * `status` is a real field so the dispatcher's `ctx.status = 'dead'`
   * lands here without bouncing through getters.
   */
  private readonly ctx: DispatcherContext;

  private constructor(args: {
    cellEngine: GameCellEngine;
    registry: HostFunctionRegistry;
    policies: CompiledDungeonPolicies;
    board: DungeonBoard;
    boardCellBytes: Uint8Array;
    terminalEvents?: readonly DungeonGameStatus[];
  }) {
    this.engineId = `dungeon-${nextEngineId++}`;
    this.cellEngine = args.cellEngine;
    this.registry = args.registry;
    this.policies = args.policies;
    this.currentBoard = args.board;
    this.boardHistory = [args.board.cellId];
    this.consumedCells = new Set();
    this.lastBoardCell = args.boardCellBytes;
    this._status = 'playing';
    this.visibleTiles = new Set();
    this.exploredTiles = new Set();

    this.policy = makePolicyEvaluator({
      cellEngine: args.cellEngine,
      registry: args.registry,
      policies: args.policies,
      runtime: args.cellEngine.policyRuntime,
    });

    this.terminalEmitter = makeTerminalEventEmitter({
      anchorEmitter: args.cellEngine.anchorEmitter,
      terminalEvents: args.terminalEvents ?? DEFAULT_TERMINAL_EVENTS,
    });

    this.atoms = getDungeonAtoms(this.engineId);
    set(this.atoms.boardStateAtom, this.currentBoard);
    set(this.atoms.boardHistoryAtom, [...this.boardHistory]);
    set(this.atoms.consumedCellsAtom, new Set(this.consumedCells));
    set(this.atoms.statusAtom, this._status);

    // FOV — bind the default rot.js factory if no test stub is in place.
    bindDefaultFovProvider();
    this.fov = resolveFovFactory()({
      passable: passableForFloor(this.currentBoard.floors[this.currentBoard.floor]),
    });

    // Build the dispatcher context — a flat object the dispatcher
    // treats as mutable runtime state. Methods reference `this`
    // closures so commits stay co-located with the facade.
    const self = this;
    this.ctx = {
      board: this.currentBoard,
      status: this._status,
      consumedCells: this.consumedCells,
      visibleTiles: this.visibleTiles,
      exploredTiles: this.exploredTiles,
      fov: this.fov,
      recomputeFov: () => self.recomputeFov(),
      generateNextFloor: (idx) => self.generateNextFloor(idx),
      commit: (msg) => self.commitAndResult(msg),
      result: (msg) => self.result(msg),
      assertPlaying: () => self.assertPlaying(),
    };

    this.recomputeFov();
  }

  // ── Factory ────────────────────────────────────────────────

  static async create(opts?: DungeonEngineCreateOptions): Promise<DungeonEngine> {
    const registry = new HostFunctionRegistry();
    registerDungeonHostFunctions(registry);

    const engine = await GameCellEngine.create({
      ...opts,
      hostRegistry: registry,
    } as CreateOptions & { hostRegistry: HostFunctionRegistry });

    const policies = compileDungeonPolicies();

    const generated = generateFloor(0, MAX_FLOORS);

    const playerEntity = engine.createEntity({
      entityType: GameEntityType.CHARACTER,
      ownerId: PLAYER_OWNER,
      linearity: RELEVANT,
      metadata: { domain: 'dungeon-player', name: 'Adventurer' },
      state: 'alive',
    });

    const daggerTemplate = ITEM_TEMPLATES.dagger;
    const daggerEntity = engine.createEntity({
      entityType: GameEntityType.ITEM,
      ownerId: PLAYER_OWNER,
      linearity: AFFINE,
      metadata: { domain: 'dungeon-item', ...daggerTemplate },
      state: 'equipped',
    });
    const startingWeapon: DungeonItem = {
      entity: daggerEntity,
      name: daggerTemplate.name,
      category: 'weapon',
      position: generated.playerStart,
      damage: daggerTemplate.damage,
      durability: daggerTemplate.durability,
    };

    const player: DungeonPlayer = {
      entity: playerEntity,
      position: { ...generated.playerStart },
      hp: 30,
      maxHp: 30,
      attack: 2,
      defense: 0,
      level: 1,
      xp: 0,
      xpToLevel: XP_PER_LEVEL,
      gold: 0,
      inventory: [startingWeapon],
      equippedWeapon: startingWeapon,
      equippedArmor: null,
    };

    const floor: DungeonFloor = populateFloor({ engine, generated, floorIndex: 0 });

    const boardEntity = engine.createEntity({
      entityType: GameEntityType.STRUCTURE,
      ownerId: DUNGEON_OWNER,
      linearity: RELEVANT,
      metadata: {
        domain: 'dungeon',
        floor: 0,
        turn: 0,
        playerPos: [player.position.x, player.position.y],
        playerHp: player.hp,
      },
      state: 'playing',
    });

    const board: DungeonBoard = {
      cellId: boardEntity.id,
      floor: 0,
      floors: [floor],
      player,
      turnNumber: 0,
      previousBoardCellId: null,
      messages: ['You enter the dungeon. A dagger gleams in your hand.'],
    };

    return new DungeonEngine({
      cellEngine: engine,
      registry,
      policies,
      board,
      boardCellBytes: boardEntity.cell,
      terminalEvents: opts?.terminalEvents,
    });
  }

  // ── Accessors ──────────────────────────────────────────────

  getBoard(): DungeonBoard { return this.currentBoard; }
  status(): DungeonGameStatus { return this._status; }
  history(): string[] { return [...this.boardHistory]; }
  getVisibleTiles(): Set<string> { return this.visibleTiles; }
  getExploredTiles(): Set<string> { return this.exploredTiles; }

  /** Phase 29.5: Last policy result for audit trail inspection. */
  lastPolicyResult(): PolicyResult | undefined {
    return this.policy.lastResult();
  }

  // ── Public actions (dispatch through dispatcher) ──────────

  move(direction: Direction): ActionResult {
    return this.dispatch({ type: 'move', direction });
  }

  attack(direction: Direction): ActionResult {
    return this.dispatch({ type: 'attack', direction });
  }

  pickup(itemIndex?: number): ActionResult {
    return this.dispatch({ type: 'pickup', itemIndex });
  }

  useItem(itemIndex: number): ActionResult {
    return this.dispatch({ type: 'use', itemIndex });
  }

  openDoor(direction: Direction): ActionResult {
    return this.dispatch({ type: 'open-door', direction });
  }

  descend(): ActionResult {
    return this.dispatch({ type: 'descend' });
  }

  // ── Dispatcher entry ───────────────────────────────────────

  private dispatch(action: DungeonAction): ActionResult {
    // Refresh the context view of board (commits replace the ref)
    // and status (handlers may have flipped to dead/victory previously).
    this.ctx.board = this.currentBoard;
    this.ctx.status = this._status;
    this.ctx.visibleTiles = this.visibleTiles;
    this.ctx.exploredTiles = this.exploredTiles;
    this.ctx.consumedCells = this.consumedCells;
    this.ctx.fov = this.fov;

    return dispatchDungeonAction(
      { ctx: this.ctx, policy: this.policy },
      action,
    );
  }

  // ── Floor generation ──────────────────────────────────────

  private generateNextFloor(floorIndex: number): void {
    const generated = generateFloor(floorIndex, MAX_FLOORS);
    const newFloor = populateFloor({
      engine: this.cellEngine,
      generated,
      floorIndex,
    });
    this.currentBoard.floors[floorIndex] = newFloor;
    this.currentBoard.player.position = { ...generated.playerStart };
    this.fov = resolveFovFactory()({
      passable: passableForFloor(newFloor),
    });
    this.ctx.fov = this.fov;
  }

  // ── FOV ────────────────────────────────────────────────────

  private recomputeFov(): void {
    const floor = this.currentBoard.floors[this.currentBoard.floor];
    if (!this.fov) {
      this.fov = resolveFovFactory()({ passable: passableForFloor(floor) });
    }
    applyVisibility(
      this.fov,
      this.currentBoard.player.position,
      this.visibleTiles,
      this.exploredTiles,
    );
  }

  // ── Board commit ──────────────────────────────────────────

  private commitBoard(): void {
    const result = commitBoardSnapshot({
      engine: this.cellEngine,
      board: this.currentBoard,
      status: this._status,
      previousCellBytes: this.lastBoardCell,
    });

    this.currentBoard = result.board;
    this.lastBoardCell = result.cellBytes;
    this.boardHistory.push(result.cellId);

    set(this.atoms.boardStateAtom, this.currentBoard);
    set(this.atoms.boardHistoryAtom, [...this.boardHistory]);
    set(this.atoms.consumedCellsAtom, new Set(this.consumedCells));
    set(this.atoms.statusAtom, this._status);

    this.terminalEmitter.maybeEmit({
      cellBytes: result.cellBytes,
      cellId: result.cellId,
      status: this._status,
    });
  }

  // ── Helpers ────────────────────────────────────────────────

  private assertPlaying(): void {
    if (this._status !== 'playing') {
      throw new Error(`Game is over: ${this._status}`);
    }
  }

  private result(message: string): ActionResult {
    this.currentBoard.messages = [message];
    return { board: this.currentBoard, message, status: this._status };
  }

  private commitAndResult(message: string): ActionResult {
    // The dispatcher may have flipped `ctx.status` for dead/victory.
    // Pull it back onto the facade before snapshotting the board.
    if (this.ctx.status !== this._status) {
      this._status = this.ctx.status;
    }
    this.commitBoard();
    this.currentBoard.messages = [message];
    return { board: this.currentBoard, message, status: this._status };
  }
}

```
