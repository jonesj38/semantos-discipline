---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tests/generate-bca-vectors.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.958688+00:00
---

# core/cell-engine/tests/generate-bca-vectors.ts

```ts
/**
 * BCA Test Vector Generator — Phase 2
 *
 * Generates BCA (Bitcoin-Certified Address) test vectors INDEPENDENTLY
 * of the Zig implementation. Uses @bsv/sdk for SHA256 and key generation.
 *
 * BCA Algorithm (simplified Semantos version):
 *   data = modifier(16B) || subnetPrefix(8B) || collisionCount(1B) || pubkey(33B)
 *   Hash1 = SHA256(data)
 *   interfaceIdentifier = Hash1[0..8]
 *   Clear u-bit (bit 6 from MSB) and g-bit (bit 7 from MSB) of byte 0
 *   Encode sec in bits 0-2 (3 MSBs) of byte 0
 *   BCA = subnetPrefix || interfaceIdentifier
 *
 * Usage: bun run tests/generate-bca-vectors.ts
 */

import { Hash, PrivateKey } from '@bsv/sdk';
import { writeFileSync } from 'fs';
import { join } from 'path';

const VECTORS_DIR = join(import.meta.dir, 'vectors');

// ── BCA Algorithm (TypeScript reference implementation) ──

interface BCAInput {
  pubkey: Uint8Array;       // 33 bytes, compressed
  subnetPrefix: Uint8Array; // 8 bytes
  modifier: Uint8Array;     // 16 bytes
  sec: number;              // 0, 1, or 2
}

interface BCAOutput {
  address: Uint8Array;      // 16 bytes
  collisionCount: number;
}

function deriveBCA(input: BCAInput): BCAOutput {
  // For the simplified algorithm, collision count starts at 0
  // and we always return the first result (no collision oracle)
  const cc = 0;

  // Concatenate: modifier(16) || subnetPrefix(8) || collisionCount(1) || pubkey(33)
  const data = new Uint8Array(58);
  data.set(input.modifier, 0);
  data.set(input.subnetPrefix, 16);
  data[24] = cc;
  data.set(input.pubkey, 25);

  // SHA256
  const hash = Hash.sha256(data); // number[]

  // interfaceIdentifier = first 8 bytes
  const iid = new Uint8Array(hash.slice(0, 8));

  // RFC 4291 bit manipulation on byte 0:
  // Bits numbered from MSB: bit 0 = MSB (0x80), bit 7 = LSB (0x01)
  // u-bit = bit 6 from MSB = 0x02 position → clear it
  // g-bit = bit 7 from MSB = 0x01 position → clear it
  iid[0] &= ~0x03; // clear u-bit and g-bit (bits 6,7 from MSB = bits 1,0 from LSB)

  // Encode sec in 3 MSBs (bits 0-2 from MSB = bits 7,6,5 from LSB)
  iid[0] = (iid[0] & 0x1F) | ((input.sec & 0x07) << 5);

  // BCA = subnetPrefix || interfaceIdentifier
  const address = new Uint8Array(16);
  address.set(input.subnetPrefix, 0);
  address.set(iid, 8);

  return { address, collisionCount: cc };
}

function verifyBCA(address: Uint8Array, input: BCAInput): boolean {
  const targetIid = address.slice(8, 16);

  for (let cc = 0; cc <= 2; cc++) {
    const data = new Uint8Array(58);
    data.set(input.modifier, 0);
    data.set(input.subnetPrefix, 16);
    data[24] = cc;
    data.set(input.pubkey, 25);

    const hash = Hash.sha256(data);
    const candidate = new Uint8Array(hash.slice(0, 8));

    // Apply same bit manipulation
    candidate[0] &= ~0x03;
    const sec = (targetIid[0] >> 5) & 0x07;
    candidate[0] = (candidate[0] & 0x1F) | ((sec & 0x07) << 5);

    if (candidate.every((v, i) => v === targetIid[i])) return true;
  }
  return false;
}

// ── Helper functions ──

function toHex(arr: Uint8Array): string {
  return Array.from(arr).map(b => b.toString(16).padStart(2, '0')).join('');
}

function fromHex(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
  }
  return bytes;
}

function getCompressedPubkey(privKeyHex: string): Uint8Array {
  const pk = PrivateKey.fromString(privKeyHex, 16);
  const pubKey = pk.toPublicKey();
  const encoded = pubKey.encode(true) as number[];
  return new Uint8Array(encoded);
}

// ── Generate vectors ──

// Deterministic test keys (well-known hex private keys)
const TEST_KEYS = [
  '0000000000000000000000000000000000000000000000000000000000000001',
  '0000000000000000000000000000000000000000000000000000000000000002',
  '0000000000000000000000000000000000000000000000000000000000000003',
  'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140', // n-1
];

const DEFAULT_PREFIX = fromHex('20010db800000001'); // 2001:db8:0:1::/64
const DEFAULT_MODIFIER = fromHex('00112233445566778899aabbccddeeff');
const ALT_MODIFIER = fromHex('ffeeddccbbaa99887766554433221100');

// ── 1. bca_basic.json — Known pubkey → known IPv6 (sec=0) ──

interface VectorEntry {
  pubkey: string;
  subnetPrefix: string;
  modifier: string;
  sec: number;
  expectedAddress: string;
  expectedCollisionCount: number;
  description: string;
}

const basicVectors: VectorEntry[] = [];

for (let i = 0; i < TEST_KEYS.length; i++) {
  const pubkey = getCompressedPubkey(TEST_KEYS[i]);
  const input: BCAInput = {
    pubkey,
    subnetPrefix: DEFAULT_PREFIX,
    modifier: DEFAULT_MODIFIER,
    sec: 0,
  };
  const output = deriveBCA(input);

  // Verify round-trip
  if (!verifyBCA(output.address, input)) {
    throw new Error(`Round-trip verification failed for key ${i}`);
  }

  basicVectors.push({
    pubkey: toHex(pubkey),
    subnetPrefix: toHex(DEFAULT_PREFIX),
    modifier: toHex(DEFAULT_MODIFIER),
    sec: 0,
    expectedAddress: toHex(output.address),
    expectedCollisionCount: output.collisionCount,
    description: `BCA for test key ${i + 1} (sec=0)`,
  });
}

// Also test with alt modifier and different prefix
const altPrefix = fromHex('fe80000000000000'); // fe80::/64 link-local
const pubkey0 = getCompressedPubkey(TEST_KEYS[0]);
const altInput: BCAInput = {
  pubkey: pubkey0,
  subnetPrefix: altPrefix,
  modifier: ALT_MODIFIER,
  sec: 0,
};
const altOutput = deriveBCA(altInput);
basicVectors.push({
  pubkey: toHex(pubkey0),
  subnetPrefix: toHex(altPrefix),
  modifier: toHex(ALT_MODIFIER),
  sec: 0,
  expectedAddress: toHex(altOutput.address),
  expectedCollisionCount: altOutput.collisionCount,
  description: 'BCA for test key 1 with alt modifier and link-local prefix (sec=0)',
});

writeFileSync(join(VECTORS_DIR, 'bca_basic.json'), JSON.stringify(basicVectors, null, 2) + '\n');

// ── 2. bca_all_sec_params.json — sec=0, sec=1, sec=2 with same pubkey ──

const secVectors: VectorEntry[] = [];

for (let sec = 0; sec <= 2; sec++) {
  const pubkey = getCompressedPubkey(TEST_KEYS[0]);
  const input: BCAInput = {
    pubkey,
    subnetPrefix: DEFAULT_PREFIX,
    modifier: DEFAULT_MODIFIER,
    sec,
  };
  const output = deriveBCA(input);

  if (!verifyBCA(output.address, input)) {
    throw new Error(`Round-trip verification failed for sec=${sec}`);
  }

  secVectors.push({
    pubkey: toHex(pubkey),
    subnetPrefix: toHex(DEFAULT_PREFIX),
    modifier: toHex(DEFAULT_MODIFIER),
    sec,
    expectedAddress: toHex(output.address),
    expectedCollisionCount: output.collisionCount,
    description: `BCA for test key 1 with sec=${sec}`,
  });
}

writeFileSync(join(VECTORS_DIR, 'bca_all_sec_params.json'), JSON.stringify(secVectors, null, 2) + '\n');

// ── 3. bca_modifier_diversity.json — Different modifiers produce different addresses ──
// NOTE (E-P2.2): Renamed from bca_collision.json. These vectors don't test collision
// retry (all have cc=0). They verify that different modifiers produce different addresses,
// which exercises verifyBCA's loop but not actual collision avoidance.

const collisionVectors: VectorEntry[] = [];

// Use different modifiers to show different addresses from same key
const modifiers = [
  fromHex('00000000000000000000000000000000'),
  fromHex('11111111111111111111111111111111'),
  fromHex('22222222222222222222222222222222'),
];

for (let i = 0; i < modifiers.length; i++) {
  const pubkey = getCompressedPubkey(TEST_KEYS[0]);
  const input: BCAInput = {
    pubkey,
    subnetPrefix: DEFAULT_PREFIX,
    modifier: modifiers[i],
    sec: 2, // max retries allowed
  };
  const output = deriveBCA(input);

  collisionVectors.push({
    pubkey: toHex(pubkey),
    subnetPrefix: toHex(DEFAULT_PREFIX),
    modifier: toHex(modifiers[i]),
    sec: 2,
    expectedAddress: toHex(output.address),
    expectedCollisionCount: output.collisionCount,
    description: `BCA with modifier ${i} and sec=2 — different modifier produces different address`,
  });
}

writeFileSync(join(VECTORS_DIR, 'bca_modifier_diversity.json'), JSON.stringify(collisionVectors, null, 2) + '\n');

// ── 4. bca_verify_false.json — Wrong pubkey → verification fails ──

interface VerifyFalseEntry {
  address: string;
  pubkey: string;
  subnetPrefix: string;
  modifier: string;
  expectedResult: boolean;
  description: string;
}

const verifyFalseVectors: VerifyFalseEntry[] = [];

// Derive a valid BCA from key 1
const validPubkey = getCompressedPubkey(TEST_KEYS[0]);
const validInput: BCAInput = {
  pubkey: validPubkey,
  subnetPrefix: DEFAULT_PREFIX,
  modifier: DEFAULT_MODIFIER,
  sec: 0,
};
const validOutput = deriveBCA(validInput);

// Verify with wrong pubkey
const wrongPubkey = getCompressedPubkey(TEST_KEYS[1]);
verifyFalseVectors.push({
  address: toHex(validOutput.address),
  pubkey: toHex(wrongPubkey),
  subnetPrefix: toHex(DEFAULT_PREFIX),
  modifier: toHex(DEFAULT_MODIFIER),
  expectedResult: false,
  description: 'Wrong pubkey — verification should fail',
});

// Verify with wrong modifier
verifyFalseVectors.push({
  address: toHex(validOutput.address),
  pubkey: toHex(validPubkey),
  subnetPrefix: toHex(DEFAULT_PREFIX),
  modifier: toHex(ALT_MODIFIER),
  expectedResult: false,
  description: 'Wrong modifier — verification should fail',
});

// Verify with wrong subnet prefix
verifyFalseVectors.push({
  address: toHex(validOutput.address),
  pubkey: toHex(validPubkey),
  subnetPrefix: toHex(altPrefix),
  modifier: toHex(DEFAULT_MODIFIER),
  expectedResult: false,
  description: 'Wrong subnet prefix — verification should fail',
});

// Verify with correct params (positive control)
verifyFalseVectors.push({
  address: toHex(validOutput.address),
  pubkey: toHex(validPubkey),
  subnetPrefix: toHex(DEFAULT_PREFIX),
  modifier: toHex(DEFAULT_MODIFIER),
  expectedResult: true,
  description: 'Correct params — verification should pass (positive control)',
});

// Verify with corrupted address
const corruptedAddr = new Uint8Array(validOutput.address);
corruptedAddr[15] ^= 0xFF; // flip last byte
verifyFalseVectors.push({
  address: toHex(corruptedAddr),
  pubkey: toHex(validPubkey),
  subnetPrefix: toHex(DEFAULT_PREFIX),
  modifier: toHex(DEFAULT_MODIFIER),
  expectedResult: false,
  description: 'Corrupted address — verification should fail',
});

writeFileSync(join(VECTORS_DIR, 'bca_verify_false.json'), JSON.stringify(verifyFalseVectors, null, 2) + '\n');

// ── Print summary ──

console.log('BCA test vectors generated:');
console.log(`  bca_basic.json: ${basicVectors.length} vectors`);
console.log(`  bca_all_sec_params.json: ${secVectors.length} vectors`);
console.log(`  bca_modifier_diversity.json: ${collisionVectors.length} vectors`);
console.log(`  bca_verify_false.json: ${verifyFalseVectors.length} vectors`);

// Print first basic vector for debugging
console.log('\nFirst basic vector:');
console.log(`  pubkey:   ${basicVectors[0].pubkey}`);
console.log(`  prefix:   ${basicVectors[0].subnetPrefix}`);
console.log(`  modifier: ${basicVectors[0].modifier}`);
console.log(`  sec:      ${basicVectors[0].sec}`);
console.log(`  address:  ${basicVectors[0].expectedAddress}`);
console.log(`  cc:       ${basicVectors[0].expectedCollisionCount}`);

```
