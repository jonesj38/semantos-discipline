---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.523490+00:00
---

# packages/game-sdk/src/engine.ts

```ts
/**
 * @deprecated — use the split modules under
 * `packages/game-sdk/src/engine/` instead.
 *
 * Prompt 22 split this 679-LOC file into:
 *
 *   Concrete `GameCellEngine` decomposition:
 *     - host-imports.ts       — createHostImports
 *     - kernel-loader.ts      — bootKernel (WASM init)
 *     - engine-utils.ts       — rewriteOwnerId / padTo / uint8Eq /
 *                                hexEncode
 *     - entity-ops.ts         — createEntity / getEntity /
 *                                updateEntity / loadEntity / serialize
 *     - inventory-ops.ts      — createInventory / addTo / removeFrom /
 *                                transferBetween / loadInventory
 *     - trade-ops.ts          — executeTrade (snapshot-and-swap)
 *     - transition-ops.ts     — transitionEntity + evaluatePolicy
 *     - cell-engine-facade.ts — thin GameCellEngine class
 *
 *   New abstract pattern layer (downstream games will adopt):
 *     - reducer-base.ts       — generic <S, A> EngineSlice
 *     - action-dispatcher.ts  — Registry<ActionHandler> on a slice
 *     - policy-hook.ts        — policyPort + PolicyEvaluator interface
 *     - persistence-hook.ts   — cellStorePort + CellStoreFacade
 *     - event-emitter.ts      — gameEventBus<E> factory
 *     - engine-template.ts    — orchestrator combining the above
 *
 * Migration target imports:
 *
 *   import { GameCellEngine } from './engine/';
 *   import { makeEngineTemplate } from './engine/';
 */

export {
  GameCellEngine,
  type CreateEntityOptions,
  type CreateOptions,
} from './engine/index';

// Pattern-layer exports surfaced for downstream prompts (23–26).
export {
  combineReducers,
  makeEngineSlice,
  type EngineSlice,
  type Reducer,
  makeActionDispatcher,
  type ActionContext,
  type ActionDispatcher,
  type ActionHandler,
  acceptAllPolicy,
  policyPort,
  resolvePolicy,
  type PolicyDecision,
  type PolicyEvaluator,
  cellStorePort,
  noopCellStore,
  resolveCellStore,
  type CellStoreFacade,
  gameEventBus,
  makeEngineTemplate,
  type EngineTemplate,
  type EngineTemplateOptions,
} from './engine/index';

```
