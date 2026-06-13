---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/grammar-validator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.895679+00:00
---

# core/protocol-types/src/grammar/grammar-validator.ts

```ts
/**
 * Grammar validator orchestrator.
 *
 * Composes the per-section validators (manifest, verbs, schemas,
 * bindings, capabilities, policy, migrations) into a single public
 * entry point with the legacy `(grammar) → GrammarValidationResult`
 * shape. The actual validation logic lives in `validators/*.ts`.
 *
 * Cross-references:
 *   - `extension-grammar.ts` → type definitions
 *   - `validator-registry.ts` → ordered section dispatcher
 */

import type { GrammarValidationResult } from '../extension-grammar';
import { ValidationErrorCollector } from './error-collector';
import { DEFAULT_SECTIONS, runSections } from './validator-registry';

/**
 * Validate a JSON document against the Extension Grammar schema.
 *
 * Returns all validation errors collected (never short-circuits).
 * A grammar is valid if there are zero errors (warnings are acceptable).
 */
export function validateExtensionGrammar(grammar: unknown): GrammarValidationResult {
  const errors = ValidationErrorCollector.create();

  if (!grammar || typeof grammar !== 'object') {
    errors.push({
      path: '',
      message: 'Grammar must be a non-null object',
    });
    return errors.toResult();
  }

  runSections(grammar as Record<string, unknown>, DEFAULT_SECTIONS, errors);
  return errors.toResult();
}

// Re-export for downstream callers that want pluggable section sets
// (e.g., tests, or future per-grammar-type variants).
export {
  DEFAULT_SECTIONS,
  runSections,
  type SectionContext,
  type ValidatorSection,
} from './validator-registry';
export { ValidationErrorCollector } from './error-collector';

```
