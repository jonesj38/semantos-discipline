---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/direct-broadcast/__tests__/utxo-pool-manager.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.808322+00:00
---

# archive/apps-poker-agent/src/direct-broadcast/__tests__/utxo-pool-manager.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import {
  addToPool,
  consumeUtxos,
  getPoolSizes,
  initPools,
  pickFundingUtxo,
  recycleUtxo,
  resetUtxoPoolAtoms,
  returnUtxos,
} from '../utxo-pool-manager';
import type { FundingUtxo } from '../types';

afterEach(() => resetUtxoPoolAtoms());

const fakeTx = {} as any;
const utxo = (id: string, satoshis: number, vout = 0): FundingUtxo => ({
  txid: id,
  vout,
  satoshis,
  sourceTx: fakeTx,
});

describe('utxo-pool-manager', () => {
  test('1. initPools creates N empty pools', () => {
    initPools('e1', 4);
    expect(getPoolSizes('e1')).toEqual([0, 0, 0, 0]);
  });

  test('2. addToPool grows the requested pool only', () => {
    initPools('e1', 2);
    addToPool('e1', 0, [utxo('a', 200), utxo('b', 200)]);
    expect(getPoolSizes('e1')).toEqual([2, 0]);
  });

  test('3. consumeUtxos pops off the front', () => {
    initPools('e1', 1);
    addToPool('e1', 0, [utxo('a', 200), utxo('b', 200), utxo('c', 200)]);
    const taken = consumeUtxos('e1', 0, 2);
    expect(taken.map((u) => u.txid)).toEqual(['a', 'b']);
    expect(getPoolSizes('e1')).toEqual([1]);
  });

  test('4. consumeUtxos throws when pool too small', () => {
    initPools('e1', 1);
    expect(() => consumeUtxos('e1', 0, 1)).toThrow('only 0 available');
  });

  test('5. returnUtxos pushes onto the tail', () => {
    initPools('e1', 1);
    addToPool('e1', 0, [utxo('a', 200)]);
    returnUtxos('e1', 0, [utxo('b', 200)]);
    expect(getPoolSizes('e1')).toEqual([2]);
  });

  test('6. pickFundingUtxo skips dust below MIN_USEFUL_SATS', () => {
    initPools('e1', 1);
    addToPool('e1', 0, [utxo('dust', 100), utxo('good', 200)]);
    const r = pickFundingUtxo('e1', 0, 'op');
    expect(r.utxo.txid).toBe('good');
    expect(r.discardedDust).toBe(100);
  });

  test('7. pickFundingUtxo throws when nothing is left', () => {
    initPools('e1', 1);
    expect(() => pickFundingUtxo('e1', 0, 'op')).toThrow('no more funding UTXOs');
  });

  test('8. recycleUtxo appends back into the pool', () => {
    initPools('e1', 1);
    addToPool('e1', 0, [utxo('a', 200)]);
    recycleUtxo('e1', 0, utxo('change', 200));
    expect(getPoolSizes('e1')).toEqual([2]);
  });

  test('9. distinct engineIds isolate pools', () => {
    initPools('e1', 1);
    initPools('e2', 1);
    addToPool('e1', 0, [utxo('x', 200)]);
    expect(getPoolSizes('e1')).toEqual([1]);
    expect(getPoolSizes('e2')).toEqual([0]);
  });
});

```
