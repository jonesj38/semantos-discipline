---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/shared/relay/q-star-netting.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.437790+00:00
---

# cartridges/shared/relay/q-star-netting.ts

```ts
/**
 * Q* netting — deterministic sub-satoshi → whole-satoshi settlement.
 *
 * CW Lift L1 (docs/canon/cw-lift-matrix.yml).
 *
 * Ports the algorithm from prof-faustus/bonded-subsat-channel (MIT)
 * @ src/channel/accounting.py.
 *
 * The problem this solves:
 *   Cell-routing relays accumulate fractional credits in micro-units
 *   (sub-satoshi precision) between whole-sat on-chain settlements.
 *   When it's time to settle, we have an N-tuple of micro-unit balances
 *   that we need to collapse to N whole satoshis. The collapse MUST:
 *     (1) sum to exactly the funded amount S sats (conservation),
 *     (2) be deterministic across parties (every party computes the
 *         same allocation from the same state — no on-chain dispute),
 *     (3) bound the per-party rounding error to ≤ 1 sat,
 *     (4) be cheap (no on-chain dust per micro-credit).
 *
 * Algorithm Q*:
 *   Input: balances a = (a_1, ..., a_n) in micro-units; divisor k;
 *          total S sats where sum(a) = k * S.
 *
 *   Step 1: q_i^floor = floor(a_i / k)
 *           r_i = a_i mod k                     // 0 ≤ r_i < k
 *
 *   Step 2: R = S - sum(q_i^floor)              // provably 0 ≤ R < n
 *
 *   Step 3: rank parties by (r_i DESC, index ASC) and grant the top-R
 *           one extra satoshi each (tie-break by smaller index, fully
 *           deterministic).
 *
 *   Output: q_i = q_i^floor + (1 if i in top-R else 0); sum(q) = S.
 *
 * Invariants (proven by the bounds + asserted in tests):
 *   - sum(q) === S (conservation)
 *   - 0 ≤ R < n (sub-satoshi remainder never exceeds participant count)
 *   - |q_i - a_i/k| < 1 (per-party error bounded by 1 sat)
 *   - identical (a, k, S) → identical q on any platform (determinism)
 *
 * Use this in any semantos relay surface that accumulates
 * fractional-sat credits between settlements (CashLanes, mfp/flow-
 * adapter metered mode, future Skyminer-class cell-routing fee
 * accumulators).
 */

// ── Types ───────────────────────────────────────────────────────────

export interface QStarInput {
  /** Micro-unit balances per party, in submission order. Each value
   *  must be a non-negative integer (or bigint). The implementation
   *  operates on bigints throughout to avoid JS number precision
   *  hazards at large scale. */
  readonly balances: readonly (bigint | number)[];
  /** Divisor: how many micro-units make one satoshi (e.g. 1_000 for
   *  milli-sats, 1_000_000 for micro-sats). Must be a positive
   *  integer. */
  readonly k: bigint | number;
  /** Total satoshis being settled — caller's assertion of `sum(balances) / k`.
   *  Required for the conservation check; the algorithm verifies that
   *  `sum(balances) === k * S`. */
  readonly totalSats: bigint | number;
}

export interface QStarResult {
  /** Whole-satoshi allocation per party, in the same order as input
   *  balances. sum(allocations) === totalSats. */
  readonly allocations: readonly bigint[];
  /** Per-party (floor, remainder, gotPlus1) breakdown for audit. */
  readonly breakdown: readonly QStarBreakdown[];
  /** R = totalSats - sum(floors). 0 ≤ R < n. */
  readonly remainderDistributed: number;
}

export interface QStarBreakdown {
  /** Position in the input balances. */
  readonly index: number;
  /** Original micro-unit balance. */
  readonly balance: bigint;
  /** floor(balance / k). */
  readonly floor: bigint;
  /** balance mod k. */
  readonly remainder: bigint;
  /** Whether this party received the +1 sat tie-break grant. */
  readonly gotPlus1: boolean;
  /** Final allocation = floor + (gotPlus1 ? 1 : 0). */
  readonly allocation: bigint;
}

// ── Pure-function implementation ───────────────────────────────────

/**
 * Compute the Q* whole-satoshi allocation for an N-party state.
 *
 * Throws if:
 *   - balances is empty
 *   - k is not a positive integer
 *   - any balance is negative or not an integer
 *   - sum(balances) !== k * totalSats (conservation precondition)
 */
export function qStarNetting(input: QStarInput): QStarResult {
  const balances = input.balances.map(toBigInt);
  const k = toBigInt(input.k);
  const S = toBigInt(input.totalSats);

  if (balances.length === 0) {
    throw new Error('qStarNetting: balances must be non-empty');
  }
  if (k <= 0n) {
    throw new Error(`qStarNetting: k must be a positive integer (got ${k})`);
  }
  if (S < 0n) {
    throw new Error(`qStarNetting: totalSats must be non-negative (got ${S})`);
  }
  let sum = 0n;
  for (const b of balances) {
    if (b < 0n) {
      throw new Error(`qStarNetting: balances must be non-negative (got ${b})`);
    }
    sum += b;
  }
  if (sum !== k * S) {
    throw new Error(
      `qStarNetting: conservation precondition failed — sum(balances)=${sum} but k*S=${k * S}`,
    );
  }

  // Step 1: floors + remainders
  const n = balances.length;
  const floors = new Array<bigint>(n);
  const remainders = new Array<bigint>(n);
  let floorSum = 0n;
  for (let i = 0; i < n; i++) {
    floors[i] = balances[i] / k; // bigint division truncates toward 0; non-negative inputs ⇒ floor
    remainders[i] = balances[i] % k;
    floorSum += floors[i];
  }

  // Step 2: R = S - sum(floors). Bound: 0 ≤ R < n.
  const R_big = S - floorSum;
  if (R_big < 0n || R_big >= BigInt(n)) {
    // This is an algorithm-invariant violation; should be impossible
    // given the conservation precondition. Defensive throw.
    throw new Error(
      `qStarNetting: invariant R ∈ [0, n) violated — R=${R_big}, n=${n}`,
    );
  }
  const R = Number(R_big);

  // Step 3: rank by (remainder DESC, index ASC) and grant +1 to top-R.
  const indices = Array.from({ length: n }, (_, i) => i);
  indices.sort((a, b) => {
    if (remainders[a] !== remainders[b]) {
      return remainders[b] > remainders[a] ? 1 : -1;
    }
    return a - b; // tie-break: smaller index wins (the +1)
  });
  const gotPlus1 = new Array<boolean>(n).fill(false);
  for (let rank = 0; rank < R; rank++) {
    gotPlus1[indices[rank]] = true;
  }

  // Build allocations + breakdown
  const allocations = new Array<bigint>(n);
  const breakdown: QStarBreakdown[] = [];
  for (let i = 0; i < n; i++) {
    allocations[i] = floors[i] + (gotPlus1[i] ? 1n : 0n);
    breakdown.push({
      index: i,
      balance: balances[i],
      floor: floors[i],
      remainder: remainders[i],
      gotPlus1: gotPlus1[i],
      allocation: allocations[i],
    });
  }

  return {
    allocations,
    breakdown,
    remainderDistributed: R,
  };
}

// ── Helpers ─────────────────────────────────────────────────────────

function toBigInt(v: bigint | number): bigint {
  if (typeof v === 'bigint') return v;
  if (!Number.isInteger(v)) {
    throw new Error(`qStarNetting: expected integer, got ${v}`);
  }
  return BigInt(v);
}

```
