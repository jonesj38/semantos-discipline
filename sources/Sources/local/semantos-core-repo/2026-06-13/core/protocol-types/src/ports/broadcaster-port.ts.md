---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/ports/broadcaster-port.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.902617+00:00
---

# core/protocol-types/src/ports/broadcaster-port.ts

```ts
/**
 * Broadcaster port — replaces inline `new ARC(...)` calls in the
 * payment-channel layer.
 *
 * Concrete impls wrap ARC, the metanet-desktop wallet broadcast path,
 * or in-memory doubles for tests.
 */

import { port, type Port } from '@semantos/state';

export interface BroadcastResult {
  txid: string;
  ok: boolean;
  /** Optional broadcaster-specific status string (e.g. "MINED", "QUEUED"). */
  status?: string;
  /** Optional human-readable error message when `ok=false`. */
  error?: string;
}

export interface Broadcaster {
  /** Broadcast a raw transaction. Hex or BEEF-encoded number[]. */
  broadcast(rawTx: string | number[]): Promise<BroadcastResult>;
}

export const broadcasterPort: Port<Broadcaster> = port<Broadcaster>('broadcaster');

```
