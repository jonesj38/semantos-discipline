---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/poker-state-machine/create-hand-flow.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.766408+00:00
---

# archive/apps-poker-agent/src/poker-state-machine/create-hand-flow.ts

```ts
/**
 * `createHandToken` flow — extracted from the facade so the file
 * stays under the prompt-17 LOC ceiling.
 *
 * Builds the v1 CellToken for a fresh poker hand: derive the cell
 * bytes, lock them to the target pubkey, broadcast via the wallet,
 * find the resulting vout, and seed the live-UTXO atom.
 */

import { CellToken } from '../../../../core/protocol-types/src/cell-token';
import type { WalletClient } from '../../../../core/protocol-types/src/wallet-client';
import { toArray as beefToArray } from '../shared';

import { buildCell, semanticPath } from './cell-builder';
import type { BsvLazy } from './celltoken-signer';
import { locateVout, sleep } from './tx-utils';
import { setLiveUtxo } from './utxo-tracker';
import type { AnchorResult, HandStatePayload } from './types';

export interface CreateHandFlowOptions {
  wallet: WalletClient;
  bsv: BsvLazy & { PublicKey: any };
  gameId: string;
  ownerId: Uint8Array;
  myPubKeyHex: string;
  /** Settle delay applied after the linear write completes (ms). */
  settleDelayMs: number;
  log: (label: string, msg: string) => void;
}

/**
 * Returns the AnchorResult for the v1 token. On success the
 * `liveUtxoAtom` for `gameId` is populated. On wallet failure
 * (no BEEF returned) the function returns `null` and leaves the
 * atom untouched.
 */
export async function runCreateHandToken(
  opts: CreateHandFlowOptions,
  state: HandStatePayload,
  lockToKey?: string,
): Promise<AnchorResult | null> {
  const targetKey = lockToKey ?? opts.myPubKeyHex;
  const { cellBytes, contentHash } = await buildCell(state, { ownerId: opts.ownerId });
  const lockPubKey = opts.bsv.PublicKey.fromString(targetKey);

  const lockingScript = CellToken.createOutputScript(
    cellBytes,
    semanticPath(state),
    contentHash,
    lockPubKey,
  );
  const scriptHex = lockingScript.toHex();
  opts.log(
    'CREATE',
    `Hand #${state.handNumber} v1 — locked to ${
      targetKey === opts.myPubKeyHex ? 'ME' : 'OPPONENT'
    } (${targetKey.slice(0, 16)}...)`,
  );

  const t0 = Date.now();
  const result = await opts.wallet.createAction({
    description: `Poker hand #${state.handNumber} (${state.phase})`,
    labels: ['semantos-poker', 'hand-state'],
    outputs: [
      {
        lockingScript: scriptHex,
        satoshis: 1,
        outputDescription: `CellToken: ${semanticPath(state)}`,
        basket: 'semantos-poker',
        tags: ['poker', 'hand-state', `hand-${state.handNumber}`],
      },
    ],
  });

  const beef = result.tx;
  if (!beef) {
    opts.log('CREATE', '✗ No BEEF in response — cannot do transitions');
    return null;
  }

  const beefArray = beefToArray(beef as string | number[]);
  const vout = locateVout(opts.bsv, beefArray, scriptHex);

  setLiveUtxo(opts.gameId, {
    txid: result.txid,
    vout,
    satoshis: 1,
    lockingScript: scriptHex,
    beef: beefArray,
    version: 1,
    cellBytes,
    lockedToKey: targetKey,
  });

  const anchor: AnchorResult = {
    txid: result.txid,
    eventType: 'hand-create',
    isLinear: true,
    phase: state.phase,
    beef: beefArray,
    vout,
    lockingScript: scriptHex,
    cellVersion: 1,
  };
  opts.log('CREATE', `✓ v1 → ${result.txid.slice(0, 16)}... (vout ${vout}) [${Date.now() - t0}ms]`);
  opts.log('WoC', `https://whatsonchain.com/tx/${result.txid}`);

  if (opts.settleDelayMs > 0) await sleep(opts.settleDelayMs);
  return anchor;
}


```
