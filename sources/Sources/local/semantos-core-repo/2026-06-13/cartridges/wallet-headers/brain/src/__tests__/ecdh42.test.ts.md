---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/__tests__/ecdh42.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.675120+00:00
---

# cartridges/wallet-headers/brain/src/__tests__/ecdh42.test.ts

```ts
import { describe, it, expect } from 'bun:test';
import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 } from '@noble/hashes/sha2';
import { deriveEdgeSk, deriveEdgeChildPk, buildRotatedLock, deriveChangeSk, CHANGE_DOMAIN_FLAG } from '../ecdh42';
import { pubkeyToHash160, buildP2pkhLock } from '../tx-builder';

// Wire HMAC backend (required before calling secp helpers in test scope)
secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(sha256, key, secp.etc.concatBytes(...msgs));

// ── Helpers ───────────────────────────────────────────────────────────────────

function hexToBytes(h: string): Uint8Array {
  const b = new Uint8Array(h.length / 2);
  for (let i = 0; i < b.length; i++) b[i] = parseInt(h.slice(i * 2, i * 2 + 2), 16);
  return b;
}
function bytesToHex(b: Uint8Array): string {
  return Array.from(b).map(x => x.toString(16).padStart(2, '0')).join('');
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

// Alice = sender; Bob = recipient.
// These are well-known secp256k1 test keys (privkeys 3 and 7).
const ALICE_SK = new Uint8Array(32); ALICE_SK[31] = 3;
const ALICE_PK = secp.getPublicKey(ALICE_SK, true);
const BOB_SK = new Uint8Array(32); BOB_SK[31] = 7;
const BOB_PK = secp.getPublicKey(BOB_SK, true);

// ── Round-trip: sender lock ↔ recipient spend ─────────────────────────────────

describe('BRC-42 round-trip (sender → recipient)', () => {
  it('buildRotatedLock address matches deriveEdgeSk spending key', () => {
    const INDEX = 1;

    // Alice (sender) builds the lock addressed to Bob's rotated key
    const lock = buildRotatedLock(BOB_PK, ALICE_SK, INDEX);
    expect(lock).not.toBeNull();

    // Bob (recipient) derives his spending key using Alice's public key
    const bobChildSk = deriveEdgeSk(BOB_SK, ALICE_PK, INDEX);
    expect(bobChildSk).not.toBeNull();

    // Derive the public key from Bob's child SK — it must match the lock's hash160
    const bobChildPk = secp.getPublicKey(bobChildSk!, true);

    // The lock must equal buildP2pkhLock(pubkeyToHash160(bobChildPk))
    const expectedLock = buildP2pkhLock(pubkeyToHash160(bobChildPk));
    expect(bytesToHex(lock!)).toBe(bytesToHex(expectedLock));
  });

  it('round-trip works across multiple indices', () => {
    for (const index of [0, 1, 5, 100]) {
      const lock = buildRotatedLock(BOB_PK, ALICE_SK, index);
      const bobChildSk = deriveEdgeSk(BOB_SK, ALICE_PK, index);
      expect(lock).not.toBeNull();
      expect(bobChildSk).not.toBeNull();

      const bobChildPk = secp.getPublicKey(bobChildSk!, true);
      const expectedLock = buildP2pkhLock(pubkeyToHash160(bobChildPk));
      expect(bytesToHex(lock!)).toBe(bytesToHex(expectedLock));
    }
  });

  it('different indices produce different locks (no address reuse)', () => {
    const lock1 = buildRotatedLock(BOB_PK, ALICE_SK, 1);
    const lock2 = buildRotatedLock(BOB_PK, ALICE_SK, 2);
    expect(lock1).not.toBeNull();
    expect(lock2).not.toBeNull();
    expect(bytesToHex(lock1!)).not.toBe(bytesToHex(lock2!));
  });

  it('different sender/recipient pairs produce different locks', () => {
    const CAROL_SK = new Uint8Array(32); CAROL_SK[31] = 11;
    const CAROL_PK = secp.getPublicKey(CAROL_SK, true);

    const lockAliceToBob = buildRotatedLock(BOB_PK, ALICE_SK, 1);
    const lockAliceToCarol = buildRotatedLock(CAROL_PK, ALICE_SK, 1);
    expect(bytesToHex(lockAliceToBob!)).not.toBe(bytesToHex(lockAliceToCarol!));
  });
});

// ── deriveEdgeChildPk — DAM grantee key (grantor side) ──────────────────────────
//
// The DAM access-grant carries the grantee's edge-derived PUBLIC key; the
// grantor derives it via deriveEdgeChildPk, the grantee derives the matching
// child SK via deriveEdgeSk and signs the access-challenge digest with it.

describe('deriveEdgeChildPk (DAM grantee key)', () => {
  it('grantor-derived grantee pubkey == getPublicKey(grantee child SK)', () => {
    for (const index of [0, 1, 5, 100]) {
      // Alice (grantor) derives Bob's grantee pubkey for the grant cell.
      const granteePk = deriveEdgeChildPk(BOB_PK, ALICE_SK, index);
      expect(granteePk).not.toBeNull();
      // Bob (grantee) derives his signing key; its pubkey must match.
      const bobChildSk = deriveEdgeSk(BOB_SK, ALICE_PK, index);
      expect(bobChildSk).not.toBeNull();
      const bobChildPk = secp.getPublicKey(bobChildSk!, true);
      expect(bytesToHex(granteePk!)).toBe(bytesToHex(bobChildPk));
    }
  });

  it('grantee child keypair signs + verifies a 32-byte challenge digest (host.checksig path)', () => {
    const INDEX = 7;
    const granteePk = deriveEdgeChildPk(BOB_PK, ALICE_SK, INDEX)!;
    const granteeSk = deriveEdgeSk(BOB_SK, ALICE_PK, INDEX)!;
    // A 32-byte access-challenge-shaped digest. The grantee signs it raw
    // (no re-hash) exactly as the brain's host.checksig verifies it.
    const digest = new Uint8Array(32).fill(0xa5);
    const sig = secp.sign(digest, granteeSk).normalizeS();
    expect(secp.verify(sig, digest, granteePk, { lowS: false })).toBe(true);
    // A different key must NOT verify the same signature.
    const carolPk = secp.getPublicKey((() => { const s = new Uint8Array(32); s[31] = 11; return s; })(), true);
    expect(secp.verify(sig, digest, carolPk, { lowS: false })).toBe(false);
  });

  it('different indices produce different grantee pubkeys (no key reuse)', () => {
    const pk1 = deriveEdgeChildPk(BOB_PK, ALICE_SK, 1)!;
    const pk2 = deriveEdgeChildPk(BOB_PK, ALICE_SK, 2)!;
    expect(bytesToHex(pk1)).not.toBe(bytesToHex(pk2));
  });
});

// ── buildRotatedLock ──────────────────────────────────────────────────────────

describe('buildRotatedLock', () => {
  it('returns a 25-byte P2PKH script', () => {
    const lock = buildRotatedLock(BOB_PK, ALICE_SK, 1);
    expect(lock).not.toBeNull();
    expect(lock!.length).toBe(25);
    expect(lock![0]).toBe(0x76); // OP_DUP
    expect(lock![1]).toBe(0xa9); // OP_HASH160
    expect(lock![2]).toBe(0x14); // push 20 bytes
    expect(lock![23]).toBe(0x88); // OP_EQUALVERIFY
    expect(lock![24]).toBe(0xac); // OP_CHECKSIG
  });

  it('is deterministic for same inputs', () => {
    const lock1 = buildRotatedLock(BOB_PK, ALICE_SK, 7);
    const lock2 = buildRotatedLock(BOB_PK, ALICE_SK, 7);
    expect(bytesToHex(lock1!)).toBe(bytesToHex(lock2!));
  });

  it('lock targets recipient key, NOT sender key', () => {
    const lock = buildRotatedLock(BOB_PK, ALICE_SK, 1);
    // Alice (sender) should NOT be able to spend this — the lock is for Bob
    // If Alice tried deriveEdgeSk(ALICE_SK, BOB_PK, 1), her child pk ≠ the lock's address
    const aliceChildSk = deriveEdgeSk(ALICE_SK, BOB_PK, 1);
    const aliceChildPk = secp.getPublicKey(aliceChildSk!, true);
    const aliceLock = buildP2pkhLock(pubkeyToHash160(aliceChildPk));
    // Should NOT match — the lock belongs to Bob, not Alice
    expect(bytesToHex(lock!)).not.toBe(bytesToHex(aliceLock));
  });
});

// ── deriveEdgeSk ─────────────────────────────────────────────────────────────

describe('deriveEdgeSk (recipient perspective)', () => {
  it('returns a 32-byte valid secp256k1 scalar', () => {
    const sk = deriveEdgeSk(BOB_SK, ALICE_PK, 1);
    expect(sk).not.toBeNull();
    expect(sk!.length).toBe(32);
    expect(() => secp.getPublicKey(sk!, true)).not.toThrow();
    const pk = secp.getPublicKey(sk!, true);
    expect(pk[0] === 0x02 || pk[0] === 0x03).toBe(true);
  });

  it('different indices give different keys (BKDS monotonic rotation)', () => {
    const sk1 = deriveEdgeSk(BOB_SK, ALICE_PK, 1);
    const sk2 = deriveEdgeSk(BOB_SK, ALICE_PK, 2);
    expect(bytesToHex(sk1!)).not.toBe(bytesToHex(sk2!));
  });

  it('is deterministic', () => {
    const sk1 = deriveEdgeSk(BOB_SK, ALICE_PK, 5);
    const sk2 = deriveEdgeSk(BOB_SK, ALICE_PK, 5);
    expect(bytesToHex(sk1!)).toBe(bytesToHex(sk2!));
  });
});

// ── BRC-42 spec public key test vectors ──────────────────────────────────────
// Source: https://bsv.brc.dev/key-derivation/0042
// These use raw UTF-8 invoice strings (not our protocolHash||index format) and
// raw ECDH point as HMAC key.  They verify the core ECDH+HMAC mechanism is
// correct — if these pass, buildRotatedLock is deriving keys the right way.

describe('BRC-42 spec test vectors (core ECDH mechanism)', () => {
  const vectors = [
    {
      senderPrivateKey: '583755110a8c059de5cd81b8a04e1be884c46083ade3f779c1e022f6f89da94c',
      recipientPublicKey: '02c0c1e1a1f7d247827d1bcf399f0ef2deef7695c322fd91a01a91378f101b6ffc',
      invoiceNumber: 'IBioA4D/OaE=',
      expectedPublicKey: '03c1bf5baadee39721ae8c9882b3cf324f0bf3b9eb3fc1b8af8089ca7a7c2e669f',
    },
    {
      senderPrivateKey: '2c378b43d887d72200639890c11d79e8f22728d032a5733ba3d7be623d1bb118',
      recipientPublicKey: '039a9da906ecb8ced5c87971e9c2e7c921e66ad450fd4fc0a7d569fdb5bede8e0f',
      invoiceNumber: 'PWYuo9PDKvI=',
      expectedPublicKey: '0398cdf4b56a3b2e106224ff3be5253afd5b72de735d647831be51c713c9077848',
    },
    {
      senderPrivateKey: 'd5a5f70b373ce164998dff7ecd93260d7e80356d3d10abf928fb267f0a6c7be6',
      recipientPublicKey: '02745623f4e5de046b6ab59ce837efa1a959a8f28286ce9154a4781ec033b85029',
      invoiceNumber: 'X9pnS+bByrM=',
      expectedPublicKey: '0273eec9380c1a11c5a905e86c2d036e70cbefd8991d9a0cfca671f5e0bbea4a3c',
    },
    {
      senderPrivateKey: '46cd68165fd5d12d2d6519b02feb3f4d9c083109de1bfaa2b5c4836ba717523c',
      recipientPublicKey: '031e18bb0bbd3162b886007c55214c3c952bb2ae6c33dd06f57d891a60976003b1',
      invoiceNumber: '+ktmYRHv3uQ=',
      expectedPublicKey: '034c5c6bf2e52e8de8b2eb75883090ed7d1db234270907f1b0d1c2de1ddee5005d',
    },
    {
      senderPrivateKey: '7c98b8abd7967485cfb7437f9c56dd1e48ceb21a4085b8cdeb2a647f62012db4',
      recipientPublicKey: '03c8885f1e1ab4facd0f3272bb7a48b003d2e608e1619fb38b8be69336ab828f37',
      invoiceNumber: 'PPfDTTcl1ao=',
      expectedPublicKey: '03304b41cfa726096ffd9d8907fe0835f888869eda9653bca34eb7bcab870d3779',
    },
  ];

  const enc = new TextEncoder();

  it.each(vectors)(
    'sender=$senderPrivateKey.slice(0,8)… derives correct child public key',
    ({ senderPrivateKey, recipientPublicKey, invoiceNumber, expectedPublicKey }) => {
      const senderSk = hexToBytes(senderPrivateKey);
      const recipientPk = hexToBytes(recipientPublicKey);
      const invoiceBytes = enc.encode(invoiceNumber);

      // ECDH: senderSk × recipientPk — raw compressed point as HMAC key (per spec)
      const shared = secp.getSharedSecret(senderSk, recipientPk, true);
      const tweak = hmac(sha256, shared, invoiceBytes);

      // child_pk = recipientPk + tweak*G
      const tweakN = secp.etc.bytesToNumberBE(tweak);
      const recipientPoint = secp.ProjectivePoint.fromHex(recipientPk);
      const tweakPoint = secp.ProjectivePoint.BASE.multiply(tweakN);
      const childPk = bytesToHex(recipientPoint.add(tweakPoint).toRawBytes(true));

      expect(childPk).toBe(expectedPublicKey);
    },
  );
});

// ── CHANGE domain — L11.5 kdf-v3 (domain-separated) ─────────────────────────────

describe('deriveChangeSk — L11.5 kdf-v3 (CHANGE flag folded into the tweak)', () => {
  const enc = new TextEncoder();
  const CHANGE_PROTOCOL_HASH = sha256(enc.encode('BRC-42-wallet-change')).slice(0, 16);

  /** Independent reconstruction of the documented v3 formula:
   *  child = identitySk + SHA-256( u32_be(CHANGE_DOMAIN_FLAG) || protocolHash || index_le8 ) mod n.
   *  This is the same byte layout the SDK `deriveDomainSegment` / cell-anchor.ts use. */
  function expectedChangeSk(identitySk: Uint8Array, index: number): string {
    const invoice = new Uint8Array(24);
    invoice.set(CHANGE_PROTOCOL_HASH, 0);
    new DataView(invoice.buffer).setBigUint64(16, BigInt(index), true);
    const preimage = new Uint8Array(4 + invoice.length);
    new DataView(preimage.buffer).setUint32(0, CHANGE_DOMAIN_FLAG, false); // big-endian tag
    preimage.set(invoice, 4);
    const tweak = sha256(preimage);
    const child =
      (secp.etc.bytesToNumberBE(identitySk) + secp.etc.bytesToNumberBE(tweak)) % secp.CURVE.n;
    return bytesToHex(secp.etc.numberToBytesBE(child, 32));
  }

  it('CHANGE_DOMAIN_FLAG is 0x0b (PLEXUS_RESERVED band)', () => {
    expect(CHANGE_DOMAIN_FLAG).toBe(0x0b);
  });

  it.each([0, 1, 7, 42])('KAT — deriveChangeSk matches the v3 domain-separated formula at index %i', (index) => {
    const child = deriveChangeSk(BOB_SK, index);
    expect(child).not.toBeNull();
    expect(bytesToHex(child!)).toBe(expectedChangeSk(BOB_SK, index));
  });

  it('domain-bound — differs from the unbound v2 tweak SHA-256(invoice)', () => {
    const index = 5;
    const invoice = new Uint8Array(24);
    invoice.set(CHANGE_PROTOCOL_HASH, 0);
    new DataView(invoice.buffer).setBigUint64(16, BigInt(index), true);
    const v2Tweak = sha256(invoice); // old kdf-v2: no flag prepended
    const v2Child =
      (secp.etc.bytesToNumberBE(BOB_SK) + secp.etc.bytesToNumberBE(v2Tweak)) % secp.CURVE.n;
    const v2Hex = bytesToHex(secp.etc.numberToBytesBE(v2Child, 32));
    expect(bytesToHex(deriveChangeSk(BOB_SK, index)!)).not.toBe(v2Hex);
  });
});


```
