---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/vault.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.670064+00:00
---

# cartridges/wallet-headers/brain/test/vault.spec.ts

```ts
// Phase W11 — Tier-3 vault management spec (browser bundle).
//
// Acceptance criteria (from W11 brief):
//   • 2-of-3 vault: create, sign, verify via host.host_checkmultisig.
//   • Below-threshold rejected.
//   • nSequence encoding correct per BIP-68 (relative-lock-by-time, bit 22).
//   • Vault round-trip via host.persistCell / host.loadCell after
//     host.unlockTier(3, ...).
//
// References:
//   • design §4.3, §4.4, §6.2.1
//   • docs/design/VAULT-MULTISIG-NSEQUENCE.md
//   • core/cell-engine/src/opcodes/plexus.zig (VAULT_OFFSET_*)

import { beforeEach, describe, expect, test } from 'bun:test';
import 'fake-indexeddb/auto';

import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

import {
  createVault,
  signVaultSpend,
  nextNSequence,
  decodeCooldownSeconds,
  readThreshold,
  readNSequence,
  readMemberPubkey,
  readMemberCount,
  readLinearity,
  readDomainFlag,
  readParentTxid,
  CELL_SIZE,
  HEADER_SIZE,
  VAULT_DOMAIN_FLAG,
  VAULT_NSEQUENCE_TYPE_FLAG,
  VAULT_NSEQUENCE_DISABLE_FLAG,
  VAULT_NSEQUENCE_VALUE_MASK,
  VAULT_NSEQUENCE_TIME_UNIT_SECONDS,
  VAULT_MAX_MEMBERS,
  VAULT_OFFSET_THRESHOLD,
  VAULT_OFFSET_NSEQUENCE,
  _internal_for_tests,
} from '../src/vault';

import {
  createHost,
  beginRequest,
  endRequest,
  primeUnlockTier,
  setSessionKek,
  clearAllKeks,
  deriveKek,
  encryptCellForBridge,
  flushRequest,
} from '../src/host';
import { slotPut, _resetDbForTests } from '../src/storage';

// secp v2 needs sync HMAC for sync sign().
secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

// ──────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────

let nextPtr = 1024;

function freshMemory(): { host: ReturnType<typeof createHost>; memory: WebAssembly.Memory } {
  const memory = new WebAssembly.Memory({ initial: 4 });
  return { host: createHost(memory), memory };
}

function alloc(memory: WebAssembly.Memory, len: number): number {
  const ptr = nextPtr;
  nextPtr += (len + 15) & ~15;
  if (nextPtr > memory.buffer.byteLength) memory.grow(1);
  return ptr;
}

function writeMem(memory: WebAssembly.Memory, ptr: number, data: Uint8Array): void {
  new Uint8Array(memory.buffer, ptr, data.length).set(data);
}

function readMem(memory: WebAssembly.Memory, ptr: number, len: number): Uint8Array {
  return new Uint8Array(memory.buffer, ptr, len).slice();
}

/** Deterministic-but-distinct test scalars. We do NOT use random keys so a
 *  failure is reproducible. The byte at index 0 is forced high so the scalar
 *  is never near-zero. */
function makeSk(seed: number): Uint8Array {
  const sk = new Uint8Array(32);
  for (let i = 0; i < 32; i++) sk[i] = ((seed * 31 + i * 7) & 0xff) || 1;
  sk[0] = 0x40 | (seed & 0x3f);
  return sk;
}

function makeMember(seed: number): { sk: Uint8Array; pk: Uint8Array } {
  const sk = makeSk(seed);
  return { sk, pk: secp.getPublicKey(sk, true) };
}

function makeProtocolHash(): Uint8Array {
  const ph = new Uint8Array(16);
  for (let i = 0; i < 16; i++) ph[i] = 0xa0 + i;
  return ph;
}

function makeCounterparty(): Uint8Array {
  const cp = new Uint8Array(33);
  cp[0] = 0x02;
  for (let i = 1; i < 33; i++) cp[i] = 0x55;
  return cp;
}

function zeros(n: number): Uint8Array {
  return new Uint8Array(n);
}

beforeEach(() => {
  nextPtr = 1024;
  clearAllKeks();
  _resetDbForTests();
  return new Promise<void>((resolve) => {
    const req = indexedDB.deleteDatabase('semantos-wallet');
    req.onsuccess = () => resolve();
    req.onerror = () => resolve();
    req.onblocked = () => resolve();
  });
});

// ──────────────────────────────────────────────────────────────────────
// createVault — structural correctness
// ──────────────────────────────────────────────────────────────────────

describe('createVault', () => {
  test('builds a 1024-byte LINEAR Tier-3 cell with v0.2 multisig fields', () => {
    const a = makeMember(1);
    const b = makeMember(2);
    const c = makeMember(3);
    const v = createVault({
      memberPubkeys: [a.pk, b.pk, c.pk],
      threshold: 2,
      leafPrivKey: makeSk(99),
      protocolHash: makeProtocolHash(),
      counterparty: makeCounterparty(),
      nsequence: nextNSequence(null, 60),
      parentTxid: zeros(32),
    });

    expect(v.bytes.length).toBe(CELL_SIZE);
    expect(readLinearity(v)).toBe(_internal_for_tests.LINEARITY_LINEAR);
    expect(readDomainFlag(v)).toBe(VAULT_DOMAIN_FLAG);
    expect(readThreshold(v)).toBe(2);
    expect(readMemberCount(v)).toBe(3);

    // Each member pubkey survives the layout intact.
    expect(readMemberPubkey(v, 0)).toEqual(a.pk);
    expect(readMemberPubkey(v, 1)).toEqual(b.pk);
    expect(readMemberPubkey(v, 2)).toEqual(c.pk);
    // Empty slots stay zero.
    expect(readMemberPubkey(v, 3).every((b) => b === 0)).toBe(true);
    expect(readMemberPubkey(v, 4).every((b) => b === 0)).toBe(true);
  });

  test('rejects threshold > member count', () => {
    const a = makeMember(11);
    const b = makeMember(12);
    expect(() =>
      createVault({
        memberPubkeys: [a.pk, b.pk],
        threshold: 3,
        leafPrivKey: makeSk(13),
        protocolHash: makeProtocolHash(),
        counterparty: makeCounterparty(),
        nsequence: 0,
        parentTxid: zeros(32),
      }),
    ).toThrow();
  });

  test('rejects too many members', () => {
    const pks: Uint8Array[] = [];
    for (let i = 0; i < VAULT_MAX_MEMBERS + 1; i++) pks.push(makeMember(20 + i).pk);
    expect(() =>
      createVault({
        memberPubkeys: pks,
        threshold: 2,
        leafPrivKey: makeSk(50),
        protocolHash: makeProtocolHash(),
        counterparty: makeCounterparty(),
        nsequence: 0,
        parentTxid: zeros(32),
      }),
    ).toThrow();
  });

  test('rejects malformed compressed pubkey', () => {
    const bad = new Uint8Array(33);
    bad[0] = 0x05; // not 0x02 / 0x03
    expect(() =>
      createVault({
        memberPubkeys: [bad],
        threshold: 1,
        leafPrivKey: makeSk(60),
        protocolHash: makeProtocolHash(),
        counterparty: makeCounterparty(),
        nsequence: 0,
        parentTxid: zeros(32),
      }),
    ).toThrow();
  });
});

// ──────────────────────────────────────────────────────────────────────
// signVaultSpend — m-of-n satisfaction
// ──────────────────────────────────────────────────────────────────────

describe('signVaultSpend', () => {
  test('2-of-3 vault: sigs verify via host.host_checkmultisig', () => {
    const a = makeMember(101);
    const b = makeMember(102);
    const c = makeMember(103);
    const v = createVault({
      memberPubkeys: [a.pk, b.pk, c.pk],
      threshold: 2,
      leafPrivKey: makeSk(199),
      protocolHash: makeProtocolHash(),
      counterparty: makeCounterparty(),
      nsequence: nextNSequence(null, 60),
      parentTxid: zeros(32),
    });

    const digest = new Uint8Array(32);
    for (let i = 0; i < 32; i++) digest[i] = (i * 13 + 7) & 0xff;

    // Sign with members 0 and 1 (a + b).
    const sig = signVaultSpend(v, [0, 1], [a.sk, b.sk], digest);
    expect(sig.sigCount).toBe(2);

    // Verify via the actual host_checkmultisig — the same code path the
    // engine takes at runtime.
    const { host, memory } = freshMemory();
    const pksPtr = alloc(memory, 3 * 33);
    const sigsPtr = alloc(memory, sig.packed.length);
    const msgPtr = alloc(memory, 32);
    writeMem(memory, pksPtr, concatPks([a.pk, b.pk, c.pk]));
    writeMem(memory, sigsPtr, sig.packed);
    writeMem(memory, msgPtr, digest);

    const ok = host.host_checkmultisig(pksPtr, 3, sigsPtr, sig.sigCount, msgPtr, 32, readThreshold(v));
    expect(ok).toBe(1);
  });

  test('below-threshold (1 sig, 2-of-3) is rejected', () => {
    const a = makeMember(201);
    const b = makeMember(202);
    const c = makeMember(203);
    const v = createVault({
      memberPubkeys: [a.pk, b.pk, c.pk],
      threshold: 2,
      leafPrivKey: makeSk(299),
      protocolHash: makeProtocolHash(),
      counterparty: makeCounterparty(),
      nsequence: 0,
      parentTxid: zeros(32),
    });

    // signVaultSpend itself enforces the threshold.
    expect(() => signVaultSpend(v, [0], [a.sk], new Uint8Array(32))).toThrow();
  });

  test('mismatched (sk, vault.member_pubkeys[idx]) pair rejected before signing', () => {
    const a = makeMember(301);
    const b = makeMember(302);
    const v = createVault({
      memberPubkeys: [a.pk, b.pk],
      threshold: 2,
      leafPrivKey: makeSk(399),
      protocolHash: makeProtocolHash(),
      counterparty: makeCounterparty(),
      nsequence: 0,
      parentTxid: zeros(32),
    });

    // Pass `b.sk` for index 0 (which holds a.pk) — must throw.
    const digest = new Uint8Array(32);
    expect(() => signVaultSpend(v, [0, 1], [b.sk, b.sk], digest)).toThrow();
  });

  test('3-of-3 satisfies even when threshold is 2', () => {
    const a = makeMember(401);
    const b = makeMember(402);
    const c = makeMember(403);
    const v = createVault({
      memberPubkeys: [a.pk, b.pk, c.pk],
      threshold: 2,
      leafPrivKey: makeSk(499),
      protocolHash: makeProtocolHash(),
      counterparty: makeCounterparty(),
      nsequence: 0,
      parentTxid: zeros(32),
    });

    const digest = new Uint8Array(32);
    for (let i = 0; i < 32; i++) digest[i] = i;

    const sig = signVaultSpend(v, [0, 1, 2], [a.sk, b.sk, c.sk], digest);
    expect(sig.sigCount).toBe(3);

    const { host, memory } = freshMemory();
    const pksPtr = alloc(memory, 3 * 33);
    const sigsPtr = alloc(memory, sig.packed.length);
    const msgPtr = alloc(memory, 32);
    writeMem(memory, pksPtr, concatPks([a.pk, b.pk, c.pk]));
    writeMem(memory, sigsPtr, sig.packed);
    writeMem(memory, msgPtr, digest);

    expect(host.host_checkmultisig(pksPtr, 3, sigsPtr, 3, msgPtr, 32, 2)).toBe(1);
  });

  test('forged sig from non-member is rejected by host_checkmultisig', () => {
    const a = makeMember(501);
    const b = makeMember(502);
    const c = makeMember(503);
    const v = createVault({
      memberPubkeys: [a.pk, b.pk, c.pk],
      threshold: 2,
      leafPrivKey: makeSk(599),
      protocolHash: makeProtocolHash(),
      counterparty: makeCounterparty(),
      nsequence: 0,
      parentTxid: zeros(32),
    });

    const digest = new Uint8Array(32);
    digest[0] = 0xab;

    // Build a sig blob *manually* mixing a real member sig (a) and one from
    // a non-member, bypassing signVaultSpend's verification.
    const attackerSk = makeSk(999);
    const sigA = secp.sign(digest, a.sk).normalizeS();
    const sigX = secp.sign(digest, attackerSk).normalizeS();
    const derA = encodeDerExt(sigA.r, sigA.s);
    const derX = encodeDerExt(sigX.r, sigX.s);

    // [len][derA||0x41][len][derX||0x41]
    const buf = new Uint8Array((1 + derA.length + 1) + (1 + derX.length + 1));
    let off = 0;
    buf[off++] = derA.length + 1;
    buf.set(derA, off);
    off += derA.length;
    buf[off++] = 0x41;
    buf[off++] = derX.length + 1;
    buf.set(derX, off);
    off += derX.length;
    buf[off++] = 0x41;

    const { host, memory } = freshMemory();
    const pksPtr = alloc(memory, 3 * 33);
    const sigsPtr = alloc(memory, buf.length);
    const msgPtr = alloc(memory, 32);
    writeMem(memory, pksPtr, concatPks([a.pk, b.pk, c.pk]));
    writeMem(memory, sigsPtr, buf);
    writeMem(memory, msgPtr, digest);

    // 2 sigs, threshold 2 — but only 1 verifies → reject.
    expect(host.host_checkmultisig(pksPtr, 3, sigsPtr, 2, msgPtr, 32, 2)).toBe(0);
  });
});

// ──────────────────────────────────────────────────────────────────────
// nextNSequence — BIP-68 encoding
// ──────────────────────────────────────────────────────────────────────

describe('nextNSequence', () => {
  test('encodes time mode (bit 22 set, value = ceil(secs / 512))', () => {
    // 60 seconds → ceil(60/512) = 1 unit; bit 22 set; bit 31 unset.
    const v = nextNSequence(null, 60);
    expect((v & VAULT_NSEQUENCE_TYPE_FLAG) >>> 0).toBe(VAULT_NSEQUENCE_TYPE_FLAG);
    expect((v & VAULT_NSEQUENCE_DISABLE_FLAG) >>> 0).toBe(0);
    expect((v & VAULT_NSEQUENCE_VALUE_MASK) >>> 0).toBe(1);
  });

  test('encodes 512s exactly as 1 unit', () => {
    const v = nextNSequence(null, VAULT_NSEQUENCE_TIME_UNIT_SECONDS);
    expect(v & VAULT_NSEQUENCE_VALUE_MASK).toBe(1);
  });

  test('encodes 1024s as 2 units', () => {
    const v = nextNSequence(null, VAULT_NSEQUENCE_TIME_UNIT_SECONDS * 2);
    expect(v & VAULT_NSEQUENCE_VALUE_MASK).toBe(2);
  });

  test('cooldown 0 disables relative-lock', () => {
    const v = nextNSequence(null, 0);
    expect((v & VAULT_NSEQUENCE_DISABLE_FLAG) >>> 0).toBe(VAULT_NSEQUENCE_DISABLE_FLAG);
  });

  test('caps at the BIP-68 max representable value (~33.5M sec)', () => {
    const huge = 100_000_000; // way over the 16-bit unit ceiling
    const v = nextNSequence(null, huge);
    expect(v & VAULT_NSEQUENCE_VALUE_MASK).toBe(VAULT_NSEQUENCE_VALUE_MASK);
    expect((v & VAULT_NSEQUENCE_TYPE_FLAG) >>> 0).toBe(VAULT_NSEQUENCE_TYPE_FLAG);
  });

  test('rejects negative cooldown', () => {
    expect(() => nextNSequence(null, -1)).toThrow();
  });

  test('rejects fractional cooldown', () => {
    expect(() => nextNSequence(null, 1.5)).toThrow();
  });

  test('decodeCooldownSeconds round-trips a typical encoding', () => {
    const v = nextNSequence(null, 1024);
    expect(decodeCooldownSeconds(v)).toBe(1024);
  });

  test('decodeCooldownSeconds returns null for disabled / block-mode encodings', () => {
    expect(decodeCooldownSeconds(VAULT_NSEQUENCE_DISABLE_FLAG)).toBe(null);
    expect(decodeCooldownSeconds(0x0000_0010)).toBe(null); // bit 22 unset → block-mode
  });
});

// ──────────────────────────────────────────────────────────────────────
// nSequence field is at the documented offset of the cell payload
// ──────────────────────────────────────────────────────────────────────

describe('vault cell layout', () => {
  test('nSequence written at +229..+233 of payload, little-endian', () => {
    const a = makeMember(601);
    const targetNs = 0x0040_00ff; // bit 22 set, value 0xff
    const v = createVault({
      memberPubkeys: [a.pk],
      threshold: 1,
      leafPrivKey: makeSk(602),
      protocolHash: makeProtocolHash(),
      counterparty: makeCounterparty(),
      nsequence: targetNs,
      parentTxid: zeros(32),
    });

    expect(readNSequence(v)).toBe(targetNs);
    // Direct byte read at the offset.
    const dv = new DataView(v.bytes.buffer, v.bytes.byteOffset, v.bytes.byteLength);
    expect(dv.getUint32(HEADER_SIZE + VAULT_OFFSET_NSEQUENCE, true)).toBe(targetNs);
    // Threshold byte at +63.
    expect(v.bytes[HEADER_SIZE + VAULT_OFFSET_THRESHOLD]).toBe(1);
  });

  test('parent_txid round-trips bytewise', () => {
    const a = makeMember(701);
    const txid = new Uint8Array(32);
    for (let i = 0; i < 32; i++) txid[i] = 0xc0 + (i & 0x0f);
    const v = createVault({
      memberPubkeys: [a.pk],
      threshold: 1,
      leafPrivKey: makeSk(702),
      protocolHash: makeProtocolHash(),
      counterparty: makeCounterparty(),
      nsequence: 0,
      parentTxid: txid,
    });
    expect(readParentTxid(v)).toEqual(txid);
  });
});

// ──────────────────────────────────────────────────────────────────────
// Round-trip via host.persistCell / host.loadCell after host.unlockTier(3)
//
// Tier 3 is locked at rest (encrypted under the vault's KEK). After
// `primeUnlockTier(3, factor, slotId)` resolves true, the engine's
// host_load_cell must return the same cell bytes that host_persist_cell
// would write back. This is the same pattern as the v0.1 host.spec.ts
// Tier-1 round-trip — extended here to confirm nothing in W11 regressed
// the W4 envelope path.
// ──────────────────────────────────────────────────────────────────────

describe('vault cell at-rest round-trip via host_unlock_tier(3)', () => {
  test('build vault, encrypt under tier-3 KEK, unlock, host_load_cell returns identical bytes', async () => {
    const factor = new TextEncoder().encode('vault-passphrase-or-yubikey-blob');
    const tier = 3;
    const slotId = 0x300;

    const a = makeMember(800);
    const b = makeMember(801);
    const c = makeMember(802);
    const v = createVault({
      memberPubkeys: [a.pk, b.pk, c.pk],
      threshold: 2,
      leafPrivKey: makeSk(899),
      protocolHash: makeProtocolHash(),
      counterparty: makeCounterparty(),
      nsequence: nextNSequence(null, 60),
      parentTxid: zeros(32),
    });

    // Build the at-rest envelope identically to what the wallet creation
    // flow would: derive the tier-3 KEK from the factor, AES-GCM-encrypt
    // the cell, write to IndexedDB.
    const kek = await deriveKek(tier, factor);
    const blob = await encryptCellForBridge(tier, kek, v.bytes);
    await slotPut(slotId, blob);

    // Unlock + load through the host externs (the same path the engine
    // uses at runtime).
    const { host, memory } = freshMemory();
    beginRequest();
    try {
      const ok = await primeUnlockTier(tier, factor, slotId);
      expect(ok).toBe(true);

      const outPtr = alloc(memory, CELL_SIZE);
      const loaded = host.host_load_cell(slotId, outPtr);
      expect(loaded).toBe(1);

      const got = readMem(memory, outPtr, CELL_SIZE);
      expect(got).toEqual(v.bytes);

      // Sanity: the loaded cell still parses as a 2-of-3 vault.
      expect(readThreshold({ bytes: got })).toBe(2);
      expect(readMemberCount({ bytes: got })).toBe(3);
    } finally {
      endRequest();
    }
  });

  test('Tier-3 load fails without prior unlock', async () => {
    const factor = new TextEncoder().encode('vault-pass');
    const tier = 3;
    const slotId = 0x301;

    const a = makeMember(900);
    const v = createVault({
      memberPubkeys: [a.pk],
      threshold: 1,
      leafPrivKey: makeSk(901),
      protocolHash: makeProtocolHash(),
      counterparty: makeCounterparty(),
      nsequence: 0,
      parentTxid: zeros(32),
    });
    const kek = await deriveKek(tier, factor);
    const blob = await encryptCellForBridge(tier, kek, v.bytes);
    await slotPut(slotId, blob);

    const { host, memory } = freshMemory();
    beginRequest();
    try {
      // Skip primeUnlockTier — no Tier-3 KEK staged.
      const outPtr = alloc(memory, CELL_SIZE);
      const loaded = host.host_load_cell(slotId, outPtr);
      expect(loaded).toBe(0);
    } finally {
      endRequest();
    }
  });

  test('host_persist_cell tier-classifies a fresh vault cell (Tier-3)', async () => {
    // Validates that createVault produces a cell whose domain flag is read
    // by the TS host's tier classifier as Tier-3 — required for
    // host_persist_cell to install the right at-rest KEK. The full
    // re-read path (persist → flush → reopen → load) hits a known v0.1
    // limitation in the TS host (`syncPersistCell` stages plaintext as the
    // "dirty" blob — see `cartridges/wallet-headers/brain/src/host.ts:728-742` and the
    // matching v0.1 limitation comment in `host.spec.ts`). That is not a
    // W11 regression and is tracked separately; we cover the substantive
    // round-trip via the encrypt-then-load test above.
    const factor = new TextEncoder().encode('persist-vault-pass');
    const tier = 3;
    const slotId = 0x302;

    const a = makeMember(1100);
    const b = makeMember(1101);
    const v = createVault({
      memberPubkeys: [a.pk, b.pk],
      threshold: 2,
      leafPrivKey: makeSk(1199),
      protocolHash: makeProtocolHash(),
      counterparty: makeCounterparty(),
      nsequence: nextNSequence(null, 30),
      parentTxid: zeros(32),
    });

    // Seed the slot so a Tier-3 KEK is staged after primeUnlockTier.
    const kek = await deriveKek(tier, factor);
    const blob = await encryptCellForBridge(tier, kek, v.bytes);
    await slotPut(slotId, blob);

    const { host, memory } = freshMemory();
    beginRequest();
    try {
      expect(await primeUnlockTier(tier, factor, slotId)).toBe(true);
      const cellPtr = alloc(memory, CELL_SIZE);
      writeMem(memory, cellPtr, v.bytes);
      // host_persist_cell returns 1 only if the cell tier-classifies AND
      // the matching tier KEK is staged. Both must be true for vault cells.
      expect(host.host_persist_cell(slotId, cellPtr, CELL_SIZE)).toBe(1);
    } finally {
      endRequest();
    }
  });
});

// ──────────────────────────────────────────────────────────────────────
// v0.1 stub regression: a non-multisig Tier-3 LINEAR cell (zero member
// table) still encrypts/decrypts cleanly. Tier 0/1/2 aren't touched here
// because §4.3 explicitly scopes v0.2 to Tier-3 only.
// ──────────────────────────────────────────────────────────────────────

describe('v0.1 backward compatibility', () => {
  test('a Tier-3 LINEAR cell with zero W11 fields still round-trips', async () => {
    const factor = new TextEncoder().encode('legacy-pass');
    const tier = 3;
    const slotId = 0x310;

    // Hand-rolled v0.1 stub cell — no createVault since createVault enforces
    // member_pubkeys >= 1. The v0.1 stub had a single LINEAR key with
    // priv_key at payload[0..32] and zeros elsewhere.
    const stub = new Uint8Array(CELL_SIZE);
    const dv = new DataView(stub.buffer);
    dv.setUint32(0, 0xdeadbeef, true);
    dv.setUint32(4, 0xcafebabe, true);
    dv.setUint32(8, 0x13371337, true);
    dv.setUint32(12, 0x42424242, true);
    dv.setUint32(16, _internal_for_tests.LINEARITY_LINEAR, true);
    dv.setUint32(20, 1, true);
    dv.setUint32(24, VAULT_DOMAIN_FLAG, true);
    // Pseudo-priv-key marker.
    for (let i = 0; i < 32; i++) stub[HEADER_SIZE + i] = 0xee;

    const kek = await deriveKek(tier, factor);
    const blob = await encryptCellForBridge(tier, kek, stub);
    await slotPut(slotId, blob);

    const { host, memory } = freshMemory();
    beginRequest();
    try {
      expect(await primeUnlockTier(tier, factor, slotId)).toBe(true);
      const outPtr = alloc(memory, CELL_SIZE);
      expect(host.host_load_cell(slotId, outPtr)).toBe(1);
      const got = readMem(memory, outPtr, CELL_SIZE);
      expect(got).toEqual(stub);
      // Threshold byte is 0 — recognizable as v0.1.
      expect(got[HEADER_SIZE + VAULT_OFFSET_THRESHOLD]).toBe(0);
    } finally {
      endRequest();
    }
  });
});

// ──────────────────────────────────────────────────────────────────────
// helpers
// ──────────────────────────────────────────────────────────────────────

function concatPks(pks: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(pks.length * 33);
  for (let i = 0; i < pks.length; i++) out.set(pks[i]!, i * 33);
  return out;
}

function encodeDerExt(r: bigint, s: bigint): Uint8Array {
  // Same encoder as vault.ts uses internally — duplicated for the
  // adversarial-sig forged-blob test. Public DER format.
  const rB = encInt(r);
  const sB = encInt(s);
  const total = 2 + rB.length + 2 + sB.length;
  const out = new Uint8Array(2 + total);
  out[0] = 0x30;
  out[1] = total;
  let off = 2;
  out[off++] = 0x02;
  out[off++] = rB.length;
  out.set(rB, off);
  off += rB.length;
  out[off++] = 0x02;
  out[off++] = sB.length;
  out.set(sB, off);
  return out;
}

function encInt(n: bigint): Uint8Array {
  let hex = n.toString(16);
  if (hex.length % 2 === 1) hex = '0' + hex;
  let bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  let start = 0;
  while (start < bytes.length - 1 && bytes[start] === 0 && (bytes[start + 1]! & 0x80) === 0) start++;
  bytes = bytes.slice(start);
  if ((bytes[0]! & 0x80) !== 0) {
    const padded = new Uint8Array(bytes.length + 1);
    padded[0] = 0x00;
    padded.set(bytes, 1);
    bytes = padded;
  }
  return bytes;
}

```
