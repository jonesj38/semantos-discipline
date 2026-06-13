---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/chess-wallet-claim.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.661738+00:00
---

# cartridges/wallet-headers/brain/src/chess-wallet-claim.ts

```ts
/**
 * chess-wallet-claim — browser-native payout for chess doubling-cube games.
 *
 * Runs entirely in the wallet browser context — no server-side submitter,
 * no key export, no rbs scripts. Uses the identity sk already in wallet
 * memory and the anchor UTXOs already in outputStore (IndexedDB).
 *
 * Flow:
 *   1. Call brain chess.get_game → get winner / multiplier.
 *   2. Find this game's anchor UTXOs in outputStore (stored by test-chess-stake).
 *   3. Re-derive each anchor's spending sk via deriveCellAnchorSk.
 *   4. Build a spend tx paying the pot (totalIn − fee) to the winner.
 *   5. Broadcast the BEEF to ARC.
 *   6. Mark anchors spent in outputStore (cache; on-chain is authoritative).
 *
 * V1 constraint: both anchor UTXOs must be derivable from the same identity sk
 * (i.e. the game was funded from one wallet instance). For real two-player games
 * with separate wallets the correct mechanism is §12 pre-signed settlements —
 * tracked separately. On-chain double-spend rejection is the replay guard.
 *
 * Reference:
 *   cartridges/wallet-headers/brain/src/chess-submitter.ts  (bun/file equivalent)
 *   cartridges/wallet-headers/brain/src/chess-manifest-export.ts
 *   cartridges/wallet-headers/brain/src/chess-brain-proxy.ts
 *   docs/design/CHESS-DOUBLING-CUBE.md §12
 */

import * as secp from '@noble/secp256k1';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import { hmac } from '@noble/hashes/hmac';
import { encodeDer } from './der';
import { parseBeef, buildBeefV1ChainedN, computeTxid } from './beef-codec';
import {
  computeSighash,
  serializeEFTx,
  buildP2pkhUnlockScript,
  buildP2pkhLock,
  pubkeyToHash160,
  type TxInput,
  type TxOutput,
} from './tx-builder';
import { deriveCellAnchorSk } from './cell-anchor';
import { broadcastToArc } from './arc-broadcast';
import { outputStore, type OutputRecord } from './output-store';
import { dispatchChessVerb } from './chess-brain-proxy';
import { getIdentitySnapshot } from './wallet-ops';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

// ── Types ──────────────────────────────────────────────────────────────

export interface ClaimOpts {
  gameId: string;
  /** wss://brain.oddjobtodd.info/api/v1/wallet */
  brainUrl: string;
  /** 64-char hex operator bearer */
  bearer: string;
  arcUrl?: string;
  /** Build and show the tx without broadcasting (default: false). */
  dryRun?: boolean;
}

export interface ClaimResult {
  ok: boolean;
  dryRun: boolean;
  gameId: string;
  winner?: 'white' | 'black';
  isDraw?: boolean;
  payoutSats?: bigint;
  txidBe?: string;
  arcTxid?: string;
  summary: string;
  error?: string;
}

// ── Wire shape from chess.get_game ────────────────────────────────────

interface GameRecord {
  ok: true;
  gameId: string;
  status: string;
  winner: 'white' | 'black' | null;
  stakeSats: number;
  multiplier: number;
}

function isGameRecord(v: unknown): v is GameRecord {
  return typeof v === 'object' && v !== null && (v as { ok?: unknown }).ok === true;
}

// ── Helpers ────────────────────────────────────────────────────────────

function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

const FEE_SATS = 200n;

// ── Main ───────────────────────────────────────────────────────────────

/** Claim chess winnings for a resolved game from the wallet UI. */
export async function claimChessWinnings(opts: ClaimOpts): Promise<ClaimResult> {
  const arcUrl = opts.arcUrl ?? 'https://arc.gorillapool.io';
  const dryRun = opts.dryRun ?? false;
  const base: ClaimResult = { ok: false, dryRun, gameId: opts.gameId, summary: '' };

  // ── 1. Brain: resolve the game state ─────────────────────────────────
  const rpc = await dispatchChessVerb({
    verb: 'get_game',
    params: { gameId: opts.gameId },
    brainUrl: opts.brainUrl,
    bearer: opts.bearer,
  });
  if (rpc.error) return { ...base, error: `brain RPC: ${rpc.error.message}` };
  const rec = rpc.result;
  if (!isGameRecord(rec)) return { ...base, error: `unexpected brain response: ${JSON.stringify(rec)}` };

  const { status } = rec;
  if (status === 'waiting' || status === 'active') {
    return { ...base, error: `game still in progress (${status})` };
  }
  if (status === 'cancelled') {
    // Each player's anchor goes back to themselves; not yet implemented
    // (would require two separate 1-input txs, one per anchor).
    return { ...base, error: 'game cancelled — each player should claim their own anchor separately (not yet implemented)' };
  }

  const isDraw = status === 'draw';
  const winner: 'white' | 'black' | null = isDraw ? null : (rec.winner ?? null);
  if (!isDraw && winner === null) {
    return { ...base, error: `game ended (${status}) but no winner in response` };
  }

  // ── 2. Wallet: get identity sk ────────────────────────────────────────
  const snap = getIdentitySnapshot();
  if (!snap.identitySk || !snap.identityPk) {
    return { ...base, error: 'wallet not unlocked — reload the page and try again' };
  }
  const { identitySk, identityPk } = snap;

  // ── 3. OutputStore: find this game's unspent anchors ─────────────────
  const all = await outputStore.listOutputs({ basket: 'cell-anchors', status: 'unspent' });
  const gameAnchors = all.filter((r: OutputRecord) =>
    r.tags.includes('chess') &&
    r.tags.includes('stake') &&
    r.tags.includes(opts.gameId) &&
    r.typeHash !== undefined
  );
  if (gameAnchors.length === 0) {
    return {
      ...base,
      error: `no unspent chess anchors for "${opts.gameId}" in this wallet — ` +
        'make sure you funded the game from this wallet instance',
    };
  }

  // ── 4. Build inputs + re-derive spending keys ─────────────────────────
  type EfInput = {
    txid: Uint8Array; vout: number; unlockScript: Uint8Array;
    sequence: number; sourceValue: bigint; sourceLock: Uint8Array;
  };
  const txInputs: TxInput[] = [];
  const efInputs: EfInput[] = [];
  const anchorSks: Uint8Array[] = [];

  for (const anchor of gameAnchors) {
    const sk = deriveCellAnchorSk(
      identitySk,
      anchor.typeHash!,           // typeHash present — filtered above
      Number(anchor.derivationContext.index),
    );
    if (!sk) {
      return { ...base, error: `key derivation failed for anchor index ${anchor.derivationContext.index}` };
    }
    anchorSks.push(sk);
    txInputs.push({
      txid: anchor.outpoint.txid,
      vout: anchor.outpoint.vout,
      value: anchor.satoshis,       // already bigint
      script: anchor.lockingScript,
      sequence: 0xffffffff,
    });
    efInputs.push({
      txid: anchor.outpoint.txid,
      vout: anchor.outpoint.vout,
      unlockScript: new Uint8Array(0), // filled after outputs known
      sequence: 0xffffffff,
      sourceValue: anchor.satoshis,
      sourceLock: anchor.lockingScript,
    });
  }

  const totalIn = txInputs.reduce((s, i) => s + i.value, 0n);
  if (totalIn < FEE_SATS + 546n) {
    return { ...base, error: `total_in ${totalIn} sats would dust after fee` };
  }
  const payoutSats = totalIn - FEE_SATS;

  // ── 5. Build outputs ──────────────────────────────────────────────────
  const identityLock = buildP2pkhLock(pubkeyToHash160(identityPk));
  let txOutputs: TxOutput[];
  if (isDraw) {
    // Return each anchor to its owner (same identity in V1).
    // Simple even split: two equal outputs, each absorbing half the fee.
    const half = (payoutSats - FEE_SATS) / 2n;
    if (half < 546n) return { ...base, error: 'pot too small to split without dusting' };
    txOutputs = [
      { script: identityLock, satoshis: half },
      { script: identityLock, satoshis: half },
    ];
  } else {
    // Winner takes all. V1: both anchors belong to the same wallet identity.
    // In a real two-player game the winner's owner_pk from the manifest would
    // be used here; tracked in the §12 pre-signed-settlement follow-up.
    txOutputs = [{ script: identityLock, satoshis: payoutSats }];
  }

  // ── 6. Sign each input ────────────────────────────────────────────────
  for (let i = 0; i < txInputs.length; i++) {
    const sk = anchorSks[i]!;
    const pk = secp.getPublicKey(sk, true);
    const digest = computeSighash(txInputs, txOutputs, i);
    const sig = secp.sign(digest, sk).normalizeS();
    efInputs[i]!.unlockScript = buildP2pkhUnlockScript(encodeDer(sig.r, sig.s), pk);
  }

  // ── 7. Serialize + build BEEF proof ──────────────────────────────────
  const { rawTx, txid } = serializeEFTx(efInputs, txOutputs);
  const txidBeHex = bytesToHex(new Uint8Array(txid).reverse());

  // Deduplicate source BEEFs by funding txid (both anchors often come from
  // the same split tx, so only one BEEF is needed).
  const seenParents = new Set<string>();
  const distinctBeefs: Uint8Array[] = [];
  for (const anchor of gameAnchors) {
    const parentIdHex = bytesToHex(anchor.outpoint.txid.slice().reverse()); // LE→BE for dedup
    if (seenParents.has(parentIdHex)) continue;
    seenParents.add(parentIdHex);
    distinctBeefs.push(anchor.beef);
  }
  const baseBeef = distinctBeefs[0]!;
  const followups: Uint8Array[] = [];
  for (let i = 1; i < distinctBeefs.length; i++) {
    const parsed = parseBeef(distinctBeefs[i]!);
    for (const tx of parsed.txs) followups.push(tx.rawTx);
  }
  followups.push(rawTx);
  const beef = buildBeefV1ChainedN(baseBeef, followups, txid);

  // ── 8. Dry-run exit ───────────────────────────────────────────────────
  const label = isDraw ? 'draw' : `${winner!} wins`;
  if (dryRun) {
    return {
      ok: true, dryRun: true, gameId: opts.gameId,
      winner: winner ?? undefined, isDraw,
      payoutSats, txidBe: txidBeHex,
      summary: `DRY-RUN ${label} — ${payoutSats} sats → ${txidBeHex.slice(0, 16)}…`,
    };
  }

  // ── 9. Broadcast ──────────────────────────────────────────────────────
  const bcast = await broadcastToArc(beef, { arcUrl });
  if (!bcast.ok) {
    return { ...base, txidBe: txidBeHex, error: `ARC broadcast failed: ${bcast.reason}` };
  }
  const arcTxid = bcast.txid ?? txidBeHex;

  // ── 10. Mark anchors spent in outputStore (cache only) ────────────────
  const spendingTxid = new Uint8Array(txid); // LE bytes as returned by computeTxid
  for (const anchor of gameAnchors) {
    try { await outputStore.markSpent(anchor.outpoint, spendingTxid); }
    catch { /* non-fatal; on-chain state is authoritative */ }
  }

  return {
    ok: true, dryRun: false, gameId: opts.gameId,
    winner: winner ?? undefined, isDraw,
    payoutSats, txidBe: txidBeHex, arcTxid,
    summary: `✓ ${label} — ${payoutSats} sats, txid ${arcTxid}`,
  };
}

```
