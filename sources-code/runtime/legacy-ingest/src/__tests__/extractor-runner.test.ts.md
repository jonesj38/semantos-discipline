---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/extractor-runner.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.154694+00:00
---

# runtime/legacy-ingest/src/__tests__/extractor-runner.test.ts

```ts
import { describe, expect, test, beforeEach } from 'bun:test';
import { LegacyBlobStore } from '../blob-store';
import { ProposalStore } from '../proposal-store';
import { ExtractorRegistry } from '../extractor/registry';
import { ExtractionRunner } from '../extractor/runner';
import { EmailExtractor } from '../extractor/email';
import type { GrantPersistence } from '../grant-store';
import type { LLMAdapter } from '../extractor/types';
import type { RawItem } from '../types';

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

const REAL_EMAIL = `From: jane@example.com
Subject: Quote request
Message-ID: <m1@example.com>

Body asking for a quote.
`;

const NEWSLETTER = `From: news@bigco.com
Subject: Weekly Newsletter
List-Unsubscribe: <https://x>

Read this`;

function emailItem(id: string, content: string): RawItem {
  return {
    providerId: 'gmail',
    providerItemId: id,
    fetchedAt: Date.now(),
    contentType: 'email/rfc822',
    bytes: new TextEncoder().encode(content),
    metadata: {},
  };
}

function stubLLM(payload: unknown, confidence: number): LLMAdapter {
  return {
    async extract<T>() {
      return { payload: payload as T, confidence, raw: JSON.stringify(payload) };
    },
  };
}

describe('ExtractionRunner', () => {
  let blobStore: LegacyBlobStore;
  let proposalStore: ProposalStore;
  let registry: ExtractorRegistry;

  beforeEach(async () => {
    const kek = await makeKek();
    const persistence = new MemoryPersistence();
    blobStore = new LegacyBlobStore({ persistence, kekProvider: async () => kek });
    proposalStore = new ProposalStore({ persistence, kekProvider: async () => kek });
    registry = new ExtractorRegistry();
    registry.register(new EmailExtractor());
  });

  test('walks blobs, runs extractor, persists proposals', async () => {
    await blobStore.put(emailItem('a', REAL_EMAIL));
    await blobStore.put(emailItem('b', REAL_EMAIL));
    const runner = new ExtractionRunner({
      blobStore, proposalStore, registry,
      llm: stubLLM({ intent: 'lead', summary: 'Jane: quote' }, 0.9),
    });
    const summary = await runner.runForProvider('gmail');
    expect(summary.extracted).toBe(2);
    expect(summary.itemsExamined).toBe(2);
    const proposals = await proposalStore.list();
    expect(proposals.length).toBe(2);
  });

  test('pre-filtered items count separately and produce no proposal', async () => {
    await blobStore.put(emailItem('a', REAL_EMAIL));
    await blobStore.put(emailItem('b', NEWSLETTER));
    const runner = new ExtractionRunner({
      blobStore, proposalStore, registry,
      llm: stubLLM({ intent: 'lead', summary: 'Jane: quote' }, 0.9),
    });
    const summary = await runner.runForProvider('gmail');
    expect(summary.extracted).toBe(1);
    expect(summary.preFiltered).toBe(1);
  });

  test('low-confidence items count separately', async () => {
    await blobStore.put(emailItem('a', REAL_EMAIL));
    const runner = new ExtractionRunner({
      blobStore, proposalStore, registry,
      llm: stubLLM({ intent: 'other', summary: '?' }, 0.2),
    });
    const summary = await runner.runForProvider('gmail');
    expect(summary.extracted).toBe(0);
    expect(summary.lowConfidence).toBe(1);
  });

  test('default mode skips items already extracted', async () => {
    await blobStore.put(emailItem('a', REAL_EMAIL));
    const runner = new ExtractionRunner({
      blobStore, proposalStore, registry,
      llm: stubLLM({ intent: 'lead', summary: 's' }, 0.9),
    });
    const first = await runner.runForProvider('gmail');
    expect(first.extracted).toBe(1);
    const second = await runner.runForProvider('gmail');
    expect(second.extracted).toBe(0);
  });

  test('force=true re-extracts and supersedes prior proposals', async () => {
    await blobStore.put(emailItem('a', REAL_EMAIL));
    const runner = new ExtractionRunner({
      blobStore, proposalStore, registry,
      llm: stubLLM({ intent: 'lead', summary: 'first' }, 0.9),
    });
    await runner.runForProvider('gmail');
    const runner2 = new ExtractionRunner({
      blobStore, proposalStore, registry,
      llm: stubLLM({ intent: 'lead', summary: 'second' }, 0.9),
    });
    const r = await runner2.runForProvider('gmail', { force: true });
    expect(r.extracted).toBe(1);
    const all = await proposalStore.list();
    const statuses = all.map(p => p.status).sort();
    expect(statuses).toEqual(['pending', 'superseded']);
  });

  test('no-extractor counts items whose contentType has no registered extractor', async () => {
    await blobStore.put({
      providerId: 'gmail', providerItemId: 'x', fetchedAt: 0,
      contentType: 'gmail/preview', bytes: new Uint8Array(0), metadata: {},
    });
    const runner = new ExtractionRunner({
      blobStore, proposalStore, registry,
      llm: stubLLM({}, 1),
    });
    const summary = await runner.runForProvider('gmail');
    expect(summary.noExtractor).toBe(1);
    expect(summary.extracted).toBe(0);
  });
});

```
