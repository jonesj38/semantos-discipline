---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/__tests__/two-kernel-harness.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.109465+00:00
---

# runtime/services/src/services/__tests__/two-kernel-harness.test.ts

```ts
/**
 * WI-C1 — Two-kernel single-process harness (TypeScript counterpart).
 *
 * Mirrors two_kernel_harness.zig: instantiates two PaskAdapter instances
 * from the same WASM bytes, drives them with configurable stream overlap,
 * and verifies the cross-kernel stability convergence invariants.
 *
 * Three test cases:
 *   WI-C1-T-disjoint-streams-no-convergence   — shared_fraction ≈ 0 → rate < 0.5
 *   WI-C1-T-identical-streams-full-convergence — shared_fraction = 1 → rate = 1
 *   WI-C1-T-partial-overlap-intermediate       — monotonic in shared content
 */

import { describe, it, expect, beforeAll } from 'bun:test';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { loadPask } from '@semantos/pask';
import { PaskAdapter } from '@semantos/pask';

const WASM_PATH = path.resolve(
  import.meta.dir,
  '../../../../../core/pask/zig-out/bin/pask.wasm',
);

let wasmBytes: Uint8Array;

beforeAll(() => {
  wasmBytes = readFileSync(WASM_PATH);
});

// ── Helpers ───────────────────────────────────────────────────────────────────

async function freshAdapter(): Promise<PaskAdapter> {
  const pask = await loadPask(wasmBytes);
  return new PaskAdapter(pask, {
    stabilityCheckEvery: 1,
    pruneEvery: 0,
    minInteractions: 3,
    // Small learning rate keeps deltas below stabilityEpsilon=0.01
    learningRate: 0.005,
  });
}

const ROUNDS = 60;

/** Stream A: root + {a1, b1, c1} */
async function driveStreamA(a: PaskAdapter): Promise<void> {
  let clock = 0;
  for (let i = 0; i < ROUNDS; i++) {
    clock++; await a.interact({ cellId: 'root', kind: 'k', strength: 1.0, relatedCells: ['a1', 'b1'], nowMs: clock });
    clock++; await a.interact({ cellId: 'a1',   kind: 'k', strength: 0.7, relatedCells: ['b1', 'c1'], nowMs: clock });
    clock++; await a.interact({ cellId: 'b1',   kind: 'k', strength: 0.4, relatedCells: ['c1'],        nowMs: clock });
    clock++; await a.interact({ cellId: 'c1',   kind: 'k', strength: 0.3, relatedCells: ['a1'],        nowMs: clock });
  }
}

/** Stream B: root + {a2, b2, c2} — disjoint domain cells from Stream A */
async function driveStreamB(b: PaskAdapter): Promise<void> {
  let clock = 0;
  for (let i = 0; i < ROUNDS; i++) {
    clock++; await b.interact({ cellId: 'root', kind: 'k', strength: 1.0, relatedCells: ['a2', 'b2'], nowMs: clock });
    clock++; await b.interact({ cellId: 'a2',   kind: 'k', strength: 0.7, relatedCells: ['b2', 'c2'], nowMs: clock });
    clock++; await b.interact({ cellId: 'b2',   kind: 'k', strength: 0.4, relatedCells: ['c2'],        nowMs: clock });
    clock++; await b.interact({ cellId: 'c2',   kind: 'k', strength: 0.3, relatedCells: ['a2'],        nowMs: clock });
  }
}

/**
 * Convergence rate: fraction of stable cells that are stable in BOTH kernels.
 *   both   = |{stable in A} ∩ {stable in B}|  (matched by cellId)
 *   either = |{stable in A} ∪ {stable in B}|
 *   rate   = both / max(1, either)
 */
function convergenceRate(a: PaskAdapter, b: PaskAdapter): number {
  const snapA = a.snapshot();
  const snapB = b.snapshot();

  const stableA = new Map<string, boolean>();
  for (const n of snapA.nodes) {
    if (!n.isPruned) stableA.set(n.cellId, n.isStable);
  }
  const stableB = new Map<string, boolean>();
  for (const n of snapB.nodes) {
    if (!n.isPruned) stableB.set(n.cellId, n.isStable);
  }

  let both = 0;
  let either = 0;

  const allIds = new Set([...stableA.keys(), ...stableB.keys()]);
  for (const id of allIds) {
    const sa = stableA.get(id) ?? false;
    const sb = stableB.get(id) ?? false;
    if (sa || sb) either++;
    if (sa && sb) both++;
  }
  return either === 0 ? 0 : both / either;
}

// ── WI-C1-T-disjoint-streams-no-convergence ───────────────────────────────────

describe('WI-C1-T-disjoint-streams-no-convergence', () => {
  it('convergence_rate < 0.5 when kernels see entirely different cell domains', async () => {
    const engA = await freshAdapter();
    const engB = await freshAdapter();
    await driveStreamA(engA);
    await driveStreamB(engB);
    const rate = convergenceRate(engA, engB);
    // Only `root` is shared; domain cells are disjoint → rate dominated by non-shared stable cells
    expect(rate).toBeLessThan(0.5);
  });
});

// ── WI-C1-T-identical-streams-full-convergence ────────────────────────────────

describe('WI-C1-T-identical-streams-full-convergence', () => {
  it('convergence_rate = 1 when both kernels receive identical interaction streams', async () => {
    const engA = await freshAdapter();
    const engB = await freshAdapter();
    await driveStreamA(engA);
    await driveStreamA(engB); // same stream
    const rate = convergenceRate(engA, engB);
    expect(rate).toBeCloseTo(1, 3);
  });
});

// ── WI-C1-T-partial-overlap-intermediate ─────────────────────────────────────

describe('WI-C1-T-partial-overlap-intermediate', () => {
  it('convergence_rate is monotonically ordered: disjoint ≤ partial ≤ identical', async () => {
    // Disjoint
    const [dA, dB] = [await freshAdapter(), await freshAdapter()];
    await driveStreamA(dA);
    await driveStreamB(dB);
    const rateDisjoint = convergenceRate(dA, dB);

    // Partial: kernel X gets both streams, kernel Y gets only B
    const [pX, pY] = [await freshAdapter(), await freshAdapter()];
    await driveStreamA(pX);
    await driveStreamB(pX);
    await driveStreamB(pY);
    const ratePartial = convergenceRate(pX, pY);

    // Identical
    const [iA, iB] = [await freshAdapter(), await freshAdapter()];
    await driveStreamA(iA);
    await driveStreamA(iB);
    const rateIdentical = convergenceRate(iA, iB);

    expect(ratePartial).toBeGreaterThanOrEqual(rateDisjoint);
    expect(rateIdentical).toBeGreaterThanOrEqual(ratePartial);
  });
});

```
