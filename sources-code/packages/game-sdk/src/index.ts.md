---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.521838+00:00
---

# packages/game-sdk/src/index.ts

```ts
/**
 * @semantos/game-sdk — Game Engine SemanticObject SDK
 *
 * Platform-agnostic TypeScript core that maps game concepts
 * (entities, inventories, trades, state machines) onto cell engine primitives.
 *
 * Every game object IS a cell. Every inventory operation is an opcode sequence.
 * Every trade is a capability-gated transfer.
 */

// Types
export {
  GameEntityType,
  type GameEntity,
  type Inventory,
  type TradeOffer,
  type TradeProposal,
  type TradeResult,
  type EntityState,
  type EntityTransition,
  type EntityStateMachine,
  type LinearityMode,
  type GamePolicy,
  ENTITY_PAYLOAD_HEADER_SIZE,
  MAX_PAYLOAD_CONTENT_SIZE,
  LinearityError,
  TradeError,
  TransitionError,
} from './types';

// Codec
export { encodeEntityPayload, decodeEntityPayload } from './codec';

// Engine
export { GameCellEngine, type CreateOptions, type CreateEntityOptions } from './engine';

// Re-export StorageAdapter type for consumers
export type { StorageAdapter } from '../../../core/protocol-types/src/storage';

// Policies
export {
  compileGamePolicy,
  compileGamePolicyFile,
  packPolicyCell,
  unpackPolicyCell,
  BOARD_PRIMITIVES,
  ENTITY_PRIMITIVES,
  INVENTORY_PRIMITIVES,
  ALL_PRIMITIVES,
  type GamePrimitive,
} from './policies/index';

// Phase 29.5: Kernel enforcement provider
export { createGameSDKHostFunctionProvider, GameSDKHostFunctionProvider } from './kernel-provider';

// ECS (bitECS integration — optional, requires `bitecs` to be installed)
export {
  DEFAULT_CAPACITY,
  CellBacked,
  Dirty,
  Position,
  Velocity,
  Health,
  Owner,
  StateTag,
  TradeIntent,
  hashStateTag,
  shortOwnerId,
  type GameWorld,
  createGameWorld,
  registerCellBacked,
  getCellBackedEntity,
  setCellBackedEntity,
  stashTradeOffer,
  loadTradeOffer,
  clearTradeOffer,
  markDirty,
  drainDirty,
  syncFromCell,
  syncToCell,
  tradeSystem,
  TRADE_PENDING,
  TRADE_ACCEPTED,
  TRADE_REJECTED,
} from './ecs/index';

// Bindings (scaffold types only)
export type {
  GodotNodeData,
  GodotSignal,
  SemanticInventory as GodotSemanticInventory,
  SemanticEntity as GodotSemanticEntity,
  SemanticTradeUI,
  SemanticPolicyEditor,
} from './bindings/godot/index';

export type {
  UnityGameObjectData,
  UnityEvent,
  SemanticInventory as UnitySemanticInventory,
  SemanticEntity as UnitySemanticEntity,
  SemanticTradeManager,
  SemanticPolicyAsset,
} from './bindings/unity/index';

```
