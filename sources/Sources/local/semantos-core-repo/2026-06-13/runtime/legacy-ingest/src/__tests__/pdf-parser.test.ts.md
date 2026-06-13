---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/pdf-parser.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.138471+00:00
---

# runtime/legacy-ingest/src/__tests__/pdf-parser.test.ts

```ts
/**
 * D-DOG.1a — PDF byte-parser tests.
 *
 * Exercises the three-layer pipeline (cache → pdftotext → vision) with
 * an in-memory cache, an injectable spawn stub, and a stub VisionAdapter.
 * No real `pdftotext` binary is required; no network calls are made.
 */

import { describe, it, expect } from 'bun:test';
import {
  PdfParser,
  PdftotextNotInstalled,
  PdfseparateNotInstalled,
  PdfParseError,
  isLowQuality,
  type PdfTextCache,
  type SpawnLike,
  type SpawnedProcessLike,
} from '../extractor/pdf';
import type { VisionAdapter } from '../extractor/attachment';

// ── Test doubles ─────────────────────────────────────────────────────────────

class MapCache implements PdfTextCache {
  readonly store = new Map<string, string>();
  readonly gets: string[] = [];
  readonly puts: Array<{ key: string; value: string }> = [];

  async get(key: string): Promise<string | null> {
    this.gets.push(key);
    return this.store.has(key) ? this.store.get(key)! : null;
  }
  async put(key: string, value: string): Promise<void> {
    this.puts.push({ key, value });
    this.store.set(key, value);
  }
}

interface SpawnStubResult {
  stdoutText?: string;
  stderrText?: string;
  exitCode?: number;
  /** If set, throws this error synchronously from spawn() to simulate ENOENT. */
  throwOnSpawn?: unknown;
}

interface SpawnStubBookkeeping {
  calls: Array<{ cmd: string[]; stdinBytes: Uint8Array | null }>;
}

function makeSpawnStub(
  result: SpawnStubResult,
  bookkeeping: SpawnStubBookkeeping = { calls: [] },
): SpawnLike {
  return ((cmd: string[], _opts) => {
    if (result.throwOnSpawn) throw result.throwOnSpawn;

    const call: { cmd: string[]; stdinBytes: Uint8Array | null } = { cmd, stdinBytes: null };
    bookkeeping.calls.push(call);

    const stdin = {
      write(data: Uint8Array) {
        call.stdinBytes = data;
      },
      end() {
        // no-op
      },
    };

    const stdout = stringToReadableStream(result.stdoutText ?? '');
    const stderr = stringToReadableStream(result.stderrText ?? '');
    const exited = Promise.resolve(result.exitCode ?? 0);

    const proc: SpawnedProcessLike = {
      stdin: stdin as unknown as SpawnedProcessLike['stdin'],
      stdout,
      stderr,
      exited,
    };
    return proc;
  }) as SpawnLike;
}

function stringToReadableStream(s: string): ReadableStream<Uint8Array> {
  const enc = new TextEncoder().encode(s);
  return new ReadableStream({
    start(ctrl) {
      ctrl.enqueue(enc);
      ctrl.close();
    },
  });
}

class StubVision implements VisionAdapter {
  calls: Array<{ base64: string; mimeType: string }> = [];
  constructor(
    private readonly behaviour:
      | { kind: 'reply'; text: string }
      | { kind: 'throw'; error: unknown },
  ) {}
  async describeImage(base64Data: string, mimeType: string): Promise<string> {
    this.calls.push({ base64: base64Data, mimeType });
    if (this.behaviour.kind === 'throw') throw this.behaviour.error;
    return this.behaviour.text;
  }
}

const PDF_BYTES = new TextEncoder().encode('%PDF-1.4 fake-pdf-bytes');
const FIXED_HASH_HEX = 'deadbeef'.repeat(8); // 64 chars
const fixedHash = async (_b: Uint8Array) => FIXED_HASH_HEX;

// ── Layer A: cache ───────────────────────────────────────────────────────────

describe('PdfParser — Layer A (cache)', () => {
  it('returns cached text without invoking pdftotext or vision', async () => {
    const cache = new MapCache();
    cache.store.set(`pdf-text:${FIXED_HASH_HEX}`, 'cached text');

    const bookkeeping: SpawnStubBookkeeping = { calls: [] };
    const spawn = makeSpawnStub({ stdoutText: 'unused' }, bookkeeping);
    const vision = new StubVision({ kind: 'reply', text: 'unused vision' });

    const parser = new PdfParser({ cache, vision, spawn, sha256: fixedHash });
    const result = await parser.parse(PDF_BYTES);

    expect(result.text).toBe('cached text');
    expect(result.source).toBe('cache');
    expect(result.fromCache).toBe(true);
    expect(bookkeeping.calls.length).toBe(0);
    expect(vision.calls.length).toBe(0);
  });
});

// ── Layer B: pdftotext ───────────────────────────────────────────────────────

describe('PdfParser — Layer B (pdftotext)', () => {
  it('extracts text via pdftotext on cache miss and writes the cache', async () => {
    const cache = new MapCache();
    const bookkeeping: SpawnStubBookkeeping = { calls: [] };
    // Long enough non-whitespace, all printable — passes quality floor.
    const goodText = 'extracted text from PDF — line one with plenty of printable content here so the quality floor passes easily.';
    const spawn = makeSpawnStub({ stdoutText: goodText, exitCode: 0 }, bookkeeping);
    const vision = new StubVision({ kind: 'reply', text: 'unused' });

    const parser = new PdfParser({ cache, vision, spawn, sha256: fixedHash });
    const result = await parser.parse(PDF_BYTES);

    expect(result.source).toBe('pdftotext');
    expect(result.fromCache).toBe(false);
    expect(result.text).toBe(goodText);
    expect(bookkeeping.calls.length).toBe(1);
    expect(bookkeeping.calls[0].cmd).toEqual(['pdftotext', '-q', '-layout', '-', '-']);
    expect(bookkeeping.calls[0].stdinBytes).toEqual(PDF_BYTES);
    expect(vision.calls.length).toBe(0);
    expect(cache.puts).toEqual([{ key: `pdf-text:${FIXED_HASH_HEX}`, value: goodText }]);
  });

  it('escalates to Layer C when Layer B output is below quality floor', async () => {
    const cache = new MapCache();
    // 5 chars of garbage — below default minNonWhitespace=50.
    const spawn = makeSpawnStub({ stdoutText: 'a   b', exitCode: 0 });
    const vision = new StubVision({ kind: 'reply', text: 'OCR text' });

    const parser = new PdfParser({ cache, vision, spawn, sha256: fixedHash });
    const result = await parser.parse(PDF_BYTES);

    expect(result.source).toBe('vision');
    expect(result.text).toBe('OCR text');
    expect(vision.calls.length).toBe(1);
    expect(vision.calls[0].mimeType).toBe('application/pdf');
    expect(cache.store.get(`pdf-text:${FIXED_HASH_HEX}`)).toBe('OCR text');
  });

  it('falls through to Layer C when pdftotext exits non-zero', async () => {
    const cache = new MapCache();
    const spawn = makeSpawnStub({
      stdoutText: '',
      stderrText: 'Syntax Error: PDF file is corrupt',
      exitCode: 1,
    });
    const vision = new StubVision({ kind: 'reply', text: 'OCR rescued the day' });

    const parser = new PdfParser({ cache, vision, spawn, sha256: fixedHash });
    const result = await parser.parse(PDF_BYTES);

    expect(result.source).toBe('vision');
    expect(result.text).toBe('OCR rescued the day');
  });

  it('returns low-quality Layer B text as-is when vision is disabled (no throw)', async () => {
    const cache = new MapCache();
    const spawn = makeSpawnStub({ stdoutText: 'short', exitCode: 0 });

    const parser = new PdfParser({ cache, vision: null, spawn, sha256: fixedHash });
    const result = await parser.parse(PDF_BYTES);

    expect(result.source).toBe('pdftotext');
    expect(result.text).toBe('short');
    // Caller decides what to do with low-quality text — but cache it for next time.
    expect(cache.puts.length).toBe(1);
  });
});

// ── pdftotext not installed ──────────────────────────────────────────────────

describe('PdfParser — pdftotext not installed', () => {
  it('falls back to vision when pdftotext is missing and vision is configured', async () => {
    const cache = new MapCache();
    const enoent = Object.assign(new Error('spawn pdftotext ENOENT'), { code: 'ENOENT' });
    const spawn = makeSpawnStub({ throwOnSpawn: enoent });
    const vision = new StubVision({ kind: 'reply', text: 'vision-only path text' });

    const parser = new PdfParser({ cache, vision, spawn, sha256: fixedHash });
    const result = await parser.parse(PDF_BYTES);

    expect(result.source).toBe('vision');
    expect(result.text).toBe('vision-only path text');
  });

  it('throws PdftotextNotInstalled when pdftotext is missing AND vision is null', async () => {
    const cache = new MapCache();
    const enoent = Object.assign(new Error('spawn pdftotext ENOENT'), { code: 'ENOENT' });
    const spawn = makeSpawnStub({ throwOnSpawn: enoent });

    const parser = new PdfParser({ cache, vision: null, spawn, sha256: fixedHash });

    let thrown: unknown = null;
    try {
      await parser.parse(PDF_BYTES);
    } catch (e) {
      thrown = e;
    }
    expect(thrown).toBeInstanceOf(PdftotextNotInstalled);
    expect((thrown as Error).message).toContain('brew install poppler');
  });
});

// ── Caching disabled ─────────────────────────────────────────────────────────

describe('PdfParser — caching disabled', () => {
  it('does not consult or write any cache when opts.cache is null', async () => {
    const bookkeeping: SpawnStubBookkeeping = { calls: [] };
    const spawn = makeSpawnStub(
      { stdoutText: 'a' .repeat(60), exitCode: 0 },
      bookkeeping,
    );

    const parser = new PdfParser({ cache: null, vision: null, spawn, sha256: fixedHash });
    const r1 = await parser.parse(PDF_BYTES);
    const r2 = await parser.parse(PDF_BYTES);

    expect(r1.source).toBe('pdftotext');
    expect(r2.source).toBe('pdftotext');
    // pdftotext invoked every time, no cache short-circuit.
    expect(bookkeeping.calls.length).toBe(2);
  });
});

// ── Hash override ───────────────────────────────────────────────────────────

describe('PdfParser — hash override', () => {
  it('uses the supplied sha256 to derive the cache key', async () => {
    const cache = new MapCache();
    const customHash = async (_b: Uint8Array) => 'custom-hash-value';
    cache.store.set('pdf-text:custom-hash-value', 'cached via custom hash');

    const spawn = makeSpawnStub({ stdoutText: 'unused' });
    const parser = new PdfParser({ cache, vision: null, spawn, sha256: customHash });

    const result = await parser.parse(PDF_BYTES);
    expect(result.source).toBe('cache');
    expect(result.text).toBe('cached via custom hash');
  });
});

// ── Vision-throw propagation ────────────────────────────────────────────────

describe('PdfParser — vision errors propagate', () => {
  it('re-throws auth/rate-limit errors from vision (does not silently swallow)', async () => {
    const cache = new MapCache();
    const spawn = makeSpawnStub({ stdoutText: 'short', exitCode: 0 }); // forces Layer C
    class FakeAnthropicAuthError extends Error {
      constructor() { super('Invalid or missing Anthropic API key'); this.name = 'AnthropicAuthError'; }
    }
    const vision = new StubVision({ kind: 'throw', error: new FakeAnthropicAuthError() });

    const parser = new PdfParser({ cache, vision, spawn, sha256: fixedHash });

    let thrown: unknown = null;
    try {
      await parser.parse(PDF_BYTES);
    } catch (e) {
      thrown = e;
    }
    expect(thrown).not.toBeNull();
    expect((thrown as Error).name).toBe('AnthropicAuthError');
    expect(cache.puts.length).toBe(0);
  });
});

// ── isLowQuality unit tests ─────────────────────────────────────────────────

// ── Layer C chunking (large PDFs) ───────────────────────────────────────────

/**
 * Spawn router for chunking tests. Dispatches per-command stubs so a
 * single PdfParser call can drive several different binaries
 * (`pdftotext`, `mktemp`, `pdfseparate`, `rm`, `tee`).
 *
 * Each command stub may return either a `SpawnStubResult` shape (uniform
 * exit/text/throw) or a function that produces a fresh `SpawnedProcessLike`
 * each invocation — lets us count calls and synthesize per-call output.
 */
type CommandHandler =
  | SpawnStubResult
  | ((cmd: string[]) => SpawnedProcessLike);

interface RouterBookkeeping {
  calls: Array<{ cmd: string[]; stdinBytes: Uint8Array | null }>;
}

function makeRouterSpawn(
  handlers: Record<string, CommandHandler>,
  bookkeeping: RouterBookkeeping = { calls: [] },
): SpawnLike {
  return ((cmd: string[], _opts) => {
    const program = cmd[0];
    const handler = handlers[program];
    if (!handler) {
      throw Object.assign(new Error(`spawn ${program} ENOENT`), { code: 'ENOENT' });
    }

    const call: { cmd: string[]; stdinBytes: Uint8Array | null } = { cmd, stdinBytes: null };
    bookkeeping.calls.push(call);

    if (typeof handler === 'function') return handler(cmd);

    if (handler.throwOnSpawn) throw handler.throwOnSpawn;

    const stdin = {
      write(data: Uint8Array) { call.stdinBytes = data; },
      end() { /* no-op */ },
    };
    return {
      stdin: stdin as unknown as SpawnedProcessLike['stdin'],
      stdout: stringToReadableStream(handler.stdoutText ?? ''),
      stderr: stringToReadableStream(handler.stderrText ?? ''),
      exited: Promise.resolve(handler.exitCode ?? 0),
    };
  }) as SpawnLike;
}

/** Minimal pdftotext-failure handler so chunking tests reach Layer C cleanly. */
function pdftotextFails(): SpawnStubResult {
  return { stdoutText: '', stderrText: 'syntax error', exitCode: 1 };
}

describe('PdfParser — Layer C chunking (large PDFs)', () => {
  it('small PDF skips chunking — single Vision call, no pdfseparate spawn', async () => {
    // 100 bytes, default threshold = 4_500_000 → no chunking.
    const small = new Uint8Array(100).fill(65);

    const bookkeeping: RouterBookkeeping = { calls: [] };
    const spawn = makeRouterSpawn(
      { pdftotext: pdftotextFails() },
      bookkeeping,
    );
    const vision = new StubVision({ kind: 'reply', text: 'single-call OCR text' });

    const parser = new PdfParser({
      cache: null,
      vision,
      spawn,
      sha256: fixedHash,
    });

    const result = await parser.parse(small);
    expect(result.source).toBe('vision');
    expect(result.text).toBe('single-call OCR text');
    expect(result.pageCount).toBeUndefined();
    expect(vision.calls.length).toBe(1);
    // Only pdftotext was spawned; no pdfseparate / mktemp.
    expect(bookkeeping.calls.map((c) => c.cmd[0])).toEqual(['pdftotext']);
  });

  it('large PDF triggers chunking — N pages, Vision called N times, results concatenated in order', async () => {
    // 200 bytes, threshold lowered → chunk.
    const big = new Uint8Array(200).fill(66);

    const pageBytesByPath = new Map<string, Uint8Array>([
      ['/tmp/tmpdir/page-1.pdf', new TextEncoder().encode('page-one-bytes')],
      ['/tmp/tmpdir/page-2.pdf', new TextEncoder().encode('page-two-bytes')],
      ['/tmp/tmpdir/page-3.pdf', new TextEncoder().encode('page-three-bytes')],
    ]);
    const readFile = async (path: string): Promise<Uint8Array> => {
      const bytes = pageBytesByPath.get(path);
      if (!bytes) {
        // Simulate ENOENT for page-4+ so the parser stops probing.
        throw Object.assign(new Error(`ENOENT: ${path}`), { code: 'ENOENT' });
      }
      return bytes;
    };

    const bookkeeping: RouterBookkeeping = { calls: [] };
    const spawn = makeRouterSpawn(
      {
        pdftotext: pdftotextFails(),
        mktemp: { stdoutText: '/tmp/tmpdir\n', exitCode: 0 },
        pdfseparate: { stdoutText: '', exitCode: 0 },
        tee: { stdoutText: '', exitCode: 0 },
        rm: { stdoutText: '', exitCode: 0 },
      },
      bookkeeping,
    );

    let visionCallIdx = 0;
    const perPageOcr = ['OCR-PAGE-1', 'OCR-PAGE-2', 'OCR-PAGE-3'];
    const vision: VisionAdapter = {
      async describeImage(_b64: string, _mime: string): Promise<string> {
        return perPageOcr[visionCallIdx++];
      },
    };

    const parser = new PdfParser({
      cache: null,
      vision,
      spawn,
      sha256: fixedHash,
      maxVisionPdfBytes: 100, // force chunking
      readFile,
    });

    const result = await parser.parse(big);
    expect(result.source).toBe('vision');
    expect(result.pageCount).toBe(3);
    expect(visionCallIdx).toBe(3);
    expect(result.text).toContain('--- page 1 ---');
    expect(result.text).toContain('OCR-PAGE-1');
    expect(result.text).toContain('--- page 2 ---');
    expect(result.text).toContain('OCR-PAGE-2');
    expect(result.text).toContain('--- page 3 ---');
    expect(result.text).toContain('OCR-PAGE-3');
    // Order preservation:
    const idx1 = result.text.indexOf('OCR-PAGE-1');
    const idx2 = result.text.indexOf('OCR-PAGE-2');
    const idx3 = result.text.indexOf('OCR-PAGE-3');
    expect(idx1).toBeLessThan(idx2);
    expect(idx2).toBeLessThan(idx3);
    // pdfseparate was actually spawned.
    const programs = bookkeeping.calls.map((c) => c.cmd[0]);
    expect(programs).toContain('pdfseparate');
  });

  it('per-page Vision failure does not abort the whole PDF — emits failure marker, returns partial text', async () => {
    const big = new Uint8Array(200).fill(67);

    const pageBytesByPath = new Map<string, Uint8Array>([
      ['/tmp/tmpdir/page-1.pdf', new TextEncoder().encode('one')],
      ['/tmp/tmpdir/page-2.pdf', new TextEncoder().encode('two')],
      ['/tmp/tmpdir/page-3.pdf', new TextEncoder().encode('three')],
    ]);
    const readFile = async (path: string): Promise<Uint8Array> => {
      const bytes = pageBytesByPath.get(path);
      if (!bytes) throw Object.assign(new Error('ENOENT'), { code: 'ENOENT' });
      return bytes;
    };

    const spawn = makeRouterSpawn({
      pdftotext: pdftotextFails(),
      mktemp: { stdoutText: '/tmp/tmpdir\n', exitCode: 0 },
      pdfseparate: { stdoutText: '', exitCode: 0 },
      tee: { stdoutText: '', exitCode: 0 },
      rm: { stdoutText: '', exitCode: 0 },
    });

    let n = 0;
    const vision: VisionAdapter = {
      async describeImage(_b64, _mime): Promise<string> {
        n++;
        if (n === 2) throw new Error('rate limit hit on page 2');
        return `PAGE-${n}-OK`;
      },
    };

    const parser = new PdfParser({
      cache: null,
      vision,
      spawn,
      sha256: fixedHash,
      maxVisionPdfBytes: 100,
      readFile,
    });

    const result = await parser.parse(big);
    expect(result.source).toBe('vision');
    expect(result.pageCount).toBe(3);
    expect(result.text).toContain('--- page 1 ---');
    expect(result.text).toContain('PAGE-1-OK');
    expect(result.text).toContain('--- page 2: vision failed (rate limit hit on page 2) ---');
    expect(result.text).toContain('--- page 3 ---');
    expect(result.text).toContain('PAGE-3-OK');
  });

  it('throws PdfseparateNotInstalled when chunking is needed and pdfseparate is missing (ENOENT)', async () => {
    const big = new Uint8Array(200).fill(68);

    const spawn = makeRouterSpawn({
      pdftotext: pdftotextFails(),
      mktemp: { stdoutText: '/tmp/tmpdir\n', exitCode: 0 },
      tee: { stdoutText: '', exitCode: 0 },
      rm: { stdoutText: '', exitCode: 0 },
      pdfseparate: { throwOnSpawn: Object.assign(new Error('spawn pdfseparate ENOENT'), { code: 'ENOENT' }) },
    });

    const vision = new StubVision({ kind: 'reply', text: 'unused' });

    const parser = new PdfParser({
      cache: null,
      vision,
      spawn,
      sha256: fixedHash,
      maxVisionPdfBytes: 100,
      readFile: async () => new Uint8Array(),
    });

    let thrown: unknown = null;
    try {
      await parser.parse(big);
    } catch (e) {
      thrown = e;
    }
    expect(thrown).toBeInstanceOf(PdfseparateNotInstalled);
    expect((thrown as Error).message).toContain('brew install poppler');
  });

  it('configurable threshold — opts.maxVisionPdfBytes=1000 forces tiny inputs through the chunking path', async () => {
    // 1500 bytes — small in absolute terms, but above the test threshold.
    const bytes = new Uint8Array(1500).fill(69);

    const pageBytesByPath = new Map<string, Uint8Array>([
      ['/tmp/tmpdir/page-1.pdf', new TextEncoder().encode('only-page')],
    ]);
    const readFile = async (path: string): Promise<Uint8Array> => {
      const b = pageBytesByPath.get(path);
      if (!b) throw Object.assign(new Error('ENOENT'), { code: 'ENOENT' });
      return b;
    };

    const bookkeeping: RouterBookkeeping = { calls: [] };
    const spawn = makeRouterSpawn(
      {
        pdftotext: pdftotextFails(),
        mktemp: { stdoutText: '/tmp/tmpdir\n', exitCode: 0 },
        pdfseparate: { stdoutText: '', exitCode: 0 },
        tee: { stdoutText: '', exitCode: 0 },
        rm: { stdoutText: '', exitCode: 0 },
      },
      bookkeeping,
    );
    const vision = new StubVision({ kind: 'reply', text: 'page-text' });

    const parser = new PdfParser({
      cache: null,
      vision,
      spawn,
      sha256: fixedHash,
      maxVisionPdfBytes: 1000,
      readFile,
    });

    const result = await parser.parse(bytes);
    expect(result.source).toBe('vision');
    expect(result.pageCount).toBe(1);
    expect(result.text).toContain('--- page 1 ---');
    expect(result.text).toContain('page-text');
    // The chunking branch must have spawned pdfseparate.
    expect(bookkeeping.calls.map((c) => c.cmd[0])).toContain('pdfseparate');
  });
});

describe('isLowQuality', () => {
  const floor = { minNonWhitespace: 50, printableRatio: 0.7 };

  it('flags too few non-whitespace chars', () => {
    expect(isLowQuality('   short    ', floor)).toBe(true);
  });

  it('flags low printable-ASCII ratio', () => {
    // 100 chars, mostly non-printable — well above min non-whitespace, but garbled.
    const garbled = '\x01\x02\x03'.repeat(40) + 'abcdef';
    expect(isLowQuality(garbled, floor)).toBe(true);
  });

  it('passes plain English text', () => {
    const ok = 'This is a perfectly normal extracted text from a digital-native PDF document with plenty of printable content.';
    expect(isLowQuality(ok, floor)).toBe(false);
  });

  it('flags empty string', () => {
    expect(isLowQuality('', floor)).toBe(true);
  });
});

```
