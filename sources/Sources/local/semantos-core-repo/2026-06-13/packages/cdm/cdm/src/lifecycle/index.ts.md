---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.498529+00:00
---

# packages/cdm/cdm/src/lifecycle/index.ts

```ts
/**
 * Lifecycle barrel — public surface for the per-concern modules
 * created by refactor 29.
 *
 * `lifecycle.ts` (legacy) re-exports from here as a deprecation shim.
 * New code should import from `@semantos/cdm/lifecycle` instead.
 */

export {
  CDMLifecycleEngine,
  type CDMLifecycleOptions,
  type ExecuteEventOk,
  type NovateOk,
  type PartialTerminateOk,
} from './lifecycle-facade';

export {
  reduceTradeEvent,
  type ReducerResult,
} from './event-reducer';

export {
  TRANSITION_TABLE,
  TERMINAL_EVENTS,
  canTransition,
  isTerminalEvent,
  nextStateFor,
  validEventsFor,
  validateTradeEvent,
  economicEffectFrom,
  type TradeEvent,
  type TradeEventPayload,
} from './trade-events';

export { applyEconomicEffect } from './economic-effects';

export {
  novateProduct,
  type NovationResult,
} from './novation';

export {
  partialTerminateProduct,
  closeOutNetPortfolio,
  type PartialTerminationResult,
} from './termination';

export {
  decreaseNotional,
} from './decrease';

export {
  increaseNotional,
  type IncreaseResult,
} from './increase';

export {
  buildEventCell,
  type BuiltEventCell,
} from './cell-builder';

export {
  runPolicyGate,
  type PolicyGateResult,
  type PolicyGateOk,
  type PolicyGateRejected,
} from './policy-gate';

export {
  bindPersistence,
  emitLifecycleEvent,
  lifecycleEventBus,
  type LifecycleEffectEvent,
  type LifecycleStore,
} from './persistence';

```
