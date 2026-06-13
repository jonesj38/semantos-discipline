---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/poker-state-machine/__tests__/utxo-tracker.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.801096+00:00
---

# archive/apps-poker-agent/src/poker-state-machine/__tests__/utxo-tracker.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import {
  canSpendLiveUtxo,
  clearLiveUtxo,
  getLiveUtxo,
  resetUtxoAtoms,
  setLiveUtxo,
  snapshotLiveUtxo,
} from '../utxo-tracker';
import type { LiveUtxo } from '../types';

afterEach(() => resetUtxoAtoms());

function sampleUtxo(opts: Partial<LiveUtxo> = {}): LiveUtxo {
  return {
    txid: 't1',
    vout: 0,
    satoshis: 1,
    lockingScript: '76a9',
    beef: 'beef',
    version: 1,
    cellBytes: new Uint8Array([1, 2, 3]),
    lockedToKey: 'me',
    ...opts,
  };
}

describe('utxo-tracker', () => {
  test('1. starts unbound (null)', () => {
    expect(getLiveUtxo('g-1')).toBeNull();
  });

  test('2. setLiveUtxo + getLiveUtxo round-trip', () => {
    setLiveUtxo('g-1', sampleUtxo());
    expect(getLiveUtxo('g-1')?.txid).toBe('t1');
  });

  test('3. clearLiveUtxo resets to null', () => {
    setLiveUtxo('g-1', sampleUtxo());
    clearLiveUtxo('g-1');
    expect(getLiveUtxo('g-1')).toBeNull();
  });

  test('4. snapshot strips beef + cellBytes', () => {
    setLiveUtxo('g-1', sampleUtxo());
    expect(snapshotLiveUtxo('g-1')).toEqual({
      txid: 't1',
      vout: 0,
      lockedToKey: 'me',
      version: 1,
    });
  });

  test('5. snapshot returns null when unset', () => {
    expect(snapshotLiveUtxo('g-2')).toBeNull();
  });

  test('6. canSpendLiveUtxo true when key matches', () => {
    setLiveUtxo('g-1', sampleUtxo({ lockedToKey: 'me' }));
    expect(canSpendLiveUtxo('g-1', 'me')).toBe(true);
  });

  test('7. canSpendLiveUtxo false when key differs', () => {
    setLiveUtxo('g-1', sampleUtxo({ lockedToKey: 'opponent' }));
    expect(canSpendLiveUtxo('g-1', 'me')).toBe(false);
  });

  test('8. canSpendLiveUtxo false when no UTXO is set', () => {
    expect(canSpendLiveUtxo('g-1', 'me')).toBe(false);
  });

  test('9. distinct gameIds isolate state', () => {
    setLiveUtxo('g-1', sampleUtxo({ txid: 'one' }));
    setLiveUtxo('g-2', sampleUtxo({ txid: 'two' }));
    expect(getLiveUtxo('g-1')?.txid).toBe('one');
    expect(getLiveUtxo('g-2')?.txid).toBe('two');
  });
});

```
