---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/effects/__tests__/broadcast-effect.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.797112+00:00
---

# archive/apps-poker-agent/src/payment-channel/effects/__tests__/broadcast-effect.test.ts

```ts
import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import {
  broadcasterPort,
  type Broadcaster,
  type BroadcastResult,
} from '@semantos/protocol-types/ports';
import { effectBus, makeBroadcastEffect } from '../index';

let dispose: (() => void) | null = null;

afterEach(() => {
  dispose?.();
  dispose = null;
  broadcasterPort.unbind();
});

beforeEach(() => {
  broadcasterPort.unbind();
});

function silentLogger(errs: string[] = []) {
  return {
    info: () => {},
    warn: () => {},
    debug: () => {},
    error: (msg: string) => errs.push(msg),
  };
}

describe('broadcast-effect', () => {
  test('1. forwards rawTx to broadcasterPort.broadcast', async () => {
    const seen: string[] = [];
    const stub: Broadcaster = {
      broadcast: async (raw) => {
        seen.push(typeof raw === 'string' ? raw : raw.join(','));
        return { ok: true, txid: 'abc' };
      },
    };
    broadcasterPort.bind(stub);
    const eff = makeBroadcastEffect({ logger: silentLogger() });
    dispose = eff.dispose;
    effectBus.emit({
      type: 'broadcast',
      channelId: 'c1',
      rawTx: 'deadbeef',
      label: 'funding',
    });
    await new Promise((r) => setTimeout(r, 5));
    expect(seen).toEqual(['deadbeef']);
  });

  test('2. surfaces broadcaster failures to onResult', async () => {
    const stub: Broadcaster = {
      broadcast: async () => ({ ok: false, txid: '', error: 'nope' }),
    };
    broadcasterPort.bind(stub);
    const results: BroadcastResult[] = [];
    const eff = makeBroadcastEffect({
      logger: silentLogger(),
      onResult: (_id, _label, r) => results.push(r),
    });
    dispose = eff.dispose;
    effectBus.emit({
      type: 'broadcast',
      channelId: 'c1',
      rawTx: 'aa',
      label: 'settlement',
    });
    await new Promise((r) => setTimeout(r, 5));
    expect(results).toHaveLength(1);
    expect(results[0].ok).toBe(false);
    expect(results[0].error).toBe('nope');
  });

  test('3. logs error when broadcasterPort is unbound', async () => {
    const errs: string[] = [];
    const eff = makeBroadcastEffect({ logger: silentLogger(errs) });
    dispose = eff.dispose;
    effectBus.emit({
      type: 'broadcast',
      channelId: 'c1',
      rawTx: 'aa',
      label: 'funding',
    });
    await new Promise((r) => setTimeout(r, 5));
    expect(errs.some((e) => e.includes('unbound'))).toBe(true);
  });

  test('4. swallowed thrown errors do not crash the bus', async () => {
    broadcasterPort.bind({
      broadcast: async () => {
        throw new Error('boom');
      },
    });
    const errs: string[] = [];
    const eff = makeBroadcastEffect({ logger: silentLogger(errs) });
    dispose = eff.dispose;
    let crashed = false;
    try {
      effectBus.emit({
        type: 'broadcast',
        channelId: 'c1',
        rawTx: 'aa',
        label: 'funding',
      });
      await new Promise((r) => setTimeout(r, 5));
    } catch {
      crashed = true;
    }
    expect(crashed).toBe(false);
    expect(errs.some((e) => e.includes('threw'))).toBe(true);
  });

  test('5. dispose unsubscribes', async () => {
    let count = 0;
    broadcasterPort.bind({
      broadcast: async () => {
        count++;
        return { ok: true, txid: 'x' };
      },
    });
    const eff = makeBroadcastEffect({ logger: silentLogger() });
    eff.dispose();
    dispose = null;
    effectBus.emit({
      type: 'broadcast',
      channelId: 'c1',
      rawTx: 'aa',
      label: 'funding',
    });
    await new Promise((r) => setTimeout(r, 5));
    expect(count).toBe(0);
  });
});

```
