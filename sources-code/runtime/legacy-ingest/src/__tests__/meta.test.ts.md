---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/meta.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.148388+00:00
---

# runtime/legacy-ingest/src/__tests__/meta.test.ts

```ts
import { describe, it, expect } from 'bun:test';
import {
  MetaProvider,
  MetaTransport,
  MetaApiError,
  MetaWindowExpired,
} from '../providers/meta';
import { rawItemToOddjobzMessagePatch } from '../conversation/turn-patch-store';
import { MessageExtractor } from '../extractor/message';
import type { LLMAdapter } from '../extractor/types';

// ── MetaProvider tests ────────────────────────────────────────────────────────

describe('MetaProvider.verifyChallenge', () => {
  const provider = new MetaProvider({ verifyToken: 'secret-token' });

  it('returns challenge on valid subscribe + matching token', () => {
    const result = provider.verifyChallenge({
      mode: 'subscribe',
      token: 'secret-token',
      challenge: 'abc123',
    });
    expect(result).toBe('abc123');
  });

  it('returns null on wrong token', () => {
    const result = provider.verifyChallenge({
      mode: 'subscribe',
      token: 'wrong',
      challenge: 'abc123',
    });
    expect(result).toBeNull();
  });

  it('returns null on wrong mode', () => {
    const result = provider.verifyChallenge({
      mode: 'unsubscribe',
      token: 'secret-token',
      challenge: 'abc123',
    });
    expect(result).toBeNull();
  });
});

describe('MetaProvider.parseWebhookPayload', () => {
  const provider = new MetaProvider({ verifyToken: 'tok' });

  it('parses a Messenger message event', () => {
    const payload = {
      object: 'page',
      entry: [
        {
          id: 'PAGE_ID',
          messaging: [
            {
              sender: { id: 'USER_123' },
              recipient: { id: 'PAGE_ID' },
              timestamp: 1700000000,
              message: { mid: 'MSG_001', text: 'Hi can you fix my fence?' },
            },
          ],
        },
      ],
    };
    const items = provider.parseWebhookPayload(payload);
    expect(items).toHaveLength(1);
    const [item] = items;
    expect(item.contentType).toBe('meta/message');
    expect(item.providerItemId).toBe('messenger:PAGE_ID:MSG_001');
    expect(item.metadata.channel).toBe('messenger');
    expect(item.metadata.businessAssetId).toBe('PAGE_ID');
    expect(item.metadata.participantId).toBe('USER_123');
    expect(item.metadata.senderId).toBe('USER_123');

    const meta = JSON.parse(new TextDecoder().decode(item.bytes));
    expect(meta.text).toBe('Hi can you fix my fence?');
    expect(meta.threadId).toBe('messenger:PAGE_ID:USER_123');
    expect(meta.isEchoOrAd).toBe(false);
    // seconds → ms conversion
    expect(meta.timestamp).toBe(1700000000000);
  });

  it('parses an Instagram DM event via changes[]', () => {
    const payload = {
      object: 'instagram',
      entry: [
        {
          id: 'ACTOR_ID',
          changes: [
            {
              value: {
                messages: [
                  {
                    sender: { id: 'IG_USER' },
                    recipient: { id: 'ACTOR_ID' },
                    timestamp: 1700001000000, // already ms
                    message: { mid: 'IG_MSG_1', text: 'Do you do tiling?' },
                  },
                ],
              },
            },
          ],
        },
      ],
    };
    const items = provider.parseWebhookPayload(payload);
    expect(items).toHaveLength(1);
    expect(items[0].metadata.channel).toBe('instagram');
    const meta = JSON.parse(new TextDecoder().decode(items[0].bytes));
    expect(meta.text).toBe('Do you do tiling?');
    expect(meta.timestamp).toBe(1700001000000);
  });

  it('flags echo messages in metadata', () => {
    const payload = {
      object: 'page',
      entry: [
        {
          id: 'PAGE_ID',
          messaging: [
            {
              sender: { id: 'PAGE_ID' },
              recipient: { id: 'USER_123' },
              timestamp: 1700000001000,
              message: { mid: 'ECHO_001', text: 'Thanks for your message!', is_echo: true },
            },
          ],
        },
      ],
    };
    const items = provider.parseWebhookPayload(payload);
    expect(items).toHaveLength(1);
    expect(items[0].metadata.isEcho).toBe('true');
    expect(items[0].metadata.participantId).toBe('USER_123');
    const meta = JSON.parse(new TextDecoder().decode(items[0].bytes));
    expect(meta.isEchoOrAd).toBe(true);
  });

  it('skips entries without a message field (delivery receipts etc.)', () => {
    const payload = {
      object: 'page',
      entry: [
        {
          id: 'PAGE_ID',
          messaging: [
            {
              sender: { id: 'USER_123' },
              recipient: { id: 'PAGE_ID' },
              timestamp: 1700000002000,
              delivery: { watermark: 12345 }, // no .message
            },
          ],
        },
      ],
    };
    const items = provider.parseWebhookPayload(payload);
    expect(items).toHaveLength(0);
  });

  it('returns empty array for empty payload', () => {
    expect(provider.parseWebhookPayload({ object: 'page', entry: [] })).toHaveLength(0);
  });
});

describe('MetaProvider.sendMessage', () => {
  it('calls the Send API with correct shape', async () => {
    let capturedUrl = '';
    let capturedBody = '';
    const provider = new MetaProvider({
      verifyToken: 'tok',
      fetch: async (url, init) => {
        capturedUrl = url as string;
        capturedBody = init?.body as string;
        return new Response('{"message_id":"M1"}', { status: 200 });
      },
    });
    await provider.sendMessage('PAGE_TOKEN', 'USER_123', 'Thanks!');
    expect(capturedUrl).toContain('/me/messages');
    expect(capturedUrl).toContain('access_token=PAGE_TOKEN');
    const body = JSON.parse(capturedBody);
    expect(body.recipient.id).toBe('USER_123');
    expect(body.message.text).toBe('Thanks!');
    expect(body.messaging_type).toBe('RESPONSE');
  });

  it('throws MetaWindowExpired on error code 551', async () => {
    const provider = new MetaProvider({
      verifyToken: 'tok',
      fetch: async () => new Response(
        JSON.stringify({ error: { code: 551, message: 'window expired' } }),
        { status: 400 },
      ),
    });
    await expect(provider.sendMessage('tok', 'USER', 'hi')).rejects.toThrow(MetaWindowExpired);
  });

  it('throws MetaApiError on other errors', async () => {
    const provider = new MetaProvider({
      verifyToken: 'tok',
      fetch: async () => new Response(
        JSON.stringify({ error: { code: 100, message: 'invalid param' } }),
        { status: 400 },
      ),
    });
    await expect(provider.sendMessage('tok', 'USER', 'hi')).rejects.toThrow(MetaApiError);
  });
});

describe('MetaProvider (LegacyProvider no-ops)', () => {
  const provider = new MetaProvider({ verifyToken: 'tok' });
  const fakeToken = { accessToken: 'x', refreshToken: null, expiresAt: 0, scopes: '', providerExtras: {} };

  it('listPage returns empty results when no Business Suite asset is configured', async () => {
    const r = await provider.listPage(fakeToken, { cursor: null });
    expect(r.items).toHaveLength(0);
    expect(r.nextCursor).toBeNull();
  });

  it('fetchFull returns item unchanged', async () => {
    const item = {
      providerId: 'meta', providerItemId: 'x', fetchedAt: 0,
      contentType: 'meta/message', bytes: new Uint8Array(0), metadata: {},
    };
    const result = await provider.fetchFull(fakeToken, item);
    expect(result).toBe(item);
  });

  it('fingerprint prefixes with meta:', () => {
    const item = { providerId: 'meta', providerItemId: 'messenger:PAGE:MSG_X', fetchedAt: 0, contentType: 'meta/message', bytes: new Uint8Array(0), metadata: {} };
    expect(provider.fingerprint(item)).toBe('meta:messenger:PAGE:MSG_X');
  });
});

describe('MetaProvider historical Business Suite backfill', () => {
  const fakeToken = { accessToken: 'PAGE_TOKEN', refreshToken: null, expiresAt: 0, scopes: '', providerExtras: {} };

  it('walks Messenger conversations and emits every turn as meta/message RawItems', async () => {
    const urls: string[] = [];
    const provider = new MetaProvider({
      verifyToken: 'tok',
      pageSize: 10,
      fetch: async (url) => {
        urls.push(String(url));
        if (String(url).includes('/PAGE_ID/conversations')) {
          return jsonResponse({
            data: [{ id: 'CONV_1', updated_time: '2026-05-06T09:00:00+0000' }],
          });
        }
        if (String(url).includes('/CONV_1/messages')) {
          return jsonResponse({
            data: [
              {
                id: 'MID_IN',
                message: 'Can you quote a fence repair?',
                from: { id: 'USER_123', name: 'Jane' },
                to: { data: [{ id: 'PAGE_ID' }] },
                created_time: '2026-05-06T09:01:00+0000',
              },
              {
                id: 'MID_OUT',
                message: 'Yep, send through a photo.',
                from: { id: 'PAGE_ID', name: 'Oddjob Todd' },
                to: { data: [{ id: 'USER_123' }] },
                created_time: '2026-05-06T09:02:00+0000',
              },
            ],
          });
        }
        return jsonResponse({}, 404);
      },
    });

    const result = await provider.listPage(fakeToken, {
      cursor: null,
      query: 'messenger=PAGE_ID',
    });

    expect(result.nextCursor).toBeNull();
    expect(result.items).toHaveLength(2);
    expect(urls[0]).toContain('/PAGE_ID/conversations');
    expect(urls[1]).toContain('/CONV_1/messages');

    const inbound = JSON.parse(new TextDecoder().decode(result.items[0].bytes));
    expect(inbound.threadId).toBe('messenger:PAGE_ID:USER_123');
    expect(inbound.participantId).toBe('USER_123');
    expect(inbound.isEchoOrAd).toBe(false);
    expect(result.items[0].providerItemId).toBe('messenger:PAGE_ID:MID_IN');

    const outbound = JSON.parse(new TextDecoder().decode(result.items[1].bytes));
    expect(outbound.participantId).toBe('USER_123');
    expect(outbound.isEchoOrAd).toBe(true);
  });

  it('resumes paginated messages inside the same conversation', async () => {
    const provider = new MetaProvider({
      verifyToken: 'tok',
      pageSize: 1,
      fetch: async (url) => {
        const href = String(url);
        if (href.includes('/PAGE_ID/conversations')) {
          return jsonResponse({
            data: [{ id: 'CONV_1' }],
            paging: { cursors: { after: 'CONV_AFTER' } },
          });
        }
        if (href.includes('/CONV_1/messages') && !href.includes('after=MSG_AFTER')) {
          return jsonResponse({
            data: [
              {
                id: 'MID_1',
                message: 'First turn',
                from: { id: 'USER_123' },
                to: { data: [{ id: 'PAGE_ID' }] },
                created_time: '2026-05-06T09:01:00+0000',
              },
            ],
            paging: { cursors: { after: 'MSG_AFTER' } },
          });
        }
        if (href.includes('/CONV_1/messages') && href.includes('after=MSG_AFTER')) {
          return jsonResponse({
            data: [
              {
                id: 'MID_2',
                message: 'Second turn',
                from: { id: 'PAGE_ID' },
                to: { data: [{ id: 'USER_123' }] },
                created_time: '2026-05-06T09:02:00+0000',
              },
            ],
          });
        }
        return jsonResponse({}, 404);
      },
    });

    const first = await provider.listPage(fakeToken, {
      cursor: null,
      query: 'messenger=PAGE_ID',
    });
    expect(first.items.map(item => item.providerItemId)).toEqual(['messenger:PAGE_ID:MID_1']);
    expect(first.nextCursor).toBeString();

    const second = await provider.listPage(fakeToken, {
      cursor: first.nextCursor,
      query: 'messenger=PAGE_ID',
    });
    expect(second.items.map(item => item.providerItemId)).toEqual(['messenger:PAGE_ID:MID_2']);
    expect(second.nextCursor).toBeString();
  });

  it('projects backfilled Meta raw turns into Oddjobz message patches', async () => {
    const meta = {
      channel: 'instagram',
      recipientId: 'IG_BUSINESS',
      businessAssetId: 'IG_BUSINESS',
      participantId: 'IG_USER',
      senderId: 'IG_BUSINESS',
      threadId: 'instagram:IG_BUSINESS:IG_USER',
      conversationId: 'CONV_9',
      messageId: 'IG_MID_OUT',
      text: 'I can come tomorrow morning.',
      timestamp: Date.parse('2026-05-06T10:00:00Z'),
      isEchoOrAd: true,
    };
    const patch = rawItemToOddjobzMessagePatch({
      providerId: 'meta',
      providerItemId: 'instagram:IG_BUSINESS:IG_MID_OUT',
      fetchedAt: meta.timestamp,
      contentType: 'meta/message',
      bytes: new TextEncoder().encode(JSON.stringify(meta)),
      metadata: {
        channel: 'instagram',
        businessAssetId: 'IG_BUSINESS',
        participantId: 'IG_USER',
        senderId: 'IG_BUSINESS',
        recipientId: 'IG_BUSINESS',
        threadId: 'instagram:IG_BUSINESS:IG_USER',
        conversationId: 'CONV_9',
        messageId: 'IG_MID_OUT',
        isEcho: 'true',
      },
    }, 1234);

    expect(patch?.sessionId).toBe('meta:instagram:IG_BUSINESS:IG_USER');
    expect(patch?.channel).toBe('meta_instagram');
    expect(patch?.recipientId).toBe('IG_USER');
    expect(patch?.role).toBe('operator');
    expect(patch?.source?.conversationId).toBe('CONV_9');
  });
});

describe('MetaTransport', () => {
  it('calls provider.sendMessage with resolved token', async () => {
    const calls: Array<{ recipientId: string; text: string }> = [];
    const provider = new MetaProvider({
      verifyToken: 'tok',
      fetch: async () => {
        return new Response('{}', { status: 200 });
      },
    });
    // Spy by wrapping sendMessage
    const origSend = provider.sendMessage.bind(provider);
    provider.sendMessage = async (token, recipientId, text) => {
      calls.push({ recipientId, text });
      return origSend(token, recipientId, text);
    };

    const transport = new MetaTransport({
      provider,
      pageAccessToken: 'PAGE_TOK',
      channel: 'messenger',
    });

    await transport.send('USER_A', 'Hello!');
    expect(calls).toHaveLength(1);
    expect(calls[0].recipientId).toBe('USER_A');
    expect(calls[0].text).toBe('Hello!');
  });

  it('throws MetaApiError when token provider returns null', async () => {
    const provider = new MetaProvider({ verifyToken: 'tok' });
    const transport = new MetaTransport({
      provider,
      pageAccessToken: () => null,
      channel: 'messenger',
    });
    await expect(transport.send('USER', 'hi')).rejects.toThrow(MetaApiError);
  });
});

// ── MessageExtractor tests ────────────────────────────────────────────────────

function makeLLM(payload: object, confidence = 0.8): LLMAdapter {
  return {
    async extract() {
      return { payload, confidence, raw: JSON.stringify(payload) };
    },
  };
}

function makeMetaRawItem(text: string, opts: { isEcho?: boolean; channel?: string } = {}) {
  const meta = {
    channel: opts.channel ?? 'messenger',
    recipientId: 'PAGE_ID',
    businessAssetId: 'PAGE_ID',
    participantId: 'USER_123',
    senderId: 'USER_123',
    threadId: 'messenger:PAGE_ID:USER_123',
    messageId: 'MSG_001',
    text,
    timestamp: Date.now(),
    isEchoOrAd: opts.isEcho ?? false,
  };
  return {
    providerId: 'meta',
    providerItemId: 'messenger:PAGE_ID:MSG_001',
    fetchedAt: Date.now(),
    contentType: 'meta/message',
    bytes: new TextEncoder().encode(JSON.stringify(meta)),
    metadata: { channel: 'messenger', businessAssetId: 'PAGE_ID', participantId: 'USER_123', senderId: 'USER_123', recipientId: 'PAGE_ID', threadId: 'messenger:PAGE_ID:USER_123', messageId: 'MSG_001', isEcho: String(opts.isEcho ?? false) },
  };
}

describe('MessageExtractor', () => {
  it('extracts a proposal from a valid DM', async () => {
    const extractor = new MessageExtractor();
    const item = makeMetaRawItem('I need someone to fix my leaking tap');
    const llm = makeLLM({ intent: 'quote_request', summary: 'Leaking tap repair', confidence: 0.85 });
    const outcomes = await extractor.extract(item, llm);
    expect(outcomes.length).toBe(1);
    const outcome = outcomes[0];
    expect(outcome.kind).toBe('extracted');
    if (outcome.kind === 'extracted') {
      expect(outcome.proposal.threadKey).toBe('meta:messenger:PAGE_ID:USER_123');
      expect(outcome.proposal.summary).toBe('Leaking tap repair');
    }
  });

  it('pre-filters echo messages', async () => {
    const extractor = new MessageExtractor();
    const item = makeMetaRawItem('Thanks for contacting us!', { isEcho: true });
    const outcomes = await extractor.extract(item, makeLLM({}));
    expect(outcomes.length).toBe(1);
    const outcome = outcomes[0];
    expect(outcome.kind).toBe('pre-filtered');
    expect((outcome as any).reason).toContain('echo');
  });

  it('pre-filters empty text messages', async () => {
    const extractor = new MessageExtractor();
    const item = makeMetaRawItem('');
    const outcomes = await extractor.extract(item, makeLLM({}));
    expect(outcomes.length).toBe(1);
    const outcome = outcomes[0];
    expect(outcome.kind).toBe('pre-filtered');
  });

  it('drops low-confidence results', async () => {
    const extractor = new MessageExtractor();
    const item = makeMetaRawItem('???');
    const llm = makeLLM({ intent: 'other', summary: 'unclear' }, 0.3);
    const outcomes = await extractor.extract(item, llm);
    expect(outcomes.length).toBe(1);
    const outcome = outcomes[0];
    expect(outcome.kind).toBe('low-confidence');
  });

  it('carries referenceNumber onto proposal', async () => {
    const extractor = new MessageExtractor();
    const item = makeMetaRawItem('Re: Work Order PM-5001');
    const llm = makeLLM({
      intent: 'reply',
      summary: 'Scope update for PM-5001',
      job: { referenceNumber: 'PM-5001' },
      confidence: 0.8,
    });
    const outcomes = await extractor.extract(item, llm);
    expect(outcomes.length).toBe(1);
    const outcome = outcomes[0];
    expect(outcome.kind).toBe('extracted');
    if (outcome.kind === 'extracted') {
      expect(outcome.proposal.referenceNumber).toBe('PM-5001');
    }
  });

  it('promptHash is deterministic across runs', async () => {
    const e1 = new MessageExtractor();
    const e2 = new MessageExtractor();
    expect(e1.extractorVersion).toBe(e2.extractorVersion);
    // Both should produce same promptHash; verify by extracting twice
    const hashes: string[] = [];
    const item = makeMetaRawItem('test');
    const llm: LLMAdapter = {
      async extract({ prompt }) {
        hashes.push(prompt.slice(0, 30)); // just need to see it was called
        return { payload: { intent: 'other', summary: 'x' }, confidence: 0.6, raw: '{}' };
      },
    };
    await e1.extract(item, llm);
    await e2.extract(item, llm);
    expect(hashes[0]).toBe(hashes[1]);
  });
});

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

```
