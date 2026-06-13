---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/prompts/pdf-extraction-prompt.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.527759+00:00
---

# cartridges/oddjobz/brain/src/prompts/pdf-extraction-prompt.ts

```ts
/**
 * D-O7 — PDF extraction prompt.
 *
 * Origin: `oddjobtodd/src/lib/ai/prompts/pdfExtractionPrompt.ts`.
 * Last tuned: 2026-04 (the OJT-side handed-PDF-from-real-estate-agent
 *             onboarding flow).
 *
 * The prompt is a frozen string export. PDF byte-extraction is wired
 * via `runtime/legacy-ingest/src/extractor/pdf.ts` (layered: cache →
 * pdftotext → Anthropic Vision fallback). See D-DOG.1a for the
 * implementation that closes the original "deferred" note.
 *
 * The prompt is parameterised over the `JOB_TYPE_VALUES` enum so it
 * stays in sync with the `TradesLexicon` — adding a trade extends the
 * lexicon and re-derives this prompt without manual edit.
 */

import { JOB_TYPE_VALUES } from './extraction-prompt.js';

/** Schema version of this prompt. Bump (and APPEND a new version
 *  entry in conversation/prompt-store.ts) on any intentional change to
 *  the prompt text, so the old version stays in the audit chain. */
export const PDF_EXTRACTION_PROMPT_VERSION = '1.0.0' as const;

/** Render the trades job-type list as a quoted comma-separated string —
 *  matches the OJT origin's `${jobTypeList}` interpolation point. */
function renderJobTypeList(): string {
  return JOB_TYPE_VALUES.map((v) => `"${v}"`).join(', ');
}

/**
 * Build the PDF extraction system prompt. Pure function — same input
 * always yields the same prompt (the input is the trades lexicon
 * snapshot at module-load time).
 *
 * Verbatim port of OJT's `PDF_EXTRACTION_PROMPT` constant.
 */
export function buildPdfExtractionPrompt(): string {
  const jobTypeList = renderJobTypeList();

  return `You are a data extraction agent for a Sunshine Coast handyman business.
You are reading a PDF job sheet sent by a real estate agent or property manager.

Extract ALL structured data from this document into JSON format.

These PDFs typically contain:
- Property address and suburb
- Agent or property manager contact details
- Tenant contact details (the person at the property)
- A list of maintenance tasks or repair items
- Urgency indicators (URGENT, routine, etc.)
- Access notes (keys at office, tenant home M-F, etc.)

Return ONLY valid JSON matching this structure. Use null for genuinely unknown fields:

{
  "propertyAddress": string | null,
  "suburb": string | null,
  "postcode": string | null,
  "state": string | null,

  "tenantName": string | null,
  "tenantPhone": string | null,
  "tenantEmail": string | null,

  "agentName": string | null,
  "agentPhone": string | null,
  "agentEmail": string | null,
  "agencyName": string | null,

  "accessNotes": string | null,

  "tasks": [
    {
      "description": string,
      "location": string | null,
      "category": ${jobTypeList} | null,
      "urgency": "emergency" | "urgent" | "next_week" | "flexible" | "unspecified" | null,
      "repairOrReplace": "repair" | "replace" | "install" | "inspect" | "unclear" | null,
      "quantityHint": string | null
    }
  ],

  "overallUrgency": "emergency" | "urgent" | "next_week" | "next_2_weeks" | "flexible" | "when_convenient" | "unspecified",
  "additionalNotes": string | null,
  "confidence": "high" | "medium" | "low"
}

EXTRACTION RULES:
1. Be thorough. Extract every maintenance item listed, even minor ones.
2. Map categories using the exact enum values: ${jobTypeList}.
3. For Australian addresses, infer state as "QLD" for Sunshine Coast suburbs.
4. Tenant is the customer (the person the handyman will work with on-site).
5. Agent is the referrer (the real estate agent or property manager).
6. If multiple tasks span different trades, list them all individually.
7. "confidence" reflects how readable and structured the PDF was.
8. For phone numbers, keep the original format — normalisation happens later.
9. If the PDF mentions keys, access codes, or timing constraints, put them in accessNotes.`;
}

/**
 * The PDF extraction prompt as a frozen string snapshot, for callers
 * that want the constant rather than the builder. Bound at module
 * load using the trades lexicon snapshot.
 */
export const PDF_EXTRACTION_PROMPT = Object.freeze(buildPdfExtractionPrompt());

```
