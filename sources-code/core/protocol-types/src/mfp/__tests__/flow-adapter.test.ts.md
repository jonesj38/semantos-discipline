---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/mfp/__tests__/flow-adapter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.908443+00:00
---

# core/protocol-types/src/mfp/__tests__/flow-adapter.test.ts

```ts
/**
 * MFP consumer flow-adapter tests.
 *
 * Drives the adapter against a mock BRC-100 WalletPort that enforces a
 * Tier-0 spending cap (createAction returns cap_exceeded once the cap is
 * reached — exactly how a real wallet's no-prompt Tier-0 budget behaves).
 * No browser, no real wallet — the adapter targets the WalletPort seam,
 * so this is the same code path the iframe wallet / Metanet Desktop /
 * Dolphin Milk plug into.
 */

import { describe, test, expect } from 'bun:test';
import {
  MfpFlowAdapter,
  type WalletPort,
  type WalletCreateActionArgs,
  type WalletCreateActionResult,
  type WalletCreateSignatureArgs,
  type WalletCreateSignatureResult,
} from '../flow-adapter.js';
import { mfpProtocolID, assertValidProtocolString } from '../protocol-id.js';

// Mock wallet with a Tier-0 cap. Tracks how much it has committed; once
// the cap is reached, createAction denies (cap_exceeded) — the wallet is
// the spending authority, the adapter just reacts.
function mockWallet(capSats: bigint) {
  let committed = 0n;
  const calls = { createAction: 0, createSignature: 0 };
  const port: WalletPort = {
    async createAction(a: WalletCreateActionArgs): Promise<WalletCreateActionResult> {
      calls.createAction++;
      if (committed >= capSats) return { ok: false, reason: 'cap_exceeded' };
      const grantable = a.amountSats <= capSats - committed ? a.amountSats : capSats - committed;
      committed += grantable;
      return { ok: true, txid: `tx${calls.createAction}`, committedSats: grantable };
    },
    async createSignature(_a: WalletCreateSignatureArgs): Promise<WalletCreateSignatureResult> {
      calls.createSignature++;
      // Deterministic stand-in signature — the device verifies the real
      // one via OP_CHECKSIG; here we only exercise the adapter logic.
      return { ok: true, signature: new Uint8Array([0xde, 0xad, calls.createSignature & 0xff]) };
    },
  };
  return { port, calls, committed: () => committed };
}

const COUNTERPARTY = '02'.padEnd(66, 'a'); // dummy compressed pubkey hex

describe('MFP protocolID', () => {
  test('builds a valid BRC-43 protocol string per commodity', () => {
    const [level, proto] = mfpProtocolID('energy.wh');
    expect(level).toBe(2);
    expect(proto).toBe('mfp metering energy wh');
    assertValidProtocolString(proto); // does not throw
  });

  test('distinct commodities → distinct protocol strings', () => {
    expect(mfpProtocolID('energy.wh')[1]).not.toBe(mfpProtocolID('bandwidth.mb')[1]);
  });

  test('rejects malformed protocol strings', () => {
    expect(() => assertValidProtocolString('a')).toThrow();          // too short
    expect(() => assertValidProtocolString('UPPER case')).toThrow(); // uppercase
    expect(() => assertValidProtocolString('double  space')).toThrow();
  });
});

describe('MFP metered flow — prepaid drain with Tier-0 auto-refill', () => {
  // 10W LED, 360 sats/Wh → 1 sat/sec. Cap 30 sats = ~30s of light.
  // We meter in Wh; rate is sats/Wh. 1 sec @ 10W = 10/3600 Wh.
  const WH_PER_SEC = 10 / 3600;
  const cfg = {
    commodityId: 'energy.wh',
    ratePerUnitSats: 360,           // sats per Wh
    counterparty: COUNTERPARTY,
    flowId: 'abcdef0123456789',
    fundMode: 'metered' as const,
    vaultCapSats: 30n,              // the single grant decision
    channelChunkSats: 10n,          // refill 10 sats at a time
    refillThresholdSats: 3n,        // refill when <3 sats of headroom
  };

  test('opens by drawing the first chunk from the vault', async () => {
    const w = mockWallet(cfg.vaultCapSats);
    const a = new MfpFlowAdapter(cfg, w.port);
    const r = await a.open();
    expect(r).toEqual({ kind: 'opened', state: expect.anything() } as any);
    const s = a.getState();
    expect(s.status).toBe('active');
    expect(s.fundedSats).toBe(10n);     // one chunk
    expect(s.vaultDrawnSats).toBe(10n);
    expect(w.calls.createAction).toBe(1);
  });

  test('drains, auto-refills, and exhausts exactly at the cap', async () => {
    const w = mockWallet(cfg.vaultCapSats);
    const a = new MfpFlowAdapter(cfg, w.port);
    await a.open();

    const commitments: bigint[] = [];
    let exhaustedAt = -1;
    // Report consumption second-by-second up to 40s (cap covers ~30s).
    for (let sec = 1; sec <= 40; sec++) {
      const step = await a.onConsumptionReport(sec * WH_PER_SEC);
      if (step.kind === 'commitment') {
        commitments.push(step.commitment.cumulativeSats);
        // seq strictly increases
        expect(step.commitment.seq).toBe(commitments.length);
      } else if (step.kind === 'exhausted') {
        exhaustedAt = sec;
        break;
      }
    }

    const s = a.getState();
    // Cap 30 sats, ~1 sat/sec, with a 3-sat refill headroom → exhausts
    // when cost can no longer stay 3 ahead under the cap (~cap−threshold).
    expect(exhaustedAt).toBeGreaterThanOrEqual(27);
    expect(exhaustedAt).toBeLessThanOrEqual(31);
    expect(s.status).toBe('exhausted');
    // The real "exhausted when no more funds to consume" invariant:
    // the vault was drawn down to exactly the cap, never beyond.
    expect(s.vaultDrawnSats).toBe(cfg.vaultCapSats);
    expect(w.committed()).toBe(cfg.vaultCapSats);
    // Cumulative commitments are monotonic non-decreasing.
    for (let i = 1; i < commitments.length; i++) {
      expect(commitments[i]).toBeGreaterThanOrEqual(commitments[i - 1]);
    }
  });

  test('pro-rata cost = units × rate', async () => {
    const w = mockWallet(1_000_000n); // effectively unlimited
    const a = new MfpFlowAdapter({ ...cfg, vaultCapSats: 1_000_000n, channelChunkSats: 1000n }, w.port);
    await a.open();
    const step = await a.onConsumptionReport(0.5); // 0.5 Wh
    expect(step.kind).toBe('commitment');
    if (step.kind === 'commitment') {
      // 0.5 Wh × 360 sats/Wh = 180 sats
      expect(step.commitment.cumulativeSats).toBe(180n);
    }
  });

  test('refill happens silently under cap (multiple createAction calls)', async () => {
    const w = mockWallet(cfg.vaultCapSats);
    const a = new MfpFlowAdapter(cfg, w.port);
    await a.open();                       // 1 createAction (first chunk)
    await a.onConsumptionReport(20 * WH_PER_SEC); // ~20 sats consumed → must refill past 10
    // Should have drawn more than the initial chunk without any failure.
    expect(w.calls.createAction).toBeGreaterThan(1);
    expect(a.getState().fundedSats).toBeGreaterThanOrEqual(20n);
  });
});

describe('MFP block flow — bounded grant, no channel', () => {
  const cfg = {
    commodityId: 'energy.wh',
    ratePerUnitSats: 360,
    counterparty: COUNTERPARTY,
    flowId: 'blockflow00000001',
    fundMode: 'block' as const,
    blockUnits: 1,                 // 1 Wh block
  };

  test('open() emits a single signed grant, no channel commitments', async () => {
    const w = mockWallet(1_000_000n);
    const a = new MfpFlowAdapter(cfg, w.port);
    const grant = await a.open();
    expect(grant).toHaveProperty('maxUnits', 1);
    expect(grant).toHaveProperty('maxSats', 360n);
    expect(w.calls.createSignature).toBe(1);   // one grant signature
    expect(w.calls.createAction).toBe(0);      // NO channel funding
  });

  test('consumption within bound is noop; over bound exhausts', async () => {
    const w = mockWallet(1_000_000n);
    const a = new MfpFlowAdapter(cfg, w.port);
    await a.open();
    const within = await a.onConsumptionReport(0.5); // 0.5 Wh < 1 Wh
    expect(within.kind).toBe('noop');
    expect(w.calls.createSignature).toBe(1); // no new signatures in block mode
    const over = await a.onConsumptionReport(1.5); // 1.5 Wh > 1 Wh bound
    expect(over.kind).toBe('exhausted');
  });
});

```
