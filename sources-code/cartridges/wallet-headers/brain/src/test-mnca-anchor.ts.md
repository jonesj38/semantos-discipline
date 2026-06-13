---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/test-mnca-anchor.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.645087+00:00
---

# cartridges/wallet-headers/brain/src/test-mnca-anchor.ts

```ts
// test-mnca-anchor.ts — anchor a computed MNCA snapshot cell on mainnet BSV.
//
// OPERATOR-RUN. Mirrors test-key-rotation.ts (the proven fund→spend→ARC
// template), swapping the spend output for a PUSHDROP that carries the
// snapshot cell, owned by a recoverable Tier-0 BRC-42 leaf.
//
// Flow:
//   fund    Metanet Desktop (:3321) → identity P2PKH   (anchorSats + fee)
//           → internalizeAction
//   anchor  identity UTXO → pushdrop(<cell> OP_DROP <leafPk> OP_CHECKSIG)
//           → Atomic BEEF → (on --confirm) ARC broadcast
//
// The pushdrop OWNER is a BRC-42 edge key derived from the identity at a
// fixed index (deriveEdgeSk). Because the identity is recoverable from the
// Plexus dispatch envelope and the index is deterministic, the anchored
// UTXO is recoverable via the SAME recovery scheme as the BEEF-derivation
// demo (recoverySync re-derives the edge context and finds the output).
//
// ── SAFETY ─────────────────────────────────────────────────────────────
//   • DRY-RUN by default: builds + prints the txid + EF hex, does NOT
//     broadcast. Pass `confirm: true` to broadcast for real.
//   • MAX_SPEND_SATS hard cap so a run can't drain the funding wallet.
//   • Signing uses the unlocked wallet identity key (as test-key-rotation
//     does). To route the spend signature strictly through the iframe's
//     BRC-100 createSignature instead, swap `signWithIdentity` below for a
//     dispatcher `createSignature` call — flagged inline.

import * as secp from '@noble/secp256k1';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import { hmac } from '@noble/hashes/hmac';
import { encodeDer } from './der';
import {
  parseBeef,
  buildBeefV1,
  hexFromBytes,
  reverseTxid,
  readVarInt,
} from './beef-codec';
import { buildP2pkhLock, pubkeyToHash160 } from './tx-builder';
import { deriveEdgeSk } from './ecdh42';
import { broadcastToArc } from './arc-broadcast';
import { createAction as metanetCreateAction, METANET_BASE } from './metanet-client';
import {
  loadWallet,
  unlockIdentityFromCache,
  getIdentitySnapshot,
  internalizeAction,
} from './wallet-ops';
import { buildAnchorTx, type Funder } from './mesh-bsv-sink';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

const CELL_SIZE = 1024;
const TYPE_HASH_OFFSET = 30;
/** Flat fee (1-in, 1-pushdrop-out ≈ 1100 bytes @ ~1 sat/byte, rounded up). */
const FEE = 1200n;
/** Hard ceiling per run — protects the funding wallet (don't drain 500k). */
const MAX_SPEND_SATS = 5000n;
/** Deterministic edge index the anchor leaf is derived at (recovery re-derives this). */
const ANCHOR_LEAF_INDEX = 0;

// ── pushdrop locking script: <cell> OP_DROP <ownerPk> OP_CHECKSIG ──────────
function pushdropLock(cell: Uint8Array, ownerPk: Uint8Array): Uint8Array {
  const out: number[] = [0x4d, cell.length & 0xff, (cell.length >> 8) & 0xff]; // PUSHDATA2
  for (const b of cell) out.push(b);
  out.push(0x75); // OP_DROP
  out.push(ownerPk.length);
  for (const b of ownerPk) out.push(b);
  out.push(0xac); // OP_CHECKSIG
  return new Uint8Array(out);
}

/** Build a demo mnca.snapshot cell (typeHash @ 30 + deterministic payload). */
function demoSnapshotCell(): Uint8Array {
  const cell = new Uint8Array(CELL_SIZE);
  const th = nobleSha256(new TextEncoder().encode('mnca.snapshot'));
  cell.set(th, TYPE_HASH_OFFSET);
  for (let i = 256; i < CELL_SIZE; i++) cell[i] = (i * 7) & 0xff;
  return cell;
}

function findOutputVout(rawTx: Uint8Array, lockScript: Uint8Array): { vout: number; value: bigint } | null {
  let off = 4;
  let nIn: number; [nIn, off] = readVarInt(rawTx, off);
  for (let i = 0; i < nIn; i++) {
    off += 36;
    let sl: number; [sl, off] = readVarInt(rawTx, off); off += sl + 4;
  }
  let nOut: number; [nOut, off] = readVarInt(rawTx, off);
  for (let v = 0; v < nOut; v++) {
    const value = new DataView(rawTx.buffer, rawTx.byteOffset + off, 8).getBigUint64(0, true);
    off += 8;
    let sl: number; [sl, off] = readVarInt(rawTx, off);
    const script = rawTx.slice(off, off + sl); off += sl;
    if (script.length === lockScript.length && script.every((b, i) => b === lockScript[i])) {
      return { vout: v, value };
    }
  }
  return null;
}

function arrayEqual(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((x, i) => x === b[i]);
}

export interface AnchorRunOptions {
  /** Snapshot cell to anchor (1024 bytes). Defaults to a demo snapshot. */
  cell?: Uint8Array;
  /** Sats locked into the pushdrop (data carrier — keep small). Default 1. */
  anchorSats?: number;
  /** Set true to BROADCAST for real on mainnet. Default false (dry-run). */
  confirm?: boolean;
  metanetBase?: string;
  arcUrl?: string;
  arcApiKey?: string;
}

export interface AnchorRunResult {
  ok: boolean;
  dryRun: boolean;
  anchorTxid?: string;     // display hex
  leafIndex: number;
  leafPubkeyHex?: string;
  efTxHex?: string;        // for inspection before broadcast
  broadcastTxid?: string;
  summary: string;
}

export async function runMncaAnchor(opts: AnchorRunOptions = {}): Promise<AnchorRunResult> {
  const base = opts.metanetBase ?? METANET_BASE;
  const arcOpts = { arcUrl: opts.arcUrl ?? 'https://arc.taal.com', apiKey: opts.arcApiKey };
  const cell = opts.cell ?? demoSnapshotCell();
  const anchorSats = BigInt(opts.anchorSats ?? 1);
  const dryRun = !opts.confirm;

  if (cell.length !== CELL_SIZE) {
    return { ok: false, dryRun, leafIndex: ANCHOR_LEAF_INDEX, summary: `cell must be ${CELL_SIZE} bytes` };
  }
  const totalSpend = anchorSats + FEE;
  if (totalSpend > MAX_SPEND_SATS) {
    return { ok: false, dryRun, leafIndex: ANCHOR_LEAF_INDEX, summary: `refusing: ${totalSpend} > MAX_SPEND_SATS ${MAX_SPEND_SATS}` };
  }

  // ── Unlock wallet identity (the funder + the leaf's derivation root) ──
  const loadRes = await loadWallet();
  if (!loadRes.ok) return { ok: false, dryRun, leafIndex: ANCHOR_LEAF_INDEX, summary: `wallet not ready: ${loadRes.error.kind}` };
  const unlockRes = await unlockIdentityFromCache();
  if (!unlockRes.ok) return { ok: false, dryRun, leafIndex: ANCHOR_LEAF_INDEX, summary: `identity locked: ${unlockRes.error.kind}` };
  const { identityPk, identitySk } = getIdentitySnapshot();
  const identityLock = buildP2pkhLock(pubkeyToHash160(identityPk));

  // ── Recoverable Tier-0 leaf = BRC-42 edge key at a fixed index ──
  // Recovery: identity is restored from the dispatch envelope; recoverySync
  // re-derives this edge context (so the anchored UTXO is found again).
  const leafSk = deriveEdgeSk(identitySk, identityPk, ANCHOR_LEAF_INDEX);
  if (!leafSk) return { ok: false, dryRun, leafIndex: ANCHOR_LEAF_INDEX, summary: 'deriveEdgeSk failed' };
  const leafPk = secp.getPublicKey(leafSk, true);
  const anchorScript = pushdropLock(cell, leafPk);

  // ── Fund: Metanet Desktop → identity P2PKH (anchorSats + fee) ──
  let fundRaw: Uint8Array, fundBeef: Uint8Array, fundTxid: Uint8Array, fundVout: number, fundValue: bigint;
  try {
    const funded = await metanetCreateAction(
      [{ lockingScript: hexFromBytes(identityLock), satoshis: Number(totalSpend), outputDescription: 'mnca anchor funding' }],
      'Semantos MNCA snapshot anchor — fund identity',
      base,
    );
    fundBeef = funded.beef; fundTxid = funded.txid;
    const parsed = parseBeef(fundBeef);
    const entry = parsed.txs.find(t => arrayEqual(t.txid, fundTxid)) ?? parsed.txs.at(-1)!;
    fundRaw = entry.rawTx;
    const fundOut = findOutputVout(fundRaw, identityLock);
    if (!fundOut) throw new Error('fund tx: identity output not found');
    fundVout = fundOut.vout; fundValue = fundOut.value;
    await internalizeAction({
      tx: fundBeef,
      outputs: [{ outputIndex: fundVout, protocol: 'basket insertion', insertionRemittance: { basket: 'mnca-anchor', tags: ['fund'] }, satoshis: fundValue, lockingScript: identityLock }],
      description: 'mnca anchor: fund',
    });
  } catch (e) {
    return { ok: false, dryRun, leafIndex: ANCHOR_LEAF_INDEX, summary: `Fund FAILED — Metanet Desktop at ${base}: ${(e as Error).message}` };
  }

  // ── Anchor: spend identity UTXO → pushdrop. Sign with the wallet identity. ──
  // NOTE: to route strictly through the iframe BRC-100 createSignature, replace
  // `signWithIdentity` with a dispatcher.createSignature({ data: sighash, ... })
  // call that returns a DER sig. The proven template signs with identitySk.
  const signWithIdentity: Funder = {
    pubkey: identityPk,
    signSighash: (sighash: Uint8Array) => {
      const sig = secp.sign(sighash, identitySk).normalizeS();
      return encodeDer(sig.r, sig.s);
    },
  };

  let anchorTx;
  try {
    anchorTx = buildAnchorTx({
      anchor: { lockingScript: anchorScript, satoshis: anchorSats },
      funding: { txid: fundTxid, vout: fundVout, value: fundValue },
      funder: signWithIdentity,
      feeSats: FEE,
    });
  } catch (e) {
    return { ok: false, dryRun, leafIndex: ANCHOR_LEAF_INDEX, summary: `anchor build FAILED: ${(e as Error).message}` };
  }

  const anchorTxidDisplay = hexFromBytes(reverseTxid(anchorTx.txid));
  const leafPubkeyHex = hexFromBytes(leafPk);

  if (dryRun) {
    return {
      ok: true, dryRun: true,
      anchorTxid: anchorTxidDisplay,
      leafIndex: ANCHOR_LEAF_INDEX,
      leafPubkeyHex,
      efTxHex: hexFromBytes(anchorTx.efTx),
      summary: `DRY-RUN ok — built anchor tx ${anchorTxidDisplay} (anchor ${anchorSats} sats, fee ${FEE}, change ${anchorTx.changeSats}). Re-run with confirm:true to broadcast on mainnet.`,
    };
  }

  // ── Broadcast (real money) ──
  const beefV1 = buildBeefV1(fundBeef, anchorTx.rawTx, anchorTx.txid);
  const bcast = await broadcastToArc(beefV1, arcOpts);
  // NOTE: ARC echoes back the ANCESTOR/funding txid from the BEEF, not the
  // subject. The canonical anchor txid is the one WE computed over the anchor
  // rawTx (anchorTxidDisplay) — that's the tx carrying the cell pushdrop.
  return {
    ok: bcast.ok,
    dryRun: false,
    anchorTxid: anchorTxidDisplay,
    leafIndex: ANCHOR_LEAF_INDEX,
    leafPubkeyHex,
    broadcastTxid: bcast.ok ? bcast.txid : undefined, // ARC ack (funding/ancestor tx)
    summary: bcast.ok
      ? `✓ ANCHORED on mainnet — anchor txid ${anchorTxidDisplay} (snapshot owned by edge[${ANCHOR_LEAF_INDEX}], recoverable via dispatch envelope). ARC ack (funding tx): ${bcast.txid}`
      : `broadcast FAILED: ${bcast.reason}`,
  };
}

// NOTE: this runs in the BROWSER (wallet.html), not headless Bun — loadWallet
// reads the enrolled identity from IndexedDB and Metanet Desktop is reached
// over :3321 from the page. It's invoked from the "MNCA snapshot anchor" panel
// in wallet-page.ts (dry-run button, then an explicit confirm button), exactly
// like the key-rotation / chess-stake demos. There is no headless CLI entry.

```
