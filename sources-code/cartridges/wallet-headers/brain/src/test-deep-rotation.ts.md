---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/test-deep-rotation.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.654296+00:00
---

# cartridges/wallet-headers/brain/src/test-deep-rotation.ts

```ts
// test-deep-rotation.ts — Deep BRC-42 edge rotation + session-recovery test.
//
// Phase 1 — deep rotation:
//   fund     Metanet Desktop → identity key
//   hop 0    identity → edge[0]
//   hop 1    edge[0]  → edge[1]
//   …
//   hop N-1  edge[N-2] → edge[N-1]
//   Each hop: chained BEEF → SPV → ARC broadcast.
//
// Phase 2 — session recovery:
//   Wipe only the runtime (simulates tab reload / browser restart).
//   Reload wallet from IndexedDB + unlock from boot cache.
//   Verify the reloaded identityPk matches.
//   Derive edge[N-1] sk from the reloaded identity.
//   Spend edge[N-1] → identity and broadcast to ARC.
//   Proves: key derivation is deterministic; IDB persistence works;
//   rotated funds are always spendable after a session restart.
//
// Phase 3 — envelope recovery (offline, no spend):
//   Call decryptRecoverySeed(envelope, answers) → re-derive identity.
//   Compare identityPk bytes: proves a brand-new device could recover
//   the same key from the backup envelope without any live ARC activity.

import * as secp from '@noble/secp256k1';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import { hmac } from '@noble/hashes/hmac';
import { encodeDer } from './der';
import {
  parseBeef,
  computeMerkleRoot,
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
import {
  buildCellAnchorLock,
  deriveCellAnchorSk,
  anchorProtocolHash,
  buildSchemaMapping,
  type SchemaMapping,
} from './cell-anchor';
import { outputStore } from './output-store';
import { broadcastToArc } from './arc-broadcast';
import { createAction as metanetCreateAction, METANET_BASE } from './metanet-client';
import {
  loadWallet,
  unlockIdentityFromCache,
  getIdentitySnapshot,
  internalizeAction,
  getCachedRecoveryEnvelope,
  _resetRuntimeForTests,
} from './wallet-ops';
import { decryptRecoverySeed } from './plexus/envelope';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

// ── Types ─────────────────────────────────────────────────────────────

export interface DeepHop {
  label: string;
  txid: string;
  edgeIndex: number | null; // null = fund or return
  satsOut: number;
  spvOk: boolean;
  spvDetail: string;
  broadcastOk: boolean;
  broadcastTxid?: string;
  error?: string;
}

export interface DeepRotationResult {
  hops: DeepHop[];
  depth: number;
  sessionRecoveryOk: boolean;
  sessionRecoveryDetail: string;
  sessionReturnHop?: DeepHop;
  envelopeRecoveryOk: boolean;
  envelopeRecoveryDetail: string;
  /** Phase 4: cell anchor UTXO — creation and recovery spend. */
  anchorCreatedTxid?: string;
  anchorRecoveryOk: boolean;
  anchorRecoveryDetail: string;
  anchorReturnHop?: DeepHop;
  /** Schema mappings that would be exported to Plexus schemaMappings field. */
  schemaMappings: SchemaMapping[];
  allOk: boolean;
  summary: string;
}

// ── Constants ──────────────────────────────────────────────────────────

const FEE = 192n;
const BHS_BASE = 'https://headers.semantos.me';

// ── SPV ────────────────────────────────────────────────────────────────

async function validateBeef(
  beef: Uint8Array,
): Promise<{ ok: boolean; detail: string }> {
  let parsed;
  try {
    parsed = parseBeef(beef);
  } catch (e) {
    return { ok: false, detail: `parse failed: ${(e as Error).message}` };
  }
  if (parsed.bumps.length === 0) {
    return { ok: false, detail: 'no BUMPs — unconfirmed root' };
  }
  for (const tx of parsed.txs) {
    if (tx.bumpIndex === null) continue;
    const bump = parsed.bumps[tx.bumpIndex]!;
    let computedRoot: Uint8Array;
    try {
      computedRoot = computeMerkleRoot(bump, tx.txid);
    } catch (e) {
      return { ok: false, detail: `BUMP error: ${(e as Error).message}` };
    }
    let hdrBytes: Uint8Array;
    try {
      const url = `${BHS_BASE}/api/v1/chain/header/range?from=${bump.blockHeight}&to=${bump.blockHeight}`;
      const res = await fetch(url);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      hdrBytes = new Uint8Array(await res.arrayBuffer(), 0, 80);
    } catch (e) {
      return { ok: false, detail: `header fetch failed: ${(e as Error).message}` };
    }
    if (!arrayEqual(hdrBytes.slice(36, 68), computedRoot)) {
      return { ok: false, detail: `root ${hexFromBytes(computedRoot).slice(0, 16)}… does NOT match header at h=${bump.blockHeight}` };
    }
    return { ok: true, detail: `root ${hexFromBytes(computedRoot).slice(0, 16)}… ✓ matches header at h=${bump.blockHeight}` };
  }
  return { ok: false, detail: 'no mined txs in BEEF' };
}

// ── Helpers ────────────────────────────────────────────────────────────

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

function buildSpend(
  sourceRaw: Uint8Array,
  sourceVout: number,
  sourceValue: bigint,
  sourceLock: Uint8Array,
  spendSk: Uint8Array,
  toScript: Uint8Array,
): { rawTx: Uint8Array; txid: Uint8Array } {
  const spendPk = secp.getPublicKey(spendSk, true);
  const sourceTxid = computeTxid(sourceRaw);
  const outSats = sourceValue - FEE;
  if (outSats < 546n) throw new Error(`dust after fee: ${outSats} sats`);

  const input: TxInput = { txid: sourceTxid, vout: sourceVout, value: sourceValue, script: sourceLock, sequence: 0xffffffff };
  const output: TxOutput = { script: toScript, satoshis: outSats };

  const digest = computeSighash([input], [output], 0);
  const sig = secp.sign(digest, spendSk).normalizeS();
  const derSig = encodeDer(sig.r, sig.s);
  const unlock = buildP2pkhUnlockScript(derSig, spendPk);

  const { rawTx, txid } = serializeEFTx(
    [{ txid: sourceTxid, vout: sourceVout, unlockScript: unlock, sequence: 0xffffffff, sourceValue, sourceLock }],
    [output],
  );
  return { rawTx, txid };
}

function displayTxid(txid: Uint8Array): string {
  return hexFromBytes(reverseTxid(txid));
}

/** Build a 2-output spend:
 *  output 0 → toScript0 (remaining sats after fee and anchor allocation)
 *  output 1 → toScript1 (anchorSats) */
function buildSpend2(
  sourceRaw: Uint8Array,
  sourceVout: number,
  sourceValue: bigint,
  sourceLock: Uint8Array,
  spendSk: Uint8Array,
  toScript0: Uint8Array,
  toScript1: Uint8Array,
  anchorSats: bigint,
): { rawTx: Uint8Array; txid: Uint8Array } {
  const spendPk = secp.getPublicKey(spendSk, true);
  const sourceTxid = computeTxid(sourceRaw);
  const out0Sats = sourceValue - FEE - anchorSats;
  if (out0Sats < 546n) throw new Error(`dust after fee+anchor: ${out0Sats} sats`);

  const input: TxInput = { txid: sourceTxid, vout: sourceVout, value: sourceValue, script: sourceLock, sequence: 0xffffffff };
  const outputs: TxOutput[] = [
    { script: toScript0, satoshis: out0Sats },
    { script: toScript1, satoshis: anchorSats },
  ];

  const digest = computeSighash([input], outputs, 0);
  const sig = secp.sign(digest, spendSk).normalizeS();
  const derSig = encodeDer(sig.r, sig.s);
  const unlock = buildP2pkhUnlockScript(derSig, spendPk);

  const { rawTx, txid } = serializeEFTx(
    [{ txid: sourceTxid, vout: sourceVout, unlockScript: unlock, sequence: 0xffffffff, sourceValue, sourceLock }],
    outputs,
  );
  return { rawTx, txid };
}

// ── Main ───────────────────────────────────────────────────────────────

export async function runDeepRotationTest(
  opts: {
    depth?: number;
    satoshis?: number;
    arcUrl?: string;
    arcApiKey?: string;
    metanetBase?: string;
    challengeAnswers?: string[];
  } = {},
): Promise<DeepRotationResult> {
  const depth = Math.max(1, opts.depth ?? 8);
  const seedSats = BigInt(opts.satoshis ?? 10_000);
  const arcOpts = { arcUrl: opts.arcUrl ?? 'https://arc.taal.com', apiKey: opts.arcApiKey };
  const base = opts.metanetBase ?? METANET_BASE;

  const ANCHOR_SATS = 1000n;
  // depth hops + return spend + anchor split tx + anchor return + dust buffer
  const minRequired = FEE * BigInt(depth + 3) + ANCHOR_SATS + 546n;
  const emptyResult = (detail: string): DeepRotationResult => ({
    hops: [], depth,
    sessionRecoveryOk: false, sessionRecoveryDetail: detail,
    envelopeRecoveryOk: false, envelopeRecoveryDetail: '',
    anchorRecoveryOk: false, anchorRecoveryDetail: '',
    schemaMappings: [],
    allOk: false, summary: detail,
  });
  if (seedSats < minRequired) return emptyResult(`need at least ${minRequired} sats for depth=${depth}`);

  const loadRes = await loadWallet();
  if (!loadRes.ok) throw new Error(`wallet not ready: ${loadRes.error.kind}`);
  const unlockRes = await unlockIdentityFromCache();
  if (!unlockRes.ok) throw new Error(`identity locked: ${unlockRes.error.kind}`);
  const { identityPk, identitySk } = getIdentitySnapshot();

  const identityLock = buildP2pkhLock(pubkeyToHash160(identityPk));
  const hops: DeepHop[] = [];

  // ── Fund ────────────────────────────────────────────────────────────
  let fundRaw: Uint8Array;
  let fundTxid: Uint8Array;
  let fundBeef: Uint8Array;
  let fundVout: number;
  let fundValue: bigint;

  try {
    const funded = await metanetCreateAction(
      [{ lockingScript: hexFromBytes(identityLock), satoshis: Number(seedSats), outputDescription: 'deep-rotation seed' }],
      `Semantos deep rotation test (depth=${depth})`,
      base,
    );
    fundBeef = funded.beef;
    fundTxid = funded.txid;

    const parsed = parseBeef(fundBeef);
    const entry = parsed.txs.find(t => arrayEqual(t.txid, fundTxid)) ?? parsed.txs.at(-1)!;
    fundRaw = entry.rawTx;

    const fundOut = findOutputVout(fundRaw, identityLock);
    if (!fundOut) throw new Error('fund tx: identity output not found');
    fundVout = fundOut.vout;
    fundValue = fundOut.value;

    const spv = await validateBeef(fundBeef);
    await internalizeAction({
      tx: fundBeef,
      outputs: [{ outputIndex: fundVout, protocol: 'basket insertion', insertionRemittance: { basket: 'deep-rotation', tags: ['fund'] }, satoshis: fundValue, lockingScript: identityLock }],
      description: `deep rotation depth=${depth}: fund`,
    });

    hops.push({
      label: 'fund: metanet → identity',
      txid: displayTxid(fundTxid),
      edgeIndex: null,
      satsOut: Number(fundValue),
      spvOk: spv.ok,
      spvDetail: spv.detail,
      broadcastOk: true,
      broadcastTxid: displayTxid(fundTxid),
    });
  } catch (e) {
    return emptyResult(`fund FAILED: ${(e as Error).message}`);
  }

  // ── Phase 1.5: anchor split ─────────────────────────────────────────
  // Spend the fund output into 2 outputs:
  //   vout 0 — identity lock (for the rotation chain)
  //   vout 1 — cell anchor lock (LINEAR test cell type)
  // TEST_TYPE_HASH uses the structured |8|8|8|8| construction (T5.a)
  // for triple (semantos, test, linear-cell, ""). Inlined to avoid a
  // workspace dep on @semantos/protocol-types for one test fixture.
  const TEST_TYPE_HASH = (() => {
    const out = new Uint8Array(32);
    const enc = new TextEncoder();
    (['semantos', 'test', 'linear-cell', ''] as const).forEach((seg, i) => {
      out.set(nobleSha256(enc.encode(seg)).subarray(0, 8), i * 8);
    });
    return out;
  })();
  const anchorLock = buildCellAnchorLock(identitySk, TEST_TYPE_HASH, 0);
  if (!anchorLock) return emptyResult('buildCellAnchorLock failed');

  let splitRaw: Uint8Array;
  let splitTxid: Uint8Array;
  let anchorCreatedTxid: string | undefined;

  try {
    ({ rawTx: splitRaw, txid: splitTxid } = buildSpend2(
      fundRaw, fundVout, fundValue, identityLock,
      identitySk, identityLock, anchorLock, ANCHOR_SATS,
    ));

    const splitBeef = buildBeefV1ChainedN(fundBeef, [splitRaw], splitTxid);
    const splitBcast = await broadcastToArc(splitBeef, arcOpts);
    anchorCreatedTxid = displayTxid(splitTxid);

    // Store the anchor UTXO so it survives session recovery
    await outputStore.addOutput({
      outpoint: { txid: splitTxid, vout: 1 },
      satoshis: ANCHOR_SATS,
      lockingScript: anchorLock,
      derivedKeyHash: secp.getPublicKey(deriveCellAnchorSk(identitySk, TEST_TYPE_HASH, 0)!, true),
      derivationContext: {
        protocolHash: anchorProtocolHash(TEST_TYPE_HASH),
        counterparty: identityPk,
        index: 0n,
      },
      beef: splitBeef,
      basket: 'cell-anchors',
      tags: ['linear', 'test'],
      customInstructions: new Uint8Array(0),
      confirmations: 0,
      status: 'unspent',
      spendingTxid: null,
      typeHash: TEST_TYPE_HASH,
    });

    hops.push({
      label: 'anchor-split: fund → [rotation-chain, cell-anchor]',
      txid: displayTxid(splitTxid),
      edgeIndex: null,
      satsOut: Number(fundValue - FEE - ANCHOR_SATS),
      spvOk: true,
      spvDetail: 'unconfirmed split',
      broadcastOk: splitBcast.ok,
      broadcastTxid: splitBcast.ok ? splitBcast.txid : undefined,
      error: splitBcast.ok ? undefined : `split broadcast: ${splitBcast.reason}`,
    });

    if (!splitBcast.ok) return { ...emptyResult(`anchor split failed: ${splitBcast.reason}`), hops, anchorCreatedTxid, schemaMappings: [buildSchemaMapping(TEST_TYPE_HASH, 'TestLinearCell')] };
  } catch (e) {
    return emptyResult(`anchor split FAILED: ${(e as Error).message}`);
  }

  // Rotation chain now starts from split vout 0
  const splitValue = fundValue - FEE - ANCHOR_SATS;

  // ── Rotation hops ───────────────────────────────────────────────────
  const hopRaws: Uint8Array[] = [splitRaw];
  const edgeLocks: Uint8Array[] = [];
  let prevRaw = splitRaw;
  let prevVout = 0;
  let prevValue = splitValue;
  let prevLock = identityLock;
  let prevSk = identitySk;

  for (let i = 0; i < depth; i++) {
    const toLock = buildRotatedLock(identityPk, identitySk, i);
    if (!toLock) return { ...emptyResult(`buildRotatedLock(${i}) failed`), hops };
    edgeLocks.push(toLock);

    let hopRaw: Uint8Array;
    let hopTxid: Uint8Array;

    try {
      ({ rawTx: hopRaw, txid: hopTxid } = buildSpend(prevRaw, prevVout, prevValue, prevLock, prevSk, toLock));
      hopRaws.push(hopRaw);

      const hopBeef = buildBeefV1ChainedN(fundBeef, hopRaws.slice(), hopTxid);
      const spv = await validateBeef(hopBeef);
      const bcast = await broadcastToArc(hopBeef, arcOpts);

      hops.push({
        label: i === 0 ? 'hop-0: identity → edge[0]' : `hop-${i}: edge[${i-1}] → edge[${i}]`,
        txid: displayTxid(hopTxid),
        edgeIndex: i,
        satsOut: Number(prevValue - FEE),
        spvOk: spv.ok,
        spvDetail: spv.detail,
        broadcastOk: bcast.ok,
        broadcastTxid: bcast.ok ? bcast.txid : undefined,
        error: bcast.ok ? undefined : `broadcast: ${bcast.reason}`,
      });

      if (!bcast.ok) return { ...emptyResult(`hop-${i} broadcast failed: ${bcast.reason}`), hops };

      prevRaw = hopRaw;
      prevVout = 0;
      prevValue = prevValue - FEE;
      prevLock = toLock;
      prevSk = deriveEdgeSk(identitySk, identityPk, i)!;
    } catch (e) {
      hops.push({ label: `hop-${i}`, txid: '', edgeIndex: i, satsOut: 0, spvOk: false, spvDetail: '', broadcastOk: false, error: (e as Error).message });
      return { ...emptyResult(`hop-${i} FAILED: ${(e as Error).message}`), hops };
    }
  }

  // ── Snapshot state we need to survive the runtime wipe ─────────────
  const lastRaw = prevRaw;
  const lastVout = prevVout;
  const lastValue = prevValue;
  const lastLock = prevLock;
  const lastEdgeIndex = depth - 1;
  const identityPkHex = hexFromBytes(identityPk);

  // ── Phase 2: session recovery (simulate tab reload) ─────────────────
  _resetRuntimeForTests();

  const reloadRes = await loadWallet();
  const reloadOk = reloadRes.ok;
  let sessionRecoveryOk = false;
  let sessionRecoveryDetail = '';
  let sessionReturnHop: DeepHop | undefined;

  if (!reloadOk) {
    sessionRecoveryDetail = `loadWallet after reset failed: ${reloadRes.error.kind}`;
  } else {
    const reUnlockRes = await unlockIdentityFromCache();
    if (!reUnlockRes.ok) {
      sessionRecoveryDetail = `unlockIdentityFromCache after reset failed: ${reUnlockRes.error.kind}`;
    } else {
      const reSnap = getIdentitySnapshot();
      const reloadedPkHex = hexFromBytes(reSnap.identityPk);

      if (reloadedPkHex !== identityPkHex) {
        sessionRecoveryDetail = `identity mismatch after reload: expected ${identityPkHex.slice(0, 16)}… got ${reloadedPkHex.slice(0, 16)}…`;
      } else {
        // Derive the final edge sk from the reloaded identity
        const recoveredEdgeSk = deriveEdgeSk(reSnap.identitySk, reSnap.identityPk, lastEdgeIndex);
        if (!recoveredEdgeSk) {
          sessionRecoveryDetail = `deriveEdgeSk(${lastEdgeIndex}) failed on recovered wallet`;
        } else {
          try {
            const { rawTx: retRaw, txid: retTxid } = buildSpend(lastRaw, lastVout, lastValue, lastLock, recoveredEdgeSk, identityLock);
            const retBeef = buildBeefV1ChainedN(fundBeef, [...hopRaws, retRaw], retTxid);
            const spv = await validateBeef(retBeef);
            const bcast = await broadcastToArc(retBeef, arcOpts);

            sessionReturnHop = {
              label: `recovery return: edge[${lastEdgeIndex}] → identity`,
              txid: displayTxid(retTxid),
              edgeIndex: null,
              satsOut: Number(lastValue - FEE),
              spvOk: spv.ok,
              spvDetail: spv.detail,
              broadcastOk: bcast.ok,
              broadcastTxid: bcast.ok ? bcast.txid : undefined,
              error: bcast.ok ? undefined : `broadcast: ${bcast.reason}`,
            };

            sessionRecoveryOk = bcast.ok;
            sessionRecoveryDetail = bcast.ok
              ? `identity key re-derived ✓, edge[${lastEdgeIndex}] → identity broadcast ✓`
              : `key re-derived ✓ but broadcast failed: ${bcast.reason}`;
          } catch (e) {
            sessionRecoveryDetail = `recovery return spend failed: ${(e as Error).message}`;
          }
        }
      }
    }
  }

  // ── Phase 3: envelope recovery (offline, no spend) ──────────────────
  let envelopeRecoveryOk = false;
  let envelopeRecoveryDetail = '';

  const answers = opts.challengeAnswers;
  if (!answers || answers.length === 0) {
    envelopeRecoveryDetail = 'skipped — no challengeAnswers supplied';
  } else {
    // Reload the wallet state first (may have been wiped in phase 2)
    if (!reloadOk) {
      const r2 = await loadWallet();
      if (!r2.ok) {
        envelopeRecoveryDetail = 'skipped — wallet could not reload for envelope check';
      }
    }

    const envRes = await getCachedRecoveryEnvelope();
    if (!envRes.ok) {
      envelopeRecoveryDetail = `could not load recovery envelope: ${envRes.error.kind}`;
    } else {
      try {
        const seed = await decryptRecoverySeed(envRes.value, answers);
        if (!seed) {
          envelopeRecoveryDetail = 'decryptRecoverySeed returned null — wrong answers?';
        } else {
          // Re-derive identity from the recovered seed using the same label as createWallet.
          const { hmac: hmacFn } = await import('@noble/hashes/hmac');
          const { sha256 } = await import('@noble/hashes/sha2');
          const derived = hmacFn(sha256, seed, new TextEncoder().encode('identity'));
          const derivedPk = secp.getPublicKey(derived, true);
          const derivedPkHex = hexFromBytes(derivedPk);
          derived.fill(0);
          seed.fill(0);

          if (derivedPkHex === identityPkHex) {
            envelopeRecoveryOk = true;
            envelopeRecoveryDetail = `envelope → seed → identityPk matches original ✓ (${identityPkHex.slice(0, 16)}…)`;
          } else {
            envelopeRecoveryDetail = `identityPk mismatch: expected ${identityPkHex.slice(0, 16)}… got ${derivedPkHex.slice(0, 16)}…`;
          }
        }
      } catch (e) {
        envelopeRecoveryDetail = `envelope decrypt error: ${(e as Error).message}`;
      }
    }
  }

  // ── Phase 4: anchor UTXO recovery + spend ──────────────────────────
  // The anchor record was stored in IDB (basket='cell-anchors') before the
  // runtime wipe.  Retrieve it, re-derive the spending key from the reloaded
  // identity, and broadcast the spend to ARC.
  let anchorRecoveryOk = false;
  let anchorRecoveryDetail = '';
  let anchorReturnHop: DeepHop | undefined;
  const schemaMappings: SchemaMapping[] = [buildSchemaMapping(TEST_TYPE_HASH, 'TestLinearCell')];

  try {
    // Reload identity (may already be loaded from Phase 2/3, but ensure it)
    const anchorSnap = getIdentitySnapshot();
    if (!anchorSnap.identitySk || anchorSnap.identitySk.length === 0) {
      await loadWallet();
      await unlockIdentityFromCache();
    }
    const snap = getIdentitySnapshot();

    // Look up the anchor UTXO from IDB
    const anchorRecords = await outputStore.listOutputs({ basket: 'cell-anchors', status: 'unspent' });
    const anchorRecord = anchorRecords.find(r => r.typeHash && r.typeHash.length === 32);

    if (!anchorRecord) {
      anchorRecoveryDetail = 'anchor UTXO not found in OutputStore after session recovery';
    } else {
      // Re-derive spending key from recovered identity + typeHash from stored record
      const restoredAnchorSk = deriveCellAnchorSk(snap.identitySk, anchorRecord.typeHash!, 0);
      if (!restoredAnchorSk) {
        anchorRecoveryDetail = 'deriveCellAnchorSk failed on recovered identity';
      } else {
        const { rawTx: anchorRetRaw, txid: anchorRetTxid } = buildSpend(
          splitRaw, 1, ANCHOR_SATS, anchorLock, restoredAnchorSk, identityLock,
        );
        const anchorRetBeef = buildBeefV1ChainedN(fundBeef, [splitRaw, anchorRetRaw], anchorRetTxid);
        const spv = await validateBeef(anchorRetBeef);
        const bcast = await broadcastToArc(anchorRetBeef, arcOpts);

        anchorReturnHop = {
          label: 'anchor recovery: cell-anchor[0] → identity',
          txid: displayTxid(anchorRetTxid),
          edgeIndex: null,
          satsOut: Number(ANCHOR_SATS - FEE),
          spvOk: spv.ok,
          spvDetail: spv.detail,
          broadcastOk: bcast.ok,
          broadcastTxid: bcast.ok ? bcast.txid : undefined,
          error: bcast.ok ? undefined : `broadcast: ${bcast.reason}`,
        };

        if (bcast.ok) {
          await outputStore.markSpent(anchorRecord.outpoint, anchorRetTxid);
          anchorRecoveryOk = true;
          anchorRecoveryDetail = `anchor re-derived ✓, cell-anchor[0] → identity broadcast ✓`;
        } else {
          anchorRecoveryDetail = `anchor sk re-derived ✓ but broadcast failed: ${bcast.reason}`;
        }
      }
    }
  } catch (e) {
    anchorRecoveryDetail = `anchor recovery failed: ${(e as Error).message}`;
  }

  const allHopsOk = hops.every(h => h.broadcastOk);
  const allOk = allHopsOk && sessionRecoveryOk && anchorRecoveryOk && (answers ? envelopeRecoveryOk : true);

  const summary = allOk
    ? `✓ depth=${depth}: all ${hops.length} hops + session recovery + anchor recovery${answers ? ' + envelope recovery' : ''}`
    : !allHopsOk
      ? `${hops.filter(h => h.broadcastOk).length}/${hops.length} hops succeeded`
      : !sessionRecoveryOk
        ? `all ${hops.length} hops ok but session recovery failed`
        : !anchorRecoveryOk
          ? `all ${hops.length} hops + session recovery ok but anchor recovery failed: ${anchorRecoveryDetail}`
          : `all ${hops.length} hops ok, session+anchor recovery ok, envelope recovery failed`;

  return {
    hops, depth,
    sessionRecoveryOk, sessionRecoveryDetail, sessionReturnHop,
    envelopeRecoveryOk, envelopeRecoveryDetail,
    anchorCreatedTxid, anchorRecoveryOk, anchorRecoveryDetail, anchorReturnHop,
    schemaMappings,
    allOk, summary,
  };
}

```
