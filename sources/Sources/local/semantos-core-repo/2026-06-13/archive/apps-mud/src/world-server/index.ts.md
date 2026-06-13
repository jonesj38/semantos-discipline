---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/world-server/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.836863+00:00
---

# archive/apps-mud/src/world-server/index.ts

```ts
/**
 * Barrel — public exports of the `world-server/` split.
 *
 * Refactor 24 / split of `world-server.ts`. Consumers import the
 * `WorldServer` class from here (or via the legacy `world-server.ts`
 * re-export shim, which delegates to this barrel).
 */

export { WorldServer } from './world-server-facade';

// Internal modules — exported for tests + advanced consumers. No public
// API change; the legacy monolith never exposed these but the
// individual pieces are useful for granular testing and the future
// world-host / world-client work.
export { RoomActorPool } from './room-actor-pool';
export { PlayerSessionStore } from './player-session-store';
export { EventBusBridge } from './event-bus-bridge';
export { transferPlayer } from './cross-room-transfer';
export {
  generateWorldRooms,
  wireRoomExits,
  ROOM_NAMES,
  ROOM_DESCRIPTIONS,
  roomIdAt,
  type GeneratedRoom,
} from './world-generator';
export { bootWorld, type BootFlowDeps } from './world-boot-flow';
export { joinWorld, type JoinResult } from './player-join-flow';
export {
  WORLD_CONFIG_PATH,
  WORLD_TOPOLOGY_PATH,
  playerSessionPath,
  roomStatePath,
  persistWorldConfig,
  persistTopology,
  persistPlayerSession,
  loadWorldConfig,
  loadTopology,
  verifyAllRoomDAGs,
  type TopologySnapshot,
} from './world-persistence';
export {
  RELEVANT,
  AFFINE,
  LINEAR,
  WORLD_OWNER,
  PLAYER_OWNER,
  findFreePosition,
  getItemPool,
} from './internal-types';

```
