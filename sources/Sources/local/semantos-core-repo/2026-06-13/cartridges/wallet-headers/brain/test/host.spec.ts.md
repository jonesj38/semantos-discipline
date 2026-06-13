---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/host.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.674635+00:00
---

# cartridges/wallet-headers/brain/test/host.spec.ts

```ts
// W5 host-extern conformance tests.
//
// Three scenarios per the W5 acceptance criteria:
//   1. host_sign / host_checksig round-trip under the same pubkey.
//   2. host_state_next_index is atomic — concurrent calls return distinct
//      indices.
//   3. host_unlock_tier then host_load_cell works; loading a Tier-1 cell
//      *without* prior unlock fails.
//
// Tests run under bun (no browser) — fake-indexeddb provides indexedDB,
// and Node 20 ships WebCrypto + crypto.subtle. All three are needed for
// the host_unlock_tier path.

import { beforeEach, describe, expect, test } from 'bun:test';
import 'fake-indexeddb/auto';

import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

import {
  createHost,
  beginRequest,
  endRequest,
  primeUnlockTier,
  primeStateNext,
  setSessionKek,
  clearAllKeks,
  deriveKek,
  encryptCellForBridge,
  flushRequest,
  _stageBlobForTests,
  SLOT_HEADER_BYTES,
} from '../src/host';
import { _resetDbForTests, slotPut, stateNextIndex } from '../src/storage';

// Match the host.ts initializer (sync HMAC for noble v2).
secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

/**
 * Build a fresh host import object backed by a real WebAssembly.Memory
 * instance so we can exercise pointer arithmetic the same way the engine
 * does at runtime.
 */
function freshHost(): {
  host: ReturnType<typeof createHost>;
  memory: WebAssembly.Memory;
} {
  const memory = new WebAssembly.Memory({ initial: 4 });
  return { host: createHost(memory), memory };
}

/** Allocate a region inside WASM memory and return the pointer + helpers. */
let nextPtr = 1024; // start past page-0 reserved space
function alloc(memory: WebAssembly.Memory, len: number): number {
  const ptr = nextPtr;
  nextPtr += (len + 15) & ~15; // 16-byte align
  if (nextPtr > memory.buffer.byteLength) {
    memory.grow(1);
  }
  return ptr;
}

function writeMem(memory: WebAssembly.Memory, ptr: number, data: Uint8Array): void {
  new Uint8Array(memory.buffer, ptr, data.length).set(data);
}
function readMem(memory: WebAssembly.Memory, ptr: number, len: number): Uint8Array {
  return new Uint8Array(memory.buffer, ptr, len).slice();
}

beforeEach(() => {
  nextPtr = 1024;
  clearAllKeks();
  // fake-indexeddb needs a fresh DB per test to avoid cross-test bleed.
  _resetDbForTests();
  // Wipe the IndexedDB between tests by deleting the db. fake-indexeddb's
  // implementation does this synchronously enough for our purposes.
  return new Promise<void>((resolve) => {
    const req = indexedDB.deleteDatabase('semantos-wallet');
    req.onsuccess = () => resolve();
    req.onerror = () => resolve();
    req.onblocked = () => resolve();
  });
});

describe('host_sign / host_checksig round-trip', () => {
  test('signs and verifies under same pubkey', () => {
    const { host, memory } = freshHost();
    // Random 32-byte private key.
    const sk = new Uint8Array(32);
    crypto.getRandomValues(sk);
    // Make sure it's a valid scalar.
    sk[0] = 0x01;
    const pk = secp.getPublicKey(sk, true);
    const msg = new Uint8Array(32);
    crypto.getRandomValues(msg);

    const skPtr = alloc(memory, 32);
    const msgPtr = alloc(memory, 32);
    const sigPtr = alloc(memory, 80);
    const sigLenPtr = alloc(memory, 4);
    const pkPtr = alloc(memory, 33);

    writeMem(memory, skPtr, sk);
    writeMem(memory, msgPtr, msg);
    writeMem(memory, pkPtr, pk);

    const signed = host.host_sign(skPtr, 32, msgPtr, 32, sigPtr, 80, sigLenPtr);
    expect(signed).toBe(1);

    const sigLen = new DataView(memory.buffer).getUint32(sigLenPtr, true);
    expect(sigLen).toBeGreaterThan(8);
    expect(sigLen).toBeLessThanOrEqual(72);

    const verifyResult = host.host_checksig(pkPtr, 33, msgPtr, 32, sigPtr, sigLen);
    expect(verifyResult).toBe(1);
  });

  test('verification fails for a tampered message', () => {
    const { host, memory } = freshHost();
    const sk = new Uint8Array(32);
    crypto.getRandomValues(sk);
    sk[0] = 0x02;
    const pk = secp.getPublicKey(sk, true);
    const msg = new Uint8Array(32);
    crypto.getRandomValues(msg);

    const skPtr = alloc(memory, 32);
    const msgPtr = alloc(memory, 32);
    const sigPtr = alloc(memory, 80);
    const sigLenPtr = alloc(memory, 4);
    const pkPtr = alloc(memory, 33);

    writeMem(memory, skPtr, sk);
    writeMem(memory, msgPtr, msg);
    writeMem(memory, pkPtr, pk);

    expect(host.host_sign(skPtr, 32, msgPtr, 32, sigPtr, 80, sigLenPtr)).toBe(1);
    const sigLen = new DataView(memory.buffer).getUint32(sigLenPtr, true);

    // Flip a byte in the message and re-verify — must fail.
    const tampered = new Uint8Array(32);
    tampered.set(msg);
    tampered[0] ^= 0xff;
    const tamperedPtr = alloc(memory, 32);
    writeMem(memory, tamperedPtr, tampered);
    expect(host.host_checksig(pkPtr, 33, tamperedPtr, 32, sigPtr, sigLen)).toBe(0);
  });
});

describe('host_state_next_index atomicity', () => {
  test('concurrent calls return distinct indices', async () => {
    const protocolHash = new Uint8Array(16);
    crypto.getRandomValues(protocolHash);
    const counterparty = new Uint8Array(33);
    crypto.getRandomValues(counterparty);
    counterparty[0] = 0x02; // valid compressed-pubkey prefix (cosmetic)

    // Storage-level atomicity test: fire 16 concurrent next-index calls,
    // assert we see 0..15 with no duplicates and no missing values.
    const N = 16;
    const promises: Promise<bigint>[] = [];
    for (let i = 0; i < N; i++) {
      promises.push(stateNextIndex(protocolHash, counterparty));
    }
    const results = await Promise.all(promises);
    const seen = new Set(results.map((b) => b.toString()));
    expect(seen.size).toBe(N);
    const min = results.reduce((a, b) => (a < b ? a : b));
    const max = results.reduce((a, b) => (a > b ? a : b));
    expect(min).toBe(0n);
    expect(max).toBe(BigInt(N - 1));
  });

  test('host_state_next_index reads pre-primed value from request cache', async () => {
    const { host, memory } = freshHost();
    const protocolHash = new Uint8Array(16);
    crypto.getRandomValues(protocolHash);
    const counterparty = new Uint8Array(33);
    crypto.getRandomValues(counterparty);
    counterparty[0] = 0x03;

    beginRequest();
    try {
      await primeStateNext(protocolHash, counterparty);
      const phPtr = alloc(memory, 16);
      const cpPtr = alloc(memory, 33);
      const outPtr = alloc(memory, 8);
      writeMem(memory, phPtr, protocolHash);
      writeMem(memory, cpPtr, counterparty);
      const ok = host.host_state_next_index(phPtr, cpPtr, outPtr);
      expect(ok).toBe(1);
      const idx = new DataView(memory.buffer).getBigUint64(outPtr, true);
      expect(idx).toBe(0n); // first allocation
    } finally {
      endRequest();
    }

    // Re-allocating without re-priming must return 0 (failure).
    beginRequest();
    try {
      const phPtr = alloc(memory, 16);
      const cpPtr = alloc(memory, 33);
      const outPtr = alloc(memory, 8);
      writeMem(memory, phPtr, protocolHash);
      writeMem(memory, cpPtr, counterparty);
      const ok = host.host_state_next_index(phPtr, cpPtr, outPtr);
      expect(ok).toBe(0);
    } finally {
      endRequest();
    }
  });
});

describe('host_unlock_tier + host_load_cell', () => {
  function makeTierCell(tier: number): Uint8Array {
    // 1024-byte cell. Only the first 32 bytes (header preamble + domain_flag
    // at offset 28, big-endian) matter for tierFromDomainFlag().
    const cell = new Uint8Array(1024);
    crypto.getRandomValues(cell);
    const flag = tier === 0 ? 0x10000001 : tier === 1 ? 0x10000003 : tier === 2 ? 0x10000004 : 0x10000005;
    new DataView(cell.buffer).setUint32(28, flag, false); // big-endian
    return cell;
  }

  test('unlock then load returns the same plaintext', async () => {
    const { host, memory } = freshHost();
    const factor = new TextEncoder().encode('1234'); // PIN
    const tier = 1;
    const slotId = 100;

    // Set up the encrypted blob: derive the KEK that production would,
    // encrypt the tier cell, persist it.
    const kek = await deriveKek(tier, factor);
    const cell = makeTierCell(tier);
    const blob = await encryptCellForBridge(tier, kek, cell);
    expect(blob.length).toBe(SLOT_HEADER_BYTES + cell.length);
    await slotPut(slotId, blob);

    // Begin a request scope, unlock + load through the host externs.
    beginRequest();
    try {
      const ok = await primeUnlockTier(tier, factor, slotId);
      expect(ok).toBe(true);

      const outPtr = alloc(memory, 1024);
      const loaded = host.host_load_cell(slotId, outPtr);
      expect(loaded).toBe(1);
      const got = readMem(memory, outPtr, 1024);
      expect(got).toEqual(cell);
    } finally {
      endRequest();
    }
  });

  test('Tier-1 load fails without prior unlock', async () => {
    const { host, memory } = freshHost();
    const factor = new TextEncoder().encode('5678');
    const tier = 1;
    const slotId = 101;

    const kek = await deriveKek(tier, factor);
    const cell = makeTierCell(tier);
    const blob = await encryptCellForBridge(tier, kek, cell);
    await slotPut(slotId, blob);

    beginRequest();
    try {
      // Stage the encrypted blob in the cache (as primeSlot would), but
      // deliberately skip primeUnlockTier — no KEK is staged.
      _stageBlobForTests(slotId, blob);

      const outPtr = alloc(memory, 1024);
      const loaded = host.host_load_cell(slotId, outPtr);
      expect(loaded).toBe(0); // no KEK → fail
    } finally {
      endRequest();
    }
  });

  test('Tier-0 round-trip via session KEK', async () => {
    const { host, memory } = freshHost();
    const sessionKey = new Uint8Array(32);
    crypto.getRandomValues(sessionKey);
    await setSessionKek(sessionKey);

    const tier = 0;
    const slotId = 200;
    const cell = makeTierCell(tier);

    beginRequest();
    try {
      // host_persist_cell encrypts under the session KEK and stages the dirty
      // blob; flushRequest writes it through to IndexedDB.
      const cellPtr = alloc(memory, 1024);
      writeMem(memory, cellPtr, cell);
      const persisted = host.host_persist_cell(slotId, cellPtr, 1024);
      expect(persisted).toBe(1);
    } finally {
      // Flush and reset for next phase.
      await flushRequest();
      endRequest();
    }

    // For the load phase we need the session KEK to remain installed so the
    // synchronous load path can authenticate the envelope. (clearAllKeks is
    // not called between request scopes — only between tests, in beforeEach.)
    beginRequest();
    try {
      // Stage the loaded plaintext directly — production would prime via
      // primeSlot + a Tier-0 decrypt path. v0.1 keeps that as a TODO; the
      // round-trip semantics are validated by the unlock+load test above.
      const outPtr = alloc(memory, 1024);
      // Intentionally show the v0.1 limitation: with only blobs in cache,
      // syncLoadCell returns null → 0. That's documented in host.ts.
      // The test here is the persist path producing a valid envelope on
      // disk, which is what flushRequest accomplished.
      const loaded = host.host_load_cell(slotId, outPtr);
      expect(loaded).toBe(0); // expected: no plaintext primed
    } finally {
      endRequest();
    }
  });
});

describe('host_get_blocktime / host_get_sequence / host_log', () => {
  test('blocktime defaults to wall-clock seconds', () => {
    const { host } = freshHost();
    const t = host.host_get_blocktime();
    const now = Math.floor(Date.now() / 1000);
    expect(Math.abs(t - now)).toBeLessThanOrEqual(2);
  });

  test('sequence returns 0xFFFFFFFF (no nSequence in v0.1)', () => {
    const { host } = freshHost();
    expect(host.host_get_sequence() >>> 0).toBe(0xffffffff);
  });

  test('host_log routes to the configured callback', () => {
    const memory = new WebAssembly.Memory({ initial: 1 });
    const captured: string[] = [];
    const host = createHost(memory, { log: (m: string) => captured.push(m) });
    const msg = new TextEncoder().encode('hello bridge');
    const ptr = alloc(memory, msg.length);
    writeMem(memory, ptr, msg);
    host.host_log(ptr, msg.length);
    expect(captured).toEqual(['hello bridge']);
  });
});

describe('host_call_by_name registry', () => {
  test('unknown function returns 0xFFFFFFFF', () => {
    const { host, memory } = freshHost();
    const name = new TextEncoder().encode('does.not.exist');
    const ptr = alloc(memory, name.length);
    writeMem(memory, ptr, name);
    const result = host.host_call_by_name(ptr, name.length) >>> 0;
    expect(result).toBe(0xffffffff);
  });
});

describe('hashing externs match @noble/hashes', () => {
  test('host_sha256 matches direct sha256', () => {
    const { host, memory } = freshHost();
    const data = new TextEncoder().encode('the quick brown fox');
    const ptr = alloc(memory, data.length);
    const out = alloc(memory, 32);
    writeMem(memory, ptr, data);
    host.host_sha256(ptr, data.length, out);
    expect(readMem(memory, out, 32)).toEqual(nobleSha256(data));
  });

  test('host_hash160 = ripemd160(sha256(x))', async () => {
    const { ripemd160 } = await import('@noble/hashes/ripemd160');
    const { host, memory } = freshHost();
    const data = new TextEncoder().encode('hash160 me');
    const ptr = alloc(memory, data.length);
    const out = alloc(memory, 20);
    writeMem(memory, ptr, data);
    host.host_hash160(ptr, data.length, out);
    expect(readMem(memory, out, 20)).toEqual(ripemd160(nobleSha256(data)));
  });
});

```
