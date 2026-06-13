---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/chain-broadcast/chain-broadcast/src/cell-tx-builder.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.519793+00:00
---

# packages/chain-broadcast/chain-broadcast/src/cell-tx-builder.ts

```ts
/**
 * CellTxBuilder — pure BSV transaction construction.
 *
 * Five builders, each returning a signed Transaction + metadata. No I/O, no
 * broadcast — downstream services (MapiBroadcaster) handle submission, and
 * composition (ChainBroadcaster facade) handles UTXO recycling and BEEF
 * merging.
 *
 *   1. buildPreSplit   — fan-out tx (1 input, N outputs + optional change)
 *   2. buildCellToken  — CellToken creation (BRC-48 PushDrop)
 *   3. buildTransition — CellToken state transition (PushDrop custom sign)
 *   4. buildOpReturn   — OP_RETURN anchor tx
 *   5. buildSweep      — multi-input sweep to an external address
 *
 * This file is the @bsv/sdk concentration point inside chain-broadcast. The
 * package's Signer-seam policy differs from session-protocol's: here we hold
 * a `PrivateKey` directly because @bsv/sdk unlock templates call `.sign()`
 * on the PrivateKey during preimage construction — abstracting over it
 * would mean reimplementing the sighash math, not injecting a seam.
 *
 * Extracted from the hackathon `DirectBroadcastEngine` at
 * todriguez/hackathon-submission:src/agent/direct-broadcast-engine.ts@496ee8f
 * (methods `preSplit`, `createCellToken`, `transitionCellToken`,
 * `anchorOpReturn`, `sweepAll` without broadcast orchestration).
 */

import {
  Hash,
  LockingScript,
  P2PKH,
  PrivateKey,
  PublicKey,
  Signature,
  Transaction,
  TransactionSignature,
  UnlockingScript,
} from "@bsv/sdk";
import { CellToken } from "@semantos/protocol-types/cell-token";
import type { FundingUtxo } from "./chain-tip-manager.js";

// ── Config & types ─────────────────────────────────────────

export interface CellTxBuilderConfig {
  /** Signing key — all built txs are signed with this. */
  privateKey: PrivateKey;
  /** Derived from privateKey if omitted. */
  publicKey?: PublicKey;
  /** Fee rate in sats/byte. TAAL default is 0.1 (100 sats/KB). */
  feeRate?: number;
  /** Absolute floor fee in sats. Default 135. */
  minFee?: number;
  /** Sats per CellToken output. Default 1. */
  cellSatoshis?: number;
  /** Sats per pre-split output. Default 500. */
  splitSatoshis?: number;
}

/** A built (and signed) transaction plus the metadata callers need downstream. */
export interface BuiltTx {
  tx: Transaction;
  txid: string;
  /** Estimated size in bytes (pre-serialisation estimate, not tx.toHex length). */
  estBytes: number;
  /** Fee actually paid. */
  fee: number;
  /**
   * The change output that recycles back into the funding pool, if any.
   * Callers that maintain a pool use this to append back into it.
   */
  change?: {
    vout: number;
    satoshis: number;
  };
}

export interface BuiltPreSplit extends BuiltTx {
  /** The per-output UTXOs the split produced, ready to ingest into a pool. */
  splits: FundingUtxo[];
}

const DEFAULT_FEE_RATE = 0.1;
const DEFAULT_MIN_FEE = 135;
const DEFAULT_CELL_SATS = 1;
const DEFAULT_SPLIT_SATS = 500;
const DUST_LIMIT = 546;

// Transaction-size constants (empirical averages from hackathon measurements).
const OVERHEAD_BYTES = 10;
const P2PKH_INPUT_BYTES = 148;
const P2PKH_OUTPUT_BYTES = 34;
// CellToken output is ~1,153 bytes (header + payload + path + hash + pubkey + opcodes)
const CELL_OUTPUT_BYTES = 1153;
// PushDrop custom input with 73-byte sig ≈ 114 bytes
const PUSHDROP_INPUT_BYTES = 114;

export class CellTxBuilder {
  private readonly privateKey: PrivateKey;
  private readonly publicKey: PublicKey;
  private readonly feeRate: number;
  private readonly minFee: number;
  private readonly cellSatoshis: number;
  private readonly splitSatoshis: number;

  constructor(config: CellTxBuilderConfig) {
    this.privateKey = config.privateKey;
    this.publicKey = config.publicKey ?? this.privateKey.toPublicKey();
    this.feeRate = config.feeRate ?? DEFAULT_FEE_RATE;
    this.minFee = config.minFee ?? DEFAULT_MIN_FEE;
    this.cellSatoshis = config.cellSatoshis ?? DEFAULT_CELL_SATS;
    this.splitSatoshis = config.splitSatoshis ?? DEFAULT_SPLIT_SATS;
  }

  getFundingAddress(): string {
    return this.publicKey.toAddress();
  }

  getPublicKey(): PublicKey {
    return this.publicKey;
  }

  // ── Builders ───────────────────────────────────────────

  /**
   * Fan-out a single funding UTXO into N splits of `splitSatoshis` each.
   * Returns the signed tx plus the resulting per-output `FundingUtxo`s,
   * ready to feed into a `ChainTipManager`.
   *
   * When `count` is omitted the splitter picks the maximum N that fits
   * within the input value minus fee.
   */
  async buildPreSplit(
    funding: FundingUtxo,
    opts?: { count?: number; streamCount?: number },
  ): Promise<BuiltPreSplit> {
    const streamCount = opts?.streamCount ?? 1;

    const estimateFee = (numOutputs: number) =>
      Math.max(
        this.minFee,
        Math.ceil(
          (OVERHEAD_BYTES +
            P2PKH_INPUT_BYTES +
            P2PKH_OUTPUT_BYTES * (numOutputs + 1)) *
            this.feeRate,
        ),
      );
    const maxSplitsByFee = Math.floor(
      (funding.satoshis - estimateFee(1)) /
        (this.splitSatoshis + Math.ceil(P2PKH_OUTPUT_BYTES * this.feeRate)),
    );
    const splitsCount = opts?.count
      ? Math.min(opts.count, maxSplitsByFee)
      : Math.min(maxSplitsByFee, streamCount * 200);

    if (splitsCount < streamCount) {
      const minSats =
        streamCount * this.splitSatoshis + estimateFee(streamCount);
      throw new Error(
        `Not enough funding for ${streamCount} streams. Need ≥ ${minSats} sats, got ${funding.satoshis}.`,
      );
    }
    const fee = estimateFee(splitsCount);

    const p2pkh = new P2PKH();
    const lockingScript = p2pkh.lock(this.publicKey.toAddress());
    const tx = new Transaction();

    this.addFundingInput(tx, p2pkh, funding, lockingScript);

    for (let i = 0; i < splitsCount; i++) {
      tx.addOutput({ lockingScript, satoshis: this.splitSatoshis });
    }

    const totalOut = splitsCount * this.splitSatoshis;
    const change = funding.satoshis - totalOut - fee;
    if (change > DUST_LIMIT) {
      tx.addOutput({ lockingScript, satoshis: change });
    }

    await tx.sign();
    const txid = tx.id("hex") as string;
    const estBytes = Math.ceil(tx.toHex().length / 2);

    const splits: FundingUtxo[] = [];
    for (let i = 0; i < splitsCount; i++) {
      splits.push({
        txid,
        vout: i,
        satoshis: this.splitSatoshis,
        sourceTx: tx,
      });
    }

    return {
      tx,
      txid,
      estBytes,
      fee,
      splits,
      change:
        change > DUST_LIMIT
          ? { vout: splitsCount, satoshis: change }
          : undefined,
    };
  }

  /**
   * Build a CellToken creation tx: one funding input → 1 CellToken output
   * (1 sat) + optional change back to the funding address.
   */
  async buildCellToken(
    funding: FundingUtxo,
    cellBytes: Uint8Array,
    semanticPath: string,
    contentHash: Uint8Array,
  ): Promise<BuiltTx> {
    const cellLock = CellToken.createOutputScript(
      cellBytes,
      semanticPath,
      contentHash,
      this.publicKey,
    );
    const p2pkh = new P2PKH();
    const fundingLock = p2pkh.lock(this.publicKey.toAddress());

    const tx = new Transaction();
    this.addFundingInput(tx, p2pkh, funding, fundingLock);

    tx.addOutput({ lockingScript: cellLock, satoshis: this.cellSatoshis });

    const estBytes =
      OVERHEAD_BYTES +
      P2PKH_INPUT_BYTES +
      CELL_OUTPUT_BYTES +
      P2PKH_OUTPUT_BYTES;
    const fee = Math.max(this.minFee, Math.ceil(estBytes * this.feeRate));
    const change = funding.satoshis - this.cellSatoshis - fee;
    let changeRec: BuiltTx["change"];
    if (change > 0) {
      tx.addOutput({ lockingScript: fundingLock, satoshis: change });
      changeRec = { vout: 1, satoshis: change };
    }

    await tx.sign();
    const txid = tx.id("hex") as string;
    return { tx, txid, estBytes, fee, change: changeRec };
  }

  /**
   * Build a CellToken state transition — spends the previous CellToken
   * (input 0) with a custom PushDrop unlock, funds the miner fee from
   * `funding` (input 1), and emits a new CellToken output (vout 0) plus
   * change (vout 1).
   *
   * `prevStateSequence` encodes the previous state version on input 0's
   * nSequence so the Bitcoin-level tx is self-describing (input says
   * "replacing state v(N-1)"). Clamped to `< 0xFFFFFFFF`.
   */
  async buildTransition(params: {
    funding: FundingUtxo;
    prevCellTxid: string;
    prevCellVout: number;
    prevCellTx: Transaction;
    newCellBytes: Uint8Array;
    semanticPath: string;
    contentHash: Uint8Array;
    prevStateSequence?: number;
  }): Promise<BuiltTx> {
    const {
      funding,
      prevCellTxid,
      prevCellVout,
      prevCellTx,
      newCellBytes,
      semanticPath,
      contentHash,
      prevStateSequence,
    } = params;

    const newLock = CellToken.createOutputScript(
      newCellBytes,
      semanticPath,
      contentHash,
      this.publicKey,
    );
    const signatureScope =
      TransactionSignature.SIGHASH_FORKID | TransactionSignature.SIGHASH_ALL;

    const p2pkh = new P2PKH();
    const tx = new Transaction();

    const clampedSeq =
      typeof prevStateSequence === "number"
        ? Math.max(0, Math.min(prevStateSequence, 0xfffffffe))
        : undefined;
    const privateKey = this.privateKey;
    tx.addInput({
      sourceTXID: prevCellTxid,
      sourceOutputIndex: prevCellVout,
      sourceTransaction: prevCellTx,
      ...(clampedSeq !== undefined ? { sequence: clampedSeq } : {}),
      unlockingScriptTemplate: {
        sign: async (txIn: Transaction, inputIndex: number) => {
          const preimage = txIn.preimage(inputIndex, signatureScope);
          const preimageHash = Hash.sha256(preimage);
          const sig = privateKey.sign(preimageHash);
          const txSig = new TransactionSignature(
            sig.r,
            sig.s,
            signatureScope,
          );
          const sigForScript = txSig.toChecksigFormat();
          const chunks = [
            sigForScript.length <= 75
              ? {
                  op: sigForScript.length,
                  data: Array.from(sigForScript),
                }
              : { op: 0x4c, data: Array.from(sigForScript) },
          ];
          return new UnlockingScript(chunks);
        },
        estimateLength: async () => 73,
      },
    });

    const fundingLock = p2pkh.lock(this.publicKey.toAddress());
    this.addFundingInput(tx, p2pkh, funding, fundingLock);

    tx.addOutput({ lockingScript: newLock, satoshis: this.cellSatoshis });

    const estBytes =
      OVERHEAD_BYTES +
      PUSHDROP_INPUT_BYTES +
      P2PKH_INPUT_BYTES +
      CELL_OUTPUT_BYTES +
      P2PKH_OUTPUT_BYTES;
    const fee = Math.max(this.minFee, Math.ceil(estBytes * this.feeRate));
    const totalIn =
      Number(prevCellTx.outputs[prevCellVout]!.satoshis) + funding.satoshis;
    const change = totalIn - this.cellSatoshis - fee;
    let changeRec: BuiltTx["change"];
    if (change > 0) {
      tx.addOutput({ lockingScript: fundingLock, satoshis: change });
      changeRec = { vout: 1, satoshis: change };
    }

    await tx.sign();
    const txid = tx.id("hex") as string;
    return { tx, txid, estBytes, fee, change: changeRec };
  }

  /**
   * Build an OP_RETURN anchor tx: one funding input → OP_RETURN(payload)
   * (0 sats) + change.
   */
  async buildOpReturn(
    funding: FundingUtxo,
    payload: string | Uint8Array,
  ): Promise<BuiltTx> {
    const payloadBytes = Array.from(
      typeof payload === "string"
        ? new TextEncoder().encode(payload)
        : payload,
    );
    const opReturnScript = new LockingScript([
      { op: 0 }, // OP_FALSE
      { op: 0x6a }, // OP_RETURN
      payloadBytes.length <= 75
        ? { op: payloadBytes.length, data: payloadBytes }
        : payloadBytes.length <= 255
          ? { op: 0x4c, data: payloadBytes }
          : { op: 0x4d, data: payloadBytes },
    ]);

    const p2pkh = new P2PKH();
    const fundingLock = p2pkh.lock(this.publicKey.toAddress());
    const tx = new Transaction();
    this.addFundingInput(tx, p2pkh, funding, fundingLock);

    tx.addOutput({ lockingScript: opReturnScript, satoshis: 0 });

    const estBytes =
      OVERHEAD_BYTES +
      P2PKH_INPUT_BYTES +
      (payloadBytes.length + 12) +
      P2PKH_OUTPUT_BYTES;
    const fee = Math.max(this.minFee, Math.ceil(estBytes * this.feeRate));
    const change = funding.satoshis - fee;
    let changeRec: BuiltTx["change"];
    if (change > 0) {
      tx.addOutput({ lockingScript: fundingLock, satoshis: change });
      changeRec = { vout: 1, satoshis: change };
    }

    await tx.sign();
    const txid = tx.id("hex") as string;
    return { tx, txid, estBytes, fee, change: changeRec };
  }

  /**
   * Build a sweep tx: N P2PKH inputs → one P2PKH output at `toAddress`
   * minus fee. Returns `null` if the inputs don't cover the fee floor.
   */
  async buildSweep(
    utxos: FundingUtxo[],
    toAddress: string,
  ): Promise<BuiltTx | null> {
    if (utxos.length === 0) return null;

    const p2pkh = new P2PKH();
    const tx = new Transaction();
    const totalSats = utxos.reduce((s, u) => s + u.satoshis, 0);

    for (const utxo of utxos) {
      tx.addInput({
        sourceTXID: utxo.txid,
        sourceOutputIndex: utxo.vout,
        sourceTransaction: utxo.sourceTx,
        unlockingScriptTemplate: p2pkh.unlock(this.privateKey),
      });
    }

    const estBytes =
      OVERHEAD_BYTES +
      utxos.length * P2PKH_INPUT_BYTES +
      P2PKH_OUTPUT_BYTES;
    const fee = Math.max(this.minFee, Math.ceil(estBytes * this.feeRate));
    const outSats = totalSats - fee;
    if (outSats <= DUST_LIMIT) return null;

    tx.addOutput({
      lockingScript: p2pkh.lock(toAddress),
      satoshis: outSats,
    });
    await tx.sign();
    const txid = tx.id("hex") as string;
    return { tx, txid, estBytes, fee };
  }

  // ── Helpers ────────────────────────────────────────────

  /** Add a P2PKH funding input, choosing EF-mode if `sourceTx` is present. */
  private addFundingInput(
    tx: Transaction,
    p2pkh: P2PKH,
    funding: FundingUtxo,
    fundingLock: LockingScript,
  ): void {
    if (funding.sourceTx) {
      tx.addInput({
        sourceTXID: funding.txid,
        sourceOutputIndex: funding.vout,
        sourceTransaction: funding.sourceTx,
        unlockingScriptTemplate: p2pkh.unlock(this.privateKey),
      });
    } else {
      tx.addInput({
        sourceTXID: funding.txid,
        sourceOutputIndex: funding.vout,
        unlockingScriptTemplate: p2pkh.unlock(
          this.privateKey,
          "all",
          false,
          funding.satoshis,
          fundingLock,
        ),
      });
    }
  }
}

// ── Helpers re-exported for advanced callers ──────────────────

/** Compute the 32-byte SHA-256 preimage hash for a given input. */
export function preimageHashFor(
  tx: Transaction,
  inputIndex: number,
  scope = TransactionSignature.SIGHASH_FORKID |
    TransactionSignature.SIGHASH_ALL,
): number[] {
  const preimage = tx.preimage(inputIndex, scope);
  return Hash.sha256(preimage) as number[];
}

export { Signature };

```
