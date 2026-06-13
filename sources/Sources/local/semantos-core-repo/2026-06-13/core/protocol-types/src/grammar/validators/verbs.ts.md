---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/validators/verbs.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.923007+00:00
---

# core/protocol-types/src/grammar/validators/verbs.ts

```ts
/**
 * Verbs section validator (the `source` declaration block).
 *
 * "Verbs" in grammar parlance correspond to the source-protocol calls
 * the extension can perform: which protocol (REST/GraphQL/etc.), how
 * it authenticates, paginates, and which entities/fields it exposes.
 *
 * Returns:
 *  - the set of declared `entityId`s (for binding lookups)
 *  - a per-entity map of declared source field names (for fieldMapping
 *    reference checks).
 *
 * Per-entity validation lives in `./verbs-entity.ts` to keep this
 * file under the 200-LOC ceiling.
 *
 * Pure: never mutates input.
 */

import {
  VALID_AUTH_TYPES,
  VALID_PAGINATION_TYPES,
  VALID_SOURCE_PROTOCOLS,
} from '../constants';
import {
  ValidationErrorCollector,
  requireString,
} from '../error-collector';
import {
  collectFieldNames,
  validateSourceEntity,
} from './verbs-entity';

export interface VerbsCollected {
  declaredEntityIds: Set<string>;
  declaredSourceFields: Map<string, Set<string>>;
}

export function validateVerbsSection(
  g: Record<string, unknown>,
  errors: ValidationErrorCollector,
): VerbsCollected {
  const declaredEntityIds = new Set<string>();
  const declaredSourceFields = new Map<string, Set<string>>();

  if (!g.source || typeof g.source !== 'object') {
    errors.push({
      field: 'source',
      message: 'Missing or invalid source declaration',
    });
    return { declaredEntityIds, declaredSourceFields };
  }

  const source = g.source as Record<string, unknown>;
  const srcErrors = errors.withPath('source');

  validateProtocolAndAuth(source, srcErrors);
  validatePagination(source, srcErrors);
  validateSourceEntities(source, srcErrors, declaredEntityIds, declaredSourceFields);

  return { declaredEntityIds, declaredSourceFields };
}

function validateProtocolAndAuth(
  source: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  if (
    typeof source.protocol !== 'string' ||
    !VALID_SOURCE_PROTOCOLS.has(source.protocol)
  ) {
    errors.push({
      field: 'protocol',
      message: `Invalid source protocol "${source.protocol}". Must be one of: ${[...VALID_SOURCE_PROTOCOLS].join(', ')}`,
    });
  }

  requireString(source, 'baseUrlTemplate', errors);

  if (!source.auth || typeof source.auth !== 'object') {
    errors.push({ field: 'auth', message: 'Missing or invalid source.auth' });
    return;
  }
  const auth = source.auth as Record<string, unknown>;
  const authErrors = errors.withPath('auth');
  if (typeof auth.type !== 'string' || !VALID_AUTH_TYPES.has(auth.type)) {
    authErrors.push({
      field: 'type',
      message: `Invalid auth type "${auth.type}". Must be one of: ${[...VALID_AUTH_TYPES].join(', ')}`,
    });
  }
  if (!Array.isArray(auth.requiredCredentials)) {
    authErrors.push({
      field: 'requiredCredentials',
      message: 'requiredCredentials must be an array',
    });
  }
}

function validatePagination(
  source: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  if (source.pagination === undefined) return;
  if (!source.pagination || typeof source.pagination !== 'object') {
    errors.push({
      field: 'pagination',
      message: 'pagination must be an object if provided',
    });
    return;
  }
  const pg = source.pagination as Record<string, unknown>;
  const pgErrors = errors.withPath('pagination');
  if (typeof pg.type !== 'string' || !VALID_PAGINATION_TYPES.has(pg.type)) {
    pgErrors.push({
      field: 'type',
      message: `Invalid pagination type "${pg.type}"`,
    });
  }
  if (typeof pg.pageSize !== 'number' || pg.pageSize <= 0) {
    pgErrors.push({
      field: 'pageSize',
      message: 'pageSize must be a positive number',
    });
  }
}

function validateSourceEntities(
  source: Record<string, unknown>,
  errors: ValidationErrorCollector,
  declaredEntityIds: Set<string>,
  declaredSourceFields: Map<string, Set<string>>,
): void {
  if (!Array.isArray(source.entities) || source.entities.length === 0) {
    errors.push({
      field: 'entities',
      message: 'source.entities must be a non-empty array',
    });
    return;
  }

  for (let i = 0; i < source.entities.length; i++) {
    const entity = source.entities[i] as Record<string, unknown>;
    const entErrors = errors.withPath('entities').withPath(i);
    validateSourceEntity(entity, entErrors);

    if (entity && typeof entity === 'object') {
      const id = entity.entityId;
      if (typeof id === 'string') {
        declaredEntityIds.add(id);
        declaredSourceFields.set(id, collectFieldNames(entity.fields));
      }
    }
  }
}

```
