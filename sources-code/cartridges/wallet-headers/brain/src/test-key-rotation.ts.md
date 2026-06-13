---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/test-key-rotation.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.648468+00:00
---

# cartridges/wallet-headers/brain/src/test-key-rotation.ts

```ts
// test-key-rotation.ts — End-to-end BRC-42 edge key rotation with real BSV.
//
// Flow (each step validates BEEF chain, then broadcasts to ARC):
//
//   fund    Metanet Desktop → identity key P2PKH    (seedSats)
//           → validate BEEF+SPV → internalizeAction
//
//   rot-0   identity → BRC-42 edge[0]               (seedSats - fee)
//           → validate Atomic BEEF → broadcast → ARC txid
//
//   rot-1   edge[0]  → BRC-42 edge[1]               (prev - fee)
//           → validate chained BEEF → broadcast → ARC txid
//
//   return  edge[1]  → identity key                 (prev - fee)
//           → validate chained BEEF → broadcast → ARC txid
//
// Proves: key derivation, script construction, BEEF ancestry, and ARC
// acceptance all work correctly across a 3-rotation chain.

import * as secp from '@noble/secp256k1';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import { hmac } from '@noble/hashes/hmac';
import { encodeDer } from './der';
import {
  parseBeef,
  computeMerkleRoot,
  buildAtomicBeef,
  buildAtomicBeefChainedN,
  buildBeefV1,
  buildBeefV1ChainedN,
  hexFromBytes,
  reverseTxid,
  computeTxid,
  readVarInt,
  concat,
} from './beef-codec';
import {
  computeSighash,
  serializeEFTx,
  buildP2pkhUnlockScript,
  buildP2pkhLock,
  pubkeyToHash160,
  type TxInput,
  type TxOutput,
} from './tx-builder';
import { buildRotatedLock, deriveEdgeSk } from './ecdh42';
import { broadcastToArc } from './arc-broadcast';
import { createAction as metanetCreateAction, METANET_BASE } from './metanet-client';
import {
  loadWallet,
  unlockIdentityFromCache,
  getIdentitySnapshot,
  internalizeAction,
} from './wallet-ops';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

// ── Types ─────────────────────────────────────────────────────────────

export interface RotationHop {
  label: string;
  txid: string;           // display hex (reversed)
  satsIn: number;
  satsOut: number;
  beefBytes: number;
  spvOk: boolean;
  spvDetail: string;
  blockHeight?: number;
  broadcastOk: boolean;
  broadcastTxid?: string;
  error?: string;
}

export interface KeyRotationResult {
  hops: RotationHop[];
  allOk: boolean;
  summary: string;
}

// ── Constants ─────────────────────────────────────────────────────────

// 1-input 1-output P2PKH: 148 + 34 + 10 = 192 bytes @ 1 sat/byte
const FEE = 192n;

const BHS_BASE = 'https://headers.semantos.me';

// ── SPV validation ─────────────────────────────────────────────────────

async function validateBeef(
  beef: Uint8Array,
): Promise<{ ok: boolean; detail: string; blockHeight?: number }> {
  let parsed;
  try {
    parsed = parseBeef(beef);
  } catch (e) {
    return { ok: false, detail: `parse failed: ${(e as Error).message}` };
  }

  if (parsed.bumps.length === 0) {
    return { ok: false, detail: 'no BUMPs — unconfirmed chain root, cannot SPV-verify yet' };
  }

  for (const tx of parsed.txs) {
    if (tx.bumpIndex === null) continue;
    const bump = parsed.bumps[tx.bumpIndex]!;
    let computedRoot: Uint8Array;
    try {
      computedRoot = computeMerkleRoot(bump, tx.txid);
    } catch (e) {
      return { ok: false, detail: `BUMP path error: ${(e as Error).message}` };
    }

    let hdrBytes: Uint8Array;
    try {
      const url = `${BHS_BASE}/api/v1/chain/header/range?from=${bump.blockHeight}&to=${bump.blockHeight}`;
      const res = await fetch(url);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const buf = await res.arrayBuffer();
      hdrBytes = new Uint8Array(buf, 0, 80);
    } catch (e) {
      return { ok: false, detail: `header fetch failed: ${(e as Error).message}`, blockHeight: bump.blockHeight };
    }

    const headerRoot = hdrBytes.slice(36, 68);
    const rootHex = hexFromBytes(computedRoot);
    if (!arrayEqual(headerRoot, computedRoot)) {
      return {
        ok: false,
        detail: `root ${rootHex.slice(0, 16)}… does NOT match header at h=${bump.blockHeight}`,
        blockHeight: bump.blockHeight,
      };
    }
    return {
      ok: true,
      detail: `root ${rootHex.slice(0, 16)}… ✓ matches header at h=${bump.blockHeight}`,
      blockHeight: bump.blockHeight,
    };
  }

  return { ok: false, detail: 'no mined transactions found in BEEF' };
}

// ── Spend builder ─────────────────────────────────────────────────────

function buildSpend(
  sourceRaw: Uint8Array,
  sourceVout: number,
  sourceValue: bigint,
  sourceLock: Uint8Array,
  spendSk: Uint8Array,
  toScript: Uint8Array,
): { rawTx: Uint8Array; efTx: Uint8Array; txid: Uint8Array } {
  const spendPk = secp.getPublicKey(spendSk, true);
  const sourceTxid = computeTxid(sourceRaw);
  const outSats = sourceValue - FEE;
  if (outSats < 546n) throw new Error(`dust after fee: ${outSats} sats`);

  const input: TxInput = {
    txid: sourceTxid,
    vout: sourceVout,
    value: sourceValue,
    script: sourceLock,
    sequence: 0xffffffff,
  };
  const output: TxOutput = { script: toScript, satoshis: outSats };

  const digest = computeSighash([input], [output], 0);
  const sig = secp.sign(digest, spendSk).normalizeS();
  const derSig = encodeDer(sig.r, sig.s);
  const unlock = buildP2pkhUnlockScript(derSig, spendPk);

  return serializeEFTx(
    [{ txid: sourceTxid, vout: sourceVout, unlockScript: unlock, sequence: 0xffffffff, sourceValue, sourceLock }],
    [output],
  );
}

// ── Helpers ───────────────────────────────────────────────────────────

function arrayEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

/** Scan a raw tx's outputs and return the first vout whose locking script matches. */
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

function displayTxid(txid: Uint8Array): string {
  return hexFromBytes(reverseTxid(txid));
}

// ── Main ──────────────────────────────────────────────────────────────

export async function runKeyRotationTest(
  opts: { metanetBase?: string; satoshis?: number; arcUrl?: string; arcApiKey?: string } = {},
): Promise<KeyRotationResult> {
  const base = opts.metanetBase ?? METANET_BASE;
  const arcOpts = { arcUrl: opts.arcUrl ?? 'https://arc.taal.com', apiKey: opts.arcApiKey };
  const seedSats = BigInt(opts.satoshis ?? 10_000);

  const loadRes = await loadWallet();
  if (!loadRes.ok) throw new Error(`wallet not ready: ${loadRes.error.kind}`);
  const unlockRes = await unlockIdentityFromCache();
  if (!unlockRes.ok) throw new Error(`identity locked: ${unlockRes.error.kind}`);
  const { identityPk, identitySk } = getIdentitySnapshot();

  const identityLock = buildP2pkhLock(pubkeyToHash160(identityPk));
  const hops: RotationHop[] = [];

  // ── Fund: Metanet Desktop → identity key ──────────────────────────────
  let fundRaw: Uint8Array;
  let fundTxid: Uint8Array;
  let fundBeef: Uint8Array;
  let fundVout = 0;
  let fundValue = seedSats;

  try {
    const funded = await metanetCreateAction(
      [{
        lockingScript: hexFromBytes(identityLock),
        satoshis: Number(seedSats),
        outputDescription: 'key-rotation seed',
      }],
      'Semantos key rotation test — fund identity key',
      base,
    );
    fundBeef = funded.beef;
    fundTxid = funded.txid;

    const parsed = parseBeef(fundBeef);
    const entry = parsed.txs.find(t => arrayEqual(t.txid, fundTxid)) ?? parsed.txs.at(-1)!;
    fundRaw = entry.rawTx;

    const fundOut = findOutputVout(fundRaw, identityLock);
    if (!fundOut) throw new Error('fund tx: output with identityLock not found');
    fundVout = fundOut.vout;
    fundValue = fundOut.value;

    const spv = await validateBeef(fundBeef);

    await internalizeAction({
      tx: fundBeef,
      outputs: [{
        outputIndex: fundVout,
        protocol: 'basket insertion',
        insertionRemittance: { basket: 'rotation-test', tags: ['fund'] },
        satoshis: fundValue,
        lockingScript: identityLock,
      }],
      description: 'key rotation test: fund',
    });

    hops.push({
      label: 'fund: metanet → identity',
      txid: displayTxid(fundTxid),
      satsIn: 0,
      satsOut: Number(fundValue),
      beefBytes: fundBeef.length,
      spvOk: spv.ok,
      spvDetail: spv.detail,
      blockHeight: spv.blockHeight,
      broadcastOk: true,
      broadcastTxid: displayTxid(fundTxid),
    });
  } catch (e) {
    return {
      hops,
      allOk: false,
      summary: `Fund FAILED — Metanet Desktop at ${base}: ${(e as Error).message}`,
    };
  }

  // ── rot-0: identity key → BRC-42 edge[0] ──────────────────────────────
  const edgeLock0 = buildRotatedLock(identityPk, identitySk, 0);
  if (!edgeLock0) return { hops, allOk: false, summary: 'buildRotatedLock(index=0) failed' };

  const rot0Sats = fundValue - FEE;
  let rot0Raw: Uint8Array;
  let rot0Txid: Uint8Array;

  try {
    ({ rawTx: rot0Raw, txid: rot0Txid } = buildSpend(
      fundRaw, fundVout, fundValue, identityLock, identitySk, edgeLock0,
    ));
    const rot0Beef = buildAtomicBeef(fundBeef, rot0Raw, rot0Txid);
    const spv = await validateBeef(rot0Beef);
    const bcast = await broadcastToArc(buildBeefV1(fundBeef, rot0Raw, rot0Txid), arcOpts);

    hops.push({
      label: 'rot-0: identity → edge[0]',
      txid: displayTxid(rot0Txid),
      satsIn: Number(fundValue),
      satsOut: Number(rot0Sats),
      beefBytes: rot0Beef.length,
      spvOk: spv.ok,
      spvDetail: spv.detail,
      blockHeight: spv.blockHeight,
      broadcastOk: bcast.ok,
      broadcastTxid: bcast.ok ? bcast.txid : undefined,
      error: bcast.ok ? undefined : `broadcast: ${bcast.reason}`,
    });

    if (!bcast.ok) return { hops, allOk: false, summary: `rot-0 broadcast failed: ${bcast.reason}` };
  } catch (e) {
    hops.push({
      label: 'rot-0: identity → edge[0]',
      txid: '', satsIn: Number(seedSats), satsOut: 0,
      beefBytes: 0, spvOk: false, spvDetail: '', broadcastOk: false,
      error: (e as Error).message,
    });
    return { hops, allOk: false, summary: `rot-0 FAILED: ${(e as Error).message}` };
  }

  // ── rot-1: edge[0] → BRC-42 edge[1] ───────────────────────────────────
  const edgeSk0 = deriveEdgeSk(identitySk, identityPk, 0);
  if (!edgeSk0) return { hops, allOk: false, summary: 'deriveEdgeSk(index=0) failed' };

  const edgeLock1 = buildRotatedLock(identityPk, identitySk, 1);
  if (!edgeLock1) return { hops, allOk: false, summary: 'buildRotatedLock(index=1) failed' };

  const rot1Sats = rot0Sats - FEE;
  let rot1Raw: Uint8Array;
  let rot1Txid: Uint8Array;

  try {
    ({ rawTx: rot1Raw, txid: rot1Txid } = buildSpend(
      rot0Raw, 0, rot0Sats, edgeLock0, edgeSk0, edgeLock1,
    ));
    const rot1Beef = buildAtomicBeefChainedN(fundBeef, [rot0Raw, rot1Raw], rot1Txid);
    const spv = await validateBeef(rot1Beef);
    const bcast = await broadcastToArc(buildBeefV1ChainedN(fundBeef, [rot0Raw, rot1Raw], rot1Txid), arcOpts);

    hops.push({
      label: 'rot-1: edge[0] → edge[1]',
      txid: displayTxid(rot1Txid),
      satsIn: Number(rot0Sats),
      satsOut: Number(rot1Sats),
      beefBytes: rot1Beef.length,
      spvOk: spv.ok,
      spvDetail: spv.detail,
      blockHeight: spv.blockHeight,
      broadcastOk: bcast.ok,
      broadcastTxid: bcast.ok ? bcast.txid : undefined,
      error: bcast.ok ? undefined : `broadcast: ${bcast.reason}`,
    });

    if (!bcast.ok) return { hops, allOk: false, summary: `rot-1 broadcast failed: ${bcast.reason}` };
  } catch (e) {
    hops.push({
      label: 'rot-1: edge[0] → edge[1]',
      txid: '', satsIn: Number(rot0Sats), satsOut: 0,
      beefBytes: 0, spvOk: false, spvDetail: '', broadcastOk: false,
      error: (e as Error).message,
    });
    return { hops, allOk: false, summary: `rot-1 FAILED: ${(e as Error).message}` };
  }

  // ── return: edge[1] → identity key ────────────────────────────────────
  const edgeSk1 = deriveEdgeSk(identitySk, identityPk, 1);
  if (!edgeSk1) return { hops, allOk: false, summary: 'deriveEdgeSk(index=1) failed' };

  const returnSats = rot1Sats - FEE;

  try {
    const { rawTx: retRaw, txid: retTxid } = buildSpend(
      rot1Raw, 0, rot1Sats, edgeLock1, edgeSk1, identityLock,
    );
    const retBeef = buildAtomicBeefChainedN(
      fundBeef, [rot0Raw, rot1Raw, retRaw], retTxid,
    );
    const spv = await validateBeef(retBeef);
    const bcast = await broadcastToArc(buildBeefV1ChainedN(fundBeef, [rot0Raw, rot1Raw, retRaw], retTxid), arcOpts);

    hops.push({
      label: 'return: edge[1] → identity',
      txid: displayTxid(retTxid),
      satsIn: Number(rot1Sats),
      satsOut: Number(returnSats),
      beefBytes: retBeef.length,
      spvOk: spv.ok,
      spvDetail: spv.detail,
      blockHeight: spv.blockHeight,
      broadcastOk: bcast.ok,
      broadcastTxid: bcast.ok ? bcast.txid : undefined,
      error: bcast.ok ? undefined : `broadcast: ${bcast.reason}`,
    });
  } catch (e) {
    hops.push({
      label: 'return: edge[1] → identity',
      txid: '', satsIn: Number(rot1Sats), satsOut: 0,
      beefBytes: 0, spvOk: false, spvDetail: '', broadcastOk: false,
      error: (e as Error).message,
    });
    return { hops, allOk: false, summary: `return FAILED: ${(e as Error).message}` };
  }

  const allOk = hops.every(h => h.spvOk && h.broadcastOk);
  const summary = allOk
    ? `✓ All ${hops.length} hops completed — key rotation verified end-to-end`
    : `${hops.filter(h => h.broadcastOk).length}/${hops.length} hops broadcast successfully`;

  return { hops, allOk, summary };
}

```
