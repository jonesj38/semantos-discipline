---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/mesh-bsv-sink.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.646952+00:00
---

# cartridges/wallet-headers/brain/src/mesh-bsv-sink.ts

```ts
// mesh-bsv-sink.ts — anchor a computed MNCA cell (a pushdrop output) on BSV.
//
// Composes the existing wallet primitives:
//   • snapshot-anchor (protocol-types) produces the pushdrop locking script
//     `<cell> OP_DROP <leafPubkey> OP_CHECKSIG` + sat value (the AnchorPlan).
//   • tx-builder builds + signs the BSV transaction (funding input → pushdrop
//     output + change), BIP143/SIGHASH_FORKID.
//   • arc-broadcast POSTs the EF tx to mainnet ARC (arc.taal.com).
//
// ── KEY HANDLING ───────────────────────────────────────────────────────
// This module NEVER holds a private key. The funding input is signed via an
// injected `Funder.signSighash` callback — the real key stays in the wallet /
// vault (Tier-0, IndexedDB on Mac / eFuse on C6 / lmdb on Pi). Tests inject a
// throwaway key. The pushdrop OWNER is the fresh Tier-0 BRC-42 leaf already
// chosen in the AnchorPlan (so the wallet can re-derive + spend the anchored
// cell later).
//
// ── BUILD vs BROADCAST ─────────────────────────────────────────────────
// `buildAnchorTx` is pure construction (no network) — fully unit-testable.
// `broadcastAnchorTx` performs the live mainnet POST and MUST be invoked
// deliberately by the operator (it spends real sats). It is intentionally a
// separate call so building/inspecting a tx never moves money.

import {
  computeSighash,
  buildP2pkhUnlockScript,
  buildP2pkhLock,
  pubkeyToHash160,
  serializeEFTx,
  type TxInput,
  type TxOutput,
  type EFInput,
} from './tx-builder';
import { broadcastToArc, type BroadcastOptions } from './arc-broadcast';

/** The pushdrop output to anchor — structurally an AnchorPlan slice. */
export interface PushdropOutput {
  /** `<cell> OP_DROP <ownerPubkey> OP_CHECKSIG` locking-script bytes. */
  lockingScript: Uint8Array;
  /** Satoshis to lock into the anchor output (dust+; ~1 for a data carrier). */
  satoshis: bigint;
}

/** A P2PKH UTXO that funds the anchor + fee. */
export interface FundingUtxo {
  txid: Uint8Array; // 32 bytes, internal byte order
  vout: number;
  value: bigint; // satoshis available
}

/**
 * The funding identity. `signSighash` produces a low-S DER ECDSA signature
 * over the 32-byte BIP143 sighash. The private key lives behind this callback
 * — the wallet/vault provides it; this module never sees it.
 */
export interface Funder {
  /** 33-byte compressed pubkey controlling the funding UTXO. */
  pubkey: Uint8Array;
  signSighash(sighash: Uint8Array): Uint8Array; // DER signature (no sighash byte)
}

export interface BuildAnchorTxInput {
  anchor: PushdropOutput;
  funding: FundingUtxo;
  funder: Funder;
  /** Flat miner fee in satoshis (caller estimates; ~1 sat/byte → ~1100 sats for a 1063B pushdrop). */
  feeSats: bigint;
  /** Dust threshold below which change is dropped into the fee (default 1). */
  dustSats?: bigint;
}

export interface AnchorTx {
  /** Extended-format bytes — POST these to ARC. */
  efTx: Uint8Array;
  /** Standard bytes — for BEEF ancestry. */
  rawTx: Uint8Array;
  /** 32-byte txid (internal byte order). */
  txid: Uint8Array;
  /** Change returned to the funder (0 when swept into fee as dust). */
  changeSats: bigint;
}

/**
 * Build + sign the anchoring transaction. PURE — no network, moves no money.
 * Inputs: one funding P2PKH UTXO. Outputs: the pushdrop anchor, then change
 * back to the funder (omitted if below dust). Throws if funds are insufficient.
 */
export function buildAnchorTx(input: BuildAnchorTxInput): AnchorTx {
  const { anchor, funding, funder, feeSats } = input;
  const dust = input.dustSats ?? 1n;

  if (funder.pubkey.length !== 33) {
    throw new Error(`buildAnchorTx: funder.pubkey must be 33 bytes (got ${funder.pubkey.length})`);
  }
  if (anchor.satoshis <= 0n || feeSats < 0n) {
    throw new Error('buildAnchorTx: anchor.satoshis must be > 0 and feeSats >= 0');
  }

  const funderLock = buildP2pkhLock(pubkeyToHash160(funder.pubkey));
  const changeRaw = funding.value - anchor.satoshis - feeSats;
  if (changeRaw < 0n) {
    throw new Error(
      `buildAnchorTx: insufficient funding — have ${funding.value}, need ${anchor.satoshis + feeSats}`,
    );
  }
  // Sweep sub-dust change into the fee (no uneconomical change output).
  const changeSats = changeRaw >= dust ? changeRaw : 0n;

  const outputs: TxOutput[] = [{ script: anchor.lockingScript, satoshis: anchor.satoshis }];
  if (changeSats > 0n) outputs.push({ script: funderLock, satoshis: changeSats });

  const sequence = 0xffffffff;
  const sighashInputs: TxInput[] = [
    { txid: funding.txid, vout: funding.vout, value: funding.value, script: funderLock, sequence },
  ];
  const sighash = computeSighash(sighashInputs, outputs, 0);

  const derSig = funder.signSighash(sighash);
  const unlockScript = buildP2pkhUnlockScript(derSig, funder.pubkey);

  const efInputs: EFInput[] = [
    {
      txid: funding.txid,
      vout: funding.vout,
      unlockScript,
      sequence,
      sourceValue: funding.value,
      sourceLock: funderLock,
    },
  ];
  const { efTx, rawTx, txid } = serializeEFTx(efInputs, outputs);
  return { efTx, rawTx, txid, changeSats };
}

/**
 * Broadcast a built anchor tx to mainnet ARC. ⚠ This spends real sats — the
 * operator invokes it deliberately. Sends the EF bytes (ARC validates sigs
 * without a UTXO lookup). Returns the ARC txid or a failure reason.
 */
export async function broadcastAnchorTx(
  tx: AnchorTx,
  opts: BroadcastOptions = {},
): Promise<{ ok: true; txid: string } | { ok: false; reason: string }> {
  return broadcastToArc(tx.efTx, opts);
}

```
