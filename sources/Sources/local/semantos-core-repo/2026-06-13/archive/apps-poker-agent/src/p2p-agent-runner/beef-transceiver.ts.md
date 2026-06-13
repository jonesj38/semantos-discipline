---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/p2p-agent-runner/beef-transceiver.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.785537+00:00
---

# archive/apps-poker-agent/src/p2p-agent-runner/beef-transceiver.ts

```ts
/**
 * BEEF send/receive thin wrapper around the bound `transportPort`.
 *
 * Normalises BEEF payloads through `shared/beef-codec` so callers
 * always emit a `number[]` regardless of whether the source was a
 * hex string or already-an-array. Also owns the `awaitControl`
 * helper that the legacy runner used to block on a specific
 * control-message type.
 */

import { toArray as beefToArray } from '../shared';

import type {
  PokerControlMessage,
  PokerMoveMessage,
  Transport,
} from './transport-port';

export interface SendMoveArgs {
  handNumber: number;
  phase: string;
  action: string;
  amount?: number;
  beef: number[] | string;
  txid: string;
  vout: number;
  lockingScript: string;
  cellVersion: number;
}

/** Send a move with the BEEF normalised to number[]. */
export async function sendMove(
  transport: Transport,
  args: SendMoveArgs,
): Promise<void> {
  const move: PokerMoveMessage = {
    handNumber: args.handNumber,
    phase: args.phase,
    action: args.action,
    amount: args.amount,
    beef: beefToArray(args.beef),
    txid: args.txid,
    vout: args.vout,
    lockingScript: args.lockingScript,
    cellVersion: args.cellVersion,
  };
  await transport.sendMove(move);
}

/** Pass-through send for non-move control. */
export async function sendControl(
  transport: Transport,
  type: string,
  payload: Record<string, unknown>,
): Promise<void> {
  await transport.sendControl(type, payload);
}

/**
 * Wait for a control message of a specific `type`. Resolves with
 * the message; rejects on timeout. The transport must already be
 * listening — the awaiter intercepts the `onControl` callback
 * temporarily, exactly as the legacy runner did.
 */
export function awaitControl(
  transport: Transport,
  type: string,
  timeoutMs: number,
  /** Optional pump for transports that need a poll-and-drain cycle. */
  drainEveryMs: number = 2000,
): Promise<PokerControlMessage> {
  return new Promise<PokerControlMessage>((resolve, reject) => {
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error(`Timeout waiting for ${type}`));
    }, timeoutMs);
    const drain = setInterval(async () => {
      try {
        await transport.drainPending();
      } catch {
        // ignore drain errors; we're still racing the timeout
      }
    }, drainEveryMs);

    const t = transport as unknown as { onControl?: (m: PokerControlMessage) => Promise<void> | void };
    const orig = t.onControl;
    const cleanup = () => {
      clearTimeout(timer);
      clearInterval(drain);
      t.onControl = orig;
    };
    t.onControl = async (msg: PokerControlMessage) => {
      if (msg.type === type) {
        cleanup();
        resolve(msg);
      } else if (orig) {
        await orig(msg);
      }
    };
  });
}

```
