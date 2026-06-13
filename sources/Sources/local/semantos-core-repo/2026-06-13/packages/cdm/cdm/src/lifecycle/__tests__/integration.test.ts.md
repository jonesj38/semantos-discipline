---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/__tests__/integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.508027+00:00
---

# packages/cdm/cdm/src/lifecycle/__tests__/integration.test.ts

```ts
/**
 * Integration test — full CDM lifecycle through the facade.
 *
 * Replays a synthetic fixture (one trade + ~20 lifecycle events) and
 * checks that:
 *
 *  - the final lifecycle state matches the expected value
 *  - state transitions are deterministic (replay produces the same
 *    state sequence)
 *  - the persistence bus emits one `LifecycleEffectEvent` per
 *    successful transition
 *
 * Refactor 29 — acceptance criterion: "Golden CDM fixture (sample
 * trade + 20 events) produces identical final state."
 */

import { describe, expect, test } from 'bun:test';

import { createCDMProduct, type CDMProduct } from '../../types';
import { CDMLifecycleEngine } from '../lifecycle-facade';
import {
  bindPersistence,
  type LifecycleEffectEvent,
  type LifecycleStore,
} from '../persistence';

interface ScriptStep {
  type:
    | 'execution'
    | 'confirmation'
    | 'clearing'
    | 'rate-reset'
    | 'payment'
    | 'margin-call'
    | 'partial-termination'
    | 'settlement'
    | 'full-termination';
  /** Optional payload for in-place transitions. */
  payload?: Record<string, unknown>;
}

const script: ScriptStep[] = [
  { type: 'execution' },
  { type: 'confirmation' },
  { type: 'clearing' },
  { type: 'rate-reset', payload: { rateReset: { newRate: 0.034, resetDate: '2024-09-15' } } },
  { type: 'payment', payload: { notionalChange: -100 } },
  { type: 'rate-reset', payload: { rateReset: { newRate: 0.033, resetDate: '2024-12-15' } } },
  { type: 'payment', payload: { notionalChange: -100 } },
  { type: 'margin-call', payload: { 'margin-type': 'variation', 'margin-amount': 10_000 } },
  { type: 'rate-reset', payload: { rateReset: { newRate: 0.035, resetDate: '2025-03-15' } } },
  { type: 'payment', payload: { notionalChange: -100 } },
  { type: 'margin-call' },
  { type: 'rate-reset', payload: { rateReset: { newRate: 0.036, resetDate: '2025-06-15' } } },
  { type: 'payment', payload: { notionalChange: -100 } },
  { type: 'rate-reset', payload: { rateReset: { newRate: 0.037, resetDate: '2025-09-15' } } },
  { type: 'payment', payload: { notionalChange: -100 } },
  { type: 'margin-call' },
  { type: 'partial-termination', payload: { notionalChange: -2_000_000 } },
  { type: 'rate-reset', payload: { rateReset: { newRate: 0.04, resetDate: '2026-03-15' } } },
  { type: 'payment', payload: { notionalChange: -100 } },
  { type: 'full-termination' },
];

function makeFreshProduct(): CDMProduct {
  return createCDMProduct(
    'rates.swap.fixed-float',
    {
      notional: { amount: 50_000_000, currency: 'USD' },
      effectiveDate: '2024-06-15',
      terminationDate: '2034-06-15',
      fixedRate: 0.04,
      floatingRateIndex: 'SOFR',
      paymentFrequency: '3M',
      dayCountConvention: 'ACT/360',
    },
    [
      { partyId: 'bank-a', role: 'buyer', capabilities: [2, 9], lei: 'BANKALEIENTITY01' },
      { partyId: 'bank-b', role: 'seller', capabilities: [2, 9], lei: 'BANKBLEIENTITY02' },
      { partyId: 'reporter', role: 'reporting-party', capabilities: [2], lei: 'REPORTER00000001' },
    ],
    '2024-06-15',
  );
}

async function runScript(
  engine: CDMLifecycleEngine,
  product: CDMProduct,
): Promise<{
  finalProduct: CDMProduct;
  states: string[];
  notionals: number[];
}> {
  let current = product;
  const states: string[] = [current.lifecycleState];
  const notionals: number[] = [current.economicTerms.notional.amount];
  for (const [i, step] of script.entries()) {
    const result = await engine.executeEvent(
      current,
      step.type,
      `2024-06-${(15 + (i % 14)).toString().padStart(2, '0')}`,
      step.payload ?? {},
      'actor',
    );
    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error(result.error);
    current = result.value.product;
    states.push(current.lifecycleState);
    notionals.push(current.economicTerms.notional.amount);
  }
  return { finalProduct: current, states, notionals };
}

describe('integration: golden CDM lifecycle replay', () => {
  test('20 events drive product to terminated state with expected notional path', async () => {
    const engine = new CDMLifecycleEngine();
    const { finalProduct, states, notionals } = await runScript(engine, makeFreshProduct());

    expect(finalProduct.lifecycleState).toBe('terminated');
    // 20 events → 21 entries (initial + each transition).
    expect(states.length).toBe(script.length + 1);

    // Notional path:
    //   start at 50_000_000
    //   - 5 × payment(-100) before partial → -500
    //   - partial-termination -2_000_000
    //   - 1 × payment(-100) after partial → -100
    // final = 50_000_000 - 500 - 2_000_000 - 100 = 47_999_400
    expect(finalProduct.economicTerms.notional.amount).toBe(47_999_400);
    expect(notionals[0]).toBe(50_000_000);
    expect(notionals[notionals.length - 1]).toBe(47_999_400);
  });

  test('replay is deterministic — two runs produce identical state path', async () => {
    const engine1 = new CDMLifecycleEngine();
    const engine2 = new CDMLifecycleEngine();
    const r1 = await runScript(engine1, makeFreshProduct());
    const r2 = await runScript(engine2, makeFreshProduct());
    expect(r1.states).toEqual(r2.states);
    expect(r1.notionals).toEqual(r2.notionals);
  });

  test('persistence bus emits one effect per successful transition', async () => {
    const engine = new CDMLifecycleEngine();
    const persisted: LifecycleEffectEvent[] = [];
    const store: LifecycleStore = {
      putEvent: (evt) => {
        persisted.push({
          productCellId: evt.productCellId,
          event: evt,
          cell: new Uint8Array(),
        });
      },
      putCell: () => {},
    };
    const off = bindPersistence(store);

    await runScript(engine, makeFreshProduct());
    // Drain microtasks (putEvent is wrapped in Promise.resolve.then(...)).
    for (let i = 0; i < 4; i++) await Promise.resolve();

    expect(persisted.length).toBe(script.length);
    expect(persisted[persisted.length - 1].event.eventType).toBe('full-termination');
    off();
  });
});

```
