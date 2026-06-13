---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-mud/src/room-actor/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.840352+00:00
---

# archive/apps-mud/src/room-actor/index.ts

```ts
/**
 * Public surface for the prompt-23 room-actor split.
 *
 * The legacy `apps/mud/src/room-actor.ts` is now a deprecation
 * re-export of `RoomActor` from this barrel. New consumers should
 * import individual system modules (combat, inventory, door, movement)
 * directly when they need finer-grained access.
 */

export { RoomActor } from './room-actor-facade';

// System modules — exposed for tests and downstream extensions
export {
  resolveCombatWithMonster,
  resolvePvP,
  type CombatOutcome,
  type PvPOutcome,
} from './combat-system';
export {
  handleDrop,
  handlePickup,
  handleUseItem,
  type InventoryOutcome,
} from './inventory-system';
export {
  handleExitRoom,
  handleOpenDoor,
  type DoorOutcome,
} from './door-system';
export {
  buildLookMessage,
  handleMove,
  handleSay,
  type MoveOutcome,
  type SayOutcome,
} from './movement-system';

// Policy + dispatcher
export {
  acceptAllMovePolicy,
  makePolicyEvaluator,
  type MovePolicyInput,
  type PolicyEvaluator,
} from './policy-engine';
export {
  makeActionProcessor,
  type ActionHandler,
  type ActionProcessor,
  type HandlerContext,
  type HandlerOutcome,
} from './action-processor';
export {
  makeRoomActionProcessor,
  registerDefaultHandlers,
} from './default-handlers';

// Atoms + persistence
export {
  disposeRoomAtoms,
  getRoomAtoms,
  listRoomIds,
  resetRoomAtoms,
  type RoomAtoms,
} from './atoms';
export {
  makeRoomStatePersister,
  type PersisterHandle,
  type RoomStateSnapshot,
} from './room-state-persister';

// Internal helpers used by tests
export { applyHandlerOutcome } from './outcome-applier';
export { commitRoomState } from './state-commit';
export {
  addPlayer,
  getPlayer,
  getPlayers,
  otherPlayers,
  removePlayer,
} from './player-registry';

```
