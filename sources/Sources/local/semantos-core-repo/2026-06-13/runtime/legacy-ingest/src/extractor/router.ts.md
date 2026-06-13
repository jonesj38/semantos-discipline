---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/extractor/router.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.159321+00:00
---

# runtime/legacy-ingest/src/extractor/router.ts

```ts
/**
 * LLM router — D-DOG.1d.
 *
 * Composes the three concrete adapters (Ollama / Anthropic / OpenRouter)
 * and dispatches per-call so the rest of the system gets a single
 * `LLMAdapter` + `VisionAdapter` and never has to know which backend
 * actually served a request.
 *
 * Operator preferences encoded in the defaults:
 *   • Local Ollama for shell ops (extraction, classification, dedupe) —
 *     sovereign, free, fast on an M-series Mac.
 *   • BYOK Claude (Anthropic direct) for vision and high-stakes
 *     generative — local 3B models can't reliably do vision.
 *   • OpenRouter as a fallback / legacy path; not the default for
 *     anything.
 *
 * Routing semantics: walk the preference list in order, skip any
 * backend that's been disabled (null adapter), try the next, and fall
 * through on either an adapter throw OR a confidence-below-floor return.
 * The final `backend` tag is included in the result so callers + tests
 * can see which path actually served the request.
 *
 * No retry-with-backoff lives here — the per-adapter timeouts already
 * bound how long any one call can hang, and falling through on the
 * FIRST failure is the right shape for "Ollama is down → use Anthropic"
 * which is the dominant failure mode.
 */

import type { LLMAdapter } from './types';
import type { VisionAdapter } from './attachment';
import type { OllamaAdapter } from './ollama';
import type { AnthropicAdapter } from './anthropic';
import type { OpenRouterAdapter } from './openrouter';

// ── Public types ─────────────────────────────────────────────────────────────

export type LlmBackend = 'ollama' | 'anthropic' | 'openrouter';

export interface LlmRouterAdapters {
  ollama: OllamaAdapter | null;
  anthropic: AnthropicAdapter | null;
  openrouter: OpenRouterAdapter | null;
}

export interface LlmRouterOpts {
  /**
   * Ordered preference for shell/extraction calls.
   * Default: ["ollama", "anthropic", "openrouter"]
   *
   * The router tries them in order, falling through on adapter failure
   * (connection refused, model not found, auth, parse, timeout, etc.)
   * to the next entry. Also falls through when a backend returns a
   * confidence below `confidenceFloor`.
   */
  extractionPreference?: readonly LlmBackend[];
  /**
   * Vision calls (PDF/image OCR). Ollama is intentionally excluded
   * (local 3B models can't reliably do vision); if it appears here it
   * is skipped with a one-time warning.
   * Default: ["anthropic", "openrouter"]
   */
  visionPreference?: readonly LlmBackend[];
  /**
   * Confidence floor for extraction results. If a higher-priority
   * backend returns confidence below this AND there's another backend
   * left in the preference list, the router retries with the next
   * backend.
   * Default: 0.5 (matches the existing OpenRouter floor policy).
   */
  confidenceFloor?: number;
  /** The concrete adapters. Pass null for any backend you want disabled. */
  adapters: LlmRouterAdapters;
}

/**
 * Result of a router-served `extract` call. Includes the standard
 * `LLMAdapter.extract` payload plus a `backend` tag identifying the
 * adapter that served the request.
 */
export interface RoutedExtractResult<T> {
  payload: T;
  confidence: number;
  raw: string;
  backend: LlmBackend;
}

/**
 * Result of a router-served `describeImage` call. Adds the `backend`
 * tag to the plain `string` return of the underlying VisionAdapter so
 * the caller can see which OCR provider transcribed the document.
 */
export interface RoutedOcrResult {
  text: string;
  backend: LlmBackend;
}

// ── Errors ───────────────────────────────────────────────────────────────────

/**
 * Thrown when every backend the router tried failed (or returned a
 * value below the confidence floor). The message includes a
 * one-line-per-backend summary of what went wrong so the operator's
 * first look at logs tells them what to fix.
 */
export class LlmRouterAllBackendsFailed extends Error {
  constructor(
    /** Which call shape failed: extraction or vision. */
    readonly kind: 'extraction' | 'vision',
    /** [(backend, error message)] in the order they were tried. */
    readonly attempts: ReadonlyArray<{ backend: LlmBackend; error: string }>,
  ) {
    super(
      `${kind} failed across [${attempts.map((a) => `${a.backend}: ${a.error}`).join(', ')}]`,
    );
    this.name = 'LlmRouterAllBackendsFailed';
  }
}

/**
 * Thrown at construction time if the preference lists reference a
 * backend that's null in `adapters`, or if every adapter is null.
 * Fail-fast so misconfiguration surfaces at boot, not at first call.
 */
export class LlmRouterMisconfigured extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'LlmRouterMisconfigured';
  }
}

// ── Defaults ─────────────────────────────────────────────────────────────────

const DEFAULT_EXTRACTION_PREFERENCE: readonly LlmBackend[] = [
  'ollama',
  'anthropic',
  'openrouter',
];
const DEFAULT_VISION_PREFERENCE: readonly LlmBackend[] = [
  'anthropic',
  'openrouter',
];
const DEFAULT_CONFIDENCE_FLOOR = 0.5;

// ── Router ───────────────────────────────────────────────────────────────────

export class LlmRouter implements LLMAdapter, VisionAdapter {
  private readonly adapters: LlmRouterAdapters;
  private readonly extractionPreference: readonly LlmBackend[];
  private readonly visionPreference: readonly LlmBackend[];
  private readonly confidenceFloor: number;
  /**
   * One-shot guard so we only warn once per process if the operator
   * accidentally listed `ollama` in `visionPreference` — Ollama can't
   * do vision, so we silently skip it after the first warning.
   */
  private warnedOllamaVision = false;

  constructor(opts: LlmRouterOpts) {
    this.adapters = opts.adapters;
    const explicitExtraction = opts.extractionPreference !== undefined;
    const explicitVision = opts.visionPreference !== undefined;
    this.extractionPreference = opts.extractionPreference ?? DEFAULT_EXTRACTION_PREFERENCE;
    this.visionPreference = opts.visionPreference ?? DEFAULT_VISION_PREFERENCE;
    this.confidenceFloor = opts.confidenceFloor ?? DEFAULT_CONFIDENCE_FLOOR;

    // Fail-fast: at least one adapter must be wired. A router with
    // every backend null is just a louder NullAdapter and will
    // silently swallow every call, which is exactly the bug the
    // operator pulled the router in to fix.
    const wired = (Object.keys(this.adapters) as Array<keyof LlmRouterAdapters>)
      .filter((k) => this.adapters[k] !== null);
    if (wired.length === 0) {
      throw new LlmRouterMisconfigured(
        'LlmRouter requires at least one non-null adapter (ollama, anthropic, or openrouter)',
      );
    }

    // Fail-fast: any backend named in an EXPLICITLY-supplied preference
    // list MUST be wired. Silently skipping a misconfigured preference
    // makes routing decisions hard to reason about ("why is Anthropic
    // serving when I said Ollama?"). The DEFAULT preference lists name
    // every backend; we tolerate missing adapters there because the
    // operator commonly wires only one (one env var set) and expects
    // the router to do the right thing.
    if (explicitExtraction) {
      for (const b of this.extractionPreference) {
        if (this.adapters[b] === null) {
          throw new LlmRouterMisconfigured(
            `LlmRouter extractionPreference includes "${b}" but adapters.${b} is null`,
          );
        }
      }
    }
    if (explicitVision) {
      for (const b of this.visionPreference) {
        // Ollama in visionPreference is a soft warning, not a hard
        // misconfigure — local 3B models can't do vision and we skip
        // ollama at call time anyway.
        if (b === 'ollama') continue;
        if (this.adapters[b] === null) {
          throw new LlmRouterMisconfigured(
            `LlmRouter visionPreference includes "${b}" but adapters.${b} is null`,
          );
        }
      }
    }
  }

  // ── LLMAdapter ───────────────────────────────────────────────────────────

  async extract<T>(opts: { prompt: string; schema: object }): Promise<RoutedExtractResult<T>> {
    const attempts: Array<{ backend: LlmBackend; error: string }> = [];
    // Tracks the "best so far" low-confidence response. If every backend
    // returns below the floor, we surface this rather than throwing —
    // the caller's confidence-aware code path (orchestrator gating)
    // already understands low-confidence results.
    let lowConfidenceFallback:
      | { backend: LlmBackend; result: { payload: T; confidence: number; raw: string } }
      | null = null;

    for (let i = 0; i < this.extractionPreference.length; i++) {
      const backend = this.extractionPreference[i];
      const adapter = this.adapters[backend];
      if (!adapter) continue; // construction guard makes this unreachable, but defensive

      let result: { payload: T; confidence: number; raw: string };
      try {
        result = await adapter.extract<T>(opts);
      } catch (err) {
        const msg = errorMessage(err);
        attempts.push({ backend, error: msg });
        // eslint-disable-next-line no-console
        console.warn(
          `[llm-router] extraction backend "${backend}" failed: ${msg}` +
            (i + 1 < this.extractionPreference.length ? ' — falling through' : ''),
        );
        continue;
      }

      if (result.confidence < this.confidenceFloor) {
        // Remember the most-recent low-confidence result so we have
        // something to return if every backend comes in low.
        lowConfidenceFallback = { backend, result };
        const isLast = i + 1 >= this.extractionPreference.length;
        if (isLast) {
          // No backend left; return what we have, tagged.
          return { ...result, backend };
        }
        // eslint-disable-next-line no-console
        console.warn(
          `[llm-router] extraction backend "${backend}" returned confidence ${result.confidence.toFixed(2)} < floor ${this.confidenceFloor} — falling through`,
        );
        attempts.push({
          backend,
          error: `confidence ${result.confidence.toFixed(2)} below floor ${this.confidenceFloor}`,
        });
        continue;
      }

      return { ...result, backend };
    }

    // Every backend either threw or returned low confidence. If we
    // have a low-confidence result remembered, return it; otherwise
    // throw with the full attempt list so the operator sees what
    // failed and where.
    if (lowConfidenceFallback) {
      return { ...lowConfidenceFallback.result, backend: lowConfidenceFallback.backend };
    }
    throw new LlmRouterAllBackendsFailed('extraction', attempts);
  }

  // ── VisionAdapter ────────────────────────────────────────────────────────

  /**
   * Implements the VisionAdapter port (`describeImage`). The router-aware
   * counterpart `ocr()` returns the same text plus the `backend` tag.
   * Existing call sites that treat the router as a plain VisionAdapter
   * (e.g. `EmailExtractor`) just see the string.
   */
  async describeImage(base64Data: string, mimeType: string): Promise<string> {
    const { text } = await this.ocr({ base64Data, mimeType });
    return text;
  }

  /**
   * Backend-tagged OCR. Mirrors `extract`'s shape: returns the
   * transcribed `text` plus the `backend` that served it. Defaults to
   * Anthropic → OpenRouter; Ollama is silently skipped (with a one-shot
   * warning) because local 3B models can't do vision.
   */
  async ocr(args: { base64Data: string; mimeType: string }): Promise<RoutedOcrResult> {
    const attempts: Array<{ backend: LlmBackend; error: string }> = [];

    for (const backend of this.visionPreference) {
      if (backend === 'ollama') {
        if (!this.warnedOllamaVision) {
          this.warnedOllamaVision = true;
          // eslint-disable-next-line no-console
          console.warn(
            '[llm-router] visionPreference includes "ollama" — local 3B Llama models do not reliably support vision; skipping',
          );
        }
        continue;
      }
      const adapter = this.adapters[backend];
      if (!adapter) continue;

      try {
        const text = await adapter.describeImage(args.base64Data, args.mimeType);
        return { text, backend };
      } catch (err) {
        const msg = errorMessage(err);
        attempts.push({ backend, error: msg });
        // eslint-disable-next-line no-console
        console.warn(`[llm-router] vision backend "${backend}" failed: ${msg} — falling through`);
        continue;
      }
    }

    throw new LlmRouterAllBackendsFailed('vision', attempts);
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function errorMessage(err: unknown): string {
  if (err instanceof Error) return `${err.name}: ${err.message}`;
  return String(err);
}

```
