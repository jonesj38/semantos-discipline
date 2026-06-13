---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/core/anchor.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.610077+00:00
---

# cartridges/jambox/web/src/core/anchor.ts

```ts
/**
 * BSV anchor for jam sessions.
 *
 * Mirrors `apps/poker-agent/src/direct-broadcast/celltoken-tx-builder.ts`
 * (BRC-48 PushDrop CellToken pattern) but with browser-side local-key
 * signing. The jam payload (cells + scene + bpm + identity tags) is
 * embedded as the cell-bytes field. A second OP_RETURN output carries
 * a tiny decoder so anyone scanning chain history can rehydrate the song.
 *
 * Auto-anchor cadence is owned by main.ts — this module is just the
 * "give me a signed tx" primitive plus an ARC broadcaster.
 */

import {
  PrivateKey, P2PKH, Transaction, Script, OP,
} from '@bsv/sdk';
import { JamWalletClient } from './wallet-client.js';
import type { SerializedCell } from './sync';

export interface JamSessionPayload {
  v: 1;
  room: string;
  bpm: number;
  scene: number;
  identities: string[];
  cells: SerializedCell[];
  ts: number;
}

const FIXED_FEE = 200;
const CELL_SAT = 1;
const SEMANTIC_PATH = '/jam/v1/session';

const DECODER_JS = [
  '// jam-room v1 decoder. Find PushDrop output, extract field 4 (CBOR-ish JSON),',
  '// or just use the OP_RETURN data which is gzipped/raw JSON. The JamSessionPayload',
  '// schema: { v, room, bpm, scene, identities[], cells[], ts }. Each cell carries',
  '// stateHashHex, parentHashes[], patch{op,payload}, hat, depth, branch.',
  '// Replay: sort by depth, apply patches in order, derive grid+notes.',
].join('\n');

export interface AnchorResult {
  txid: string;
  rawHex: string;
  status: 'ok' | 'error';
  arcResponse?: unknown;
}

export interface Funding {
  txid: string;
  vout: number;
  satoshis: number;
  rawTx: string;
}

/** Get a single P2PKH funding UTXO via WoC. Returns null if none big enough. */
export async function fetchFunding(
  address: string, minSatoshis: number,
): Promise<Funding | null> {
  const r = await fetch(`https://api.whatsonchain.com/v1/bsv/main/address/${address}/unspent`);
  if (!r.ok) return null;
  const utxos = (await r.json()) as Array<{ tx_hash: string; tx_pos: number; value: number }>;
  const candidate = utxos
    .filter((u) => u.value >= minSatoshis)
    .sort((a, b) => a.value - b.value)[0];
  if (!candidate) return null;
  const raw = await fetch(`https://api.whatsonchain.com/v1/bsv/main/tx/${candidate.tx_hash}/hex`);
  if (!raw.ok) return null;
  return {
    txid: candidate.tx_hash,
    vout: candidate.tx_pos,
    satoshis: candidate.value,
    rawTx: await raw.text(),
  };
}

/** Build a PushDrop locking script for the jam cell payload. */
function buildJamPushDropScript(
  payloadBytes: Uint8Array, contentHash: Uint8Array, pubKeyHex: string,
): Script {
  const semanticPathBytes = new TextEncoder().encode(SEMANTIC_PATH);
  const fields: Uint8Array[] = [
    new TextEncoder().encode('jam.v1'),
    semanticPathBytes,
    contentHash,
    payloadBytes,
  ];
  const chunks: Array<{ op: number; data?: number[] }> = [];
  // <pubkey> OP_CHECKSIG <field1> <field2> <field3> <field4> OP_DROP×N
  const pubBytes = hexToBytes(pubKeyHex);
  chunks.push(pushBytes(pubBytes));
  chunks.push({ op: OP.OP_CHECKSIG });
  for (const f of fields) chunks.push(pushBytes(f));
  // OP_2DROP pairs + final OP_DROP if odd count
  let remaining = fields.length;
  while (remaining >= 2) { chunks.push({ op: OP.OP_2DROP }); remaining -= 2; }
  if (remaining === 1) chunks.push({ op: OP.OP_DROP });
  return new Script(chunks);
}

function pushBytes(bytes: Uint8Array): { op: number; data: number[] } {
  if (bytes.length <= 75) return { op: bytes.length, data: Array.from(bytes) };
  if (bytes.length <= 0xff) return { op: OP.OP_PUSHDATA1, data: Array.from(bytes) };
  if (bytes.length <= 0xffff) return { op: OP.OP_PUSHDATA2, data: Array.from(bytes) };
  return { op: OP.OP_PUSHDATA4, data: Array.from(bytes) };
}

function hexToBytes(h: string): Uint8Array {
  const out = new Uint8Array(h.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(h.substr(i * 2, 2), 16);
  return out;
}

/** Build the OP_RETURN decoder output. */
function buildDecoderOpReturn(): Script {
  const data = new TextEncoder().encode(DECODER_JS);
  return new Script([
    { op: OP.OP_FALSE },
    { op: OP.OP_RETURN },
    pushBytes(new TextEncoder().encode('jam.v1.decoder')),
    pushBytes(data),
  ]);
}

/** Sign + broadcast a jam-session anchor. Returns txid on success. */
export async function anchorJam(
  payload: JamSessionPayload, wif: string, arcUrl?: string,
): Promise<AnchorResult> {
  const pk = PrivateKey.fromWif(wif);
  const pub = pk.toPublicKey();
  const address = pub.toAddress();

  const json = JSON.stringify(payload);
  const payloadBytes = new TextEncoder().encode(json);
  const contentHash = new Uint8Array(
    await crypto.subtle.digest('SHA-256', payloadBytes),
  );

  const minSats = CELL_SAT + FIXED_FEE + 50;
  const funding = await fetchFunding(address, minSats);
  if (!funding) {
    return { txid: '', rawHex: '', status: 'error', arcResponse: 'no funding utxo' };
  }

  const sourceTx = Transaction.fromHex(funding.rawTx);
  const tx = new Transaction();
  const p2pkh = new P2PKH();
  tx.addInput({
    sourceTXID: funding.txid,
    sourceOutputIndex: funding.vout,
    sourceTransaction: sourceTx,
    unlockingScriptTemplate: p2pkh.unlock(pk),
  });

  const cellScript = buildJamPushDropScript(
    payloadBytes, contentHash, pub.toString(),
  );
  tx.addOutput({ lockingScript: cellScript, satoshis: CELL_SAT });
  tx.addOutput({ lockingScript: buildDecoderOpReturn(), satoshis: 0 });

  const change = funding.satoshis - CELL_SAT - FIXED_FEE;
  if (change > 0) {
    tx.addOutput({
      lockingScript: p2pkh.lock(address),
      satoshis: change,
    });
  }
  await tx.sign();
  const rawHex = tx.toHex();

  const arcEndpoint = arcUrl ?? 'https://arc.gorillapool.io';
  const arcResp = await fetch(`${arcEndpoint}/v1/tx`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ rawTx: rawHex }),
  });
  const arcBody = await arcResp.json().catch(() => ({}));

  return {
    txid: tx.id('hex') as string,
    rawHex,
    status: arcResp.ok ? 'ok' : 'error',
    arcResponse: arcBody,
  };
}

// ── Wallet-backed anchor (WASM / Metanet Desktop BRC-100 wallet) ───────────
//
// Delegates funding, signing, and broadcasting to the local BRC-100 wallet.
// The dApp builds the locking scripts; the wallet picks UTXOs, adds change,
// signs every input, and returns the final txid. No WIF exposure required.
//
// Compatible with:
//   • Metanet Desktop (http://localhost:3321)
//   • WASM wallet-browser running its own HTTP surface
//   • Any future BRC-100-compliant wallet implementation

/**
 * Create a WalletClient pointed at the local WASM/Metanet wallet.
 *
 * @param baseUrl  Override the default localhost:3321 endpoint.
 */
export function createJamWalletClient(baseUrl = 'http://localhost:3321'): JamWalletClient {
  return new JamWalletClient(baseUrl);
}

/**
 * Anchor a jam session using the local BRC-100 wallet.
 *
 * The wallet handles UTXO selection, fee calculation, signing, and broadcast.
 * Returns the settled txid on success.
 */
export async function anchorJamWithWallet(
  payload: JamSessionPayload,
  wallet: JamWalletClient,
): Promise<AnchorResult> {
  try {
    const json = JSON.stringify(payload);
    const payloadBytes = new TextEncoder().encode(json);
    const contentHash = new Uint8Array(
      await crypto.subtle.digest('SHA-256', payloadBytes),
    );

    // Get the wallet's identity public key for the PushDrop script
    const pubKeyHex = await wallet.getPublicKey({ identityKey: true });

    // Build locking scripts — same byte layout as the manual WIF path
    const cellScript = buildJamPushDropScript(payloadBytes, contentHash, pubKeyHex);
    const decoderScript = buildDecoderOpReturn();

    const result = await wallet.createAction({
      description: `jam session anchor · room=${payload.room} scene=${payload.scene} bpm=${payload.bpm}`,
      labels: ['jam-room', 'session-anchor'],
      outputs: [
        {
          lockingScript: cellScript.toHex(),
          satoshis: CELL_SAT,
          outputDescription: 'jam.v1 PushDrop session record',
        },
        {
          lockingScript: decoderScript.toHex(),
          satoshis: 0,
          outputDescription: 'jam.v1 decoder (OP_RETURN)',
        },
      ],
    });

    return {
      txid: result.txid,
      rawHex: '',   // wallet holds the full BEEF; caller just needs txid
      status: 'ok',
    };
  } catch (err) {
    return {
      txid: '',
      rawHex: '',
      status: 'error',
      arcResponse: err instanceof Error ? err.message : String(err),
    };
  }
}

// ── Phase F: Take & Arrangement anchoring ──────────────────────────────────

export interface TakeAnchorPayload {
  v: 1;
  kind: 'jam.take';
  takeId: string;
  room: string;
  players: string[];
  cellCount: number;
  audioHash?: string;
  ts: number;
}

export interface ArrangementAnchorPayload {
  v: 1;
  kind: 'jam.arrangement';
  arrangementId: string;
  room: string;
  takeIds: string[];
  ts: number;
}

const TAKE_SEMANTIC_PATH = '/jam/v1/take';
const ARRANGEMENT_SEMANTIC_PATH = '/jam/v1/arrangement';

/** Build a generic PushDrop script for any jam payload. */
export function buildAnchorScript(
  semanticPath: string,
  payloadBytes: Uint8Array,
  contentHash: Uint8Array,
  pubKeyHex: string,
): Script {
  const fields: Uint8Array[] = [
    new TextEncoder().encode('jam.v1'),
    new TextEncoder().encode(semanticPath),
    contentHash,
    payloadBytes,
  ];
  const chunks: Array<{ op: number; data?: number[] }> = [];
  const pubBytes = hexToBytes(pubKeyHex);
  chunks.push(pushBytes(pubBytes));
  chunks.push({ op: OP.OP_CHECKSIG });
  for (const f of fields) chunks.push(pushBytes(f));
  let remaining = fields.length;
  while (remaining >= 2) { chunks.push({ op: OP.OP_2DROP }); remaining -= 2; }
  if (remaining === 1) chunks.push({ op: OP.OP_DROP });
  return new Script(chunks);
}

/**
 * Anchor a take record on-chain.
 * Must be called explicitly — never automatic.
 */
export async function anchorTake(
  takePayload: TakeAnchorPayload,
  wif: string,
  arcUrl?: string,
): Promise<AnchorResult> {
  const pk = PrivateKey.fromWif(wif);
  const pub = pk.toPublicKey();
  const address = pub.toAddress();

  const json = JSON.stringify(takePayload);
  const payloadBytes = new TextEncoder().encode(json);
  const contentHash = new Uint8Array(
    await crypto.subtle.digest('SHA-256', payloadBytes),
  );

  const minSats = CELL_SAT + FIXED_FEE + 50;
  const funding = await fetchFunding(address, minSats);
  if (!funding) {
    return { txid: '', rawHex: '', status: 'error', arcResponse: 'no funding utxo' };
  }

  const sourceTx = Transaction.fromHex(funding.rawTx);
  const tx = new Transaction();
  const p2pkh = new P2PKH();
  tx.addInput({
    sourceTXID: funding.txid,
    sourceOutputIndex: funding.vout,
    sourceTransaction: sourceTx,
    unlockingScriptTemplate: p2pkh.unlock(pk),
  });

  const cellScript = buildAnchorScript(
    TAKE_SEMANTIC_PATH, payloadBytes, contentHash, pub.toString(),
  );
  tx.addOutput({ lockingScript: cellScript, satoshis: CELL_SAT });
  tx.addOutput({ lockingScript: buildDecoderOpReturn(), satoshis: 0 });

  const change = funding.satoshis - CELL_SAT - FIXED_FEE;
  if (change > 0) {
    tx.addOutput({
      lockingScript: p2pkh.lock(address),
      satoshis: change,
    });
  }
  await tx.sign();
  const rawHex = tx.toHex();

  const arcEndpoint = arcUrl ?? 'https://arc.gorillapool.io';
  const arcResp = await fetch(`${arcEndpoint}/v1/tx`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ rawTx: rawHex }),
  });
  const arcBody = await arcResp.json().catch(() => ({}));

  return {
    txid: tx.id('hex') as string,
    rawHex,
    status: arcResp.ok ? 'ok' : 'error',
    arcResponse: arcBody,
  };
}

/**
 * Anchor an arrangement record on-chain.
 * Must be called explicitly — never automatic.
 */
export async function anchorArrangement(
  arrangementPayload: ArrangementAnchorPayload,
  wif: string,
  arcUrl?: string,
): Promise<AnchorResult> {
  const pk = PrivateKey.fromWif(wif);
  const pub = pk.toPublicKey();
  const address = pub.toAddress();

  const json = JSON.stringify(arrangementPayload);
  const payloadBytes = new TextEncoder().encode(json);
  const contentHash = new Uint8Array(
    await crypto.subtle.digest('SHA-256', payloadBytes),
  );

  const minSats = CELL_SAT + FIXED_FEE + 50;
  const funding = await fetchFunding(address, minSats);
  if (!funding) {
    return { txid: '', rawHex: '', status: 'error', arcResponse: 'no funding utxo' };
  }

  const sourceTx = Transaction.fromHex(funding.rawTx);
  const tx = new Transaction();
  const p2pkh = new P2PKH();
  tx.addInput({
    sourceTXID: funding.txid,
    sourceOutputIndex: funding.vout,
    sourceTransaction: sourceTx,
    unlockingScriptTemplate: p2pkh.unlock(pk),
  });

  const cellScript = buildAnchorScript(
    ARRANGEMENT_SEMANTIC_PATH, payloadBytes, contentHash, pub.toString(),
  );
  tx.addOutput({ lockingScript: cellScript, satoshis: CELL_SAT });
  tx.addOutput({ lockingScript: buildDecoderOpReturn(), satoshis: 0 });

  const change = funding.satoshis - CELL_SAT - FIXED_FEE;
  if (change > 0) {
    tx.addOutput({
      lockingScript: p2pkh.lock(address),
      satoshis: change,
    });
  }
  await tx.sign();
  const rawHex = tx.toHex();

  const arcEndpoint = arcUrl ?? 'https://arc.gorillapool.io';
  const arcResp = await fetch(`${arcEndpoint}/v1/tx`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ rawTx: rawHex }),
  });
  const arcBody = await arcResp.json().catch(() => ({}));

  return {
    txid: tx.id('hex') as string,
    rawHex,
    status: arcResp.ok ? 'ok' : 'error',
    arcResponse: arcBody,
  };
}

```
