---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/cursor-store.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.142576+00:00
---

# runtime/legacy-ingest/src/__tests__/cursor-store.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { CursorStore } from '../cursor-store';
import type { GrantPersistence } from '../grant-store';
import type { IngestCheckpoint } from '../cursor-store';

class MemoryPersistence implements GrantPersistence {
  store = new Map<string, Uint8Array>();
  async read(k: string) { return this.store.get(k) ?? null; }
  async write(k: string, v: Uint8Array) { this.store.set(k, v); }
  async delete(k: string) { this.store.delete(k); }
  async list(prefix: string) { return [...this.store.keys()].filter(k => k.startsWith(prefix)); }
}

function makeCheckpoint(over: Partial<IngestCheckpoint> = {}): IngestCheckpoint {
  return {
    providerId: 'gmail',
    grantId: 'g-1',
    cursor: 'page-2',
    since: null,
    highWatermark: 1000,
    pagesProcessed: 1,
    itemsPersisted: 100,
    lastUpdatedAt: '2026-04-28T00:00:00.000Z',
    completed: false,
    ...over,
  };
}

describe('CursorStore', () => {
  test('put → get round-trip', async () => {
    const store = new CursorStore({ persistence: new MemoryPersistence() });
    const cp = makeCheckpoint();
    await store.put(cp);
    const got = await store.get('gmail', 'g-1');
    expect(got).toEqual(cp);
  });

  test('get returns null for missing checkpoint', async () => {
    const store = new CursorStore({ persistence: new MemoryPersistence() });
    expect(await store.get('gmail', 'no-such')).toBeNull();
  });

  test('listByProvider returns all grants for that provider', async () => {
    const store = new CursorStore({ persistence: new MemoryPersistence() });
    await store.put(makeCheckpoint({ grantId: 'g-1' }));
    await store.put(makeCheckpoint({ grantId: 'g-2' }));
    const all = await store.listByProvider('gmail');
    expect(all.length).toBe(2);
    expect(all.map(c => c.grantId).sort()).toEqual(['g-1', 'g-2']);
  });

  test('delete removes the checkpoint', async () => {
    const store = new CursorStore({ persistence: new MemoryPersistence() });
    await store.put(makeCheckpoint());
    await store.delete('gmail', 'g-1');
    expect(await store.get('gmail', 'g-1')).toBeNull();
  });
});

```
