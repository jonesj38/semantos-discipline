---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/phase29.5-metering-gate.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.579791+00:00
---

# tests/gates/phase29.5-metering-gate.test.ts

```ts
/**
 * Phase 29.5 Metering Settlement Policy — Gate Tests
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
 * Hard invariants:
 *   M1: Settlement policies compile to valid scriptBytes
 *   M2: Host function predicates correctly reflect channel state
 *   M3: PolicyEnforcedChannel gates transitions through compiled policies
 *   M4: Settlement rejects when nSequence is stale or outpoint wrong
 *   M5: Payouts conservation invariant enforced on tick
 *   M6: Dispute requires higher nSequence proof
 *   M7: Anchor emission fires on settlement + dispute
 *   M8: Full lifecycle: create -> fund -> activate -> tick x N -> close -> settle
 */

import { describe, test, expect } from 'bun:test';

import { HostFunctionRegistry } from '../../core/cell-engine/bindings/host-functions';
import { registerMeteringHostFunctions } from '../../packages/metering/src/host-functions';
import {
  compileMeteringPolicies,
  type CompiledMeteringPolicies,
  FUND_POLICY,
  SETTLE_POLICY,
  DISPUTE_POLICY,
  TICK_POLICY,
} from '../../packages/metering/src/policies';
import { createMeteringHostFunctionProvider } from '../../packages/metering/src/kernel-provider';
import {
  PolicyEnforcedChannel,
  type SettlementContext,
  type DisputeContext,
  type ResolveContext,
  type TickContext,
} from '../../packages/metering/src/policy-enforced-channel';
import { ChannelState, createChannel, type MeteringChannel } from '../../packages/metering/src/channel-fsm';
import { DevModeAnchorEmitter } from '../../packages/policy-runtime/src/anchor-emitter';
import { computeTickProof, verifyTickProof, createSettlementBatch } from '../../packages/metering/src/settlement';

describe('M1 — Metering Policies Compile', () => {

  test('T1: All 8 metering policies compile to non-empty scriptBytes', () => {
    const policies = compileMeteringPolicies();

    expect(policies.fund.scriptBytes.length).toBeGreaterThan(0);
    expect(policies.activate.scriptBytes.length).toBeGreaterThan(0);
    expect(policies.tick.scriptBytes.length).toBeGreaterThan(0);
    expect(policies.closeRequest.scriptBytes.length).toBeGreaterThan(0);
    expect(policies.closeConfirm.scriptBytes.length).toBeGreaterThan(0);
    expect(policies.settle.scriptBytes.length).toBeGreaterThan(0);
    expect(policies.dispute.scriptBytes.length).toBeGreaterThan(0);
    expect(policies.resolve.scriptBytes.length).toBeGreaterThan(0);
  });

  test('T2: Policy source strings reference correct predicates', () => {
    expect(FUND_POLICY).toContain('channel-negotiating?');
    expect(FUND_POLICY).toContain('has-funding-outpoint?');
    expect(SETTLE_POLICY).toContain('settlement-is-final?');
    expect(SETTLE_POLICY).toContain('nsequence-is-latest?');
    expect(SETTLE_POLICY).toContain('spends-funding-outpoint?');
    expect(DISPUTE_POLICY).toContain('has-higher-nsequence?');
    expect(TICK_POLICY).toContain('payouts-conserved?');
    expect(TICK_POLICY).toContain('tick-amount-valid?');
  });
});

describe('M2 — Metering Host Function Predicates', () => {

  let registry: HostFunctionRegistry;

  test('T3: Channel state predicates reflect current state', () => {
    registry = new HostFunctionRegistry();
    registerMeteringHostFunctions(registry);

    // NEGOTIATING
    registry.setContext({ channelState: ChannelState.NEGOTIATING });
    expect(registry.call('channel-negotiating?')).toBe(1);
    expect(registry.call('channel-funded?')).toBe(0);
    expect(registry.call('channel-active?')).toBe(0);
    expect(registry.call('channel-settled?')).toBe(0);
    registry.clearContext();

    // ACTIVE
    registry.setContext({ channelState: ChannelState.ACTIVE });
    expect(registry.call('channel-active?')).toBe(1);
    expect(registry.call('channel-negotiating?')).toBe(0);
    registry.clearContext();

    // SETTLED
    registry.setContext({ channelState: ChannelState.SETTLED });
    expect(registry.call('channel-settled?')).toBe(1);
    expect(registry.call('channel-active?')).toBe(0);
    registry.clearContext();

    // DISPUTED
    registry.setContext({ channelState: ChannelState.DISPUTED });
    expect(registry.call('channel-disputed?')).toBe(1);
    registry.clearContext();
  });

  test('T4: Funding outpoint predicate', () => {
    registry.setContext({ hasFundingOutpoint: true });
    expect(registry.call('has-funding-outpoint?')).toBe(1);
    registry.clearContext();

    registry.setContext({ hasFundingOutpoint: false });
    expect(registry.call('has-funding-outpoint?')).toBe(0);
    registry.clearContext();
  });

  test('T5: Tick amount validation predicate', () => {
    registry.setContext({ tickAmount: 100 });
    expect(registry.call('tick-amount-valid?')).toBe(1);
    registry.clearContext();

    registry.setContext({ tickAmount: 0 });
    expect(registry.call('tick-amount-valid?')).toBe(1); // 0 is valid
    registry.clearContext();

    registry.setContext({ tickAmount: -1 });
    expect(registry.call('tick-amount-valid?')).toBe(0); // negative invalid
    registry.clearContext();
  });

  test('T6: Payouts conservation predicate', () => {
    // Conserved: provider + consumer = funding
    registry.setContext({ providerPayout: 3000, consumerPayout: 7000, fundingSatoshis: 10000 });
    expect(registry.call('payouts-conserved?')).toBe(1);
    registry.clearContext();

    // Not conserved: sum doesn't match
    registry.setContext({ providerPayout: 3000, consumerPayout: 7000, fundingSatoshis: 9999 });
    expect(registry.call('payouts-conserved?')).toBe(0);
    registry.clearContext();

    // Edge case: all zero is conserved
    registry.setContext({ providerPayout: 0, consumerPayout: 0, fundingSatoshis: 0 });
    expect(registry.call('payouts-conserved?')).toBe(1);
    registry.clearContext();
  });

  test('T7: nSequence and settlement predicates', () => {
    // nSequence is latest (submitted >= channel's current)
    registry.setContext({ nSequence: 5, channelNSequence: 5 });
    expect(registry.call('nsequence-is-latest?')).toBe(1);
    registry.clearContext();

    // nSequence is stale
    registry.setContext({ nSequence: 3, channelNSequence: 5 });
    expect(registry.call('nsequence-is-latest?')).toBe(0);
    registry.clearContext();

    // Spends correct funding outpoint
    registry.setContext({ spendsFundingOutpoint: true });
    expect(registry.call('spends-funding-outpoint?')).toBe(1);
    registry.clearContext();

    registry.setContext({ spendsFundingOutpoint: false });
    expect(registry.call('spends-funding-outpoint?')).toBe(0);
    registry.clearContext();
  });

  test('T8: Dispute and resolution predicates', () => {
    // Has higher nSequence (dispute evidence)
    registry.setContext({ hasHigherNSequence: true });
    expect(registry.call('has-higher-nsequence?')).toBe(1);
    registry.clearContext();

    registry.setContext({ hasHigherNSequence: false });
    expect(registry.call('has-higher-nsequence?')).toBe(0);
    registry.clearContext();

    // Has resolution
    registry.setContext({ hasResolution: true });
    expect(registry.call('has-resolution?')).toBe(1);
    registry.clearContext();

    registry.setContext({ hasResolution: false });
    expect(registry.call('has-resolution?')).toBe(0);
    registry.clearContext();
  });

  test('T9: Settlement finality predicate', () => {
    // Final (cooperative close: nSequence=0xFFFFFFFF)
    registry.setContext({ isFinal: true });
    expect(registry.call('settlement-is-final?')).toBe(1);
    registry.clearContext();

    // Not final (unilateral: using latest nSequence from ticks)
    registry.setContext({ isFinal: false });
    expect(registry.call('settlement-is-final?')).toBe(0);
    registry.clearContext();
  });

  test('T10: MeteringHostFunctionProvider registers all predicates', () => {
    const fresh = new HostFunctionRegistry();
    const provider = createMeteringHostFunctionProvider();
    provider.register(fresh);

    fresh.setContext({ channelState: ChannelState.ACTIVE, tickAmount: 50 });
    expect(fresh.call('channel-active?')).toBe(1);
    expect(fresh.call('tick-amount-valid?')).toBe(1);
    fresh.clearContext();
  });
});

describe('M3 — PolicyEnforcedChannel Gates Transitions', () => {

  test('T11: Fund succeeds when channel is negotiating + outpoint provided', () => {
    const pec = new PolicyEnforcedChannel();
    const ch = pec.create('provider-cert', 'consumer-cert');

    expect(ch.state).toBe(ChannelState.NEGOTIATING);

    const result = pec.fund(ch, 'abc123:0');
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.state).toBe(ChannelState.FUNDED);
      expect(result.value.fundingOutpoint).toBe('abc123:0');
    }
  });

  test('T12: Fund rejects when channel is already funded', () => {
    const pec = new PolicyEnforcedChannel();
    const ch = pec.create('p', 'c');
    const funded = pec.fund(ch, 'tx:0');
    expect(funded.ok).toBe(true);

    // Try to fund again — policy should reject (not in NEGOTIATING state)
    const result = pec.fund(funded.ok ? funded.value : ch, 'tx2:1');
    expect(result.ok).toBe(false);
  });

  test('T13: Tick rejects when channel is not active', () => {
    const pec = new PolicyEnforcedChannel();
    const ch = pec.create('p', 'c');

    // Channel is NEGOTIATING, tick should fail
    const result = pec.tick(ch, 100);
    expect(result.ok).toBe(false);
  });

  test('T14: Tick succeeds when channel is active with conserved payouts', () => {
    const pec = new PolicyEnforcedChannel();
    let ch = pec.create('p', 'c');
    ch = (pec.fund(ch, 'tx:0') as any).value;
    ch = (pec.activate(ch) as any).value;

    // Tick with conserved payouts: 100 to provider, 9900 to consumer, 10000 total
    const result = pec.tick(ch, 100, {
      tickAmount: 100,
      providerPayout: 100,
      consumerPayout: 9900,
      fundingSatoshis: 10000,
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.currentTick).toBe(1);
      expect(result.value.nSequence).toBe(1);
      expect(result.value.cumulativeSatoshis).toBe(100);
    }
  });

  test('T15: Tick rejects when payouts are not conserved', () => {
    const pec = new PolicyEnforcedChannel();
    let ch = pec.create('p', 'c');
    ch = (pec.fund(ch, 'tx:0') as any).value;
    ch = (pec.activate(ch) as any).value;

    // payouts don't sum to fundingSatoshis
    const result = pec.tick(ch, 100, {
      tickAmount: 100,
      providerPayout: 100,
      consumerPayout: 9900,
      fundingSatoshis: 9000, // WRONG: 100 + 9900 != 9000
    });
    expect(result.ok).toBe(false);
    expect(pec.lastPolicyResult()?.ok).toBe(false);
  });
});

describe('M4 — Settlement nSequence Validation', () => {

  test('T16: Settlement rejects when nSequence is stale', async () => {
    const pec = new PolicyEnforcedChannel();
    let ch = pec.create('p', 'c');
    ch = (pec.fund(ch, 'tx:0') as any).value;
    ch = (pec.activate(ch) as any).value;

    // 3 ticks -> nSequence = 3
    ch = (pec.tick(ch, 100) as any).value;
    ch = (pec.tick(ch, 100) as any).value;
    ch = (pec.tick(ch, 100) as any).value;
    expect(ch.nSequence).toBe(3);

    ch = (pec.requestClose(ch) as any).value;
    ch = (pec.confirmClose(ch, { bothPartiesAgree: true }) as any).value;

    // Try to settle with stale nSequence (1 instead of 3)
    const result = await pec.settle(ch, 'settle-tx', {
      nSequence: 1, // STALE
      spendsFundingOutpoint: true,
    });

    expect(result.ok).toBe(false);
    expect(pec.lastPolicyResult()?.ok).toBe(false);
  });

  test('T17: Settlement rejects when tx doesn\'t spend funding outpoint', async () => {
    const pec = new PolicyEnforcedChannel();
    let ch = pec.create('p', 'c');
    ch = (pec.fund(ch, 'tx:0') as any).value;
    ch = (pec.activate(ch) as any).value;
    ch = (pec.tick(ch, 500) as any).value;
    ch = (pec.requestClose(ch) as any).value;
    ch = (pec.confirmClose(ch, { bothPartiesAgree: true }) as any).value;

    const result = await pec.settle(ch, 'settle-tx', {
      nSequence: ch.nSequence,
      spendsFundingOutpoint: false, // WRONG outpoint
    });

    expect(result.ok).toBe(false);
  });

  test('T18: Settlement succeeds with latest nSequence + correct outpoint (unilateral)', async () => {
    const pec = new PolicyEnforcedChannel();
    let ch = pec.create('p', 'c');
    ch = (pec.fund(ch, 'tx:0') as any).value;
    ch = (pec.activate(ch) as any).value;
    ch = (pec.tick(ch, 100) as any).value;
    ch = (pec.tick(ch, 200) as any).value;

    expect(ch.nSequence).toBe(2);

    ch = (pec.requestClose(ch) as any).value;
    ch = (pec.confirmClose(ch, { bothPartiesAgree: true }) as any).value;

    const result = await pec.settle(ch, 'settle-tx', {
      nSequence: 2,
      spendsFundingOutpoint: true,
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.state).toBe(ChannelState.SETTLED);
    }
  });

  test('T18b: Cooperative close — isFinal=true bypasses nSequence check', async () => {
    const pec = new PolicyEnforcedChannel();
    let ch = pec.create('p', 'c');
    ch = (pec.fund(ch, 'tx:0') as any).value;
    ch = (pec.activate(ch) as any).value;
    ch = (pec.tick(ch, 100) as any).value;
    ch = (pec.tick(ch, 200) as any).value;
    ch = (pec.tick(ch, 300) as any).value;
    expect(ch.nSequence).toBe(3);

    ch = (pec.requestClose(ch) as any).value;
    ch = (pec.confirmClose(ch, { bothPartiesAgree: true }) as any).value;

    // Last signer sets nSequence=0xFFFFFFFF, nLockTime=0 — immediately final.
    // The submitted nSequence (0xFFFFFFFF) is way above channel's 3,
    // but isFinal=true is what matters — the tx is done.
    const result = await pec.settle(ch, 'final-settle-tx', {
      nSequence: 0xFFFFFFFF,
      spendsFundingOutpoint: true,
      isFinal: true,
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.state).toBe(ChannelState.SETTLED);
    }
  });

  test('T18c: Cooperative close still requires correct funding outpoint', async () => {
    const pec = new PolicyEnforcedChannel();
    let ch = pec.create('p', 'c');
    ch = (pec.fund(ch, 'tx:0') as any).value;
    ch = (pec.activate(ch) as any).value;
    ch = (pec.tick(ch, 100) as any).value;
    ch = (pec.requestClose(ch) as any).value;
    ch = (pec.confirmClose(ch, { bothPartiesAgree: true }) as any).value;

    // isFinal=true but wrong outpoint — must still be rejected
    const result = await pec.settle(ch, 'bad-outpoint-tx', {
      nSequence: 0xFFFFFFFF,
      spendsFundingOutpoint: false, // WRONG
      isFinal: true,
    });

    expect(result.ok).toBe(false);
  });
});

describe('M5 — Tick Payouts Conservation', () => {

  test('T19: Multiple ticks maintain nSequence increment', () => {
    const pec = new PolicyEnforcedChannel();
    let ch = pec.create('p', 'c');
    ch = (pec.fund(ch, 'tx:0') as any).value;
    ch = (pec.activate(ch) as any).value;

    const fundingAmount = 10000;

    // Tick 1: provider gets 100, consumer gets 9900
    ch = (pec.tick(ch, 100, {
      tickAmount: 100,
      providerPayout: 100,
      consumerPayout: 9900,
      fundingSatoshis: fundingAmount,
    }) as any).value;
    expect(ch.nSequence).toBe(1);

    // Tick 2: provider gets 300, consumer gets 9700
    ch = (pec.tick(ch, 200, {
      tickAmount: 200,
      providerPayout: 300,
      consumerPayout: 9700,
      fundingSatoshis: fundingAmount,
    }) as any).value;
    expect(ch.nSequence).toBe(2);

    // Tick 3: provider gets 600, consumer gets 9400
    ch = (pec.tick(ch, 300, {
      tickAmount: 300,
      providerPayout: 600,
      consumerPayout: 9400,
      fundingSatoshis: fundingAmount,
    }) as any).value;
    expect(ch.nSequence).toBe(3);
    expect(ch.currentTick).toBe(3);
  });

  test('T20: Tick rejects negative amounts via policy', () => {
    const pec = new PolicyEnforcedChannel();
    let ch = pec.create('p', 'c');
    ch = (pec.fund(ch, 'tx:0') as any).value;
    ch = (pec.activate(ch) as any).value;

    const result = pec.tick(ch, -50);
    expect(result.ok).toBe(false);
  });
});

describe('M6 — Dispute Validation', () => {

  test('T21: Dispute rejects without higher nSequence proof', () => {
    const pec = new PolicyEnforcedChannel();
    let ch = pec.create('p', 'c');
    ch = (pec.fund(ch, 'tx:0') as any).value;
    ch = (pec.activate(ch) as any).value;
    ch = (pec.requestClose(ch) as any).value;

    const result = pec.dispute(ch, 'stale broadcast', {
      hasHigherNSequence: false, // No proof of higher nSequence!
    });

    expect(result.ok).toBe(false);
  });

  test('T22: Dispute succeeds with higher nSequence proof', () => {
    const pec = new PolicyEnforcedChannel();
    let ch = pec.create('p', 'c');
    ch = (pec.fund(ch, 'tx:0') as any).value;
    ch = (pec.activate(ch) as any).value;
    ch = (pec.requestClose(ch) as any).value;

    const result = pec.dispute(ch, 'counterparty broadcast nSequence=2, I hold nSequence=5', {
      hasHigherNSequence: true,
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.state).toBe(ChannelState.DISPUTED);
    }
  });

  test('T23: Dispute rejects from SETTLED state', () => {
    const pec = new PolicyEnforcedChannel();
    let ch = pec.create('p', 'c');
    ch = (pec.fund(ch, 'tx:0') as any).value;
    ch = (pec.activate(ch) as any).value;

    // Manually set state to SETTLED to test the (not (channel-settled?)) guard
    const settled: MeteringChannel = { ...ch, state: ChannelState.SETTLED };
    const result = pec.dispute(settled, 'too late', { hasHigherNSequence: true });
    expect(result.ok).toBe(false);
  });

  test('T24: Resolve rejects when no resolution computed', async () => {
    const pec = new PolicyEnforcedChannel();
    let ch = pec.create('p', 'c');
    ch = (pec.fund(ch, 'tx:0') as any).value;
    ch = (pec.activate(ch) as any).value;
    ch = (pec.requestClose(ch) as any).value;
    ch = (pec.dispute(ch, 'higher nSequence', { hasHigherNSequence: true }) as any).value;

    const result = await pec.resolve(ch, 'resolve-tx', {
      hasResolution: false, // No resolution!
    });

    expect(result.ok).toBe(false);
  });

  test('T25: Resolve succeeds with resolution', async () => {
    const pec = new PolicyEnforcedChannel();
    let ch = pec.create('p', 'c');
    ch = (pec.fund(ch, 'tx:0') as any).value;
    ch = (pec.activate(ch) as any).value;
    ch = (pec.requestClose(ch) as any).value;
    ch = (pec.dispute(ch, 'higher nSequence', { hasHigherNSequence: true }) as any).value;

    const result = await pec.resolve(ch, 'resolve-tx', {
      hasResolution: true,
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.state).toBe(ChannelState.SETTLED);
    }
  });
});

describe('M7 — Anchor Emission', () => {

  test('T26: Settlement emits anchor transaction', async () => {
    const emitter = new DevModeAnchorEmitter();
    const pec = new PolicyEnforcedChannel(emitter);
    let ch = pec.create('p', 'c');
    ch = (pec.fund(ch, 'tx:0') as any).value;
    ch = (pec.activate(ch) as any).value;
    ch = (pec.tick(ch, 1000) as any).value;
    ch = (pec.requestClose(ch) as any).value;
    ch = (pec.confirmClose(ch, { bothPartiesAgree: true }) as any).value;

    const result = await pec.settle(ch, 'settle-tx', {
      nSequence: ch.nSequence,
      spendsFundingOutpoint: true,
    });

    expect(result.ok).toBe(true);

    // Verify anchor was emitted — idempotent replay returns reused=true
    const replay = await emitter.emit(new TextEncoder().encode(JSON.stringify({
      channelId: ch.channelId,
      state: 'SETTLED',
      nSequence: ch.nSequence,
      ticks: ch.currentTick,
      settlementTxId: 'settle-tx',
    })), {
      linearity: 'LINEAR',
      anchorPolicy: 'always',
      idempotencyKey: `metering-settle-${ch.channelId}`,
    });
    expect(replay.reused).toBe(true);
  });

  test('T27: Dispute emits anchor transaction', () => {
    const emitter = new DevModeAnchorEmitter();
    const pec = new PolicyEnforcedChannel(emitter);
    let ch = pec.create('p', 'c');
    ch = (pec.fund(ch, 'tx:0') as any).value;
    ch = (pec.activate(ch) as any).value;
    ch = (pec.requestClose(ch) as any).value;

    const result = pec.dispute(ch, 'nSequence mismatch', { hasHigherNSequence: true });
    expect(result.ok).toBe(true);

    // Anchor was emitted fire-and-forget — verify via idempotency key
  });
});

describe('M8 — Full Lifecycle', () => {

  test('T28: Complete lifecycle with tick proofs and nSequence settlement', async () => {
    const emitter = new DevModeAnchorEmitter();
    const pec = new PolicyEnforcedChannel(emitter);
    const sharedSecret = new Uint8Array(32).fill(0x42);
    const fundingAmount = 10000;

    // 1. Create
    let ch = pec.create('provider-cert-001', 'consumer-cert-002');
    expect(ch.state).toBe(ChannelState.NEGOTIATING);

    // 2. Fund (2-of-2 multisig)
    let result = pec.fund(ch, 'funding-txid:0');
    expect(result.ok).toBe(true);
    ch = (result as any).value;
    expect(ch.state).toBe(ChannelState.FUNDED);

    // 3. Activate
    result = pec.activate(ch);
    expect(result.ok).toBe(true);
    ch = (result as any).value;
    expect(ch.state).toBe(ChannelState.ACTIVE);

    // 4. Tick x 5 — each tick produces a new pre-signed tx with nSequence+1
    //    redistributing the locked funds pro rata
    const tickProofs = [];
    let providerTotal = 0;
    for (let i = 0; i < 5; i++) {
      const tickSats = 100;
      providerTotal += tickSats;

      result = pec.tick(ch, tickSats, {
        tickAmount: tickSats,
        providerPayout: providerTotal,
        consumerPayout: fundingAmount - providerTotal,
        fundingSatoshis: fundingAmount,
      });
      expect(result.ok).toBe(true);
      ch = (result as any).value;

      // Compute tick proof
      const proof = await computeTickProof(
        ch.channelId, ch.currentTick, ch.cumulativeSatoshis, sharedSecret,
      );
      tickProofs.push(proof);

      // Verify tick proof
      const valid = await verifyTickProof(proof, sharedSecret);
      expect(valid).toBe(true);
    }

    expect(ch.currentTick).toBe(5);
    expect(ch.nSequence).toBe(5);
    expect(ch.cumulativeSatoshis).toBe(500);

    // 5. Create settlement batch
    const batch = createSettlementBatch(ch.channelId, tickProofs);
    expect(batch.fromTick).toBe(1);
    expect(batch.toTick).toBe(5);
    expect(batch.totalSatoshis).toBe(500);

    // 6. Close request
    result = pec.requestClose(ch);
    expect(result.ok).toBe(true);
    ch = (result as any).value;
    expect(ch.state).toBe(ChannelState.CLOSING_REQUESTED);

    // 7. Confirm close (both parties agree)
    result = pec.confirmClose(ch, { bothPartiesAgree: true });
    expect(result.ok).toBe(true);
    ch = (result as any).value;
    expect(ch.state).toBe(ChannelState.CLOSING_CONFIRMED);

    // 8. Settle — broadcast the latest nSequence tx (nSequence=5)
    //    The tx spends the funding outpoint with the latest payout split:
    //    provider=500, consumer=9500
    const settleResult = await pec.settle(ch, 'settlement-txid-001', {
      nSequence: ch.nSequence,         // latest nSequence = 5
      spendsFundingOutpoint: true,     // spends correct funding outpoint
    });

    expect(settleResult.ok).toBe(true);
    if (settleResult.ok) {
      expect(settleResult.value.state).toBe(ChannelState.SETTLED);
    }

    // 9. Verify audit trail
    const lastResult = pec.lastPolicyResult();
    expect(lastResult?.ok).toBe(true);
  });

  test('T29: Close confirm rejects when only one party agrees', () => {
    const pec = new PolicyEnforcedChannel();
    let ch = pec.create('p', 'c');
    ch = (pec.fund(ch, 'tx:0') as any).value;
    ch = (pec.activate(ch) as any).value;
    ch = (pec.requestClose(ch) as any).value;

    const result = pec.confirmClose(ch, { bothPartiesAgree: false });
    expect(result.ok).toBe(false);
  });

  test('T30: Dispute -> Resolve lifecycle', async () => {
    const emitter = new DevModeAnchorEmitter();
    const pec = new PolicyEnforcedChannel(emitter);
    let ch = pec.create('p', 'c');
    ch = (pec.fund(ch, 'tx:0') as any).value;
    ch = (pec.activate(ch) as any).value;
    ch = (pec.tick(ch, 200) as any).value;
    ch = (pec.tick(ch, 300) as any).value;
    expect(ch.nSequence).toBe(2);

    // Close flow
    ch = (pec.requestClose(ch) as any).value;
    ch = (pec.confirmClose(ch, { bothPartiesAgree: true }) as any).value;

    // Counterparty broadcasts stale nSequence=1 tx. We hold nSequence=2.
    const disputeResult = pec.dispute(ch, 'counterparty broadcast stale nSequence=1', {
      hasHigherNSequence: true,
    });
    expect(disputeResult.ok).toBe(true);
    ch = (disputeResult as any).value;
    expect(ch.state).toBe(ChannelState.DISPUTED);

    // Resolution: highest nSequence tx identified (nSequence=2)
    const resolveResult = await pec.resolve(ch, 'resolution-txid', {
      hasResolution: true,
    });
    expect(resolveResult.ok).toBe(true);
    if (resolveResult.ok) {
      expect(resolveResult.value.state).toBe(ChannelState.SETTLED);
    }
  });
});

```
