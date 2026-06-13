---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/extractor/openrouter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.160785+00:00
---

# runtime/legacy-ingest/src/extractor/openrouter.ts

```ts
/**
 * OpenRouter adapter — LI3 production LLM client.
 *
 * Implements both LLMAdapter (structured JSON extraction) and VisionAdapter
 * (OCR of images and PDF documents) against the OpenRouter API using a
 * single API key. The same key already drives intent classification and
 * embeddings elsewhere in the system.
 *
 * Text extraction:
 *   POST /chat/completions with response_format: json_object.
 *   The adapter augments the caller's schema with a `confidence` field
 *   so the model self-rates its certainty, then strips it before returning
 *   the typed payload.
 *
 * Vision / OCR:
 *   For images (image/*): content block with data URI image_url.
 *   For PDFs (application/pdf): Anthropic document block when routing via
 *   an anthropic/* model — supports multi-page PDFs natively up to ~100
 *   pages. Falls back to image_url for non-Anthropic models.
 *
 * Default models:
 *   extraction: anthropic/claude-haiku-4-5-20251001 (fast, cheap, JSON-capable)
 *   vision:     anthropic/claude-sonnet-4-6          (PDF + image capable)
 */

import type { LLMAdapter } from './types';
import type { VisionAdapter } from './attachment';

type FetchLike = (url: string, init?: RequestInit) => Promise<Response>;

export interface OpenRouterAdapterOpts {
  /**
   * Your OpenRouter API key. Accepts a string or a provider function
   * so you can wire it to SettingsStore without capturing a stale value.
   */
  apiKey: string | (() => string | null);
  /**
   * Model for structured JSON extraction.
   * Default: anthropic/claude-haiku-4-5-20251001
   */
  extractionModel?: string;
  /**
   * Model for image/PDF OCR. Must support vision inputs.
   * Default: anthropic/claude-sonnet-4-6
   */
  visionModel?: string;
  /** HTTP fetch. Defaults to globalThis.fetch. */
  fetch?: FetchLike;
  /** Optional site URL sent in HTTP-Referer — improves OpenRouter analytics. */
  siteUrl?: string;
}

const OPENROUTER_BASE = 'https://openrouter.ai/api/v1';

const DEFAULT_EXTRACTION_MODEL = 'anthropic/claude-haiku-4-5-20251001';
const DEFAULT_VISION_MODEL = 'anthropic/claude-sonnet-4-6';

/** System prompt for JSON extraction. */
const EXTRACTION_SYSTEM = `You are a structured data extraction assistant.
Respond ONLY with a single JSON object matching the provided schema.
Include a "confidence" field (0.0–1.0) indicating how certain you are.
Do not include any prose or markdown outside the JSON object.`;

/** System prompt for document OCR / transcription. */
const OCR_SYSTEM = `You are transcribing a document attached to a business email.
Extract ALL visible text: names, addresses, phone numbers, dimensions, measurements,
dollar amounts, dates, job descriptions, item lists, and any handwritten notes.
Preserve numbers and figures exactly as they appear.
Return plain text only — no markdown, no commentary.`;

export class OpenRouterAdapter implements LLMAdapter, VisionAdapter {
  private readonly extractionModel: string;
  private readonly visionModel: string;
  private readonly fetchImpl: FetchLike;
  private readonly siteUrl: string;
  private readonly apiKeyProvider: () => string | null;

  constructor(opts: OpenRouterAdapterOpts) {
    this.extractionModel = opts.extractionModel ?? DEFAULT_EXTRACTION_MODEL;
    this.visionModel = opts.visionModel ?? DEFAULT_VISION_MODEL;
    this.fetchImpl = opts.fetch ?? ((url, init) => fetch(url, init));
    this.siteUrl = opts.siteUrl ?? 'https://semantos.app';
    const key = opts.apiKey;
    this.apiKeyProvider = typeof key === 'function' ? key : () => key;
  }

  // ── LLMAdapter ───────────────────────────────────────────────────────────

  async extract<T>(opts: { prompt: string; schema: object }): Promise<{
    payload: T;
    confidence: number;
    raw: string;
  }> {
    const key = this.resolveKey();
    const augmentedSchema = augmentWithConfidence(opts.schema);
    const userMessage = `${opts.prompt}\n\nRespond with a JSON object matching this schema:\n${JSON.stringify(augmentedSchema, null, 2)}`;

    const body = JSON.stringify({
      model: this.extractionModel,
      messages: [
        { role: 'system', content: EXTRACTION_SYSTEM },
        { role: 'user', content: userMessage },
      ],
      response_format: { type: 'json_object' },
      temperature: 0.1,
    });

    const res = await this.post('/chat/completions', body, key);
    const raw = extractContent(res);
    const { confidence, payload } = parseExtractionResponse<T>(raw);
    return { payload, confidence, raw };
  }

  // ── VisionAdapter ────────────────────────────────────────────────────────

  async describeImage(base64Data: string, mimeType: string): Promise<string> {
    const key = this.resolveKey();
    const isAnthropicModel = this.visionModel.startsWith('anthropic/');
    const contentBlock = buildVisionContentBlock(base64Data, mimeType, isAnthropicModel);

    const body = JSON.stringify({
      model: this.visionModel,
      messages: [
        { role: 'system', content: OCR_SYSTEM },
        {
          role: 'user',
          content: [
            contentBlock,
            { type: 'text', text: 'Transcribe all text from this document.' },
          ],
        },
      ],
      temperature: 0,
      max_tokens: 4096,
    });

    const res = await this.post('/chat/completions', body, key);
    return extractContent(res).trim();
  }

  // ── Internals ────────────────────────────────────────────────────────────

  private resolveKey(): string {
    const key = this.apiKeyProvider();
    if (!key) throw new OpenRouterError('OpenRouter API key is not configured', 0);
    return key;
  }

  private async post(path: string, body: string, apiKey: string): Promise<OpenRouterResponse> {
    const res = await this.fetchImpl(`${OPENROUTER_BASE}${path}`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'authorization': `Bearer ${apiKey}`,
        'http-referer': this.siteUrl,
        'x-title': 'semantos-legacy-ingest',
      },
      body,
    });

    if (res.status === 401) throw new OpenRouterError('Invalid or missing API key', 401);
    if (res.status === 429) {
      const ra = res.headers.get('retry-after');
      const retryAfter = ra ? parseInt(ra, 10) : 60;
      throw new OpenRouterRateLimited(retryAfter);
    }
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw new OpenRouterError(`HTTP ${res.status}: ${text.slice(0, 200)}`, res.status);
    }

    return res.json() as Promise<OpenRouterResponse>;
  }
}

// ── Content block builder ────────────────────────────────────────────────────

function buildVisionContentBlock(
  base64Data: string,
  mimeType: string,
  isAnthropicModel: boolean,
): object {
  if (mimeType === 'application/pdf' && isAnthropicModel) {
    // Anthropic's native document type: supports multi-page PDFs, no page limit
    // for Claude claude-sonnet-4-6 / Opus 4.7 (up to ~100 pages in practice).
    return {
      type: 'document',
      source: {
        type: 'base64',
        media_type: 'application/pdf',
        data: base64Data,
      },
    };
  }

  if (mimeType.startsWith('image/')) {
    // Standard OpenAI-compatible image_url format — works on all vision models.
    return {
      type: 'image_url',
      image_url: { url: `data:${mimeType};base64,${base64Data}` },
    };
  }

  // Unknown binary — send a best-effort data URI and let the model try.
  return {
    type: 'image_url',
    image_url: { url: `data:${mimeType};base64,${base64Data}` },
  };
}

// ── Response parsing ─────────────────────────────────────────────────────────

interface OpenRouterResponse {
  choices?: Array<{
    message?: { content?: string | null };
    finish_reason?: string;
  }>;
  error?: { message?: string; code?: number };
}

function extractContent(res: OpenRouterResponse): string {
  if (res.error) {
    throw new OpenRouterError(res.error.message ?? 'upstream model error', res.error.code ?? 0);
  }
  const content = res.choices?.[0]?.message?.content;
  if (typeof content !== 'string' || content.length === 0) {
    throw new OpenRouterError('model returned empty content', 0);
  }
  return content;
}

function parseExtractionResponse<T>(raw: string): { payload: T; confidence: number } {
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(raw);
  } catch {
    // Model returned prose wrapping JSON — try to find the first {...} block.
    const m = raw.match(/\{[\s\S]*\}/);
    if (!m) throw new OpenRouterError(`model did not return valid JSON: ${raw.slice(0, 200)}`, 0);
    parsed = JSON.parse(m[0]);
  }

  const confidence = typeof parsed.confidence === 'number'
    ? Math.min(1, Math.max(0, parsed.confidence))
    : 0.7; // conservative default when model omits the field

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

// ── Errors ───────────────────────────────────────────────────────────────────

export class OpenRouterError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
    this.name = 'OpenRouterError';
  }
}

export class OpenRouterRateLimited extends OpenRouterError {
  constructor(readonly retryAfterSeconds: number) {
    super(`OpenRouter rate limited — retry after ${retryAfterSeconds}s`, 429);
    this.name = 'OpenRouterRateLimited';
  }
}

```
