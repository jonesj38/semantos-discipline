---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.834284+00:00
---

# archive/apps-mud/src/index.ts

```ts
/**
 * @semantos/mud -- Multiplayer dungeon with provable cell-backed state.
 *
 * Room actors process actions sequentially (no concurrency within a room).
 * Every entity is a cell with enforced linearity.
 * Every state change is a Merkle-chained DAG node.
 * All action legality is validated via Lisp policies in WASM.
 */

// Core
export { WorldServer } from './world-server';
export { RoomActor } from './room-actor';
export { ActionQueue } from './action-queue';

// Policies
export { registerMUDHostFunctions } from './host-functions';
export { compileMUDPolicies } from './policies';
export type { CompiledMUDPolicies } from './policies';
export { createMUDHostFunctionProvider, MUDHostFunctionProvider } from './kernel-provider';

// Renderer
export {
  renderRoom,
  renderPlayerStatus,
  renderRoomDescription,
  renderMUDInventory,
} from './renderer';

// Types
export type {
  MUDPlayer,
  PlayerId,
  RoomId,
  RoomState,
  RoomEvent,
  RoomEventType,
  RoomExit,
  PlayerAction,
  ActionType,
  ActionResult,
  PlayerSession,
  SessionId,
  WorldConfig,
  ClientMessage,
  ServerMessage,
  StorageAdapter,
} from './types';
export { DEFAULT_WORLD_CONFIG } from './types';

```
