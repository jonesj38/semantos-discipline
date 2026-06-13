---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/effects/__tests__/fee-credit-effect.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.796517+00:00
---

# archive/apps-poker-agent/src/payment-channel/effects/__tests__/fee-credit-effect.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import { effectBus, makeFeeCreditEffect } from '../index';

let dispose: (() => void) | null = null;

afterEach(() => {
  dispose?.();
  dispose = null;
});

function silent(warns: string[] = []) {
  return {
    info: () => {},
    warn: (msg: string) => warns.push(msg),
    debug: () => {},
    error: () => {},
  };
}

describe('fee-credit-effect', () => {
  test('1. credits accumulate per channel', () => {
    const eff = makeFeeCreditEffect({ logger: silent() });
    dispose = eff.dispose;
    effectBus.emit({ type: 'fee-credit', channelId: 'a', reason: 'funding', sats: 1 });
    effectBus.emit({ type: 'fee-credit', channelId: 'a', reason: 'tick', sats: 1 });
    effectBus.emit({ type: 'fee-credit', channelId: 'b', reason: 'funding', sats: 1 });
    expect(eff.totalForChannel('a')).toBe(2);
    expect(eff.totalForChannel('b')).toBe(1);
    expect(eff.total()).toBe(3);
  });

  test('2. ledger is in arrival order', () => {
    const eff = makeFeeCreditEffect({ logger: silent() });
    dispose = eff.dispose;
    effectBus.emit({ type: 'fee-credit', channelId: 'a', reason: 'funding', sats: 1 });
    effectBus.emit({ type: 'fee-credit', channelId: 'a', reason: 'tick', sats: 1 });
    effectBus.emit({ type: 'fee-credit', channelId: 'a', reason: 'settlement', sats: 1 });
    expect(eff.ledger().map((e) => e.reason)).toEqual(['funding', 'tick', 'settlement']);
  });

  test('3. zero / negative sats are ignored with a warning', () => {
    const warns: string[] = [];
    const eff = makeFeeCreditEffect({ logger: silent(warns) });
    dispose = eff.dispose;
    effectBus.emit({ type: 'fee-credit', channelId: 'a', reason: 'funding', sats: 0 });
    effectBus.emit({ type: 'fee-credit', channelId: 'a', reason: 'funding', sats: -1 });
    expect(eff.total()).toBe(0);
    expect(warns.length).toBe(2);
  });

  test('4. dispose stops credits being recorded', () => {
    const eff = makeFeeCreditEffect({ logger: silent() });
    eff.dispose();
    dispose = null;
    effectBus.emit({ type: 'fee-credit', channelId: 'a', reason: 'funding', sats: 1 });
    expect(eff.total()).toBe(0);
  });
});

```
