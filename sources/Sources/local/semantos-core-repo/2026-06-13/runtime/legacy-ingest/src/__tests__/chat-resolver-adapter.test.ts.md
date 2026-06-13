---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/chat-resolver-adapter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.143696+00:00
---

# runtime/legacy-ingest/src/__tests__/chat-resolver-adapter.test.ts

```ts
/**
 * T9 follow-up — ChatResolverAdapter conformance tests.
 *
 * Composes BrainJobsView + resolveJobReference into the PWA-facing
 * entry point. Tests the long-lived caching invariant + the
 * onCellMinted invalidation hook.
 */

import { describe, test, expect } from 'bun:test';
import { ChatResolverAdapter } from '../chat-resolver-adapter';
import type { JobSummary } from '../chat-resolver';

function job(o: Partial<JobSummary> & { cellId: string }): JobSummary {
  return {
    cellId: o.cellId,
    services: o.services ?? [],
    state: o.state ?? 'lead',
    displayName: o.displayName,
    siteId: o.siteId ?? null,
    issuanceDate: o.issuanceDate ?? null,
  };
}

describe('ChatResolverAdapter', () => {
  test('resolves a clean pergola query end-to-end', async () => {
    const adapter = new ChatResolverAdapter({
      jobsFetcher: async () => [
        job({ cellId: 'A'.repeat(64), services: ['pergola'] }),
        job({ cellId: 'B'.repeat(64), services: ['plumbing'] }),
      ],
    });
    const r = await adapter.resolve({ utterance: 'quote 500 for the pergola job' });
    expect(r.kind).toBe('match');
    if (r.kind === 'match') {
      expect(r.cellId).toBe('A'.repeat(64));
      expect(r.intent).toBe('quote');
    }
  });

  test('siteHint propagates through', async () => {
    const SITE_A = '1'.repeat(64);
    const SITE_B = '2'.repeat(64);
    const adapter = new ChatResolverAdapter({
      jobsFetcher: async () => [
        job({ cellId: 'A'.repeat(64), services: ['pergola'], siteId: SITE_A }),
        job({ cellId: 'B'.repeat(64), services: ['pergola'], siteId: SITE_B }),
      ],
    });
    const r = await adapter.resolve({
      utterance: 'quote the pergola',
      siteHint: SITE_A,
    });
    expect(r.kind).toBe('match');
    if (r.kind === 'match') expect(r.cellId).toBe('A'.repeat(64));
  });

  test('fetcher hit only once across multiple resolves (cached view)', async () => {
    let calls = 0;
    const adapter = new ChatResolverAdapter({
      jobsFetcher: async () => {
        calls += 1;
        return [job({ cellId: 'A'.repeat(64), services: ['pergola'] })];
      },
      cacheTtlMs: 60_000,
    });
    await adapter.resolve({ utterance: 'quote the pergola' });
    await adapter.resolve({ utterance: 'schedule the pergola' });
    await adapter.resolve({ utterance: 'complete the pergola' });
    expect(calls).toBe(1);
  });

  test('onCellMinted invalidates cache', async () => {
    let calls = 0;
    const adapter = new ChatResolverAdapter({
      jobsFetcher: async () => {
        calls += 1;
        return [];
      },
      cacheTtlMs: 60_000,
    });
    await adapter.resolve({ utterance: 'status update' });
    adapter.onCellMinted();
    await adapter.resolve({ utterance: 'status update' });
    expect(calls).toBe(2);
  });

  test('cachedCount reports after first resolve', async () => {
    const adapter = new ChatResolverAdapter({
      jobsFetcher: async () => [
        job({ cellId: 'A' }),
        job({ cellId: 'B' }),
        job({ cellId: 'C' }),
      ],
    });
    expect(adapter.cachedCount()).toBe(0);
    await adapter.resolve({ utterance: 'status' });
    expect(adapter.cachedCount()).toBe(3);
  });

  test('none result for empty job graph', async () => {
    const adapter = new ChatResolverAdapter({
      jobsFetcher: async () => [],
    });
    const r = await adapter.resolve({ utterance: 'quote the pergola' });
    expect(r.kind).toBe('none');
  });
});

```
