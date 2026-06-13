---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/world-server/world-persistence.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.837433+00:00
---

# archive/apps-mud/src/world-server/world-persistence.ts

```ts
/**
 * World-persistence — `CellStore` IO for world-level cells.
 *
 * Refactor 24 / split of `world-server.ts`.
 *
 * Three logical cell groups are managed here:
 *
 *   - `mud/world/config`           — RELEVANT, JSON-encoded `WorldConfig` snapshot
 *   - `mud/world/topology`         — RELEVANT, JSON-encoded room-id→exits graph
 *   - `mud/players/<pid>/session`  — RELEVANT, JSON-encoded `PlayerSession`
 *
 * Every value is a single-cell payload (no chained DAG); the
 * room-actor manages its own per-room DAG separately.
 *
 * Each function takes the `CellStore` as an explicit dependency so the
 * persistence concern is decoupled from the world-server itself.
 */

import { CellStore } from '../../../../core/protocol-types/src/cell-store';
import { Linearity } from '../../../../core/protocol-types/src/constants';
import type {
  PlayerId,
  PlayerSession,
  RoomExit,
  RoomId,
  WorldConfig,
} from '../types';

// ── Cell paths ─────────────────────────────────────────────────

export const WORLD_CONFIG_PATH = 'mud/world/config';
export const WORLD_TOPOLOGY_PATH = 'mud/world/topology';
export const playerSessionPath = (playerId: PlayerId): string =>
  `mud/players/${playerId}/session`;
export const roomStatePath = (roomId: RoomId): string =>
  `mud/rooms/${roomId}/state`;

// ── World-config cell ──────────────────────────────────────────

/** Snapshot the `WorldConfig` (minus the storage adapter) to a JSON cell. */
export async function persistWorldConfig(
  cellStore: CellStore,
  config: WorldConfig,
): Promise<void> {
  const payload = new TextEncoder().encode(
    JSON.stringify({
      name: config.name,
      roomCount: config.roomCount,
      maxPlayersPerRoom: config.maxPlayersPerRoom,
      pvpEnabled: config.pvpEnabled,
      startRoomId: config.startRoomId,
      seed: config.seed,
      createdAt: Date.now(),
    }),
  );
  await cellStore.put(WORLD_CONFIG_PATH, payload, {
    linearity: Linearity.RELEVANT,
  });
}

/** Load the world-config cell (or `null` if not yet persisted). */
export async function loadWorldConfig(
  cellStore: CellStore,
): Promise<Record<string, unknown> | null> {
  const cell = await cellStore.get(WORLD_CONFIG_PATH);
  if (!cell) return null;
  try {
    return JSON.parse(new TextDecoder().decode(cell.payload));
  } catch {
    return null;
  }
}

// ── Topology cell ──────────────────────────────────────────────

export type TopologySnapshot = Record<
  string,
  { name: string; description: string; exits: RoomExit[] }
>;

/** Snapshot the room-id→exits graph to a JSON cell. */
export async function persistTopology(
  cellStore: CellStore,
  topology: TopologySnapshot,
): Promise<void> {
  const payload = new TextEncoder().encode(JSON.stringify(topology));
  await cellStore.put(WORLD_TOPOLOGY_PATH, payload, {
    linearity: Linearity.RELEVANT,
  });
}

/** Load the topology cell (or `null` if not yet persisted). */
export async function loadTopology(
  cellStore: CellStore,
): Promise<TopologySnapshot | null> {
  const cell = await cellStore.get(WORLD_TOPOLOGY_PATH);
  if (!cell) return null;
  try {
    return JSON.parse(new TextDecoder().decode(cell.payload));
  } catch {
    return null;
  }
}

// ── Player-session cell ────────────────────────────────────────

/**
 * Persist a player's session as a single RELEVANT cell. Fire-and-forget:
 * the session cell is convenience data, not source of truth, so the
 * caller doesn't await the result.
 */
export function persistPlayerSession(
  cellStore: CellStore,
  playerId: PlayerId,
  session: PlayerSession,
): void {
  const payload = new TextEncoder().encode(
    JSON.stringify({ ...session, playerId }),
  );
  // Fire-and-forget — match legacy semantics
  void cellStore.put(playerSessionPath(playerId), payload, {
    linearity: Linearity.RELEVANT,
  });
}

// ── Per-room DAG verification ──────────────────────────────────

/**
 * Verify the integrity of every room's DAG via `CellStore.verify()`.
 * Returns `Map<RoomId, { valid, errors }>`.
 */
export async function verifyAllRoomDAGs(
  cellStore: CellStore,
  roomIds: Iterable<RoomId>,
): Promise<Map<RoomId, { valid: boolean; errors: string[] }>> {
  const results = new Map<RoomId, { valid: boolean; errors: string[] }>();
  for (const roomId of roomIds) {
    const result = await cellStore.verify(roomStatePath(roomId));
    results.set(roomId, result);
  }
  return results;
}

```
