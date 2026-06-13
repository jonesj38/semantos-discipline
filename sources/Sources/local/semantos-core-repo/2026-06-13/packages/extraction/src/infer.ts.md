---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/infer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.452314+00:00
---

# packages/extraction/src/infer.ts

```ts
/**
 * Infer engine — detects unmapped fields and optionally suggests taxonomy.
 *
 * Pure async generator: ValidatedRecord stream → InferredRecord | GrammarPatch stream.
 * The InferenceClient is optional (stub for Phase 36C).
 */

import type { ExtensionGrammar } from '@semantos/protocol-types';
import type {
  ValidatedRecord,
  InferredRecord,
  GrammarPatch,
  ExtractionContext,
  InferenceClient,
} from './stages';
import { findEntityMapping } from './parse';

/**
 * Enrich validated records with inferred taxonomy and detect unmapped fields.
 */
export async function* inferRecords(
  records: AsyncIterable<ValidatedRecord>,
  grammar: ExtensionGrammar,
  context: ExtractionContext,
  inferenceClient?: InferenceClient,
): AsyncGenerator<InferredRecord | GrammarPatch, void, void> {
  const discoveredFields = new Set<string>();

  for await (const record of records) {
    // Detect unmapped source fields
    const mapping = findEntityMapping(grammar, record.sourceEntityId);
    const mappedSourceFields = new Set(
      mapping?.fieldMappings.map(fm => fm.sourceField) ?? [],
    );

    for (const sourceField of Object.keys(record.sourceFields)) {
      if (!mappedSourceFields.has(sourceField)) {
        discoveredFields.add(`${record.sourceEntityId}.${sourceField}`);
      }
    }

    // Optional: use inference client to suggest taxonomy
    let inferredTaxonomy: { confidence: number; suggestion: string } | undefined;
    if (inferenceClient) {
      const suggestion = await inferenceClient.suggestTaxonomy(record);
      if (suggestion) {
        inferredTaxonomy = {
          confidence: suggestion.confidence,
          suggestion: suggestion.path,
        };
      }
    }

    // Add inference evidence
    record.evidence.addInference({
      inferenceApplied: !!inferredTaxonomy,
      suggestedTaxonomy: inferredTaxonomy?.suggestion,
      confidenceScore: inferredTaxonomy?.confidence,
      grammarPatchProposed: false, // will be set by the trailing GrammarPatch
    });

    const inferred: InferredRecord = {
      ...record,
      inferredTaxonomy,
      grammarPatchRequired: discoveredFields.size > 0,
    };

    yield inferred;
  }

  // After all records, yield grammar patch if new fields were discovered
  if (discoveredFields.size > 0) {
    yield {
      type: 'grammar-patch',
      targetGrammar: grammar.grammarId,
      proposedFieldMappings: Array.from(discoveredFields).map(qualifiedField => {
        const dotIndex = qualifiedField.indexOf('.');
        const sourceField = dotIndex >= 0 ? qualifiedField.slice(dotIndex + 1) : qualifiedField;
        return {
          sourceField,
          targetField: camelCase(sourceField),
          required: false,
        };
      }),
      confidence: 'low',
    };
  }
}

/** Convert snake_case to camelCase. */
function camelCase(input: string): string {
  return input.replace(/_([a-z])/g, (_match, letter: string) => letter.toUpperCase());
}

```
