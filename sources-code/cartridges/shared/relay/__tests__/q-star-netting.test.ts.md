---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/relay/__tests__/q-star-netting.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.440740+00:00
---

# cartridges/shared/relay/__tests__/q-star-netting.test.ts

```ts
/**
 * Q* netting tests.
 *
 * CW Lift L1 (docs/canon/cw-lift-matrix.yml).
 *
 * Asserts the four invariants from the Q* algorithm:
 *   (1) sum(allocations) === totalSats          conservation
 *   (2) 0 ≤ R < n                                bounded remainder
 *   (3) |allocation_i - balance_i/k| < 1         per-party error
 *   (4) deterministic across input ordering      reproducibility (ish — see below)
 *
 * Note on (4): the algorithm's tie-break is by SMALLER INDEX, which
 * means the OUTPUT order is fixed but the result IS sensitive to input
 * order (reordering parties relabels who gets the +1 grant on ties).
 * This is correct behaviour — the algorithm is deterministic given a
 * fixed party-index assignment, which is what we get from the channel
 * setup (parties enroll once, get a stable index).
 */

import { describe, expect, test } from 'bun:test';
import { qStarNetting, type QStarInput } from '../q-star-netting';

describe('CW Lift L1: Q* netting', () => {
  describe('happy path — small worked examples', () => {
    test('2-party even split (no remainder needed)', () => {
      // 1000 micro-units each at k=10 → 100 sats each, sum=200, k*S=200*10=2000 ✓
      const r = qStarNetting({ balances: [1000n, 1000n], k: 10, totalSats: 200 });
      expect(r.allocations).toEqual([100n, 100n]);
      expect(r.remainderDistributed).toBe(0);
      expect(r.breakdown[0].gotPlus1).toBe(false);
      expect(r.breakdown[1].gotPlus1).toBe(false);
    });

    test('3-party with remainder — top-R by remainder, tie-break by index', () => {
      // k=10, S=20 ⇒ sum=200. balances = [73, 76, 51].
      // floors = [7, 7, 5]; remainders = [3, 6, 1].
      // floorSum = 19; R = 20 - 19 = 1.
      // top-R=1 by remainder DESC: index 1 (r=6). So +1 to party 1.
      const r = qStarNetting({ balances: [73, 76, 51], k: 10, totalSats: 20 });
      expect(r.allocations).toEqual([7n, 8n, 5n]);
      expect(r.allocations.reduce((a, b) => a + b, 0n)).toBe(20n);
      expect(r.remainderDistributed).toBe(1);
      expect(r.breakdown[1].gotPlus1).toBe(true);
      expect(r.breakdown[0].gotPlus1).toBe(false);
      expect(r.breakdown[2].gotPlus1).toBe(false);
    });

    test('tie-break by smaller index', () => {
      // k=10, S=21 ⇒ sum=210. balances = [55, 65, 90]. All have remainder 5, 5, 0.
      // floors = [5, 6, 9]; remainders = [5, 5, 0].
      // floorSum = 20; R = 1.
      // top-R=1 by remainder DESC: parties 0 and 1 tie (both r=5).
      // Tie-break by smaller index → party 0 gets the +1.
      const r = qStarNetting({ balances: [55, 65, 90], k: 10, totalSats: 21 });
      expect(r.allocations).toEqual([6n, 6n, 9n]);
      expect(r.breakdown[0].gotPlus1).toBe(true);
      expect(r.breakdown[1].gotPlus1).toBe(false);
    });
  });

  describe('invariant (1) — conservation: sum(allocations) === totalSats', () => {
    const cases: { name: string; input: QStarInput }[] = [
      { name: 'n=2, R=0', input: { balances: [50, 50], k: 10, totalSats: 10 } },
      { name: 'n=4, R near n-1', input: { balances: [11, 12, 13, 14], k: 10, totalSats: 5 } },
      { name: 'n=10, varied', input: {
        balances: [97, 53, 1, 88, 12, 45, 78, 90, 30, 6],
        k: 10, totalSats: 50,
      }},
    ];
    for (const c of cases) {
      test(c.name, () => {
        const r = qStarNetting(c.input);
        const sum = r.allocations.reduce((a, b) => a + b, 0n);
        expect(sum).toBe(BigInt(c.input.totalSats as number));
      });
    }
  });

  describe('invariant (2) — bounded remainder: 0 ≤ R < n', () => {
    test('R < n for many random-but-valid inputs', () => {
      // Generate balances summing to k*S; check R always < n.
      // (Deterministic — no Math.random — using a counter.)
      for (let n = 2; n <= 12; n++) {
        for (let kInt = 1; kInt <= 16; kInt++) {
          for (let S = 1; S <= 20; S++) {
            // Construct balances that sum to kInt*S deterministically:
            // give the last party the residue.
            const balances: number[] = [];
            let acc = 0;
            for (let i = 0; i < n - 1; i++) {
              const v = (i * 7 + kInt * 3 + S) % (kInt * S + 1);
              if (acc + v <= kInt * S) {
                balances.push(v);
                acc += v;
              } else {
                balances.push(0);
              }
            }
            balances.push(kInt * S - acc);
            const r = qStarNetting({ balances, k: kInt, totalSats: S });
            expect(r.remainderDistributed).toBeGreaterThanOrEqual(0);
            expect(r.remainderDistributed).toBeLessThan(n);
          }
        }
      }
    });
  });

  describe('invariant (3) — bounded per-party error', () => {
    test('|allocation - balance/k| < 1 for every party', () => {
      const r = qStarNetting({
        balances: [97, 53, 1, 88, 12, 45, 78, 90, 30, 6],
        k: 10, totalSats: 50,
      });
      for (const b of r.breakdown) {
        // allocation_i ∈ {floor_i, floor_i + 1}, and balance_i/k ∈ [floor_i, floor_i + 1).
        // So |allocation - balance/k| is at most 1 (strict for non-integer balance/k).
        const balanceAsRational = Number(b.balance) / 10;
        const allocAsNum = Number(b.allocation);
        expect(Math.abs(allocAsNum - balanceAsRational)).toBeLessThan(1);
      }
    });
  });

  describe('invariant (4) — determinism', () => {
    test('same input → same output (multiple invocations)', () => {
      const input: QStarInput = {
        balances: [73n, 76n, 51n, 42n, 88n],
        k: 10n,
        totalSats: 33n,
      };
      const r1 = qStarNetting(input);
      const r2 = qStarNetting(input);
      const r3 = qStarNetting(input);
      expect(r1.allocations).toEqual(r2.allocations);
      expect(r2.allocations).toEqual(r3.allocations);
      expect(r1.remainderDistributed).toBe(r2.remainderDistributed);
    });
  });

  describe('precondition checks (fail-closed)', () => {
    test('rejects empty balances', () => {
      expect(() => qStarNetting({ balances: [], k: 10, totalSats: 0 })).toThrow('non-empty');
    });

    test('rejects non-positive k', () => {
      expect(() => qStarNetting({ balances: [10], k: 0, totalSats: 0 })).toThrow('positive integer');
      expect(() => qStarNetting({ balances: [10], k: -5, totalSats: 0 })).toThrow('positive integer');
    });

    test('rejects negative balances', () => {
      expect(() => qStarNetting({ balances: [10, -5], k: 10, totalSats: 1 })).toThrow('non-negative');
    });

    test('rejects negative totalSats', () => {
      expect(() => qStarNetting({ balances: [10], k: 10, totalSats: -1 })).toThrow('non-negative');
    });

    test('rejects conservation violation (sum(balances) !== k*S)', () => {
      expect(() => qStarNetting({ balances: [55, 65], k: 10, totalSats: 100 })).toThrow('conservation');
    });

    test('rejects non-integer numeric inputs', () => {
      expect(() => qStarNetting({ balances: [10.5], k: 10, totalSats: 1 })).toThrow('integer');
      expect(() => qStarNetting({ balances: [10], k: 1.5, totalSats: 7 })).toThrow('integer');
    });
  });

  describe('large-scale + bigint correctness', () => {
    test('handles micro-sat scale (k = 1_000_000)', () => {
      // 1 million micro-sats per sat; party with 1.5 sats worth.
      // balances = [1_500_000, 500_000] ⇒ 2 sats total at k=1_000_000.
      const r = qStarNetting({
        balances: [1_500_000n, 500_000n],
        k: 1_000_000n,
        totalSats: 2n,
      });
      // floors = [1, 0], remainders = [500_000, 500_000]; floorSum = 1; R = 1.
      // Tie on remainders, smaller index wins → party 0 gets +1.
      expect(r.allocations).toEqual([2n, 0n]);
    });

    test('handles values beyond Number.MAX_SAFE_INTEGER via bigint', () => {
      const big = 9_007_199_254_740_993n; // 2^53 + 1, beyond JS safe-int
      const r = qStarNetting({
        balances: [big, 1n],
        k: 1n,
        totalSats: big + 1n,
      });
      expect(r.allocations).toEqual([big, 1n]);
      expect(r.remainderDistributed).toBe(0);
    });
  });

  describe('Skyminer-shaped scenario — 8-party sub-satoshi state on a 9-sat channel', () => {
    test('8 relays, k=1000 (milli-sats), evenly distributed → tie-break by index', () => {
      // Channel: 8 parties, S=9 sats funded. Total micro-units = 9 * 1000 = 9000.
      // State: each party holds 1125 milli-sats (channel sum invariant satisfied).
      // floors = [1,1,1,1,1,1,1,1]; remainders = [125,125,125,125,125,125,125,125]
      // floorSum = 8; R = 9 - 8 = 1.
      // All tied on remainders → tie-break by smaller index → party 0 gets +1.
      const balances = new Array(8).fill(1125);
      const r = qStarNetting({ balances, k: 1000, totalSats: 9 });
      expect(r.remainderDistributed).toBe(1);
      expect(r.allocations).toEqual([2n, 1n, 1n, 1n, 1n, 1n, 1n, 1n]);
      expect(r.allocations.reduce((a, b) => a + b, 0n)).toBe(9n);
    });

    test('8 relays, k=1000, varied state with multiple non-trivial remainders', () => {
      // Channel: 8 parties, S=10 sats funded. Total micro-units = 10_000.
      // State distributes credits unevenly after routing activity.
      // balances summing to 10_000: [1800, 1200, 800, 950, 1100, 1500, 1400, 1250]
      // sums to 10_000 ✓ → k*S=10*1000=10000 ✓
      // floors = [1, 1, 0, 0, 1, 1, 1, 1]; floorSum = 6; R = 10 - 6 = 4
      // remainders = [800, 200, 800, 950, 100, 500, 400, 250]
      // sorted by (rem DESC, idx ASC): idx 3 (950), 0 (800), 2 (800), 5 (500), 6 (400), 7 (250), 1 (200), 4 (100)
      // top-4: parties 3, 0, 2, 5 → each gets +1.
      const balances = [1800, 1200, 800, 950, 1100, 1500, 1400, 1250];
      const r = qStarNetting({ balances, k: 1000, totalSats: 10 });
      expect(r.remainderDistributed).toBe(4);
      expect(r.allocations).toEqual([2n, 1n, 1n, 1n, 1n, 2n, 1n, 1n]);
      expect(r.allocations.reduce((a, b) => a + b, 0n)).toBe(10n);
    });
  });
});

```
