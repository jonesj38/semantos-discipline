---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/poker-state-machine/celltoken-signer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.767607+00:00
---

# archive/apps-poker-agent/src/poker-state-machine/celltoken-signer.ts

```ts
/**
 * Deferred-signing flow for CellToken transitions.
 *
 * Extracted from the legacy `transition()` so the operation is
 * isolated + testable. Steps:
 *
 *   1. `findOurInputIndex` — locate the v(n) UTXO inside the wallet's
 *      signable transaction (some wallets reorder inputs).
 *   2. `linkSourceTransaction` — attach the source tx to our input
 *      so `tx.preimage(...)` can compute the sighash.
 *   3. `createPushDropUnlock` — call `wallet.createSignature` with
 *      the preimage hash, then build the BRC-48 PushDrop unlocking
 *      script.
 *   4. `signAndFinalize` — `wallet.signAction` to broadcast +
 *      retrieve the final BEEF.
 *
 * The functions are kept independent so tests can drive each step
 * without involving the full @bsv/sdk runtime.
 */

import type { WalletClient } from '../../../../core/protocol-types/src/wallet-client';
import { toArray as beefToArray } from '../shared';

import { CELLTOKEN_COUNTERPARTY, CELLTOKEN_PROTOCOL } from './types';

// We can't statically import @bsv/sdk types without bringing the
// whole runtime in; the signer accepts the lazily-loaded module via
// a small contract.
export interface BsvLazy {
  Transaction: any;
  TransactionSignature: any;
  Signature: any;
  Hash: any;
}

export interface SignableInput {
  sourceTXID?: string;
  sourceTransaction?: { id(format: 'hex'): string } | undefined;
  sourceOutputIndex?: number;
}

export interface SignableTx {
  inputs: SignableInput[];
  preimage(index: number, scope: number): Uint8Array;
}

/**
 * Locate the input that spends our live UTXO. Falls back to index 0
 * if the wallet returned no recognizable matches (sufficient for
 * simple actions with a single non-change input).
 */
export function findOurInputIndex(
  tx: SignableTx,
  liveUtxoTxid: string,
): number {
  for (let i = 0; i < tx.inputs.length; i++) {
    const inp = tx.inputs[i];
    if (
      inp.sourceTXID === liveUtxoTxid ||
      inp.sourceTransaction?.id('hex') === liveUtxoTxid
    ) {
      return i;
    }
  }
  return 0;
}

/**
 * Attach the source transaction to a signable input so the preimage
 * computation has the source-output context. No-op if the input
 * already has a sourceTransaction.
 */
export function linkSourceTransaction(
  bsv: BsvLazy,
  input: SignableInput & { sourceTransaction?: any; sourceOutputIndex?: number },
  beef: number[] | string,
  vout: number,
): void {
  if (!input.sourceTransaction) {
    input.sourceTransaction = bsv.Transaction.fromAtomicBEEF(beefToArray(beef));
    input.sourceOutputIndex = vout;
  }
}

/**
 * Compute the sighash, ask the wallet for a bare signature with the
 * shared CellToken protocol params, and assemble the unlocking
 * script (just the signature for a PushDrop output — the CellToken
 * data was committed in the locking script).
 */
export async function createPushDropUnlock(opts: {
  bsv: BsvLazy;
  wallet: WalletClient;
  tx: SignableTx;
  ourInputIndex: number;
  keyID: string;
}): Promise<{ unlockingScriptHex: string }> {
  const { bsv, wallet, tx, ourInputIndex, keyID } = opts;
  const signatureScope =
    bsv.TransactionSignature.SIGHASH_FORKID | bsv.TransactionSignature.SIGHASH_ALL;
  const preimage = tx.preimage(ourInputIndex, signatureScope);
  const preimageHash = bsv.Hash.sha256(preimage);

  const { signature: bareSignature } = await wallet.createSignature({
    protocolID: CELLTOKEN_PROTOCOL,
    keyID,
    counterparty: CELLTOKEN_COUNTERPARTY,
    data: Array.from(preimageHash),
  });

  const sig = bsv.Signature.fromDER(bareSignature);
  const txSig = new bsv.TransactionSignature(sig.r, sig.s, signatureScope);
  const sigForScript = txSig.toChecksigFormat();
  const unlockingScriptHex = Buffer.from(
    new Uint8Array([sigForScript.length, ...Array.from(sigForScript)]),
  ).toString('hex');
  return { unlockingScriptHex };
}

/**
 * Submit the unlock script back to the wallet via `signAction` to
 * finalize + broadcast. Returns the final BEEF + txid the facade
 * needs to thread into the live UTXO atom.
 */
export async function signAndFinalize(opts: {
  wallet: WalletClient;
  reference: string;
  ourInputIndex: number;
  unlockingScriptHex: string;
  fallbackBeef: number[] | string;
}): Promise<{ txid: string; beef: number[] | string }> {
  const finalResult = await opts.wallet.signAction({
    reference: opts.reference,
    spends: {
      [opts.ourInputIndex]: { unlockingScript: opts.unlockingScriptHex },
    },
  });
  return {
    txid: finalResult.txid,
    beef: finalResult.tx ?? opts.fallbackBeef,
  };
}

```
