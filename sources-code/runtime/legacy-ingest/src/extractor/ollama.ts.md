---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/extractor/ollama.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.159018+00:00
---

# runtime/legacy-ingest/src/extractor/ollama.ts

```ts
/**
 * Ollama adapter — LI3 local LLM client (D-DOG.1b).
 *
 * Implements LLMAdapter against a local Ollama server, so shell ops
 * (extraction, classification, dedupe — the bulk of LLM work) can run
 * sovereign on the operator's machine without touching a hosted API.
 *
 * Routing between this adapter and a hosted adapter (OpenRouter /
 * Anthropic) is the job of D-DOG.1d (router) — this PR only ships the
 * adapter. Generative contexts that need vision will continue to fall
 * back to hosted Claude.
 *
 * Vision: NOT supported. Local Llama models in the 3B class don't
 * reliably do vision. VisionAdapter is intentionally not implemented
 * here — callers needing OCR must use OpenRouterAdapter / AnthropicAdapter.
 *
 * Wire shape (chat endpoint, preferred — preserves system+user split):
 *   POST {baseUrl}/api/chat
 *   {
 *     "model": "llama3.2:3b",
 *     "messages": [{"role":"system","content":"..."},{"role":"user","content":"..."}],
 *     "stream": false,
 *     "format": "json",
 *     "options": { "temperature": 0.0 }
 *   }
 * Response: { "message": { "role": "assistant", "content": "..." }, "done": true, ... }
 *
 * Schema augmentation:
 *   The caller's schema is augmented with a `confidence` field that the
 *   model self-rates; the adapter strips it before returning the typed
 *   payload. Mirrors OpenRouterAdapter so call sites are interchangeable.
 *
 * Confidence floor:
 *   We do NOT gate on confidence here — we pass the model's self-rated
 *   number through (clamped to [0,1], defaulted to 0.7 if absent). The
 *   ratification orchestrator decides whether to drop, auto-ratify, or
 *   surface to the operator.
 */

import type { LLMAdapter } from './types';

type FetchLike = (url: string, init?: RequestInit) => Promise<Response>;

export interface OllamaAdapterOpts {
  /** Base URL of the Ollama server. Default: http://localhost:11434 */
  baseUrl?: string;
  /** Model tag (e.g. "llama3.2:3b", "qwen2.5:3b-instruct"). Default: "llama3.2:3b" */
  model?: string;
  /** HTTP fetch. Defaults to globalThis.fetch. */
  fetch?: FetchLike;
  /** Request timeout in ms. Default: 60000 */
  timeoutMs?: number;
}

const DEFAULT_BASE_URL = 'http://localhost:11434';
const DEFAULT_MODEL = 'llama3.2:3b';
const DEFAULT_TIMEOUT_MS = 60_000;

/** System prompt for JSON extraction — mirrors OpenRouterAdapter's. */
const EXTRACTION_SYSTEM = `You are a structured data extraction assistant.
Respond ONLY with a single JSON object matching the provided schema.
Include a "confidence" field (0.0–1.0) indicating how certain you are.
Do not include any prose or markdown outside the JSON object.`;

export class OllamaAdapter implements LLMAdapter {
  private readonly baseUrl: string;
  private readonly model: string;
  private readonly fetchImpl: FetchLike;
  private readonly timeoutMs: number;

  constructor(opts: OllamaAdapterOpts = {}) {
    // Strip a trailing slash so we can always concat with `/api/chat`.
    const base = opts.baseUrl ?? DEFAULT_BASE_URL;
    this.baseUrl = base.endsWith('/') ? base.slice(0, -1) : base;
    this.model = opts.model ?? DEFAULT_MODEL;
    this.fetchImpl = opts.fetch ?? ((url, init) => fetch(url, init));
    this.timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  }

  // ── LLMAdapter ───────────────────────────────────────────────────────────

  async extract<T>(opts: { prompt: string; schema: object }): Promise<{
    payload: T;
    confidence: number;
    raw: string;
  }> {
    const augmentedSchema = augmentWithConfidence(opts.schema);
    const userMessage = `${opts.prompt}\n\nRespond with a JSON object matching this schema:\n${JSON.stringify(augmentedSchema, null, 2)}`;

    const body = JSON.stringify({
      model: this.model,
      messages: [
        { role: 'system', content: EXTRACTION_SYSTEM },
        { role: 'user', content: userMessage },
      ],
      stream: false,
      format: 'json',
      options: { temperature: 0.0 },
    });

    const res = await this.post('/api/chat', body);
    const raw = extractContent(res);
    const { confidence, payload } = parseExtractionResponse<T>(raw);
    return { payload, confidence, raw };
  }

  // ── Internals ────────────────────────────────────────────────────────────

  private async post(path: string, body: string): Promise<OllamaChatResponse> {
    const url = `${this.baseUrl}${path}`;

    // Wire up an AbortController so a hung Ollama server (e.g. the model
    // is mid-load and never responds) eventually surfaces as OllamaTimeout
    // rather than hanging the extractor pipeline.
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);

    let res: Response;
    try {
      res = await this.fetchImpl(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body,
        signal: controller.signal,
      });
    } catch (err) {
      // AbortError → timeout. Any other fetch-level error → connection refused
      // / DNS failure / TLS error etc. Map both to friendly typed errors so
      // the operator sees "did you `ollama serve`?" rather than ECONNREFUSED.
      if (isAbortError(err)) {
        throw new OllamaTimeout(this.timeoutMs);
      }
      throw new OllamaConnectionError(
        `Could not reach Ollama at ${this.baseUrl}: ${errorMessage(err)}. Is \`ollama serve\` running?`,
        err,
      );
    } finally {
      clearTimeout(timer);
    }

    if (res.status === 404) {
      // Ollama returns 404 with a body like {"error":"model 'foo' not found, try pulling it first"}.
      const text = await res.text().catch(() => '');
      throw new OllamaModelNotFound(this.model, text.slice(0, 200));
    }
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw new OllamaError(`HTTP ${res.status}: ${text.slice(0, 200)}`, res.status);
    }

    return (await res.json()) as OllamaChatResponse;
  }
}

// ── Response shape ───────────────────────────────────────────────────────────

interface OllamaChatResponse {
  message?: { role?: string; content?: string | null };
  done?: boolean;
  error?: string;
}

function extractContent(res: OllamaChatResponse): string {
  if (res.error) {
    throw new OllamaError(res.error, 0);
  }
  const content = res.message?.content;
  if (typeof content !== 'string' || content.length === 0) {
    throw new OllamaError('Ollama returned empty content', 0);
  }
  return content;
}

function parseExtractionResponse<T>(raw: string): { payload: T; confidence: number } {
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(raw);
  } catch {
    // Even with format:"json" set, smaller local models occasionally wrap
    // the JSON object in prose. Try to pull the first {...} block before
    // giving up — same fallback OpenRouterAdapter uses.
    const m = raw.match(/\{[\s\S]*\}/);
    if (!m) {
      throw new OllamaParseError(`Ollama did not return valid JSON: ${raw.slice(0, 200)}`, raw);
    }
    try {
      parsed = JSON.parse(m[0]);
    } catch {
      throw new OllamaParseError(`Ollama did not return valid JSON: ${raw.slice(0, 200)}`, raw);
    }
  }

  const confidence = typeof parsed.confidence === 'number'
    ? Math.min(1, Math.max(0, parsed.confidence))
    : 0.7; // conservative default when the model omits the field

  const { confidence: _dropped, ...payload } = parsed;
  void _dropped;
  return { payload: payload as T, confidence };
}

function augmentWithConfidence(schema: object): object {
  const s = schema as Record<string, unknown>;
  const props = (s.properties as Record<string, unknown>) ?? {};
  const required = Array.isArray(s.required) ? s.required : [];
  return {
    ...s,
    properties: {
      ...props,
      confidence: {
        type: 'number',
        minimum: 0,
        maximum: 1,
        description: 'How confident you are in this extraction (0=guessing, 1=certain).',
      },
    },
    required: required.includes('confidence') ? required : [...required, 'confidence'],
  };
}

function isAbortError(err: unknown): boolean {
  if (!err || typeof err !== 'object') return false;
  const name = (err as { name?: unknown }).name;
  return name === 'AbortError' || name === 'TimeoutError';
}

function errorMessage(err: unknown): string {
  if (err instanceof Error) return err.message;
  return String(err);
}

// ── Errors ───────────────────────────────────────────────────────────────────

/** Base error for all Ollama adapter failures. */
export class OllamaError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
    this.name = 'OllamaError';
  }
}

/**
 * Thrown when the Ollama server is unreachable — almost always because
 * the operator forgot to run `ollama serve`. The message is intentionally
 * actionable so the operator doesn't have to decode an ECONNREFUSED.
 */
export class OllamaConnectionError extends OllamaError {
  constructor(message: string, readonly cause?: unknown) {
    super(message, 0);
    this.name = 'OllamaConnectionError';
  }
}

/**
 * Thrown when Ollama returns 404 for the configured model — the operator
 * hasn't run `ollama pull <model>` yet.
 */
export class OllamaModelNotFound extends OllamaError {
  constructor(readonly model: string, readonly serverMessage: string) {
    super(`Ollama model "${model}" is not installed. Run \`ollama pull ${model}\`. (server: ${serverMessage})`, 404);
    this.name = 'OllamaModelNotFound';
  }
}

/** Thrown when the model's response can't be parsed as JSON. */
export class OllamaParseError extends OllamaError {
  constructor(message: string, readonly raw: string) {
    super(message, 0);
    this.name = 'OllamaParseError';
  }
}

/** Thrown when a request exceeds the configured `timeoutMs`. */
export class OllamaTimeout extends OllamaError {
  constructor(readonly timeoutMs: number) {
    super(`Ollama request timed out after ${timeoutMs}ms`, 0);
    this.name = 'OllamaTimeout';
  }
}

```
