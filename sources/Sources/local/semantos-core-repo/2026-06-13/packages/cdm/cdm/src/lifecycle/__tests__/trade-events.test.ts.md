---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/cdm/cdm/src/lifecycle/__tests__/trade-events.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.507362+00:00
---

# packages/cdm/cdm/src/lifecycle/__tests__/trade-events.test.ts

```ts
/**
 * trade-events module — pure transition table + validators.
 *
 * Refactor 29.
 */

import { describe, expect, test } from 'bun:test';

import { createCDMProduct } from '../../types';
import {
  TRANSITION_TABLE,
  canTransition,
  isTerminalEvent,
  nextStateFor,
  validEventsFor,
  validateTradeEvent,
  economicEffectFrom,
  type TradeEvent,
} from '../trade-events';

describe('trade-events: transition table', () => {
  test('proposed → executed via execution', () => {
    expect(nextStateFor('proposed', 'execution')).toBe('executed');
  });

  test('executed → confirmed via confirmation', () => {
    expect(nextStateFor('executed', 'confirmation')).toBe('confirmed');
  });

  test('terminated has no outgoing events', () => {
    expect(validEventsFor('terminated')).toEqual([]);
  });

  test('unknown transition is rejected', () => {
    expect(canTransition('proposed', 'confirmation')).toBe(false);
    expect(nextStateFor('proposed', 'confirmation')).toBeUndefined();
  });

  test('TRANSITION_TABLE covers every CDMLifecycleState', () => {
    const expected = [
      'proposed', 'executed', 'confirmed', 'cleared', 'settled',
      'novated', 'partially-terminated', 'terminated', 'defaulted', 'close-out',
    ];
    for (const state of expected) {
      expect(state in TRANSITION_TABLE).toBe(true);
    }
  });
});

describe('trade-events: terminal events', () => {
  test('execution, novation, settlement, full-termination, close-out-netting are terminal', () => {
    expect(isTerminalEvent('execution')).toBe(true);
    expect(isTerminalEvent('novation')).toBe(true);
    expect(isTerminalEvent('settlement')).toBe(true);
    expect(isTerminalEvent('full-termination')).toBe(true);
    expect(isTerminalEvent('close-out-netting')).toBe(true);
  });

  test('confirmation, payment, rate-reset are NOT terminal', () => {
    expect(isTerminalEvent('confirmation')).toBe(false);
    expect(isTerminalEvent('payment')).toBe(false);
    expect(isTerminalEvent('rate-reset')).toBe(false);
  });
});

describe('trade-events: validateTradeEvent', () => {
  function makeProduct(state: string = 'proposed') {
    const p = createCDMProduct(
      'rates.swap.fixed-float',
      {
        notional: { amount: 1_000_000, currency: 'USD' },
        effectiveDate: '2024-06-15',
        terminationDate: '2025-06-15',
      },
      [{ partyId: 'p1', role: 'buyer', capabilities: [] }],
      '2024-06-15',
    );
    p.lifecycleState = state as any;
    return p;
  }

  test('rejects an event whose transition is not in the table', () => {
    const product = makeProduct('terminated');
    const evt: TradeEvent = {
      type: 'confirmation',
      effectiveDate: '2024-06-16',
      payload: {},
    };
    const result = validateTradeEvent(product, evt);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toContain("Cannot apply 'confirmation'");
      expect(result.error).toContain("'terminated'");
    }
  });

  test('rejects partial-termination with positive notionalChange', () => {
    const product = makeProduct('confirmed');
    const evt: TradeEvent = {
      type: 'partial-termination',
      effectiveDate: '2024-06-16',
      payload: { notionalChange: 1_000 },
    };
    const result = validateTradeEvent(product, evt);
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toContain('partial-termination expects a negative');
    }
  });

  test('accepts a valid execution event', () => {
    const product = makeProduct('proposed');
    const evt: TradeEvent = {
      type: 'execution',
      effectiveDate: '2024-06-15',
      payload: {},
    };
    expect(validateTradeEvent(product, evt).ok).toBe(true);
  });
});

describe('trade-events: economicEffectFrom', () => {
  test('extracts notionalChange', () => {
    const eff = economicEffectFrom({ notionalChange: -500 });
    expect(eff?.notionalChange).toBe(-500);
  });

  test('extracts rateReset', () => {
    const eff = economicEffectFrom({
      rateReset: { newRate: 0.05, resetDate: '2024-07-01' },
    });
    expect(eff?.rateReset?.newRate).toBe(0.05);
  });

  test('returns undefined when payload has no economic fields', () => {
    expect(economicEffectFrom({})).toBeUndefined();
    expect(economicEffectFrom({ misc: 'foo' })).toBeUndefined();
  });
});

```
