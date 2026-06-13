---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/few-shot.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.138172+00:00
---

# runtime/legacy-ingest/src/__tests__/few-shot.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { CorrectionEdgeStore } from '../ratification/store';
import { FewShotRetriever } from '../ratification/few-shot';
import type { CorrectionEdge } from '../ratification/types';
import type { GrantPersistence } from '../grant-store';

class MemoryPersistence implements GrantPersistence {
  store = new Map<string, Uint8Array>();
  async read(k: string) { return this.store.get(k) ?? null; }
  async write(k: string, v: Uint8Array) { this.store.set(k, v); }
  async delete(k: string) { this.store.delete(k); }
  async list(prefix: string) { return [...this.store.keys()].filter(k => k.startsWith(prefix)); }
}

async function makeStore(): Promise<CorrectionEdgeStore> {
  const kek = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
  return new CorrectionEdgeStore({
    persistence: new MemoryPersistence(),
    kekProvider: async () => kek,
  });
}

function makeCorrection(id: string, opts: { pinned?: boolean; createdAt: string; reason?: string }): CorrectionEdge {
  return {
    correctionId: id, proposalId: id + '-prop', providerId: 'gmail',
    original: {} as any, corrected: {} as any,
    reason: opts.reason ?? null,
    source: { extractorVersion: 'v1', promptHash: 'h1' },
    createdAt: opts.createdAt, pinned: opts.pinned ?? false,
  };
}

describe('FewShotRetriever', () => {
  test('returns most-recent K corrections, pinned first, reversed for prompt order', async () => {
    const store = await makeStore();
    await store.put(makeCorrection('a', { createdAt: '2024-01-01' }));
    await store.put(makeCorrection('b', { createdAt: '2025-01-01' }));
    await store.put(makeCorrection('c', { createdAt: '2026-01-01' }));
    await store.put(makeCorrection('d', { createdAt: '2023-01-01', pinned: true }));
    const r = new FewShotRetriever({ store, k: 3 });
    const got = await r.retrieve('gmail');
    expect(got.length).toBe(3);
    // Pinned first internally (d), then most recent (c, b); reverse → b, c, d
    expect(got.map(c => c.correctionId)).toEqual(['b', 'c', 'd']);
  });

  test('renders to a prompt block', async () => {
    const store = await makeStore();
    await store.put(makeCorrection('a', { createdAt: '2024-01-01', reason: 'wrong intent' }));
    const r = new FewShotRetriever({ store });
    const got = await r.retrieve('gmail');
    const rendered = FewShotRetriever.renderBlock(got);
    expect(rendered).toContain('Past corrections from the operator');
    expect(rendered).toContain('Reason: wrong intent');
  });

  test('renders empty string when no corrections exist', async () => {
    const store = await makeStore();
    const r = new FewShotRetriever({ store });
    expect(FewShotRetriever.renderBlock(await r.retrieve('gmail'))).toBe('');
  });
});

```
