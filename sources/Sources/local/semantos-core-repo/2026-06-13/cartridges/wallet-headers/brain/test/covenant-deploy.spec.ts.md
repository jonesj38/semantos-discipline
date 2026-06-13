---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/covenant-deploy.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.670712+00:00
---

# cartridges/wallet-headers/brain/test/covenant-deploy.spec.ts

```ts
// covenant-deploy spec — the deploy/spend tx assembly + the quine consistency
// check (the part we CAN verify off-chain: the rebuilt next lock is exactly the
// evolved covenant, and the covenant logic is region-independent).

import { describe, expect, test } from 'bun:test';
import { toHex } from '../src/script-macro';
import { compileCovenantScript, DEFAULT_RULE } from '../src/tile-covenant';
import { buildGenesisOutput, buildCovenantSpend, evolveRegion } from '../src/covenant-deploy';
import { computeTxid } from '../src/beef-codec';

const seed = () => new Uint8Array([130, 0, 130, 0, 200, 0, 0, 0, 0]);

describe('evolveRegion — matches the in-script rule', () => {
  test('alive centre (200) with 2 alive neighbours survives → grows to 255', () => {
    // 200 + growStep(64) = 264 → clamp 255
    expect(evolveRegion(seed())[4]).toBe(255);
  });
  test('only the centre changes; the halo ring is carried over', () => {
    const r = seed();
    const n = evolveRegion(r);
    for (let i = 0; i < 9; i++) if (i !== 4) expect(n[i]).toBe(r[i]!);
  });
  test('dead centre with exactly 3 alive neighbours is born', () => {
    const r = new Uint8Array([200, 200, 200, 0, 0, 0, 0, 0, 0]); // centre dead, 3 alive
    expect(evolveRegion(r)[4]).toBe(64); // 0 + growStep
  });
});

describe('the quine self-replication is consistent (off-chain check)', () => {
  test('covenant logic after the state push is region-independent', () => {
    const a = compileCovenantScript(new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9]));
    const b = compileCovenantScript(new Uint8Array([9, 8, 7, 6, 5, 4, 3, 2, 1]));
    expect(toHex(a.slice(10))).toBe(toHex(b.slice(10))); // identical covenantCode
  });
  test('next lock = 0x09 ‖ nextRegion ‖ covenantCode (what BIND reconstructs)', () => {
    const region = seed();
    const next = evolveRegion(region);
    const inputLock = compileCovenantScript(region);
    const nextLock = compileCovenantScript(next);
    const rebuilt = new Uint8Array([0x09, ...next, ...inputLock.slice(10)]);
    expect(toHex(nextLock)).toBe(toHex(rebuilt));
  });
});

describe('buildGenesisOutput', () => {
  test('output script is the covenant carrying the seed region', () => {
    const out = buildGenesisOutput(seed(), 5000n);
    expect(out.satoshis).toBe(5000n);
    expect(out.script[0]).toBe(0x09);            // statePush
    expect(out.script.slice(1, 10)).toEqual(seed());
    expect(out.script.length).toBeGreaterThan(252);
  });
});

describe('buildCovenantSpend', () => {
  const utxo = {
    txid: new Uint8Array(32).fill(0xab),
    vout: 0,
    satoshis: 5000n,
    region: seed(),
  };

  test('one value-preserving output = the evolved covenant', () => {
    const s = buildCovenantSpend({ utxo });
    expect(toHex(s.nextRegion)).toBe(toHex(evolveRegion(seed())));
    expect(toHex(s.nextLock)).toBe(toHex(compileCovenantScript(s.nextRegion)));
    // recompute the txid from the raw bytes as an integrity check
    expect(toHex(s.txid)).toBe(toHex(computeTxid(s.rawTx)));
  });
  test('the preimage embeds the covenant input script (current state) + commits to the output', () => {
    const s = buildCovenantSpend({ utxo });
    const inputLock = compileCovenantScript(seed());
    // BIP143 preimage contains the scriptCode (the covenant being spent)
    expect(toHex(s.preimage).includes(toHex(inputLock))).toBe(true);
  });
  test('a fee input is appended after the covenant input', () => {
    const fee = {
      txid: new Uint8Array(32).fill(0xcd),
      vout: 1,
      value: 2000n,
      lockingScript: new Uint8Array([0x51]),
      unlockScript: new Uint8Array([0x00]),
    };
    const s0 = buildCovenantSpend({ utxo });
    const s1 = buildCovenantSpend({ utxo, feeInputs: [fee] });
    expect(s1.rawTx.length).toBeGreaterThan(s0.rawTx.length); // extra input present
    // output (covenant) is unchanged regardless of the fee input
    expect(toHex(s1.nextLock)).toBe(toHex(s0.nextLock));
  });
});

```
