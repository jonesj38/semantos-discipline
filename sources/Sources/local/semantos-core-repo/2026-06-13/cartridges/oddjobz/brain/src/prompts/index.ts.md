---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/prompts/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.528061+00:00
---

# cartridges/oddjobz/brain/src/prompts/index.ts

```ts
/**
 * D-O7 — prompts module entrypoint.
 *
 * The three prompts ported from OJT under the D-O7 salvage:
 *
 *   - `system-prompt.ts`        — operator-tuned chat persona prompt,
 *                                 hat-keyed (carpenter | musician | …).
 *   - `extraction-prompt.ts`    — extraction prompt + tagged-facts
 *                                 section (trades-only by default).
 *   - `pdf-extraction-prompt.ts` — PDF job-sheet extraction prompt
 *                                 (prompt-only; parser deferred).
 *
 * See `docs/design/D-O7-OJT-SALVAGE-REPORT.md` for the per-file
 * salvage verdict + tuning provenance.
 */

export {
  buildSystemPrompt,
  CARPENTER_PERSONA,
  MUSICIAN_PERSONA,
  PERSONAS,
  SYSTEM_PROMPT_VERSION,
  type ChannelContext,
  type OddjobzPersona,
  type PdfImportContext,
  type SystemPromptInput,
} from './system-prompt.js';
export {
  buildExtractionPrompt,
  buildTradesTaggedFactsSection,
  EXTRACTION_PROMPT_VERSION,
  JOB_TYPE_VALUES,
  type ExtractionPromptInput,
  type ExtractionPromptState,
} from './extraction-prompt.js';
export {
  buildPdfExtractionPrompt,
  PDF_EXTRACTION_PROMPT,
  PDF_EXTRACTION_PROMPT_VERSION,
} from './pdf-extraction-prompt.js';

```
