---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/openrouter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.141990+00:00
---

# runtime/legacy-ingest/src/__tests__/openrouter.test.ts

```ts
import { describe, it, expect } from 'bun:test';
import { OpenRouterAdapter, OpenRouterError, OpenRouterRateLimited } from '../extractor/openrouter';

// ── Fetch mock helpers ────────────────────────────────────────────────────────

function mockFetch(response: object, status = 200, headers: Record<string, string> = {}) {
  return async (_url: string, _init?: RequestInit): Promise<Response> => {
    const h = new Headers(headers);
    if (!h.has('content-type')) h.set('content-type', 'application/json');
    return new Response(JSON.stringify(response), { status, headers: h });
  };
}

function chatResponse(content: string) {
  return {
    choices: [{ message: { content }, finish_reason: 'stop' }],
  };
}

// ── LLMAdapter tests ──────────────────────────────────────────────────────────

describe('OpenRouterAdapter.extract', () => {
  it('parses structured JSON and extracts confidence', async () => {
    const payload = {
      intent: 'quote_request',
      summary: 'Fence job',
      confidence: 0.88,
    };
    const adapter = new OpenRouterAdapter({
      apiKey: 'sk-test',
      fetch: mockFetch(chatResponse(JSON.stringify(payload))),
    });

    const result = await adapter.extract<{ intent: string; summary: string }>({
      prompt: 'Extract intent',
      schema: { type: 'object', properties: { intent: {}, summary: {} }, required: ['intent'] },
    });

    expect(result.confidence).toBeCloseTo(0.88);
    expect(result.payload.intent).toBe('quote_request');
    expect(result.payload.summary).toBe('Fence job');
    // confidence must NOT be in the returned payload
    expect((result.payload as Record<string, unknown>).confidence).toBeUndefined();
  });

  it('defaults confidence to 0.7 when model omits the field', async () => {
    const payload = { intent: 'inquiry', summary: 'Just asking' };
    const adapter = new OpenRouterAdapter({
      apiKey: 'sk-test',
      fetch: mockFetch(chatResponse(JSON.stringify(payload))),
    });
    const result = await adapter.extract({ prompt: 'x', schema: {} });
    expect(result.confidence).toBe(0.7);
  });

  it('clamps confidence to [0, 1]', async () => {
    const adapter = new OpenRouterAdapter({
      apiKey: 'sk-test',
      fetch: mockFetch(chatResponse(JSON.stringify({ intent: 'lead', confidence: 1.5 }))),
    });
    const result = await adapter.extract({ prompt: 'x', schema: {} });
    expect(result.confidence).toBe(1.0);

    const adapter2 = new OpenRouterAdapter({
      apiKey: 'sk-test',
      fetch: mockFetch(chatResponse(JSON.stringify({ intent: 'lead', confidence: -0.2 }))),
    });
    const result2 = await adapter2.extract({ prompt: 'x', schema: {} });
    expect(result2.confidence).toBe(0.0);
  });

  it('recovers JSON from prose wrapping', async () => {
    const content = 'Sure! Here is the extraction:\n```json\n{"intent":"booking","summary":"Tuesday slot","confidence":0.95}\n```';
    const adapter = new OpenRouterAdapter({
      apiKey: 'sk-test',
      fetch: mockFetch(chatResponse(content)),
    });
    const result = await adapter.extract<{ intent: string }>({ prompt: 'x', schema: {} });
    expect(result.payload.intent).toBe('booking');
    expect(result.confidence).toBeCloseTo(0.95);
  });

  it('throws OpenRouterError on 401', async () => {
    const adapter = new OpenRouterAdapter({
      apiKey: 'sk-bad',
      fetch: mockFetch({ error: { message: 'Unauthorized' } }, 401),
    });
    await expect(adapter.extract({ prompt: 'x', schema: {} })).rejects.toThrow(OpenRouterError);
  });

  it('throws OpenRouterRateLimited on 429 with retry-after header', async () => {
    const adapter = new OpenRouterAdapter({
      apiKey: 'sk-test',
      fetch: mockFetch({}, 429, { 'retry-after': '30' }),
    });
    try {
      await adapter.extract({ prompt: 'x', schema: {} });
      expect(true).toBe(false); // should not reach here
    } catch (err) {
      expect(err).toBeInstanceOf(OpenRouterRateLimited);
      expect((err as OpenRouterRateLimited).retryAfterSeconds).toBe(30);
    }
  });

  it('throws when model returns empty content', async () => {
    const adapter = new OpenRouterAdapter({
      apiKey: 'sk-test',
      fetch: mockFetch(chatResponse('')),
    });
    await expect(adapter.extract({ prompt: 'x', schema: {} })).rejects.toThrow(OpenRouterError);
  });

  it('throws OpenRouterError when API key provider returns null', async () => {
    const adapter = new OpenRouterAdapter({
      apiKey: () => null,
      fetch: mockFetch(chatResponse('{}')),
    });
    await expect(adapter.extract({ prompt: 'x', schema: {} })).rejects.toThrow(OpenRouterError);
  });

  it('accepts a function api key provider', async () => {
    let called = 0;
    const adapter = new OpenRouterAdapter({
      apiKey: () => { called++; return 'sk-dynamic'; },
      fetch: mockFetch(chatResponse(JSON.stringify({ intent: 'other', confidence: 0.5 }))),
    });
    await adapter.extract({ prompt: 'x', schema: {} });
    expect(called).toBe(1);
  });

  it('sends Authorization header with Bearer token', async () => {
    const capturedHeaders: Record<string, string> = {};
    const adapter = new OpenRouterAdapter({
      apiKey: 'sk-sentinel',
      fetch: async (url, init) => {
        for (const [k, v] of Object.entries((init?.headers ?? {}) as Record<string, string>)) {
          capturedHeaders[k.toLowerCase()] = v;
        }
        return new Response(JSON.stringify(chatResponse(JSON.stringify({ x: 1, confidence: 0.8 }))));
      },
    });
    await adapter.extract({ prompt: 'x', schema: {} });
    expect(capturedHeaders['authorization']).toBe('Bearer sk-sentinel');
  });

  it('augments caller schema with confidence field', async () => {
    let sentBody = '';
    const adapter = new OpenRouterAdapter({
      apiKey: 'sk-test',
      fetch: async (_url, init) => {
        sentBody = init?.body as string ?? '';
        return new Response(JSON.stringify(chatResponse(JSON.stringify({ a: 1, confidence: 0.9 }))));
      },
    });
    await adapter.extract({
      prompt: 'x',
      schema: { type: 'object', properties: { a: {} }, required: ['a'] },
    });
    const body = JSON.parse(sentBody);
    const userContent = body.messages[1].content as string;
    expect(userContent).toContain('"confidence"');
  });
});

// ── VisionAdapter tests ───────────────────────────────────────────────────────

describe('OpenRouterAdapter.describeImage', () => {
  it('returns transcribed text from vision response', async () => {
    const adapter = new OpenRouterAdapter({
      apiKey: 'sk-test',
      fetch: mockFetch(chatResponse('Invoice total: $1,450.00\nDate: 15 March 2025')),
    });
    const text = await adapter.describeImage(btoa('fake-image'), 'image/jpeg');
    expect(text).toContain('$1,450.00');
  });

  it('uses document type for PDFs on Anthropic models', async () => {
    let sentBody = '';
    const adapter = new OpenRouterAdapter({
      apiKey: 'sk-test',
      visionModel: 'anthropic/claude-sonnet-4-6',
      fetch: async (_url, init) => {
        sentBody = init?.body as string ?? '';
        return new Response(JSON.stringify(chatResponse('3 bedroom unit, 120sqm')));
      },
    });
    const pdfBase64 = btoa('%PDF-1.4');
    await adapter.describeImage(pdfBase64, 'application/pdf');
    const body = JSON.parse(sentBody);
    const contentBlocks = body.messages[1].content as Array<{ type: string }>;
    const docBlock = contentBlocks.find(b => b.type === 'document');
    expect(docBlock).toBeDefined();
    expect((docBlock as any).source.media_type).toBe('application/pdf');
    expect((docBlock as any).source.data).toBe(pdfBase64);
  });

  it('uses image_url for images regardless of model', async () => {
    let sentBody = '';
    const adapter = new OpenRouterAdapter({
      apiKey: 'sk-test',
      visionModel: 'openai/gpt-4o',
      fetch: async (_url, init) => {
        sentBody = init?.body as string ?? '';
        return new Response(JSON.stringify(chatResponse('Photo of fence')));
      },
    });
    const imgBase64 = btoa('fake-png-data');
    await adapter.describeImage(imgBase64, 'image/png');
    const body = JSON.parse(sentBody);
    const contentBlocks = body.messages[1].content as Array<{ type: string }>;
    const imgBlock = contentBlocks.find(b => b.type === 'image_url');
    expect(imgBlock).toBeDefined();
    expect((imgBlock as any).image_url.url).toBe(`data:image/png;base64,${imgBase64}`);
  });

  it('uses image_url for PDFs on non-Anthropic models', async () => {
    let sentBody = '';
    const adapter = new OpenRouterAdapter({
      apiKey: 'sk-test',
      visionModel: 'openai/gpt-4-vision-preview',
      fetch: async (_url, init) => {
        sentBody = init?.body as string ?? '';
        return new Response(JSON.stringify(chatResponse('some text')));
      },
    });
    await adapter.describeImage(btoa('%PDF'), 'application/pdf');
    const body = JSON.parse(sentBody);
    const contentBlocks = body.messages[1].content as Array<{ type: string }>;
    const imgBlock = contentBlocks.find(b => b.type === 'image_url');
    expect(imgBlock).toBeDefined();
  });

  it('throws OpenRouterRateLimited on 429', async () => {
    const adapter = new OpenRouterAdapter({
      apiKey: 'sk-test',
      fetch: mockFetch({}, 429, { 'retry-after': '60' }),
    });
    await expect(adapter.describeImage(btoa('x'), 'image/jpeg')).rejects.toThrow(OpenRouterRateLimited);
  });

  it('trims whitespace from returned text', async () => {
    const adapter = new OpenRouterAdapter({
      apiKey: 'sk-test',
      fetch: mockFetch(chatResponse('  \n  Some text \n  ')),
    });
    const result = await adapter.describeImage(btoa('x'), 'image/jpeg');
    expect(result).toBe('Some text');
  });
});

// ── Integration: attachment pipeline with OpenRouterAdapter ──────────────────

describe('OpenRouterAdapter as VisionAdapter in extractAttachmentTexts', () => {
  it('passes base64 PDF to describeImage and returns transcribed text', async () => {
    const { extractAttachmentTexts } = await import('../extractor/attachment');

    const pdfBytes = new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d]); // %PDF-
    const adapter = new OpenRouterAdapter({
      apiKey: 'sk-test',
      fetch: mockFetch(chatResponse('3 bedrooms\n2 bathrooms\nLand: 450sqm')),
    });

    const results = await extractAttachmentTexts(
      [{ contentType: 'application/pdf', bytes: pdfBytes, filename: null, kind: 'pdf' }],
      adapter,
    );
    expect(results[0]).toContain('450sqm');
  });
});

```
