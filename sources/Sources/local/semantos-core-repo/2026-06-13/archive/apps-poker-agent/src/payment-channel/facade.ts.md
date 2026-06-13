---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-poker-agent/src/payment-channel/facade.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.765901+00:00
---

# archive/apps-poker-agent/src/payment-channel/facade.ts

```ts
/**
 * Payment-channel facade — thin orchestrator that turns method calls
 * into reducer dispatches + effect-bus emissions.
 *
 * The facade is deliberately stateless beyond the per-channel atom
 * bundle (`atoms.ts`). All durable state lives behind ports + effects;
 * the reducer (prompt 13) is pure; the facade just glues them.
 *
 * Public methods correspond 1:1 to the prompt-15 spec:
 *   fund, extract, bindConsumer, internalizeConsumer,
 *   internalizeProvider, settle, close.
 *
 * Each method:
 *   1. Reads the current `ChannelStateValue` from `stateAtom`
 *   2. Calls `channelReducer(state, event)` (pure)
 *   3. Writes the new state into the atoms
 *   4. Forwards reducer commands + facade-only effect commands onto
 *      `effectBus`
 *   5. Pushes the accepted event onto `channelEventsBus`
 */

import { get, set } from '@semantos/state';

import { getChannelAtoms, type ChannelAtoms } from './atoms';
import { effectBus } from './effects/bus';
import type { EffectCommand } from './effects/types';
import {
  channelReducer,
  type ChannelArtifacts,
  type ChannelCommand,
  type ChannelEvent,
  type ChannelRole,
  type ChannelStateValue,
  type RoleScopedKeyId,
  type SpvProof,
} from './fsm';

export interface FundArgs {
  channelId: string;
  role?: ChannelRole;
  artifacts: ChannelArtifacts;
  isNativeMultisig: boolean;
  keyIds: RoleScopedKeyId[];
}

export interface ExtractArgs {
  channelId: string;
  vout: number;
}

export interface BindConsumerArgs {
  channelId: string;
  proof: SpvProof;
}

export interface SettleArgs {
  channelId: string;
  spvProof: SpvProof;
  /** Hex-encoded settlement raw tx — broadcast as part of settle. */
  settlementRawTx: string;
}

export interface CloseArgs {
  channelId: string;
  /** Optional close raw tx — broadcast on close. */
  closeRawTx?: string;
}

/**
 * Boot-once: dispatches a reducer event for the given channel, updates
 * the atoms, fans out commands to `effectBus`. Returns the new state
 * value so callers can react synchronously.
 */
export function dispatch(
  channelId: string,
  event: ChannelEvent,
  role: ChannelRole = 'consumer',
): ChannelStateValue {
  const atoms = getChannelAtoms(channelId, role);
  const current = get(atoms.stateAtom);
  const result = channelReducer(current, event);

  // 1. Reflect the new state value into the atoms.
  set(atoms.stateAtom, result.next);
  if (result.next.state !== current.state) {
    set(atoms.channelStateAtom, result.next.state);
  }
  if (result.next.artifacts && get(atoms.artifactsAtom) === null) {
    set(atoms.artifactsAtom, result.next.artifacts);
  }

  // 2. Always announce the event (atoms.channelEventsBus is the public
  //    feed for log/observers). lastError-bearing transitions still go
  //    through — observers can filter.
  atoms.channelEventsBus.emit(event);
  effectBus.emit({ type: 'emit-event', channelId, event });

  // 3. Forward reducer commands as effect-bus commands.
  for (const cmd of result.emitted) {
    forwardReducerCommand(channelId, cmd);
  }

  return result.next;
}

function forwardReducerCommand(
  channelId: string,
  cmd: ChannelCommand,
): void {
  switch (cmd.type) {
    case 'persist-artifacts':
      effectBus.emit({ type: 'persist-artifacts', channelId, artifacts: cmd.artifacts });
      return;
    case 'persist-spv':
      effectBus.emit({ type: 'persist-spv', channelId, proof: cmd.proof });
      return;
    case 'mark-state':
      effectBus.emit({ type: 'mark-state', channelId, state: cmd.state });
      return;
    case 'emit-event':
      effectBus.emit({ type: 'emit-event', channelId, event: cmd.event });
      return;
  }
}

/**
 * Dispatch a synthetic effect command. Used by facade methods to layer
 * broadcast / await-spv / fee-credit on top of pure reducer output.
 */
function dispatchEffect(cmd: EffectCommand): void {
  effectBus.emit(cmd);
}

// ── Public methods ────────────────────────────────────────────────

/** Fund: UNFUNDED → FUNDED. Emits broadcast + fee-credit. */
export function fund(args: FundArgs): ChannelStateValue {
  const next = dispatch(
    args.channelId,
    {
      type: 'fund',
      artifacts: args.artifacts,
      isNativeMultisig: args.isNativeMultisig,
      keyIds: args.keyIds,
    },
    args.role,
  );
  if (next.state === 'FUNDED') {
    dispatchEffect({
      type: 'broadcast',
      channelId: args.channelId,
      rawTx: args.artifacts.simpleRawTx,
      label: 'funding',
    });
    dispatchEffect({
      type: 'fee-credit',
      channelId: args.channelId,
      reason: 'funding',
      sats: 1,
    });
  }
  return next;
}

/** Extract: confirms vout match against frozen artifacts. */
export function extract(args: ExtractArgs): ChannelStateValue {
  return dispatch(args.channelId, { type: 'extract', vout: args.vout });
}

/**
 * Bind consumer: attaches an SPV proof, then progresses to FLOW_READY.
 * The reducer requires two events here; we dispatch them in order.
 */
export function bindConsumer(args: BindConsumerArgs): ChannelStateValue {
  dispatch(args.channelId, { type: 'attach-spv', proof: args.proof });
  return dispatch(args.channelId, { type: 'flow-ready' });
}

/**
 * Internalize consumer-side delta — facade-side noop in the reducer
 * sense, but we still emit a fee-credit so accounting stays consistent.
 */
export function internalizeConsumer(channelId: string): ChannelStateValue {
  const atoms = getChannelAtoms(channelId);
  dispatchEffect({ type: 'fee-credit', channelId, reason: 'tick', sats: 1 });
  return get(atoms.stateAtom);
}

/**
 * Internalize provider-side delta — same shape as consumer; lifted to
 * a separate method so callers don't need to know about the symmetric
 * fee-credit accounting.
 */
export function internalizeProvider(channelId: string): ChannelStateValue {
  const atoms = getChannelAtoms(channelId);
  dispatchEffect({ type: 'fee-credit', channelId, reason: 'tick', sats: 1 });
  return get(atoms.stateAtom);
}

/** Settle: dispatches `settle-begin`, broadcasts settlement tx. */
export function settle(args: SettleArgs): ChannelStateValue {
  const next = dispatch(args.channelId, {
    type: 'settle-begin',
    spvProof: args.spvProof,
  });
  if (next.state === 'SETTLING') {
    dispatchEffect({
      type: 'broadcast',
      channelId: args.channelId,
      rawTx: args.settlementRawTx,
      label: 'settlement',
    });
    dispatchEffect({
      type: 'fee-credit',
      channelId: args.channelId,
      reason: 'settlement',
      sats: 1,
    });
  }
  return next;
}

/** Close: SETTLING → CLOSED. Optionally broadcasts a close tx. */
export function close(args: CloseArgs): ChannelStateValue {
  const next = dispatch(args.channelId, { type: 'close' });
  if (next.state === 'CLOSED' && args.closeRawTx) {
    dispatchEffect({
      type: 'broadcast',
      channelId: args.channelId,
      rawTx: args.closeRawTx,
      label: 'close',
    });
  }
  return next;
}

/** Convenience: snapshot the current channel state for a caller. */
export function getState(channelId: string): ChannelStateValue {
  const atoms: ChannelAtoms = getChannelAtoms(channelId);
  return get(atoms.stateAtom);
}

```
