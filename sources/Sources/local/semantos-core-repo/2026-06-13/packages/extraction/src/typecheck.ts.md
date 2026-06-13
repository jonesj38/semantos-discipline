---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/typecheck.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.453956+00:00
---

# packages/extraction/src/typecheck.ts

```ts
/**
 * Typecheck engine — validates intermediate records against grammar schema.
 *
 * Pure async generator: IntermediateRecord stream → ValidatedRecord stream.
 * Collects errors per-record without aborting the batch.
 */

import type { ExtensionGrammar, EntityMapping, ObjectTypeDeclaration } from '@semantos/protocol-types';
import type { IntermediateRecord, ValidatedRecord, ExtractionContext, TaxonomyCoordinate } from './stages';
import { findEntityMapping } from './parse';

/**
 * Validate intermediate records against grammar schema, assign taxonomy and phase.
 */
export async function* typecheckRecords(
  records: AsyncIterable<IntermediateRecord>,
  grammar: ExtensionGrammar,
  context: ExtractionContext,
): AsyncGenerator<ValidatedRecord, void, void> {
  for await (const record of records) {
    const mapping = findEntityMapping(grammar, record.sourceEntityId);
    if (!mapping) {
      yield {
        ...record,
        targetObjectType: 'unknown',
        taxonomy: { what: '', how: '', why: '' },
        phase: 'unknown',
        validationPassed: false,
        validationErrors: [`No entity mapping for ${record.sourceEntityId}`],
      };
      continue;
    }

    const objectType = findObjectType(grammar, mapping.targetObjectType);
    const errors: string[] = [];

    // 1. Validate required fields from payloadSchema
    if (objectType) {
      for (const [fieldName, fieldDef] of Object.entries(objectType.payloadSchema)) {
        // Check if this field is required via field mappings
        const fm = mapping.fieldMappings.find(f => f.targetField === fieldName);
        if (fm?.required && !(fieldName in record.mappedFields)) {
          errors.push(`Required field "${fieldName}" missing`);
        }
      }
    } else {
      errors.push(`Object type "${mapping.targetObjectType}" not declared in grammar`);
    }

    // 2. Validate field types against payloadSchema
    if (objectType) {
      for (const [fieldName, value] of Object.entries(record.mappedFields)) {
        const schemaDef = objectType.payloadSchema[fieldName];
        if (schemaDef) {
          const typeError = validateFieldType(fieldName, value, schemaDef.type);
          if (typeError) errors.push(typeError);
        }
      }
    }

    // 3. Resolve and validate taxonomy coordinates
    const taxonomy = resolveTaxonomy(mapping, record.sourceFields);
    if (!isValidTaxonomyPath(taxonomy.what)) {
      errors.push(`Invalid taxonomy what: "${taxonomy.what}"`);
    }
    if (!isValidTaxonomyPath(taxonomy.how)) {
      errors.push(`Invalid taxonomy how: "${taxonomy.how}"`);
    }
    if (!isValidTaxonomyPath(taxonomy.why)) {
      errors.push(`Invalid taxonomy why: "${taxonomy.why}"`);
    }

    // 4. Assign phase via phaseMapping or initialPhase
    const phase = resolvePhase(mapping, record.sourceFields);

    // 5. Add typecheck evidence
    const taxonomyStr = `${taxonomy.what}|${taxonomy.how}|${taxonomy.why}`;
    record.evidence.addTypecheck({
      passed: errors.length === 0,
      errors,
      taxonomyAssigned: taxonomyStr,
      phaseAssigned: phase,
    });

    yield {
      ...record,
      targetObjectType: mapping.targetObjectType,
      taxonomy,
      phase,
      validationPassed: errors.length === 0,
      validationErrors: errors,
    };
  }
}

// ── Helpers ─────────────────────────────────────────────────────

/** Find an ObjectTypeDeclaration by typePath. */
export function findObjectType(
  grammar: ExtensionGrammar,
  typePath: string,
): ObjectTypeDeclaration | undefined {
  return grammar.objectTypes.find(ot => ot.typePath === typePath);
}

/** Validate that a taxonomy path is syntactically valid (dot-separated segments). */
export function isValidTaxonomyPath(path: string): boolean {
  if (!path || path.length === 0) return false;
  return /^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9-]*)*$/.test(path);
}

/** Resolve taxonomy coordinates, substituting source field values if needed. */
function resolveTaxonomy(
  mapping: EntityMapping,
  sourceFields: Record<string, unknown>,
): TaxonomyCoordinate {
  return {
    what: resolveTaxonomyValue(mapping.taxonomy.what, sourceFields),
    how: resolveTaxonomyValue(mapping.taxonomy.how, sourceFields),
    why: resolveTaxonomyValue(mapping.taxonomy.why, sourceFields),
    where: mapping.taxonomy.where
      ? resolveTaxonomyValue(mapping.taxonomy.where, sourceFields)
      : undefined,
  };
}

/** Resolve a single taxonomy value — may be a literal or a template expression. */
function resolveTaxonomyValue(
  value: string,
  sourceFields: Record<string, unknown>,
): string {
  // If it contains {{...}}, treat as template
  if (value.includes('{{')) {
    return value.replace(/\{\{([^}]+)\}\}/g, (_match, field: string) => {
      const resolved = sourceFields[field.trim()];
      return resolved !== undefined ? String(resolved) : 'unknown';
    });
  }
  return value;
}

/** Resolve commerce phase from source status via phaseMapping. */
function resolvePhase(
  mapping: EntityMapping,
  sourceFields: Record<string, unknown>,
): string {
  if (!mapping.phaseMapping) {
    return mapping.initialPhase ?? 'source';
  }

  // Find the status key field — it's the first field name that matches a key in phaseMapping
  for (const [sourceValue, targetPhase] of Object.entries(mapping.phaseMapping)) {
    // Check all source fields for a matching value
    for (const fieldValue of Object.values(sourceFields)) {
      if (String(fieldValue) === sourceValue) {
        return targetPhase;
      }
    }
  }

  return mapping.initialPhase ?? 'source';
}

/** Validate a field value against its expected type. */
function validateFieldType(
  fieldName: string,
  value: unknown,
  expectedType: string,
): string | null {
  if (value === null || value === undefined) return null; // null is acceptable

  switch (expectedType) {
    case 'string':
      if (typeof value !== 'string') return `Field "${fieldName}" expected string, got ${typeof value}`;
      break;
    case 'number':
      if (typeof value !== 'number') return `Field "${fieldName}" expected number, got ${typeof value}`;
      break;
    case 'boolean':
      if (typeof value !== 'boolean') return `Field "${fieldName}" expected boolean, got ${typeof value}`;
      break;
    case 'array':
      if (!Array.isArray(value)) return `Field "${fieldName}" expected array, got ${typeof value}`;
      break;
    case 'object':
      if (typeof value !== 'object' || Array.isArray(value)) return `Field "${fieldName}" expected object`;
      break;
    // date, datetime, enum — accept strings
    case 'date':
    case 'datetime':
    case 'enum':
      break;
  }
  return null;
}

```
