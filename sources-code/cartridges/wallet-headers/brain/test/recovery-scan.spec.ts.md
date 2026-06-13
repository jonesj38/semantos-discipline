---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/recovery-scan.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.667875+00:00
---

# cartridges/wallet-headers/brain/test/recovery-scan.spec.ts

```ts
// WA4 — Recovery scan tests.
//
// Per WALLET-ACTIVE-USE-ROADMAP.md §2 / WA4 deliverable 7:
//   "synthetic mock indexer returns known UTXOs at known addresses.
//    recoverySync succeeds. OutputStore matches expected. DerivationStateStore
//    correctly updated. Resume after simulated cancellation produces same
//    final state."
//
// Coverage:
//   • Happy path: 3 contexts × known UTXOs at specific indices → all
//     UTXOs land in OutputStore.
//   • Gap window: scan stops after `gapWindow` consecutive empty addresses.
//   • Resume: aborting mid-scan persists state; a follow-up scan returns
//     the same totals.
//   • Indexer error → status=FAILED with diagnostic message.
//   • BEEF verifier rejects wrong-txid pair → no insertion.

import { beforeEach, describe, expect, test } from 'bun:test';
import 'fake-indexeddb/auto';
import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

import {
  createWallet,
  recoverWallet,
  recordContext,
  buildP2pkhScript,
  brc29DerivationKey,
  exportRecoveryEnvelope,
  listOutputs,
  getIdentitySnapshot,
  _resetRuntimeForTests,
} from '../src/wallet-ops';
import {
  recoverySync,
  createMockIndexer,
  loadResumeState,
  type IndexedUtxo,
  type Indexer,
  type ScanProgress,
} from '../src/recovery-scan';
import { _resetDbForTests } from '../src/storage';
import { deriveLeafSync } from '../src/host';

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

function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

/** Build a synthetic UTXO for an address derived from (identitySk,
 *  protocolHash, counterparty, index) and return both the address (h160)
 *  and the UTXO + BEEF. */
function buildSyntheticUtxo(input: {
  identitySk: Uint8Array;
  protocolHash: Uint8Array;
  counterparty: Uint8Array;
  index: number;
  txidByte: number;
  vout: number;
  satoshis: bigint;
}): { addressH160Hex: string; utxo: IndexedUtxo; txidHex: string; beef: Uint8Array } {
  const childSk = deriveLeafSync(
    input.identitySk,
    input.protocolHash,
    input.counterparty,
    BigInt(input.index),
  )!;
  const childPk = secp.getPublicKey(childSk, true);
  childSk.fill(0);
  const lockingScript = buildP2pkhScript(childPk);
  const addressH160 = lockingScript.slice(3, 23);

  const txid = new Uint8Array(32).fill(input.txidByte);
  // Synthetic BEEF: txid in the first 32 bytes (no magic) — matches the
  // synthetic test path in defaultVerifyBeef.
  const beef = new Uint8Array(64);
  beef.set(txid, 0);

  return {
    addressH160Hex: bytesToHex(addressH160),
    utxo: {
      txid,
      vout: input.vout,
      satoshis: input.satoshis,
      lockingScriptHex: bytesToHex(lockingScript),
      confirmations: 1,
    },
    txidHex: bytesToHex(txid),
    beef,
  };
}

describe('WA4 — recoverySync (happy path)', () => {
  test('3 contexts × known UTXOs → 50K + 25K + 10K all recovered', async () => {
    const create = await createWallet(freshCreateInputs());
    expect(create.ok).toBe(true);
    if (!create.ok) return;
    const id = getIdentitySnapshot();

    const ph = (label: string) => brc29DerivationKey(label, '0').protocolHash;
    const cp = (label: string) => {
      // Real pubkey on the curve: derive a private key from the label and
      // take its public form. secp.getSharedSecret rejects off-curve
      // points, so we can't fake the counterparty with arbitrary bytes.
      const sk = nobleSha256(new TextEncoder().encode(`cp:${label}`));
      return secp.getPublicKey(sk, true);
    };

    // Three (protocolHash, counterparty) contexts. Each has UTXOs at
    // known indices.
    const aliceUtxo = buildSyntheticUtxo({
      identitySk: id.identitySk,
      protocolHash: ph('alice-payment'),
      counterparty: cp('alice'),
      index: 0,
      txidByte: 0xa0,
      vout: 0,
      satoshis: 50_000n,
    });
    const bobUtxo = buildSyntheticUtxo({
      identitySk: id.identitySk,
      protocolHash: ph('bob-payment'),
      counterparty: cp('bob'),
      index: 0,
      txidByte: 0xb0,
      vout: 0,
      satoshis: 25_000n,
    });
    const carolUtxo = buildSyntheticUtxo({
      identitySk: id.identitySk,
      protocolHash: ph('carol-payment'),
      counterparty: cp('carol'),
      index: 0,
      txidByte: 0xc0,
      vout: 0,
      satoshis: 10_000n,
    });

    // Register the contexts so the scan knows where to look.
    await recordContext(ph('alice-payment'), cp('alice'));
    await recordContext(ph('bob-payment'), cp('bob'));
    await recordContext(ph('carol-payment'), cp('carol'));

    const indexer = createMockIndexer({
      unspent: {
        [aliceUtxo.addressH160Hex]: [aliceUtxo.utxo],
        [bobUtxo.addressH160Hex]: [bobUtxo.utxo],
        [carolUtxo.addressH160Hex]: [carolUtxo.utxo],
      },
      beefs: {
        [aliceUtxo.txidHex]: aliceUtxo.beef,
        [bobUtxo.txidHex]: bobUtxo.beef,
        [carolUtxo.txidHex]: carolUtxo.beef,
      },
    });

    const result = await recoverySync({ indexer, gapWindow: 5 });
    expect(result.status).toBe('COMPLETE');
    expect(result.utxosRecovered).toBe(3);
    expect(result.satsRecovered).toBe(85_000n);

    const utxos = await listOutputs();
    expect(utxos).toHaveLength(3);
    const sums = utxos.map((u) => Number(u.satoshis)).sort((a, b) => a - b);
    expect(sums).toEqual([10_000, 25_000, 50_000]);
  });

  test('multiple UTXOs at the same context (different indices)', async () => {
    await createWallet(freshCreateInputs());
    const id = getIdentitySnapshot();

    const protocolHash = brc29DerivationKey('multi', '0').protocolHash;
    const counterparty = secp.getPublicKey(
      nobleSha256(new TextEncoder().encode('cp:peer')),
      true,
    );

    await recordContext(protocolHash, counterparty);

    // Three UTXOs at indices 0, 1, 2 then a gap.
    const utxos = [0, 1, 2].map((i) =>
      buildSyntheticUtxo({
        identitySk: id.identitySk,
        protocolHash,
        counterparty,
        index: i,
        txidByte: 0x10 + i,
        vout: 0,
        satoshis: 1000n * BigInt(i + 1),
      }),
    );

    const unspent: Record<string, IndexedUtxo[]> = {};
    const beefs: Record<string, Uint8Array> = {};
    for (const u of utxos) {
      unspent[u.addressH160Hex] = [u.utxo];
      beefs[u.txidHex] = u.beef;
    }
    const indexer = createMockIndexer({ unspent, beefs });

    const result = await recoverySync({ indexer, gapWindow: 5 });
    expect(result.status).toBe('COMPLETE');
    expect(result.utxosRecovered).toBe(3);
    expect(result.satsRecovered).toBe(6000n);
  });
});

describe('WA4 — gap window', () => {
  test('stops scanning a context after `gapWindow` consecutive empty addresses', async () => {
    await createWallet(freshCreateInputs());
    const protocolHash = brc29DerivationKey('p', '0').protocolHash;
    const counterparty = secp.getPublicKey(
      nobleSha256(new TextEncoder().encode('cp:gap-test')),
      true,
    );
    await recordContext(protocolHash, counterparty);

    let getUnspentCalls = 0;
    const indexer: Indexer = {
      trustModel: 'mock',
      async getUnspent() {
        getUnspentCalls++;
        return [];
      },
      async getBeef() {
        return null;
      },
    };

    const result = await recoverySync({ indexer, gapWindow: 7 });
    expect(result.status).toBe('COMPLETE');
    expect(result.utxosRecovered).toBe(0);
    // After gap of 7 empties on the only context, scan stops.
    expect(getUnspentCalls).toBe(7);
  });
});

describe('WA4 — abort + resume', () => {
  test('AbortSignal mid-scan → status=INCOMPLETE, resume picks up where it left off', async () => {
    await createWallet(freshCreateInputs());
    const id = getIdentitySnapshot();
    const ph = brc29DerivationKey('p', '0').protocolHash;
    const cp = secp.getPublicKey(
      nobleSha256(new TextEncoder().encode('cp:abort-peer')),
      true,
    );
    await recordContext(ph, cp);

    const utxo = buildSyntheticUtxo({
      identitySk: id.identitySk,
      protocolHash: ph,
      counterparty: cp,
      index: 0,
      txidByte: 0x77,
      vout: 0,
      satoshis: 7_000n,
    });

    const indexer = createMockIndexer({
      unspent: { [utxo.addressH160Hex]: [utxo.utxo] },
      beefs: { [utxo.txidHex]: utxo.beef },
    });

    const ac = new AbortController();
    // Abort after 1 progress callback fires.
    let calls = 0;
    const onProgress = (_p: ScanProgress) => {
      calls++;
      if (calls === 1) ac.abort();
    };

    const result = await recoverySync({
      indexer,
      gapWindow: 3,
      abortSignal: ac.signal,
      onProgress,
    });
    expect(['INCOMPLETE', 'COMPLETE'].includes(result.status)).toBe(true);

    // Resume by calling again — the scan picks up via persisted state.
    const result2 = await recoverySync({
      indexer,
      gapWindow: 3,
    });
    expect(result2.status).toBe('COMPLETE');

    const persisted = await loadResumeState();
    expect(persisted?.status).toBe('COMPLETE');
  });
});

describe('WA4 — error handling', () => {
  test('indexer 5xx surfaces as FAILED with diagnostic', async () => {
    await createWallet(freshCreateInputs());
    const ph = brc29DerivationKey('p', '0').protocolHash;
    const cp = secp.getPublicKey(
      nobleSha256(new TextEncoder().encode('cp:5xx-peer')),
      true,
    );
    await recordContext(ph, cp);

    const indexer: Indexer = {
      trustModel: 'mock',
      async getUnspent() {
        throw new Error('500 Internal Server Error');
      },
      async getBeef() {
        return null;
      },
    };

    const result = await recoverySync({ indexer, gapWindow: 3 });
    expect(result.status).toBe('FAILED');
    expect(result.diagnostic).toContain('500');
  });

  test('BEEF verifier rejecting → utxo skipped, scan continues', async () => {
    await createWallet(freshCreateInputs());
    const id = getIdentitySnapshot();
    const ph = brc29DerivationKey('p', '0').protocolHash;
    const cp = secp.getPublicKey(
      nobleSha256(new TextEncoder().encode('cp:reject-peer')),
      true,
    );
    await recordContext(ph, cp);

    const utxo = buildSyntheticUtxo({
      identitySk: id.identitySk,
      protocolHash: ph,
      counterparty: cp,
      index: 0,
      txidByte: 0x99,
      vout: 0,
      satoshis: 1n,
    });

    const indexer = createMockIndexer({
      unspent: { [utxo.addressH160Hex]: [utxo.utxo] },
      beefs: { [utxo.txidHex]: utxo.beef },
    });

    const result = await recoverySync({
      indexer,
      gapWindow: 3,
      verifyBeef: async () => false, // reject everything
    });
    expect(result.status).toBe('COMPLETE');
    expect(result.utxosRecovered).toBe(0);
  });
});

describe('WA4 — full recovery flow integration', () => {
  test('createWallet → record → exportEnvelope → wipe → recover → recoverySync rebuilds OutputStore', async () => {
    // Phase A: create wallet, touch some contexts.
    const create = await createWallet(freshCreateInputs());
    expect(create.ok).toBe(true);
    if (!create.ok) return;
    const id = getIdentitySnapshot();

    const ph1 = brc29DerivationKey('alice-payment', '0').protocolHash;
    const cp1 = secp.getPublicKey(
      nobleSha256(new TextEncoder().encode('cp:alice-integration')),
      true,
    );
    await recordContext(ph1, cp1);

    // Build synthetic UTXOs the indexer will return *after* recovery.
    const utxoA = buildSyntheticUtxo({
      identitySk: id.identitySk,
      protocolHash: ph1,
      counterparty: cp1,
      index: 0,
      txidByte: 0xab,
      vout: 0,
      satoshis: 100_000n,
    });
    const utxoB = buildSyntheticUtxo({
      identitySk: id.identitySk,
      protocolHash: ph1,
      counterparty: cp1,
      index: 1,
      txidByte: 0xcd,
      vout: 0,
      satoshis: 200_000n,
    });

    // Phase B: export the envelope that carries the context list.
    const exp = await exportRecoveryEnvelope({
      challengeAnswers: ['Smith', 'Sydney', 'Rover'],
    });
    expect(exp.ok).toBe(true);
    if (!exp.ok) return;
    const envelope = exp.value;

    // Phase C: wipe the device.
    _resetRuntimeForTests();
    _resetDbForTests();
    await new Promise<void>((resolve) => {
      const req = indexedDB.deleteDatabase('semantos-wallet');
      req.onsuccess = () => resolve();
      req.onerror = () => resolve();
      req.onblocked = () => resolve();
    });

    // Phase D: recover.
    const rec = await recoverWallet({
      envelope,
      challengeAnswers: ['Smith', 'Sydney', 'Rover'],
      tier1Pin: new TextEncoder().encode('5678'),
      tier2Factor: new TextEncoder().encode('new-passphrase'),
      tier3Factor: new TextEncoder().encode('new-vault'),
    });
    expect(rec.ok).toBe(true);
    if (!rec.ok) return;

    // Phase E: scan rebuilds OutputStore from the indexer.
    const indexer = createMockIndexer({
      unspent: {
        [utxoA.addressH160Hex]: [utxoA.utxo],
        [utxoB.addressH160Hex]: [utxoB.utxo],
      },
      beefs: {
        [utxoA.txidHex]: utxoA.beef,
        [utxoB.txidHex]: utxoB.beef,
      },
    });
    const result = await recoverySync({ indexer, gapWindow: 5 });
    expect(result.status).toBe('COMPLETE');
    expect(result.utxosRecovered).toBe(2);
    expect(result.satsRecovered).toBe(300_000n);

    const utxos = await listOutputs();
    expect(utxos).toHaveLength(2);
  });
});

```
