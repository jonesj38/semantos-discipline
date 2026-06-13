---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/fsm/transitions.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.792677+00:00
---

# archive/apps-poker-agent/src/payment-channel/fsm/transitions.ts

```ts
/**
 * Per-event transition handlers. Each takes the current state + event
 * and returns either an updated state with emitted commands or a
 * rejection (state unchanged, lastError populated).
 *
 * Pure functions only — no `await`, no `Date.now()`, no `Math.random()`,
 * no `this`. The reducer concatenates these.
 */

import {
  assertFundingInvariants,
  assertSpvAttached,
} from './invariants';
import type {
  ChannelArtifacts,
  ChannelCommand,
  ChannelEvent,
  ChannelStateValue,
  ReducerResult,
  RoleScopedKeyId,
  SpvProof,
} from './types';

function reject(current: ChannelStateValue, reason: string): ReducerResult {
  return { next: { ...current, lastError: reason }, emitted: [] };
}

function advance(
  current: ChannelStateValue,
  patch: Partial<ChannelStateValue>,
  emitted: ChannelCommand[],
): ReducerResult {
  return {
    next: { ...current, ...patch, lastError: undefined },
    emitted,
  };
}

export function transitionFund(
  current: ChannelStateValue,
  event: Extract<ChannelEvent, { type: 'fund' }>,
): ReducerResult {
  if (current.state !== 'UNFUNDED' && current.state !== 'FUNDING_PENDING') {
    return reject(current, `cannot fund from ${current.state}`);
  }
  const inv = assertFundingInvariants({
    current,
    artifacts: event.artifacts,
    isNativeMultisig: event.isNativeMultisig,
    keyIds: event.keyIds,
  });
  if (!inv.ok) return reject(current, inv.reason);

  return advance(
    current,
    {
      state: 'FUNDED',
      artifacts: event.artifacts,
      isNativeMultisig: event.isNativeMultisig,
      keyIds: mergeKeyIds(current.keyIds, event.keyIds),
    },
    [
      { type: 'persist-artifacts', artifacts: event.artifacts },
      { type: 'mark-state', state: 'FUNDED' },
    ],
  );
}

export function transitionExtract(
  current: ChannelStateValue,
  event: Extract<ChannelEvent, { type: 'extract' }>,
): ReducerResult {
  if (current.state !== 'FUNDED') {
    return reject(current, `cannot extract from ${current.state}`);
  }
  if (!current.artifacts) {
    return reject(current, 'invariant 2: artifacts must be present before extract');
  }
  if (event.vout !== current.artifacts.vout) {
    return reject(
      current,
      `extract vout mismatch: expected ${current.artifacts.vout}, got ${event.vout}`,
    );
  }
  // No state change — extract is a confirmation step. Emit the
  // observable mark for downstream effects.
  return advance(current, {}, [{ type: 'mark-state', state: 'FUNDED' }]);
}

export function transitionAttachSpv(
  current: ChannelStateValue,
  event: Extract<ChannelEvent, { type: 'attach-spv' }>,
): ReducerResult {
  if (current.state !== 'FUNDED') {
    return reject(current, `cannot attach SPV from ${current.state}`);
  }
  const ok = assertSpvAttached(event.proof);
  if (!ok.ok) return reject(current, ok.reason);

  return advance(current, { spvProof: event.proof }, [
    { type: 'persist-spv', proof: event.proof },
  ]);
}

export function transitionFlowReady(current: ChannelStateValue): ReducerResult {
  if (current.state !== 'FUNDED') {
    return reject(current, `cannot enter FLOW_READY from ${current.state}`);
  }
  const ok = assertSpvAttached(current.spvProof);
  if (!ok.ok) return reject(current, ok.reason);

  return advance(current, { state: 'FLOW_READY' }, [
    { type: 'mark-state', state: 'FLOW_READY' },
  ]);
}

export function transitionFlowActivate(current: ChannelStateValue): ReducerResult {
  if (current.state !== 'FLOW_READY') {
    return reject(current, `cannot activate flow from ${current.state}`);
  }
  return advance(current, { state: 'FLOW_ACTIVE' }, [
    { type: 'mark-state', state: 'FLOW_ACTIVE' },
  ]);
}

export function transitionFlowDeactivate(current: ChannelStateValue): ReducerResult {
  if (current.state !== 'FLOW_ACTIVE') {
    return reject(current, `cannot deactivate flow from ${current.state}`);
  }
  return advance(current, { state: 'FLOW_READY' }, [
    { type: 'mark-state', state: 'FLOW_READY' },
  ]);
}

export function transitionSettleBegin(
  current: ChannelStateValue,
  event: Extract<ChannelEvent, { type: 'settle-begin' }>,
): ReducerResult {
  if (current.state !== 'FLOW_READY' && current.state !== 'FLOW_ACTIVE') {
    return reject(current, `cannot settle from ${current.state}`);
  }
  const ok = assertSpvAttached(event.spvProof);
  if (!ok.ok) return reject(current, ok.reason);

  return advance(current, { state: 'SETTLING', spvProof: event.spvProof }, [
    { type: 'persist-spv', proof: event.spvProof },
    { type: 'mark-state', state: 'SETTLING' },
  ]);
}

export function transitionClose(current: ChannelStateValue): ReducerResult {
  if (current.state !== 'SETTLING') {
    return reject(current, `cannot close from ${current.state}`);
  }
  return advance(current, { state: 'CLOSED' }, [
    { type: 'mark-state', state: 'CLOSED' },
  ]);
}

function mergeKeyIds(
  current: RoleScopedKeyId[],
  next: RoleScopedKeyId[],
): RoleScopedKeyId[] {
  const seen = new Set(current.map((k) => k.keyId));
  const out = [...current];
  for (const k of next) {
    if (!seen.has(k.keyId)) {
      out.push(k);
      seen.add(k.keyId);
    }
  }
  return out;
}

// Re-export type aliases used by the reducer.
export type { ChannelArtifacts, ChannelEvent, SpvProof };

```
