---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/__tests__/AttentionTelemetry.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.110030+00:00
---

# runtime/services/src/services/__tests__/AttentionTelemetry.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { AttentionTelemetry } from '../AttentionTelemetry';

describe('AttentionTelemetry', () => {
  test('records interactions with monotonic ids', async () => {
    const t = new AttentionTelemetry();
    const r1 = await t.record({ kind: 'tapped', itemId: 'a', rank: 0, relevance: 0.8, primaryReason: 'active_work' });
    const r2 = await t.record({ kind: 'opened', itemId: 'a', secondsViewed: 3 });
    expect(r1.id).not.toEqual(r2.id);
    expect(t.size()).toBe(2);
  });

  test('decorates records with hatId + context from providers', async () => {
    const t = new AttentionTelemetry();
    t.setHatIdProvider(() => 'hat-1');
    t.setContextProvider(() => 'field');
    const rec = await t.record({ kind: 'dismissed', itemId: 'b', explicit: true });
    expect(rec.hatId).toBe('hat-1');
    expect(rec.context).toBe('field');
  });

  test('query filters by since / kinds / itemId / limit', async () => {
    const t = new AttentionTelemetry();
    await t.record({ kind: 'tapped', itemId: 'a', rank: 0, relevance: 0.5, primaryReason: 'recency' });
    await t.record({ kind: 'tapped', itemId: 'b', rank: 1, relevance: 0.4, primaryReason: 'recency' });
    await t.record({ kind: 'dismissed', itemId: 'a', explicit: true });
    expect(t.query({ kinds: ['tapped'] }).length).toBe(2);
    expect(t.query({ itemId: 'a' }).length).toBe(2);
    expect(t.query({ limit: 1 }).length).toBe(1);
  });

  test('aggregateByItem counts interactions per kind', async () => {
    const t = new AttentionTelemetry();
    await t.record({ kind: 'tapped', itemId: 'x', rank: 0, relevance: 0.5, primaryReason: 'recency' });
    await t.record({ kind: 'tapped', itemId: 'x', rank: 0, relevance: 0.5, primaryReason: 'recency' });
    await t.record({ kind: 'dismissed', itemId: 'x', explicit: false });
    const agg = t.aggregateByItem();
    const x = agg.get('x')!;
    expect(x.tapped).toBe(2);
    expect(x.dismissed).toBe(1);
  });

  test('persistFn is called per record; failure is non-fatal', async () => {
    const t = new AttentionTelemetry();
    let calls = 0;
    t.setPersistFn(async () => {
      calls += 1;
      if (calls === 2) throw new Error('disk full');
    });
    await t.record({ kind: 'tapped', itemId: 'a', rank: 0, relevance: 0.1, primaryReason: 'recency' });
    await t.record({ kind: 'tapped', itemId: 'b', rank: 0, relevance: 0.1, primaryReason: 'recency' });
    expect(calls).toBe(2);
    expect(t.size()).toBe(2);
  });

  test('trim drops records older than cutoff', async () => {
    const t = new AttentionTelemetry();
    await t.record({ kind: 'tapped', itemId: 'a', rank: 0, relevance: 0.5, primaryReason: 'recency' });
    await new Promise(resolve => setTimeout(resolve, 5));
    const cutoff = Date.now();
    await new Promise(resolve => setTimeout(resolve, 5));
    await t.record({ kind: 'tapped', itemId: 'b', rank: 0, relevance: 0.5, primaryReason: 'recency' });
    const dropped = t.trim(cutoff);
    expect(dropped).toBeGreaterThanOrEqual(1);
    expect(t.query({ itemId: 'b' }).length).toBe(1);
  });
});

```
