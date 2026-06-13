---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/validators/bindings-fields.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.922718+00:00
---

# core/protocol-types/src/grammar/validators/bindings-fields.ts

```ts
/**
 * Field-mapping + transform validator (used by bindings.ts).
 *
 * Each `entityMapping.fieldMappings[i]` joins one source field to one
 * target object-type field, optionally with a visibility classifier
 * and a transform pipeline. Split out from `bindings.ts` to keep
 * each validator file under the 200-LOC ceiling.
 *
 * Pure: never mutates input.
 */

import type { FieldTransformType } from '../../extension-grammar';
import {
  COMPUTE_EXPRESSION_REGEX,
  VALID_TRANSFORM_TYPES,
  VALID_VISIBILITY,
} from '../constants';
import {
  ValidationErrorCollector,
  requireString,
} from '../error-collector';

export function validateFieldMappings(
  fieldMappings: unknown,
  entityFields: Set<string>,
  errors: ValidationErrorCollector,
): void {
  if (!Array.isArray(fieldMappings)) {
    errors.push({
      field: 'fieldMappings',
      message: 'fieldMappings must be an array',
    });
    return;
  }
  for (let j = 0; j < fieldMappings.length; j++) {
    validateFieldMapping(
      fieldMappings[j] as Record<string, unknown>,
      entityFields,
      errors.withPath('fieldMappings').withPath(j),
    );
  }
}

function validateFieldMapping(
  fm: Record<string, unknown>,
  entityFields: Set<string>,
  errors: ValidationErrorCollector,
): void {
  if (!fm || typeof fm !== 'object') {
    errors.push({ message: 'fieldMapping must be an object' });
    return;
  }

  requireString(fm, 'sourceField', errors);
  requireString(fm, 'targetField', errors);

  if (typeof fm.required !== 'boolean') {
    errors.push({ field: 'required', message: 'required must be a boolean' });
  }

  // Resolve sourceField — check the root field name (before any dot-notation)
  if (typeof fm.sourceField === 'string' && entityFields.size > 0) {
    const rootField = fm.sourceField.split('.')[0];
    if (!entityFields.has(rootField)) {
      errors.push({
        field: 'sourceField',
        message: `sourceField "${fm.sourceField}" does not reference a declared source field (root: "${rootField}")`,
      });
    }
  }

  // Visibility (optional)
  if (fm.visibility !== undefined) {
    if (
      typeof fm.visibility !== 'string' ||
      !VALID_VISIBILITY.has(fm.visibility)
    ) {
      errors.push({
        field: 'visibility',
        message: `Invalid visibility "${fm.visibility}"`,
      });
    }
  }

  // Transform (optional)
  if (fm.transform !== undefined) {
    validateTransform(
      fm.transform as Record<string, unknown>,
      errors.withPath('transform'),
    );
  }
}

function validateTransform(
  tr: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  if (!tr || typeof tr !== 'object') {
    errors.push({ message: 'transform must be an object' });
    return;
  }

  if (
    typeof tr.type !== 'string' ||
    !VALID_TRANSFORM_TYPES.has(tr.type as FieldTransformType)
  ) {
    errors.push({
      field: 'type',
      message: `Invalid transform type "${tr.type}". Must be one of: ${[...VALID_TRANSFORM_TYPES].join(', ')}`,
    });
  }

  // Validate compute expressions are constrained
  if (tr.type === 'compute' && typeof tr.expression === 'string') {
    if (!COMPUTE_EXPRESSION_REGEX.test(tr.expression)) {
      errors.push({
        field: 'expression',
        message: `Compute expression "${tr.expression}" is not safe. Only source.<field> references, numeric literals, and +, -, *, / operators are allowed`,
      });
    }
  }
}

```
