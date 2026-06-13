---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/store/__tests__/settlement-store-integration.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.715981+00:00
---

# archive/apps-settlement/src/store/__tests__/settlement-store-integration.test.ts

```ts
/**
 * Integration test for the prompt-44 split: drive a delta sequence
 * through the `PaskianStore` facade, verify node/edge state matches
 * expectations, prune via the node store + pruner, and verify the
 * game-facing query surface returns the right results.
 *
 * The point of this test is to confirm that the per-concern modules
 * compose correctly when wired through the facade — i.e. the
 * external-facing API of `PaskianStore` still behaves the same as
 * the legacy 501-LOC `store.ts` did.
 */

import { describe, expect, test } from 'bun:test';

import { PaskianStore } from '../settlement-store';

describe('PaskianStore facade — integration', () => {
  test('apply a delta sequence: node/edge state, prune, and queries reflect the right state', () => {
    const store = new PaskianStore();

    // ── Seed three nodes — two of which will become a stable thread,
    //    one of which will weaken to a prune candidate.
    store.upsertNode({ cellId: 'hero', typePath: 'paskian.story.thread' });
    store.upsertNode({ cellId: 'mentor', typePath: 'paskian.story.thread' });
    store.upsertNode({ cellId: 'fade', typePath: 'paskian.story.thread' });

    // ── Build the constraint graph: hero ↔ mentor (strong),
    //    hero → fade (weakening).
    const heroToMentor = store.upsertEdge('hero', 'mentor');
    const mentorToHero = store.upsertEdge('mentor', 'hero');
    const heroToFade = store.upsertEdge('hero', 'fade');

    // Reinforcing deltas on hero↔mentor.
    for (let i = 0; i < 4; i++) {
      store.updateEdgeWeight(heroToMentor, 0.25);
      store.recordDelta(heroToMentor, 0.25, 'reinforce');
      store.updateEdgeWeight(mentorToHero, 0.25);
      store.recordDelta(mentorToHero, 0.25, 'reinforce');
    }

    // Negative trend on hero→fade.
    for (let i = 0; i < 4; i++) {
      store.updateEdgeWeight(heroToFade, -0.05);
      store.recordDelta(heroToFade, -0.05, 'fade');
    }

    // Set positive trends on the strong pair, negative on the fading.
    store.updateEdgeTrend(heroToMentor, 0.4);
    store.updateEdgeTrend(mentorToHero, 0.4);
    store.updateEdgeTrend(heroToFade, -0.5);

    // Apply h_state deltas reflecting the recorded interactions.
    store.updateNodeState('hero', 1.0);
    store.updateNodeState('mentor', 1.0);
    store.updateNodeState('fade', -0.4);

    // ── Verify per-concern state ──────────────────────────────────
    const hero = store.getNode('hero')!;
    const mentor = store.getNode('mentor')!;
    const fade = store.getNode('fade')!;
    expect(hero.hState).toBeCloseTo(1.0);
    expect(mentor.hState).toBeCloseTo(1.0);
    expect(fade.hState).toBeCloseTo(-0.4);

    expect(store.getEdge(heroToMentor)!.constraintWeight).toBeCloseTo(1.0);
    expect(store.getEdge(heroToFade)!.constraintWeight).toBeCloseTo(-0.2);

    // ── Inbound trend / avgDelta aggregates ───────────────────────
    expect(store.inboundTrend('mentor')).toBeCloseTo(0.4);
    expect(store.inboundTrend('fade')).toBeCloseTo(-0.5);
    expect(store.avgDelta(heroToMentor, 60_000)).toBeCloseTo(0.25);

    // ── Mark the strong pair stable, then verify queries ─────────
    store.markStable('hero', true);
    store.markStable('mentor', true);

    const stable = store.stableThreads().map((t) => t.cellId).sort();
    expect(stable).toEqual(['hero', 'mentor']);

    // ── Prune candidates: only `fade` falls below threshold 0 ────
    const candidates = store.pruningCandidates(0).map((n) => n.cellId);
    expect(candidates).toEqual(['fade']);

    // ── Apply the prune (mark + log) ─────────────────────────────
    store.markPruned('fade');
    store.recordPruning({
      cellId: 'fade',
      typePath: 'paskian.story.thread',
      reason: 'weak_constraint',
      finalHState: fade.hState,
      prunedAt: Date.now(),
      anchorTxid: null,
    });

    // ── Confirm `fade` is gone from active sets but still in snapshot
    expect(store.activeNodes().map((n) => n.cellId).sort()).toEqual([
      'hero',
      'mentor',
    ]);
    expect(store.snapshot().nodes).toHaveLength(3);

    // Pruning a stable node would still have left it in stableThreads;
    // but `fade` was never stable, so the count is unchanged.
    expect(store.stableThreads()).toHaveLength(2);

    store.close();
  });

  test('the deprecation shim still resolves PaskianStore identity', async () => {
    // Both the directory barrel and the legacy file path must export
    // the same class so `from './store'` and `from './store/index'`
    // resolve compatibly across the codebase.
    const { PaskianStore: ShimClass } = await import('../../store');
    const { PaskianStore: BarrelClass } = await import('../index');
    expect(ShimClass).toBe(BarrelClass);
  });

  test('replay 1k deltas: aggregates + per-row state are deterministic', () => {
    // The spec's test plan calls for replaying ≥1k deltas and
    // checking final node/edge state + stability output. We use
    // deterministic edges (round-robin between three pairs) and
    // deltas of `+0.001` so the cumulative weight is exact.
    const store = new PaskianStore();
    const PAIRS: Array<[string, string]> = [
      ['n0', 'n1'],
      ['n1', 'n2'],
      ['n2', 'n0'],
    ];
    for (const [from, to] of PAIRS) {
      store.upsertNode({ cellId: from, typePath: 't' });
      store.upsertNode({ cellId: to, typePath: 't' });
      store.upsertEdge(from, to);
    }

    const N = 1200;
    for (let i = 0; i < N; i++) {
      const [from, to] = PAIRS[i % PAIRS.length];
      const edgeId = `${from}-${to}`;
      store.recordDelta(edgeId, 0.001, 'replay');
      store.updateEdgeWeight(edgeId, 0.001);
      store.updateNodeState(to, 0.001);
    }

    // Each pair receives N/3 = 400 deltas; cumulative weight = 0.4
    for (const [from, to] of PAIRS) {
      const edge = store.getEdge(`${from}-${to}`)!;
      expect(edge.constraintWeight).toBeCloseTo(0.4, 5);
      expect(edge.interactionCount).toBe(N / PAIRS.length);
    }

    // Each node was the target of exactly one pair, so each gains 0.4
    for (const cellId of ['n0', 'n1', 'n2']) {
      const node = store.getNode(cellId)!;
      expect(node.hState).toBeCloseTo(0.4, 5);
      expect(node.interactionCount).toBe(N / PAIRS.length);
    }

    // avgDelta(|0.001|, ...) should equal 0.001 over the window.
    const avg = store.avgDelta('n0-n1', 60_000);
    expect(avg).toBeCloseTo(0.001, 5);

    store.close();
  });
});

```
