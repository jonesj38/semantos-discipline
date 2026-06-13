---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/metering/metering/src/host-functions.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.486961+00:00
---

# packages/metering/metering/src/host-functions.ts

```ts
/**
 * Metering host functions — registered with HostFunctionRegistry.
 *
 * Payment channel model (incrementing nSequence):
 *   - Funding tx: 2-of-2 multisig
 *   - Each tick: pre-signed tx with nSequence+1, same funding input,
 *     outputs redistribute: providerPayout + consumerPayout = fundingSatoshis
 *   - Cooperative close: last signer sets nSequence=0xFFFFFFFF + nLockTime=0,
 *     tx is immediately broadcastable (finalised)
 *   - Unilateral close: broadcast the latest (highest nSequence) pre-signed tx
 *   - Dispute: prove you hold a higher nSequence than what was broadcast
 *
 * Context shape (frozen before WASM evaluation):
 *   channelState: string              // Current ChannelState enum value
 *   hasFundingOutpoint: boolean        // Funding outpoint is set
 *   tickAmount: number                 // Satoshis shifted this tick (>= 0)
 *   providerPayout: number             // Provider's output in this tick's tx
 *   consumerPayout: number             // Consumer's output in this tick's tx
 *   fundingSatoshis: number            // Total locked in funding tx
 *   nSequence: number                  // This tick's nSequence value
 *   channelNSequence: number           // Channel's current (highest seen) nSequence
 *   spendsFundingOutpoint: boolean     // Tx input matches funding outpoint
 *   isFinal: boolean                   // nSequence=0xFFFFFFFF, cooperative close
 *   bothPartiesAgree: boolean          // Both parties acknowledged close
 *   hasHigherNSequence: boolean        // Disputer holds higher nSequence than broadcast
 *   hasResolution: boolean             // Dispute resolution computed
 *
 * Phase 29.5 kernel enforcement sweep.
 */

import type { HostFunctionRegistry, HostFunctionContext } from '../../cell-engine/bindings/host-functions';
import { ChannelState } from './channel-fsm';

// ── Helpers ───────────────────────────────────────────────────────

function channelState(ctx: HostFunctionContext): string {
  return ctx.channelState as string;
}

// ── Registration ──────────────────────────────────────────────────

export function registerMeteringHostFunctions(registry: HostFunctionRegistry): void {

  // ── State predicates ─────────────────────────────────────────

  registry.register('channel-negotiating?', (ctx) =>
    channelState(ctx) === ChannelState.NEGOTIATING ? 1 : 0,
  );

  registry.register('channel-funded?', (ctx) =>
    channelState(ctx) === ChannelState.FUNDED ? 1 : 0,
  );

  registry.register('channel-active?', (ctx) =>
    channelState(ctx) === ChannelState.ACTIVE ? 1 : 0,
  );

  registry.register('channel-paused?', (ctx) =>
    channelState(ctx) === ChannelState.PAUSED ? 1 : 0,
  );

  registry.register('channel-closing-requested?', (ctx) =>
    channelState(ctx) === ChannelState.CLOSING_REQUESTED ? 1 : 0,
  );

  registry.register('channel-closing-confirmed?', (ctx) =>
    channelState(ctx) === ChannelState.CLOSING_CONFIRMED ? 1 : 0,
  );

  registry.register('channel-settled?', (ctx) =>
    channelState(ctx) === ChannelState.SETTLED ? 1 : 0,
  );

  registry.register('channel-disputed?', (ctx) =>
    channelState(ctx) === ChannelState.DISPUTED ? 1 : 0,
  );

  // ── Funding guard ────────────────────────────────────────────

  /** Funding outpoint has been set (non-null, non-empty). */
  registry.register('has-funding-outpoint?', (ctx) =>
    (ctx.hasFundingOutpoint as boolean) ? 1 : 0,
  );

  // ── Tick guards ──────────────────────────────────────────────

  /** Tick amount is non-negative (>= 0). */
  registry.register('tick-amount-valid?', (ctx) =>
    (ctx.tickAmount as number) >= 0 ? 1 : 0,
  );

  /**
   * Payouts are conserved: providerPayout + consumerPayout === fundingSatoshis.
   * This is the critical invariant — each tick redistributes the locked funds
   * but the total never changes. No satoshis created or destroyed.
   */
  registry.register('payouts-conserved?', (ctx) => {
    const provider = ctx.providerPayout as number;
    const consumer = ctx.consumerPayout as number;
    const funding = ctx.fundingSatoshis as number;
    return (provider + consumer === funding) ? 1 : 0;
  });

  // ── Close guards ─────────────────────────────────────────────

  /** Both provider and consumer have acknowledged the close request. */
  registry.register('both-parties-agree?', (ctx) =>
    (ctx.bothPartiesAgree as boolean) ? 1 : 0,
  );

  // ── Settlement guards ────────────────────────────────────────

  /**
   * The submitted settlement tx has the latest (highest) nSequence.
   * nSequence >= channelNSequence means this is at least as recent
   * as the channel's last recorded tick.
   */
  registry.register('nsequence-is-latest?', (ctx) => {
    const submitted = ctx.nSequence as number;
    const current = ctx.channelNSequence as number;
    return (submitted >= current) ? 1 : 0;
  });

  /**
   * The settlement tx input spends the correct funding outpoint.
   * Prevents settling against the wrong channel.
   */
  registry.register('spends-funding-outpoint?', (ctx) =>
    (ctx.spendsFundingOutpoint as boolean) ? 1 : 0,
  );

  /**
   * The settlement tx is final: nSequence=0xFFFFFFFF, nLockTime=0.
   * The last signer cooperatively finalises the tx, making it
   * immediately broadcastable without waiting for nSequence to
   * reach MAXINT through incremental ticks.
   */
  registry.register('settlement-is-final?', (ctx) =>
    (ctx.isFinal as boolean) ? 1 : 0,
  );

  // ── Dispute guards ───────────────────────────────────────────

  /**
   * The disputing party holds a pre-signed tx with a higher nSequence
   * than the one the counterparty broadcast. This proves the broadcast
   * was stale — a newer state exists.
   */
  registry.register('has-higher-nsequence?', (ctx) =>
    (ctx.hasHigherNSequence as boolean) ? 1 : 0,
  );

  /**
   * A resolution has been computed for the dispute.
   * The highest-nSequence tx has been identified and will be used.
   */
  registry.register('has-resolution?', (ctx) =>
    (ctx.hasResolution as boolean) ? 1 : 0,
  );

}

```
