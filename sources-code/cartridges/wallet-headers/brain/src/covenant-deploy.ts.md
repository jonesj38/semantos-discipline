---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/covenant-deploy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.653693+00:00
---

# cartridges/wallet-headers/brain/src/covenant-deploy.ts

```ts
// covenant-deploy.ts — build the transactions that deploy and advance the MNCA
// covenant on-chain. NO broadcasting and NO key handling here: this only
// assembles bytes. The operator funds (Metanet createAction) and broadcasts
// (ARC). See tile-covenant.ts for the locking script itself.
//
// Two steps:
//   1. GENESIS — create the first covenant UTXO. The output script is the
//      covenant carrying a seed 3×3 region; fund it via Metanet createAction
//      (exactly like the mainnet pushdrop anchor).
//   2. SPEND   — advance the cellular automaton one tick: spend the covenant
//      UTXO into a new covenant output carrying the evolved region. The
//      unlocking script is just the BIP143 sighash preimage; the covenant's
//      AUTH clause checks it is authentic, TRANSITION recomputes the next
//      state, and BIND verifies the new output is this same covenant evolved.
//
// VALUE-PRESERVING: BIND reconstructs the next output using the INPUT's value,
// so the covenant output must keep the same satoshis. The fee therefore comes
// from a separate, already-signed funding input (extraInputs) — the covenant
// spend has exactly ONE output (BIND assumes a single output / hashOutputs).

import { pushBytes, compile } from './script-macro';
import { compileCovenantScript, type RuleParams, DEFAULT_RULE } from './tile-covenant';
import {
  buildSighashPreimage, serializeRawTx, type TxInput, type TxOutput,
} from './tx-builder';

const CENTRE = 4;
const NEIGHBOURS = [0, 1, 2, 3, 5, 6, 7, 8] as const;

function clampU8(v: number): number {
  return v < 0 ? 0 : v > 255 ? 255 : v;
}

/** The per-cell rule, identical to compileCellRule / mnca_tile / tile.ts. */
function applyRule(self: number, alive: number, p: RuleParams): number {
  const isAlive = self >= p.aliveThreshold;
  let delta = isAlive
    ? (alive >= p.surviveLo && alive <= p.surviveHi ? p.growStep : -p.decayStep)
    : (alive >= p.birthLo && alive <= p.birthHi ? p.growStep : -p.decayStep);
  if (alive >= p.outerBoost) delta += p.growStep;
  return clampU8(self + delta);
}

/**
 * Evolve a 3×3 region one tick (radius-1 — inner == outer neighbourhood),
 * matching `compileRegionToNextCentre` in Script exactly. Only the centre
 * changes (the ring is the covenant's halo, refreshed off-chain).
 */
export function evolveRegion(region: Uint8Array, params: RuleParams = DEFAULT_RULE): Uint8Array {
  if (region.length !== 9) throw new Error(`evolveRegion: region must be 9 bytes, got ${region.length}`);
  let alive = 0;
  for (const i of NEIGHBOURS) if (region[i]! >= params.aliveThreshold) alive++;
  const next = new Uint8Array(region);
  next[CENTRE] = applyRule(region[CENTRE]!, alive, params);
  return next;
}

/**
 * The GENESIS output: the covenant carrying `seedRegion`, to be created with
 * the given satoshis. Pass to Metanet createAction as
 * `{ script: toHex(script), satoshis }` (lockingScript / custom output).
 */
export function buildGenesisOutput(
  seedRegion: Uint8Array,
  satoshis: bigint,
  params: RuleParams = DEFAULT_RULE,
): TxOutput {
  return { script: compileCovenantScript(seedRegion, params), satoshis };
}

/** The covenant UTXO being advanced. */
export interface CovenantUtxo {
  txid: Uint8Array;   // 32 bytes, internal byte order
  vout: number;
  satoshis: bigint;   // covenant value (preserved across the spend)
  region: Uint8Array; // the 9-byte 3×3 state this UTXO carries
}

/** A pre-signed fee/funding input (covers the miner fee — covenant value is preserved). */
export interface FeeInput {
  txid: Uint8Array;
  vout: number;
  value: bigint;          // satoshis of this funding UTXO (for the sighash preimage)
  lockingScript: Uint8Array; // its locking script (scriptCode, for the preimage of THAT input if it self-signs)
  unlockScript: Uint8Array;  // already-built scriptSig (the operator signs this input)
  sequence?: number;
}

export interface CovenantSpend {
  rawTx: Uint8Array;     // standard serialization (for BEEF + txid)
  txid: Uint8Array;
  preimage: Uint8Array;  // the BIP143 preimage the covenant input is unlocked with
  nextRegion: Uint8Array;
  nextLock: Uint8Array;  // the evolved covenant locking script (the new UTXO)
}

/**
 * Build the SPEND that advances the covenant one tick. The covenant input
 * (index 0) is unlocked with its sighash preimage; `feeInputs` cover the fee.
 * Exactly one output (the evolved covenant) — required by BIND.
 */
export function buildCovenantSpend(opts: {
  utxo: CovenantUtxo;
  feeInputs?: FeeInput[];
  params?: RuleParams;
  version?: number;
  locktime?: number;
}): CovenantSpend {
  const params = opts.params ?? DEFAULT_RULE;
  const { utxo } = opts;
  const feeInputs = opts.feeInputs ?? [];
  const sequence = 0xffffffff;

  const nextRegion = evolveRegion(utxo.region, params);
  const inputLock = compileCovenantScript(utxo.region, params); // = scriptCode of the covenant input
  const nextLock = compileCovenantScript(nextRegion, params);

  // Single, value-preserving output (BIND reconstructs it from the input value).
  const outputs: TxOutput[] = [{ script: nextLock, satoshis: utxo.satoshis }];

  // Sighash preimage for the covenant input (index 0).
  const sighashInputs: TxInput[] = [
    { txid: utxo.txid, vout: utxo.vout, value: utxo.satoshis, script: inputLock, sequence },
    ...feeInputs.map((f) => ({
      txid: f.txid, vout: f.vout, value: f.value, script: f.lockingScript, sequence: f.sequence ?? sequence,
    })),
  ];
  const preimage = buildSighashPreimage(sighashInputs, outputs, 0, opts.version ?? 1, opts.locktime ?? 0);

  // Covenant unlocking script is simply the preimage push.
  const covenantUnlock = compile([pushBytes(preimage)]);

  const txInputs = [
    { txid: utxo.txid, vout: utxo.vout, unlockScript: covenantUnlock, sequence },
    ...feeInputs.map((f) => ({ txid: f.txid, vout: f.vout, unlockScript: f.unlockScript, sequence: f.sequence ?? sequence })),
  ];
  const { rawTx, txid } = serializeRawTx(txInputs, outputs, opts.version ?? 1, opts.locktime ?? 0);
  return { rawTx, txid, preimage, nextRegion, nextLock };
}

```
