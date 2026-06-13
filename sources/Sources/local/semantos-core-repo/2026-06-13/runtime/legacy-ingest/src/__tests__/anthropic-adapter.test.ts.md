---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/anthropic-adapter.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.146675+00:00
---

# runtime/legacy-ingest/src/__tests__/anthropic-adapter.test.ts

```ts
import { describe, it, expect, spyOn } from 'bun:test';
import sharp from 'sharp';
import type { SharpFactory } from '../extractor/anthropic';
import {
  AnthropicAdapter,
  AnthropicAuthError,
  AnthropicConnectionError,
  AnthropicError,
  AnthropicImageTooLarge,
  AnthropicOverloaded,
  AnthropicParseError,
  AnthropicRateLimited,
  AnthropicTimeout,
  AnthropicTruncated,
} from '../extractor/anthropic';

// ── Fetch mock helpers ────────────────────────────────────────────────────────

function mockFetch(
  response: object,
  status = 200,
  headers: Record<string, string> = {},
) {
  return async (_url: string, _init?: RequestInit): Promise<Response> => {
    const h = new Headers(headers);
    if (!h.has('content-type')) h.set('content-type', 'application/json');
    return new Response(JSON.stringify(response), { status, headers: h });
  };
}

/** Anthropic Messages API success-shape response body. */
function messagesResponse(text: string, stopReason: string = 'end_turn') {
  return {
    type: 'message',
    content: [{ type: 'text', text }],
    stop_reason: stopReason,
  };
}

// ── LLMAdapter tests ──────────────────────────────────────────────────────────

describe('AnthropicAdapter.extract', () => {
  it('parses structured JSON text block and extracts confidence', async () => {
    const payload = {
      intent: 'quote_request',
      summary: 'Fence job',
      confidence: 0.88,
    };
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: mockFetch(messagesResponse(JSON.stringify(payload))),
    });

    const result = await adapter.extract<{ intent: string; summary: string }>({
      prompt: 'Extract intent',
      schema: {
        type: 'object',
        properties: { intent: {}, summary: {} },
        required: ['intent'],
      },
    });

    expect(result.confidence).toBeCloseTo(0.88);
    expect(result.payload.intent).toBe('quote_request');
    expect(result.payload.summary).toBe('Fence job');
    // confidence must NOT be in the returned payload
    expect((result.payload as Record<string, unknown>).confidence).toBeUndefined();
  });

  it('strips ```json code fences from response', async () => {
    const fenced = '```json\n{"intent":"booking","summary":"Tuesday slot","confidence":0.95}\n```';
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: mockFetch(messagesResponse(fenced)),
    });
    const result = await adapter.extract<{ intent: string }>({ prompt: 'x', schema: {} });
    expect(result.payload.intent).toBe('booking');
    expect(result.confidence).toBeCloseTo(0.95);
  });

  it('strips bare ``` code fences from response', async () => {
    const fenced = '```\n{"a":1,"confidence":0.5}\n```';
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: mockFetch(messagesResponse(fenced)),
    });
    const result = await adapter.extract<{ a: number }>({ prompt: 'x', schema: {} });
    expect(result.payload.a).toBe(1);
    expect(result.confidence).toBeCloseTo(0.5);
  });

  it('defaults confidence to 0.7 when model omits the field', async () => {
    const payload = { intent: 'inquiry', summary: 'Just asking' };
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: mockFetch(messagesResponse(JSON.stringify(payload))),
    });
    const result = await adapter.extract({ prompt: 'x', schema: {} });
    expect(result.confidence).toBe(0.7);
  });

  it('clamps confidence to [0, 1]', async () => {
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: mockFetch(messagesResponse(JSON.stringify({ intent: 'lead', confidence: 1.5 }))),
    });
    const result = await adapter.extract({ prompt: 'x', schema: {} });
    expect(result.confidence).toBe(1.0);

    const adapter2 = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: mockFetch(messagesResponse(JSON.stringify({ intent: 'lead', confidence: -0.2 }))),
    });
    const result2 = await adapter2.extract({ prompt: 'x', schema: {} });
    expect(result2.confidence).toBe(0.0);
  });

  it('throws AnthropicAuthError on 401', async () => {
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-bad',
      fetch: mockFetch({ error: { type: 'authentication_error', message: 'Unauthorized' } }, 401),
    });
    await expect(adapter.extract({ prompt: 'x', schema: {} })).rejects.toThrow(AnthropicAuthError);
  });

  it('throws AnthropicRateLimited on 429 with retry-after header', async () => {
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: mockFetch({}, 429, { 'retry-after': '30' }),
    });
    try {
      await adapter.extract({ prompt: 'x', schema: {} });
      expect(true).toBe(false); // unreachable
    } catch (err) {
      expect(err).toBeInstanceOf(AnthropicRateLimited);
      expect((err as AnthropicRateLimited).retryAfterSeconds).toBe(30);
    }
  });

  it('throws AnthropicOverloaded on 529', async () => {
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: mockFetch({ error: { type: 'overloaded_error' } }, 529),
    });
    await expect(adapter.extract({ prompt: 'x', schema: {} })).rejects.toThrow(AnthropicOverloaded);
  });

  it('throws AnthropicTruncated when stop_reason is max_tokens', async () => {
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: mockFetch(messagesResponse('{"a":1', 'max_tokens')),
    });
    await expect(adapter.extract({ prompt: 'x', schema: {} })).rejects.toThrow(AnthropicTruncated);
  });

  it('throws AnthropicParseError when model returns non-JSON prose', async () => {
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: mockFetch(messagesResponse('I cannot help with that request.')),
    });
    await expect(adapter.extract({ prompt: 'x', schema: {} })).rejects.toThrow(AnthropicParseError);
  });

  it('throws AnthropicTimeout when fetch never resolves before timeoutMs', async () => {
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      timeoutMs: 25,
      fetch: () => new Promise<Response>(() => { /* never resolve */ }),
    });
    await expect(adapter.extract({ prompt: 'x', schema: {} })).rejects.toThrow(AnthropicTimeout);
  });

  it('wraps network errors in AnthropicConnectionError', async () => {
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: async () => { throw new TypeError('fetch failed'); },
    });
    await expect(adapter.extract({ prompt: 'x', schema: {} })).rejects.toThrow(AnthropicConnectionError);
  });

  it('throws AnthropicError when response is empty content', async () => {
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: mockFetch({ type: 'message', content: [], stop_reason: 'end_turn' }),
    });
    await expect(adapter.extract({ prompt: 'x', schema: {} })).rejects.toThrow(AnthropicError);
  });

  it('calls api key provider function on every request', async () => {
    let called = 0;
    const adapter = new AnthropicAdapter({
      apiKey: () => { called++; return 'sk-ant-dynamic-fake'; },
      fetch: mockFetch(messagesResponse(JSON.stringify({ intent: 'x', confidence: 0.5 }))),
    });
    await adapter.extract({ prompt: 'x', schema: {} });
    await adapter.extract({ prompt: 'y', schema: {} });
    expect(called).toBe(2);
  });

  it('throws AnthropicAuthError with env-var hint when api key is null', async () => {
    const adapter = new AnthropicAdapter({
      apiKey: () => null,
      fetch: mockFetch(messagesResponse('{}')),
    });
    let caught: unknown;
    try {
      await adapter.extract({ prompt: 'x', schema: {} });
    } catch (err) {
      caught = err;
    }
    expect(caught).toBeInstanceOf(AnthropicAuthError);
    expect((caught as Error).message).toContain('ANTHROPIC_API_KEY');
  });

  it('throws AnthropicAuthError when api key is empty string', async () => {
    const adapter = new AnthropicAdapter({
      apiKey: '',
      fetch: mockFetch(messagesResponse('{}')),
    });
    await expect(adapter.extract({ prompt: 'x', schema: {} })).rejects.toThrow(AnthropicAuthError);
  });

  it('sends x-api-key + anthropic-version headers (not Bearer)', async () => {
    const capturedHeaders: Record<string, string> = {};
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-sentinel-fake',
      fetch: async (_url, init) => {
        for (const [k, v] of Object.entries((init?.headers ?? {}) as Record<string, string>)) {
          capturedHeaders[k.toLowerCase()] = v;
        }
        return new Response(JSON.stringify(messagesResponse(JSON.stringify({ x: 1, confidence: 0.8 }))));
      },
    });
    await adapter.extract({ prompt: 'x', schema: {} });
    expect(capturedHeaders['x-api-key']).toBe('sk-ant-sentinel-fake');
    expect(capturedHeaders['anthropic-version']).toBe('2023-06-01');
    expect(capturedHeaders['authorization']).toBeUndefined();
    expect(capturedHeaders['http-referer']).toBeUndefined();
  });

  it('hits the native Anthropic Messages endpoint', async () => {
    let capturedUrl = '';
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: async (url, _init) => {
        capturedUrl = String(url);
        return new Response(JSON.stringify(messagesResponse(JSON.stringify({ a: 1, confidence: 0.5 }))));
      },
    });
    await adapter.extract({ prompt: 'x', schema: {} });
    expect(capturedUrl).toBe('https://api.anthropic.com/v1/messages');
  });

  it('sends Anthropic-native body shape (system + messages, no response_format)', async () => {
    let sentBody = '';
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: async (_url, init) => {
        sentBody = init?.body as string ?? '';
        return new Response(JSON.stringify(messagesResponse(JSON.stringify({ a: 1, confidence: 0.5 }))));
      },
    });
    await adapter.extract({ prompt: 'Extract this', schema: {} });
    const body = JSON.parse(sentBody);
    expect(body.model).toBe('claude-haiku-4-5-20251001');
    expect(typeof body.system).toBe('string');
    expect(body.system.length).toBeGreaterThan(0);
    expect(body.messages).toHaveLength(1);
    expect(body.messages[0].role).toBe('user');
    expect(typeof body.max_tokens).toBe('number');
    expect(body.response_format).toBeUndefined();
  });

  it('augments caller schema with confidence field before sending', async () => {
    let sentBody = '';
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: async (_url, init) => {
        sentBody = init?.body as string ?? '';
        return new Response(JSON.stringify(messagesResponse(JSON.stringify({ a: 1, confidence: 0.9 }))));
      },
    });
    const result = await adapter.extract<{ a: number }>({
      prompt: 'x',
      schema: { type: 'object', properties: { a: {} }, required: ['a'] },
    });
    const body = JSON.parse(sentBody);
    const userText = body.messages[0].content[0].text as string;
    expect(userText).toContain('"confidence"');
    // …and confidence is stripped from the returned payload
    expect((result.payload as Record<string, unknown>).confidence).toBeUndefined();
    expect(result.payload.a).toBe(1);
  });

  it('respects custom apiVersion override', async () => {
    const captured: Record<string, string> = {};
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      apiVersion: '2024-10-22',
      fetch: async (_url, init) => {
        for (const [k, v] of Object.entries((init?.headers ?? {}) as Record<string, string>)) {
          captured[k.toLowerCase()] = v;
        }
        return new Response(JSON.stringify(messagesResponse(JSON.stringify({ a: 1, confidence: 0.5 }))));
      },
    });
    await adapter.extract({ prompt: 'x', schema: {} });
    expect(captured['anthropic-version']).toBe('2024-10-22');
  });

  // 2026-05-07 — operator's overnight gmail ingest produced "valid JSON
  // start, no closing brace, stop_reason != max_tokens" responses on
  // long quote-PDF extractions.  The router was logging noisy
  // AnthropicParseError instead of falling through silently.  These
  // tests lock in the truncation-detection heuristic.
  describe('truncation-detection heuristic', () => {
    it('throws AnthropicTruncated when response opens JSON but has no closing brace', async () => {
      const truncated =
        '{\n  "job_type": "quote_request",\n  "summary": "Quote from Todd Price for deck rail works",\n  "point_of_contact": "Daniell';
      const adapter = new AnthropicAdapter({
        apiKey: 'sk-ant-test-fake',
        fetch: mockFetch(messagesResponse(truncated, 'end_turn')),
      });
      await expect(
        adapter.extract({ prompt: 'x', schema: { type: 'object' } }),
      ).rejects.toThrow(AnthropicTruncated);
    });

    it('still throws AnthropicParseError for non-JSON prose with no opening brace', async () => {
      const adapter = new AnthropicAdapter({
        apiKey: 'sk-ant-test-fake',
        fetch: mockFetch(
          messagesResponse('I cannot help with that request.', 'end_turn'),
        ),
      });
      await expect(
        adapter.extract({ prompt: 'x', schema: {} }),
      ).rejects.toThrow(AnthropicParseError);
    });

    it('parses normally when JSON is complete (closing brace present)', async () => {
      const adapter = new AnthropicAdapter({
        apiKey: 'sk-ant-test-fake',
        fetch: mockFetch(
          messagesResponse(
            JSON.stringify({ a: 1, confidence: 0.5 }),
            'end_turn',
          ),
        ),
      });
      const result = await adapter.extract<{ a: number }>({
        prompt: 'x',
        schema: {},
      });
      expect(result.payload.a).toBe(1);
    });

    it('treats trailing comma + whitespace as still-complete (closing brace check is robust)', async () => {
      const adapter = new AnthropicAdapter({
        apiKey: 'sk-ant-test-fake',
        fetch: mockFetch(messagesResponse('{"a": 1}\n  \n', 'end_turn')),
      });
      const result = await adapter.extract<{ a: number }>({
        prompt: 'x',
        schema: {},
      });
      expect(result.payload.a).toBe(1);
    });

    it('throws AnthropicTruncated on prose-wrapped truncated JSON', async () => {
      const proseWrapped =
        'Here is the extracted data:\n```json\n{\n  "job_type": "quote_request",\n  "point_of_contact": "Clever Property';
      const adapter = new AnthropicAdapter({
        apiKey: 'sk-ant-test-fake',
        fetch: mockFetch(messagesResponse(proseWrapped, 'end_turn')),
      });
      await expect(
        adapter.extract({ prompt: 'x', schema: {} }),
      ).rejects.toThrow(AnthropicTruncated);
    });
  });
});

// ── VisionAdapter tests ───────────────────────────────────────────────────────

describe('AnthropicAdapter.describeImage', () => {
  it('returns transcribed text from vision response', async () => {
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: mockFetch(messagesResponse('Invoice total: $1,450.00\nDate: 15 March 2025')),
    });
    const text = await adapter.describeImage(btoa('fake-image'), 'image/jpeg');
    expect(text).toContain('$1,450.00');
  });

  it('uses native document block for PDFs (multi-page support)', async () => {
    let sentBody = '';
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: async (_url, init) => {
        sentBody = init?.body as string ?? '';
        return new Response(JSON.stringify(messagesResponse('3 bedroom unit, 120sqm')));
      },
    });
    const pdfBase64 = btoa('%PDF-1.4');
    await adapter.describeImage(pdfBase64, 'application/pdf');
    const body = JSON.parse(sentBody);
    const contentBlocks = body.messages[0].content as Array<{ type: string }>;
    const docBlock = contentBlocks.find((b) => b.type === 'document');
    expect(docBlock).toBeDefined();
    expect((docBlock as any).source.type).toBe('base64');
    expect((docBlock as any).source.media_type).toBe('application/pdf');
    expect((docBlock as any).source.data).toBe(pdfBase64);
    expect(body.model).toBe('claude-sonnet-4-6');
  });

  it('uses native image block for image/* with correct mime type', async () => {
    let sentBody = '';
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: async (_url, init) => {
        sentBody = init?.body as string ?? '';
        return new Response(JSON.stringify(messagesResponse('Photo of fence')));
      },
    });
    const imgBase64 = btoa('fake-png-data');
    await adapter.describeImage(imgBase64, 'image/png');
    const body = JSON.parse(sentBody);
    const contentBlocks = body.messages[0].content as Array<{ type: string }>;
    const imgBlock = contentBlocks.find((b) => b.type === 'image');
    expect(imgBlock).toBeDefined();
    expect((imgBlock as any).source.type).toBe('base64');
    expect((imgBlock as any).source.media_type).toBe('image/png');
    expect((imgBlock as any).source.data).toBe(imgBase64);
  });

  it('throws AnthropicRateLimited on 429', async () => {
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: mockFetch({}, 429, { 'retry-after': '60' }),
    });
    await expect(adapter.describeImage(btoa('x'), 'image/jpeg')).rejects.toThrow(AnthropicRateLimited);
  });

  it('throws AnthropicOverloaded on 529 from vision endpoint', async () => {
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: mockFetch({}, 529),
    });
    await expect(adapter.describeImage(btoa('x'), 'image/jpeg')).rejects.toThrow(AnthropicOverloaded);
  });

  it('trims whitespace from returned text', async () => {
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: mockFetch(messagesResponse('  \n  Some text \n  ')),
    });
    const result = await adapter.describeImage(btoa('x'), 'image/jpeg');
    expect(result).toBe('Some text');
  });

  it('honours custom visionModel option', async () => {
    let sentBody = '';
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      visionModel: 'claude-opus-4-7',
      fetch: async (_url, init) => {
        sentBody = init?.body as string ?? '';
        return new Response(JSON.stringify(messagesResponse('text')));
      },
    });
    await adapter.describeImage(btoa('x'), 'image/jpeg');
    const body = JSON.parse(sentBody);
    expect(body.model).toBe('claude-opus-4-7');
  });
});

// ── Integration: attachment pipeline with AnthropicAdapter ──────────────────

describe('AnthropicAdapter as VisionAdapter in extractAttachmentTexts', () => {
  it('passes base64 PDF through to describeImage and returns transcribed text', async () => {
    const { extractAttachmentTexts } = await import('../extractor/attachment');

    const pdfBytes = new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d]); // %PDF-
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      fetch: mockFetch(messagesResponse('3 bedrooms\n2 bathrooms\nLand: 450sqm')),
    });

    const results = await extractAttachmentTexts(
      [{ contentType: 'application/pdf', bytes: pdfBytes, filename: null, kind: 'pdf' }],
      adapter,
    );
    expect(results[0]).toContain('450sqm');
  });
});

// ── Helpers for sharp-based test fixtures ────────────────────────────────────

/**
 * Build a real JPEG buffer using sharp from a raw RGB Buffer.
 * width × height × 3 bytes of raw RGB data, encoded as JPEG at `quality`.
 * Returns the JPEG as a Buffer and its base64-encoded form.
 */
async function makeJpegFixture(
  width: number,
  height: number,
  quality: number,
): Promise<{ jpegBuffer: Buffer; base64: string }> {
  // Alternating-pixel pattern gives moderate entropy (not solid, not pure noise).
  const rawSize = width * height * 3;
  const raw = Buffer.alloc(rawSize);
  for (let i = 0; i < rawSize; i++) {
    // Simple gradient + stripe pattern to get deterministic, non-trivial JPEG output.
    raw[i] = (i % 256) ^ ((i >> 8) & 0xff);
  }
  const jpegBuffer = await sharp(raw, { raw: { width, height, channels: 3 } })
    .jpeg({ quality })
    .toBuffer();
  return { jpegBuffer, base64: jpegBuffer.toString('base64') };
}

// ── Downsampler tests (PR #398) ───────────────────────────────────────────────
//
// PR #397 shipped a defensive throw-before-HTTP guard.  PR #398 replaces it
// with an iterative sharp downsampler so large images are actually extracted
// via Anthropic instead of silently falling through.
//
// All downsampler tests inject a `sharpFactory` stub via
// `AnthropicAdapterOpts.sharpFactory` rather than monkey-patching the module,
// so they work correctly under ESM's frozen module namespace.

describe('AnthropicAdapter.describeImage — oversize image guard and downsampler', () => {
  /**
   * Build a `SharpFactory` stub for injection via `AnthropicAdapterOpts.sharpFactory`.
   * Each call to `.toBuffer()` yields the next buffer from `outputs`, holding at
   * the last entry once exhausted.  Tracks the total number of `.toBuffer()` calls.
   */
  function makeSharpStub(outputs: Buffer[]): {
    factory: SharpFactory;
    callCount: () => number;
  } {
    let calls = 0;
    const factory: SharpFactory = (_input: Buffer) => ({
      resize: (_w: number, _h: number, _opts?: object) => ({
        jpeg: (_opts?: object) => ({
          toBuffer: async (): Promise<Buffer> => {
            const idx = Math.min(calls, outputs.length - 1);
            calls++;
            return outputs[idx];
          },
        }),
      }),
    }) as unknown as ReturnType<SharpFactory>;
    return { factory, callCount: () => calls };
  }

  // ── 1. Under-limit: sharp never called, passes through ───────────────────

  it('image under the 4 MB base64 limit — sharp factory never called, Anthropic call succeeds', async () => {
    // A real small JPEG well under 4 MB. Under-limit images bypass the downsampler.
    const { base64: smallBase64 } = await makeJpegFixture(100, 100, 90);
    expect(smallBase64.length).toBeLessThan(4 * 1024 * 1024); // sanity

    let sharpCalled = false;
    const factory: SharpFactory = (_buf: Buffer) => {
      sharpCalled = true;
      return {} as ReturnType<SharpFactory>;
    };

    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      sharpFactory: factory,
      fetch: mockFetch(messagesResponse('text from small image')),
    });

    const result = await adapter.describeImage(smallBase64, 'image/jpeg');
    expect(result).toBe('text from small image');
    expect(sharpCalled).toBe(false);
  });

  // ── 2. ~8 MB image → fits after attempt 1 ────────────────────────────────

  it('image at ~8 MB base64 → sharp downsizes to under 4 MB on attempt 1, Anthropic gets called with downsized image', async () => {
    // Build a large JPEG (3000×3000 Q99) as the oversize input fixture.
    const { base64: largeBase64 } = await makeJpegFixture(3000, 3000, 99);

    if (largeBase64.length <= 4 * 1024 * 1024) {
      // On some platforms (different libjpeg builds) the gradient image may
      // not exceed 4 MB. Log and skip gracefully rather than fail.
      console.warn('[test] 3000×3000 Q99 JPEG is under 4 MB on this platform — skipping');
      return;
    }

    // The stub factory returns a small buffer (under limit) on the first call.
    const LIMIT = 4 * 1024 * 1024;
    const smallBuf = Buffer.alloc(Math.ceil((LIMIT - 500_000) * 3 / 4)); // ~3 MB base64
    const { factory, callCount } = makeSharpStub([smallBuf]);

    const warnSpy = spyOn(console, 'warn').mockImplementation(() => {});

    let capturedBase64 = '';
    let capturedMimeType = '';
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      sharpFactory: factory,
      fetch: async (_url, init) => {
        const body = JSON.parse(init?.body as string);
        const imgBlock = body.messages[0].content[0] as {
          source: { data: string; media_type: string };
        };
        capturedBase64 = imgBlock.source.data;
        capturedMimeType = imgBlock.source.media_type;
        return new Response(JSON.stringify(messagesResponse('invoice total: $1,200')));
      },
    });

    const result = await adapter.describeImage(largeBase64, 'image/jpeg');

    expect(callCount()).toBe(1); // only 1 attempt needed
    expect(capturedBase64.length).toBeLessThan(LIMIT);
    expect(capturedMimeType).toBe('image/jpeg');
    expect(result).toBe('invoice total: $1,200');

    // Log line must have been emitted.
    const warnCalls = warnSpy.mock.calls;
    const allWarnText = warnCalls.map((c) => (c as unknown[]).map(String).join(' ')).join('\n');
    expect(allWarnText).toContain('[vision-anthropic] downsized image');
    expect(allWarnText).toContain('attempt: 1/4');

    warnSpy.mockRestore();
  });

  // ── 3. Extreme image → multiple attempts needed ───────────────────────────

  it('extreme image → downsizer iterates over multiple attempts until it fits', async () => {
    // Stub: attempt 1 still over limit, attempt 2 fits.
    const LIMIT = 4 * 1024 * 1024;
    const overBuf = Buffer.alloc(Math.ceil((LIMIT + 500_000) * 3 / 4)); // > 4 MB base64
    const underBuf = Buffer.alloc(Math.ceil((LIMIT - 500_000) * 3 / 4)); // < 4 MB base64

    const { factory, callCount } = makeSharpStub([overBuf, underBuf]);
    const warnSpy = spyOn(console, 'warn').mockImplementation(() => {});

    const oversizedInput = 'A'.repeat(LIMIT + 1);

    let capturedBase64 = '';
    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      sharpFactory: factory,
      fetch: async (_url, init) => {
        const body = JSON.parse(init?.body as string);
        const imgBlock = body.messages[0].content[0] as { source: { data: string } };
        capturedBase64 = imgBlock.source.data;
        return new Response(JSON.stringify(messagesResponse('multi-attempt extraction')));
      },
    });

    const result = await adapter.describeImage(oversizedInput, 'image/jpeg');
    warnSpy.mockRestore();

    expect(callCount()).toBe(2); // took 2 attempts
    expect(capturedBase64.length).toBeLessThan(LIMIT);
    expect(result).toBe('multi-attempt extraction');
  });

  // ── 4. Uncompressible: throws AnthropicImageTooLarge after 4 attempts ────

  it('uncompressible image — all 4 attempts fail → throws AnthropicImageTooLarge, HTTP never called', async () => {
    const LIMIT = 4 * 1024 * 1024;
    const alwaysOverBuf = Buffer.alloc(Math.ceil((LIMIT + 500_000) * 3 / 4));

    const { factory, callCount } = makeSharpStub([alwaysOverBuf]);
    const warnSpy = spyOn(console, 'warn').mockImplementation(() => {});

    const oversizedInput = 'A'.repeat(LIMIT + 1);
    let fetchWasCalled = false;

    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      sharpFactory: factory,
      fetch: async () => {
        fetchWasCalled = true;
        return new Response('{}');
      },
    });

    await expect(adapter.describeImage(oversizedInput, 'image/jpeg')).rejects.toThrow(
      AnthropicImageTooLarge,
    );

    warnSpy.mockRestore();

    expect(callCount()).toBe(4); // all 4 attempts exhausted
    expect(fetchWasCalled).toBe(false); // HTTP call never made
  });

  // ── 5. Error carries original base64 length ───────────────────────────────

  it('AnthropicImageTooLarge thrown after 4 failed attempts carries the original base64 length', async () => {
    const LIMIT = 4 * 1024 * 1024;
    const alwaysOverBuf = Buffer.alloc(Math.ceil((LIMIT + 500_000) * 3 / 4));
    const { factory } = makeSharpStub([alwaysOverBuf]);
    const warnSpy = spyOn(console, 'warn').mockImplementation(() => {});

    const inputLength = LIMIT + 1;
    const oversizedInput = 'A'.repeat(inputLength);

    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      sharpFactory: factory,
      fetch: async () => new Response('{}'),
    });

    let caught: unknown;
    try {
      await adapter.describeImage(oversizedInput, 'image/jpeg');
    } catch (err) {
      caught = err;
    }

    warnSpy.mockRestore();

    expect(caught).toBeInstanceOf(AnthropicImageTooLarge);
    expect((caught as AnthropicImageTooLarge).base64Length).toBe(inputLength);
    expect((caught as AnthropicImageTooLarge).message).toContain('MB');
    expect((caught as AnthropicImageTooLarge).message).toContain('4 MB');
  });

  // ── 6. Log lines emitted per attempt ─────────────────────────────────────

  it('emits [vision-anthropic] warn log with MB sizes for each downsize attempt', async () => {
    const LIMIT = 4 * 1024 * 1024;
    // 2 over-limit then 1 under-limit → 3 attempts, 3 log lines.
    const overBuf = Buffer.alloc(Math.ceil((LIMIT + 500_000) * 3 / 4));
    const underBuf = Buffer.alloc(Math.ceil((LIMIT - 500_000) * 3 / 4));
    const { factory } = makeSharpStub([overBuf, overBuf, underBuf]);

    const warnMessages: string[] = [];
    const warnSpy = spyOn(console, 'warn').mockImplementation((...args: unknown[]) => {
      warnMessages.push(args.map(String).join(' '));
    });

    const oversizedInput = 'A'.repeat(LIMIT + 1);

    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      sharpFactory: factory,
      fetch: mockFetch(messagesResponse('done')),
    });

    await adapter.describeImage(oversizedInput, 'image/jpeg');
    warnSpy.mockRestore();

    const downsizeLines = warnMessages.filter((m) => m.includes('[vision-anthropic] downsized image'));
    expect(downsizeLines).toHaveLength(3);
    expect(downsizeLines[0]).toMatch(/from .+MB to .+MB/);
    expect(downsizeLines[0]).toContain('attempt: 1/4');
    expect(downsizeLines[1]).toContain('attempt: 2/4');
    expect(downsizeLines[2]).toContain('attempt: 3/4');
  });

  // ── 7. PDFs bypass the downsampler ───────────────────────────────────────

  it('oversized PDF bypasses the downsampler — sharp factory never called, Anthropic call proceeds', async () => {
    const LIMIT = 4 * 1024 * 1024;
    let sharpCalled = false;
    const factory: SharpFactory = (_buf: Buffer) => {
      sharpCalled = true;
      return {} as ReturnType<SharpFactory>;
    };

    const oversizedPdfBase64 = 'A'.repeat(LIMIT + 1);

    const adapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      sharpFactory: factory,
      fetch: mockFetch(messagesResponse('pdf text extracted')),
    });

    const result = await adapter.describeImage(oversizedPdfBase64, 'application/pdf');

    expect(sharpCalled).toBe(false);
    expect(result).toBe('pdf text extracted');
  });

  // ── 8. Router fall-through when all 4 attempts fail ──────────────────────

  it('AnthropicImageTooLarge after 4 failed attempts → llm-router falls through to next backend', async () => {
    const LIMIT = 4 * 1024 * 1024;
    const alwaysOverBuf = Buffer.alloc(Math.ceil((LIMIT + 500_000) * 3 / 4));
    const { factory } = makeSharpStub([alwaysOverBuf]);

    const warnSpy = spyOn(console, 'warn').mockImplementation(() => {});

    const { LlmRouter } = await import('../extractor/router');
    const { OpenRouterAdapter } = await import('../extractor/openrouter');

    const oversizedInput = 'A'.repeat(LIMIT + 1);

    const anthropicAdapter = new AnthropicAdapter({
      apiKey: 'sk-ant-test-fake',
      sharpFactory: factory,
      fetch: async () => new Response('should not be called'),
    });

    const openrouterStub = {
      extract: async () => ({ payload: {}, confidence: 0.9, raw: '' }),
      describeImage: async (_b64: string, _mime: string) => 'text from fallback backend',
    } as unknown as InstanceType<typeof OpenRouterAdapter>;

    const router = new LlmRouter({
      adapters: {
        ollama: null,
        anthropic: anthropicAdapter,
        openrouter: openrouterStub,
      },
      visionPreference: ['anthropic', 'openrouter'],
    });

    const result = await router.describeImage(oversizedInput, 'image/jpeg');
    warnSpy.mockRestore();

    expect(result).toBe('text from fallback backend');
  });
});

```
