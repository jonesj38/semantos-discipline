---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/turn-extractor.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.519876+00:00
---

# cartridges/oddjobz/brain/src/conversation/turn-extractor.ts

```ts
/**
 * I-14 — LLM turn extractor.
 *
 * Closes the raw-text → TaggedFact[] seam: takes a customer message,
 * calls the Anthropic API with the extraction prompt, parses the JSON
 * response into { extraction: MessageExtraction, taggedFacts: TaggedFact[] }.
 *
 * The caller then passes these to processConversationTurn() to get an Intent:
 *
 *   const { extraction, taggedFacts } = await extractConversationTurn(...)
 *   const { state }  = mergeExtraction(currentState, extraction)
 *   const { reducerResult } = await processConversationTurn({ accumulatedState: state, taggedFacts, ... })
 *
 * Model: claude-haiku-4-5 (fast, cheap, sufficient for structured extraction).
 * The extraction prompt is already operator-tuned across OJT Sprints 1–3;
 * this module only adds the API call layer.
 *
 * Output parsing: strips markdown fences then extracts the first balanced
 * JSON object — guards against the model emitting continuation text after
 * the closing brace (same class of bug as the Llama JSON fix in SirExtractor).
 */

import Anthropic from '@anthropic-ai/sdk';
import {
  buildExtractionPrompt,
  type ExtractionPromptState,
} from '../prompts/extraction-prompt.js';
import type { AccumulatedJobState, MessageExtraction } from './accumulated-job-state.js';
import type { TaggedFact } from '@semantos/intent/reducer/types';

// ── Public types ──────────────────────────────────────────────────────────────

export interface TurnExtractionResult {
  extraction: MessageExtraction;
  taggedFacts: ReadonlyArray<TaggedFact>;
  /** Raw JSON string returned by the model — retained for debugging. */
  rawJson: string;
}

export interface TurnExtractorOptions {
  /** Defaults to process.env.ANTHROPIC_API_KEY. */
  apiKey?: string;
  /** Defaults to claude-haiku-4-5. */
  model?: string;
  /** Inject a pre-built client (for testing / DI). */
  client?: Anthropic;
}

// ── Implementation ────────────────────────────────────────────────────────────

const DEFAULT_MODEL = 'claude-haiku-4-5';
const MAX_TOKENS = 2048;

/**
 * Extract structured fields + tagged facts from one customer message.
 *
 * @param input  - current state, the customer message, optional summary.
 * @param options - optional API key / model / injected client.
 */
export async function extractConversationTurn(
  input: {
    currentState: AccumulatedJobState;
    latestMessage: string;
    conversationSummary?: string;
  },
  options: TurnExtractorOptions = {},
): Promise<TurnExtractionResult> {
  const client =
    options.client ??
    new Anthropic({ apiKey: options.apiKey ?? process.env.ANTHROPIC_API_KEY });
  const model = options.model ?? DEFAULT_MODEL;

  const prompt = buildExtractionPrompt({
    currentState: input.currentState as unknown as ExtractionPromptState,
    latestMessage: input.latestMessage,
    conversationSummary: input.conversationSummary ?? '',
  });

  const response = await client.messages.create({
    model,
    max_tokens: MAX_TOKENS,
    messages: [{ role: 'user', content: prompt }],
  });

  const textBlock = response.content.find((b) => b.type === 'text');
  const raw = textBlock?.type === 'text' ? textBlock.text : '';

  return parseExtractionResponse(raw);
}

// ── Parsing ───────────────────────────────────────────────────────────────────

/** Exported for unit testing without an API call. */
export function parseExtractionResponse(raw: string): TurnExtractionResult {
  const jsonStr = extractFirstJsonObject(raw.trim());

  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(jsonStr) as Record<string, unknown>;
  } catch {
    // Return empty extraction if JSON is unparseable — don't crash the turn.
    return { extraction: {}, taggedFacts: [], rawJson: raw };
  }

  const { taggedFacts: rawFacts, ...rest } = parsed;
  const extraction = rest as MessageExtraction;
  const taggedFacts = sanitiseTaggedFacts(rawFacts);

  return { extraction, taggedFacts, rawJson: jsonStr };
}

/**
 * Strip markdown fences (```json ... ```) and extract the first
 * balanced JSON object from the text.  Handles trailing garbage
 * (continuation text after the closing brace) the same way
 * SirExtractor._extractFirstJsonObject does on the Dart side.
 */
function extractFirstJsonObject(text: string): string {
  // Strip optional markdown fence.
  const stripped = text
    .replace(/^```json\s*/i, '')
    .replace(/```\s*$/, '')
    .trim();

  let depth = 0;
  let start = -1;
  for (let i = 0; i < stripped.length; i++) {
    const ch = stripped[i];
    if (ch === '{') {
      if (depth === 0) start = i;
      depth++;
    } else if (ch === '}') {
      depth--;
      if (depth === 0 && start !== -1) {
        return stripped.slice(start, i + 1);
      }
    }
  }
  // Fallback — return the full stripped text and let JSON.parse surface the error.
  return stripped;
}

function sanitiseTaggedFacts(raw: unknown): ReadonlyArray<TaggedFact> {
  if (!Array.isArray(raw)) return [];
  const out: TaggedFact[] = [];
  for (const item of raw) {
    if (
      item !== null &&
      typeof item === 'object' &&
      typeof (item as Record<string, unknown>).fact === 'string' &&
      typeof (item as Record<string, unknown>).confidence === 'number'
    ) {
      const r = item as Record<string, unknown>;
      out.push({
        lexicon:    typeof r.lexicon    === 'string' ? r.lexicon    : '',
        category:   typeof r.category   === 'string' ? r.category   : '',
        confidence: r.confidence as number,
        fact:       r.fact as string,
        source:     typeof r.source     === 'string' ? r.source     : 'nl-extraction',
      });
    }
  }
  return out;
}

```
