---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/world-server/world-server-facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.836568+00:00
---

# archive/apps-mud/src/world-server/world-server-facade.ts

```ts
/**
 * `WorldServer` — public facade for the room-actor-pool supervisor.
 *
 * Refactor 24 / split of `world-server.ts`. Public class shape is
 * preserved byte-identical with the pre-split monolith — every
 * existing call site (`apps/mud/src/index.ts`, future world-host /
 * world-client wiring) continues to compile without a single import
 * change.
 *
 * Internally delegates to:
 *   - `world-boot-flow.ts`        — initial world generation + start
 *   - `room-actor-pool.ts`        — RoomActor registry
 *   - `player-session-store.ts`   — session + room-binding maps
 *   - `player-join-flow.ts`       — player creation + bind
 *   - `cross-room-transfer.ts`    — atomic exit/entry between actors
 *   - `event-bus-bridge.ts`       — per-player event routing
 *   - `world-persistence.ts`      — config / topology / session cells
 */

import type { CreateOptions } from '../../../../packages/game-sdk/src/engine';
import { GameCellEngine } from '../../../../packages/game-sdk/src/engine';
import { CellStore } from '../../../../core/protocol-types/src/cell-store';
import type { StorageAdapter } from '../../../../core/protocol-types/src/storage';
import { createAdapter } from '../../../../core/protocol-types/src/adapters/create-adapter';
import type { PolicyRuntime } from '../../../../packages/policy-runtime/src/runtime';
import type { AnchorEmitter } from '../../../../packages/policy-runtime/src/anchor-emitter';
import { HostFunctionRegistry } from '@semantos/cell-engine/bindings/host-functions';
import { registerMUDHostFunctions } from '../host-functions';
import { compileMUDPolicies, type CompiledMUDPolicies } from '../policies';
import type { RoomActor } from '../room-actor';
import type {
  MUDPlayer,
  PlayerAction,
  PlayerId,
  PlayerSession,
  RoomEvent,
  RoomId,
  SessionId,
  WorldConfig,
} from '../types';
import { DEFAULT_WORLD_CONFIG } from '../types';

import { transferPlayer as transferPlayerFn } from './cross-room-transfer';
import { EventBusBridge } from './event-bus-bridge';
import { joinWorld } from './player-join-flow';
import { PlayerSessionStore } from './player-session-store';
import { RoomActorPool } from './room-actor-pool';
import { bootWorld } from './world-boot-flow';
import {
  loadTopology as loadTopologyFn,
  loadWorldConfig as loadWorldConfigFn,
  persistWorldConfig,
  verifyAllRoomDAGs as verifyAllRoomDAGsFn,
  type TopologySnapshot,
} from './world-persistence';

export class WorldServer {
  private readonly cellEngine: GameCellEngine;
  private readonly registry: HostFunctionRegistry;
  private readonly policies: CompiledMUDPolicies;
  private readonly config: WorldConfig;

  /** StorageAdapter backing all MUD persistence. */
  readonly storage: StorageAdapter;
  /** CellStore for structured cell persistence (versioned, Merkle-chained). */
  readonly cellStore: CellStore;

  /** Phase 29.5: PolicyRuntime for kernel-enforced evaluation. */
  private readonly runtime?: PolicyRuntime;
  /** Phase 29.5: AnchorEmitter for terminal-event anchoring. */
  private readonly anchorEmitter?: AnchorEmitter;

  private readonly pool: RoomActorPool;
  private readonly sessionStore: PlayerSessionStore;
  private readonly eventBridge: EventBusBridge;

  private constructor(
    cellEngine: GameCellEngine,
    registry: HostFunctionRegistry,
    policies: CompiledMUDPolicies,
    config: WorldConfig,
    storage: StorageAdapter,
    cellStore: CellStore,
    runtime?: PolicyRuntime,
    anchorEmitter?: AnchorEmitter,
  ) {
    this.cellEngine = cellEngine;
    this.registry = registry;
    this.policies = policies;
    this.config = config;
    this.storage = storage;
    this.cellStore = cellStore;
    this.runtime = runtime;
    this.anchorEmitter = anchorEmitter;

    this.pool = new RoomActorPool();
    this.sessionStore = new PlayerSessionStore();
    this.eventBridge = new EventBusBridge(this.pool, this.sessionStore);
  }

  /**
   * Create a new world with generated rooms.
   *
   * Resolves the storage adapter (explicit override → engine opts →
   * auto-detect), wires up the GameCellEngine + host functions +
   * policies, then runs the boot flow.
   */
  static async create(
    config?: Partial<WorldConfig>,
    opts?: CreateOptions,
  ): Promise<WorldServer> {
    const fullConfig = { ...DEFAULT_WORLD_CONFIG, ...config };

    // Resolve storage: explicit override → GameCellEngine opts → auto-detect
    const storage =
      fullConfig.storage ?? opts?.storage ?? (await createAdapter());

    const registry = new HostFunctionRegistry();
    registerMUDHostFunctions(registry);

    const cellEngine = await GameCellEngine.create({
      ...opts,
      storage,
      hostRegistry: registry,
    } as CreateOptions & { hostRegistry: HostFunctionRegistry });

    const policies = compileMUDPolicies();
    const cellStore = new CellStore(storage);

    // Phase 29.5: inherit from engine
    const runtime = cellEngine.policyRuntime;
    const anchorEmitter = cellEngine.anchorEmitter;

    const server = new WorldServer(
      cellEngine,
      registry,
      policies,
      fullConfig,
      storage,
      cellStore,
      runtime,
      anchorEmitter,
    );

    await bootWorld({
      cellEngine,
      registry,
      policies,
      cellStore,
      config: fullConfig,
      pool: server.pool,
      runtime,
      anchorEmitter,
    });

    await persistWorldConfig(cellStore, fullConfig);

    return server;
  }

  // ── Player Sessions ────────────────────────────────────────

  /** Join the world. Creates a player and places them in the start room. */
  join(playerName: string): { session: PlayerSession; player: MUDPlayer } {
    return joinWorld(playerName, {
      cellEngine: this.cellEngine,
      cellStore: this.cellStore,
      pool: this.pool,
      sessions: this.sessionStore,
      config: this.config,
    });
  }

  /** Submit an action for a player. Routes to their current room's actor. */
  act(playerId: PlayerId, action: Omit<PlayerAction, 'playerId'>): void {
    const roomId = this.sessionStore.getPlayerRoom(playerId);
    if (!roomId) throw new Error(`Player ${playerId} not in any room`);

    const actor = this.pool.get(roomId);
    if (!actor) throw new Error(`Room ${roomId} not found`);

    actor.submit({ ...action, playerId } as PlayerAction);
  }

  /** Move a player between rooms. Called after exit-room action is processed. */
  transferPlayer(playerId: PlayerId, targetRoomId: RoomId): boolean {
    const ok = transferPlayerFn(
      this.pool,
      this.sessionStore,
      playerId,
      targetRoomId,
    );
    if (ok) {
      // Re-attach the event listener to the new room's actor.
      this.eventBridge.rebindPlayer(playerId);
    }
    return ok;
  }

  /** Subscribe to events for a specific player's current room. */
  onPlayerEvent(
    playerId: PlayerId,
    listener: (event: RoomEvent) => void,
  ): () => void {
    return this.eventBridge.subscribe(playerId, listener);
  }

  // ── Accessors ──────────────────────────────────────────────

  getRoom(roomId: RoomId): RoomActor | undefined {
    return this.pool.get(roomId);
  }

  getRoomIds(): RoomId[] {
    return this.pool.ids();
  }

  getSession(sessionId: SessionId): PlayerSession | undefined {
    return this.sessionStore.getSession(sessionId);
  }

  getPlayerRoom(playerId: PlayerId): RoomId | undefined {
    return this.sessionStore.getPlayerRoom(playerId);
  }

  getPlayer(playerId: PlayerId): MUDPlayer | undefined {
    const roomId = this.sessionStore.getPlayerRoom(playerId);
    if (!roomId) return undefined;
    return this.pool.get(roomId)?.getPlayer(playerId);
  }

  /** Get all room DAG histories for verification. */
  getAllHistories(): Map<RoomId, string[]> {
    const result = new Map<RoomId, string[]>();
    for (const [id, actor] of this.pool.entries()) {
      result.set(id, actor.getHistory());
    }
    return result;
  }

  /** Shut down all room actors. */
  shutdown(): void {
    this.eventBridge.shutdown();
    this.pool.stopAll();
  }

  // ── Persistence pass-through ───────────────────────────────

  /** Load world config from storage. Returns null if not persisted. */
  loadWorldConfig(): Promise<Record<string, unknown> | null> {
    return loadWorldConfigFn(this.cellStore);
  }

  /** Load room topology from storage. Returns null if not persisted. */
  loadTopology(): Promise<TopologySnapshot | null> {
    return loadTopologyFn(this.cellStore);
  }

  /** Verify integrity of all room DAGs via CellStore.verify(). */
  verifyAllRoomDAGs(): Promise<
    Map<RoomId, { valid: boolean; errors: string[] }>
  > {
    return verifyAllRoomDAGsFn(this.cellStore, this.pool.ids());
  }
}

```
