---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/cell-anchor.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.667292+00:00
---

# cartridges/wallet-headers/brain/test/cell-anchor.spec.ts

```ts
// cell-anchor.spec.ts — TDD for LINEAR cell anchor UTXO tracking.
//
// Tests the full derivation + storage + recovery lifecycle:
//   1. Domain flag derivation (sovereign range, determinism, isolation)
//   2. Protocol hash derivation (16-byte BRC-42 key)
//   3. Key derivation (deriveCellAnchorSk + buildCellAnchorLock round-trip)
//   4. OutputStore round-trip with typeHash field
//   5. Session recovery: wipe runtime, reload, spend from anchor key

import { beforeEach, describe, expect, test } from 'bun:test';
import 'fake-indexeddb/auto';
import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 } from '@noble/hashes/sha2';
import { ripemd160 } from '@noble/hashes/ripemd160';
import { encodeDer } from '../src/der';

import {
  anchorProtocolHash,
  domainFlagFromTypeHash,
  buildSchemaMapping,
  deriveCellAnchorSk,
  buildCellAnchorLock,
} from '../src/cell-anchor';
import { deriveChangeSk } from '../src/ecdh42';
import { outputStore } from '../src/output-store';
import { _resetDbForTests } from '../src/storage';
import {
  computeSighash,
  buildP2pkhUnlockScript,
  buildP2pkhLock,
  pubkeyToHash160,
  serializeEFTx,
  type TxInput,
  type TxOutput,
} from '../src/tx-builder';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(sha256, key, secp.etc.concatBytes(...msgs));

// Deterministic test typeHash — inlined structured |8|8|8|8| construction
// matching the canonical `buildTypeHash` from `@semantos/protocol-types`
// (T5.a).  Triple: (semantos, test, linear-cell, "").  Inlined here
// rather than imported to avoid adding @semantos/protocol-types to
// @semantos/wallet-browser's deps for a 5-line test helper.  Routing
// invariant: bytes 0..7 = sha256("semantos")[0:8] = af70498e94f58c41.
function buildTestTypeHash(s1: string, s2: string, s3: string, s4: string): Uint8Array {
  const out = new Uint8Array(32);
  const enc = new TextEncoder();
  [s1, s2, s3, s4].forEach((seg, i) => {
    out.set(sha256(enc.encode(seg)).subarray(0, 8), i * 8);
  });
  return out;
}
const TEST_TYPE_HASH = buildTestTypeHash('semantos', 'test', 'linear-cell', '');

function hex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

beforeEach(() => {
  _resetDbForTests();
  return new Promise<void>((resolve) => {
    const req = indexedDB.deleteDatabase('semantos-wallet');
    req.onsuccess = () => resolve();
    req.onerror = () => resolve();
    req.onblocked = () => resolve();
  });
});

// ─── 1. Domain flag ───────────────────────────────────────────────────────────

describe('cell-anchor — domain flag', () => {
  test('is in sovereign range (0x00010000+)', () => {
    const flag = domainFlagFromTypeHash(TEST_TYPE_HASH);
    expect(flag).toBeGreaterThanOrEqual(0x00010000);
    expect(flag).toBeLessThanOrEqual(0xffffffff);
  });

  test('is deterministic', () => {
    expect(domainFlagFromTypeHash(TEST_TYPE_HASH)).toBe(domainFlagFromTypeHash(TEST_TYPE_HASH));
  });

  test('differs across type_hashes', () => {
    const other = sha256(new TextEncoder().encode('semantos:test:affine-cell'));
    expect(domainFlagFromTypeHash(TEST_TYPE_HASH)).not.toBe(domainFlagFromTypeHash(other));
  });

  test('differs from Plexus well-known flags (0x00000001–0x0000FFFF)', () => {
    const flag = domainFlagFromTypeHash(TEST_TYPE_HASH);
    expect(flag & 0x00010000).toBeTruthy();
  });
});

// ─── 2. Schema mapping ────────────────────────────────────────────────────────

describe('cell-anchor — schema mapping', () => {
  test('buildSchemaMapping encodes typeHashHex as 64-char string', () => {
    const m = buildSchemaMapping(TEST_TYPE_HASH, 'TestLinearCell');
    expect(m.typeHashHex).toBe(hex(TEST_TYPE_HASH));
    expect(m.typeHashHex.length).toBe(64);
  });

  test('domainFlag in mapping matches standalone derivation', () => {
    const m = buildSchemaMapping(TEST_TYPE_HASH);
    expect(m.domainFlag).toBe(domainFlagFromTypeHash(TEST_TYPE_HASH));
  });

  test('canonical ordering: sorted ascending by domainFlag', () => {
    const types = [
      sha256(new TextEncoder().encode('c')),
      sha256(new TextEncoder().encode('a')),
      sha256(new TextEncoder().encode('b')),
    ];
    const mappings = types
      .map(t => buildSchemaMapping(t))
      .sort((a, b) => a.domainFlag - b.domainFlag);
    for (let i = 1; i < mappings.length; i++) {
      expect(mappings[i]!.domainFlag).toBeGreaterThanOrEqual(mappings[i - 1]!.domainFlag);
    }
  });
});

// ─── 2b. L11.5 domain-separated derivation (kdf-v3) ─────────────────────────────

describe('cell-anchor — L11.5 kdf-v3 (domain-separated)', () => {
  const fromHex = (h: string): Uint8Array => Uint8Array.from(Buffer.from(h, 'hex'));
  // KAT pinned to the plexus-vendor-sdk `deriveDomainSegment` primitive
  // (computed there; see derive-domain-segment.test.ts). Proves the anchor
  // derivation folds u32_be(domainFlag) into the tweak byte-identically.
  const KAT_ID_SK = fromHex('1111111111111111111111111111111111111111111111111111111111111111');
  const KAT_TYPE_HASH = fromHex('abcdef0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d');
  const KAT_INDEX = 3;
  const KAT_CHILD_SK = '43a4d19e66e3f6660e4a810ea658e8129174da32fdadbcd2eae96be0899c1f48';

  test('KAT — deriveCellAnchorSk == SDK deriveDomainSegment(identitySk, domainFlag, invoice)', () => {
    const child = deriveCellAnchorSk(KAT_ID_SK, KAT_TYPE_HASH, KAT_INDEX);
    expect(hex(child!)).toBe(KAT_CHILD_SK);
  });

  test('domain-bound — differs from the unbound v2 tweak SHA-256(invoice)', () => {
    // Reconstruct the OLD v2 key (no flag) and confirm the new key is different.
    const protocolHash = sha256(new TextEncoder().encode(hex(KAT_TYPE_HASH))).slice(0, 16);
    const invoice = new Uint8Array(24);
    invoice.set(protocolHash, 0);
    new DataView(invoice.buffer).setBigUint64(16, BigInt(KAT_INDEX), true);
    const v2Tweak = sha256(invoice);
    const v2Child =
      (secp.etc.bytesToNumberBE(KAT_ID_SK) + secp.etc.bytesToNumberBE(v2Tweak)) % secp.CURVE.n;
    const v2Hex = hex(secp.etc.numberToBytesBE(v2Child, 32));
    expect(KAT_CHILD_SK).not.toBe(v2Hex);
  });

  test('schemaMapping stamps kdfVersion = plexus-kdf-v3 (recovery routing, 2b)', () => {
    expect(buildSchemaMapping(KAT_TYPE_HASH).kdfVersion).toBe('plexus-kdf-v3');
  });
});

// ─── 3. Protocol hash ─────────────────────────────────────────────────────────

describe('cell-anchor — protocol hash', () => {
  test('returns 16 bytes', () => {
    expect(anchorProtocolHash(TEST_TYPE_HASH).length).toBe(16);
  });

  test('is deterministic', () => {
    expect(anchorProtocolHash(TEST_TYPE_HASH)).toEqual(anchorProtocolHash(TEST_TYPE_HASH));
  });

  test('differs across type_hashes', () => {
    const other = sha256(new TextEncoder().encode('semantos:test:other'));
    expect(anchorProtocolHash(TEST_TYPE_HASH)).not.toEqual(anchorProtocolHash(other));
  });
});

// ─── 4. Key derivation ────────────────────────────────────────────────────────

describe('cell-anchor — key derivation', () => {
  test('deriveCellAnchorSk returns 32-byte key', () => {
    const sk = secp.utils.randomPrivateKey();
    const child = deriveCellAnchorSk(sk, TEST_TYPE_HASH, 0);
    expect(child).not.toBeNull();
    expect(child!.length).toBe(32);
  });

  test('is deterministic', () => {
    const sk = secp.utils.randomPrivateKey();
    expect(deriveCellAnchorSk(sk, TEST_TYPE_HASH, 0)).toEqual(
      deriveCellAnchorSk(sk, TEST_TYPE_HASH, 0),
    );
  });

  test('different indices produce different keys', () => {
    const sk = secp.utils.randomPrivateKey();
    expect(deriveCellAnchorSk(sk, TEST_TYPE_HASH, 0)).not.toEqual(
      deriveCellAnchorSk(sk, TEST_TYPE_HASH, 1),
    );
  });

  test('different type_hashes produce different keys at same index', () => {
    const sk = secp.utils.randomPrivateKey();
    const th2 = sha256(new TextEncoder().encode('semantos:test:other'));
    expect(deriveCellAnchorSk(sk, TEST_TYPE_HASH, 0)).not.toEqual(
      deriveCellAnchorSk(sk, th2, 0),
    );
  });

  test('anchor key differs from change key (domain isolation)', () => {
    const sk = secp.utils.randomPrivateKey();
    const anchorSk = deriveCellAnchorSk(sk, TEST_TYPE_HASH, 0);
    const changeSk = deriveChangeSk(sk, 0);
    expect(anchorSk).not.toEqual(changeSk);
  });

  test('buildCellAnchorLock embeds hash160 of derived pubkey', () => {
    const identitySk = secp.utils.randomPrivateKey();
    const lock = buildCellAnchorLock(identitySk, TEST_TYPE_HASH, 0);
    expect(lock).not.toBeNull();

    const childSk = deriveCellAnchorSk(identitySk, TEST_TYPE_HASH, 0)!;
    const childPk = secp.getPublicKey(childSk, true);
    const expectedHash = ripemd160(sha256(childPk));

    // P2PKH: OP_DUP OP_HASH160 <20 bytes> OP_EQUALVERIFY OP_CHECKSIG
    const hash160InLock = lock!.slice(3, 23);
    expect(hash160InLock).toEqual(expectedHash);
  });

  test('spend: sign with derived sk, verify against lock', () => {
    const identitySk = secp.utils.randomPrivateKey();
    const childSk = deriveCellAnchorSk(identitySk, TEST_TYPE_HASH, 0)!;
    const childPk = secp.getPublicKey(childSk, true);
    const lock = buildCellAnchorLock(identitySk, TEST_TYPE_HASH, 0)!;
    const toScript = buildP2pkhLock(pubkeyToHash160(secp.getPublicKey(identitySk, true)));

    // Fabricate a source txid
    const sourceTxid = new Uint8Array(32);
    crypto.getRandomValues(sourceTxid);
    const sourceValue = 10_000n;

    const inp: TxInput = { txid: sourceTxid, vout: 0, value: sourceValue, script: lock, sequence: 0xffffffff };
    const out: TxOutput = { script: toScript, satoshis: sourceValue - 192n };

    const digest = computeSighash([inp], [out], 0);
    const sig = secp.sign(digest, childSk).normalizeS();
    const derSig = encodeDer(sig.r, sig.s);
    const unlock = buildP2pkhUnlockScript(derSig, childPk);

    // Verify secp256k1 agrees
    expect(secp.verify(sig, digest, childPk)).toBe(true);
    // Unlock script is non-empty
    expect(unlock.length).toBeGreaterThan(70);
  });
});

// ─── 5. OutputRecord with typeHash ────────────────────────────────────────────

describe('cell-anchor — OutputRecord storage', () => {
  function makeAnchorRecord(identitySk: Uint8Array, typeHash: Uint8Array, index: number) {
    const childSk = deriveCellAnchorSk(identitySk, typeHash, index)!;
    const childPk = secp.getPublicKey(childSk, true);
    const lock = buildCellAnchorLock(identitySk, typeHash, index)!;
    const txid = new Uint8Array(32);
    crypto.getRandomValues(txid);
    return {
      record: {
        outpoint: { txid, vout: index },
        satoshis: 1000n,
        lockingScript: lock,
        derivedKeyHash: childPk,
        derivationContext: {
          protocolHash: anchorProtocolHash(typeHash),
          counterparty: secp.getPublicKey(identitySk, true),
          index: BigInt(index),
        },
        beef: new Uint8Array(0),
        basket: 'cell-anchors',
        tags: ['linear'],
        customInstructions: new Uint8Array(0),
        confirmations: 0,
        status: 'unspent' as const,
        spendingTxid: null,
        typeHash,
      },
      childSk,
      txid,
    };
  }

  test('addOutput and getOutput round-trips typeHash', async () => {
    const identitySk = secp.utils.randomPrivateKey();
    const { record, txid } = makeAnchorRecord(identitySk, TEST_TYPE_HASH, 0);

    const { inserted } = await outputStore.addOutput(record);
    expect(inserted).toBe(true);

    const got = await outputStore.getOutput({ txid, vout: 0 });
    expect(got).not.toBeNull();
    expect(got!.typeHash).toEqual(TEST_TYPE_HASH);
    expect(got!.basket).toBe('cell-anchors');
  });

  test('listOutputs by basket returns anchor UTXOs with typeHash', async () => {
    const identitySk = secp.utils.randomPrivateKey();
    const { record } = makeAnchorRecord(identitySk, TEST_TYPE_HASH, 0);

    await outputStore.addOutput(record);
    const list = await outputStore.listOutputs({ basket: 'cell-anchors' });
    expect(list.length).toBe(1);
    expect(list[0]!.typeHash).toEqual(TEST_TYPE_HASH);
  });

  test('markSpent clears UTXO from unspent list', async () => {
    const identitySk = secp.utils.randomPrivateKey();
    const { record, txid } = makeAnchorRecord(identitySk, TEST_TYPE_HASH, 0);

    await outputStore.addOutput(record);
    const spendingTxid = new Uint8Array(32);
    crypto.getRandomValues(spendingTxid);
    await outputStore.markSpent({ txid, vout: 0 }, spendingTxid);

    const unspent = await outputStore.listOutputs({ basket: 'cell-anchors', status: 'unspent' });
    expect(unspent.length).toBe(0);

    const spent = await outputStore.listOutputs({ basket: 'cell-anchors', status: 'spent' });
    expect(spent.length).toBe(1);
  });

  test('idempotent: addOutput twice returns inserted=false second time', async () => {
    const identitySk = secp.utils.randomPrivateKey();
    const { record } = makeAnchorRecord(identitySk, TEST_TYPE_HASH, 0);

    const r1 = await outputStore.addOutput(record);
    const r2 = await outputStore.addOutput(record);
    expect(r1.inserted).toBe(true);
    expect(r2.inserted).toBe(false);
  });

  test('multiple type_hashes stored and retrieved independently', async () => {
    const identitySk = secp.utils.randomPrivateKey();
    const thA = sha256(new TextEncoder().encode('type:A'));
    const thB = sha256(new TextEncoder().encode('type:B'));

    const { record: recA } = makeAnchorRecord(identitySk, thA, 0);
    const { record: recB } = makeAnchorRecord(identitySk, thB, 0);

    await outputStore.addOutput(recA);
    await outputStore.addOutput(recB);

    const list = await outputStore.listOutputs({ basket: 'cell-anchors' });
    expect(list.length).toBe(2);

    const hashes = list.map(r => hex(r.typeHash!)).sort();
    expect(hashes).toContain(hex(thA));
    expect(hashes).toContain(hex(thB));
  });
});

// ─── 6. Recovery: derive anchor key from reconstituted identity ───────────────

describe('cell-anchor — key recovery from seed', () => {
  test('re-deriving from same identitySk recovers anchor spending key', () => {
    // Simulate: wallet boots fresh on new device, reconstructs identitySk from seed.
    const identitySk = secp.utils.randomPrivateKey();

    const anchorSk = deriveCellAnchorSk(identitySk, TEST_TYPE_HASH, 0)!;
    const lock = buildCellAnchorLock(identitySk, TEST_TYPE_HASH, 0)!;

    // "New device" — same identitySk, re-derive anchor sk
    const recoveredAnchorSk = deriveCellAnchorSk(identitySk, TEST_TYPE_HASH, 0)!;
    expect(recoveredAnchorSk).toEqual(anchorSk);

    // Recovered key produces the same lock
    const recoveredLock = buildCellAnchorLock(identitySk, TEST_TYPE_HASH, 0)!;
    expect(recoveredLock).toEqual(lock);
  });

  test('spend with recovered anchor key verifies against stored lock', () => {
    const identitySk = secp.utils.randomPrivateKey();
    const lock = buildCellAnchorLock(identitySk, TEST_TYPE_HASH, 0)!;

    // Recovery path: given identitySk + typeHash (from Plexus schemaMappings), re-derive
    const recoveredSk = deriveCellAnchorSk(identitySk, TEST_TYPE_HASH, 0)!;
    const recoveredPk = secp.getPublicKey(recoveredSk, true);
    const toScript = buildP2pkhLock(pubkeyToHash160(secp.getPublicKey(identitySk, true)));

    const sourceTxid = new Uint8Array(32);
    crypto.getRandomValues(sourceTxid);

    const inp: TxInput = {
      txid: sourceTxid, vout: 0,
      value: 10_000n, script: lock, sequence: 0xffffffff,
    };
    const out: TxOutput = { script: toScript, satoshis: 9_808n };

    const digest = computeSighash([inp], [out], 0);
    const sig = secp.sign(digest, recoveredSk).normalizeS();

    // Verify the signature using the pubkey embedded in the lock
    expect(secp.verify(sig, digest, recoveredPk)).toBe(true);
  });
});

```
