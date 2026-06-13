---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/room-actor-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.841352+00:00
---

# archive/apps-mud/src/room-actor/room-actor-facade.ts

```ts
/**
 * RoomActor facade — orchestrator that wires the prompt-23 system
 * modules together.
 *
 * Public API matches the legacy `apps/mud/src/room-actor.ts` exactly
 * so consumers (`world-server.ts`, the gate test, the renderer) keep
 * compiling unchanged. The legacy file becomes a deprecation re-export.
 *
 * The facade owns:
 *   - The single-threaded action queue + main loop
 *   - The atom bundle (state / players / consumed cells / DAG history)
 *   - The action processor (registry-based dispatch into system modules)
 *   - The policy evaluator (audit `_lastPolicyResult`)
 *   - The non-blocking persister (effect-backed CellStore writes)
 *   - The event emitter (room events + per-action results)
 *
 * Per-action effect fan-out lives in `outcome-applier.ts`; player
 * lifecycle in `player-registry.ts`; cell-DAG commit in
 * `state-commit.ts`.
 */

import { get, set } from '@semantos/state';

import type { GameCellEngine } from '../../../../packages/game-sdk/src/engine';
import type { HostFunctionRegistry } from '../../../../core/cell-engine/bindings/host-functions';
import type { CellStore } from '../../../../core/protocol-types/src/cell-store';
import type { PolicyRuntime } from '../../../../packages/policy-runtime/src/runtime';
import type { AnchorEmitter } from '../../../../packages/policy-runtime/src/anchor-emitter';
import type { PolicyResult } from '../../../../packages/policy-runtime/src/types';

import { ActionQueue } from '../action-queue';
import type { CompiledMUDPolicies } from '../policies';
import type {
  MUDPlayer,
  PlayerAction,
  PlayerId,
  RoomEvent,
  RoomId,
  RoomState,
} from '../types';

import { disposeRoomAtoms, getRoomAtoms, type RoomAtoms } from './atoms';
import { makeRoomActionProcessor } from './default-handlers';
import type { ActionProcessor } from './action-processor';
import { applyHandlerOutcome } from './outcome-applier';
import { makePolicyEvaluator, type PolicyEvaluator } from './policy-engine';
import {
  addPlayer as addPlayerOp,
  getPlayer as getPlayerOp,
  getPlayers as getPlayersOp,
  otherPlayers,
  removePlayer as removePlayerOp,
} from './player-registry';
import {
  makeRoomStatePersister,
  type PersisterHandle,
} from './room-state-persister';

export class RoomActor {
  readonly roomId: RoomId;
  private cellEngine: GameCellEngine;
  private pvpEnabled: boolean;
  private cellStore: CellStore;
  private runtime?: PolicyRuntime;
  private anchorEmitter?: AnchorEmitter;

  private atoms: RoomAtoms;
  private queue: ActionQueue<PlayerAction>;
  private processor: ActionProcessor;
  private policy: PolicyEvaluator;
  private persister: PersisterHandle;

  private eventListeners = new Set<(event: RoomEvent) => void>();
  private busDispose: (() => void) | null = null;
  private running = false;

  constructor(
    roomId: RoomId,
    state: RoomState,
    cellEngine: GameCellEngine,
    registry: HostFunctionRegistry,
    policies: CompiledMUDPolicies,
    cellBytes: Uint8Array,
    cellStore: CellStore,
    pvpEnabled = false,
    runtime?: PolicyRuntime,
    anchorEmitter?: AnchorEmitter,
  ) {
    this.roomId = roomId;
    this.cellEngine = cellEngine;
    this.pvpEnabled = pvpEnabled;
    this.cellStore = cellStore;
    this.runtime = runtime;
    this.anchorEmitter = anchorEmitter;

    this.atoms = getRoomAtoms({
      roomId,
      initialState: state,
      initialCellBytes: cellBytes,
    });
    // Reset to caller's authoritative values in case the registry
    // returned a pre-existing bundle (test reboots, world reloads).
    set(this.atoms.roomStateAtom, state);
    set(this.atoms.dagHistoryAtom, [state.cellId]);
    set(this.atoms.lastCellBytesAtom, cellBytes);
    set(this.atoms.playersAtom, new Map<PlayerId, MUDPlayer>());
    set(this.atoms.consumedCellsAtom, new Set<string>());

    this.queue = new ActionQueue();
    this.processor = makeRoomActionProcessor();
    this.policy = makePolicyEvaluator({ cellEngine, registry, policies });
    this.persister = makeRoomStatePersister({ cellStore });

    this.busDispose = this.atoms.eventsBus.on((event: RoomEvent) => {
      for (const listener of this.eventListeners) listener(event);
    });
  }

  // ── Lifecycle ──────────────────────────────────────────────

  async start(): Promise<void> {
    if (this.running) return;
    this.running = true;
    for await (const action of this.queue.drain()) {
      try {
        this.processAction(action);
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        this.atoms.eventsBus.emit({
          type: 'combat',
          roomId: this.roomId,
          playerId: action.playerId,
          message: `Error: ${msg}`,
        });
      }
    }
    this.running = false;
  }

  stop(): void {
    this.queue.close();
    this.persister.dispose();
    if (this.busDispose) {
      this.busDispose();
      this.busDispose = null;
    }
    disposeRoomAtoms(this.roomId);
  }

  submit(action: PlayerAction): void {
    this.queue.push(action);
  }

  // ── Player Management ──────────────────────────────────────

  addPlayer(player: MUDPlayer): void { addPlayerOp(this.atoms, player); }
  removePlayer(playerId: PlayerId): MUDPlayer | null {
    return removePlayerOp(this.atoms, playerId);
  }
  getPlayer(playerId: PlayerId): MUDPlayer | undefined {
    return getPlayerOp(this.atoms, playerId);
  }
  getPlayers(): MUDPlayer[] { return getPlayersOp(this.atoms); }

  // ── State Accessors ────────────────────────────────────────

  getState(): RoomState { return get(this.atoms.roomStateAtom); }
  getHistory(): string[] { return [...get(this.atoms.dagHistoryAtom)]; }
  isConsumed(cellId: string): boolean { return get(this.atoms.consumedCellsAtom).has(cellId); }
  lastPolicyResult(): PolicyResult | undefined { return this.policy.lastResult(); }

  async getCellStoreHistory() { return this.cellStore.history(`mud/rooms/${this.roomId}/state`); }
  async verifyCellStoreDAG() { return this.cellStore.verify(`mud/rooms/${this.roomId}/state`); }

  // ── Event System ───────────────────────────────────────────

  onEvent(listener: (event: RoomEvent) => void): () => void {
    this.eventListeners.add(listener);
    return () => this.eventListeners.delete(listener);
  }

  // ── Action Processing (sequential, single-threaded) ────────

  private processAction(action: PlayerAction): void {
    const player = getPlayerOp(this.atoms, action.playerId);
    if (!player) return;

    if (player.hp <= 0) {
      this.atoms.eventsBus.emit({
        type: 'combat',
        roomId: this.roomId,
        playerId: action.playerId,
        message: 'You are dead. You cannot act.',
      });
      return;
    }

    const outcome = this.processor.dispatch({
      roomId: this.roomId,
      state: get(this.atoms.roomStateAtom),
      player,
      action,
      otherPlayers: otherPlayers(this.atoms, player.id),
      policy: this.policy,
      pvpEnabled: this.pvpEnabled,
    });

    applyHandlerOutcome({
      atoms: this.atoms,
      cellEngine: this.cellEngine,
      anchorEmitter: this.anchorEmitter,
      persister: this.persister,
      player,
      action,
      outcome,
    });
  }
}

```
