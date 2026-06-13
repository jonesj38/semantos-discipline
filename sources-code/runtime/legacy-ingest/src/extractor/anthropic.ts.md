---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/extractor/anthropic.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.157400+00:00
---

# runtime/legacy-ingest/src/extractor/anthropic.ts

```ts
/**
 * Anthropic adapter — LI3 production LLM client (BYOK direct).
 *
 * Implements both LLMAdapter (structured JSON extraction) and VisionAdapter
 * (OCR of images and PDF documents) by talking directly to the Anthropic
 * Messages API (https://api.anthropic.com/v1/messages). This drops the
 * OpenRouter middleman for the high-end vision/extraction path so an
 * operator with an Anthropic API key can use Claude directly.
 *
 * Text extraction:
 *   POST /v1/messages with a single user message. Anthropic's Messages
 *   API has no `response_format: json_object` toggle, so we constrain
 *   the output via prompt engineering: we instruct the model to reply
 *   with ONLY a JSON object matching the augmented schema, then strip
 *   any code fences the model may wrap around its response.
 *
 *   The caller's schema is augmented with a `confidence` field so the
 *   model self-rates its certainty; we strip the field before returning
 *   the typed payload (mirrors OpenRouterAdapter exactly).
 *
 * Vision / OCR:
 *   For images (image/*): native `image` content block with base64
 *   source. For PDFs (application/pdf): native `document` content block
 *   with base64 source — supports multi-page PDFs up to ~100 pages.
 *
 * Default models:
 *   extraction: claude-haiku-4-5-20251001 (fast, cheap)
 *   vision:     claude-sonnet-4-6          (PDF + image capable)
 *
 * Error taxonomy mirrors OpenRouterAdapter — swap "OpenRouter" for
 * "Anthropic" — so caller try/catch patterns translate cleanly. Plus
 * two Anthropic-specific errors: AnthropicOverloaded (529) and
 * AnthropicTruncated (stop_reason === 'max_tokens').
 */

import sharp from 'sharp';

import type { LLMAdapter } from './types';
import type { VisionAdapter } from './attachment';

type FetchLike = (url: string, init?: RequestInit) => Promise<Response>;

/**
 * Minimal interface for the sharp pipeline chain used by `downsizeForAnthropic`.
 * Matches the real sharp API (subset). Exposed so tests can inject a fake.
 */
export interface SharpPipeline {
  resize(width: number, height: number, opts?: object): SharpPipeline;
  jpeg(opts?: object): SharpPipeline;
  toBuffer(): Promise<Buffer>;
}

/** Creates a SharpPipeline from a raw Buffer. Defaults to real `sharp()`. */
export type SharpFactory = (input: Buffer) => SharpPipeline;

export interface AnthropicAdapterOpts {
  /**
   * Anthropic API key. String or provider function (so you can wire to a
   * SettingsStore without capturing a stale value).
   */
  apiKey: string | (() => string | null);
  /** Extraction model (JSON output). Default: claude-haiku-4-5-20251001 */
  extractionModel?: string;
  /** Vision model (PDF/image OCR). Default: claude-sonnet-4-6 */
  visionModel?: string;
  /** HTTP fetch. Defaults to globalThis.fetch. */
  fetch?: FetchLike;
  /** Anthropic API version header. Default: "2023-06-01" */
  apiVersion?: string;
  /** Request timeout in ms. Default: 90000 */
  timeoutMs?: number;
  /**
   * Override the sharp factory used by the iterative downsampler. Defaults to
   * the real `sharp` package. Inject a stub in tests to control resize output
   * without touching the native binary.
   */
  sharpFactory?: SharpFactory;
}

const ANTHROPIC_BASE = 'https://api.anthropic.com';
const ANTHROPIC_MESSAGES_PATH = '/v1/messages';

const DEFAULT_EXTRACTION_MODEL = 'claude-haiku-4-5-20251001';
const DEFAULT_VISION_MODEL = 'claude-sonnet-4-6';
const DEFAULT_API_VERSION = '2023-06-01';
const DEFAULT_TIMEOUT_MS = 90_000;
// 2026-05-07: bumped from 4096 → 8192 after operator's overnight gmail
// ingest hit truncation mid-JSON on long quote-PDF responses (model
// stopped emitting before closing `}` even though stop_reason was not
// `max_tokens`).  Most Claude models support 8K-32K output; 8K is a
// safe pragmatic default for structured extraction whose JSON output is
// typically <2K but spikes higher when the model writes a long summary
// + multiple cust/site/contact fields for forwarded property-management
// bundles.
// 2026-05-19: bumped 8192 → 16000 after operator's full-history gmail
// re-extract hit ~59/67 AnthropicParseError on long property-management
// job-sheet bundles — the structured JSON for multi-page work orders
// (summary + WO# + services[] + multi-contact + site) routinely exceeds
// 8K and truncated mid-object ending in a `}` (slipping past the
// truncation guard into a hard parse error).
const DEFAULT_MAX_TOKENS_EXTRACTION = 16000;
// Vision OCR of multi-page PDF job sheets likewise overran 4K; 8K keeps
// the full transcribed sheet so the extraction step sees all the work
// detail.
const DEFAULT_MAX_TOKENS_VISION = 8192;

/**
 * Anthropic's hard limit for base64-encoded image data is 5 MB (5 242 880
 * bytes). Base64 inflates raw bytes by 4/3, so the source image must be
 * < ~3.75 MB. We target 4 MB of base64 (giving ~1 MB headroom) so we don't
 * walk right up to Anthropic's cliff edge.
 *
 * When an image exceeds this limit, `describeImage` calls `downsizeForAnthropic`
 * which iteratively resizes the image using sharp until it fits. Only if the
 * image still exceeds the limit after all 4 downsize attempts is
 * `AnthropicImageTooLarge` thrown, allowing the llm-router to fall through to
 * the next configured vision backend.
 *
 * Implemented in PR #398; downsizing happens in describeImage's call to
 * downsizeForAnthropic().
 */
const ANTHROPIC_IMAGE_B64_LIMIT = 4 * 1024 * 1024; // 4 MB of base64 chars

/** System prompt for JSON extraction. */
const EXTRACTION_SYSTEM = `You are a structured data extraction assistant.
Respond with ONLY a single JSON object matching the provided schema.
Include a "confidence" field (0.0–1.0) indicating how certain you are.
No prose, no markdown, no code fences — just the JSON object.`;

/** System prompt for document OCR / transcription. */
const OCR_SYSTEM = `You are transcribing a document attached to a business email.
Extract ALL visible text: names, addresses, phone numbers, dimensions, measurements,
dollar amounts, dates, job descriptions, item lists, and any handwritten notes.
Preserve numbers and figures exactly as they appear.
Return plain text only — no markdown, no commentary.`;

export class AnthropicAdapter implements LLMAdapter, VisionAdapter {
  private readonly extractionModel: string;
  private readonly visionModel: string;
  private readonly fetchImpl: FetchLike;
  private readonly apiVersion: string;
  private readonly timeoutMs: number;
  private readonly apiKeyProvider: () => string | null;
  private readonly sharpFactory: SharpFactory;

  constructor(opts: AnthropicAdapterOpts) {
    this.extractionModel = opts.extractionModel ?? DEFAULT_EXTRACTION_MODEL;
    this.visionModel = opts.visionModel ?? DEFAULT_VISION_MODEL;
    this.fetchImpl = opts.fetch ?? ((url, init) => fetch(url, init));
    this.apiVersion = opts.apiVersion ?? DEFAULT_API_VERSION;
    this.timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    this.sharpFactory = opts.sharpFactory ?? ((buf) => sharp(buf) as unknown as SharpPipeline);
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
      max_tokens: DEFAULT_MAX_TOKENS_EXTRACTION,
      system: EXTRACTION_SYSTEM,
      messages: [
        {
          role: 'user',
          content: [{ type: 'text', text: userMessage }],
        },
      ],
      temperature: 0.1,
    });

    const res = await this.post(body, key);
    const raw = extractContent(res);
    const { confidence, payload } = parseExtractionResponse<T>(raw);
    return { payload, confidence, raw };
  }

  // ── VisionAdapter ────────────────────────────────────────────────────────

  async describeImage(base64Data: string, mimeType: string): Promise<string> {
    // For images that exceed the 4 MB base64 limit, attempt iterative
    // downsizing with sharp before making the API call. If the image still
    // exceeds the limit after all 4 attempts, AnthropicImageTooLarge is
    // thrown and the llm-router falls through to the next backend.
    // PDFs are not resizable — only attempt downsizing for image/* types.
    let effectiveBase64 = base64Data;
    let effectiveMimeType = mimeType;

    if (mimeType !== 'application/pdf' && base64Data.length > ANTHROPIC_IMAGE_B64_LIMIT) {
      const result = await downsizeForAnthropic(base64Data, mimeType, this.sharpFactory);
      effectiveBase64 = result.base64;
      effectiveMimeType = result.mimeType;
    }

    const key = this.resolveKey();
    const contentBlock = buildVisionContentBlock(effectiveBase64, effectiveMimeType);

    const body = JSON.stringify({
      model: this.visionModel,
      max_tokens: DEFAULT_MAX_TOKENS_VISION,
      system: OCR_SYSTEM,
      messages: [
        {
          role: 'user',
          content: [
            contentBlock,
            { type: 'text', text: 'Transcribe all text from this document.' },
          ],
        },
      ],
      temperature: 0,
    });

    const res = await this.post(body, key);
    return extractContent(res).trim();
  }

  // ── Internals ────────────────────────────────────────────────────────────

  private resolveKey(): string {
    const key = this.apiKeyProvider();
    if (!key) {
      throw new AnthropicAuthError(
        'Anthropic API key is not configured (ANTHROPIC_API_KEY not set)',
      );
    }
    return key;
  }

  private async post(body: string, apiKey: string): Promise<AnthropicMessagesResponse> {
    const url = `${ANTHROPIC_BASE}${ANTHROPIC_MESSAGES_PATH}`;
    let res: Response;
    try {
      res = await withTimeout(
        this.fetchImpl(url, {
          method: 'POST',
          headers: {
            'content-type': 'application/json',
            'x-api-key': apiKey,
            'anthropic-version': this.apiVersion,
          },
          body,
        }),
        this.timeoutMs,
      );
    } catch (err) {
      if (err instanceof AnthropicError) throw err;
      const msg = err instanceof Error ? err.message : String(err);
      throw new AnthropicConnectionError(`network error contacting Anthropic: ${msg}`);
    }

    if (res.status === 401) {
      throw new AnthropicAuthError('Invalid or missing Anthropic API key');
    }
    if (res.status === 429) {
      const ra = res.headers.get('retry-after');
      const retryAfter = ra ? parseInt(ra, 10) : 60;
      throw new AnthropicRateLimited(retryAfter);
    }
    if (res.status === 529) {
      throw new AnthropicOverloaded();
    }
    if (!res.ok) {
      const text = await withTimeout(res.text(), this.timeoutMs).catch(() => '');
      throw new AnthropicError(
        `Anthropic HTTP ${res.status}: ${text.slice(0, 200)}`,
        res.status,
      );
    }

    // The body read must be bounded too. `withTimeout` above wraps only the
    // fetch() call, which resolves when HEADERS arrive — a stalled response BODY
    // (res.json hanging in poll() forever) is what froze the bulk backfill with
    // no timeout error. Wrap the body read in the same deadline.
    return await withTimeout(
      res.json() as Promise<AnthropicMessagesResponse>,
      this.timeoutMs,
    );
  }
}

// ── Image downsampler ─────────────────────────────────────────────────────────

/**
 * Downsize steps: each entry is [longestEdgePx, jpegQuality].
 * We try these in order, stopping as soon as the re-encoded base64 fits
 * within ANTHROPIC_IMAGE_B64_LIMIT. Four attempts is the hard cap.
 */
const DOWNSIZE_STEPS: Array<[number, number]> = [
  [2400, 85],
  [1800, 80],
  [1200, 75],
  [800, 70],
];

interface DownsizeResult {
  base64: string;
  mimeType: string;
  downsized: boolean;
}

/**
 * Iteratively resize an image using sharp until its base64 representation fits
 * within `ANTHROPIC_IMAGE_B64_LIMIT`. Output is always JPEG regardless of input
 * format — operator's images are dominated by photos and JPEG is the right output.
 *
 * Throws `AnthropicImageTooLarge` if the image still exceeds the limit after all
 * 4 downsize attempts. The caller should let this propagate to the llm-router.
 */
async function downsizeForAnthropic(
  base64Data: string,
  _mimeType: string,
  sharpFactory: SharpFactory,
): Promise<DownsizeResult> {
  // Already fits — return as-is.
  if (base64Data.length <= ANTHROPIC_IMAGE_B64_LIMIT) {
    return { base64: base64Data, mimeType: _mimeType, downsized: false };
  }

  const inputBuffer = Buffer.from(base64Data, 'base64');

  for (let attempt = 0; attempt < DOWNSIZE_STEPS.length; attempt++) {
    const [longestEdge, quality] = DOWNSIZE_STEPS[attempt];

    const resized = await sharpFactory(inputBuffer)
      .resize(longestEdge, longestEdge, { fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality })
      .toBuffer();

    const resultBase64 = resized.toString('base64');
    const fromMb = (base64Data.length / (1024 * 1024)).toFixed(1);
    const toMb = (resultBase64.length / (1024 * 1024)).toFixed(1);

    // eslint-disable-next-line no-console
    console.warn(
      `[vision-anthropic] downsized image from ${fromMb}MB to ${toMb}MB (attempt: ${attempt + 1}/${DOWNSIZE_STEPS.length})`,
    );

    if (resultBase64.length <= ANTHROPIC_IMAGE_B64_LIMIT) {
      return { base64: resultBase64, mimeType: 'image/jpeg', downsized: true };
    }
  }

  // All 4 attempts failed — let the router fall through to the next backend.
  throw new AnthropicImageTooLarge(base64Data.length);
}

// ── Content block builder ────────────────────────────────────────────────────

function buildVisionContentBlock(base64Data: string, mimeType: string): object {
  if (mimeType === 'application/pdf') {
    // Anthropic native document block. Supports multi-page PDFs up to
    // ~100 pages on Sonnet/Opus class models.
    return {
      type: 'document',
      source: {
        type: 'base64',
        media_type: 'application/pdf',
        data: base64Data,
      },
    };
  }

  // Anthropic native image block (image/jpeg, image/png, image/gif, image/webp).
  return {
    type: 'image',
    source: {
      type: 'base64',
      media_type: mimeType,
      data: base64Data,
    },
  };
}

// ── Response parsing ─────────────────────────────────────────────────────────

interface AnthropicContentBlock {
  type: string;
  text?: string;
}

interface AnthropicMessagesResponse {
  content?: AnthropicContentBlock[];
  stop_reason?: string;
  type?: string;
  error?: { type?: string; message?: string };
}

function extractContent(res: AnthropicMessagesResponse): string {
  if (res.error) {
    throw new AnthropicError(res.error.message ?? 'upstream model error', 0);
  }
  if (res.stop_reason === 'max_tokens') {
    throw new AnthropicTruncated();
  }
  const blocks = Array.isArray(res.content) ? res.content : [];
  // Concatenate all text blocks (Anthropic typically returns a single
  // text block for non-streaming non-tool responses).
  const text = blocks
    .filter((b) => b.type === 'text' && typeof b.text === 'string')
    .map((b) => b.text as string)
    .join('');
  if (text.length === 0) {
    throw new AnthropicError('Anthropic returned empty content', 0);
  }
  return text;
}

function parseExtractionResponse<T>(raw: string): { payload: T; confidence: number } {
  const cleaned = stripCodeFences(raw);
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(cleaned);
  } catch {
    // Model returned prose wrapping JSON, or a leading ```json fence we
    // couldn't fully strip — extract the first brace-balanced object
    // (string/escape aware) rather than a greedy `\{[\s\S]*\}` which
    // over-grabs trailing junk or under-matches when a `}` appears
    // inside a string. This is what unblocked the operator's full
    // gmail re-extract (2026-05-19): the model emits good JSON wrapped
    // in ```json fences; balanced extraction recovers it cleanly.
    const balanced = extractFirstJsonObject(cleaned);
    if (balanced) {
      try {
        const p = JSON.parse(balanced);
        const confidence0 =
          typeof p.confidence === 'number'
            ? Math.min(1, Math.max(0, p.confidence))
            : 0.7;
        const { confidence: _d0, ...payload0 } = p;
        void _d0;
        return { payload: payload0 as T, confidence: confidence0 };
      } catch {
        /* fall through to the legacy regex path below */
      }
    }
    // Model returned prose wrapping JSON — try to find the first {...} block.
    const m = cleaned.match(/\{[\s\S]*\}/);
    if (!m) {
      // 2026-05-07: distinguish "truncated mid-JSON" from "model emitted
      // prose with no JSON at all".  If the cleaned text starts with `{`
      // but does not contain a closing `}`, the response was cut off
      // before completion (Anthropic sometimes truncates without setting
      // stop_reason='max_tokens').  Surface this as AnthropicTruncated
      // so the LLM router falls through to the next backend silently
      // rather than logging a noisy AnthropicParseError with the
      // truncated payload — operator's overnight gmail ingest produced
      // dozens of these for long quote-PDF extractions.
      if (looksLikeTruncatedJson(cleaned)) {
        throw new AnthropicTruncated();
      }
      throw new AnthropicParseError(
        `model did not return valid JSON: ${raw.slice(0, 200)}`,
      );
    }
    try {
      parsed = JSON.parse(m[0]);
    } catch {
      // Same truncation check on the matched substring — if the regex
      // grabbed an opening `{` but no real closer, treat as truncated.
      if (looksLikeTruncatedJson(m[0])) {
        throw new AnthropicTruncated();
      }
      throw new AnthropicParseError(
        `model did not return valid JSON: ${raw.slice(0, 200)}`,
      );
    }
  }

  const confidence =
    typeof parsed.confidence === 'number'
      ? Math.min(1, Math.max(0, parsed.confidence))
      : 0.7; // conservative default when model omits the field

  const { confidence: _dropped, ...payload } = parsed;
  void _dropped;
  return { payload: payload as T, confidence };
}

/**
 * Heuristic: does this look like the model's JSON output got cut off
 * before the closing brace?  Used to surface truncations that Anthropic
 * doesn't flag with stop_reason='max_tokens' (we've seen long quote-PDF
 * extractions stop mid-string field even when within token budget).
 *
 * Conservative: requires `{` near the start AND no balanced closing `}`
 * AND the trailing characters don't look like a complete JSON value.
 */
function looksLikeTruncatedJson(s: string): boolean {
  const trimmed = s.trim();
  // Two truncation patterns:
  //   1. Bare JSON: starts with `{`, ends without matching `}`
  //   2. Prose-wrapped (or fence-prefixed): contains `{` SOMEWHERE but
  //      the trailing characters are not `}` — model began the JSON
  //      block then got cut off
  // Both reduce to: if there is an opening `{` but the trimmed text
  // doesn't end with `}` (after stripping trailing whitespace/commas),
  // treat as truncated.
  if (!trimmed.includes('{')) return false;
  const tail = trimmed.replace(/[\s,]+$/, '');
  return !tail.endsWith('}');
}

/**
 * Strip ```json ... ``` or ``` ... ``` fences that Sonnet sometimes wraps
 * around its JSON output despite the system-prompt instruction.
 */
function stripCodeFences(raw: string): string {
  const trimmed = raw.trim();
  // Preferred: a complete ```<lang?>\n ... \n``` block.
  const fence = /^```(?:json|JSON)?\s*\n?([\s\S]*?)\n?```$/;
  const m = trimmed.match(fence);
  if (m) return m[1].trim();
  // Degraded: a LEADING fence whose closing ``` is missing (the model's
  // JSON was truncated before it could close the fence) or has trailing
  // prose after the close. Strip the opening fence line and any trailing
  // fence independently so the brace-balanced extractor downstream can
  // still recover the object. This is the common shape behind the
  // operator's 2026-05-19 AnthropicParseError storm.
  if (/^```/.test(trimmed)) {
    return trimmed
      .replace(/^```(?:json|JSON)?[ \t]*\r?\n?/, '')
      .replace(/\r?\n?```[\s\S]*$/, '')
      .trim();
  }
  return trimmed;
}

/**
 * Extract the first brace-balanced JSON object from a string, ignoring
 * braces that appear inside JSON string literals (escape-aware). Returns
 * the object substring, or null if no balanced object is present.
 *
 * More robust than `/\{[\s\S]*\}/`: that greedy regex grabs from the
 * first `{` to the LAST `}` anywhere in the text (swallowing trailing
 * prose / a second object), and a naive non-greedy variant stops at the
 * first `}` even when it's inside a string value. Depth counting with
 * string-state tracking returns exactly the first complete object.
 */
function extractFirstJsonObject(s: string): string | null {
  const start = s.indexOf('{');
  if (start < 0) return null;
  let depth = 0;
  let inStr = false;
  let esc = false;
  for (let i = start; i < s.length; i++) {
    const c = s[i];
    if (inStr) {
      if (esc) esc = false;
      else if (c === '\\') esc = true;
      else if (c === '"') inStr = false;
      continue;
    }
    if (c === '"') inStr = true;
    else if (c === '{') depth++;
    else if (c === '}') {
      depth--;
      if (depth === 0) return s.slice(start, i + 1);
    }
  }
  return null;
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
        description:
          'How confident you are in this extraction (0=guessing, 1=certain).',
      },
    },
    required: required.includes('confidence')
      ? required
      : [...required, 'confidence'],
  };
}

// ── Timeout helper ───────────────────────────────────────────────────────────

function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<T>((_resolve, reject) => {
    timer = setTimeout(() => reject(new AnthropicTimeout(ms)), ms);
  });
  return Promise.race([p, timeout]).finally(() => {
    if (timer !== undefined) clearTimeout(timer);
  }) as Promise<T>;
}

// ── Errors ───────────────────────────────────────────────────────────────────

export class AnthropicError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
    this.name = 'AnthropicError';
  }
}

export class AnthropicAuthError extends AnthropicError {
  constructor(message: string) {
    super(message, 401);
    this.name = 'AnthropicAuthError';
  }
}

export class AnthropicRateLimited extends AnthropicError {
  constructor(readonly retryAfterSeconds: number) {
    super(`Anthropic rate limited — retry after ${retryAfterSeconds}s`, 429);
    this.name = 'AnthropicRateLimited';
  }
}

export class AnthropicOverloaded extends AnthropicError {
  constructor() {
    super('Anthropic API overloaded — try again shortly', 529);
    this.name = 'AnthropicOverloaded';
  }
}

export class AnthropicConnectionError extends AnthropicError {
  constructor(message: string) {
    super(message, 0);
    this.name = 'AnthropicConnectionError';
  }
}

export class AnthropicParseError extends AnthropicError {
  constructor(message: string) {
    super(message, 0);
    this.name = 'AnthropicParseError';
  }
}

export class AnthropicTimeout extends AnthropicError {
  constructor(readonly timeoutMs: number) {
    super(`Anthropic request timed out after ${timeoutMs}ms`, 0);
    this.name = 'AnthropicTimeout';
  }
}

export class AnthropicTruncated extends AnthropicError {
  constructor() {
    super('Anthropic response truncated (stop_reason=max_tokens)', 0);
    this.name = 'AnthropicTruncated';
  }
}

/**
 * Thrown by `describeImage` when the base64-encoded image payload still exceeds
 * `ANTHROPIC_IMAGE_B64_LIMIT` (4 MB) after all 4 iterative downsize attempts.
 * The llm-router catches this and falls through to the next configured backend.
 */
export class AnthropicImageTooLarge extends AnthropicError {
  constructor(readonly base64Length: number) {
    const mb = (base64Length / (1024 * 1024)).toFixed(1);
    super(
      `image base64 payload ${mb} MB exceeds the ${ANTHROPIC_IMAGE_B64_LIMIT / (1024 * 1024)} MB pre-flight limit`,
      0,
    );
    this.name = 'AnthropicImageTooLarge';
  }
}

```
