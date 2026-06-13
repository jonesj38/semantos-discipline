---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/test-covenant-genesis.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.646035+00:00
---

# cartridges/wallet-headers/brain/src/test-covenant-genesis.ts

```ts
// test-covenant-genesis.ts — create the first MNCA covenant UTXO on mainnet.
//
// OPERATOR-RUN (browser, wallet.html). Mirrors test-mnca-anchor.ts but instead
// of a pushdrop it creates the covenant locking script (tile-covenant.ts) as a
// custom output via Metanet Desktop createAction. This is the GENESIS cell:
// it parks `satoshis` in the covenant carrying a seed 3×3 region. Creating it
// risks nothing until it is spent — the spend (buildCovenantSpend) is the live
// test of the OP_PUSH_TX AUTH clause.
//
// ── SAFETY ──────────────────────────────────────────────────────────────
//   • DRY-RUN by default: builds + shows the covenant script, no Metanet call.
//   • MAX_GENESIS_SATS hard cap (don't drain the funding wallet).
//   • This module never broadcasts a SPEND and never holds the covenant key
//     (the covenant is unlocked by a preimage, not a key).

import { compileCovenantScript } from './tile-covenant';
import { DEFAULT_RULE } from './tile-script';
import { createAction as metanetCreateAction, METANET_BASE } from './metanet-client';
import { parseBeef, hexFromBytes, reverseTxid, readVarInt, computeTxid, toBeefV1 } from './beef-codec';
import { broadcastToArc } from './arc-broadcast';
import { buildP2pkhLock, pubkeyToHash160 } from './tx-builder';
import { loadWallet, unlockIdentityFromCache, getIdentitySnapshot } from './wallet-ops';

/** Hard ceiling on the covenant value (protects the funding wallet). */
const MAX_GENESIS_SATS = 5000n;
/** Fee reserve created as a 2nd output to identity, so the spend is single-parent. */
const FEE_RESERVE_SATS = 3000n;

/** Seed region: alive centre (200) + two alive neighbours → survives, grows to 255. */
const DEFAULT_SEED = new Uint8Array([130, 0, 130, 0, 200, 0, 0, 0, 0]);

/**
 * Genesis → spend handoff. The spend needs the genesis BEEF (so its single
 * parent travels in the package) + the fee-reserve UTXO. Cached in-memory for
 * the same wallet session; the spend panel reads it.
 */
export interface GenesisRecord {
  beef: Uint8Array;
  txidInternal: Uint8Array;
  txidDisplay: string;
  covVout: number;
  covSats: bigint;
  feeVout: number;
  feeValue: bigint;
  regionHex: string;
}
let lastGenesis: GenesisRecord | null = null;
export function getLastGenesis(): GenesisRecord | null { return lastGenesis; }

function arrayEqual(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((x, i) => x === b[i]);
}

/** Find the output index whose locking script matches `lock`. */
function findOutputVout(rawTx: Uint8Array, lock: Uint8Array): { vout: number; value: bigint } | null {
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
    if (arrayEqual(script, lock)) return { vout: v, value };
  }
  return null;
}

export interface CovenantGenesisOptions {
  /** Seed 3×3 region (9 bytes). Defaults to a survival seed. */
  seedRegion?: Uint8Array;
  /** Sats locked into the covenant. Default 5000. */
  satoshis?: number;
  /** Set true to CREATE on mainnet via Metanet. Default false (dry-run). */
  confirm?: boolean;
  metanetBase?: string;
  arcUrl?: string;
  arcApiKey?: string;
}

export interface CovenantGenesisResult {
  ok: boolean;
  dryRun: boolean;
  lockHex?: string;
  lockLen?: number;
  regionHex?: string;
  genesisTxid?: string;   // display order (computed from the rawTx)
  vout?: number;          // covenant output index
  feeVout?: number;       // fee-reserve output index
  satoshis?: number;
  broadcastTxid?: string; // ARC ack
  summary: string;
}

export async function runCovenantGenesis(opts: CovenantGenesisOptions = {}): Promise<CovenantGenesisResult> {
  const seed = opts.seedRegion ?? DEFAULT_SEED;
  const sats = BigInt(opts.satoshis ?? 5000);
  const dryRun = !opts.confirm;
  const base = opts.metanetBase ?? METANET_BASE;

  if (seed.length !== 9) return { ok: false, dryRun, summary: 'seed region must be 9 bytes (3×3)' };
  if (sats > MAX_GENESIS_SATS) return { ok: false, dryRun, summary: `refusing: ${sats} > MAX_GENESIS_SATS ${MAX_GENESIS_SATS}` };

  const lock = compileCovenantScript(seed, DEFAULT_RULE);
  const lockHex = hexFromBytes(lock);
  const regionHex = hexFromBytes(seed);

  if (dryRun) {
    return {
      ok: true, dryRun: true, lockHex, lockLen: lock.length, regionHex,
      summary: `DRY-RUN — covenant lock ${lock.length} bytes, seed region ${regionHex}. ` +
        `Confirm to create on mainnet (${sats} covenant + ${FEE_RESERVE_SATS} fee reserve to identity, ` +
        `one tx). The covenant is safe to create; only the SPEND executes AUTH.`,
    };
  }

  // Identity P2PKH = the fee reserve (a 2nd output in the SAME genesis tx, so
  // the spend has a single parent). Loaded for its locking script.
  const loadRes = await loadWallet();
  if (!loadRes.ok) return { ok: false, dryRun, lockHex, lockLen: lock.length, regionHex, summary: `wallet not ready: ${loadRes.error.kind}` };
  const unlockRes = await unlockIdentityFromCache();
  if (!unlockRes.ok) return { ok: false, dryRun, lockHex, lockLen: lock.length, regionHex, summary: `identity locked: ${unlockRes.error.kind}` };
  const { identityPk } = getIdentitySnapshot();
  const identityLock = buildP2pkhLock(pubkeyToHash160(identityPk));

  const arcOpts = { arcUrl: opts.arcUrl ?? 'https://arc.taal.com', apiKey: opts.arcApiKey };
  let beef: Uint8Array, rawTx: Uint8Array;
  let cov: { vout: number; value: bigint } | null, fee: { vout: number; value: bigint } | null;
  try {
    const created = await metanetCreateAction(
      [
        { lockingScript: lockHex, satoshis: Number(sats), outputDescription: 'mnca covenant genesis' },
        { lockingScript: hexFromBytes(identityLock), satoshis: Number(FEE_RESERVE_SATS), outputDescription: 'mnca covenant fee reserve' },
      ],
      'Semantos MNCA covenant genesis',
      base,
    );
    beef = created.beef;
    const parsed = parseBeef(beef);
    const entry = parsed.txs.find((t) => arrayEqual(t.txid, created.txid)) ?? parsed.txs.at(-1)!;
    rawTx = entry.rawTx;
    cov = findOutputVout(rawTx, lock);
    fee = findOutputVout(rawTx, identityLock);
  } catch (e) {
    return { ok: false, dryRun: false, lockHex, lockLen: lock.length, regionHex,
      summary: `Genesis build FAILED — Metanet Desktop at ${base}: ${(e as Error).message}` };
  }
  if (!cov || !fee) {
    return { ok: false, dryRun: false, lockHex, lockLen: lock.length, regionHex,
      summary: `createAction returned a tx, but ${!cov ? 'the covenant' : 'the fee-reserve'} output was not found — inspect the BEEF.` };
  }

  const txidInternal = computeTxid(rawTx);
  const txidDisplay = hexFromBytes(reverseTxid(txidInternal));
  // Normalize Metanet's BEEF (may be Atomic/V2) to clean V1 — ARC's /v1/tx
  // misparses non-V1 ("unexpected EOF"). buildBeefV1 already does this for the
  // spend; the genesis must too.
  const bcast = await broadcastToArc(toBeefV1(beef), arcOpts);
  if (bcast.ok) {
    lastGenesis = {
      beef, txidInternal, txidDisplay,
      covVout: cov.vout, covSats: cov.value,
      feeVout: fee.vout, feeValue: fee.value,
      regionHex,
    };
  }
  return {
    ok: bcast.ok, dryRun: false, lockHex, lockLen: lock.length, regionHex,
    genesisTxid: txidDisplay, vout: cov.vout, feeVout: fee.vout, satoshis: Number(cov.value),
    broadcastTxid: bcast.ok ? bcast.txid : undefined,
    summary: bcast.ok
      ? `✓ GENESIS BROADCAST — txid ${txidDisplay} (covenant vout ${cov.vout} = ${cov.value} sats, ` +
        `fee reserve vout ${fee.vout} = ${fee.value} sats). ARC ack: ${bcast.txid}. ` +
        `The spend panel can now advance it (genesis cached for this session).`
      : `✗ Genesis built but ARC REJECTED: ${bcast.reason}. NOT on-chain (no funds moved). txid would be ${txidDisplay}.`,
  };
}

```
