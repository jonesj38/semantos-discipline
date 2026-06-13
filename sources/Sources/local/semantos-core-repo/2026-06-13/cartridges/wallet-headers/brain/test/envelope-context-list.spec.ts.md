---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/envelope-context-list.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.671001+00:00
---

# cartridges/wallet-headers/brain/test/envelope-context-list.spec.ts

```ts
// WA3 — envelope context list tests.
//
// Per WALLET-ACTIVE-USE-ROADMAP.md §2 / WA3 deliverable 5:
//   "create wallet, sign 5 spends across 3 distinct (protocol, counterparty)
//    contexts, export envelope, parse, assert all 3 contexts appear in
//    derivationStateSnapshot.records with correct currentIndex values."
//
// Coverage:
//   • recordContext is idempotent on duplicates.
//   • nextIndexForContext populates ContextRegistry implicitly.
//   • snapshotDerivationContexts merges state + registry correctly.
//   • currentIndex: null records are preserved through envelope build.
//   • exportRecoveryEnvelope refreshes the cached envelope with current
//     state and decrypts under the same answers.
//   • recoverWallet restores ContextRegistry from null-index records.

import { beforeEach, describe, expect, test } from 'bun:test';
import 'fake-indexeddb/auto';
import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

import {
  createWallet,
  recoverWallet,
  recordContext,
  listContextRegistry,
  snapshotDerivationContexts,
  exportRecoveryEnvelope,
  nextIndexForContext,
  _resetRuntimeForTests,
} from '../src/wallet-ops';
import { _resetDbForTests } from '../src/storage';
import { decryptRecoverySeed } from '../src/plexus/envelope';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

function freshCreateInputs() {
  return {
    challengeQuestions: ["Mother's maiden name?", 'City of birth?', 'First pet?'] as [string, string, string],
    challengeAnswers: ['Smith', 'Sydney', 'Rover'] as [string, string, string],
    contactEmail: 'user@example.com',
    tier1Pin: new TextEncoder().encode('1234'),
    tier2Factor: new TextEncoder().encode('passphrase'),
    tier3Factor: new TextEncoder().encode('vault'),
  };
}

function ph(label: string): Uint8Array {
  // Deterministic 16-byte protocol hash for tests.
  const out = new Uint8Array(16);
  const src = nobleSha256(new TextEncoder().encode(label));
  out.set(src.slice(0, 16));
  return out;
}

function cp(label: string): Uint8Array {
  // Deterministic 33-byte "counterparty" pubkey-shaped fixture.
  const out = new Uint8Array(33);
  out[0] = 0x02;
  const src = nobleSha256(new TextEncoder().encode(label));
  out.set(src, 1);
  return out;
}

function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

beforeEach(() => {
  _resetRuntimeForTests();
  _resetDbForTests();
  return new Promise<void>((resolve) => {
    const req = indexedDB.deleteDatabase('semantos-wallet');
    req.onsuccess = () => resolve();
    req.onerror = () => resolve();
    req.onblocked = () => resolve();
  });
});

describe('WA3 — ContextRegistry', () => {
  test('recordContext is idempotent — duplicates collapse', async () => {
    await createWallet(freshCreateInputs());
    await recordContext(ph('brc-29'), cp('alice'));
    await recordContext(ph('brc-29'), cp('alice'));
    await recordContext(ph('brc-29'), cp('alice'));
    const reg = await listContextRegistry();
    expect(reg).toHaveLength(1);
    expect(reg[0].protocolHash).toBe(bytesToHex(ph('brc-29')));
    expect(reg[0].counterparty).toBe(bytesToHex(cp('alice')));
  });

  test('recordContext rejects bad lengths', async () => {
    await createWallet(freshCreateInputs());
    await expect(recordContext(new Uint8Array(15), cp('alice'))).rejects.toThrow();
    await expect(recordContext(ph('p'), new Uint8Array(32))).rejects.toThrow();
  });

  test('three distinct contexts appear in the registry', async () => {
    await createWallet(freshCreateInputs());
    await recordContext(ph('brc-29'), cp('alice'));
    await recordContext(ph('brc-29'), cp('bob'));
    await recordContext(ph('brc-77'), cp('alice'));
    const reg = await listContextRegistry();
    expect(reg).toHaveLength(3);
  });

  test('nextIndexForContext records the context implicitly', async () => {
    await createWallet(freshCreateInputs());
    const before = await listContextRegistry();
    expect(before).toHaveLength(0);

    await nextIndexForContext(ph('brc-29'), cp('carol'));
    const after = await listContextRegistry();
    expect(after).toHaveLength(1);
    expect(after[0].counterparty).toBe(bytesToHex(cp('carol')));
  });
});

describe('WA3 — snapshotDerivationContexts', () => {
  test('merges live state rows with registry-only entries (null currentIndex)', async () => {
    await createWallet(freshCreateInputs());

    // Context A: advanced via nextIndexForContext → has currentIndex 0
    await nextIndexForContext(ph('brc-29'), cp('alice'));

    // Context B: registered only (no index allocated) → currentIndex: null
    await recordContext(ph('brc-29'), cp('bob'));

    // Context C: advanced twice → currentIndex 1
    await nextIndexForContext(ph('brc-77'), cp('alice'));
    await nextIndexForContext(ph('brc-77'), cp('alice'));

    const snap = await snapshotDerivationContexts();
    expect(snap).toHaveLength(3);

    const byCp = new Map(snap.map((r) => [`${r.protocolHash}:${r.counterparty}`, r]));

    const aKey = `${bytesToHex(ph('brc-29'))}:${bytesToHex(cp('alice'))}`;
    const bKey = `${bytesToHex(ph('brc-29'))}:${bytesToHex(cp('bob'))}`;
    const cKey = `${bytesToHex(ph('brc-77'))}:${bytesToHex(cp('alice'))}`;

    expect(byCp.get(aKey)?.currentIndex).toBe(0);
    expect(byCp.get(bKey)?.currentIndex).toBeNull();
    expect(byCp.get(cKey)?.currentIndex).toBe(1);
  });

  test('5 spends across 3 contexts → all 3 in snapshot with correct indices', async () => {
    // Spec: "sign 5 spends across 3 distinct (protocol, counterparty) contexts,
    //        export envelope, parse, assert all 3 contexts appear in records
    //        with correct currentIndex values."
    await createWallet(freshCreateInputs());

    // 2 spends to Alice@brc-29
    await nextIndexForContext(ph('brc-29'), cp('alice'));
    await nextIndexForContext(ph('brc-29'), cp('alice'));
    // 2 spends to Bob@brc-29
    await nextIndexForContext(ph('brc-29'), cp('bob'));
    await nextIndexForContext(ph('brc-29'), cp('bob'));
    // 1 spend to Alice@brc-77
    await nextIndexForContext(ph('brc-77'), cp('alice'));

    const snap = await snapshotDerivationContexts();
    expect(snap).toHaveLength(3);

    const byCp = new Map(snap.map((r) => [`${r.protocolHash}:${r.counterparty}`, r]));
    expect(byCp.get(`${bytesToHex(ph('brc-29'))}:${bytesToHex(cp('alice'))}`)?.currentIndex).toBe(1);
    expect(byCp.get(`${bytesToHex(ph('brc-29'))}:${bytesToHex(cp('bob'))}`)?.currentIndex).toBe(1);
    expect(byCp.get(`${bytesToHex(ph('brc-77'))}:${bytesToHex(cp('alice'))}`)?.currentIndex).toBe(0);
  });
});

describe('WA3 — exportRecoveryEnvelope', () => {
  test('rebuilds envelope with current snapshot, decryptable under same answers', async () => {
    const r = await createWallet(freshCreateInputs());
    expect(r.ok).toBe(true);
    if (!r.ok) return;

    // Touch some contexts after creation.
    await nextIndexForContext(ph('brc-29'), cp('alice'));
    await recordContext(ph('brc-29'), cp('bob'));

    const exportResult = await exportRecoveryEnvelope({
      challengeAnswers: ['Smith', 'Sydney', 'Rover'],
    });
    expect(exportResult.ok).toBe(true);
    if (!exportResult.ok) return;

    const refreshed = exportResult.value;
    expect(refreshed.derivationStateSnapshot.records).toHaveLength(2);

    // Same identity, same contact email.
    expect(refreshed.identityKey).toBe(r.value.identity.identityPkHex);
    expect(refreshed.contactEmail).toBe('user@example.com');

    // The seed is still recoverable under the same answers.
    const seed = await decryptRecoverySeed(refreshed, ['Smith', 'Sydney', 'Rover']);
    expect(seed).not.toBeNull();
    expect(seed!.length).toBe(64);

    // Wrong answers don't decrypt.
    const fail = await decryptRecoverySeed(refreshed, ['Wrong', 'Sydney', 'Rover']);
    expect(fail).toBeNull();
  });

  test('rejects bad answers length', async () => {
    await createWallet(freshCreateInputs());
    const r = await exportRecoveryEnvelope({ challengeAnswers: ['only-one'] });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('BAD_INPUT');
  });

  test('returns DECRYPT_FAILED on wrong answers', async () => {
    await createWallet(freshCreateInputs());
    const r = await exportRecoveryEnvelope({
      challengeAnswers: ['nope', 'nope', 'nope'],
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('DECRYPT_FAILED');
  });
});

describe('WA3 — null currentIndex round-trip', () => {
  test('recoverWallet restores ContextRegistry from null-index snapshot records', async () => {
    const r = await createWallet(freshCreateInputs());
    expect(r.ok).toBe(true);
    if (!r.ok) return;

    // Mix of advanced + registered-only contexts.
    await nextIndexForContext(ph('brc-29'), cp('alice'));
    await recordContext(ph('brc-29'), cp('bob'));
    await recordContext(ph('brc-77'), cp('eve'));

    // Refresh the envelope so it picks up the new contexts.
    const exp = await exportRecoveryEnvelope({
      challengeAnswers: ['Smith', 'Sydney', 'Rover'],
    });
    expect(exp.ok).toBe(true);
    if (!exp.ok) return;

    const envelope = exp.value;
    expect(envelope.derivationStateSnapshot.records).toHaveLength(3);

    // Wipe the device.
    _resetRuntimeForTests();
    _resetDbForTests();
    await new Promise<void>((resolve) => {
      const req = indexedDB.deleteDatabase('semantos-wallet');
      req.onsuccess = () => resolve();
      req.onerror = () => resolve();
      req.onblocked = () => resolve();
    });

    // Recover from the envelope.
    const rec = await recoverWallet({
      envelope,
      challengeAnswers: ['Smith', 'Sydney', 'Rover'],
      tier1Pin: new TextEncoder().encode('5678'),
      tier2Factor: new TextEncoder().encode('new-passphrase'),
      tier3Factor: new TextEncoder().encode('new-vault'),
    });
    expect(rec.ok).toBe(true);
    if (!rec.ok) return;

    // Only the advanced context (alice@brc-29) gets a state-store row;
    // the other two are null-index. derivationStateRecordsReplayed only
    // counts the live ones.
    expect(rec.value.derivationStateRecordsReplayed).toBe(1);

    // But ContextRegistry restoration includes ALL three — that's how WA4
    // bounds the recovery scan address space.
    const reg = await listContextRegistry();
    expect(reg).toHaveLength(3);
  });
});

```
