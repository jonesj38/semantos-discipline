---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/validators/verbs-entity.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.922426+00:00
---

# core/protocol-types/src/grammar/validators/verbs-entity.ts

```ts
/**
 * Source-entity validator (used by verbs.ts).
 *
 * Each `source.entities[i]` declares an addressable entity exposed
 * by the upstream protocol — its endpoint URLs, response shape,
 * fields, and relationships. Split out from `verbs.ts` to keep
 * each validator file under the 200-LOC ceiling.
 *
 * Pure: never mutates input.
 */

import type { SourceFieldType } from '../../extension-grammar';
import {
  VALID_RELATIONSHIP_TYPES,
  VALID_SOURCE_FIELD_TYPES,
} from '../constants';
import {
  ValidationErrorCollector,
  requireString,
} from '../error-collector';

export function validateSourceEntity(
  entity: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  if (!entity || typeof entity !== 'object') {
    errors.push({ message: 'Source entity must be an object' });
    return;
  }

  requireString(entity, 'entityId', errors);
  requireString(entity, 'displayName', errors);

  // Endpoint
  if (!entity.endpoint || typeof entity.endpoint !== 'object') {
    errors.push({ field: 'endpoint', message: 'Missing endpoint' });
  } else {
    const epErrors = errors.withPath('endpoint');
    const ep = entity.endpoint as Record<string, unknown>;
    requireString(ep, 'list', epErrors);
    requireString(ep, 'get', epErrors);
  }

  // Response shape
  if (!entity.responseShape || typeof entity.responseShape !== 'object') {
    errors.push({ field: 'responseShape', message: 'Missing responseShape' });
  } else {
    const rsErrors = errors.withPath('responseShape');
    const rs = entity.responseShape as Record<string, unknown>;
    requireString(rs, 'dataPath', rsErrors);
    requireString(rs, 'idField', rsErrors);
  }

  // Fields
  if (!Array.isArray(entity.fields) || entity.fields.length === 0) {
    errors.push({
      field: 'fields',
      message: 'fields must be a non-empty array',
    });
  } else {
    for (let j = 0; j < entity.fields.length; j++) {
      validateSourceField(
        entity.fields[j] as Record<string, unknown>,
        errors.withPath('fields').withPath(j),
      );
    }
  }

  // Relationships (optional)
  validateRelationships(entity, errors);
}

function validateSourceField(
  field: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  if (!field || typeof field !== 'object') {
    errors.push({ message: 'Source field must be an object' });
    return;
  }
  requireString(field, 'sourceFieldName', errors);
  if (
    typeof field.sourceType !== 'string' ||
    !VALID_SOURCE_FIELD_TYPES.has(field.sourceType as SourceFieldType)
  ) {
    errors.push({
      field: 'sourceType',
      message: `Invalid sourceType "${field.sourceType}". Must be one of: ${[...VALID_SOURCE_FIELD_TYPES].join(', ')}`,
    });
  }
  if (typeof field.required !== 'boolean') {
    errors.push({ field: 'required', message: 'required must be a boolean' });
  }
  if (
    field.sourceType === 'enum' &&
    (!Array.isArray(field.enumValues) || field.enumValues.length === 0)
  ) {
    errors.push({
      field: 'enumValues',
      message: 'enum type requires non-empty enumValues array',
    });
  }
}

function validateRelationships(
  entity: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  if (entity.relationships === undefined) return;
  if (!Array.isArray(entity.relationships)) {
    errors.push({
      field: 'relationships',
      message: 'relationships must be an array',
    });
    return;
  }
  for (let j = 0; j < entity.relationships.length; j++) {
    const rel = entity.relationships[j] as Record<string, unknown>;
    const relErrors = errors.withPath('relationships').withPath(j);
    requireString(rel, 'targetEntityId', relErrors);
    if (
      typeof rel.type !== 'string' ||
      !VALID_RELATIONSHIP_TYPES.has(rel.type)
    ) {
      relErrors.push({
        field: 'type',
        message: `Invalid relationship type "${rel.type}"`,
      });
    }
    requireString(rel, 'foreignKey', relErrors);
    if (
      rel.foreignKeyLocation !== 'source' &&
      rel.foreignKeyLocation !== 'target'
    ) {
      relErrors.push({
        field: 'foreignKeyLocation',
        message: 'foreignKeyLocation must be "source" or "target"',
      });
    }
  }
}

/** Helper exported so `verbs.ts` can collect declared field names. */
export function collectFieldNames(fields: unknown): Set<string> {
  const out = new Set<string>();
  if (!Array.isArray(fields)) return out;
  for (const f of fields) {
    if (f && typeof f === 'object') {
      const name = (f as Record<string, unknown>).sourceFieldName;
      if (typeof name === 'string') out.add(name);
    }
  }
  return out;
}

```
