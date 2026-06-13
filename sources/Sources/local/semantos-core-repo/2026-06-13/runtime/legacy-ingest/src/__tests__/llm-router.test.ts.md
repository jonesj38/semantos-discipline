---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/llm-router.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.144570+00:00
---

# runtime/legacy-ingest/src/__tests__/llm-router.test.ts

```ts
/**
 * LLM router tests — D-DOG.1d.
 *
 * Mirrors the sibling adapter tests' style: we exercise the router
 * against mock adapter instances that satisfy the OllamaAdapter /
 * AnthropicAdapter / OpenRouterAdapter shapes the router depends on
 * (`extract` for LLMAdapter, `describeImage` for VisionAdapter).
 *
 * The router's contract:
 *   • Walk preference list in order.
 *   • Throw → fall through to next backend (warn).
 *   • Confidence < floor → fall through (warn). On the LAST backend,
 *     return the low-confidence result tagged.
 *   • All backends throw → LlmRouterAllBackendsFailed.
 *   • Vision route skips ollama with a one-shot warning.
 *   • Construction validates preferences vs adapters.
 */

import { describe, it, expect } from 'bun:test';
import {
  LlmRouter,
  LlmRouterAllBackendsFailed,
  LlmRouterMisconfigured,
  type LlmRouterAdapters,
} from '../extractor/router';
import { OllamaConnectionError } from '../extractor/ollama';

// ── Mock adapter helpers ──────────────────────────────────────────────────────
//
// The router only depends on the public method shapes of its three
// concrete adapters: `.extract({prompt,schema})` and (for Anthropic /
// OpenRouter) `.describeImage(base64,mime)`. We build minimal mocks
// rather than driving real adapters with mock fetch — the adapter
// tests already cover the wire-level behaviour, and a thin mock keeps
// the router's routing logic the only thing under test here.

type ExtractFn = (opts: { prompt: string; schema: object }) => Promise<{
  payload: unknown;
  confidence: number;
  raw: string;
}>;

type DescribeFn = (base64: string, mime: string) => Promise<string>;

interface MockAdapter {
  extract: ExtractFn;
  describeImage: DescribeFn;
  /** Calls so tests can assert routing went where expected. */
  extractCalls: number;
  describeCalls: number;
}

function mockAdapter(
  extract?: Partial<{ payload: object; confidence: number; raw: string }> | (() => Promise<never> | never),
  describe?: string | (() => Promise<never> | never),
): MockAdapter {
  const m: MockAdapter = {
    extractCalls: 0,
    describeCalls: 0,
    extract: async () => {
      m.extractCalls += 1;
      if (typeof extract === 'function') {
        // Function form: call to throw or yield.
        return await (extract as () => Promise<never>)();
      }
      const e = extract ?? {};
      return {
        payload: e.payload ?? { ok: true },
        confidence: e.confidence ?? 0.9,
        raw: e.raw ?? '{"ok":true,"confidence":0.9}',
      };
    },
    describeImage: async () => {
      m.describeCalls += 1;
      if (typeof describe === 'function') {
        return await (describe as () => Promise<never>)();
      }
      return describe ?? '<transcribed text>';
    },
  };
  return m;
}

/**
 * Cast the mock to the adapter slot. The router only touches the public
 * methods we mock; the cast lets us compose `LlmRouterAdapters` without
 * dragging real constructors into the test.
 */
function asAdapters(opts: {
  ollama?: MockAdapter | null;
  anthropic?: MockAdapter | null;
  openrouter?: MockAdapter | null;
}): LlmRouterAdapters {
  return {
    ollama: (opts.ollama ?? null) as unknown as LlmRouterAdapters['ollama'],
    anthropic: (opts.anthropic ?? null) as unknown as LlmRouterAdapters['anthropic'],
    openrouter: (opts.openrouter ?? null) as unknown as LlmRouterAdapters['openrouter'],
  };
}

// ── Construction validation ───────────────────────────────────────────────────

describe('LlmRouter construction', () => {
  it('throws LlmRouterMisconfigured when every adapter is null', () => {
    expect(() =>
      new LlmRouter({
        adapters: asAdapters({}),
      }),
    ).toThrow(LlmRouterMisconfigured);
  });

  it('throws LlmRouterMisconfigured when extractionPreference references a null adapter', () => {
    const anthropic = mockAdapter();
    expect(() =>
      new LlmRouter({
        extractionPreference: ['ollama'],
        adapters: asAdapters({ anthropic, ollama: null }),
      }),
    ).toThrow(LlmRouterMisconfigured);
  });

  it('throws LlmRouterMisconfigured when visionPreference references a null adapter', () => {
    const anthropic = mockAdapter();
    expect(() =>
      new LlmRouter({
        visionPreference: ['openrouter'],
        adapters: asAdapters({ anthropic, openrouter: null }),
      }),
    ).toThrow(LlmRouterMisconfigured);
  });

  it('accepts ollama in visionPreference (skipped at call time, not construction)', () => {
    const anthropic = mockAdapter();
    expect(() =>
      new LlmRouter({
        visionPreference: ['ollama', 'anthropic'],
        adapters: asAdapters({ anthropic, ollama: null }),
      }),
    ).not.toThrow();
  });
});

// ── extract: happy path + backend tagging ─────────────────────────────────────

describe('LlmRouter.extract — happy path', () => {
  it('routes extraction to ollama by default and tags the result', async () => {
    const ollama = mockAdapter({ payload: { intent: 'lead' }, confidence: 0.9 });
    const anthropic = mockAdapter();
    const openrouter = mockAdapter();
    const router = new LlmRouter({
      adapters: asAdapters({ ollama, anthropic, openrouter }),
    });

    const r = await router.extract<{ intent: string }>({ prompt: 'x', schema: {} });

    expect(r.backend).toBe('ollama');
    expect(r.payload.intent).toBe('lead');
    expect(r.confidence).toBeCloseTo(0.9);
    expect(ollama.extractCalls).toBe(1);
    expect(anthropic.extractCalls).toBe(0);
    expect(openrouter.extractCalls).toBe(0);
  });

  it('respects an explicit extractionPreference (anthropic-first)', async () => {
    const ollama = mockAdapter({ confidence: 0.95 });
    const anthropic = mockAdapter({ payload: { hi: true }, confidence: 0.85 });
    const router = new LlmRouter({
      extractionPreference: ['anthropic', 'ollama'],
      adapters: asAdapters({ ollama, anthropic }),
    });

    const r = await router.extract<{ hi: boolean }>({ prompt: 'x', schema: {} });

    expect(r.backend).toBe('anthropic');
    expect(r.payload.hi).toBe(true);
    expect(anthropic.extractCalls).toBe(1);
    expect(ollama.extractCalls).toBe(0);
  });

  it('skips a disabled backend (null adapter) and routes to the next', async () => {
    const anthropic = mockAdapter({ payload: { from: 'anthropic' }, confidence: 0.8 });
    // Even though "ollama" is first in preference, it's disabled (null);
    // router should fall through silently to anthropic.
    const router = new LlmRouter({
      extractionPreference: ['anthropic'],
      adapters: asAdapters({ ollama: null, anthropic }),
    });

    const r = await router.extract<{ from: string }>({ prompt: 'x', schema: {} });

    expect(r.backend).toBe('anthropic');
    expect(r.payload.from).toBe('anthropic');
    expect(anthropic.extractCalls).toBe(1);
  });
});

// ── extract: fall-through on adapter throw ────────────────────────────────────

describe('LlmRouter.extract — fall-through on errors', () => {
  it('falls through ollama → anthropic when ollama throws OllamaConnectionError', async () => {
    const ollama = mockAdapter(() => {
      throw new OllamaConnectionError('Could not reach Ollama at http://localhost:11434: ECONNREFUSED. Is `ollama serve` running?');
    });
    const anthropic = mockAdapter({ payload: { rescue: true }, confidence: 0.92 });
    const router = new LlmRouter({
      adapters: asAdapters({ ollama, anthropic }),
    });

    const r = await router.extract<{ rescue: boolean }>({ prompt: 'x', schema: {} });

    expect(r.backend).toBe('anthropic');
    expect(r.payload.rescue).toBe(true);
    expect(ollama.extractCalls).toBe(1);
    expect(anthropic.extractCalls).toBe(1);
  });

  it('throws LlmRouterAllBackendsFailed when every backend throws', async () => {
    const ollama = mockAdapter(() => {
      throw new OllamaConnectionError('ollama down');
    });
    const anthropic = mockAdapter(() => {
      const e = new Error('Invalid or missing Anthropic API key');
      e.name = 'AnthropicAuthError';
      throw e;
    });
    const router = new LlmRouter({
      extractionPreference: ['ollama', 'anthropic'],
      adapters: asAdapters({ ollama, anthropic }),
    });

    let caught: unknown = null;
    try {
      await router.extract({ prompt: 'x', schema: {} });
    } catch (e) {
      caught = e;
    }
    expect(caught).toBeInstanceOf(LlmRouterAllBackendsFailed);
    const err = caught as LlmRouterAllBackendsFailed;
    expect(err.kind).toBe('extraction');
    expect(err.attempts).toHaveLength(2);
    expect(err.attempts[0].backend).toBe('ollama');
    expect(err.attempts[1].backend).toBe('anthropic');
    // Message should include both backends — operator's first-look log.
    expect(err.message).toContain('ollama');
    expect(err.message).toContain('anthropic');
    expect(err.message).toContain('extraction');
  });
});

// ── extract: fall-through on low confidence ───────────────────────────────────

describe('LlmRouter.extract — confidence floor', () => {
  it('falls through when ollama returns confidence below the default floor (0.5)', async () => {
    const ollama = mockAdapter({ payload: { from: 'ollama' }, confidence: 0.3 });
    const anthropic = mockAdapter({ payload: { from: 'anthropic' }, confidence: 0.9 });
    const router = new LlmRouter({
      adapters: asAdapters({ ollama, anthropic }),
    });

    const r = await router.extract<{ from: string }>({ prompt: 'x', schema: {} });

    expect(r.backend).toBe('anthropic');
    // The first call's payload must be DISCARDED, not merged.
    expect(r.payload.from).toBe('anthropic');
    expect(r.confidence).toBeCloseTo(0.9);
    expect(ollama.extractCalls).toBe(1);
    expect(anthropic.extractCalls).toBe(1);
  });

  it('respects a configurable confidenceFloor', async () => {
    // Floor 0.8: ollama's 0.7 falls through; anthropic's 0.85 wins.
    const ollama = mockAdapter({ payload: { from: 'ollama' }, confidence: 0.7 });
    const anthropic = mockAdapter({ payload: { from: 'anthropic' }, confidence: 0.85 });
    const router = new LlmRouter({
      confidenceFloor: 0.8,
      adapters: asAdapters({ ollama, anthropic }),
    });

    const r = await router.extract<{ from: string }>({ prompt: 'x', schema: {} });

    expect(r.backend).toBe('anthropic');
    expect(r.payload.from).toBe('anthropic');
  });

  it('returns the low-confidence result from the LAST backend rather than throwing', async () => {
    // Single backend, low confidence → returned tagged. The orchestrator
    // (not the router) decides whether to drop it.
    const ollama = mockAdapter({ payload: { iffy: true }, confidence: 0.2 });
    const router = new LlmRouter({
      extractionPreference: ['ollama'],
      adapters: asAdapters({ ollama }),
    });

    const r = await router.extract<{ iffy: boolean }>({ prompt: 'x', schema: {} });

    expect(r.backend).toBe('ollama');
    expect(r.confidence).toBeCloseTo(0.2);
    expect(r.payload.iffy).toBe(true);
  });
});

// ── extract: backend-tag correctness on every path ────────────────────────────

describe('LlmRouter.extract — backend tag is set on every return path', () => {
  it('tags happy-path returns', async () => {
    const ollama = mockAdapter({ confidence: 0.9 });
    const router = new LlmRouter({
      extractionPreference: ['ollama'],
      adapters: asAdapters({ ollama }),
    });
    const r = await router.extract({ prompt: 'x', schema: {} });
    expect(r.backend).toBe('ollama');
  });

  it('tags fallback-after-error returns with the surviving backend', async () => {
    const ollama = mockAdapter(() => {
      throw new Error('boom');
    });
    const openrouter = mockAdapter({ confidence: 0.8 });
    const router = new LlmRouter({
      extractionPreference: ['ollama', 'openrouter'],
      adapters: asAdapters({ ollama, openrouter }),
    });
    const r = await router.extract({ prompt: 'x', schema: {} });
    expect(r.backend).toBe('openrouter');
  });

  it('tags fallback-after-low-confidence returns with the surviving backend', async () => {
    const ollama = mockAdapter({ confidence: 0.1 });
    const anthropic = mockAdapter({ confidence: 0.95 });
    const router = new LlmRouter({
      extractionPreference: ['ollama', 'anthropic'],
      adapters: asAdapters({ ollama, anthropic }),
    });
    const r = await router.extract({ prompt: 'x', schema: {} });
    expect(r.backend).toBe('anthropic');
  });
});

// ── Vision routing ────────────────────────────────────────────────────────────

describe('LlmRouter vision routing', () => {
  it('routes vision to anthropic by default — never calls ollama', async () => {
    const ollama = mockAdapter({}, () => {
      throw new Error('ollama vision should never be called');
    });
    const anthropic = mockAdapter({}, '<<<transcribed by anthropic>>>');
    const openrouter = mockAdapter();
    const router = new LlmRouter({
      adapters: asAdapters({ ollama, anthropic, openrouter }),
    });

    const text = await router.describeImage('AAAA', 'image/png');

    expect(text).toBe('<<<transcribed by anthropic>>>');
    expect(anthropic.describeCalls).toBe(1);
    expect(ollama.describeCalls).toBe(0);
    expect(openrouter.describeCalls).toBe(0);
  });

  it('falls through anthropic → openrouter when anthropic throws', async () => {
    const anthropic = mockAdapter({}, () => {
      throw new Error('Anthropic overloaded');
    });
    const openrouter = mockAdapter({}, '<<<openrouter saved us>>>');
    const router = new LlmRouter({
      adapters: asAdapters({ anthropic, openrouter }),
    });

    const text = await router.describeImage('AAAA', 'image/png');
    expect(text).toBe('<<<openrouter saved us>>>');
    expect(anthropic.describeCalls).toBe(1);
    expect(openrouter.describeCalls).toBe(1);
  });

  it('skips ollama if it appears in visionPreference (defensive)', async () => {
    const ollama = mockAdapter({}, () => {
      throw new Error('ollama vision should never be called');
    });
    const anthropic = mockAdapter({}, '<<<anthropic>>>');
    const router = new LlmRouter({
      visionPreference: ['ollama', 'anthropic'],
      adapters: asAdapters({ ollama, anthropic }),
    });

    const text = await router.describeImage('AAAA', 'image/png');
    expect(text).toBe('<<<anthropic>>>');
    expect(ollama.describeCalls).toBe(0);
    expect(anthropic.describeCalls).toBe(1);
  });

  it('throws LlmRouterAllBackendsFailed when every vision backend throws', async () => {
    const anthropic = mockAdapter({}, () => {
      throw new Error('anthropic 500');
    });
    const openrouter = mockAdapter({}, () => {
      throw new Error('openrouter 500');
    });
    const router = new LlmRouter({
      adapters: asAdapters({ anthropic, openrouter }),
    });

    let caught: unknown = null;
    try {
      await router.describeImage('AAAA', 'image/png');
    } catch (e) {
      caught = e;
    }
    expect(caught).toBeInstanceOf(LlmRouterAllBackendsFailed);
    const err = caught as LlmRouterAllBackendsFailed;
    expect(err.kind).toBe('vision');
    expect(err.attempts).toHaveLength(2);
    expect(err.message).toContain('vision');
  });

  it('ocr() returns the backend tag alongside the text', async () => {
    const anthropic = mockAdapter({}, '<<<anthropic OCR text>>>');
    const router = new LlmRouter({
      adapters: asAdapters({ anthropic }),
    });

    const r = await router.ocr({ base64Data: 'AAAA', mimeType: 'application/pdf' });
    expect(r.text).toBe('<<<anthropic OCR text>>>');
    expect(r.backend).toBe('anthropic');
  });
});

```
