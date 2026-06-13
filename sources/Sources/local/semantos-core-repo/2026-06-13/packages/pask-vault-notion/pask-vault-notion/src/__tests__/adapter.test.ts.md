---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/pask-vault-notion/pask-vault-notion/src/__tests__/adapter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.444003+00:00
---

# packages/pask-vault-notion/pask-vault-notion/src/__tests__/adapter.test.ts

```ts
import { describe, test, expect, mock } from 'bun:test';
import { NotionAdapter } from '../adapter';
import { TokenBucket } from '../rate-limiter';
import type { NotionProvider } from '../notion-provider';

// ── TokenBucket ────────────────────────────────────────────────────────────

describe('TokenBucket', () => {
  test('allows immediate calls up to capacity', async () => {
    const bucket = new TokenBucket(3, 3);
    const start = Date.now();
    await bucket.acquire();
    await bucket.acquire();
    await bucket.acquire();
    // All three within the initial fill — should be instant
    expect(Date.now() - start).toBeLessThan(100);
  });

  test('throttles calls beyond capacity', async () => {
    const bucket = new TokenBucket(1, 10); // 10 tokens/s
    await bucket.acquire(); // uses the 1 initial token
    const start = Date.now();
    await bucket.acquire(); // must wait ~100ms for refill
    expect(Date.now() - start).toBeGreaterThanOrEqual(50);
  });
});

// ── NotionAdapter ──────────────────────────────────────────────────────────

function makeFakePask() {
  const calls: unknown[] = [];
  return {
    calls,
    interact: (args: unknown) => calls.push(args),
    stableThreads: () => [],
    distance: () => Infinity,
    ready: true,
  };
}

function makeProvider(pages = [], databases = []): NotionProvider {
  return {
    getWorkspaceInfo: async () => ({ workspaceId: 'ws-test' }),
    searchAll: async () => ({
      pages,
      databases,
      nextCursor: null,
    }),
  };
}

describe('NotionAdapter.coldStart', () => {
  test('seeds pages with backdated nowMs', async () => {
    const editedTime = new Date('2026-04-01T10:00:00Z').toISOString();
    const pask = makeFakePask();
    const provider = makeProvider(
      [
        {
          id: 'page-abc',
          last_edited_time: editedTime,
          parent: { type: 'workspace', workspace: true },
          properties: {},
        },
      ],
      [],
    );

    const adapter = new NotionAdapter({
      provider,
      paskGraph: pask as never,
      pollIntervalMs: 999_999, // don't auto-poll
    });

    await adapter.start();
    adapter.stop();

    expect(pask.calls.length).toBeGreaterThanOrEqual(1);
    const call = pask.calls[0] as Record<string, unknown>;
    expect(call['cellId']).toBe('nx:page:ws-test/page-abc');
    expect(call['kind']).toBe('seed');
    expect(call['strength']).toBe(0.1);
    expect(call['nowMs']).toBe(new Date(editedTime).getTime());
  });

  test('rows (pages in DB) use nx:row cell ID', async () => {
    const pask = makeFakePask();
    const provider = makeProvider(
      [
        {
          id: 'page-xyz',
          last_edited_time: new Date().toISOString(),
          parent: { type: 'database_id', database_id: 'db-001' },
          properties: {},
        },
      ],
      [],
    );

    const adapter = new NotionAdapter({
      provider,
      paskGraph: pask as never,
      pollIntervalMs: 999_999,
    });

    await adapter.start();
    adapter.stop();

    const call = pask.calls[0] as Record<string, unknown>;
    expect(call['cellId']).toBe('nx:row:db-001/page-xyz');
  });

  test('relation properties become relatedCells', async () => {
    const pask = makeFakePask();
    const provider = makeProvider(
      [
        {
          id: 'page-a',
          last_edited_time: new Date().toISOString(),
          parent: { type: 'workspace', workspace: true },
          properties: {
            Related: {
              type: 'relation',
              relation: [{ id: 'page-b' }, { id: 'page-c' }],
            },
          },
        },
      ],
      [],
    );

    const adapter = new NotionAdapter({
      provider,
      paskGraph: pask as never,
      pollIntervalMs: 999_999,
    });

    await adapter.start();
    adapter.stop();

    const call = pask.calls[0] as Record<string, unknown>;
    expect(call['relatedCells'] as string[]).toContain('nx:page:ws-test/page-b');
    expect(call['relatedCells'] as string[]).toContain('nx:page:ws-test/page-c');
  });

  test('select properties become nx:tag cells', async () => {
    const pask = makeFakePask();
    const provider = makeProvider(
      [
        {
          id: 'page-d',
          last_edited_time: new Date().toISOString(),
          parent: { type: 'workspace', workspace: true },
          properties: {
            Status: { type: 'select', select: { name: 'In Progress' } },
            Tags: {
              type: 'multi_select',
              multi_select: [{ name: 'Research' }, { name: 'AI' }],
            },
          },
        },
      ],
      [],
    );

    const adapter = new NotionAdapter({
      provider,
      paskGraph: pask as never,
      pollIntervalMs: 999_999,
    });

    await adapter.start();
    adapter.stop();

    const call = pask.calls[0] as Record<string, unknown>;
    const related = call['relatedCells'] as string[];
    expect(related).toContain('nx:tag:ws-test/in-progress');
    expect(related).toContain('nx:tag:ws-test/research');
    expect(related).toContain('nx:tag:ws-test/ai');
  });
});

describe('NotionAdapter.notionUrl', () => {
  test('builds desktop URL for page cells', async () => {
    const adapter = new NotionAdapter({
      provider: makeProvider(),
      paskGraph: makeFakePask() as never,
    });
    await adapter.start();
    adapter.stop();

    const url = adapter.notionUrl('nx:page:ws-test/abc123-def456');
    expect(url).toBe('notion://www.notion.so/abc123def456');
  });

  test('returns null for non-notion cells', async () => {
    const adapter = new NotionAdapter({
      provider: makeProvider(),
      paskGraph: makeFakePask() as never,
    });
    await adapter.start();
    adapter.stop();

    expect(adapter.notionUrl('helm:item:some-id')).toBeNull();
    expect(adapter.notionUrl('obs:note:vault/foo')).toBeNull();
  });
});

```
