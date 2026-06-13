---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/consciousness/consciousness/src/extraction.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.721702+00:00
---

# archive/consciousness/consciousness/src/extraction.ts

```ts
/**
 * LLM Extraction: Raw release text → structured semantic objects.
 *
 * Defines the extraction prompts and parsers that turn
 * stream-of-consciousness writing into Release, Insight, and Pattern
 * objects that the kernel can enforce consumption rules on.
 *
 * @module @semantos/consciousness/extraction
 */

import type {
  ReleaseExtractionResult,
  JournalPhotoExtractionResult,
  LifeDimension,
  PatternCategory,
} from './types/consciousness-objects.js';

/**
 * System prompt for the release extraction LLM call.
 */
export const RELEASE_EXTRACTION_SYSTEM_PROMPT = `You are a compassionate, non-judgmental analyst helping someone process their stream-of-consciousness writing.

Your role is to extract structured insights from raw release writing WITHOUT interpreting, diagnosing, or pathologizing. This writing is an act of release — like going to the toilet. The content is not necessarily "true" or representative of the person's actual beliefs. It's material that needed to be expressed.

Given a raw release text, extract the following JSON structure:

{
  "summary": "A brief, neutral 1-2 sentence summary of the core themes expressed",
  "valence": <number from -1.0 (heavy/dark) to 1.0 (light/expansive)>,
  "themes": ["3-7 keyword themes, e.g. 'self-doubt', 'control', 'family', 'creativity'"],
  "dimensions": ["which life dimensions are touched: MENTAL, PHYSICAL, SPIRITUAL, SOCIAL, VOCATIONAL, FINANCIAL, FAMILIAL"],
  "insights": [
    {
      "content": "A wisdom nugget extracted — something the writer may not see yet",
      "significance": <1-5, how important this seems>,
      "dimensions": ["relevant dimensions"],
      "tags": ["categorization tags"]
    }
  ],
  "patterns": [
    {
      "description": "A recurring theme or pattern detected",
      "category": "belief | emotion | relationship | behavior | desire | resistance",
      "polarity": "limiting | empowering | neutral",
      "dimensions": ["relevant dimensions"],
      "existingPatternId": "if this matches a known pattern, its ID (null otherwise)"
    }
  ],
  "intentions": [
    {
      "statement": "An implicit intention detected in the writing — what the person is choosing or wanting to move toward",
      "dimensions": ["relevant dimensions"]
    }
  ]
}

Guidelines:
- Be GENTLE. This is sacred, private material.
- Extract insights the writer may not consciously see — the gold in the dirt.
- Identify patterns across the writing (self-blame, projection, resistance themes).
- Detect implicit intentions even when expressed negatively ("I hate being broke" → intention toward financial abundance).
- The valence score reflects the overall emotional weight, not judgment.
- Themes should be concrete keywords, not abstract categories.
- If the writing contains a prompt prefix like "I feel..." or "I release...", note that in themes.
- NEVER suggest the person needs therapy, medication, or professional help in the extraction.
- If prior patterns are provided for context, reference their IDs when a pattern recurs.`;

/**
 * System prompt for journal photo OCR + extraction.
 */
export const JOURNAL_PHOTO_SYSTEM_PROMPT = `You are processing a photograph of handwritten journal pages for someone's personal consciousness process.

Step 1: Transcribe the handwritten text as accurately as possible. Note any words you're uncertain about with [?].
Step 2: Assess your OCR confidence (0.0 to 1.0).
Step 3: Apply the same extraction process as for typed release text.

Return JSON:
{
  "transcribedText": "the full OCR'd text",
  "ocrConfidence": <0.0-1.0>,
  "extraction": { ...same structure as release extraction... }
}

Be especially careful with handwriting — preserve the author's voice even in messy writing.`;

/**
 * Build the extraction prompt for a release, optionally with prior pattern context.
 */
export function buildReleaseExtractionPrompt(
  rawText: string,
  existingPatterns?: Array<{ id: string; description: string; category: string }>,
): string {
  let prompt = `Extract structured data from this release writing:\n\n---\n${rawText}\n---\n`;

  if (existingPatterns && existingPatterns.length > 0) {
    prompt += `\nKnown patterns from prior releases (reference by ID if any recur):\n`;
    for (const p of existingPatterns) {
      prompt += `- [${p.id}] ${p.category}: ${p.description}\n`;
    }
  }

  prompt += `\nRespond with valid JSON only.`;
  return prompt;
}

/**
 * Build the extraction prompt for a journal photo.
 */
export function buildJournalPhotoPrompt(): string {
  return `Transcribe the handwritten text in this image and extract structured data from it. Respond with valid JSON only.`;
}

/**
 * Parse and validate the LLM extraction result.
 */
export function parseExtractionResult(raw: string): ReleaseExtractionResult | null {
  try {
    let cleaned = raw.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '');
    }

    const parsed = JSON.parse(cleaned);

    if (typeof parsed.summary !== 'string') return null;
    if (typeof parsed.valence !== 'number') return null;
    if (!Array.isArray(parsed.themes)) return null;
    if (!Array.isArray(parsed.dimensions)) return null;
    if (!Array.isArray(parsed.insights)) return null;
    if (!Array.isArray(parsed.patterns)) return null;

    parsed.valence = Math.max(-1, Math.min(1, parsed.valence));

    const validDimensions: LifeDimension[] = [
      'MENTAL' as LifeDimension,
      'PHYSICAL' as LifeDimension,
      'SPIRITUAL' as LifeDimension,
      'SOCIAL' as LifeDimension,
      'VOCATIONAL' as LifeDimension,
      'FINANCIAL' as LifeDimension,
      'FAMILIAL' as LifeDimension,
    ];
    parsed.dimensions = parsed.dimensions.filter((d: string) =>
      validDimensions.includes(d as LifeDimension),
    );

    const validCategories: PatternCategory[] = [
      'belief' as PatternCategory,
      'emotion' as PatternCategory,
      'relationship' as PatternCategory,
      'behavior' as PatternCategory,
      'desire' as PatternCategory,
      'resistance' as PatternCategory,
    ];
    parsed.patterns = parsed.patterns.filter((p: { category: string }) =>
      validCategories.includes(p.category as PatternCategory),
    );

    if (!Array.isArray(parsed.intentions)) {
      parsed.intentions = [];
    }

    return parsed as ReleaseExtractionResult;
  } catch {
    return null;
  }
}

/**
 * Parse journal photo extraction result.
 */
export function parseJournalPhotoResult(raw: string): JournalPhotoExtractionResult | null {
  try {
    let cleaned = raw.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '');
    }

    const parsed = JSON.parse(cleaned);

    if (typeof parsed.transcribedText !== 'string') return null;
    if (typeof parsed.ocrConfidence !== 'number') return null;
    if (!parsed.extraction) return null;

    const extraction = parseExtractionResult(JSON.stringify(parsed.extraction));
    if (!extraction) return null;

    return {
      transcribedText: parsed.transcribedText,
      ocrConfidence: Math.max(0, Math.min(1, parsed.ocrConfidence)),
      extraction,
    };
  } catch {
    return null;
  }
}

```
