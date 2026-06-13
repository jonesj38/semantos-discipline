---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/effects/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.791484+00:00
---

# archive/apps-poker-agent/src/payment-channel/effects/types.ts

```ts
/**
 * Effect commands — what the facade dispatches to the effect layer.
 *
 * The prompt-13 reducer emits a small set of pure commands (`persist-
 * artifacts`, `persist-spv`, `mark-state`, `emit-event`). The facade
 * translates those into a richer set the side-effect atoms understand,
 * adding broadcast / await-spv / fee-credit instructions that the pure
 * reducer can't emit (they require external IO).
 *
 * Each effect atom subscribes to a slice of this union via the effect
 * bus exposed by `bus.ts`. Subscribers must be safe to call repeatedly
 * — the facade does not deduplicate.
 */

import type {
  ChannelArtifacts,
  ChannelEvent,
  ChannelState,
  SpvProof,
} from '../fsm';

export interface PersistArtifactsCommand {
  type: 'persist-artifacts';
  channelId: string;
  artifacts: ChannelArtifacts;
}

export interface PersistSpvCommand {
  type: 'persist-spv';
  channelId: string;
  proof: SpvProof;
}

export interface BroadcastCommand {
  type: 'broadcast';
  channelId: string;
  rawTx: string;
  /** Logical label so the log effect can describe what we broadcast. */
  label: 'funding' | 'settlement' | 'close';
}

export interface AwaitSpvCommand {
  type: 'await-spv';
  channelId: string;
  txid: string;
  /** Minimum confirmation depth the spv effect must reach. */
  minConfirmations: number;
}

export interface FeeCreditCommand {
  type: 'fee-credit';
  channelId: string;
  /** Why the credit was emitted — controls the destination bucket. */
  reason: 'funding' | 'tick' | 'settlement';
  /** Always 1 sat per the CashLanes spec, but the field keeps it explicit. */
  sats: number;
}

export interface MarkStateCommand {
  type: 'mark-state';
  channelId: string;
  state: ChannelState;
}

export interface EmitEventCommand {
  type: 'emit-event';
  channelId: string;
  event: ChannelEvent;
}

export type EffectCommand =
  | PersistArtifactsCommand
  | PersistSpvCommand
  | BroadcastCommand
  | AwaitSpvCommand
  | FeeCreditCommand
  | MarkStateCommand
  | EmitEventCommand;

```
