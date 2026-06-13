---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/__tests__/persistence.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.508941+00:00
---

# packages/cdm/cdm/src/lifecycle/__tests__/persistence.test.ts

```ts
/**
 * persistence module — bus + store binding for lifecycle events.
 *
 * Refactor 29.
 */

import { describe, expect, test } from 'bun:test';

import {
  bindPersistence,
  emitLifecycleEvent,
  lifecycleEventBus,
  type LifecycleEffectEvent,
  type LifecycleStore,
} from '../persistence';

function makeFixtureEvent(
  productCellId = 'p-1',
  eventId = 'evt-1',
): LifecycleEffectEvent {
  return {
    productCellId,
    event: {
      eventId,
      eventType: 'execution',
      timestamp: 1,
      effectiveDate: '2024-06-15',
      parties: [],
      before: 'proposed',
      after: 'executed',
      productCellId,
    },
    cell: new Uint8Array([1, 2, 3]),
  };
}

describe('lifecycleEventBus', () => {
  test('emits to subscribers', () => {
    const seen: LifecycleEffectEvent[] = [];
    const off = lifecycleEventBus.on((evt: LifecycleEffectEvent) => seen.push(evt));
    emitLifecycleEvent(makeFixtureEvent());
    expect(seen.length).toBe(1);
    expect(seen[0].productCellId).toBe('p-1');
    off();
  });

  test('dispose stops further deliveries', () => {
    const seen: LifecycleEffectEvent[] = [];
    const off = lifecycleEventBus.on((evt: LifecycleEffectEvent) => seen.push(evt));
    off();
    emitLifecycleEvent(makeFixtureEvent('p-2'));
    expect(seen.length).toBe(0);
  });
});

describe('bindPersistence', () => {
  test('forwards events to store.putEvent and store.putCell', async () => {
    const events: string[] = [];
    const cells: Array<{ cellId: string; bytes: Uint8Array }> = [];
    const store: LifecycleStore = {
      putEvent: (e) => {
        events.push(e.eventId);
      },
      putCell: (cellId, _eventId, bytes) => {
        cells.push({ cellId, bytes });
      },
    };
    const off = bindPersistence(store);
    emitLifecycleEvent(makeFixtureEvent('p-3', 'evt-3'));
    // putEvent / putCell are async-wrapped; let microtasks drain.
    await Promise.resolve();
    await Promise.resolve();
    expect(events).toContain('evt-3');
    expect(cells.find((c) => c.cellId === 'p-3')).toBeTruthy();
    off();
  });

  test('store throw does not break other subscribers', async () => {
    const seen: string[] = [];
    const offBad = bindPersistence({
      putEvent: () => {
        throw new Error('boom');
      },
      putCell: () => {
        throw new Error('boom');
      },
    });
    const offGood = lifecycleEventBus.on((evt: LifecycleEffectEvent) => seen.push(evt.event.eventId));
    emitLifecycleEvent(makeFixtureEvent('p-4', 'evt-4'));
    await Promise.resolve();
    expect(seen).toContain('evt-4');
    offBad();
    offGood();
  });
});

```
