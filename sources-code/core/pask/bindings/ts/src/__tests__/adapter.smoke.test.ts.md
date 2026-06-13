---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/bindings/ts/src/__tests__/adapter.smoke.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.935186+00:00
---

# core/pask/bindings/ts/src/__tests__/adapter.smoke.test.ts

```ts
/**
 * End-to-end smoke test for the Pask TS bindings.
 *
 * Loads pask.wasm from disk, runs a synthetic mini-rig, asserts the
 * structural learning invariants. This is the same kind of check the
 * Zig interact_conformance test performs, but exercising the JS↔WASM
 * boundary too — catches struct-offset drift, encoder/decoder bugs,
 * scratch-pointer aliasing.
 */

import { describe, it, expect } from 'bun:test';
import { readFileSync } from 'node:fs';
import path from 'node:path';

import { loadPask } from '../loader';
import { PaskAdapter } from '../adapter';

const WASM_PATH = path.resolve(import.meta.dir, '../../../../zig-out/bin/pask.wasm');

async function fresh(config?: Parameters<typeof PaskAdapter.prototype.constructor>[1]) {
  const bytes = readFileSync(WASM_PATH);
  const pask = await loadPask(bytes);
  return new PaskAdapter(pask, config);
}

describe('PaskAdapter smoke', () => {
  it('records edge weight on a single interact', async () => {
    const a = await fresh({ stabilityCheckEvery: 0, pruneEvery: 0, propagationDepth: 0 });
    await a.interact({
      cellId: 'A',
      kind: 'test',
      strength: 1.0,
      relatedCells: ['B'],
      nowMs: 100,
    });
    const A = a.getNode('A')!;
    const B = a.getNode('B')!;
    expect(A).not.toBeNull();
    expect(B).not.toBeNull();
    expect(A.hState).toBeCloseTo(1.0, 9);
    // Edge A→B should have weight = 1.0 * 0.1 (default lr) = 0.1
    const snap = a.snapshot();
    const edge = snap.edges.find((e) => e.fromCell === 'A' && e.toCell === 'B');
    expect(edge).toBeDefined();
    expect(edge!.constraintWeight).toBeCloseTo(0.1, 9);
  });

  it('high-traffic edges accumulate weight; rare edges stay weak', async () => {
    const a = await fresh({ stabilityCheckEvery: 0, pruneEvery: 0, propagationDepth: 0 });
    let clock = 0;
    for (let i = 0; i < 30; i++) {
      clock++;
      await a.interact({ cellId: 'root', kind: 'test', strength: 1, relatedCells: ['A1'], nowMs: clock });
      clock++;
      await a.interact({ cellId: 'A1', kind: 'test', strength: 1, relatedCells: ['B1'], nowMs: clock });
    }
    clock++;
    await a.interact({ cellId: 'root', kind: 'test', strength: 1, relatedCells: ['A2'], nowMs: clock });

    const snap = a.snapshot();
    const heavy = snap.edges.find((e) => e.fromCell === 'root' && e.toCell === 'A1');
    const rare = snap.edges.find((e) => e.fromCell === 'root' && e.toCell === 'A2');
    expect(heavy).toBeDefined();
    expect(rare).toBeDefined();
    expect(heavy!.interactionCount).toBeGreaterThanOrEqual(30);
    expect(rare!.interactionCount).toBe(1);
    expect(heavy!.constraintWeight).toBeGreaterThan(rare!.constraintWeight);
  });

  it('snapshot/restore round-trips state', async () => {
    const a = await fresh({ stabilityCheckEvery: 0, pruneEvery: 0 });
    await a.interact({ cellId: 'X', kind: 'k', strength: 0.5, relatedCells: ['Y'], nowMs: 1 });
    const blob = a.exportSnapshotBlob();
    const before = a.getNode('X')!;
    // Mutate
    await a.interact({ cellId: 'X', kind: 'k', strength: 0.5, relatedCells: ['Y'], nowMs: 2 });
    expect(a.getNode('X')!.hState).toBeGreaterThan(before.hState);
    a.importSnapshotBlob(blob);
    expect(a.getNode('X')!.hState).toBeCloseTo(before.hState, 9);
  });

  it('zero-copy views: nodesView/edgesView reflect kernel state', async () => {
    const a = await fresh({ stabilityCheckEvery: 0, pruneEvery: 0, propagationDepth: 0 });
    await a.interact({ cellId: 'X', kind: 'k', strength: 0.5, relatedCells: ['Y'], nowMs: 1 });

    const nodes = a.nodesView();
    expect(nodes.count).toBe(2);
    expect(nodes.stride).toBe(208); // sizeof(Node) — comptime-locked in main.zig
    expect(nodes.bytes.length).toBe(nodes.count * nodes.stride);

    const edges = a.edgesView();
    expect(edges.count).toBe(1);
    expect(edges.stride).toBe(40); // sizeof(Edge)
    // First u32 of edge 0 is from_idx — should be 0 (the X node).
    const view = new DataView(edges.bytes.buffer, edges.bytes.byteOffset, edges.bytes.byteLength);
    expect(view.getUint32(0, true)).toBe(0);
    expect(view.getUint32(4, true)).toBe(1);
  });

  it('stableThreadsRange: slice [n..nx] without per-element calls', async () => {
    const a = await fresh({
      stabilityCheckEvery: 0,
      pruneEvery: 0,
      propagationDepth: 0,
      stabilityEpsilon: 1e9, // force everything stable for the ordering test
      minInteractions: 1,
    });
    let clock = 0;
    // Distinct h_state values for ordering.
    for (let i = 0; i < 10; i++) {
      clock++;
      const cellId = `n${i}`;
      const strength = (10 - i) / 10; // descending strengths → descending h
      await a.interact({ cellId, kind: 'k', strength, relatedCells: ['edge'], nowMs: clock });
    }
    a.finalize(clock + 1);

    // Pull only [2, 5) — 3 records.
    const slice = a.stableThreadsRange(2, 5);
    expect(slice.hState.length).toBe(3);
    // Ordering: each subsequent h_state is <= the previous.
    for (let i = 1; i < slice.hState.length; i++) {
      expect(slice.hState[i - 1]).toBeGreaterThanOrEqual(slice.hState[i]);
    }
  });

  it('stableThreads returns nodes ordered by h_state desc', async () => {
    // Build a tiny graph where the high-h node is unambiguous, then run
    // finalize() to push stability updates. We can't rely on natural
    // stabilization at this scale, so we set a permissive epsilon.
    const a = await fresh({
      stabilityCheckEvery: 0,
      pruneEvery: 0,
      propagationDepth: 0,
      stabilityEpsilon: 1e9, // anything is "stable" — we test ordering, not detection
      minInteractions: 1,
    });
    let clock = 0;
    for (let i = 0; i < 5; i++) {
      clock++;
      await a.interact({ cellId: 'big', kind: 'k', strength: 1, relatedCells: ['edge'], nowMs: clock });
    }
    clock++;
    await a.interact({ cellId: 'small', kind: 'k', strength: 0.1, relatedCells: ['edge'], nowMs: clock });
    a.finalize(clock + 1);
    const stable = a.stableThreads();
    expect(stable.length).toBeGreaterThan(0);
    // Ordering check: h_state values are non-increasing.
    for (let i = 1; i < stable.length; i++) {
      expect(stable[i - 1].hState).toBeGreaterThanOrEqual(stable[i].hState);
    }
  });
});

```
