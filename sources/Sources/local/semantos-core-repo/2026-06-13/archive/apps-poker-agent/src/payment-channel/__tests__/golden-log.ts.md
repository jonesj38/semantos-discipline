---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/__tests__/golden-log.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.794207+00:00
---

# archive/apps-poker-agent/src/payment-channel/__tests__/golden-log.ts

```ts
/**
 * Golden command sequence the lifecycle test pins against.
 *
 * Each entry is the smallest projection of an `EffectCommand` we
 * actually need to compare — the test's swap-in log effect only
 * captures `cmd`, plus a single discriminator field per command type.
 */

export interface GoldenLogEntry {
  cmd: string;
  state?: string;
  label?: string;
  reason?: string;
  event?: string;
}

export const GOLDEN_LIFECYCLE_LOG: GoldenLogEntry[] = [
  // fund() — dispatch + facade-only broadcast + fee-credit
  { cmd: 'emit-event', event: 'fund' },
  { cmd: 'persist-artifacts' },
  { cmd: 'mark-state', state: 'FUNDED' },
  { cmd: 'broadcast', label: 'funding' },
  { cmd: 'fee-credit', reason: 'funding' },

  // bindConsumer() — dispatch attach-spv, then dispatch flow-ready
  { cmd: 'emit-event', event: 'attach-spv' },
  { cmd: 'persist-spv' },
  { cmd: 'emit-event', event: 'flow-ready' },
  { cmd: 'mark-state', state: 'FLOW_READY' },

  // internalizeConsumer + internalizeProvider — fee-credit only
  { cmd: 'fee-credit', reason: 'tick' },
  { cmd: 'fee-credit', reason: 'tick' },

  // settle() — dispatch settle-begin + facade-only broadcast + fee-credit
  { cmd: 'emit-event', event: 'settle-begin' },
  { cmd: 'persist-spv' },
  { cmd: 'mark-state', state: 'SETTLING' },
  { cmd: 'broadcast', label: 'settlement' },
  { cmd: 'fee-credit', reason: 'settlement' },

  // close() — dispatch close (no closeRawTx → no broadcast)
  { cmd: 'emit-event', event: 'close' },
  { cmd: 'mark-state', state: 'CLOSED' },
];

```
