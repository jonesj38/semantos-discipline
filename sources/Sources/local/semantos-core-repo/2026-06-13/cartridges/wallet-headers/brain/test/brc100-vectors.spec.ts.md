---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/brc100-vectors.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.668241+00:00
---

# cartridges/wallet-headers/brain/test/brc100-vectors.spec.ts

```ts
// Pinned BRC-100 canonical-digest test vectors (W7 cross-runtime interop).
//
// Per `docs/design/BRC100-CANONICAL-DIGEST.md` §8 these vectors are
// reproduced bit-for-bit by the W6 Zig runtime in
// `runtime/node/tests/brc100_vectors.zig`. The two test files together are
// the cross-runtime interop guarantee — the W7 reconciliation contract.

import { describe, expect, test } from 'bun:test';
import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

import { envelopeDigest, hexToBytes, bytesToHex } from '../src/brc100';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

// Vector 1 — empty body, sk=0x01.
const VECTOR_1 = {
  sk: '0000000000000000000000000000000000000000000000000000000000000001',
  identityKey: '0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
  nonce: '00'.repeat(32),
  timestamp: 0,
  body: '', // utf-8 empty
  digest: '9967659398ba69b0913a7d5eb65b58a9a390d2ab1584cb77bb4dbdd505a9eaed',
};

// Vector 2 — RPC body, ts = 0x66666666 (which fits in u32 LE).
const VECTOR_2 = {
  sk: VECTOR_1.sk,
  identityKey: VECTOR_1.identityKey,
  nonce: 'ff'.repeat(32),
  timestamp: 0x66666666,
  body: '{"method":"getPublicKey","params":{},"id":"req-1"}',
  digest: 'd8bb125589659f49df927ca2da6510ac8fb4d6bffa957ed5519253db59b653d5',
};

describe('BRC-100 canonical digest test vectors', () => {
  test('Vector 1: empty body, sk=0x01, all-zero nonce, ts=0', () => {
    const sk = hexToBytes(VECTOR_1.sk);
    const pk = secp.getPublicKey(sk, true);
    expect(bytesToHex(pk)).toBe(VECTOR_1.identityKey);

    const d = envelopeDigest({
      identityKey: pk,
      nonce: hexToBytes(VECTOR_1.nonce),
      timestamp: VECTOR_1.timestamp,
      body: new TextEncoder().encode(VECTOR_1.body),
    });
    expect(bytesToHex(d)).toBe(VECTOR_1.digest);
  });

  test('Vector 2: RPC body, all-ff nonce, ts=0x66666666', () => {
    const pk = hexToBytes(VECTOR_2.identityKey);
    const d = envelopeDigest({
      identityKey: pk,
      nonce: hexToBytes(VECTOR_2.nonce),
      timestamp: VECTOR_2.timestamp,
      body: new TextEncoder().encode(VECTOR_2.body),
    });
    expect(bytesToHex(d)).toBe(VECTOR_2.digest);
  });
});

```
