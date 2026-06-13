---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/ollama-adapter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.152654+00:00
---

# runtime/legacy-ingest/src/__tests__/ollama-adapter.test.ts

```ts
import { describe, it, expect } from 'bun:test';
import {
  OllamaAdapter,
  OllamaConnectionError,
  OllamaError,
  OllamaModelNotFound,
  OllamaParseError,
  OllamaTimeout,
} from '../extractor/ollama';

// ── Fetch mock helpers ────────────────────────────────────────────────────────

function mockFetch(
  response: object | string,
  status = 200,
  headers: Record<string, string> = {},
) {
  return async (_url: string, _init?: RequestInit): Promise<Response> => {
    const h = new Headers(headers);
    if (!h.has('content-type')) h.set('content-type', 'application/json');
    const body = typeof response === 'string' ? response : JSON.stringify(response);
    return new Response(body, { status, headers: h });
  };
}

function chatResponse(content: string) {
  return {
    message: { role: 'assistant', content },
    done: true,
  };
}

// ── Happy path + payload shaping ──────────────────────────────────────────────

describe('OllamaAdapter.extract', () => {
  it('parses structured JSON and extracts confidence', async () => {
    const payload = {
      intent: 'quote_request',
      summary: 'Fence job',
      confidence: 0.88,
    };
    const adapter = new OllamaAdapter({
      fetch: mockFetch(chatResponse(JSON.stringify(payload))),
    });

    const result = await adapter.extract<{ intent: string; summary: string }>({
      prompt: 'Extract intent',
      schema: { type: 'object', properties: { intent: {}, summary: {} }, required: ['intent'] },
    });

    expect(result.confidence).toBeCloseTo(0.88);
    expect(result.payload.intent).toBe('quote_request');
    expect(result.payload.summary).toBe('Fence job');
    // confidence must NOT be in the returned payload — it's a sidecar field.
    expect((result.payload as Record<string, unknown>).confidence).toBeUndefined();
  });

  it('passes through high-confidence responses unchanged (>= 0.5)', async () => {
    const payload = { has_lead: true, confidence: 0.9 };
    const adapter = new OllamaAdapter({
      fetch: mockFetch(chatResponse(JSON.stringify(payload))),
    });
    const result = await adapter.extract<{ has_lead: boolean }>({
      prompt: 'Is this a lead?',
      schema: {},
    });
    expect(result.confidence).toBeCloseTo(0.9);
    expect(result.payload.has_lead).toBe(true);
  });

  it('passes through low-confidence (< 0.5) — caller decides to gate', async () => {
    // The confidence floor is enforced by the ratification orchestrator,
    // not the adapter. The adapter is a transport.
    const payload = { intent: 'maybe_lead', confidence: 0.3 };
    const adapter = new OllamaAdapter({
      fetch: mockFetch(chatResponse(JSON.stringify(payload))),
    });
    const result = await adapter.extract({ prompt: 'x', schema: {} });
    expect(result.confidence).toBeCloseTo(0.3);
    expect((result.payload as { intent: string }).intent).toBe('maybe_lead');
  });

  it('defaults confidence to 0.7 when model omits the field', async () => {
    const payload = { intent: 'inquiry', summary: 'Just asking' };
    const adapter = new OllamaAdapter({
      fetch: mockFetch(chatResponse(JSON.stringify(payload))),
    });
    const result = await adapter.extract({ prompt: 'x', schema: {} });
    expect(result.confidence).toBe(0.7);
  });

  it('clamps confidence to [0, 1]', async () => {
    const adapter = new OllamaAdapter({
      fetch: mockFetch(chatResponse(JSON.stringify({ intent: 'lead', confidence: 1.5 }))),
    });
    expect((await adapter.extract({ prompt: 'x', schema: {} })).confidence).toBe(1.0);

    const adapter2 = new OllamaAdapter({
      fetch: mockFetch(chatResponse(JSON.stringify({ intent: 'lead', confidence: -0.2 }))),
    });
    expect((await adapter2.extract({ prompt: 'x', schema: {} })).confidence).toBe(0.0);
  });

  it('recovers JSON from prose wrapping (small models occasionally do this)', async () => {
    const content = 'Sure! Here is the extraction:\n```json\n{"intent":"booking","confidence":0.95}\n```';
    const adapter = new OllamaAdapter({
      fetch: mockFetch(chatResponse(content)),
    });
    const result = await adapter.extract<{ intent: string }>({ prompt: 'x', schema: {} });
    expect(result.payload.intent).toBe('booking');
    expect(result.confidence).toBeCloseTo(0.95);
  });
});

// ── Error taxonomy ────────────────────────────────────────────────────────────

describe('OllamaAdapter.extract errors', () => {
  it('throws OllamaParseError on non-JSON response', async () => {
    const adapter = new OllamaAdapter({
      fetch: mockFetch(chatResponse('totally not json, sorry')),
    });
    await expect(adapter.extract({ prompt: 'x', schema: {} })).rejects.toThrow(OllamaParseError);
  });

  it('throws OllamaConnectionError when the server is unreachable', async () => {
    const econnrefused = Object.assign(new Error('connect ECONNREFUSED 127.0.0.1:11434'), {
      code: 'ECONNREFUSED',
    });
    const adapter = new OllamaAdapter({
      fetch: async () => {
        throw econnrefused;
      },
    });
    let caught: unknown = null;
    try {
      await adapter.extract({ prompt: 'x', schema: {} });
    } catch (e) {
      caught = e;
    }
    expect(caught).toBeInstanceOf(OllamaConnectionError);
    // Error message should be actionable — point the operator at `ollama serve`.
    expect((caught as Error).message).toContain('ollama serve');
  });

  it('throws OllamaModelNotFound on 404', async () => {
    const adapter = new OllamaAdapter({
      model: 'llama3.2:3b',
      fetch: mockFetch({ error: 'model "llama3.2:3b" not found, try pulling it first' }, 404),
    });
    let caught: unknown = null;
    try {
      await adapter.extract({ prompt: 'x', schema: {} });
    } catch (e) {
      caught = e;
    }
    expect(caught).toBeInstanceOf(OllamaModelNotFound);
    expect((caught as OllamaModelNotFound).model).toBe('llama3.2:3b');
    expect((caught as Error).message).toContain('ollama pull');
  });

  it('throws OllamaTimeout when the request exceeds timeoutMs', async () => {
    // Simulate a fetch that respects AbortSignal: rejects with AbortError when the signal fires.
    const adapter = new OllamaAdapter({
      timeoutMs: 25,
      fetch: (_url, init) =>
        new Promise<Response>((_resolve, reject) => {
          const signal = init?.signal;
          if (signal) {
            signal.addEventListener('abort', () => {
              const err = new Error('aborted');
              err.name = 'AbortError';
              reject(err);
            });
          }
          // Otherwise never resolve — the timeout has to do the work.
        }),
    });
    let caught: unknown = null;
    try {
      await adapter.extract({ prompt: 'x', schema: {} });
    } catch (e) {
      caught = e;
    }
    expect(caught).toBeInstanceOf(OllamaTimeout);
    expect((caught as OllamaTimeout).timeoutMs).toBe(25);
  });

  it('throws OllamaError on other non-2xx responses', async () => {
    const adapter = new OllamaAdapter({
      fetch: mockFetch({ error: 'internal' }, 500),
    });
    await expect(adapter.extract({ prompt: 'x', schema: {} })).rejects.toThrow(OllamaError);
  });

  it('throws OllamaError when the response is missing the message field', async () => {
    const adapter = new OllamaAdapter({
      fetch: mockFetch({ done: true }), // no message at all
    });
    await expect(adapter.extract({ prompt: 'x', schema: {} })).rejects.toThrow(OllamaError);
  });
});

// ── Wire shape: chat endpoint, system+user split, schema augmentation ────────

describe('OllamaAdapter.extract wire shape', () => {
  it('sends a chat-shape body to /api/chat with system + user split', async () => {
    let capturedUrl = '';
    let capturedBody = '';
    const adapter = new OllamaAdapter({
      baseUrl: 'http://localhost:11434',
      model: 'llama3.2:3b',
      fetch: async (url, init) => {
        capturedUrl = url;
        capturedBody = (init?.body as string) ?? '';
        return new Response(JSON.stringify(chatResponse(JSON.stringify({ ok: true, confidence: 0.8 }))));
      },
    });
    await adapter.extract({ prompt: 'classify this', schema: {} });

    expect(capturedUrl).toBe('http://localhost:11434/api/chat');
    const body = JSON.parse(capturedBody);
    expect(body.model).toBe('llama3.2:3b');
    expect(body.stream).toBe(false);
    expect(body.format).toBe('json');
    expect(body.options.temperature).toBe(0.0);

    // Chat shape preserves the system prompt as a separate message,
    // not concatenated into the user prompt.
    expect(Array.isArray(body.messages)).toBe(true);
    expect(body.messages).toHaveLength(2);
    expect(body.messages[0].role).toBe('system');
    expect(body.messages[1].role).toBe('user');
    expect(body.messages[0].content).toContain('JSON');
    expect(body.messages[1].content).toContain('classify this');
  });

  it("strips a trailing slash from baseUrl so URL composition doesn't double up", async () => {
    let capturedUrl = '';
    const adapter = new OllamaAdapter({
      baseUrl: 'http://localhost:11434/',
      fetch: async (url) => {
        capturedUrl = url;
        return new Response(JSON.stringify(chatResponse('{"x":1,"confidence":0.8}')));
      },
    });
    await adapter.extract({ prompt: 'x', schema: {} });
    expect(capturedUrl).toBe('http://localhost:11434/api/chat');
  });

  it('augments caller schema with confidence field before sending to model', async () => {
    let sentBody = '';
    const adapter = new OllamaAdapter({
      fetch: async (_url, init) => {
        sentBody = (init?.body as string) ?? '';
        return new Response(JSON.stringify(chatResponse(JSON.stringify({ a: 1, confidence: 0.9 }))));
      },
    });
    const result = await adapter.extract<{ a: number }>({
      prompt: 'extract a',
      schema: { type: 'object', properties: { a: { type: 'number' } }, required: ['a'] },
    });

    // Asserted via the captured user-message body: the confidence field
    // must appear in the schema we asked the model to follow.
    const body = JSON.parse(sentBody);
    const userContent = body.messages[1].content as string;
    expect(userContent).toContain('"confidence"');
    expect(userContent).toContain('"required"');
    // The augmented `required` array should still include the caller's original entries.
    expect(userContent).toContain('"a"');

    // And the returned payload must have confidence stripped.
    expect(result.payload.a).toBe(1);
    expect((result.payload as Record<string, unknown>).confidence).toBeUndefined();
    expect(result.confidence).toBeCloseTo(0.9);
  });

  it('uses default model and base URL when none are supplied', async () => {
    let capturedUrl = '';
    let capturedBody = '';
    const adapter = new OllamaAdapter({
      fetch: async (url, init) => {
        capturedUrl = url;
        capturedBody = (init?.body as string) ?? '';
        return new Response(JSON.stringify(chatResponse('{"x":1,"confidence":0.8}')));
      },
    });
    await adapter.extract({ prompt: 'x', schema: {} });
    expect(capturedUrl).toBe('http://localhost:11434/api/chat');
    expect(JSON.parse(capturedBody).model).toBe('llama3.2:3b');
  });
});

```
