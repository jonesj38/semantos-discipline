---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/test-covenant-spend.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.657140+00:00
---

# cartridges/wallet-headers/brain/src/test-covenant-spend.ts

```ts
// test-covenant-spend.ts — advance the MNCA covenant one tick on mainnet.
//
// OPERATOR-RUN (browser). Spends an existing covenant UTXO into a new covenant
// output carrying the MNCA-evolved state. This is the LIVE test of the whole
// locking script — AUTH (OP_PUSH_TX) + TRANSITION + BIND — on a real node.
//
//   input 0  the covenant UTXO        unlock = push(BIP143 preimage)   [no key]
//   input 1  identity P2PKH (fee)      unlock = P2PKH sig (identitySk)
//   output 0 the evolved covenant      value = the covenant's value (preserved)
//
// Value-preserving (BIND pins the output value to the input), single output
// (BIND assumes one output). The fee comes from input 1, funded via Metanet.
// Extended Format → ARC validates with no BEEF ancestry.
//
// DRY-RUN by default; the operator clicks broadcast. MAX cap on the fee.

import * as secp from '@noble/secp256k1';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import { hmac } from '@noble/hashes/hmac';
import { encodeDer } from './der';
import { compileCovenantScript } from './tile-covenant';
import { evolveRegion } from './covenant-deploy';
import {
  buildP2pkhLock, buildP2pkhUnlockScript, pubkeyToHash160,
  buildSighashPreimage, computeSighash, serializeEFTx,
  type TxInput, type TxOutput, type EFInput,
} from './tx-builder';
import { compile, pushBytes } from './script-macro';
import { hexFromBytes, bytesFromHex, reverseTxid } from './beef-codec';
import { broadcastToArc, getArcTxStatus } from './arc-broadcast';
import { loadWallet, unlockIdentityFromCache, getIdentitySnapshot } from './wallet-ops';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

export interface CovenantSpendOptions {
  /** The covenant UTXO (and fee reserve) — both outputs of the genesis tx. */
  covTxid: string;       // display order
  covVout: number;
  covSats: number;
  regionHex: string;     // 18 hex — the 3×3 state this covenant carries
  feeVout: number;       // the fee-reserve output of the same genesis tx
  feeSats: number;
  confirm?: boolean;     // true = broadcast on mainnet. default false (dry-run).
  arcUrl?: string;
  arcApiKey?: string;
}

export interface CovenantSpendResult {
  ok: boolean;
  dryRun: boolean;
  regionHex?: string;
  nextRegionHex?: string;
  spendTxid?: string;    // the tick we built (display order)
  efTxHex?: string;
  broadcastTxid?: string;
  summary: string;
}

export async function runCovenantSpend(opts: CovenantSpendOptions): Promise<CovenantSpendResult> {
  const arcOpts = { arcUrl: opts.arcUrl ?? 'https://arc.taal.com', apiKey: opts.arcApiKey };
  const dryRun = !opts.confirm;

  if (!/^[0-9a-fA-F]{18}$/.test(opts.regionHex)) return { ok: false, dryRun, summary: 'regionHex must be 18 hex chars (9 bytes)' };
  if (!/^[0-9a-fA-F]{64}$/.test(opts.covTxid)) return { ok: false, dryRun, summary: 'covTxid must be 64 hex chars' };

  const region = bytesFromHex(opts.regionHex);
  const covLock = compileCovenantScript(region);
  const nextRegion = evolveRegion(region);
  const nextLock = compileCovenantScript(nextRegion);
  const covSats = BigInt(opts.covSats);
  const feeSats = BigInt(opts.feeSats);
  const output: TxOutput = { script: nextLock, satoshis: covSats }; // value-preserving, single output
  const txidInternal = reverseTxid(bytesFromHex(opts.covTxid));

  // Identity signs the fee-reserve input (the genesis 2nd output).
  const loadRes = await loadWallet();
  if (!loadRes.ok) return { ok: false, dryRun, summary: `wallet not ready: ${loadRes.error.kind}` };
  const unlockRes = await unlockIdentityFromCache();
  if (!unlockRes.ok) return { ok: false, dryRun, summary: `identity locked: ${unlockRes.error.kind}` };
  const { identityPk, identitySk } = getIdentitySnapshot();
  const identityLock = buildP2pkhLock(pubkeyToHash160(identityPk));

  const seq = 0xffffffff;
  const inputs: TxInput[] = [
    { txid: txidInternal, vout: opts.covVout, value: covSats, script: covLock, sequence: seq },
    { txid: txidInternal, vout: opts.feeVout, value: feeSats, script: identityLock, sequence: seq },
  ];
  // input 0 (covenant) — unlocked by its BIP143 preimage
  const preimage = buildSighashPreimage(inputs, [output], 0);
  const covUnlock = compile([pushBytes(preimage)]);
  // input 1 (fee reserve P2PKH) — signed by identity
  const feeSighash = computeSighash(inputs, [output], 1);
  const feeSig = secp.sign(feeSighash, identitySk).normalizeS();
  const feeUnlock = buildP2pkhUnlockScript(encodeDer(feeSig.r, feeSig.s), identityPk);

  const efInputs: EFInput[] = [
    { txid: txidInternal, vout: opts.covVout, unlockScript: covUnlock, sequence: seq, sourceValue: covSats, sourceLock: covLock },
    { txid: txidInternal, vout: opts.feeVout, unlockScript: feeUnlock, sequence: seq, sourceValue: feeSats, sourceLock: identityLock },
  ];
  const { efTx, rawTx, txid } = serializeEFTx(efInputs, [output]);
  const spendTxidDisplay = hexFromBytes(reverseTxid(txid));

  // Diagnostic: push the standard raw tx through WhatsOnChain too — its node
  // returns the real reject reason (consensus error vs. nonstandard relay policy)
  // which ARC's "ANNOUNCED_TO_NETWORK" hides.
  const tryWoc = async (): Promise<string> => {
    try {
      const res = await fetch('https://api.whatsonchain.com/v1/bsv/main/tx/raw', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ txhex: hexFromBytes(rawTx) }),
      });
      const body = await res.text();
      return `WoC ${res.status}: ${body.slice(0, 200)}`;
    } catch (e) { return `WoC error: ${(e as Error).message}`; }
  };

  if (dryRun) {
    return {
      ok: true, dryRun: true,
      regionHex: opts.regionHex, nextRegionHex: hexFromBytes(nextRegion),
      spendTxid: spendTxidDisplay,
      efTxHex: hexFromBytes(efTx),
      summary: `DRY-RUN — tick built: ${opts.regionHex} → ${hexFromBytes(nextRegion)} ` +
        `(centre ${region[4]} → ${nextRegion[4]}), covenant ${covSats} preserved, fee ${feeSats} (from genesis reserve). ` +
        `Broadcasts Extended Format (ARC requires EF) — both inputs' source script+value inline.`,
    };
  }

  // ARC requires Extended Format. EF carries each input's source script + value
  // inline, so ARC validates the covenant (AUTH+TRANSITION+BIND) without a UTXO
  // lookup or BEEF ancestry. The genesis is confirmed, so the inputs resolve.
  const bcast = await broadcastToArc(efTx, arcOpts);
  // ARC ack only means RECEIVED/ANNOUNCED — not network-accepted. Poll the real
  // status, and ALSO push to WoC for the node-level reject reason.
  const arc = await getArcTxStatus(spendTxidDisplay, arcOpts);
  const wocLine = await tryWoc();
  const arcLine = `ARC: ${bcast.ok ? (arc.status ?? 'accepted') : `rejected (${bcast.reason})`}${arc.detail ? ` — ${arc.detail}` : ''}`;
  // "already in the mempool" from WoC = our tx is already there (ARC put it) = accepted.
  const inMempool = wocLine.startsWith('WoC 200') || wocLine.includes('already in the mempool');
  const propagated = arc.status === 'SEEN_ON_NETWORK' || arc.status === 'MINED' || inMempool;
  return {
    ok: propagated,
    dryRun: false,
    regionHex: opts.regionHex, nextRegionHex: hexFromBytes(nextRegion),
    spendTxid: spendTxidDisplay,
    efTxHex: hexFromBytes(efTx),
    broadcastTxid: bcast.ok ? bcast.txid : undefined,
    summary: `tick ${opts.regionHex} → ${hexFromBytes(nextRegion)} (centre ${region[4]} → ${nextRegion[4]}), spend ${spendTxidDisplay}\n` +
      `  ${arcLine}\n  ${wocLine}\n` +
      (propagated
        ? `→ ACCEPTED by the network (in mempool). The covenant ran AUTH+TRANSITION+BIND on mainnet — ` +
          `the MNCA advanced a generation on-chain. Watch ${spendTxidDisplay} on WoC for confirmation.`
        : `→ NOT propagated. The WoC line above is the node's real verdict — ANNOUNCED_TO_NETWORK ≠ accepted. ` +
          `("non-mandatory…MINIMALDATA" = relay policy; "mandatory-script-verify" = a consensus script failure.)`),
  };
}

```
