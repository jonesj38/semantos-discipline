---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/covenant-interp.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.671963+00:00
---

# cartridges/wallet-headers/brain/test/covenant-interp.spec.ts

```ts
// covenant-interp spec — validate the FULL covenant spend (AUTH + TRANSITION +
// BIND) offline with a bignum Script interpreter + real ECDSA. The cell-engine
// proves TRANSITION+BIND (i64); this proves the OP_PUSH_TX AUTH clause it can't
// run, so the whole on-chain spend is verified before a single sat is spent.

import { describe, expect, test, beforeAll } from 'bun:test';
import * as secp from '@noble/secp256k1';
import { sha256 } from '@noble/hashes/sha2';
import { hmac } from '@noble/hashes/hmac';
import { compileCovenantScript } from '../src/tile-covenant';
import { evolveRegion } from '../src/covenant-deploy';
import { buildSighashPreimage, computeSighash, serializeRawTx, buildP2pkhLock } from '../src/tx-builder';
import { compile, pushBytes } from '../src/script-macro';
import { computeTxid } from '../src/beef-codec';
import { evalScript, decodeNum, encodeNum } from '../src/script-interp';

beforeAll(() => {
  secp.etc.hmacSha256Sync = (k: Uint8Array, ...m: Uint8Array[]) => hmac(sha256, k, secp.etc.concatBytes(...m));
});

const REGION = new Uint8Array([0x82, 0, 0x82, 0, 0xc8, 0, 0, 0, 0]); // centre 200, 2 alive nbrs

function setup(outputs: { script: Uint8Array; satoshis: bigint }[]) {
  const covLock = compileCovenantScript(REGION);
  const idLock = buildP2pkhLock(new Uint8Array(20).fill(0x33));
  const genesis = serializeRawTx(
    [{ txid: new Uint8Array(32).fill(0x99), vout: 0, unlockScript: new Uint8Array([0x00]), sequence: 0xffffffff }],
    [{ script: covLock, satoshis: 5000n }, { script: idLock, satoshis: 3000n }],
  );
  const gTxid = computeTxid(genesis.rawTx);
  const inputs = [
    { txid: gTxid, vout: 0, value: 5000n, script: covLock, sequence: 0xffffffff },
    { txid: gTxid, vout: 1, value: 3000n, script: idLock, sequence: 0xffffffff },
  ];
  const preimage = buildSighashPreimage(inputs, outputs, 0);
  const sighash = computeSighash(inputs, outputs, 0);
  const script = new Uint8Array([...compile([pushBytes(preimage)]), ...covLock]);
  return { script, sighash, covLock };
}

describe('ScriptNum BigInt round-trip', () => {
  test('encodes/decodes signed minimal little-endian', () => {
    for (const v of [0n, 1n, -1n, 127n, 128n, 255n, 256n, -255n, 0x010203n, (1n << 250n)]) {
      expect(decodeNum(encodeNum(v))).toBe(v);
    }
  });
});

describe('full covenant spend — offline script validation', () => {
  const next = evolveRegion(REGION);

  test('correct spend (200 → 255) is script-VALID end-to-end', () => {
    const { script, sighash } = setup([{ script: compileCovenantScript(next), satoshis: 5000n }]);
    const r = evalScript(script, sighash);
    expect(r.ok).toBe(true);
    expect(r.finalTrue).toBe(true);   // AUTH + TRANSITION + BIND all pass
    expect(next[4]).toBe(255);
  });

  test('AUTH: a forged preimage (wrong sighash) is rejected by OP_CHECKSIG', () => {
    const { script } = setup([{ script: compileCovenantScript(next), satoshis: 5000n }]);
    const r = evalScript(script, sha256(sha256(new Uint8Array([1, 2, 3]))));
    expect(r.finalTrue).toBe(false);
    expect(r.error).toContain('VERIFY');
  });

  test('TRANSITION/BIND: a wrong next state is rejected', () => {
    const bad = new Uint8Array(next); bad[4] ^= 1;
    const { script, sighash } = setup([{ script: compileCovenantScript(bad), satoshis: 5000n }]);
    expect(evalScript(script, sighash).finalTrue).toBe(false);
  });

  test('BIND: a wrong output value (not value-preserving) is rejected', () => {
    const { script, sighash } = setup([{ script: compileCovenantScript(next), satoshis: 4000n }]);
    expect(evalScript(script, sighash).finalTrue).toBe(false);
  });
});

```
