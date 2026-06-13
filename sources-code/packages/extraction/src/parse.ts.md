---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/parse.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.453133+00:00
---

# packages/extraction/src/parse.ts

```ts
/**
 * Parse engine — applies field mappings and transforms to raw API responses.
 *
 * Pure async generator: RawResponse stream → IntermediateRecord stream.
 * No protocol awareness, no side effects.
 */

import type { ExtensionGrammar, SourceEntity, EntityMapping, FieldMapping } from '@semantos/protocol-types';
import type { RawResponse, IntermediateRecord, ExtractionContext } from './stages';
import { EvidenceAccumulator } from './evidence';
import { applyTransform, resolveNestedField, extractRecordsFromResponse } from './transforms';

/**
 * Parse raw API responses into intermediate records using grammar field mappings.
 */
export async function* parseResponses(
  responses: AsyncIterable<RawResponse>,
  grammar: ExtensionGrammar,
  entity: SourceEntity,
  context: ExtractionContext,
): AsyncGenerator<IntermediateRecord, void, void> {
  const mapping = findEntityMapping(grammar, entity.entityId);
  if (!mapping) {
    throw new Error(`No entity mapping found for entity: ${entity.entityId}`);
  }

  for await (const response of responses) {
    const records = extractRecordsFromResponse(response.body, entity.responseShape.dataPath);

    for (const rawRecord of records) {
      const sourceFields = rawRecord as Record<string, unknown>;
      const mappedFields: Record<string, unknown> = {};
      const transformsApplied: string[] = [];

      for (const fm of mapping.fieldMappings) {
        const value = applyFieldMapping(sourceFields, fm);
        if (value !== undefined) {
          mappedFields[fm.targetField] = value;
          if (fm.transform) {
            transformsApplied.push(`${fm.sourceField}→${fm.transform.type}`);
          }
        } else if (fm.default !== undefined) {
          mappedFields[fm.targetField] = fm.default;
        }
      }

      const sourceId = sourceFields[entity.responseShape.idField];

      // Build evidence
      const evidence = new EvidenceAccumulator(context.grammarVersion);
      evidence.addFetch({
        endpoint: response.endpoint,
        responseHash: response.responseHash,
        statusCode: response.statusCode,
        bytesReceived: JSON.stringify(response.body).length,
      });
      evidence.addParse({
        sourceEntityId: entity.entityId,
        targetObjectType: mapping.targetObjectType,
        fieldsMapped: Object.keys(mappedFields).length,
        transformsApplied,
      });

      yield {
        sourceEntityId: entity.entityId,
        sourceFields,
        mappedFields,
        sourceId,
        evidence,
      };
    }
  }
}

/** Apply a single field mapping to a source record. */
function applyFieldMapping(
  sourceRecord: Record<string, unknown>,
  mapping: FieldMapping,
): unknown {
  // Resolve source value (may be nested via dot-notation)
  let value = resolveNestedField(sourceRecord, mapping.sourceField);

  // If source is missing and no transform generates a value
  if (value === undefined && !mapping.transform) {
    return undefined;
  }

  // Apply coercion
  if (mapping.coerce && value !== undefined) {
    value = coerceValue(value, mapping.coerce.from, mapping.coerce.to, mapping.coerce.format);
  }

  // Apply transform
  if (mapping.transform) {
    value = applyTransform(value, mapping.transform, sourceRecord);
  }

  return value;
}

/** Coerce a value from one type to another. */
function coerceValue(value: unknown, _from: string, to: string, format?: string): unknown {
  switch (to) {
    case 'string':
      return String(value);
    case 'number':
      return Number(value);
    case 'boolean':
      return Boolean(value);
    case 'date':
    case 'datetime':
      if (format && typeof value === 'string') {
        return new Date(value).toISOString();
      }
      return typeof value === 'string' ? value : String(value);
    default:
      return value;
  }
}

/** Find the entity mapping for a source entity. */
export function findEntityMapping(
  grammar: ExtensionGrammar,
  entityId: string,
): EntityMapping | undefined {
  return grammar.entityMappings.find(em => em.sourceEntityId === entityId);
}

```
