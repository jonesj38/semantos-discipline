---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/direct-broadcast/__tests__/funding-acquisition.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.806678+00:00
---

# archive/apps-poker-agent/src/direct-broadcast/__tests__/funding-acquisition.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { estimateFanOutFee, ingestFundingTx } from '../funding-acquisition';
import { Transaction, PrivateKey, P2PKH } from '@bsv/sdk';

describe('estimateFanOutFee', () => {
  test('1. monotonically increasing in numOutputs', () => {
    expect(estimateFanOutFee(1)).toBeLessThan(estimateFanOutFee(10));
    expect(estimateFanOutFee(10)).toBeLessThan(estimateFanOutFee(100));
  });

  test('2. matches the legacy formula (overhead + input + output*(N+1))', () => {
    // legacy: (10 + 148 + 34*(N+1)) * 1
    for (const n of [1, 5, 50, 500]) {
      expect(estimateFanOutFee(n)).toBe(10 + 148 + 34 * (n + 1));
    }
  });
});

describe('ingestFundingTx', () => {
  test('3. parses txid + satoshis from the supplied raw tx', async () => {
    const pk = PrivateKey.fromRandom();
    const pub = pk.toPublicKey();
    const p2pkh = new P2PKH();
    // Build a self-contained tx so we don't need a real source UTXO.
    const tx = new Transaction();
    tx.addOutput({ lockingScript: p2pkh.lock(pub.toAddress()), satoshis: 1000 });
    const hex = tx.toHex();
    const utxo = ingestFundingTx(hex, 0);
    expect(utxo.satoshis).toBe(1000);
    expect(utxo.vout).toBe(0);
    expect(utxo.txid.length).toBe(64);
    expect(utxo.sourceTx).toBeDefined();
  });
});

```
