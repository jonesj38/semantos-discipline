---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/ingest-worker.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.151226+00:00
---

# runtime/legacy-ingest/src/__tests__/ingest-worker.test.ts

```ts
import { describe, expect, test, beforeEach } from 'bun:test';
import { IngestWorker } from '../ingest-worker';
import { LegacyBlobStore } from '../blob-store';
import { CursorStore } from '../cursor-store';
import type { GrantPersistence } from '../grant-store';
import type {
  AccessToken,
  Cursor,
  LegacyGrant,
  LegacyProvider,
  ListPageResult,
  RawItem,
} from '../types';
import { GmailRateLimited } from '../providers/gmail';

class MemoryPersistence implements GrantPersistence {
  store = new Map<string, Uint8Array>();
  async read(k: string) { return this.store.get(k) ?? null; }
  async write(k: string, v: Uint8Array) { this.store.set(k, v); }
  async delete(k: string) { this.store.delete(k); }
  async list(prefix: string) { return [...this.store.keys()].filter(k => k.startsWith(prefix)); }
}

async function makeKek(): Promise<CryptoKey> {
  return crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}

const grant: LegacyGrant = {
  grantId: 'g-1',
  providerId: 'gmail',
  createdAt: '0',
  lastRefreshedAt: null,
  accountLabel: null,
  hatId: null,
  token: {
    accessToken: 'AT', refreshToken: 'RT',
    expiresAt: Date.now() + 3600_000, scopes: '', providerExtras: {},
  },
};

class FakeProvider implements LegacyProvider {
  readonly id = 'gmail';
  readonly displayName = 'Gmail';
  readonly oauthScopes = [];
  readonly oauthAuthorizeUrl = '';
  readonly oauthTokenUrl = '';
  readonly oauthRevokeUrl = null;

  pages: Array<{ items: RawItem[]; nextCursor: Cursor }>;
  listCalls = 0;
  fetchFullCalls = 0;
  rateLimitOnListCalls: Set<number> = new Set();

  constructor(pages: Array<{ items: RawItem[]; nextCursor: Cursor }>) {
    this.pages = pages;
  }

  async listPage(_t: AccessToken, opts: { cursor: Cursor }): Promise<ListPageResult> {
    this.listCalls += 1;
    if (this.rateLimitOnListCalls.has(this.listCalls)) {
      throw new GmailRateLimited(new Response('', {
        status: 429, headers: { 'retry-after': '0' },
      }));
    }
    const idx = opts.cursor === null ? 0 : Number(opts.cursor);
    return this.pages[idx] ?? { items: [], nextCursor: null };
  }

  async fetchFull(_t: AccessToken, item: RawItem): Promise<RawItem> {
    this.fetchFullCalls += 1;
    return {
      ...item,
      contentType: 'email/rfc822',
      bytes: new TextEncoder().encode(`full ${item.providerItemId}`),
    };
  }

  fingerprint(item: RawItem): string { return `gmail:${item.providerItemId}`; }
}

function makePreview(id: string): RawItem {
  return {
    providerId: 'gmail', providerItemId: id, fetchedAt: Date.now(),
    contentType: 'gmail/preview', bytes: new Uint8Array(0), metadata: {},
  };
}

describe('IngestWorker', () => {
  let blobStore: LegacyBlobStore;
  let cursorStore: CursorStore;
  let worker: IngestWorker;

  beforeEach(async () => {
    const kek = await makeKek();
    const persistence = new MemoryPersistence();
    blobStore = new LegacyBlobStore({ persistence, kekProvider: async () => kek });
    cursorStore = new CursorStore({ persistence });
    worker = new IngestWorker({
      blobStore,
      cursorStore,
      grantResolver: async () => grant,
    });
  });

  test('walks all pages until nextCursor is null', async () => {
    const provider = new FakeProvider([
      { items: [makePreview('a'), makePreview('b')], nextCursor: '1' },
      { items: [makePreview('c')], nextCursor: '2' },
      { items: [makePreview('d')], nextCursor: null },
    ]);
    const cp = await worker.backfill(provider);
    expect(cp.completed).toBe(true);
    expect(cp.itemsPersisted).toBe(4);
    expect(cp.pagesProcessed).toBe(3);
    expect(provider.listCalls).toBe(3);
    expect(provider.fetchFullCalls).toBe(4);
    expect(await blobStore.count('gmail')).toBe(4);
  });

  test('emits the full persisted raw item to the unified message-patch hook', async () => {
    const seen: RawItem[] = [];
    worker = new IngestWorker({
      blobStore,
      cursorStore,
      grantResolver: async () => grant,
      onItemPersisted: (item) => {
        seen.push(item);
      },
    });
    const provider = new FakeProvider([
      { items: [makePreview('a')], nextCursor: null },
    ]);

    await worker.backfill(provider);

    expect(seen).toHaveLength(1);
    expect(seen[0]?.providerItemId).toBe('a');
    expect(seen[0]?.contentType).toBe('email/rfc822');
    expect(new TextDecoder().decode(seen[0]?.bytes)).toBe('full a');
  });

  test('message-patch hook failures do not block raw blob ingest', async () => {
    worker = new IngestWorker({
      blobStore,
      cursorStore,
      grantResolver: async () => grant,
      onItemPersisted: () => {
        throw new Error('sink offline');
      },
    });
    const provider = new FakeProvider([
      { items: [makePreview('a')], nextCursor: null },
    ]);

    const cp = await worker.backfill(provider);

    expect(cp.itemsPersisted).toBe(1);
    expect(await blobStore.count('gmail')).toBe(1);
  });

  test('checkpointed mid-run, resumes from where it left off', async () => {
    const provider = new FakeProvider([
      { items: [makePreview('a'), makePreview('b')], nextCursor: '1' },
      { items: [makePreview('c')], nextCursor: '2' },
      { items: [makePreview('d')], nextCursor: null },
    ]);
    // First run — only 1 page.
    const partial = await worker.backfill(provider, { maxPages: 1 });
    expect(partial.completed).toBe(false);
    expect(partial.cursor).toBe('1');
    expect(partial.itemsPersisted).toBe(2);

    // Second run — picks up from cursor='1'
    const final = await worker.backfill(provider);
    expect(final.completed).toBe(true);
    expect(final.itemsPersisted).toBe(4);
    expect(provider.listCalls).toBe(3); // 1 + 2
  });

  test('rate-limit on first listPage call retries and succeeds', async () => {
    const provider = new FakeProvider([
      { items: [makePreview('a')], nextCursor: null },
    ]);
    provider.rateLimitOnListCalls.add(1);
    const cp = await worker.backfill(provider);
    expect(cp.completed).toBe(true);
    expect(cp.itemsPersisted).toBe(1);
    expect(provider.listCalls).toBe(2); // first throws, second succeeds
  });

  test('skipFetchFull bypasses fetchFull (used by adapters with full bodies in list)', async () => {
    const provider = new FakeProvider([
      { items: [makePreview('a')], nextCursor: null },
    ]);
    await worker.backfill(provider, { skipFetchFull: true });
    expect(provider.fetchFullCalls).toBe(0);
  });

  test('cancel terminates the loop at the next page boundary', async () => {
    const provider = new FakeProvider([
      { items: [makePreview('a')], nextCursor: '1' },
      { items: [makePreview('b')], nextCursor: '2' },
      { items: [makePreview('c')], nextCursor: null },
    ]);
    const onProgress = (p: { pagesProcessed: number }): void => {
      if (p.pagesProcessed === 1) {
        worker.cancel('gmail', 'g-1');
      }
    };
    worker = new IngestWorker({
      blobStore, cursorStore,
      grantResolver: async () => grant,
      onProgress,
    });
    const cp = await worker.backfill(provider);
    expect(cp.pagesProcessed).toBe(1);
    expect(cp.completed).toBe(false);
  });

  test('throws when no grant resolves for the provider', async () => {
    const noGrantWorker = new IngestWorker({
      blobStore, cursorStore,
      grantResolver: async () => null,
    });
    const provider = new FakeProvider([]);
    await expect(noGrantWorker.backfill(provider)).rejects.toThrow(/no grant/);
  });

  test('isRunning reports correctly during a run', async () => {
    let observed = false;
    const provider = new FakeProvider([
      { items: [makePreview('a')], nextCursor: null },
    ]);
    worker = new IngestWorker({
      blobStore, cursorStore,
      grantResolver: async () => grant,
      onProgress: () => {
        observed = worker.isRunning('gmail', 'g-1');
      },
    });
    expect(worker.isRunning('gmail', 'g-1')).toBe(false);
    await worker.backfill(provider);
    expect(observed).toBe(true);
    expect(worker.isRunning('gmail', 'g-1')).toBe(false);
  });
});

```
