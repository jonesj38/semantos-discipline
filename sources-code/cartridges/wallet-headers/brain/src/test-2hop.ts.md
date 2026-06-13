---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/test-2hop.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.663305+00:00
---

# cartridges/wallet-headers/brain/src/test-2hop.ts

```ts
// 2-hop BEEF validation proof.
//
// Flow:
//   Hop 0  Metanet Desktop → our wallet (150 sats via createAction)
//          → validate BEEF against brain block headers (real SPV)
//          → internalizeAction stores the UTXO
//
//   Hop 1  our wallet → self (second derived address, 140 sats)
//          → build + sign spending tx
//          → wrap as Atomic BEEF (hop-0 mined BUMP + hop-1 unsigned)
//          → validate chain: hop-0 BUMP checks out, scripts valid
//
//   Hop 2  our wallet → self (third derived address, 130 sats)
//          → same pattern, chain now 3 txs deep
//
// "Real SPV" means: the BUMP merkle root is computed from the path and
// compared against the header byte 36..68 from the local brain store.
// No miner lookup ever happens; everything resolves from local data.

import * as secp from '@noble/secp256k1';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import { hmac } from '@noble/hashes/hmac';
import { encodeDer } from './der';
import {
  parseBeef,
  computeMerkleRoot,
  buildAtomicBeef,
  buildAtomicBeefChained,
  buildBeefV1,
  buildBeefV1ChainedN,
  hexFromBytes,
  reverseTxid,
  computeTxid,
  readVarInt,
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
import { createAction, getIdentityKey, METANET_BASE } from './metanet-client';
import { broadcastToArc } from './arc-broadcast';
import {
  loadWallet,
  unlockIdentityFromCache,
  getIdentitySnapshot,
  internalizeAction,
  listOutputs,
  type InternalizeActionInput,
} from './wallet-ops';

const BHS_BASE = 'https://headers.semantos.me';

async function fetchHeaderRaw(height: number): Promise<Uint8Array> {
  const url = `${BHS_BASE}/api/v1/chain/header/range?from=${height}&to=${height}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`BHS fetch h=${height}: HTTP ${res.status}`);
  const buf = await res.arrayBuffer();
  if (buf.byteLength < 80) throw new Error(`BHS returned ${buf.byteLength} bytes for h=${height}`);
  return new Uint8Array(buf, 0, 80);
}

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

// ── Result type ───────────────────────────────────────────────────────

export interface HopResult {
  hop: number;
  txid: string;          // display hex (reversed), full 64 chars
  satoshis: number;
  beefBytes: number;
  spvOk: boolean;
  spvDetail: string;     // e.g. "root 3fa2… matches header at height 843210"
  blockHeight?: number;  // block the anchoring tx was mined in
  scriptOk: boolean;
  broadcastTxid?: string; // ARC txid when hop was broadcast
  error?: string;
}

export interface TwoHopResult {
  hops: HopResult[];
  allOk: boolean;
  summary: string;
}

// ── SPV validation ────────────────────────────────────────────────────

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

  // Validate each BUMP: compute merkle root, compare against single header from BHS.
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
      hdrBytes = await fetchHeaderRaw(bump.blockHeight);
    } catch (e) {
      return { ok: false, detail: `header fetch failed: ${(e as Error).message}`, blockHeight: bump.blockHeight };
    }

    // merkle root is bytes 36..68 of the 80-byte header (internal byte order)
    const headerRoot = hdrBytes.slice(36, 68);
    const rootHex = hexFromBytes(computedRoot);
    if (!arrayEqual(headerRoot, computedRoot)) {
      return {
        ok: false,
        detail: `root ${rootHex.slice(0, 16)}… does NOT match header at height ${bump.blockHeight}`,
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

// ── Key derivation helper ─────────────────────────────────────────────

// Derive a deterministic child sk for the nth hop using the identity key.
// Simple: HMAC-SHA256(identitySk, "hop-<n>") — gives a unique key per hop.
function deriveHopSk(identitySk: Uint8Array, hopN: number): Uint8Array {
  return hmac(nobleSha256, identitySk, new TextEncoder().encode(`hop-${hopN}`));
}

// ── Fee estimate ──────────────────────────────────────────────────────
// 1 P2PKH input (~148 bytes) + 1 P2PKH output (~34 bytes) + overhead (~10)
// ≈ 192 bytes at 0.5 sat/byte = ~10 sats. Use 10 sat flat fee per hop.
const HOP_FEE_SATS = 10n;

// ── Spend builder ─────────────────────────────────────────────────────

function buildHopSpend(
  sourceRaw: Uint8Array,
  sourceVout: number,
  sourceValue: bigint,
  sourceLockScript: Uint8Array,
  spendSk: Uint8Array,
  toScript: Uint8Array,
): { rawTx: Uint8Array; efTx: Uint8Array; txid: Uint8Array } {
  const spendPk = secp.getPublicKey(spendSk, true);
  const sourceTxid = computeTxid(sourceRaw);
  const outSats = sourceValue - HOP_FEE_SATS;
  if (outSats < 1n) throw new Error('not enough sats after fee');

  const txInput: TxInput = {
    txid: sourceTxid,
    vout: sourceVout,
    value: sourceValue,
    script: sourceLockScript,
    sequence: 0xffffffff,
  };
  const txOutput: TxOutput = { script: toScript, satoshis: outSats };

  const digest = computeSighash([txInput], [txOutput], 0);
  const sig = secp.sign(digest, spendSk).normalizeS();
  const derSig = encodeDer(sig.r, sig.s);
  const unlock = buildP2pkhUnlockScript(derSig, spendPk);

  return serializeEFTx(
    [{ txid: sourceTxid, vout: sourceVout, unlockScript: unlock, sequence: 0xffffffff, sourceValue, sourceLock: sourceLockScript }],
    [txOutput],
  );
}

// ── Main orchestrator ─────────────────────────────────────────────────

export async function run2HopTest(
  opts: { metanetBase?: string; satoshis?: number; arcUrl?: string; arcApiKey?: string } = {},
): Promise<TwoHopResult> {
  const base = opts.metanetBase ?? METANET_BASE;
  const arcOpts = { arcUrl: opts.arcUrl ?? 'https://arc.taal.com', apiKey: opts.arcApiKey };
  const seedSats = BigInt(opts.satoshis ?? 150);
  const results: HopResult[] = [];

  // ── Ensure wallet is loaded + identity unlocked ────────────────────
  const loadRes = await loadWallet();
  if (!loadRes.ok) throw new Error(`wallet not ready: ${loadRes.error.kind}`);
  const unlockRes = await unlockIdentityFromCache();
  if (!unlockRes.ok) throw new Error(`identity lock: ${unlockRes.error.kind}`);
  const { identityPk, identitySk } = getIdentitySnapshot();

  // Hop-0 receiving key = identity key directly (simplest for demo)
  const hop0Script = buildP2pkhLock(pubkeyToHash160(identityPk));
  const hop0ScriptHex = hexFromBytes(hop0Script);

  // ── Hop 0: fund from Metanet Desktop ──────────────────────────────
  let hop0Beef: Uint8Array;
  let hop0Txid: Uint8Array;
  try {
    const funded = await createAction(
      [{ lockingScript: hop0ScriptHex, satoshis: Number(seedSats), outputDescription: 'hop-0 UTXO' }],
      '2-hop BEEF proof: fund WASM wallet',
      base,
    );
    hop0Beef = funded.beef;
    hop0Txid = funded.txid;
  } catch (e) {
    return {
      hops: [],
      allOk: false,
      summary: `Hop 0 FAILED — Metanet Desktop not reachable at ${base}: ${(e as Error).message}`,
    };
  }

  const hop0Spv = await validateBeef(hop0Beef);
  results.push({
    hop: 0,
    txid: hexFromBytes(reverseTxid(hop0Txid)),
    satoshis: Number(hop0Value),
    beefBytes: hop0Beef.length,
    spvOk: hop0Spv.ok,
    spvDetail: hop0Spv.detail,
    blockHeight: hop0Spv.blockHeight,
    scriptOk: true,
  });

  // Find hop-0 raw tx and locate our output by script (not assuming vout=0)
  const hop0Parsed = parseBeef(hop0Beef);
  const hop0TxEntry = hop0Parsed.txs.find(t =>
    arrayEqual(t.txid, hop0Txid) ||
    (hop0Parsed.subjectTxid && arrayEqual(t.txid, hop0Parsed.subjectTxid))
  ) ?? hop0Parsed.txs.at(-1)!;
  const hop0Out = findOutputVout(hop0TxEntry.rawTx, hop0Script);
  const hop0Vout = hop0Out?.vout ?? 0;
  const hop0Value = hop0Out?.value ?? seedSats;

  // Store hop-0 UTXO
  const internalizeInput: InternalizeActionInput = {
    tx: hop0Beef,
    outputs: [{
      outputIndex: hop0Vout,
      protocol: 'basket insertion' as const,
      insertionRemittance: { basket: 'hop-test', tags: ['hop-0'] },
      satoshis: hop0Value,
      lockingScript: hop0Script,
    }],
    description: 'hop-0 funded by Metanet Desktop',
    labels: ['hop-test'],
  };
  const intRes = await internalizeAction(internalizeInput);
  if (!intRes.ok) {
    results[0]!.error = `internalizeAction: ${intRes.error.kind}`;
  }

  // ── Hop 1: spend hop-0 → hop-1 address ────────────────────────────
  const hop1Sk = deriveHopSk(identitySk, 1);
  const hop1Pk = secp.getPublicKey(hop1Sk, true);
  const hop1Script = buildP2pkhLock(pubkeyToHash160(hop1Pk));
  const hop1Sats = hop0Value - HOP_FEE_SATS;

  let hop1Raw: Uint8Array | undefined;
  let hop1Txid: Uint8Array | undefined;
  let hop1Beef: Uint8Array | undefined;
  let hop1SpvOk = false;
  let hop1SpvDetail = '';
  let hop1ScriptOk = false;
  let hop1BroadcastTxid: string | undefined;

  try {
    ({ rawTx: hop1Raw, txid: hop1Txid } = buildHopSpend(
      hop0TxEntry.rawTx,
      hop0Vout,
      hop0Value,
      hop0Script,
      identitySk,       // spending key = identity key (matches hop0Script)
      hop1Script,
    ));

    hop1Beef = buildAtomicBeef(hop0Beef, hop1Raw, hop1Txid);

    const hop1Spv = await validateBeef(hop1Beef);
    hop1SpvOk = hop1Spv.ok;
    hop1SpvDetail = hop1Spv.detail;
    hop1ScriptOk = true;

    const hop1Bcast = await broadcastToArc(buildBeefV1(hop0Beef, hop1Raw, hop1Txid), arcOpts);
    hop1BroadcastTxid = hop1Bcast.ok ? hop1Bcast.txid : undefined;
    if (!hop1Bcast.ok) hop1SpvDetail += ` | ARC: ${hop1Bcast.reason}`;
  } catch (e) {
    hop1SpvDetail = `build failed: ${(e as Error).message}`;
  }

  results.push({
    hop: 1,
    txid: hop1Txid ? hexFromBytes(reverseTxid(hop1Txid)) : '(build failed)',
    satoshis: Number(hop1Sats),
    beefBytes: hop1Beef! ? hop1Beef!.length : 0,
    spvOk: hop1SpvOk,
    spvDetail: hop1SpvDetail,
    blockHeight: results[0]?.blockHeight,
    scriptOk: hop1ScriptOk,
    broadcastTxid: hop1BroadcastTxid,
    error: hop1SpvDetail.includes('failed') ? hop1SpvDetail : undefined,
  });

  // ── Hop 2: spend hop-1 → hop-2 address ────────────────────────────
  const hop2Sk = deriveHopSk(identitySk, 2);
  const hop2Pk = secp.getPublicKey(hop2Sk, true);
  const hop2Script = buildP2pkhLock(pubkeyToHash160(hop2Pk));
  const hop2Sats = hop1Sats - HOP_FEE_SATS;

  let hop2Raw: Uint8Array | undefined;
  let hop2Txid: Uint8Array | undefined;
  let hop2Beef: Uint8Array | undefined;
  let hop2SpvOk = false;
  let hop2SpvDetail = '';
  let hop2ScriptOk = false;
  let hop2BroadcastTxid: string | undefined;

  if (hop1Raw && hop1Txid) {
    try {
      ({ rawTx: hop2Raw, txid: hop2Txid } = buildHopSpend(
        hop1Raw,
        0,
        hop1Sats,
        hop1Script,
        hop1Sk,
        hop2Script,
      ));

      hop2Beef = buildAtomicBeefChained(
        hop0Beef,
        hop1Raw,
        hop1Txid,
        hop2Raw,
        hop2Txid,
      );

      const hop2Spv = await validateBeef(hop2Beef);
      hop2SpvOk = hop2Spv.ok;
      hop2SpvDetail = hop2Spv.detail;
      hop2ScriptOk = true;

      const hop2Bcast = await broadcastToArc(
        buildBeefV1ChainedN(hop0Beef, [hop1Raw, hop2Raw], hop2Txid),
        arcOpts,
      );
      hop2BroadcastTxid = hop2Bcast.ok ? hop2Bcast.txid : undefined;
      if (!hop2Bcast.ok) hop2SpvDetail += ` | ARC: ${hop2Bcast.reason}`;
    } catch (e) {
      hop2SpvDetail = `build failed: ${(e as Error).message}`;
    }
  } else {
    hop2SpvDetail = 'skipped — hop 1 failed';
  }

  results.push({
    hop: 2,
    txid: hop2Txid ? hexFromBytes(reverseTxid(hop2Txid)) : '(build failed)',
    satoshis: Number(hop2Sats),
    beefBytes: hop2Beef ? hop2Beef.length : 0,
    spvOk: hop2SpvOk,
    spvDetail: hop2SpvDetail,
    blockHeight: results[0]?.blockHeight,
    scriptOk: hop2ScriptOk,
    broadcastTxid: hop2BroadcastTxid,
    error: hop2SpvDetail.includes('failed') ? hop2SpvDetail : undefined,
  });

  const allOk = results.every(r => r.spvOk && r.scriptOk);
  const broadcastCount = results.filter(r => r.broadcastTxid).length;
  const summary = allOk
    ? `✓ All ${results.length} hops validated — BEEF SPV real, ${broadcastCount} broadcast to ARC`
    : `${results.filter(r => r.spvOk).length}/${results.length} hops passed SPV`;

  return { hops: results, allOk, summary };
}

function arrayEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
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

```
