---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/test-pushtx-auth.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.661156+00:00
---

# cartridges/wallet-headers/brain/src/test-pushtx-auth.ts

```ts
// test-pushtx-auth.ts — isolate + test Brendogg's OP_PUSH_TX AUTH clause on
// mainnet, cheaply, before risking the full covenant.
//
// OPERATOR-RUN (browser, wallet.html). The lock is JUST the auth clause:
//
//     <0x41> OP_TOALTSTACK  <OP_PUSH_TX block>  OP_CHECKSIG
//
// To spend it the witness is simply the BIP143 sighash preimage of the spend.
// The block hashes it, derives the k=1 / R=Gx signature, and OP_CHECKSIG passes
// IFF the node's own sighash equals that preimage — i.e. the preimage is
// genuine. No covenant body, no key: if this spend confirms, AUTH works on a
// real node and the full covenant becomes high-confidence. If it bounces, we
// learned it for ~the fee, not 5k blind.
//
// Uses Extended Format (EF) so ARC validates the script without a UTXO lookup —
// no BEEF ancestry needed. DRY-RUN by default; MAX cap protects the wallet.

import { OP, op, pushBytes, compile, seq } from './script-macro';
import { pushTxIntrospect } from './push-tx';
import { buildP2pkhLock, pubkeyToHash160, buildSighashPreimage, serializeEFTx, type TxInput, type TxOutput, type EFInput } from './tx-builder';
import { createAction as metanetCreateAction, METANET_BASE } from './metanet-client';
import { parseBeef, hexFromBytes, reverseTxid, readVarInt, buildBeefV1 } from './beef-codec';
import { broadcastToArc } from './arc-broadcast';
import { loadWallet, unlockIdentityFromCache, getIdentitySnapshot } from './wallet-ops';

const MAX_FUND_SATS = 5000n;

/** The AUTH-only lock: push SIGHASH flag to alt, run OP_PUSH_TX, OP_CHECKSIG. */
export function buildAuthOnlyLock(): Uint8Array {
  return compile(seq(
    [pushBytes(Uint8Array.of(0x41)), op(OP.OP_TOALTSTACK)],
    pushTxIntrospect(),
    [op(OP.OP_CHECKSIG)],
  ));
}

function arrayEqual(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((x, i) => x === b[i]);
}

function findOutputVout(rawTx: Uint8Array, lock: Uint8Array): { vout: number; value: bigint } | null {
  let off = 4;
  let nIn: number; [nIn, off] = readVarInt(rawTx, off);
  for (let i = 0; i < nIn; i++) { off += 36; let sl: number; [sl, off] = readVarInt(rawTx, off); off += sl + 4; }
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

export interface PushtxAuthOptions {
  fundSats?: number;  // sats locked in the auth-only output (default 2000)
  feeSats?: number;   // fee for the spend (default 1000; rest returns to identity)
  confirm?: boolean;  // true = fund + broadcast on mainnet. default false.
  metanetBase?: string;
  arcUrl?: string;
  arcApiKey?: string;
}

export interface PushtxAuthResult {
  ok: boolean;
  dryRun: boolean;
  lockLen: number;
  fundTxid?: string;     // display order
  fundVout?: number;
  spendTxid?: string;    // the AUTH-test spend we built
  efTxHex?: string;
  broadcastTxid?: string;
  summary: string;
}

export async function runPushtxAuthTest(opts: PushtxAuthOptions = {}): Promise<PushtxAuthResult> {
  const base = opts.metanetBase ?? METANET_BASE;
  const arcOpts = { arcUrl: opts.arcUrl ?? 'https://arc.taal.com', apiKey: opts.arcApiKey };
  const fundSats = BigInt(opts.fundSats ?? 2000);
  const feeSats = BigInt(opts.feeSats ?? 1000);
  const dryRun = !opts.confirm;

  const lock = buildAuthOnlyLock();
  if (fundSats > MAX_FUND_SATS) return { ok: false, dryRun, lockLen: lock.length, summary: `refusing: ${fundSats} > MAX ${MAX_FUND_SATS}` };
  if (feeSats >= fundSats) return { ok: false, dryRun, lockLen: lock.length, summary: `feeSats ${feeSats} must be < fundSats ${fundSats}` };

  // Identity P2PKH is where the spent sats return (recoverable).
  const loadRes = await loadWallet();
  if (!loadRes.ok) return { ok: false, dryRun, lockLen: lock.length, summary: `wallet not ready: ${loadRes.error.kind}` };
  const unlockRes = await unlockIdentityFromCache();
  if (!unlockRes.ok) return { ok: false, dryRun, lockLen: lock.length, summary: `identity locked: ${unlockRes.error.kind}` };
  const { identityPk } = getIdentitySnapshot();
  const identityLock = buildP2pkhLock(pubkeyToHash160(identityPk));
  const outValue = fundSats - feeSats;

  // Helper: build the AUTH-test spend given the funding UTXO. Keep BOTH the EF
  // (for inspection) and the raw tx (for the BEEF package we actually broadcast).
  const buildSpend = (fundTxid: Uint8Array, fundVout: number): { efTx: Uint8Array; rawTx: Uint8Array; txid: Uint8Array; preimage: Uint8Array } => {
    const outputs: TxOutput[] = [{ script: identityLock, satoshis: outValue }];
    const sighashInputs: TxInput[] = [{ txid: fundTxid, vout: fundVout, value: fundSats, script: lock, sequence: 0xffffffff }];
    const preimage = buildSighashPreimage(sighashInputs, outputs, 0);
    const unlockScript = compile([pushBytes(preimage)]); // witness = push(preimage)
    const efInputs: EFInput[] = [{ txid: fundTxid, vout: fundVout, unlockScript, sequence: 0xffffffff, sourceValue: fundSats, sourceLock: lock }];
    const { efTx, rawTx, txid } = serializeEFTx(efInputs, outputs);
    return { efTx, rawTx, txid, preimage };
  };

  if (dryRun) {
    const placeholder = new Uint8Array(32).fill(0xaa);
    const s = buildSpend(placeholder, 0);
    return {
      ok: true, dryRun: true, lockLen: lock.length,
      spendTxid: hexFromBytes(reverseTxid(s.txid)),
      efTxHex: hexFromBytes(s.efTx),
      summary: `DRY-RUN — auth-only lock ${lock.length} bytes; sample spend built (preimage ${s.preimage.length} B, ` +
        `out ${outValue} sats to identity, fee ${feeSats}). Confirm to fund ${fundSats} sats + broadcast on mainnet.`,
    };
  }

  // ── Fund the auth-only output via Metanet, then spend it with the preimage. ──
  let fundTxid: Uint8Array, fundVout: number, fundBeef: Uint8Array;
  try {
    const funded = await metanetCreateAction(
      [{ lockingScript: hexFromBytes(lock), satoshis: Number(fundSats), outputDescription: 'pushtx auth test' }],
      'Semantos OP_PUSH_TX auth test — fund',
      base,
    );
    const parsed = parseBeef(funded.beef);
    const entry = parsed.txs.find((t) => arrayEqual(t.txid, funded.txid)) ?? parsed.txs.at(-1)!;
    const found = findOutputVout(entry.rawTx, lock);
    if (!found) throw new Error('auth-test output not found in funding tx');
    fundTxid = funded.txid; fundVout = found.vout; fundBeef = funded.beef;
  } catch (e) {
    return { ok: false, dryRun: false, lockLen: lock.length, summary: `Fund FAILED — Metanet at ${base}: ${(e as Error).message}` };
  }

  const spend = buildSpend(fundTxid, fundVout);
  const fundTxidDisplay = hexFromBytes(reverseTxid(fundTxid));
  const spendTxidDisplay = hexFromBytes(reverseTxid(spend.txid));

  // Broadcast the funding tx + the spend as one BEEF package (the funding tx is
  // unconfirmed; createAction signed but did not send it).
  const beef = buildBeefV1(fundBeef, spend.rawTx, spend.txid);
  const bcast = await broadcastToArc(beef, arcOpts);
  return {
    ok: bcast.ok,
    dryRun: false,
    lockLen: lock.length,
    fundTxid: fundTxidDisplay,
    fundVout,
    spendTxid: spendTxidDisplay,
    efTxHex: hexFromBytes(spend.efTx),
    broadcastTxid: bcast.ok ? bcast.txid : undefined,
    summary: bcast.ok
      ? `✓ AUTH SPEND BROADCAST — spend ${spendTxidDisplay} (from fund ${fundTxidDisplay}:${fundVout}). ` +
        `If it CONFIRMS, OP_PUSH_TX works on mainnet and the full covenant is high-confidence. ARC ack: ${bcast.txid}`
      : `✗ AUTH spend rejected: ${bcast.reason} — this is the signal that the OP_PUSH_TX wiring needs adjusting (no covenant funds at risk; only this test's fee).`,
  };
}

```
