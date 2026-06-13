---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/poker-state-machine/transition-flow.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.767017+00:00
---

# archive/apps-poker-agent/src/poker-state-machine/transition-flow.ts

```ts
/**
 * `transition` flow — extracted from the facade so the file stays
 * under the prompt-17 LOC ceiling.
 *
 * Spends the v(n) CellToken and creates v(n+1) locked to the next
 * pubkey. Handles both direct-sign and deferred-sign wallet paths;
 * the latter routes through `celltoken-signer.ts`.
 */

import { CellToken } from '../../../../core/protocol-types/src/cell-token';
import type { WalletClient } from '../../../../core/protocol-types/src/wallet-client';
import { toArray as beefToArray } from '../shared';

import { buildCell, semanticPath } from './cell-builder';
import {
  createPushDropUnlock,
  findOurInputIndex,
  linkSourceTransaction,
  signAndFinalize,
  type BsvLazy,
} from './celltoken-signer';
import { locateVout, sleep } from './tx-utils';
import { getLiveUtxo, setLiveUtxo } from './utxo-tracker';
import type { AnchorResult, HandStatePayload, LiveUtxo } from './types';

export interface TransitionFlowOptions {
  wallet: WalletClient;
  bsv: BsvLazy & { PublicKey: any };
  gameId: string;
  ownerId: Uint8Array;
  myPubKeyHex: string;
  keyID: string;
  /** Mutable version counter — caller increments before invocation. */
  cellVersion: number;
  settleDelayMs: number;
  log: (label: string, msg: string) => void;
}

export interface TransitionFlowResult {
  anchor: AnchorResult;
  /** Caller pulls the version forward + writes back into its field. */
  newCellVersion: number;
}

export async function runTransition(
  opts: TransitionFlowOptions,
  newState: HandStatePayload,
  lockNextTo?: string,
): Promise<TransitionFlowResult | null> {
  const live = getLiveUtxo(opts.gameId);
  if (!live) {
    opts.log('TRANSITION', '✗ No live UTXO — skipping');
    return null;
  }
  if (live.lockedToKey !== opts.myPubKeyHex) {
    opts.log('TRANSITION', `✗ UTXO locked to opponent — I cannot spend this. Waiting for their move.`);
    return null;
  }

  const nextKey = lockNextTo ?? opts.myPubKeyHex;
  const nextPubKey = opts.bsv.PublicKey.fromString(nextKey);

  const { cellBytes: v2CellBytes, contentHash: v2ContentHash } = await buildCell(newState, {
    ownerId: opts.ownerId,
    version: opts.cellVersion,
  });

  const v2LockingScript = CellToken.createOutputScript(
    v2CellBytes,
    semanticPath(newState),
    v2ContentHash,
    nextPubKey,
  );
  const v2ScriptHex = v2LockingScript.toHex();

  opts.log(
    'TRANSITION',
    `v${opts.cellVersion - 1} → v${opts.cellVersion}: ${newState.phase} | lock → ${
      nextKey === opts.myPubKeyHex ? 'ME' : 'OPPONENT'
    }`,
  );

  const { v1Outpoint, v1Satoshis, v1LockingScript } = await locateV1(opts, live);
  opts.log('TRANSITION', `Spending ${v1Outpoint}...`);
  const tCreate = Date.now();

  const transResult = await opts.wallet.createAction({
    description: `Hand #${newState.handNumber} → ${newState.phase}`,
    labels: ['semantos-poker', 'state-transition'],
    inputBEEF: live.beef,
    inputs: [
      {
        outpoint: v1Outpoint,
        inputDescription: `Spend hand state v${opts.cellVersion - 1}`,
        unlockingScriptLength: 73,
        sourceSatoshis: v1Satoshis,
        sourceLockingScript: v1LockingScript,
      },
    ],
    outputs: [
      {
        lockingScript: v2ScriptHex,
        satoshis: 1,
        outputDescription: `Hand state v${opts.cellVersion}: ${newState.phase}`,
        basket: 'semantos-poker',
        tags: ['poker', 'hand-state', `hand-${newState.handNumber}`, newState.phase],
      },
    ],
  });

  opts.log('TRANSITION', `createAction [${Date.now() - tCreate}ms] keys: ${Object.keys(transResult).join(', ')}`);

  const { finalTxid, finalBeef } = await finalizeTx(opts, transResult, live, tCreate);

  const beefArray = beefToArray(finalBeef as string | number[]);
  const v2Vout = locateVout(opts.bsv, beefArray, v2ScriptHex);

  setLiveUtxo(opts.gameId, {
    txid: finalTxid,
    vout: v2Vout,
    satoshis: 1,
    lockingScript: v2ScriptHex,
    beef: beefArray,
    version: opts.cellVersion,
    cellBytes: v2CellBytes,
    lockedToKey: nextKey,
  });

  const anchor: AnchorResult = {
    txid: finalTxid,
    eventType: `transition-${newState.phase}`,
    isLinear: true,
    phase: newState.phase,
    beef: beefArray,
    vout: v2Vout,
    lockingScript: v2ScriptHex,
    cellVersion: opts.cellVersion,
  };
  opts.log('WoC', `https://whatsonchain.com/tx/${finalTxid}`);

  if (opts.settleDelayMs > 0) await sleep(opts.settleDelayMs);
  return { anchor, newCellVersion: opts.cellVersion };
}

async function locateV1(
  opts: TransitionFlowOptions,
  live: LiveUtxo,
): Promise<{ v1Outpoint: string; v1Satoshis: number; v1LockingScript: string }> {
  let v1Outpoint = `${live.txid}.${live.vout}`;
  let v1Satoshis = live.satoshis;
  let v1LockingScript = live.lockingScript;
  try {
    const outputs = await opts.wallet.listOutputs('semantos-poker', ['poker', 'hand-state'], 'locking scripts');
    opts.log('UTXO', `Basket: ${outputs.length} output(s)`);
    for (const out of outputs) {
      if (out.outpoint?.includes(live.txid)) {
        v1Outpoint = out.outpoint;
        v1Satoshis = out.satoshis ?? 1;
        v1LockingScript = out.lockingScript ?? live.lockingScript;
        opts.log('UTXO', `Found in basket: ${v1Outpoint}`);
        break;
      }
    }
  } catch (err) {
    opts.log('UTXO', `listOutputs: ${(err as Error).message} — using cached outpoint`);
  }
  return { v1Outpoint, v1Satoshis, v1LockingScript };
}

async function finalizeTx(
  opts: TransitionFlowOptions,
  transResult: { txid?: string; tx?: number[] | string; signableTransaction?: unknown },
  live: LiveUtxo,
  tCreate: number,
): Promise<{ finalTxid: string; finalBeef: number[] | string }> {
  if (transResult.txid && !transResult.signableTransaction) {
    const finalTxid = transResult.txid;
    const finalBeef = transResult.tx ?? [];
    opts.log('TRANSITION', `✓ Direct sign → ${finalTxid.slice(0, 16)}...`);
    return { finalTxid, finalBeef };
  }

  if (!transResult.signableTransaction) {
    throw new Error('Wallet returned neither txid nor signableTransaction');
  }

  opts.log('TRANSITION', 'Deferred signing — computing sighash for PushDrop unlock...');
  const signable = transResult.signableTransaction;
  const reference = typeof signable === 'string' ? signable : (signable as { reference: string }).reference;
  const signableTxBeef = typeof signable === 'string' ? undefined : (signable as { tx: number[] | string }).tx;

  let txToSign: any;
  if (signableTxBeef) {
    txToSign = opts.bsv.Transaction.fromAtomicBEEF(beefToArray(signableTxBeef));
  } else if (transResult.tx) {
    txToSign = opts.bsv.Transaction.fromAtomicBEEF(beefToArray(transResult.tx as string | number[]));
  }
  if (!txToSign) throw new Error('No tx data for deferred signing');

  const ourInputIndex = findOurInputIndex(txToSign, live.txid);
  const inp = txToSign.inputs[ourInputIndex];
  linkSourceTransaction(opts.bsv, inp, live.beef, live.vout);

  const { unlockingScriptHex } = await createPushDropUnlock({
    bsv: opts.bsv,
    wallet: opts.wallet,
    tx: txToSign,
    ourInputIndex,
    keyID: opts.keyID,
  });

  const tSign = Date.now();
  const finalized = await signAndFinalize({
    wallet: opts.wallet,
    reference,
    ourInputIndex,
    unlockingScriptHex,
    fallbackBeef: transResult.tx ?? [],
  });
  let finalTxid = finalized.txid;
  const finalBeef = finalized.beef;

  if (!finalTxid && finalBeef) {
    const v2Tx = opts.bsv.Transaction.fromAtomicBEEF(beefToArray(finalBeef as string | number[]));
    finalTxid = v2Tx.id('hex');
  }

  opts.log(
    'TRANSITION',
    `✓ Deferred sign → ${finalTxid?.slice(0, 16) ?? '(pending)'}... [create=${Date.now() - tCreate}ms sign=${
      Date.now() - tSign
    }ms]`,
  );
  return { finalTxid, finalBeef };
}


```
