---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/direct-broadcast/celltoken-tx-builder.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.783464+00:00
---

# archive/apps-poker-agent/src/direct-broadcast/celltoken-tx-builder.ts

```ts
/**
 * Pure tx builders for the direct-broadcast path.
 *
 * `createCellTokenTx` and `transitionCellTokenTx` return signed
 * `Transaction` objects ready to broadcast. They never touch the
 * UTXO pool atoms or the broadcaster — the facade owns IO. The
 * builders take a `LocalKeyPair` + `FundingUtxo` and return:
 *
 *   { tx, change }
 *
 * where `change` is the recycle UTXO the facade should push back
 * into the pool (or `null` if there's no change).
 */

import {
  type Transaction as TransactionType,
  Hash,
  P2PKH,
  Signature,
  Transaction,
  TransactionSignature,
  type LockingScript,
  type PrivateKey,
  type PublicKey,
} from '@bsv/sdk';

import { CellToken } from '../../../../core/protocol-types/src/cell-token';

import { FIXED_CELL_FEE, type FundingUtxo } from './types';

export interface BuildCreateOptions {
  privateKey: PrivateKey;
  publicKey: PublicKey;
  funding: FundingUtxo;
  cellBytes: Uint8Array;
  semanticPath: string;
  contentHash: Uint8Array;
  cellSatoshis: number;
}

export interface BuildResult {
  tx: TransactionType;
  /** Change recycle entry — `null` if there's no change to recycle. */
  change: FundingUtxo | null;
}

/**
 * Build + sign a CellToken creation tx. Output 0 is the 1-sat
 * CellToken; output 1 is the change recycle (if any).
 */
export async function createCellTokenTx(opts: BuildCreateOptions): Promise<BuildResult> {
  const cellLockingScript = CellToken.createOutputScript(
    opts.cellBytes,
    opts.semanticPath,
    opts.contentHash,
    opts.publicKey,
  );
  const p2pkh = new P2PKH();
  const tx = new Transaction();
  tx.addInput({
    sourceTXID: opts.funding.txid,
    sourceOutputIndex: opts.funding.vout,
    sourceTransaction: opts.funding.sourceTx,
    unlockingScriptTemplate: p2pkh.unlock(opts.privateKey),
  });
  tx.addOutput({ lockingScript: cellLockingScript, satoshis: opts.cellSatoshis });

  const change = opts.funding.satoshis - opts.cellSatoshis - FIXED_CELL_FEE;
  if (change > 0) {
    tx.addOutput({
      lockingScript: p2pkh.lock(opts.publicKey.toAddress()) as LockingScript,
      satoshis: change,
    });
  }
  await tx.sign();

  const txid = tx.id('hex') as string;
  return {
    tx,
    change:
      change > 0
        ? { txid, vout: 1, satoshis: change, sourceTx: tx }
        : null,
  };
}

export interface BuildTransitionOptions {
  privateKey: PrivateKey;
  publicKey: PublicKey;
  funding: FundingUtxo;
  prevCellTxid: string;
  prevCellVout: number;
  prevCellTx: TransactionType;
  newCellBytes: Uint8Array;
  semanticPath: string;
  contentHash: Uint8Array;
  cellSatoshis: number;
  /** Optional nSequence on the PushDrop input (state-version marker). */
  prevStateSequence?: number;
}

/**
 * Build + sign a CellToken state transition tx. Spends input 0
 * (PushDrop locked v(n)) + input 1 (funding); output 0 is v(n+1);
 * output 1 is recycled change.
 */
export async function transitionCellTokenTx(
  opts: BuildTransitionOptions,
): Promise<BuildResult> {
  const newLockingScript = CellToken.createOutputScript(
    opts.newCellBytes,
    opts.semanticPath,
    opts.contentHash,
    opts.publicKey,
  );
  const signatureScope =
    TransactionSignature.SIGHASH_FORKID | TransactionSignature.SIGHASH_ALL;
  const p2pkh = new P2PKH();
  const tx = new Transaction();
  const clampedSeq =
    typeof opts.prevStateSequence === 'number'
      ? Math.max(0, Math.min(opts.prevStateSequence, 0xfffffffe))
      : undefined;

  tx.addInput({
    sourceTXID: opts.prevCellTxid,
    sourceOutputIndex: opts.prevCellVout,
    sourceTransaction: opts.prevCellTx,
    ...(clampedSeq !== undefined ? { sequence: clampedSeq } : {}),
    unlockingScriptTemplate: makePushDropUnlock(opts.privateKey, signatureScope),
  });
  tx.addInput({
    sourceTXID: opts.funding.txid,
    sourceOutputIndex: opts.funding.vout,
    sourceTransaction: opts.funding.sourceTx,
    unlockingScriptTemplate: p2pkh.unlock(opts.privateKey),
  });

  tx.addOutput({ lockingScript: newLockingScript, satoshis: opts.cellSatoshis });

  const totalIn = Number(opts.prevCellTx.outputs[opts.prevCellVout].satoshis) + opts.funding.satoshis;
  const change = totalIn - opts.cellSatoshis - FIXED_CELL_FEE;
  if (change > 0) {
    tx.addOutput({
      lockingScript: p2pkh.lock(opts.publicKey.toAddress()) as LockingScript,
      satoshis: change,
    });
  }
  await tx.sign();

  const txid = tx.id('hex') as string;
  return {
    tx,
    change:
      change > 0
        ? { txid, vout: 1, satoshis: change, sourceTx: tx }
        : null,
  };
}

/**
 * Build the per-input unlock template the PushDrop spend needs.
 * Uses local-key signing so the tx never round-trips a wallet.
 */
function makePushDropUnlock(privateKey: PrivateKey, signatureScope: number) {
  return {
    sign: async (tx: TransactionType, inputIndex: number): Promise<any> => {
      const preimage = tx.preimage(inputIndex, signatureScope);
      const preimageHash = Hash.sha256(preimage);
      const sig = privateKey.sign(preimageHash);
      const txSig = new TransactionSignature(sig.r, sig.s, signatureScope);
      const sigForScript = txSig.toChecksigFormat();
      const chunks = [
        sigForScript.length <= 75
          ? { op: sigForScript.length, data: Array.from(sigForScript) }
          : { op: 0x4c, data: Array.from(sigForScript) },
      ];
      const { UnlockingScript: US } = await import('@bsv/sdk');
      return new US(chunks);
    },
    estimateLength: async (): Promise<number> => 73,
  };
}

```
