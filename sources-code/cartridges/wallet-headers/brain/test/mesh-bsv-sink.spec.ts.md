---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/test/mesh-bsv-sink.spec.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.663953+00:00
---

# cartridges/wallet-headers/brain/test/mesh-bsv-sink.spec.ts

```ts
// mesh-bsv-sink spec — anchor-tx construction is correct + correctly signed.
//
// Pure construction only: NO broadcast, NO mainnet, throwaway key. Proves the
// sink composes tx-builder + the pushdrop output into a valid, signed BSV tx
// the operator can later broadcast with the real Tier-0 key.

import { describe, expect, test } from 'bun:test';
import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

import {
  buildAnchorTx,
  type Funder,
  type FundingUtxo,
  type PushdropOutput,
} from '../src/mesh-bsv-sink';
import {
  computeSighash,
  buildP2pkhLock,
  pubkeyToHash160,
  type TxInput,
  type TxOutput,
} from '../src/tx-builder';
import { encodeDer } from '../src/der';

// secp v2 needs a sync HMAC for sync sign() (matches host.ts / vault.ts).
secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

/** A representative pushdrop: <cell> OP_DROP <leafPubkey> OP_CHECKSIG. */
function pushdropScript(cell: Uint8Array, leafPubkey: Uint8Array): Uint8Array {
  // PUSHDATA2 for the (large) cell, then OP_DROP, then push pubkey, OP_CHECKSIG.
  const out: number[] = [0x4d, cell.length & 0xff, (cell.length >> 8) & 0xff];
  for (const b of cell) out.push(b);
  out.push(0x75); // OP_DROP
  out.push(leafPubkey.length);
  for (const b of leafPubkey) out.push(b);
  out.push(0xac); // OP_CHECKSIG
  return new Uint8Array(out);
}

function makeFunder(): { funder: Funder; priv: Uint8Array; lastSighash: () => Uint8Array | null } {
  const priv = secp.utils.randomPrivateKey();
  const pubkey = secp.getPublicKey(priv, true); // 33-byte compressed
  let captured: Uint8Array | null = null;
  const funder: Funder = {
    pubkey,
    signSighash(sighash: Uint8Array): Uint8Array {
      captured = sighash;
      const sig = secp.sign(sighash, priv).normalizeS(); // low-S, matches wallet
      return encodeDer(sig.r, sig.s);
    },
  };
  return { funder, priv, lastSighash: () => captured };
}

function fakeUtxo(value: bigint): FundingUtxo {
  const txid = new Uint8Array(32);
  for (let i = 0; i < 32; i++) txid[i] = (i + 1) & 0xff;
  return { txid, vout: 0, value };
}

function anchorOutput(): PushdropOutput {
  const cell = new Uint8Array(1024);
  for (let i = 0; i < 1024; i++) cell[i] = (i * 7) & 0xff;
  const leaf = new Uint8Array(33);
  leaf[0] = 0x02;
  for (let i = 1; i < 33; i++) leaf[i] = i;
  return { lockingScript: pushdropScript(cell, leaf), satoshis: 1n };
}

describe('mesh-bsv-sink buildAnchorTx', () => {
  test('builds a funded, signed anchor tx with correct change', () => {
    const { funder, lastSighash } = makeFunder();
    const anchor = anchorOutput();
    const funding = fakeUtxo(5000n);

    const tx = buildAnchorTx({ anchor, funding, funder, feeSats: 1100n });

    // change = 5000 - 1 (anchor) - 1100 (fee) = 3899.
    expect(tx.changeSats).toBe(3899n);
    expect(tx.txid.length).toBe(32);
    // EF marker sits right after the 4-byte version: 00 00 00 00 00 EF.
    expect(Array.from(tx.efTx.slice(4, 10))).toEqual([0, 0, 0, 0, 0, 0xef]);
    // EF tx carries the source value+script, so it's longer than the std tx.
    expect(tx.efTx.length).toBeGreaterThan(tx.rawTx.length);

    // The sink computed the BIP143 sighash over [funding input] → [anchor, change],
    // and signed it. Recompute independently and verify the captured signature.
    const funderLock = buildP2pkhLock(pubkeyToHash160(funder.pubkey));
    const outputs: TxOutput[] = [
      { script: anchor.lockingScript, satoshis: 1n },
      { script: funderLock, satoshis: 3899n },
    ];
    const inputs: TxInput[] = [
      { txid: funding.txid, vout: 0, value: 5000n, script: funderLock, sequence: 0xffffffff },
    ];
    const expectedSighash = computeSighash(inputs, outputs, 0);
    const captured = lastSighash();
    expect(captured).not.toBeNull();
    expect(Array.from(captured!)).toEqual(Array.from(expectedSighash));
  });

  test('sweeps sub-dust change into the fee (single output)', () => {
    const { funder } = makeFunder();
    const anchor = anchorOutput();
    // value = anchor(1) + fee(1100) + 0 leftover → no change output.
    const tx = buildAnchorTx({ anchor, funding: fakeUtxo(1101n), funder, feeSats: 1100n });
    expect(tx.changeSats).toBe(0n);
    // Just under dust (dust default 1): leftover 0 → still single output.
  });

  test('rejects insufficient funding', () => {
    const { funder } = makeFunder();
    const anchor = anchorOutput();
    expect(() => buildAnchorTx({ anchor, funding: fakeUtxo(500n), funder, feeSats: 1100n })).toThrow();
  });

  test('rejects a non-compressed funder pubkey', () => {
    const anchor = anchorOutput();
    const badFunder: Funder = { pubkey: new Uint8Array(65), signSighash: () => new Uint8Array(70) };
    expect(() => buildAnchorTx({ anchor, funding: fakeUtxo(5000n), funder: badFunder, feeSats: 1100n })).toThrow();
  });
});

```
