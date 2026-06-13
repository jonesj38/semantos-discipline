---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/persistence.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.500894+00:00
---

# packages/cdm/cdm/src/lifecycle/persistence.ts

```ts
/**
 * Persistence effect — observable bus + opt-in store hookup for CDM
 * lifecycle events.
 *
 * The facade emits `LifecycleEffectEvent`s onto `lifecycleEventBus`
 * after every successful state transition. Consumers can subscribe
 * to log, persist, or anchor the events. `bindPersistence(store)`
 * wires a default `LifecycleStore` that gets `putEvent` + `putCell`
 * called on every emission.
 *
 * The bus is intentionally non-fatal: if a subscriber throws, the
 * facade still returns success (the in-memory state already advanced).
 *
 * Refactor 29 / split of `lifecycle.ts`.
 */

import { eventBus, type Dispose, type EventBus } from '@semantos/state';

import type { CDMLifecycleEvent } from '../types';

/** What a persisted event looks like over the bus. */
export interface LifecycleEffectEvent {
  /** Identifier of the product the event applies to. */
  productCellId: string;
  /** The lifecycle event record itself. */
  event: CDMLifecycleEvent;
  /** Packed cell bytes for the event (linear, anchorable). */
  cell: Uint8Array;
  /** Optional anchor tx id once emitted (terminal events only). */
  anchorTxId?: string;
}

/** Single global bus — one stream of every accepted lifecycle event. */
export const lifecycleEventBus: EventBus<LifecycleEffectEvent> =
  eventBus<LifecycleEffectEvent>();

/** Persisted-event store interface. Tests can bind a fake. */
export interface LifecycleStore {
  putEvent(event: CDMLifecycleEvent): Promise<void> | void;
  putCell(productCellId: string, eventId: string, cell: Uint8Array): Promise<void> | void;
}

/**
 * Wire `store` to receive every event from `lifecycleEventBus`. Returns
 * a `Dispose` so callers (and tests) can tear down the subscription.
 */
export function bindPersistence(store: LifecycleStore): Dispose {
  return lifecycleEventBus.on((effect: LifecycleEffectEvent) => {
    void Promise.resolve()
      .then(() => store.putEvent(effect.event))
      .catch(() => {
        // Persistence failures must not block the in-memory transition.
      });
    void Promise.resolve()
      .then(() =>
        store.putCell(effect.productCellId, effect.event.eventId, effect.cell),
      )
      .catch(() => {
        // Same — non-fatal.
      });
  });
}

/** Emit a lifecycle event onto the bus. Used by the facade. */
export function emitLifecycleEvent(effect: LifecycleEffectEvent): void {
  lifecycleEventBus.emit(effect);
}

```
