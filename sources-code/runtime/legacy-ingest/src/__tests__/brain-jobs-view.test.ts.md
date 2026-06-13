---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/brain-jobs-view.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.144858+00:00
---

# runtime/legacy-ingest/src/__tests__/brain-jobs-view.test.ts

```ts
/**
 * T9 follow-up — BrainJobsView conformance tests.
 *
 * Acceptance gate: implements the JobsView seam; caches the fetcher
 * result per session; filters by service tag + active state; gracefully
 * degrades to stale cache on fetcher errors after first success.
 */

import { describe, test, expect } from 'bun:test';
import { BrainJobsView } from '../brain-jobs-view';
import { resolveJobReference } from '../chat-resolver';
import type { JobSummary } from '../chat-resolver';

function job(overrides: Partial<JobSummary> & { cellId: string }): JobSummary {
  return {
    cellId: overrides.cellId,
    services: overrides.services ?? [],
    state: overrides.state ?? 'lead',
    displayName: overrides.displayName,
    siteId: overrides.siteId ?? null,
    issuanceDate: overrides.issuanceDate ?? null,
  };
}

/* ──────────────────────────────────────────────────────────────────────
 * Filter semantics
 * ────────────────────────────────────────────────────────────────────── */

describe('BrainJobsView: filtering', () => {
  test('active-state filter excludes completed / closed / paid', async () => {
    const all: JobSummary[] = [
      job({ cellId: 'A', state: 'lead', services: ['plumbing'] }),
      job({ cellId: 'B', state: 'completed', services: ['plumbing'] }),
      job({ cellId: 'C', state: 'closed', services: ['plumbing'] }),
      job({ cellId: 'D', state: 'paid', services: ['plumbing'] }),
      job({ cellId: 'E', state: 'in_progress', services: ['plumbing'] }),
      job({ cellId: 'F', state: 'invoiced', services: ['plumbing'] }),
    ];
    const view = new BrainJobsView({ fetcher: async () => all });
    const active = await view.findActiveByServices(['plumbing']);
    const ids = active.map(j => j.cellId).sort();
    expect(ids).toEqual(['A', 'E', 'F']);
  });

  test('services filter uses set intersection (any-of)', async () => {
    const view = new BrainJobsView({
      fetcher: async () => [
        job({ cellId: 'A', services: ['pergola', 'carpentry'] }),
        job({ cellId: 'B', services: ['roof-repair'] }),
        job({ cellId: 'C', services: ['plumbing', 'leak-investigation'] }),
      ],
    });
    const r = await view.findActiveByServices(['pergola']);
    expect(r.map(j => j.cellId)).toEqual(['A']);
    const r2 = await view.findActiveByServices(['leak-investigation', 'roof-repair']);
    expect(r2.map(j => j.cellId).sort()).toEqual(['B', 'C']);
  });

  test('empty services array returns all active jobs', async () => {
    const view = new BrainJobsView({
      fetcher: async () => [
        job({ cellId: 'A', state: 'lead' }),
        job({ cellId: 'B', state: 'completed' }),
        job({ cellId: 'C', state: 'scheduled' }),
      ],
    });
    const r = await view.findActiveByServices([]);
    expect(r.map(j => j.cellId).sort()).toEqual(['A', 'C']);
  });

  test('caller-supplied activeStates set overrides defaults', async () => {
    const view = new BrainJobsView({
      fetcher: async () => [
        job({ cellId: 'A', state: 'lead' }),
        job({ cellId: 'B', state: 'completed' }),
      ],
      activeStates: new Set(['completed']),
    });
    const r = await view.findActiveByServices([]);
    expect(r.map(j => j.cellId)).toEqual(['B']);
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Caching + TTL + coalesce
 * ────────────────────────────────────────────────────────────────────── */

describe('BrainJobsView: caching', () => {
  test('cache hit within TTL: fetcher called once across N queries', async () => {
    let calls = 0;
    const view = new BrainJobsView({
      fetcher: async () => {
        calls += 1;
        return [job({ cellId: 'A', services: ['plumbing'] })];
      },
      cacheTtlMs: 60_000,
    });
    await view.findActiveByServices(['plumbing']);
    await view.findActiveByServices(['plumbing']);
    await view.findActiveByServices([]);
    expect(calls).toBe(1);
  });

  test('cache miss after TTL', async () => {
    let now = 1000;
    let calls = 0;
    const view = new BrainJobsView({
      fetcher: async () => {
        calls += 1;
        return [];
      },
      cacheTtlMs: 100,
      clockFn: () => now,
    });
    await view.findActiveByServices([]);
    now += 50;
    await view.findActiveByServices([]); // still within TTL
    now += 100; // past TTL
    await view.findActiveByServices([]);
    expect(calls).toBe(2);
  });

  test('concurrent calls coalesce into one fetcher run', async () => {
    let calls = 0;
    let resolve: ((v: JobSummary[]) => void) | null = null;
    const view = new BrainJobsView({
      fetcher: () => {
        calls += 1;
        return new Promise<JobSummary[]>(r => {
          resolve = r;
        });
      },
    });
    // Fire 5 concurrent queries.
    const queries = Promise.all([
      view.findActiveByServices([]),
      view.findActiveByServices([]),
      view.findActiveByServices(['plumbing']),
      view.findActiveByServices(['roof-repair']),
      view.findActiveByServices([]),
    ]);
    // Resolve the in-flight fetcher.
    resolve!([job({ cellId: 'A', services: ['plumbing'] })]);
    await queries;
    expect(calls).toBe(1);
  });

  test('invalidate() forces next call to refetch', async () => {
    let calls = 0;
    const view = new BrainJobsView({
      fetcher: async () => {
        calls += 1;
        return [];
      },
      cacheTtlMs: 60_000,
    });
    await view.findActiveByServices([]);
    await view.findActiveByServices([]);
    view.invalidate();
    await view.findActiveByServices([]);
    expect(calls).toBe(2);
  });

  test('cachedCount reflects cache state', async () => {
    const view = new BrainJobsView({
      fetcher: async () => [job({ cellId: 'A' }), job({ cellId: 'B' })],
    });
    expect(view.cachedCount()).toBe(0);
    await view.findActiveByServices([]);
    expect(view.cachedCount()).toBe(2);
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * Graceful degradation
 * ────────────────────────────────────────────────────────────────────── */

describe('BrainJobsView: graceful degradation on fetcher error', () => {
  test('first-fetch error propagates', async () => {
    const view = new BrainJobsView({
      fetcher: async () => {
        throw new Error('connect_failed');
      },
    });
    let caught: unknown = null;
    try {
      await view.findActiveByServices([]);
    } catch (e) {
      caught = e;
    }
    expect(caught).toBeDefined();
    expect((caught as Error).message).toBe('connect_failed');
  });

  test('subsequent fetch error returns stale cache', async () => {
    let attempt = 0;
    let now = 1000;
    const view = new BrainJobsView({
      fetcher: async () => {
        attempt += 1;
        if (attempt === 1) return [job({ cellId: 'A', services: ['plumbing'] })];
        throw new Error('transient');
      },
      cacheTtlMs: 100,
      clockFn: () => now,
    });

    const r1 = await view.findActiveByServices(['plumbing']);
    expect(r1.map(j => j.cellId)).toEqual(['A']);

    // Move past TTL — next call attempts fetcher (throws), but the
    // stale cache is returned.
    now += 500;
    const r2 = await view.findActiveByServices(['plumbing']);
    expect(r2.map(j => j.cellId)).toEqual(['A']);
  });
});

/* ──────────────────────────────────────────────────────────────────────
 * End-to-end with the chat resolver
 * ────────────────────────────────────────────────────────────────────── */

describe('BrainJobsView + resolveJobReference: end-to-end', () => {
  test('"quote 500 for the pergola job" against a wired view', async () => {
    const view = new BrainJobsView({
      fetcher: async () => [
        job({ cellId: 'A'.repeat(64), services: ['pergola'], state: 'lead' }),
        job({ cellId: 'B'.repeat(64), services: ['plumbing'], state: 'lead' }),
        job({ cellId: 'C'.repeat(64), services: ['pergola'], state: 'completed' }), // filtered
      ],
    });
    const r = await resolveJobReference({
      utterance: 'quote 500 for the pergola job',
      jobsView: view,
    });
    expect(r.kind).toBe('match');
    if (r.kind === 'match') {
      expect(r.cellId).toBe('A'.repeat(64));
      expect(r.intent).toBe('quote');
    }
  });
});

```
