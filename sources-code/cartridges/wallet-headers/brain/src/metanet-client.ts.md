---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/metanet-client.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.659295+00:00
---

# cartridges/wallet-headers/brain/src/metanet-client.ts

```ts
// HTTP client for the local Metanet Desktop wallet (BRC-56 HTTP interface).
//
// Metanet Desktop listens on http://localhost:3321 and implements the
// @bsv/sdk WalletInterface as a JSON HTTP service (HTTPWalletJSON).
// All methods use POST with no /v1/ prefix — paths are /${method}.
// We use only:
//
//   POST /getPublicKey   — fetch the desktop wallet's identity key
//   POST /createAction   — fund an output in our wallet
//
// The response from createAction may return the transaction as:
//   • `tx`    (number[] byte array of BEEF)        ← @bsv/sdk default
//   • `beef`  (hex-encoded Atomic/Standard BEEF)  ← some versions
//   • `rawTx` (hex-encoded raw tx, no BUMP)       ← fallback

import {
  bytesFromHex,
  parseBeef,
  computeTxid,
  writeVarInt,
  BEEF_V1_MAGIC,
  concat,
} from './beef-codec';

export const METANET_BASE = 'http://localhost:3321';

// ── getPublicKey ──────────────────────────────────────────────────────

export interface GetPublicKeyResult {
  publicKey: string; // 33-byte compressed pubkey, hex
}

export async function getIdentityKey(base = METANET_BASE): Promise<Uint8Array> {
  // HTTPWalletJSON uses POST for all methods; identity key = protocolID omitted.
  const resp = await fetch(`${base}/getPublicKey`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ identityKey: true }),
  });
  if (!resp.ok) throw new Error(`getPublicKey ${resp.status}: ${await resp.text()}`);
  const body = await resp.json() as { publicKey?: string };
  if (!body.publicKey) throw new Error('getPublicKey: no publicKey in response');
  return bytesFromHex(body.publicKey);
}

// ── createAction ──────────────────────────────────────────────────────

export interface CreateActionOutput {
  lockingScript: string; // hex
  satoshis: number;
  outputDescription?: string;
  /** BRC-100 output tags. Always sent as [] when omitted (see createAction). */
  tags?: string[];
}

export interface CreateActionResult {
  beef: Uint8Array;
  txid: Uint8Array;
}

export async function createAction(
  outputs: CreateActionOutput[],
  description: string,
  base = METANET_BASE,
): Promise<CreateActionResult> {
  // Defensive: send the optional array fields (labels, per-output tags) as
  // empty arrays. A recent Metanet Desktop builds a peer/overlay notification
  // for each createAction and calls Array.from() on these — if they're
  // null/undefined it throws "Array.from requires an array-like object".
  // Sending [] keeps behaviour identical while satisfying the notifier.
  const requestBody = {
    description,
    outputs: outputs.map((o) => ({ ...o, tags: o.tags ?? [] })),
    labels: [] as string[],
  };
  const resp = await fetch(`${base}/createAction`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(requestBody),
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`createAction ${resp.status}: ${text}`);
  }

  const body = await resp.json() as {
    beef?: string;
    rawTx?: string;
    txid?: string;
    tx?: number[];        // @bsv/sdk returns number[] for the BEEF bytes
    signedTransaction?: string;
  };

  // Extract BEEF bytes — try multiple field names used by different versions.
  let beef: Uint8Array | null = null;
  if (body.beef && typeof body.beef === 'string') {
    beef = bytesFromHex(body.beef);
  } else if (Array.isArray(body.tx)) {
    beef = new Uint8Array(body.tx);
  } else if (body.rawTx && typeof body.rawTx === 'string') {
    // Raw tx without BUMP — wrap as a bare BEEF V1 with no bumps so the
    // rest of the pipeline can handle it uniformly. SPV can't be fully
    // verified without a BUMP; the caller will see 0 bumps and should
    // flag this for the user.
    beef = wrapRawTxAsBeef(bytesFromHex(body.rawTx));
  } else if (body.signedTransaction && typeof body.signedTransaction === 'string') {
    beef = bytesFromHex(body.signedTransaction);
  }

  if (!beef) throw new Error('createAction: no BEEF/rawTx in response');

  // Extract txid: prefer the explicit field, fall back to parsing the BEEF.
  let txid: Uint8Array;
  if (body.txid && typeof body.txid === 'string') {
    // txid in display order (reversed) → convert to internal byte order
    txid = bytesFromHex(body.txid).reverse();
  } else {
    const parsed = parseBeef(beef);
    const lastTx = parsed.txs.at(-1);
    if (!lastTx) throw new Error('createAction: BEEF contains no transactions');
    txid = parsed.subjectTxid ?? lastTx.txid;
  }

  return { beef, txid };
}

// ── Bare-BEEF wrapper for raw-tx fallback ─────────────────────────────

function wrapRawTxAsBeef(rawTx: Uint8Array): Uint8Array {
  // BEEF V1: magic(4) + nBUMPs=0(1) + nTxs=1(1) + rawTx + hasBUMP=0(1)
  const magic = new Uint8Array(4);
  new DataView(magic.buffer).setUint32(0, BEEF_V1_MAGIC, true);
  return concat([magic, writeVarInt(0), writeVarInt(1), rawTx, new Uint8Array([0])]);
}

```
