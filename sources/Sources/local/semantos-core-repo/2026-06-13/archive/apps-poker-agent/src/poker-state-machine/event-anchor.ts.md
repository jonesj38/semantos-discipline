---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/poker-state-machine/event-anchor.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.769035+00:00
---

# archive/apps-poker-agent/src/poker-state-machine/event-anchor.ts

```ts
/**
 * Standalone OP_RETURN anchor builder.
 *
 * `anchorEvent()` and `anchorEventBatch()` were extracted verbatim
 * from the legacy `PokerStateMachine` so the byte layout of every
 * OP_RETURN is byte-identical to what shipped before. Anyone reading
 * a chain of pre-refactor txs sees the same JSON in the same script.
 *
 * Each call hits `wallet.createAction({ outputs: [{ lockingScript:
 * opReturnScript, satoshis: 0 }] })`. There is no chaining — each
 * tx is independent, so the wallet handles fees + change.
 */

import type { WalletClient } from '../../../../core/protocol-types/src/wallet-client';

import type { AnchorResult, PokerPhase } from './types';

export interface EventAnchorOptions {
  wallet: WalletClient;
  /** Settle delay applied after each OP_RETURN (ms). 0 in turbo mode. */
  settleDelayMs?: number;
  /** Optional log hook so the facade can keep its existing format. */
  log?: (label: string, msg: string) => void;
}

export type EventBatchEntry = {
  eventType: string;
  data: Record<string, unknown>;
};

/**
 * Anchor a single non-linear event as a 0-sat OP_RETURN.
 *
 * Each OP_RETURN is completely standalone — no references to other
 * txs, no chaining through change outputs. The linkage to the hand
 * state is purely informational (a string in the JSON payload).
 */
export async function anchorEvent(
  opts: EventAnchorOptions,
  eventType: string,
  data: Record<string, unknown>,
): Promise<AnchorResult | null> {
  const payload = JSON.stringify({
    proto: 'semantos-poker',
    v: 1,
    event: eventType,
    ts: Date.now(),
    ...data,
  });

  const opReturnScript = buildOpReturnScript(payload);

  try {
    const t0 = Date.now();
    const result = await opts.wallet.createAction({
      description: `${eventType} | Hand #${(data as { hand?: unknown }).hand ?? '?'}`,
      labels: ['semantos-poker', eventType],
      outputs: [
        {
          lockingScript: opReturnScript,
          satoshis: 0,
          outputDescription: eventType,
        },
      ],
    });

    const anchor: AnchorResult = {
      txid: result.txid,
      eventType,
      isLinear: false,
      phase: ((data as { phase?: PokerPhase }).phase ?? 'unknown') as PokerPhase,
    };
    opts.log?.('EVENT', `${eventType} → ${result.txid.slice(0, 16)}... [${Date.now() - t0}ms]`);
    if ((opts.settleDelayMs ?? 0) > 0) await sleep(opts.settleDelayMs!);
    return anchor;
  } catch (err) {
    opts.log?.('EVENT', `✗ ${eventType}: ${(err as Error).message}`);
    return null;
  }
}

/**
 * Batch multiple events into a single OP_RETURN tx with one combined
 * payload. One wallet call instead of N — much faster than calling
 * `anchorEvent` in a loop.
 */
export async function anchorEventBatch(
  opts: EventAnchorOptions,
  events: EventBatchEntry[],
): Promise<AnchorResult | null> {
  if (events.length === 0) return null;

  const batchPayload = JSON.stringify({
    proto: 'semantos-poker',
    v: 1,
    batch: true,
    count: events.length,
    events: events.map((e) => ({ event: e.eventType, ...e.data })),
    ts: Date.now(),
  });
  const opReturnScript = buildOpReturnScript(batchPayload);
  const description = events.map((e) => e.eventType).join('+');

  try {
    const result = await opts.wallet.createAction({
      description: `batch(${events.length}): ${description.slice(0, 30)}`,
      labels: ['semantos-poker', 'batch'],
      outputs: [
        {
          lockingScript: opReturnScript,
          satoshis: 0,
          outputDescription: `batch: ${description}`,
        },
      ],
    });

    const anchor: AnchorResult = {
      txid: result.txid,
      eventType: `batch(${events.length})`,
      isLinear: false,
      phase: ((events[0].data as { phase?: PokerPhase }).phase ?? 'unknown') as PokerPhase,
    };
    opts.log?.('BATCH', `${events.length} events → ${result.txid.slice(0, 16)}...`);
    if ((opts.settleDelayMs ?? 0) > 0) await sleep(opts.settleDelayMs!);
    return anchor;
  } catch (err) {
    opts.log?.('BATCH', `✗ ${description}: ${(err as Error).message}`);
    return null;
  }
}

/**
 * Build a standalone OP_RETURN script from a string payload. Output
 * exactly matches the legacy inline implementation:
 *
 *   '006a' (OP_FALSE OP_RETURN) + push-prefix + payload-hex
 *
 * Push prefix:
 *   - len < 76        → single byte 0x{len}
 *   - 76 ≤ len ≤ 255  → 0x4c {len}
 *   - len > 255       → 0x4d {len_lo} {len_hi}
 */
export function buildOpReturnScript(payload: string): string {
  const payloadHex = Buffer.from(payload).toString('hex');
  const lenBytes = payloadHex.length / 2;
  let pushPrefix: string;
  if (lenBytes < 76) {
    pushPrefix = lenBytes.toString(16).padStart(2, '0');
  } else if (lenBytes <= 255) {
    pushPrefix = '4c' + lenBytes.toString(16).padStart(2, '0');
  } else {
    pushPrefix =
      '4d' +
      (lenBytes & 0xff).toString(16).padStart(2, '0') +
      ((lenBytes >> 8) & 0xff).toString(16).padStart(2, '0');
  }
  return '006a' + pushPrefix + payloadHex;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

```
