---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/tools/image-extract.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.562277+00:00
---

# cartridges/betterment/brain/tools/image-extract.ts

```ts
#!/usr/bin/env bun
/**
 * image-extract.ts — bun shell-out wrapper for the betterment OCR pipeline.
 *
 * The brain forks this process per `/api/v1/image-extract` request
 * (runtime/semantos-brain/src/image_extract_http.zig + image_extract_shell.zig).
 * It transcribes photo(s) of a handwritten release page via Claude vision and
 * returns the text structured as chronological `ReleaseTurn`s for the
 * betterment.practice.release cell.
 *
 * Wire shape:
 *     bun cartridges/betterment/brain/tools/image-extract.ts \
 *         --images   /tmp/img-NNN-1.jpg,/tmp/img-NNN-2.jpg \
 *         --metadata /tmp/meta-NNN.json
 *
 *   stdin:  unused
 *   stdout: ExtractResult JSON (see below) on exit 0 when the pipeline ran.
 *   stderr: diagnostics. Non-zero exit = fatal infra error (missing key,
 *           unreadable file, upstream model failure) → brain returns 422.
 *
 * Design mirrors cartridges/betterment/brain/src/sweep_runner.ts: a pure,
 * injectable core (`extractFromImages`) that tests drive with a fake
 * VisionClient, plus an `if (import.meta.main)` entry that builds the real
 * Anthropic client. The vision client returns PLAIN transcribed text per page;
 * turn segmentation is done deterministically in TS (paragraph splitting), so
 * it is fully unit-testable without the model.
 *
 * Reference for the Anthropic request shape + fence-stripping:
 *   runtime/legacy-ingest/src/extractor/anthropic.ts (describeImage).
 */

import { readFileSync } from 'node:fs';

// ─── Output shape (mirrors packages/betterment_experience ReleaseTurn) ──────

export interface ExtractedTurn {
  readonly index: number;
  readonly speaker: 'self';
  readonly text: string;
  /** Which source page this turn came from, e.g. "page:1". */
  readonly sourcePageRef: string;
  /** Optional model self-rated transcription confidence 0..1. */
  readonly confidence?: number;
}

export interface ExtractResult {
  readonly turns: readonly ExtractedTurn[];
  /** Canonical joined transcript across all pages. */
  readonly rawText: string;
  /** Number of source images transcribed. */
  readonly pageCount: number;
}

export interface ImageInput {
  /** Base64-encoded image bytes. */
  readonly base64: string;
  /** MIME type, e.g. "image/jpeg". */
  readonly mediaType: string;
}

/**
 * Injectable vision client. The real implementation calls Claude; tests pass a
 * fake that returns canned transcription text.
 */
export interface VisionClient {
  /** Transcribe one image to plain verbatim text. */
  transcribe(base64: string, mediaType: string): Promise<string>;
}

// ─── Pure core — segmentation + assembly (no I/O, no model) ─────────────────

/**
 * Split one page of transcribed text into chronological turns. A "turn" is a
 * paragraph: a run of non-empty lines separated from the next by a blank line.
 * A page with no blank lines yields a single turn. Whitespace-only pages yield
 * no turns.
 */
export function segmentIntoTurns(pageText: string): string[] {
  return pageText
    .replace(/\r\n/g, '\n')
    .split(/\n[ \t]*\n+/) // blank-line paragraph breaks
    .map((p) => p.trim())
    .filter((p) => p.length > 0);
}

/**
 * Transcribe each image and assemble the chronological turns + joined rawText.
 * Turn `index` is strictly increasing across ALL pages (the release validator
 * requires this); each turn records its source page as "page:N" (1-based).
 */
export async function extractFromImages(
  client: VisionClient,
  images: readonly ImageInput[],
): Promise<ExtractResult> {
  const turns: ExtractedTurn[] = [];
  const pageTexts: string[] = [];

  for (let p = 0; p < images.length; p++) {
    const img = images[p]!;
    const pageText = (await client.transcribe(img.base64, img.mediaType)).trim();
    pageTexts.push(pageText);
    const sourcePageRef = `page:${p + 1}`;
    for (const para of segmentIntoTurns(pageText)) {
      turns.push({
        index: turns.length,
        speaker: 'self',
        text: para,
        sourcePageRef,
      });
    }
  }

  return {
    turns,
    rawText: pageTexts.join('\n\n').trim(),
    pageCount: images.length,
  };
}

// ─── Anthropic vision client (real implementation) ──────────────────────────

const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
const ANTHROPIC_VERSION = '2023-06-01';
const VISION_MODEL = 'claude-sonnet-4-6';
const MAX_TOKENS = 8192;

/** Handwriting-OCR system prompt — verbatim transcription, paragraph-preserving. */
const OCR_SYSTEM = `You are transcribing a photo of a handwritten personal journal /
morning-pages page. Transcribe ALL visible handwritten text VERBATIM — preserve the
writer's exact words, spelling, and line/paragraph structure. Separate distinct
paragraphs or thoughts with a blank line. Do not summarise, correct, interpret, or add
commentary. If a word is illegible, transcribe your best guess and mark it [?]. Return
PLAIN TEXT ONLY — no markdown, no code fences, no preamble.`;

type FetchLike = (url: string, init: RequestInit) => Promise<Response>;

export class AnthropicVisionClient implements VisionClient {
  private readonly apiKey: string;
  private readonly model: string;
  private readonly fetchImpl: FetchLike;

  constructor(opts: { apiKey: string; model?: string; fetch?: FetchLike }) {
    this.apiKey = opts.apiKey;
    this.model = opts.model ?? VISION_MODEL;
    this.fetchImpl = opts.fetch ?? ((url, init) => fetch(url, init));
  }

  async transcribe(base64: string, mediaType: string): Promise<string> {
    const body = JSON.stringify({
      model: this.model,
      max_tokens: MAX_TOKENS,
      system: OCR_SYSTEM,
      temperature: 0,
      messages: [
        {
          role: 'user',
          content: [
            { type: 'image', source: { type: 'base64', media_type: mediaType, data: base64 } },
            { type: 'text', text: 'Transcribe all handwritten text from this page.' },
          ],
        },
      ],
    });

    const res = await this.fetchImpl(ANTHROPIC_URL, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': this.apiKey,
        'anthropic-version': ANTHROPIC_VERSION,
      },
      body,
    });

    if (!res.ok) {
      const detail = await res.text().catch(() => '');
      throw new Error(`image-extract: anthropic ${res.status}: ${detail.slice(0, 200)}`);
    }

    const json = (await res.json()) as { content?: Array<{ type: string; text?: string }> };
    const text = (json.content ?? [])
      .filter((b) => b.type === 'text' && typeof b.text === 'string')
      .map((b) => b.text as string)
      .join('');
    return stripCodeFences(text).trim();
  }
}

/** Strip a leading/trailing markdown code fence if the model wraps its reply. */
export function stripCodeFences(s: string): string {
  const trimmed = s.trim();
  if (!trimmed.startsWith('```')) return trimmed;
  return trimmed
    .replace(/^```[a-zA-Z0-9]*\n?/, '')
    .replace(/\n?```$/, '')
    .trim();
}

// ─── CLI entry ──────────────────────────────────────────────────────────────

interface CliArgs {
  imagePaths: string[];
  metadataPath: string | null;
  /** Optional model override (BYOK model selection); null → AnthropicVisionClient default. */
  model: string | null;
}

export function parseArgs(argv: ReadonlyArray<string>): CliArgs {
  let imagePaths: string[] = [];
  let metadataPath: string | null = null;
  let model: string | null = null;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--images' && i + 1 < argv.length) {
      imagePaths = argv[++i]!.split(',').map((s) => s.trim()).filter((s) => s.length > 0);
    } else if (a === '--metadata' && i + 1 < argv.length) {
      metadataPath = argv[++i]!;
    } else if (a === '--model' && i + 1 < argv.length) {
      const m = argv[++i]!.trim();
      model = m.length > 0 ? m : null;
    }
  }
  if (imagePaths.length === 0) {
    throw new Error('image-extract: missing --images');
  }
  return { imagePaths, metadataPath, model };
}

/** Infer the image MIME type from a file path extension. */
export function mediaTypeForPath(path: string): string {
  const ext = path.slice(path.lastIndexOf('.') + 1).toLowerCase();
  switch (ext) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    case 'jpg':
    case 'jpeg':
    default:
      return 'image/jpeg';
  }
}

async function main(): Promise<number> {
  let args: CliArgs;
  try {
    args = parseArgs(process.argv.slice(2));
  } catch (e) {
    process.stderr.write(`${(e as Error).message}\n`);
    return 64;
  }

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey || apiKey.length === 0) {
    process.stderr.write('image-extract: ANTHROPIC_API_KEY not set in environment\n');
    return 69;
  }

  let images: ImageInput[];
  try {
    images = args.imagePaths.map((p) => ({
      base64: readFileSync(p).toString('base64'),
      mediaType: mediaTypeForPath(p),
    }));
  } catch (e) {
    process.stderr.write(`image-extract: failed to read image files: ${(e as Error).message}\n`);
    return 66;
  }

  const client = new AnthropicVisionClient({
    apiKey,
    ...(args.model ? { model: args.model } : {}),
  });
  try {
    const result = await extractFromImages(client, images);
    process.stdout.write(JSON.stringify(result));
    return 0;
  } catch (e) {
    process.stderr.write(`image-extract: extraction failed: ${(e as Error).message}\n`);
    return 70;
  }
}

if (import.meta.main) {
  process.exit(await main());
}

```
