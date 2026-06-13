---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/direct-broadcast/__tests__/tx-flow.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.806961+00:00
---

# archive/apps-poker-agent/src/direct-broadcast/__tests__/tx-flow.test.ts

```ts
/**
 * `runTxFlow` integration tests — drive the full pick-build-broadcast-
 * recycle pipeline against a stub `broadcasterPort` recorder.
 */

import { afterEach, describe, expect, test } from 'bun:test';
import {
  broadcasterPort,
  type Broadcaster,
} from '@semantos/protocol-types/ports';
import {
  addToPool,
  initPools,
  resetUtxoPoolAtoms,
  getPoolSizes,
} from '../utxo-pool-manager';
import {
  attachStatsCollector,
  resetDirectBroadcastStats,
  selectStats,
} from '../tx-stats-collector';
import { runTxFlow } from '../tx-flow';
import type { FundingUtxo } from '../types';

afterEach(() => {
  resetUtxoPoolAtoms();
  resetDirectBroadcastStats();
  broadcasterPort.unbind();
});

function recorder(): Broadcaster & { calls: string[] } {
  const calls: string[] = [];
  const b = {
    broadcast: async (rawTx: string | number[]) => {
      calls.push(typeof rawTx === 'string' ? rawTx : rawTx.join(','));
      return { ok: true, txid: 'broadcast-txid' };
    },
  } as Broadcaster & { calls: string[] };
  (b as any).calls = calls;
  return b;
}

const fakeTx = (id: string) => ({
  toHex: () => `hex-${id}`,
  id: () => id,
});

const fakeUtxo = (id: string): FundingUtxo => ({
  txid: id,
  vout: 0,
  satoshis: 200,
  sourceTx: {} as any,
});

describe('runTxFlow', () => {
  test('1. preserves ordering across 100 broadcasts', async () => {
    initPools('e1', 1);
    for (let i = 0; i < 100; i++) addToPool('e1', 0, [fakeUtxo(`f${i}`)]);
    const rec = recorder();
    broadcasterPort.bind(rec);
    attachStatsCollector('e1');

    for (let i = 0; i < 100; i++) {
      await runTxFlow(
        {
          engineId: 'e1',
          streamId: 0,
          label: 'T',
          fireAndForget: false,
          trackPending: () => {},
        },
        async () => ({
          tx: fakeTx(`tx${i}`) as any,
          change: null,
        }),
      );
    }
    expect(rec.calls.length).toBe(100);
    expect(rec.calls[0]).toBe('hex-tx0');
    expect(rec.calls[99]).toBe('hex-tx99');
    expect(selectStats('e1').totalBroadcast).toBe(100);
  });

  test('2. recycles change utxo back into the pool', async () => {
    initPools('e1', 1);
    addToPool('e1', 0, [fakeUtxo('f1')]);
    broadcasterPort.bind(recorder());
    attachStatsCollector('e1');

    await runTxFlow(
      {
        engineId: 'e1',
        streamId: 0,
        label: 'T',
        fireAndForget: false,
        trackPending: () => {},
      },
      async () => ({
        tx: fakeTx('a') as any,
        change: { txid: 'a', vout: 1, satoshis: 50, sourceTx: {} as any },
      }),
    );
    expect(getPoolSizes('e1')).toEqual([1]);
  });

  test('3. fire-and-forget records broadcastMs=0', async () => {
    initPools('e1', 1);
    addToPool('e1', 0, [fakeUtxo('f1')]);
    broadcasterPort.bind(recorder());
    attachStatsCollector('e1');

    const tracked: Promise<void>[] = [];
    const result = await runTxFlow(
      {
        engineId: 'e1',
        streamId: 0,
        label: 'T',
        fireAndForget: true,
        trackPending: (p) => tracked.push(p),
      },
      async () => ({ tx: fakeTx('a') as any, change: null }),
    );
    expect(result.broadcastMs).toBe(0);
    await Promise.all(tracked);
    expect(selectStats('e1').totalBroadcast).toBe(1);
  });

  test('4. broadcaster failure surfaces as broadcast-error event', async () => {
    initPools('e1', 1);
    addToPool('e1', 0, [fakeUtxo('f1')]);
    broadcasterPort.bind({
      broadcast: async () => ({ ok: false, txid: '', error: 'rejected' }),
    });
    attachStatsCollector('e1');

    let threw = false;
    try {
      await runTxFlow(
        {
          engineId: 'e1',
          streamId: 0,
          label: 'T',
          fireAndForget: false,
          trackPending: () => {},
        },
        async () => ({ tx: fakeTx('a') as any, change: null }),
      );
    } catch (err) {
      threw = true;
      expect((err as Error).message).toContain('rejected');
    }
    expect(threw).toBe(true);
    expect(selectStats('e1').errors[0]).toContain('rejected');
  });
});

```
