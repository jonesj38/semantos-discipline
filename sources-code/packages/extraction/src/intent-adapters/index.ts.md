---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/intent-adapters/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.455414+00:00
---

# packages/extraction/src/intent-adapters/index.ts

```ts
/**
 * @semantos/extraction/intent-adapters — LLM-backed Intent producers.
 *
 * Slice 2c: Anthropic-backed triage classifier + OddJobTodd trades
 * grammar. Plug a different grammar in by calling
 * `createAnthropicClassifier` with your own `ExtensionGrammarSpec`.
 *
 * See docs/INTENT-PIPELINE.md §"Triage and conversation patches".
 */

export { createAnthropicClassifier } from './llm-classifier';
export type { AnthropicClassifierOptions } from './llm-classifier';

export {
  CLASSIFIER_TOOL_SCHEMA,
  buildClassifierToolSchema,
  parseClassifierToolInput,
} from './classifier-tool';
export type {
  ClassifierToolInput,
  ParseClassifierInputContext,
} from './classifier-tool';

export { buildClassifierSystemPrompt } from './system-prompt';

// Cherry-picked oddjobz extraction richness (graft-before-cut) — a
// COMPOSABLE addendum, intentionally not folded into the cached
// classifier prompt. See sizing-prompt.ts header.
export {
  buildSizingQuestionsPrompt,
  ODDJOBZ_EXTRACTION_FIELD_RULES,
} from './sizing-prompt';

export { TRADES_GRAMMAR } from './trades-grammar';
export { SCADA_GRAMMAR } from './scada-grammar';
export type { ActionDefinition, ExtensionGrammarSpec } from './trades-grammar';

```
