---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/__tests__/engine-template.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.531084+00:00
---

# packages/game-sdk/src/engine/__tests__/engine-template.test.ts

```ts
/**
 * Toy-engine integration test — exercises the full engine-template
 * flow (reducer → policy gate → dispatcher → handlers → events →
 * persistence) against test-double ports.
 *
 * This is the prompt-22 acceptance test for the abstract pattern
 * layer: a downstream game can construct one engine via
 * `makeEngineTemplate`, bind a fake policy + cell-store, and
 * watch the lifecycle in order.
 */

import { afterEach, describe, expect, test } from 'bun:test';
import {
  cellStorePort,
  noopCellStore,
  resolveCellStore,
  type CellStoreFacade,
} from '../persistence-hook';
import {
  policyPort,
  type PolicyEvaluator,
} from '../policy-hook';
import {
  makeEngineTemplate,
  type EngineTemplate,
} from '../engine-template';

interface ToyState {
  count: number;
}
type ToyAction = { type: 'inc' } | { type: 'dec' };
type ToyEvent = { kind: 'changed'; from: number; to: number };

const reducer = (state: ToyState, action: ToyAction): ToyState =>
  action.type === 'inc'
    ? { count: state.count + 1 }
    : { count: state.count - 1 };

afterEach(() => {
  policyPort.unbind();
  cellStorePort.unbind();
});

function buildToy(opts?: {
  bypassPolicy?: boolean;
  persist?: boolean;
}): EngineTemplate<ToyState, ToyAction, ToyEvent> {
  return makeEngineTemplate<ToyState, ToyAction, ToyEvent>({
    reducer,
    initial: { count: 0 },
    bypassPolicy: opts?.bypassPolicy,
    persistOnChange: opts?.persist
      ? (next) => ({
          path: 'toy/state.json',
          bytes: new TextEncoder().encode(JSON.stringify(next)),
        })
      : undefined,
  });
}

describe('makeEngineTemplate', () => {
  test('1. lifecycle order: policy gate → reducer → handler → event', async () => {
    const policyCalls: string[] = [];
    policyPort.bind({
      evaluate: ({ action }) => {
        policyCalls.push((action as ToyAction).type);
        return { decision: 'accept' };
      },
    } as PolicyEvaluator);
    const toy = buildToy();
    const handlerOrder: string[] = [];
    toy.on('inc', () => handlerOrder.push('handler'));
    toy.events.on((e) => handlerOrder.push(`event:${e.kind}`));
    await toy.dispatch({ type: 'inc' });
    expect(policyCalls).toEqual(['inc']);
    expect(toy.slice.state()).toEqual({ count: 1 });
    expect(handlerOrder[0]).toBe('handler');
  });

  test('2. policy reject blocks the dispatch', async () => {
    policyPort.bind({
      evaluate: () => ({ decision: 'reject', reason: 'nope' }),
    });
    const toy = buildToy();
    let threw = false;
    try {
      await toy.dispatch({ type: 'inc' });
    } catch (err) {
      threw = true;
      expect((err as Error).message).toContain('policy rejected inc');
    }
    expect(threw).toBe(true);
    expect(toy.slice.state()).toEqual({ count: 0 });
  });

  test('3. bypassPolicy skips the gate', async () => {
    policyPort.bind({
      evaluate: () => ({ decision: 'reject', reason: 'always' }),
    });
    const toy = buildToy({ bypassPolicy: true });
    await toy.dispatch({ type: 'inc' });
    expect(toy.slice.state()).toEqual({ count: 1 });
  });

  test('4. persistOnChange writes via cellStorePort on every change', async () => {
    const writes: { path: string; bytes: Uint8Array }[] = [];
    const fake: CellStoreFacade = {
      write: (path, bytes) => {
        writes.push({ path, bytes });
      },
      read: () => null,
      delete: () => {},
      list: () => [],
    };
    cellStorePort.bind(fake);
    const toy = buildToy({ bypassPolicy: true, persist: true });
    await toy.dispatch({ type: 'inc' });
    await toy.dispatch({ type: 'inc' });
    // Allow the microtask queue to drain async writes.
    await new Promise((r) => setTimeout(r, 0));
    expect(writes).toHaveLength(2);
    expect(writes[0].path).toBe('toy/state.json');
    expect(JSON.parse(new TextDecoder().decode(writes[0].bytes))).toEqual({ count: 1 });
  });

  test('5. cellStore() resolves to the bound facade or noop', () => {
    const toy = buildToy({ bypassPolicy: true });
    expect(toy.cellStore()).toBe(noopCellStore);
    cellStorePort.bind(noopCellStore);
    expect(resolveCellStore()).toBe(noopCellStore);
  });

  test('6. multiple handlers fan out', async () => {
    const toy = buildToy({ bypassPolicy: true });
    const seen: number[] = [];
    toy.on('inc', () => seen.push(1));
    toy.on('inc', () => seen.push(2));
    toy.on('inc', () => seen.push(3));
    await toy.dispatch({ type: 'inc' });
    expect(seen).toEqual([1, 2, 3]);
  });
});

```
