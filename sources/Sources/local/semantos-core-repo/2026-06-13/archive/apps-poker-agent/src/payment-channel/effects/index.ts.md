---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/effects/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.790920+00:00
---

# archive/apps-poker-agent/src/payment-channel/effects/index.ts

```ts
/**
 * Effects barrel — bundle of side-effect atoms that subscribe to the
 * facade's effect bus.
 */

export { effectBus, subscribeEffect } from './bus';
export type {
  AwaitSpvCommand,
  BroadcastCommand,
  EffectCommand,
  EmitEventCommand,
  FeeCreditCommand,
  MarkStateCommand,
  PersistArtifactsCommand,
  PersistSpvCommand,
} from './types';
export {
  makePersistEffect,
  type PersistEffect,
  type PersistEffectOptions,
  type PersistStore,
} from './persist-effect';
export {
  makeBroadcastEffect,
  type BroadcastEffect,
  type BroadcastEffectOptions,
} from './broadcast-effect';
export {
  makeSpvEffect,
  type SpvEffect,
  type SpvEffectOptions,
} from './spv-effect';
export {
  makeFeeCreditEffect,
  type FeeCreditEffect,
  type FeeCreditEffectOptions,
  type FeeCreditLedgerEntry,
} from './fee-credit-effect';
export {
  makeLogEffect,
  type LogEffect,
  type LogEffectOptions,
} from './log-effect';

```
