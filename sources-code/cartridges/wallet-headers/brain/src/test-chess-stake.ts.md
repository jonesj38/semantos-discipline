---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/test-chess-stake.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.658087+00:00
---

# cartridges/wallet-headers/brain/src/test-chess-stake.ts

```ts
// test-chess-stake.ts — Fund a chess doubling-cube game with two
// `chess.stake.v1` cell-anchor UTXOs (one per side).
//
// Flow:
//   fund    Metanet Desktop → wallet.html identity P2PKH    (seedSats)
//           → validate BEEF+SPV → internalizeAction (basket: 'chess-fund')
//
//   split   identity → [identity-change, anchor_white, anchor_black]
//           - anchor_white = chess.stake.v1 cell-anchor at index_w
//           - anchor_black = chess.stake.v1 cell-anchor at index_b
//           - both derived via `deriveCellAnchorSk(identitySk, TYPE_HASH, idx)`
//           - chained BEEF → SPV → ARC broadcast
//           - internalizeAction each anchor (basket: 'cell-anchors',
//             tags: ['chess','stake',<color>]) with typeHash = chess.stake.v1
//             so the future native chess WalletPort can list + spend them.
//
// What this proves: the wallet can mint chess-typed cell anchors using
// exactly the same BRC-42 derivation deep-rotation already exercises —
// so Phase-2 step B (the native chess WalletPort impl) has unspent
// stake UTXOs to spend at resolution via
// `semantos_wallet_anchor_transition()`.
//
// Indices are derived from `gameId` so multiple games can fund without
// collision: index_w = first 8 LE bytes of sha256(gameId || ":w"),
// index_b = same for ":b". Recovery: the same gameId + identitySk
// re-derives identical anchor keys (deterministic).

import * as secp from '@noble/secp256k1';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import { hmac } from '@noble/hashes/hmac';
import { encodeDer } from './der';
import {
  parseBeef,
  computeMerkleRoot,
  buildBeefV1ChainedN,
  computeTxid,
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
} from './wallet-ops';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

// ── Constants ──────────────────────────────────────────────────────────

/** Stable triple for the chess.stake test fixture — built via the
 *  canonical structured |8|8|8|8| construction (T5.a, matches
 *  `buildTypeHash` from `@semantos/protocol-types`).  `.v1` dropped
 *  per D12; segment4 stays empty.  The (chess, stake, "", "") triple
 *  is intentionally simple — chess is a test fixture, not a full
 *  cartridge.  Inlined helper to avoid adding @semantos/protocol-types
 *  to @semantos/wallet-browser's deps for one test fixture.  Routing
 *  invariant: bytes 0..7 = sha256("chess")[0:8] = ac739dccd121f712. */
function buildTestTypeHash(s1: string, s2: string, s3: string, s4: string): Uint8Array {
  const out = new Uint8Array(32);
  const enc = new TextEncoder();
  [s1, s2, s3, s4].forEach((seg, i) => {
    out.set(nobleSha256(enc.encode(seg)).subarray(0, 8), i * 8);
  });
  return out;
}
const CHESS_STAKE_TYPE_NAME = 'chess.stake';
const CHESS_STAKE_TYPE_HASH = buildTestTypeHash('chess', 'stake', '', '');

const FEE = 192n;

// ── Types ──────────────────────────────────────────────────────────────

export interface ChessAnchor {
  color: 'white' | 'black';
  anchorIndex: number;
  satoshis: number;
  outpointTxid: string;
  outpointVout: number;
  derivedPkHex: string;
}

export interface ChessStakeResult {
  ok: boolean;
  identityPkHex: string;
  gameId: string;
  fundTxid?: string;
  splitTxid?: string;
  anchors: ChessAnchor[];
  schemaMapping: SchemaMapping;
  summary: string;
  error?: string;
}

// ── Helpers ────────────────────────────────────────────────────────────

function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

function arrayEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

function displayTxid(t: Uint8Array): string {
  // Display in big-endian (block-explorer style): reverse the LE bytes.
  const rev = new Uint8Array(t.length);
  for (let i = 0; i < t.length; i++) rev[i] = t[t.length - 1 - i]!;
  return bytesToHex(rev);
}

/** Derive an anchor index for (gameId, color). First 8 LE bytes of
 *  sha256("<gameId>:<color>"). JS number is safe to ~2^53; sha256
 *  prefix fits. */
function deriveAnchorIndex(gameId: string, color: 'white' | 'black'): number {
  const tag = `${gameId}:${color === 'white' ? 'w' : 'b'}`;
  const h = nobleSha256(new TextEncoder().encode(tag));
  const dv = new DataView(h.buffer, h.byteOffset, h.byteLength);
  // Low 53 bits to stay in safe-integer range.
  const lo = dv.getUint32(0, true);
  const hi = dv.getUint32(4, true) & 0x001f_ffff;
  return hi * 0x1_0000_0000 + lo;
}

/** Locate the output in `rawTx` whose script equals `lock`. */
function findOutputVout(rawTx: Uint8Array, lock: Uint8Array): { vout: number; value: bigint } | null {
  // Minimal output scanner — find an output by exact script match.
  // Tx layout: version(4) | inCount(varint) | inputs… | outCount(varint) | outputs…
  let p = 4;
  // skip inputs
  const inCount = rawTx[p++]!;
  // Assumes < 0xFD inputs; deep-rotation has the same assumption.
  for (let i = 0; i < inCount; i++) {
    p += 32 + 4; // outpoint
    const slen = rawTx[p++]!;
    p += slen + 4; // script + sequence (assumes script < 0xFD)
  }
  const outCount = rawTx[p++]!;
  for (let v = 0; v < outCount; v++) {
    const dv = new DataView(rawTx.buffer, rawTx.byteOffset + p, 8);
    const value = dv.getBigUint64(0, true);
    p += 8;
    const slen = rawTx[p++]!;
    const script = rawTx.subarray(p, p + slen);
    p += slen;
    if (arrayEqual(script, lock)) return { vout: v, value };
  }
  return null;
}

/** Build a 1-input → 3-output split tx:
 *  out0 = identity-change, out1 = anchor_white, out2 = anchor_black. */
function buildSpend3(
  sourceRaw: Uint8Array,
  sourceVout: number,
  sourceValue: bigint,
  sourceLock: Uint8Array,
  spendSk: Uint8Array,
  changeLock: Uint8Array,
  anchorWhiteLock: Uint8Array,
  anchorBlackLock: Uint8Array,
  anchorSats: bigint,
): { rawTx: Uint8Array; txid: Uint8Array } {
  const spendPk = secp.getPublicKey(spendSk, true);
  const sourceTxid = computeTxid(sourceRaw);
  const changeSats = sourceValue - FEE - 2n * anchorSats;
  if (changeSats < 546n) throw new Error(`dust after fee+anchors: ${changeSats} sats`);

  const input: TxInput = {
    txid: sourceTxid,
    vout: sourceVout,
    value: sourceValue,
    script: sourceLock,
    sequence: 0xffffffff,
  };
  const outputs: TxOutput[] = [
    { script: changeLock, satoshis: changeSats },
    { script: anchorWhiteLock, satoshis: anchorSats },
    { script: anchorBlackLock, satoshis: anchorSats },
  ];

  const digest = computeSighash([input], outputs, 0);
  const sig = secp.sign(digest, spendSk).normalizeS();
  const derSig = encodeDer(sig.r, sig.s);
  const unlock = buildP2pkhUnlockScript(derSig, spendPk);

  const { rawTx, txid } = serializeEFTx(
    [
      {
        txid: sourceTxid,
        vout: sourceVout,
        unlockScript: unlock,
        sequence: 0xffffffff,
        sourceValue,
        sourceLock,
      },
    ],
    outputs,
  );
  return { rawTx, txid };
}

async function validateBeef(beef: Uint8Array): Promise<boolean> {
  // Mirrors deep-rotation's local-headers SPV check via parseBeef +
  // computeMerkleRoot. A null bump path means unconfirmed — we accept
  // unconfirmed-on-broadcast (ARC accepts mempool); SPV is enforced
  // only when the funding tx is already mined.
  try {
    const parsed = parseBeef(beef);
    for (const tx of parsed.txs) {
      if (tx.bump) {
        const root = computeMerkleRoot(tx.txid, tx.bump);
        if (!root) return false;
      }
    }
    return true;
  } catch {
    return false;
  }
}

// ── Main ───────────────────────────────────────────────────────────────

export async function runChessStakeTest(opts: {
  /** Per-side base stake in satoshis. */
  stakeSats?: number;
  /** Unique game identifier — drives anchor indices so multiple games
   *  in the same wallet don't collide. */
  gameId?: string;
  arcUrl?: string;
  arcApiKey?: string;
  metanetBase?: string;
} = {}): Promise<ChessStakeResult> {
  const stakeSats = BigInt(opts.stakeSats ?? 1_000);
  const gameId = opts.gameId ?? `chess-${Date.now().toString(36)}`;
  const arcOpts = { arcUrl: opts.arcUrl ?? 'https://arc.taal.com', apiKey: opts.arcApiKey };
  const base = opts.metanetBase ?? METANET_BASE;

  const schemaMapping = buildSchemaMapping(CHESS_STAKE_TYPE_HASH, 'ChessStakeV1');
  const empty: ChessStakeResult = {
    ok: false,
    identityPkHex: '',
    gameId,
    anchors: [],
    schemaMapping,
    summary: '',
  };

  await loadWallet();
  await unlockIdentityFromCache();
  const snap = getIdentitySnapshot();
  if (!snap.identitySk || !snap.identityPk) {
    return { ...empty, error: 'wallet identity not unlocked' };
  }
  const identitySk = snap.identitySk;
  const identityPk = snap.identityPk;
  const identityPkHex = bytesToHex(identityPk);
  const identityLock = buildP2pkhLock(pubkeyToHash160(identityPk));

  const indexW = deriveAnchorIndex(gameId, 'white');
  const indexB = deriveAnchorIndex(gameId, 'black');
  const anchorLockW = buildCellAnchorLock(identitySk, CHESS_STAKE_TYPE_HASH, indexW);
  const anchorLockB = buildCellAnchorLock(identitySk, CHESS_STAKE_TYPE_HASH, indexB);
  if (!anchorLockW || !anchorLockB) {
    return { ...empty, identityPkHex, error: 'cell-anchor derivation returned null' };
  }

  // Step 1: fund identity from Metanet Desktop.
  const seedSats = 2n * stakeSats + FEE + 1_000n; // anchors + fee + slack change
  let fundRaw: Uint8Array;
  let fundTxid: Uint8Array;
  let fundBeef: Uint8Array;
  let fundVout = 0;
  let fundValue = seedSats;
  try {
    const funded = await metanetCreateAction(
      [{
        lockingScript: bytesToHex(identityLock),
        satoshis: Number(seedSats),
        outputDescription: `Chess stake fund — ${gameId}`,
      }],
      `Chess stake fund — ${gameId}`,
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

    if (!(await validateBeef(fundBeef))) throw new Error('fund BEEF SPV failed');
    await internalizeAction({
      tx: fundBeef,
      outputs: [
        {
          outputIndex: fundVout,
          protocol: 'basket insertion',
          insertionRemittance: { basket: 'chess-fund', tags: ['chess', 'fund', gameId] },
          satoshis: Number(fundValue),
          lockingScript: identityLock,
        },
      ],
      description: `Chess fund (${gameId})`,
    });
  } catch (e) {
    return { ...empty, identityPkHex, error: `fund failed: ${(e as Error).message}` };
  }

  // Step 2: split → identity-change + anchor_white + anchor_black.
  let splitRaw: Uint8Array;
  let splitTxid: Uint8Array;
  let splitBeef: Uint8Array;
  try {
    ({ rawTx: splitRaw, txid: splitTxid } = buildSpend3(
      fundRaw,
      fundVout,
      fundValue,
      identityLock,
      identitySk,
      identityLock, // change back to identity
      anchorLockW,
      anchorLockB,
      stakeSats,
    ));
    splitBeef = buildBeefV1ChainedN(fundBeef, [splitRaw], splitTxid);
    if (!(await validateBeef(splitBeef))) throw new Error('split BEEF SPV failed');
    const bcast = await broadcastToArc(splitBeef, arcOpts);
    if (!bcast.ok) throw new Error(`split broadcast: ${bcast.reason}`);
  } catch (e) {
    return { ...empty, identityPkHex, fundTxid: displayTxid(fundTxid), error: `split failed: ${(e as Error).message}` };
  }

  // Step 3: persist each anchor in the cell-anchors basket so the
  // native chess WalletPort can list + spend them at resolution via
  // semantos_wallet_anchor_transition().
  const anchors: ChessAnchor[] = [];
  for (const [color, idx, lock, vout] of [
    ['white' as const, indexW, anchorLockW, 1],
    ['black' as const, indexB, anchorLockB, 2],
  ]) {
    const anchorSk = deriveCellAnchorSk(identitySk, CHESS_STAKE_TYPE_HASH, idx)!;
    const anchorPk = secp.getPublicKey(anchorSk, true);
    try {
      await internalizeAction({
        tx: splitBeef,
        outputs: [
          {
            outputIndex: vout,
            protocol: 'basket insertion',
            insertionRemittance: {
              basket: 'cell-anchors',
              tags: ['chess', 'stake', color, gameId],
            },
            satoshis: Number(stakeSats),
            lockingScript: lock,
          },
        ],
        description: `Chess ${CHESS_STAKE_TYPE_NAME} anchor (${color}, ${gameId})`,
      });
      // Persist the full derivation context so recovery can re-derive.
      await outputStore.addOutput({
        outpoint: { txid: splitTxid, vout },
        satoshis: Number(stakeSats),
        lockingScript: lock,
        derivedKeyHash: anchorPk,
        derivationContext: {
          protocolHash: anchorProtocolHash(CHESS_STAKE_TYPE_HASH),
          counterparty: identityPk,
          index: BigInt(idx),
        },
        beef: splitBeef,
        basket: 'cell-anchors',
        tags: ['chess', 'stake', color, gameId],
        customInstructions: new Uint8Array(0),
        confirmations: 0,
        status: 'unspent',
        spendingTxid: null,
        typeHash: CHESS_STAKE_TYPE_HASH,
      });
      anchors.push({
        color,
        anchorIndex: idx,
        satoshis: Number(stakeSats),
        outpointTxid: displayTxid(splitTxid),
        outpointVout: vout,
        derivedPkHex: bytesToHex(anchorPk),
      });
    } catch (e) {
      return {
        ...empty,
        identityPkHex,
        fundTxid: displayTxid(fundTxid),
        splitTxid: displayTxid(splitTxid),
        anchors,
        error: `anchor[${color}] persist: ${(e as Error).message}`,
      };
    }
  }

  return {
    ok: true,
    identityPkHex,
    gameId,
    fundTxid: displayTxid(fundTxid),
    splitTxid: displayTxid(splitTxid),
    anchors,
    schemaMapping,
    summary: `funded ${gameId}: white@${indexW}, black@${indexB}, ${stakeSats} sats each`,
  };
}

```
