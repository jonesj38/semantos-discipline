---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/metering/metering/src/policy-enforced-channel.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.487574+00:00
---

# packages/metering/metering/src/policy-enforced-channel.ts

```ts
/**
 * PolicyEnforcedChannel — wraps the metering FSM with kernel-enforced
 * policy evaluation via HostFunctionRegistry + AnchorEmitter.
 *
 * Payment channel model (incrementing nSequence):
 *   - Funding tx: 2-of-2 multisig
 *   - Each tick: pre-signed tx with nSequence+1, same funding input,
 *     outputs: providerPayout + consumerPayout = fundingSatoshis
 *   - Cooperative close: last signer sets nSequence=0xFFFFFFFF + nLockTime=0,
 *     tx is immediately broadcastable (finalised)
 *   - Unilateral close: broadcast the latest (highest nSequence) pre-signed tx
 *   - Dispute: prove you hold a higher nSequence than the broadcast
 *
 * Every state transition passes through compiled Lisp policies evaluated
 * by host predicates. On terminal transitions (SETTLED), an anchor
 * transaction is emitted.
 *
 * Phase 29.5 kernel enforcement sweep.
 */

import { HostFunctionRegistry } from '../../cell-engine/bindings/host-functions';
import { registerMeteringHostFunctions } from './host-functions';
import { compileMeteringPolicies, type CompiledMeteringPolicies } from './policies';
import {
  ChannelState,
  type MeteringChannel,
  type Result,
  createChannel,
  fund as rawFund,
  activate as rawActivate,
  pause as rawPause,
  resume as rawResume,
  tick as rawTick,
  requestClose as rawRequestClose,
  confirmClose as rawConfirmClose,
  settle as rawSettle,
  dispute as rawDispute,
} from './channel-fsm';

import type { AnchorEmitter } from '../../policy-runtime/src/anchor-emitter';
import type { PolicyResult } from '../../policy-runtime/src/types';

// ── Types ────────────────────────────────────────────────────────

export interface TickContext {
  /** Satoshis shifted to provider this tick. */
  tickAmount: number;
  /** Provider's total payout in the new pre-signed tx. */
  providerPayout: number;
  /** Consumer's total payout in the new pre-signed tx. */
  consumerPayout: number;
  /** Total satoshis locked in the funding tx. */
  fundingSatoshis: number;
}

export interface SettlementContext {
  /** nSequence of the tx being submitted for settlement. */
  nSequence: number;
  /** Whether the tx input spends the correct funding outpoint. */
  spendsFundingOutpoint: boolean;
  /**
   * True when the last signer sets nSequence=0xFFFFFFFF (final) and
   * nLockTime=0, making the tx immediately broadcastable. This is the
   * cooperative close path — both parties agree on the final payout split,
   * no need to wait for nSequence to reach MAXINT through ticks.
   *
   * When false, settlement uses the latest pre-signed tick tx (highest
   * nSequence seen so far).
   */
  isFinal?: boolean;
}

export interface DisputeContext {
  /** Disputer holds a pre-signed tx with higher nSequence than broadcast. */
  hasHigherNSequence: boolean;
}

export interface ResolveContext {
  /** Dispute resolution has been computed (highest nSequence identified). */
  hasResolution: boolean;
}

// ── PolicyEnforcedChannel ────────────────────────────────────────

export class PolicyEnforcedChannel {
  private registry: HostFunctionRegistry;
  private policies: CompiledMeteringPolicies;
  private anchorEmitter?: AnchorEmitter;

  /** Last policy evaluation result for audit trail. */
  private _lastPolicyResult?: PolicyResult;

  constructor(anchorEmitter?: AnchorEmitter) {
    this.registry = new HostFunctionRegistry();
    registerMeteringHostFunctions(this.registry);
    this.policies = compileMeteringPolicies();
    this.anchorEmitter = anchorEmitter;
  }

  /** Last policy evaluation result (for inspection/audit). */
  lastPolicyResult(): PolicyResult | undefined {
    return this._lastPolicyResult;
  }

  // ── Policy Evaluation ──────────────────────────────────────

  private evaluatePolicy(
    policyKey: keyof CompiledMeteringPolicies,
    ctx: Record<string, unknown>,
  ): boolean {
    this.registry.setContext(ctx);

    let result = true;

    switch (policyKey) {
      case 'fund':
        // (and (channel-negotiating?) (has-funding-outpoint?))
        result = this.registry.call('channel-negotiating?') === 1
          && this.registry.call('has-funding-outpoint?') === 1;
        break;

      case 'activate':
        // (channel-funded?)
        result = this.registry.call('channel-funded?') === 1;
        break;

      case 'tick':
        // (and (channel-active?) (tick-amount-valid?) (payouts-conserved?))
        result = this.registry.call('channel-active?') === 1
          && this.registry.call('tick-amount-valid?') === 1
          && this.registry.call('payouts-conserved?') === 1;
        break;

      case 'closeRequest':
        // (or (channel-active?) (channel-paused?))
        result = this.registry.call('channel-active?') === 1
          || this.registry.call('channel-paused?') === 1;
        break;

      case 'closeConfirm':
        // (and (channel-closing-requested?) (both-parties-agree?))
        result = this.registry.call('channel-closing-requested?') === 1
          && this.registry.call('both-parties-agree?') === 1;
        break;

      case 'settle':
        // (and (channel-closing-confirmed?) (or (settlement-is-final?) (nsequence-is-latest?)) (spends-funding-outpoint?))
        result = this.registry.call('channel-closing-confirmed?') === 1
          && (this.registry.call('settlement-is-final?') === 1
            || this.registry.call('nsequence-is-latest?') === 1)
          && this.registry.call('spends-funding-outpoint?') === 1;
        break;

      case 'dispute':
        // (and (not (channel-settled?)) (has-higher-nsequence?))
        result = this.registry.call('channel-settled?') === 0
          && this.registry.call('has-higher-nsequence?') === 1;
        break;

      case 'resolve':
        // (and (channel-disputed?) (has-resolution?))
        result = this.registry.call('channel-disputed?') === 1
          && this.registry.call('has-resolution?') === 1;
        break;
    }

    this.registry.clearContext();

    this._lastPolicyResult = {
      ok: result,
      gas: 0,
      hostCalls: [],
      rejectionCode: result ? undefined : 'VERIFY_FAILED',
      rejectionDetail: result ? undefined : `Metering policy '${policyKey}' rejected`,
    };

    return result;
  }

  // ── Policy-Enforced Operations ─────────────────────────────

  /** Create a new channel (no policy needed — initial state). */
  create(providerCertId: string, consumerCertId: string): MeteringChannel {
    return createChannel(providerCertId, consumerCertId);
  }

  /** Fund: NEGOTIATING → FUNDED. Policy: channel must be negotiating + outpoint present. */
  fund(channel: MeteringChannel, fundingOutpoint: string): Result<MeteringChannel> {
    const policyOk = this.evaluatePolicy('fund', {
      channelState: channel.state,
      hasFundingOutpoint: !!fundingOutpoint && fundingOutpoint.length > 0,
    });

    if (!policyOk) {
      return { ok: false, error: `Policy rejected: ${this._lastPolicyResult?.rejectionDetail}` };
    }

    return rawFund(channel, fundingOutpoint);
  }

  /** Activate: FUNDED → ACTIVE. Policy: channel must be funded. */
  activate(channel: MeteringChannel): Result<MeteringChannel> {
    const policyOk = this.evaluatePolicy('activate', {
      channelState: channel.state,
    });

    if (!policyOk) {
      return { ok: false, error: `Policy rejected: ${this._lastPolicyResult?.rejectionDetail}` };
    }

    return rawActivate(channel);
  }

  /** Pause: ACTIVE → PAUSED. No additional policy (FSM validates state). */
  pause(channel: MeteringChannel): Result<MeteringChannel> {
    return rawPause(channel);
  }

  /** Resume: PAUSED → ACTIVE. No additional policy (FSM validates state). */
  resume(channel: MeteringChannel): Result<MeteringChannel> {
    return rawResume(channel);
  }

  /**
   * Tick: Increment nSequence, redistribute payouts.
   * Policy: state active + amount valid + payouts conserved.
   *
   * Each tick produces a new pre-signed tx: same funding input,
   * incremented nSequence, updated payout split.
   */
  tick(channel: MeteringChannel, satoshisThisTick: number, ctx?: TickContext): Result<MeteringChannel> {
    const policyOk = this.evaluatePolicy('tick', {
      channelState: channel.state,
      tickAmount: satoshisThisTick,
      providerPayout: ctx?.providerPayout ?? 0,
      consumerPayout: ctx?.consumerPayout ?? 0,
      fundingSatoshis: ctx?.fundingSatoshis ?? 0,
    });

    if (!policyOk) {
      return { ok: false, error: `Policy rejected: ${this._lastPolicyResult?.rejectionDetail}` };
    }

    return rawTick(channel, satoshisThisTick);
  }

  /** Close request: ACTIVE|PAUSED → CLOSING_REQUESTED. */
  requestClose(channel: MeteringChannel): Result<MeteringChannel> {
    const policyOk = this.evaluatePolicy('closeRequest', {
      channelState: channel.state,
    });

    if (!policyOk) {
      return { ok: false, error: `Policy rejected: ${this._lastPolicyResult?.rejectionDetail}` };
    }

    return rawRequestClose(channel);
  }

  /** Confirm close: CLOSING_REQUESTED → CLOSING_CONFIRMED. Both parties must agree. */
  confirmClose(channel: MeteringChannel, ctx: { bothPartiesAgree: boolean }): Result<MeteringChannel> {
    const policyOk = this.evaluatePolicy('closeConfirm', {
      channelState: channel.state,
      bothPartiesAgree: ctx.bothPartiesAgree,
    });

    if (!policyOk) {
      return { ok: false, error: `Policy rejected: ${this._lastPolicyResult?.rejectionDetail}` };
    }

    return rawConfirmClose(channel);
  }

  /**
   * Settle: CLOSING_CONFIRMED → SETTLED.
   *
   * Two settlement paths:
   *   1. Cooperative (isFinal=true): Last signer sets nSequence=0xFFFFFFFF
   *      and nLockTime=0, making the tx immediately broadcastable. Both
   *      parties agree on the final payout split — no waiting required.
   *   2. Unilateral (isFinal=false/omitted): Broadcast the latest pre-signed
   *      tick tx (highest nSequence). Must spend the correct funding outpoint.
   *
   * Policy: nSequence must be latest (or final) + tx must spend correct
   * funding outpoint. Emits anchor transaction on success.
   */
  async settle(
    channel: MeteringChannel,
    settlementTxId: string,
    ctx: SettlementContext,
  ): Promise<Result<MeteringChannel>> {
    const policyOk = this.evaluatePolicy('settle', {
      channelState: channel.state,
      nSequence: ctx.nSequence,
      channelNSequence: channel.nSequence,
      spendsFundingOutpoint: ctx.spendsFundingOutpoint,
      isFinal: ctx.isFinal ?? false,
    });

    if (!policyOk) {
      return { ok: false, error: `Policy rejected: ${this._lastPolicyResult?.rejectionDetail}` };
    }

    const result = rawSettle(channel, settlementTxId);

    // Anchor emission on successful settlement
    if (result.ok && this.anchorEmitter) {
      const payload = new TextEncoder().encode(JSON.stringify({
        channelId: channel.channelId,
        state: 'SETTLED',
        nSequence: ctx.nSequence,
        isFinal: ctx.isFinal ?? false,
        ticks: channel.currentTick,
        settlementTxId,
      }));
      await this.anchorEmitter.emit(payload, {
        linearity: 'LINEAR',
        anchorPolicy: 'always',
        idempotencyKey: `metering-settle-${channel.channelId}`,
      });
    }

    return result;
  }

  /**
   * Dispute: → DISPUTED.
   * The disputing party proves they hold a higher nSequence pre-signed tx
   * than what the counterparty broadcast (stale state).
   */
  dispute(channel: MeteringChannel, reason: string, ctx: DisputeContext): Result<MeteringChannel> {
    const policyOk = this.evaluatePolicy('dispute', {
      channelState: channel.state,
      hasHigherNSequence: ctx.hasHigherNSequence,
    });

    if (!policyOk) {
      return { ok: false, error: `Policy rejected: ${this._lastPolicyResult?.rejectionDetail}` };
    }

    // Anchor emission on dispute
    if (this.anchorEmitter) {
      const payload = new TextEncoder().encode(JSON.stringify({
        channelId: channel.channelId,
        state: 'DISPUTED',
        reason,
        nSequence: channel.nSequence,
      }));
      this.anchorEmitter.emit(payload, {
        linearity: 'LINEAR',
        anchorPolicy: 'always',
        idempotencyKey: `metering-dispute-${channel.channelId}`,
      });
    }

    return rawDispute(channel, reason);
  }

  /**
   * Resolve: DISPUTED → SETTLED.
   * The highest-nSequence tx has been identified and broadcast.
   */
  async resolve(
    channel: MeteringChannel,
    settlementTxId: string,
    ctx: ResolveContext,
  ): Promise<Result<MeteringChannel>> {
    const policyOk = this.evaluatePolicy('resolve', {
      channelState: channel.state,
      hasResolution: ctx.hasResolution,
    });

    if (!policyOk) {
      return { ok: false, error: `Policy rejected: ${this._lastPolicyResult?.rejectionDetail}` };
    }

    // DISPUTED→SETTLED goes through 'resolve' action in the transition table.
    if (channel.state !== ChannelState.DISPUTED) {
      return { ok: false, error: `Cannot resolve channel from state ${channel.state}` };
    }

    const result: Result<MeteringChannel> = {
      ok: true,
      value: {
        ...channel,
        state: ChannelState.SETTLED,
        updatedAt: Date.now(),
      },
    };

    // Anchor emission on dispute resolution
    if (result.ok && this.anchorEmitter) {
      const payload = new TextEncoder().encode(JSON.stringify({
        channelId: channel.channelId,
        state: 'RESOLVED',
        settlementTxId,
        nSequence: channel.nSequence,
      }));
      await this.anchorEmitter.emit(payload, {
        linearity: 'LINEAR',
        anchorPolicy: 'always',
        idempotencyKey: `metering-resolve-${channel.channelId}`,
      });
    }

    return result;
  }
}

```
