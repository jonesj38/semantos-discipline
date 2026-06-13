---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/validators/bindings.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.921781+00:00
---

# core/protocol-types/src/grammar/validators/bindings.ts

```ts
/**
 * Bindings section validator (entityMappings + linearity + condition + taxonomy).
 *
 * Bindings join source entities (declared in `verbs.ts`) to object
 * types (declared in `schemas.ts`). Each mapping describes:
 *   - sourceEntityId → targetObjectType
 *   - field-by-field mappings (delegated to `bindings-fields.ts`)
 *   - taxonomy coordinates
 *   - optional linearity override / condition
 *
 * Cross-section reference checks are folded in here: this module
 * receives the declared entity-id and object-type sets from the
 * schemas/verbs validators and reports unresolved references.
 *
 * Pure: never mutates input.
 */

import {
  VALID_CONDITION_OPERATORS,
  VALID_LINEARITY,
} from '../constants';
import {
  ValidationErrorCollector,
  requireString,
} from '../error-collector';
import { validateFieldMappings } from './bindings-fields';

export interface BindingRefs {
  declaredEntityIds: Set<string>;
  declaredObjectTypes: Set<string>;
  declaredSourceFields: Map<string, Set<string>>;
}

export function validateBindingsSection(
  g: Record<string, unknown>,
  refs: BindingRefs,
  errors: ValidationErrorCollector,
): void {
  if (!Array.isArray(g.entityMappings)) {
    errors.push({
      field: 'entityMappings',
      message: 'entityMappings must be an array',
    });
    return;
  }
  for (let i = 0; i < g.entityMappings.length; i++) {
    const em = g.entityMappings[i];
    const emErrors = errors.withPath('entityMappings').withPath(i);
    if (!em || typeof em !== 'object') {
      emErrors.push({ message: 'entityMapping must be an object' });
      continue;
    }
    validateEntityMapping(em as Record<string, unknown>, refs, emErrors);
  }
}

function validateEntityMapping(
  em: Record<string, unknown>,
  refs: BindingRefs,
  errors: ValidationErrorCollector,
): void {
  requireString(em, 'sourceEntityId', errors);
  requireString(em, 'targetObjectType', errors);

  // Resolve sourceEntityId
  if (
    typeof em.sourceEntityId === 'string' &&
    !refs.declaredEntityIds.has(em.sourceEntityId)
  ) {
    errors.push({
      field: 'sourceEntityId',
      message: `sourceEntityId "${em.sourceEntityId}" does not reference a declared source entity`,
    });
  }

  // Resolve targetObjectType
  if (
    typeof em.targetObjectType === 'string' &&
    !refs.declaredObjectTypes.has(em.targetObjectType)
  ) {
    errors.push({
      field: 'targetObjectType',
      message: `targetObjectType "${em.targetObjectType}" does not reference a declared objectType`,
    });
  }

  // Field mappings
  const entityFields = typeof em.sourceEntityId === 'string'
    ? refs.declaredSourceFields.get(em.sourceEntityId) ?? new Set<string>()
    : new Set<string>();
  validateFieldMappings(em.fieldMappings, entityFields, errors);

  // Taxonomy coordinates
  validateTaxonomyCoords(em, errors);

  // Linearity override (optional)
  if (em.linearityOverride !== undefined) {
    if (
      typeof em.linearityOverride !== 'string' ||
      !VALID_LINEARITY.has(em.linearityOverride)
    ) {
      errors.push({
        field: 'linearityOverride',
        message: `Invalid linearityOverride "${em.linearityOverride}"`,
      });
    }
  }

  // Condition (optional)
  validateCondition(em, errors);
}

function validateTaxonomyCoords(
  em: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  if (!em.taxonomy || typeof em.taxonomy !== 'object') {
    errors.push({ field: 'taxonomy', message: 'Missing taxonomy coordinates' });
    return;
  }
  const tax = em.taxonomy as Record<string, unknown>;
  const taxErrors = errors.withPath('taxonomy');
  if (typeof tax.what !== 'string') {
    taxErrors.push({ field: 'what', message: 'taxonomy.what is required' });
  }
  if (typeof tax.how !== 'string') {
    taxErrors.push({ field: 'how', message: 'taxonomy.how is required' });
  }
  if (typeof tax.why !== 'string') {
    taxErrors.push({ field: 'why', message: 'taxonomy.why is required' });
  }
}

function validateCondition(
  em: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  if (em.condition === undefined) return;
  if (!em.condition || typeof em.condition !== 'object') {
    errors.push({ field: 'condition', message: 'condition must be an object' });
    return;
  }
  const cond = em.condition as Record<string, unknown>;
  const condErrors = errors.withPath('condition');
  requireString(cond, 'field', condErrors);
  if (
    typeof cond.operator !== 'string' ||
    !VALID_CONDITION_OPERATORS.has(cond.operator)
  ) {
    condErrors.push({
      field: 'operator',
      message: `Invalid condition operator "${cond.operator}"`,
    });
  }
}

```
