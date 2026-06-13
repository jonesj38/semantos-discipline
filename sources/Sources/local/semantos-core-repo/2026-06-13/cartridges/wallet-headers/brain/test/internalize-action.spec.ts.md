---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/internalize-action.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.664538+00:00
---

# cartridges/wallet-headers/brain/test/internalize-action.spec.ts

```ts
// WA2 — internalizeAction tests.
//
// Per WALLET-ACTIVE-USE-ROADMAP.md §2 / WA2 deliverable 5:
//   "receive a synthetic BEEF, call internalizeAction, assert: BEEF
//    validation passes, derived key matches expected pubkey, OutputStore
//    now has the UTXO, listOutputs returns it, second internalize of the
//    same BEEF is idempotent (no duplicate)."
//
// Coverage:
//   • Happy path: BRC-29 wallet payment → derived key → P2PKH script
//     match → persisted with derivedKeyHash.
//   • Idempotency: second internalize of same outpoint returns no new
//     outpoints, listOutputs returns 1 row.
//   • Script mismatch is rejected with SCRIPT_MISMATCH.
//   • Bad sender pubkey is rejected with BAD_INPUT.
//   • Basket insertion path persists with arbitrary basket + tags.
//   • listActions joins description + labels by parent txid.
//   • internalize before createWallet is rejected with NOT_CREATED.

import { beforeEach, describe, expect, test } from 'bun:test';
import 'fake-indexeddb/auto';
import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

import {
  createWallet,
  internalizeAction,
  listOutputs,
  listActions,
  planTier0Sweep,
  getStatus,
  brc29DerivationKey,
  buildP2pkhScript,
  getIdentitySnapshot,
  _resetRuntimeForTests,
} from '../src/wallet-ops';
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

/** Construct a synthetic BEEF blob for tests: 32-byte parent txid (no
 *  magic — internalizeAction's structural check accepts this synthetic
 *  shape). */
function syntheticBeef(parentTxid: Uint8Array): Uint8Array {
  if (parentTxid.length !== 32) throw new Error('txid must be 32 bytes');
  // Just the parent txid + a few trailing bytes of body — internalizeAction
  // skips magic and reads the 32 bytes that follow when no magic match.
  const out = new Uint8Array(64);
  out.set(parentTxid, 0);
  // Stuff the rest with arbitrary bytes so the BEEF "body" exists.
  for (let i = 32; i < 64; i++) out[i] = i & 0xff;
  return out;
}

/** Build the locking script the *sender* would emit for a BRC-29 payment.
 *  Uses the wallet's own identity sk + the synthetic sender's pk to derive
 *  the same key the wallet will recover via internalizeAction. */
function buildBrc29Output(opts: {
  identityPk: Uint8Array;
  identitySk: Uint8Array;
  senderSk: Uint8Array;
  derivationPrefix: string;
  derivationSuffix: string;
}): { lockingScript: Uint8Array; senderIdentityKey: string } {
  const { protocolHash, index } = brc29DerivationKey(opts.derivationPrefix, opts.derivationSuffix);
  const senderPk = secp.getPublicKey(opts.senderSk, true);
  // Derive the same child key the receiver will derive — BRC-42 is symmetric
  // (recipient uses recipientSk×senderPk, sender uses senderSk×recipientPk;
  // both produce the same shared secret thus the same child key).
  // For the test: just use deriveLeafSync(identitySk, protocolHash, senderPk, index)
  // so the public key matches what internalizeAction will derive.
  const childSk = deriveLeafSync(opts.identitySk, protocolHash, senderPk, index)!;
  const childPk = secp.getPublicKey(childSk, true);
  childSk.fill(0);
  return {
    lockingScript: buildP2pkhScript(childPk),
    senderIdentityKey: bytesToHex(senderPk),
  };
}

function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

describe('WA2 — internalizeAction (wallet payment)', () => {
  test('happy path: synthetic BRC-29 payment → UTXO persisted, listOutputs returns it', async () => {
    const create = await createWallet(freshCreateInputs());
    expect(create.ok).toBe(true);
    if (!create.ok) return;

    const id = getIdentitySnapshot();
    const senderSk = new Uint8Array(32);
    crypto.getRandomValues(senderSk);

    const { lockingScript, senderIdentityKey } = buildBrc29Output({
      identityPk: id.identityPk,
      identitySk: id.identitySk,
      senderSk,
      derivationPrefix: 'invoice-2024-01',
      derivationSuffix: '0001',
    });

    const parentTxid = new Uint8Array(32);
    parentTxid.fill(0xa1);
    const beef = syntheticBeef(parentTxid);

    const r = await internalizeAction({
      tx: beef,
      outputs: [
        {
          outputIndex: 0,
          protocol: 'wallet payment',
          paymentRemittance: {
            senderIdentityKey,
            derivationPrefix: 'invoice-2024-01',
            derivationSuffix: '0001',
          },
          satoshis: 50_000n,
          lockingScript,
        },
      ],
      description: '50k sats from sender',
      labels: ['received'],
    });

    expect(r.ok).toBe(true);
    if (!r.ok) {
      console.log('error', r.error);
      return;
    }
    expect(r.value.accepted).toBe(true);
    expect(r.value.newOutpoints).toHaveLength(1);
    expect(r.value.newOutpoints[0]).toBe(`${bytesToHex(parentTxid)}:0`);

    // listOutputs surfaces the new UTXO.
    const utxos = await listOutputs({ basket: 'default' });
    expect(utxos).toHaveLength(1);
    expect(utxos[0]!.satoshis).toBe(50_000n);
    expect(utxos[0]!.outpoint.vout).toBe(0);
    expect(bytesToHex(utxos[0]!.outpoint.txid)).toBe(bytesToHex(parentTxid));
    expect(utxos[0]!.derivationContext.counterparty.length).toBe(33);
    expect(utxos[0]!.derivationContext.protocolHash.length).toBe(16);
    expect(utxos[0]!.beef.length).toBeGreaterThan(0);
    expect(utxos[0]!.status).toBe('unspent');
  });

  test('idempotency: second internalize of same BEEF + outpoint is a no-op', async () => {
    await createWallet(freshCreateInputs());
    const id = getIdentitySnapshot();
    const senderSk = new Uint8Array(32);
    crypto.getRandomValues(senderSk);

    const { lockingScript, senderIdentityKey } = buildBrc29Output({
      identityPk: id.identityPk,
      identitySk: id.identitySk,
      senderSk,
      derivationPrefix: 'inv-2',
      derivationSuffix: 'a',
    });

    const parentTxid = new Uint8Array(32);
    parentTxid.fill(0xb2);
    const beef = syntheticBeef(parentTxid);
    const inputs = {
      tx: beef,
      outputs: [
        {
          outputIndex: 0,
          protocol: 'wallet payment' as const,
          paymentRemittance: {
            senderIdentityKey,
            derivationPrefix: 'inv-2',
            derivationSuffix: 'a',
          },
          satoshis: 25_000n,
          lockingScript,
        },
      ],
      description: 'first',
      labels: ['initial'],
    };

    const r1 = await internalizeAction(inputs);
    expect(r1.ok).toBe(true);
    if (r1.ok) expect(r1.value.newOutpoints).toHaveLength(1);

    const r2 = await internalizeAction(inputs);
    expect(r2.ok).toBe(true);
    if (r2.ok) expect(r2.value.newOutpoints).toHaveLength(0);

    const utxos = await listOutputs();
    expect(utxos).toHaveLength(1);
  });

  test('Tier-0 plaintext exposure over 1M sats produces a sweep plan', async () => {
    await createWallet(freshCreateInputs());
    const id = getIdentitySnapshot();
    const senderSk = new Uint8Array(32);
    crypto.getRandomValues(senderSk);

    const { lockingScript, senderIdentityKey } = buildBrc29Output({
      identityPk: id.identityPk,
      identitySk: id.identitySk,
      senderSk,
      derivationPrefix: 'large-hot-balance',
      derivationSuffix: '0',
    });

    const parentTxid = new Uint8Array(32);
    parentTxid.fill(0xd4);
    const r = await internalizeAction({
      tx: syntheticBeef(parentTxid),
      outputs: [
        {
          outputIndex: 0,
          protocol: 'wallet payment',
          paymentRemittance: {
            senderIdentityKey,
            derivationPrefix: 'large-hot-balance',
            derivationSuffix: '0',
          },
          satoshis: 1_250_000n,
          lockingScript,
        },
      ],
      description: 'hot balance above cap',
      labels: ['received'],
    });
    expect(r.ok).toBe(true);

    const status = await getStatus();
    expect(status.ok).toBe(true);
    if (status.ok) {
      expect(status.value.tier0PlaintextExposure.sweepRequired).toBe(true);
      expect(status.value.tier0PlaintextExposure.balanceSats).toBe('1250000');
      expect(status.value.tier0PlaintextExposure.limitSats).toBe('1000000');
      expect(status.value.tier0PlaintextExposure.sweepTargetTier).toBe(1);
    }

    const plan = await planTier0Sweep();
    expect(plan.ok).toBe(true);
    if (plan.ok) {
      expect(plan.value.required).toBe(true);
      expect(plan.value.targetTier).toBe(1);
      expect(plan.value.sweepSatoshis).toBe('1250000');
      expect(plan.value.remainingPlaintextSats).toBe('0');
      expect(plan.value.sweepOutpoints).toEqual([`${bytesToHex(parentTxid)}:0`]);
    }
  });

  test('SCRIPT_MISMATCH when locking script does not match derived pubkey', async () => {
    await createWallet(freshCreateInputs());
    const id = getIdentitySnapshot();
    const senderSk = new Uint8Array(32);
    crypto.getRandomValues(senderSk);
    const senderPk = secp.getPublicKey(senderSk, true);

    // Build a P2PKH script for an *unrelated* pubkey so the wallet's
    // derivation path doesn't match.
    const wrongSk = new Uint8Array(32);
    wrongSk.fill(0x42);
    const wrongPk = secp.getPublicKey(wrongSk, true);
    const wrongScript = buildP2pkhScript(wrongPk);

    const parentTxid = new Uint8Array(32);
    parentTxid.fill(0xc3);
    const beef = syntheticBeef(parentTxid);

    const r = await internalizeAction({
      tx: beef,
      outputs: [
        {
          outputIndex: 0,
          protocol: 'wallet payment',
          paymentRemittance: {
            senderIdentityKey: bytesToHex(senderPk),
            derivationPrefix: 'inv',
            derivationSuffix: 's',
          },
          satoshis: 10_000n,
          lockingScript: wrongScript,
        },
      ],
      description: 'mismatched',
    });

    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('SCRIPT_MISMATCH');
  });

  test('BAD_INPUT on malformed senderIdentityKey', async () => {
    await createWallet(freshCreateInputs());
    const parentTxid = new Uint8Array(32).fill(1);
    const r = await internalizeAction({
      tx: syntheticBeef(parentTxid),
      outputs: [
        {
          outputIndex: 0,
          protocol: 'wallet payment',
          paymentRemittance: {
            senderIdentityKey: 'nothex',
            derivationPrefix: 'p',
            derivationSuffix: 's',
          },
          satoshis: 100n,
          lockingScript: new Uint8Array(25),
        },
      ],
      description: '',
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('BAD_INPUT');
  });

  test('BAD_INPUT on non-P2PKH locking script', async () => {
    await createWallet(freshCreateInputs());
    const id = getIdentitySnapshot();
    const senderSk = new Uint8Array(32);
    crypto.getRandomValues(senderSk);
    const senderPk = secp.getPublicKey(senderSk, true);

    const parentTxid = new Uint8Array(32).fill(1);
    const r = await internalizeAction({
      tx: syntheticBeef(parentTxid),
      outputs: [
        {
          outputIndex: 0,
          protocol: 'wallet payment',
          paymentRemittance: {
            senderIdentityKey: bytesToHex(senderPk),
            derivationPrefix: 'p',
            derivationSuffix: 's',
          },
          satoshis: 100n,
          lockingScript: new Uint8Array([0x6a, 0x01, 0x00]), // OP_RETURN, not P2PKH
        },
      ],
      description: '',
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('BAD_INPUT');
  });

  test('NOT_CREATED before createWallet', async () => {
    const r = await internalizeAction({
      tx: new Uint8Array(64),
      outputs: [
        {
          outputIndex: 0,
          protocol: 'basket insertion',
          insertionRemittance: { basket: 'archive' },
          satoshis: 1n,
          lockingScript: new Uint8Array(25),
        },
      ],
      description: '',
    });
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.error.kind).toBe('NOT_CREATED');
  });
});

describe('WA2 — internalizeAction (basket insertion)', () => {
  test('basket insertion path persists with arbitrary basket + tags', async () => {
    await createWallet(freshCreateInputs());
    const parentTxid = new Uint8Array(32).fill(0x55);
    const customScript = new Uint8Array([0x6a, 0x04, 0xde, 0xad, 0xbe, 0xef]);

    const r = await internalizeAction({
      tx: syntheticBeef(parentTxid),
      outputs: [
        {
          outputIndex: 7,
          protocol: 'basket insertion',
          insertionRemittance: {
            basket: 'metadata',
            tags: ['blog-post', 'public'],
            customInstructions: 'render-as-markdown',
          },
          satoshis: 0n,
          lockingScript: customScript,
        },
      ],
      description: 'metadata insertion',
      labels: ['metadata'],
    });
    expect(r.ok).toBe(true);

    const utxos = await listOutputs({ basket: 'metadata' });
    expect(utxos).toHaveLength(1);
    expect(utxos[0]!.tags).toEqual(['blog-post', 'public']);
    expect(new TextDecoder().decode(utxos[0]!.customInstructions)).toBe('render-as-markdown');

    // Default basket is empty — the insertion went into 'metadata'.
    const def = await listOutputs({ basket: 'default' });
    expect(def).toHaveLength(0);
  });
});

describe('WA2 — listActions', () => {
  test('joins description + labels by parent txid; one entry per tx', async () => {
    await createWallet(freshCreateInputs());
    const id = getIdentitySnapshot();
    const senderSk = new Uint8Array(32);
    crypto.getRandomValues(senderSk);

    const tx1 = new Uint8Array(32).fill(0x10);
    const tx2 = new Uint8Array(32).fill(0x20);

    const out1a = buildBrc29Output({
      identityPk: id.identityPk,
      identitySk: id.identitySk,
      senderSk,
      derivationPrefix: 'inv-1',
      derivationSuffix: 'a',
    });
    const out1b = buildBrc29Output({
      identityPk: id.identityPk,
      identitySk: id.identitySk,
      senderSk,
      derivationPrefix: 'inv-1',
      derivationSuffix: 'b',
    });
    const out2 = buildBrc29Output({
      identityPk: id.identityPk,
      identitySk: id.identitySk,
      senderSk,
      derivationPrefix: 'inv-2',
      derivationSuffix: 'a',
    });

    await internalizeAction({
      tx: syntheticBeef(tx1),
      outputs: [
        { outputIndex: 0, protocol: 'wallet payment', paymentRemittance: { senderIdentityKey: out1a.senderIdentityKey, derivationPrefix: 'inv-1', derivationSuffix: 'a' }, satoshis: 100n, lockingScript: out1a.lockingScript },
        { outputIndex: 1, protocol: 'wallet payment', paymentRemittance: { senderIdentityKey: out1b.senderIdentityKey, derivationPrefix: 'inv-1', derivationSuffix: 'b' }, satoshis: 200n, lockingScript: out1b.lockingScript },
      ],
      description: 'two-output payment',
      labels: ['multi'],
    });

    await internalizeAction({
      tx: syntheticBeef(tx2),
      outputs: [
        { outputIndex: 0, protocol: 'wallet payment', paymentRemittance: { senderIdentityKey: out2.senderIdentityKey, derivationPrefix: 'inv-2', derivationSuffix: 'a' }, satoshis: 300n, lockingScript: out2.lockingScript },
      ],
      description: 'single-output',
      labels: ['solo'],
    });

    const actions = await listActions();
    expect(actions).toHaveLength(2);
    const a1 = actions.find((a) => a.txid === bytesToHex(tx1));
    const a2 = actions.find((a) => a.txid === bytesToHex(tx2));
    expect(a1?.description).toBe('two-output payment');
    expect(a1?.labels).toEqual(['multi']);
    expect(a1?.outpoints).toHaveLength(2);
    expect(a2?.description).toBe('single-output');
    expect(a2?.outpoints).toHaveLength(1);
  });
});

```
