---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/__tests__/AttentionWeightLearner.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.108857+00:00
---

# runtime/services/src/services/__tests__/AttentionWeightLearner.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { AttentionWeightLearner, BASELINE_WEIGHTS } from '../AttentionWeightLearner';
import type { AttentionInteractionRecord } from '../AttentionTelemetry';

function rec(kind: string, ctx: 'field' | 'desk' | 'night' | null = null, itemId: string = 'a'): AttentionInteractionRecord {
  return {
    id: `r-${Math.random()}`,
    timestamp: Date.now(),
    hatId: null,
    context: ctx,
    interaction: { kind, itemId } as any,
  };
}

describe('AttentionWeightLearner', () => {
  test('cold start: drift suppressed for first 100 interactions', () => {
    const w = new AttentionWeightLearner();
    for (let i = 0; i < 99; i++) w.observe(rec('tapped'), 'recency');
    expect(w.getWeights('default').recency).toBeCloseTo(BASELINE_WEIGHTS.recency);
  });

  test('positive drift on tap nudges dominant factor up', () => {
    const w = new AttentionWeightLearner();
    // Burn warmup.
    for (let i = 0; i < 100; i++) w.observe(rec('tapped'), 'recency');
    // Now drift one step.
    const before = w.getWeights('default').recency;
    w.observe(rec('tapped'), 'recency');
    const after = w.getWeights('default').recency;
    expect(after).toBeGreaterThan(before);
  });

  test('negative drift on dismiss nudges dominant factor down', () => {
    const w = new AttentionWeightLearner();
    for (let i = 0; i < 100; i++) w.observe(rec('tapped'), 'recency');
    const before = w.getWeights('default').deadline;
    w.observe(rec('dismissed'), 'deadline');
    const after = w.getWeights('default').deadline;
    expect(after).toBeLessThan(before);
  });

  test('weights re-normalise to ~1.0 after drift', () => {
    const w = new AttentionWeightLearner();
    for (let i = 0; i < 110; i++) w.observe(rec('tapped'), 'recency');
    const ws = w.getWeights('default');
    const sum = ws.recency + ws.deadline + ws.active_work + ws.goal_alignment + ws.pending_action + ws.external_signal;
    expect(sum).toBeCloseTo(1.0, 3);
  });

  test('weights stay floored at 0.05', () => {
    const w = new AttentionWeightLearner();
    for (let i = 0; i < 100; i++) w.observe(rec('tapped'), 'goal_alignment');
    // Many dismissals on the same factor.
    for (let i = 0; i < 1000; i++) w.observe(rec('dismissed'), 'goal_alignment');
    const ws = w.getWeights('default');
    expect(ws.goal_alignment).toBeGreaterThanOrEqual(0.05);
  });

  test('selectProfile maps context tag to profile', () => {
    const w = new AttentionWeightLearner();
    expect(w.selectProfile('field')).toBe('field');
    expect(w.selectProfile('desk')).toBe('desk');
    expect(w.selectProfile(null)).toBe('default');
  });

  test('field profile up-weights deadline + active_work over default', () => {
    const w = new AttentionWeightLearner();
    const fieldW = w.getWeights('field');
    const defaultW = w.getWeights('default');
    expect(fieldW.deadline).toBeGreaterThan(defaultW.deadline);
    expect(fieldW.active_work).toBeGreaterThan(defaultW.active_work);
  });

  test('night profile heavily up-weights pending_action', () => {
    const w = new AttentionWeightLearner();
    const nightW = w.getWeights('night');
    expect(nightW.pending_action).toBeGreaterThan(0.3);
  });

  test('batchUpdate auto-boosts highly-engaged classes', () => {
    const w = new AttentionWeightLearner();
    const records: AttentionInteractionRecord[] = [];
    for (let i = 0; i < 10; i++) records.push(rec('tapped', null, `item-job-${i}`));
    for (let i = 0; i < 10; i++) records.push(rec('dismissed', null, `item-news-${i}`));
    const itemPath = (id: string): string | null => {
      if (id.startsWith('item-job')) return 'trades.job';
      if (id.startsWith('item-news')) return 'newsletter';
      return null;
    };
    w.batchUpdate(records, itemPath);
    const m = w.getClassMultipliers('default');
    expect(m['trades.job'] ?? 1).toBeGreaterThan(1);
    expect(m['newsletter'] ?? 1).toBeLessThan(1);
  });
});

```
