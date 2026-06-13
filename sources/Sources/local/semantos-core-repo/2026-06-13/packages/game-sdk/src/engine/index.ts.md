---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.524152+00:00
---

# packages/game-sdk/src/engine/index.ts

```ts
/**
 * game-sdk engine barrel — public surface for the prompt-22 split.
 *
 * Two layers:
 *   1. The concrete `GameCellEngine` (legacy class, decomposed
 *      into ops modules but with byte-identical public API)
 *   2. The new abstract pattern layer (reducer-base /
 *      action-dispatcher / policy-hook / persistence-hook /
 *      event-emitter / engine-template) that downstream games
 *      will adopt as they migrate (prompts 23–26).
 */

// ── Concrete cell-engine ─────────────────────────────────────────
export {
  GameCellEngine,
  type CreateOptions,
  type CreateEntityOptions,
} from './cell-engine-facade';

// ── Ops modules (advanced consumers / tests) ─────────────────────
export {
  createEntity,
  deserializeEntity,
  getEntity,
  loadEntity,
  serializeEntity,
  updateEntity,
  type UpdateEntityChanges,
} from './entity-ops';
export {
  addToInventory,
  createInventory,
  loadInventory,
  removeFromInventory,
  transferBetweenInventories,
} from './inventory-ops';
export { executeTrade } from './trade-ops';
export {
  evaluatePolicy,
  transitionEntity,
} from './transition-ops';
export {
  bootKernel,
  type LoadKernelOptions,
} from './kernel-loader';
export {
  createHostImports,
  type HostImportOptions,
} from './host-imports';
export {
  hexEncode,
  padTo,
  rewriteOwnerId,
  uint8Eq,
} from './engine-utils';

// ── Abstract pattern layer (prompts 23–26 will consume) ──────────
export {
  combineReducers,
  makeEngineSlice,
  type EngineSlice,
  type Reducer,
} from './reducer-base';
export {
  makeActionDispatcher,
  type ActionContext,
  type ActionDispatcher,
  type ActionHandler,
} from './action-dispatcher';
export {
  acceptAllPolicy,
  policyPort,
  resolvePolicy,
  type PolicyDecision,
  type PolicyEvaluator,
} from './policy-hook';
export {
  cellStorePort,
  noopCellStore,
  resolveCellStore,
  type CellStoreFacade,
} from './persistence-hook';
export { gameEventBus } from './event-emitter';
export {
  makeEngineTemplate,
  type EngineTemplate,
  type EngineTemplateOptions,
} from './engine-template';

```
