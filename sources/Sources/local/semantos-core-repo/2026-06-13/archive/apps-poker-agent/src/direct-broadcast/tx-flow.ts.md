---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/direct-broadcast/tx-flow.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.784894+00:00
---

# archive/apps-poker-agent/src/direct-broadcast/tx-flow.ts

```ts
/**
 * Shared "pick-build-broadcast-recycle" flow for the three direct-
 * broadcast tx kinds (CellToken create, transition, OP_RETURN).
 *
 * Each path:
 *   1. Pop a funding UTXO from the stream's pool.
 *   2. Build + sign the tx via the supplied builder.
 *   3. Broadcast through `broadcasterPort` (sync or fire-and-forget).
 *   4. Recycle change back into the pool (if the builder produced one).
 *
 * Extracted into its own module so the facade stays under the
 * prompt-18 250-LOC ceiling.
 */

import type { Transaction } from '@bsv/sdk';
import {
  broadcasterPort,
  type Broadcaster,
} from '@semantos/protocol-types/ports';

import {
  pickFundingUtxo,
  recycleUtxo,
} from './utxo-pool-manager';
import {
  getDirectBroadcastEvents,
} from './tx-stats-collector';
import type { BroadcastResult, FundingUtxo } from './types';

export interface TxFlowDeps {
  engineId: string;
  streamId: number;
  label: string;
  fireAndForget: boolean;
  /** Tracker for fire-and-forget promises so `flush()` can await them. */
  trackPending: (p: Promise<void>) => void;
}

export interface BuilderOutput {
  tx: Transaction;
  change: FundingUtxo | null;
}

export type Builder = (funding: FundingUtxo) => Promise<BuilderOutput>;

/**
 * Run the full pick → build → broadcast → recycle flow.
 * Caller passes a `builder` that turns a funding UTXO into a signed
 * transaction + optional change recycle.
 */
export async function runTxFlow(
  deps: TxFlowDeps,
  build: Builder,
): Promise<BroadcastResult> {
  const { utxo: funding } = pickFundingUtxo(deps.engineId, deps.streamId, deps.label);
  const t0 = Date.now();
  const { tx, change } = await build(funding);
  const buildMs = Date.now() - t0;
  const txid = tx.id('hex') as string;
  const { broadcastMs } = await broadcastTx(deps, tx, buildMs, txid);
  if (change) recycleUtxo(deps.engineId, deps.streamId, change);
  return { txid, buildMs, broadcastMs, tx };
}

/** Broadcast — emits stats events for both sync + fire-and-forget. */
export async function broadcastTx(
  deps: TxFlowDeps,
  tx: Transaction,
  buildMs: number,
  txid: string,
): Promise<{ broadcastMs: number }> {
  const events = getDirectBroadcastEvents(deps.engineId);
  if (deps.fireAndForget) {
    const p = broadcastWithFallback(deps, tx).catch((err) => {
      events.emit({ type: 'broadcast-error', label: deps.label, message: (err as Error).message });
    });
    deps.trackPending(p);
    events.emit({ type: 'broadcast', label: deps.label, txid, buildMs, broadcastMs: 0, fireAndForget: true });
    return { broadcastMs: 0 };
  }
  const t1 = Date.now();
  await broadcastWithFallback(deps, tx);
  const broadcastMs = Date.now() - t1;
  events.emit({
    type: 'broadcast',
    label: deps.label,
    txid,
    buildMs,
    broadcastMs,
    fireAndForget: false,
  });
  return { broadcastMs };
}

/**
 * Single broadcast call that respects the prompt-14 `broadcasterPort`.
 * Errors emit `'broadcast-error'` events; in synchronous mode the
 * error is also re-thrown so the caller sees the failure.
 */
export async function broadcastWithFallback(
  deps: TxFlowDeps,
  tx: Transaction,
): Promise<void> {
  const broadcaster: Broadcaster = broadcasterPort.get();
  const result = await broadcaster.broadcast(tx.toHex());
  if (!result.ok) {
    const msg = `${deps.label} broadcast failed: ${result.error ?? result.status ?? 'unknown'}`;
    getDirectBroadcastEvents(deps.engineId).emit({
      type: 'broadcast-error',
      label: deps.label,
      message: msg,
    });
    if (!deps.fireAndForget) throw new Error(msg);
  }
}

```
