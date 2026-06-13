---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/__tests__/forwarding-payment.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.860847+00:00
---

# core/protocol-types/__tests__/forwarding-payment.test.ts

```ts
/**
 * Forwarding-payment plan tests.
 *
 * Spec source: `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md` §4.1 + §13.5.
 * Verifies the pure-data plan composes with the pushdrop codec and that
 * the BSV-correct (no-CLTV) nLockTime semantics are modelled.
 */
import { describe, expect, test } from 'bun:test';
import { CELL_SIZE } from '../src/constants';
import {
  buildForwardingPaymentPlan,
  buildPathPaymentPlans,
  totalPathCostSats,
  isRefundLockTimeInFuture,
  type HopPayment,
} from '../src/mnca/forwarding-payment';
import {
  parsePushdropLockingScript,
  buildPushdropLockingScript,
  COMPRESSED_PUBKEY_SIZE,
  OP_DROP,
  OP_CHECKSIG,
} from '../src/cell-pushdrop';

function cell(seed: number): Uint8Array {
  const c = new Uint8Array(CELL_SIZE);
  for (let i = 0; i < CELL_SIZE; i++) c[i] = (i * 7 + seed) & 0xff;
  return c;
}
function pubkey(seed: number): Uint8Array {
  const p = new Uint8Array(COMPRESSED_PUBKEY_SIZE);
  p[0] = 0x02;
  for (let i = 1; i < COMPRESSED_PUBKEY_SIZE; i++) p[i] = (i + seed) & 0xff;
  return p;
}
const REFUND_SCRIPT = new Uint8Array([0x76, 0xa9, 0x14, /* ...p2pkh-ish placeholder... */ 0x88, 0xac]);

describe('buildForwardingPaymentPlan — single hop', () => {
  test('produces a pushdrop funding output + nLockTime refund template', () => {
    const c = cell(1);
    const hopPk = pubkey(5);
    const plan = buildForwardingPaymentPlan({
      cellBytes: c,
      hopPubkey: hopPk,
      paymentSats: 50n,
      originatorRefundScript: REFUND_SCRIPT,
      nLockTime: 800_000,
      hopIndex: 2,
    });

    expect(plan.hopIndex).toBe(2);
    expect(plan.funding.satoshis).toBe(50n);
    expect(Array.from(plan.funding.hopPubkey)).toEqual(Array.from(hopPk));

    // Refund template: pre-signed, both parties, nLockTime carries the timelock.
    expect(plan.refund.spendsFundingOutput).toBe(true);
    expect(plan.refund.nLockTime).toBe(800_000);
    expect(plan.refund.requiresSignatures).toEqual(['hop', 'originator']);
    expect(Array.from(plan.refund.refundToScript)).toEqual(Array.from(REFUND_SCRIPT));
  });

  test('funding locking script parses back to the original cell + hop pubkey', () => {
    const c = cell(42);
    const hopPk = pubkey(9);
    const plan = buildForwardingPaymentPlan({
      cellBytes: c,
      hopPubkey: hopPk,
      paymentSats: 100n,
      originatorRefundScript: REFUND_SCRIPT,
      nLockTime: 1,
    });
    const parsed = parsePushdropLockingScript(plan.funding.lockingScript);
    expect(Array.from(parsed.cellBytes)).toEqual(Array.from(c));
    expect(Array.from(parsed.pubkey)).toEqual(Array.from(hopPk));
  });

  test('funding script is a plain pushdrop with NO timelock opcodes (BSV: no CLTV/CSV)', () => {
    const c = cell(0);
    const hopPk = pubkey(0);
    const plan = buildForwardingPaymentPlan({
      cellBytes: c,
      hopPubkey: hopPk,
      paymentSats: 10n,
      originatorRefundScript: REFUND_SCRIPT,
      nLockTime: 500_000,
    });
    const s = plan.funding.lockingScript;

    // The no-CLTV/CSV guarantee is STRUCTURAL, not a byte-scan: the cell
    // data inside the push can contain any byte (incl. 0xb1/0xb2), so we
    // can't scan for opcodes. Instead, the strict parser proves the script
    // is EXACTLY `<cell> OP_DROP <pubkey> OP_CHECKSIG` with no other
    // opcodes — and rebuilding from the parsed parts reproduces it byte-
    // for-byte (no hidden trailing opcodes).
    const parsed = parsePushdropLockingScript(s);
    expect(Array.from(parsed.cellBytes)).toEqual(Array.from(c));
    expect(Array.from(parsed.pubkey)).toEqual(Array.from(hopPk));
    const rebuilt = buildPushdropLockingScript(parsed.cellBytes, parsed.pubkey);
    expect(Array.from(rebuilt)).toEqual(Array.from(s));

    // The only two opcodes (outside the data pushes) are OP_DROP then
    // OP_CHECKSIG. For a 1024-byte cell the push prefix is 3 bytes, so
    // OP_DROP sits at offset 3+1024 and OP_CHECKSIG is the final byte.
    expect(s[3 + CELL_SIZE]).toBe(OP_DROP);
    expect(s[s.length - 1]).toBe(OP_CHECKSIG);
  });

  test('rejects non-positive payment, negative/non-integer nLockTime, empty refund script', () => {
    const base = {
      cellBytes: cell(0),
      hopPubkey: pubkey(0),
      paymentSats: 10n,
      originatorRefundScript: REFUND_SCRIPT,
      nLockTime: 1,
    };
    expect(() => buildForwardingPaymentPlan({ ...base, paymentSats: 0n })).toThrow();
    expect(() => buildForwardingPaymentPlan({ ...base, paymentSats: -5n })).toThrow();
    expect(() => buildForwardingPaymentPlan({ ...base, nLockTime: -1 })).toThrow();
    expect(() => buildForwardingPaymentPlan({ ...base, nLockTime: 1.5 })).toThrow();
    expect(() => buildForwardingPaymentPlan({ ...base, originatorRefundScript: new Uint8Array(0) })).toThrow();
  });
});

describe('buildPathPaymentPlans — full path', () => {
  test('one plan per hop, index-aligned with the path', () => {
    const c = cell(3);
    const hops: HopPayment[] = [
      { hopPubkey: pubkey(1), paymentSats: 20n },
      { hopPubkey: pubkey(2), paymentSats: 30n },
      { hopPubkey: pubkey(3), paymentSats: 50n },
    ];
    const plans = buildPathPaymentPlans({
      cellBytes: c,
      hops,
      originatorRefundScript: REFUND_SCRIPT,
      nLockTime: 800_000,
    });
    expect(plans.length).toBe(3);
    for (let i = 0; i < 3; i++) {
      expect(plans[i]!.hopIndex).toBe(i);
      expect(plans[i]!.funding.satoshis).toBe(hops[i]!.paymentSats);
      // Each funding output recovers the same cell + the matching hop pubkey —
      // so a relay at spendSegmentIndex i claims plans[i].
      const parsed = parsePushdropLockingScript(plans[i]!.funding.lockingScript);
      expect(Array.from(parsed.cellBytes)).toEqual(Array.from(c));
      expect(Array.from(parsed.pubkey)).toEqual(Array.from(hops[i]!.hopPubkey));
    }
  });

  test('rejects an empty hop list', () => {
    expect(() =>
      buildPathPaymentPlans({
        cellBytes: cell(0),
        hops: [],
        originatorRefundScript: REFUND_SCRIPT,
        nLockTime: 1,
      }),
    ).toThrow();
  });
});

describe('cost + nLockTime helpers', () => {
  test('totalPathCostSats sums every hop payment', () => {
    const plans = buildPathPaymentPlans({
      cellBytes: cell(0),
      hops: [
        { hopPubkey: pubkey(1), paymentSats: 20n },
        { hopPubkey: pubkey(2), paymentSats: 30n },
        { hopPubkey: pubkey(3), paymentSats: 50n },
      ],
      originatorRefundScript: REFUND_SCRIPT,
      nLockTime: 800_000,
    });
    expect(totalPathCostSats(plans)).toBe(100n);
  });

  test('totalPathCostSats of an empty array is 0', () => {
    expect(totalPathCostSats([])).toBe(0n);
  });

  test('isRefundLockTimeInFuture compares against now in the same unit', () => {
    const plan = buildForwardingPaymentPlan({
      cellBytes: cell(0),
      hopPubkey: pubkey(0),
      paymentSats: 10n,
      originatorRefundScript: REFUND_SCRIPT,
      nLockTime: 800_000,
    });
    expect(isRefundLockTimeInFuture(plan, 799_999)).toBe(true);
    expect(isRefundLockTimeInFuture(plan, 800_000)).toBe(false); // not strictly future
    expect(isRefundLockTimeInFuture(plan, 800_001)).toBe(false);
  });
});

```
