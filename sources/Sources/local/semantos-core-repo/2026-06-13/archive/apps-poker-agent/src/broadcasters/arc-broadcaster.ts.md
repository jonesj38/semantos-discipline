---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/broadcasters/arc-broadcaster.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.764718+00:00
---

# archive/apps-poker-agent/src/broadcasters/arc-broadcaster.ts

```ts
/**
 * ARC-backed Broadcaster — the only place in the poker-agent that
 * instantiates `new ARC()`. The payment-channel layer always
 * resolves the broadcaster through `broadcasterPort` so the
 * `apps/poker-agent/src/payment-channel/` tree stays free of inline
 * external SDK instantiations.
 */

import { ARC, Transaction } from '@bsv/sdk';

import type {
  Broadcaster,
  BroadcastResult,
} from '@semantos/protocol-types/ports';

const DEFAULT_ARC_URL = 'https://arc.gorillapool.io';

/** Wrap @bsv/sdk's `ARC` into a Broadcaster port impl. */
export function makeArcBroadcaster(arcUrl: string = DEFAULT_ARC_URL): Broadcaster {
  const arc = new ARC(arcUrl);
  return {
    async broadcast(rawTx): Promise<BroadcastResult> {
      try {
        const tx =
          typeof rawTx === 'string'
            ? Transaction.fromHex(rawTx)
            : Transaction.fromBinary(rawTx);
        const result = (await tx.broadcast(arc)) as {
          status?: string;
          txid?: string;
          description?: string;
        };
        const failed = result.status === 'error' || result.status === 'ERROR';
        const out: BroadcastResult = {
          txid: result.txid ?? '',
          ok: !!result.txid && !failed,
        };
        if (result.status !== undefined) out.status = result.status;
        if (result.description !== undefined) out.error = result.description;
        return out;
      } catch (err) {
        return {
          txid: '',
          ok: false,
          error: err instanceof Error ? err.message : String(err),
        };
      }
    },
  };
}

export { DEFAULT_ARC_URL };

```
