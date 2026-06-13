---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/tools/__tests__/image-extract.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.566225+00:00
---

# cartridges/betterment/brain/tools/__tests__/image-extract.test.ts

```ts
/**
 * image-extract OCR tool tests.
 *
 * Exercise the pure core (`extractFromImages` + `segmentIntoTurns`) with a fake
 * VisionClient so turn structuring is validated without the model or network.
 * Asserts: paragraph segmentation, strictly-increasing global turn index across
 * pages, per-page sourcePageRef, rawText join, and client-error propagation.
 */

import { describe, expect, test } from 'bun:test';
import {
  extractFromImages,
  segmentIntoTurns,
  stripCodeFences,
  mediaTypeForPath,
  parseArgs,
  AnthropicVisionClient,
  type VisionClient,
  type ImageInput,
} from '../image-extract.js';

/** Fake client that returns canned text per call, in order. */
function fakeClient(pages: string[]): VisionClient {
  let i = 0;
  return {
    async transcribe() {
      return pages[i++] ?? '';
    },
  };
}

const img = (n = 1): ImageInput[] =>
  Array.from({ length: n }, (_, k) => ({ base64: `b64-${k}`, mediaType: 'image/jpeg' }));

describe('segmentIntoTurns', () => {
  test('splits paragraphs on blank lines', () => {
    expect(segmentIntoTurns('first thought\n\nsecond thought')).toEqual([
      'first thought',
      'second thought',
    ]);
  });

  test('a page with no blank line is one turn', () => {
    expect(segmentIntoTurns('one\nrun-on\nparagraph')).toEqual(['one\nrun-on\nparagraph']);
  });

  test('whitespace-only page yields no turns', () => {
    expect(segmentIntoTurns('   \n\n  \n')).toEqual([]);
  });

  test('handles CRLF and trailing whitespace', () => {
    expect(segmentIntoTurns('a\r\n\r\nb  \r\n')).toEqual(['a', 'b']);
  });
});

describe('extractFromImages', () => {
  test('single page → indexed turns with page ref', async () => {
    const result = await extractFromImages(fakeClient(['I feel tense.\n\nI release it.']), img(1));
    expect(result.pageCount).toBe(1);
    expect(result.turns).toEqual([
      { index: 0, speaker: 'self', text: 'I feel tense.', sourcePageRef: 'page:1' },
      { index: 1, speaker: 'self', text: 'I release it.', sourcePageRef: 'page:1' },
    ]);
    expect(result.rawText).toBe('I feel tense.\n\nI release it.');
  });

  test('multi-page: index strictly increasing across pages; per-page refs', async () => {
    const result = await extractFromImages(
      fakeClient(['p1a\n\np1b', 'p2a']),
      img(2),
    );
    expect(result.turns.map((t) => t.index)).toEqual([0, 1, 2]);
    expect(result.turns.map((t) => t.sourcePageRef)).toEqual(['page:1', 'page:1', 'page:2']);
    // strictly increasing
    const idx = result.turns.map((t) => t.index);
    expect(idx).toEqual([...idx].sort((a, b) => a - b));
    expect(new Set(idx).size).toBe(idx.length);
    expect(result.rawText).toBe('p1a\n\np1b\n\np2a');
    expect(result.turns.every((t) => t.speaker === 'self')).toBe(true);
  });

  test('blank page contributes no turns but counts as a page', async () => {
    const result = await extractFromImages(fakeClient(['real text', '   ']), img(2));
    expect(result.pageCount).toBe(2);
    expect(result.turns).toHaveLength(1);
    expect(result.turns[0]!.sourcePageRef).toBe('page:1');
  });

  test('propagates a client/transcription error', async () => {
    const boom: VisionClient = {
      async transcribe() {
        throw new Error('anthropic 529: overloaded');
      },
    };
    await expect(extractFromImages(boom, img(1))).rejects.toThrow(/overloaded/);
  });
});

describe('stripCodeFences', () => {
  test('strips a fenced block', () => {
    expect(stripCodeFences('```\nhello\n```')).toBe('hello');
    expect(stripCodeFences('```text\nhello\n```')).toBe('hello');
  });
  test('leaves unfenced text alone', () => {
    expect(stripCodeFences('  hello  ')).toBe('hello');
  });
});

describe('mediaTypeForPath', () => {
  test('maps extensions, defaults to jpeg', () => {
    expect(mediaTypeForPath('/tmp/a.png')).toBe('image/png');
    expect(mediaTypeForPath('/tmp/a.JPEG')).toBe('image/jpeg');
    expect(mediaTypeForPath('/tmp/a.webp')).toBe('image/webp');
    expect(mediaTypeForPath('/tmp/a.heic')).toBe('image/jpeg');
  });
});

describe('parseArgs', () => {
  test('parses comma-separated images + metadata', () => {
    const a = parseArgs(['--images', '/tmp/1.jpg,/tmp/2.png', '--metadata', '/tmp/m.json']);
    expect(a.imagePaths).toEqual(['/tmp/1.jpg', '/tmp/2.png']);
    expect(a.metadataPath).toBe('/tmp/m.json');
  });
  test('throws when no images', () => {
    expect(() => parseArgs(['--metadata', '/tmp/m.json'])).toThrow(/--images/);
  });

  test('parses optional --model (BYOK model selection)', () => {
    const a = parseArgs(['--images', '/tmp/1.jpg', '--model', 'claude-haiku-4-5']);
    expect(a.model).toBe('claude-haiku-4-5');
    expect(parseArgs(['--images', '/tmp/1.jpg']).model).toBeNull();
  });
});

describe('AnthropicVisionClient', () => {
  test('sends the configured model in the request body', async () => {
    let capturedBody: any;
    const fakeFetch = async (_url: string, init: RequestInit) => {
      capturedBody = JSON.parse(init.body as string);
      return new Response(
        JSON.stringify({ content: [{ type: 'text', text: 'hello' }] }),
        { status: 200, headers: { 'content-type': 'application/json' } },
      );
    };
    const client = new AnthropicVisionClient({
      apiKey: 'sk-test',
      model: 'claude-opus-4-1',
      fetch: fakeFetch as unknown as typeof fetch,
    });
    const out = await client.transcribe('YmFzZTY0', 'image/jpeg');
    expect(out).toBe('hello');
    expect(capturedBody.model).toBe('claude-opus-4-1');
  });

  test('uses the BYOK api key as the x-api-key header', async () => {
    let capturedHeaders: Record<string, string> = {};
    const fakeFetch = async (_url: string, init: RequestInit) => {
      capturedHeaders = init.headers as Record<string, string>;
      return new Response(JSON.stringify({ content: [{ type: 'text', text: 'ok' }] }), {
        status: 200,
      });
    };
    const client = new AnthropicVisionClient({
      apiKey: 'sk-byok-123',
      fetch: fakeFetch as unknown as typeof fetch,
    });
    await client.transcribe('YmFzZTY0', 'image/png');
    expect(capturedHeaders['x-api-key']).toBe('sk-byok-123');
  });
});

```
