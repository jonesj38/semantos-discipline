---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/gmail.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.150648+00:00
---

# runtime/legacy-ingest/src/__tests__/gmail.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { GmailProvider, GmailUnauthorized, GmailRateLimited } from '../providers/gmail';
import type { AccessToken, RawItem } from '../types';
import type { FetchLike } from '../oauth';

const accessToken: AccessToken = {
  accessToken: 'AT',
  refreshToken: 'RT',
  expiresAt: Date.now() + 3600_000,
  scopes: '',
  providerExtras: {},
};

function jsonResponse(body: unknown, init: ResponseInit = { status: 200 }): Response {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: { 'content-type': 'application/json', ...(init.headers ?? {}) },
  });
}

function base64UrlEncode(s: string): string {
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

describe('GmailProvider', () => {
  test('listPage paginates and returns preview items', async () => {
    let listCallCount = 0;
    const fetchImpl: FetchLike = async (url) => {
      listCallCount += 1;
      const u = new URL(typeof url === 'string' ? url : url.toString());
      expect(u.searchParams.get('maxResults')).toBe('50');
      const cursor = u.searchParams.get('pageToken');
      if (cursor === null) {
        return jsonResponse({
          messages: [{ id: 'm1', threadId: 't1' }, { id: 'm2', threadId: 't1' }],
          nextPageToken: 'page-2',
        });
      }
      return jsonResponse({
        messages: [{ id: 'm3', threadId: 't2' }],
        // no nextPageToken -> end of list
      });
    };
    const provider = new GmailProvider({ pageSize: 50, fetch: fetchImpl });
    const page1 = await provider.listPage(accessToken, { cursor: null });
    expect(page1.items.length).toBe(2);
    expect(page1.items[0].providerItemId).toBe('m1');
    expect(page1.items[0].contentType).toBe('gmail/preview');
    expect(page1.items[0].metadata.threadId).toBe('t1');
    expect(page1.nextCursor).toBe('page-2');

    const page2 = await provider.listPage(accessToken, { cursor: 'page-2' });
    expect(page2.items.length).toBe(1);
    expect(page2.nextCursor).toBeNull();
    expect(listCallCount).toBe(2);
  });

  test('listPage with `since` builds a Gmail `q after:` query', async () => {
    let querySeen = '';
    const fetchImpl: FetchLike = async (url) => {
      const u = new URL(typeof url === 'string' ? url : url.toString());
      querySeen = u.searchParams.get('q') ?? '';
      return jsonResponse({});
    };
    const provider = new GmailProvider({ fetch: fetchImpl });
    const since = new Date('2024-01-01T00:00:00Z').getTime();
    await provider.listPage(accessToken, { cursor: null, since });
    expect(querySeen).toBe(`after:${Math.floor(since / 1000)}`);
  });

  test('listPage with `query` only passes the operator filter as `q`', async () => {
    let urlSeen = '';
    let querySeen: string | null = '';
    const fetchImpl: FetchLike = async (url) => {
      const raw = typeof url === 'string' ? url : url.toString();
      urlSeen = raw;
      querySeen = new URL(raw).searchParams.get('q');
      return jsonResponse({});
    };
    const provider = new GmailProvider({ fetch: fetchImpl });
    await provider.listPage(accessToken, {
      cursor: null,
      query: 'from:bricksandagent.com',
    });
    expect(querySeen).toBe('from:bricksandagent.com');
    // URLSearchParams encodes ':' as %3A — assert the wire form too so a
    // future refactor that drops URL-encoding gets caught.
    expect(urlSeen).toContain('q=from%3Abricksandagent.com');
  });

  test('listPage with both `since` and `query` AND-combines into `after:<s> <q>`', async () => {
    let querySeen: string | null = '';
    const fetchImpl: FetchLike = async (url) => {
      querySeen = new URL(typeof url === 'string' ? url : url.toString())
        .searchParams.get('q');
      return jsonResponse({});
    };
    const provider = new GmailProvider({ fetch: fetchImpl });
    const since = new Date('2024-01-01T00:00:00Z').getTime();
    await provider.listPage(accessToken, {
      cursor: null,
      since,
      query: 'from:bricksandagent.com',
    });
    expect(querySeen).toBe(
      `after:${Math.floor(since / 1000)} from:bricksandagent.com`,
    );
  });

  test('listPage with neither `since` nor `query` omits `q` entirely', async () => {
    let qSeen: string | null = 'sentinel';
    const fetchImpl: FetchLike = async (url) => {
      qSeen = new URL(typeof url === 'string' ? url : url.toString())
        .searchParams.get('q');
      return jsonResponse({});
    };
    const provider = new GmailProvider({ fetch: fetchImpl });
    await provider.listPage(accessToken, { cursor: null });
    expect(qSeen).toBeNull();
  });

  test('listPage ignores empty-string `query`', async () => {
    let qSeen: string | null = 'sentinel';
    const fetchImpl: FetchLike = async (url) => {
      qSeen = new URL(typeof url === 'string' ? url : url.toString())
        .searchParams.get('q');
      return jsonResponse({});
    };
    const provider = new GmailProvider({ fetch: fetchImpl });
    await provider.listPage(accessToken, { cursor: null, query: '' });
    expect(qSeen).toBeNull();
  });

  test('fetchFull decodes base64url raw body', async () => {
    const rfc822 = 'Message-ID: <abc@example.com>\r\nSubject: Hi\r\n\r\nbody';
    const fetchImpl: FetchLike = async (url) => {
      const u = typeof url === 'string' ? url : url.toString();
      expect(u).toContain('/messages/m1');
      expect(u).toContain('format=raw');
      return jsonResponse({
        id: 'm1', threadId: 't1', internalDate: '12345',
        labelIds: ['INBOX', 'CATEGORY_PERSONAL'],
        snippet: 'preview',
        raw: base64UrlEncode(rfc822),
      });
    };
    const provider = new GmailProvider({ fetch: fetchImpl });
    const preview: RawItem = {
      providerId: 'gmail', providerItemId: 'm1', fetchedAt: 0,
      contentType: 'gmail/preview', bytes: new Uint8Array(0),
      metadata: { threadId: 't1' },
    };
    const full = await provider.fetchFull(accessToken, preview);
    expect(full.contentType).toBe('email/rfc822');
    expect(new TextDecoder().decode(full.bytes)).toBe(rfc822);
    expect(full.metadata.labelIds).toBe('INBOX,CATEGORY_PERSONAL');
    expect(full.metadata.snippet).toBe('preview');
    expect(full.metadata.internalDate).toBe('12345');
  });

  test('GmailUnauthorized on 401', async () => {
    const fetchImpl: FetchLike = async () => new Response('', { status: 401 });
    const provider = new GmailProvider({ fetch: fetchImpl });
    await expect(provider.listPage(accessToken, { cursor: null })).rejects.toThrow(GmailUnauthorized);
  });

  test('GmailRateLimited on 429 with Retry-After', async () => {
    const fetchImpl: FetchLike = async () => new Response('', {
      status: 429, headers: { 'retry-after': '5' },
    });
    const provider = new GmailProvider({ fetch: fetchImpl });
    try {
      await provider.listPage(accessToken, { cursor: null });
      throw new Error('should have thrown');
    } catch (err) {
      expect(err).toBeInstanceOf(GmailRateLimited);
      expect((err as GmailRateLimited).retryAfterSeconds).toBe(5);
    }
  });

  test('fingerprint extracts rfc822 Message-ID for cross-provider dedup', async () => {
    const provider = new GmailProvider();
    const item: RawItem = {
      providerId: 'gmail', providerItemId: 'm1', fetchedAt: 0,
      contentType: 'email/rfc822',
      bytes: new TextEncoder().encode('Message-ID: <abc@example.com>\r\nSubject: x\r\n\r\nbody'),
      metadata: {},
    };
    expect(provider.fingerprint(item)).toBe('email-id:abc@example.com');
  });

  test('fingerprint falls back to gmail id when Message-ID absent', async () => {
    const provider = new GmailProvider();
    const item: RawItem = {
      providerId: 'gmail', providerItemId: 'm1', fetchedAt: 0,
      contentType: 'email/rfc822',
      bytes: new TextEncoder().encode('Subject: no message-id\r\n\r\nbody'),
      metadata: {},
    };
    expect(provider.fingerprint(item)).toBe('gmail:m1');
  });
});

```
