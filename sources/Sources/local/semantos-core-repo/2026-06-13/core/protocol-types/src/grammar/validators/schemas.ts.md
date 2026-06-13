---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/validators/schemas.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.921491+00:00
---

# core/protocol-types/src/grammar/validators/schemas.ts

```ts
/**
 * Schemas section validator (object types + payload schemas + transitions).
 *
 * Validates `grammar.objectTypes[]` — each entry declares a typePath,
 * linearity class, lifecycle phases, payload schema, capability
 * requirements, and optional state transitions.
 *
 * The set of declared `typePath` values is also exposed (returned)
 * because downstream sections (bindings) need to reference-check
 * against it without re-walking the array.
 *
 * Pure: never mutates input.
 */

import {
  VALID_LINEARITY,
  VALID_PAYLOAD_TYPES,
} from '../constants';
import {
  ValidationErrorCollector,
  requireString,
} from '../error-collector';

/**
 * Dispatcher for the schemas (objectTypes) section.
 *
 * Returns the set of declared `typePath` values, for use by the
 * bindings validator to resolve `targetObjectType` references.
 */
export function validateSchemasSection(
  g: Record<string, unknown>,
  errors: ValidationErrorCollector,
): Set<string> {
  const declaredObjectTypes = new Set<string>();

  if (!Array.isArray(g.objectTypes) || g.objectTypes.length === 0) {
    errors.push({
      field: 'objectTypes',
      message: 'objectTypes must be a non-empty array',
    });
    return declaredObjectTypes;
  }

  for (let i = 0; i < g.objectTypes.length; i++) {
    const ot = g.objectTypes[i];
    const otErrors = errors.withPath('objectTypes').withPath(i);
    if (!ot || typeof ot !== 'object') {
      otErrors.push({ message: 'objectType entry must be an object' });
      continue;
    }
    validateObjectType(ot as Record<string, unknown>, otErrors);
    const tp = (ot as Record<string, unknown>).typePath;
    if (typeof tp === 'string') declaredObjectTypes.add(tp);
  }

  return declaredObjectTypes;
}

function validateObjectType(
  ot: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  requireString(ot, 'typePath', errors);
  requireString(ot, 'displayName', errors);
  requireString(ot, 'description', errors);

  if (typeof ot.linearity !== 'string' || !VALID_LINEARITY.has(ot.linearity)) {
    errors.push({
      field: 'linearity',
      message: `Invalid linearity "${ot.linearity}". Must be one of: ${[...VALID_LINEARITY].join(', ')}`,
    });
  }

  if (!Array.isArray(ot.phases) || ot.phases.length === 0) {
    errors.push({
      field: 'phases',
      message: 'phases must be a non-empty array',
    });
  }

  requireString(ot, 'initialPhase', errors);

  // initialPhase must be in phases
  if (typeof ot.initialPhase === 'string' && Array.isArray(ot.phases)) {
    if (!ot.phases.includes(ot.initialPhase)) {
      errors.push({
        field: 'initialPhase',
        message: `initialPhase "${ot.initialPhase}" not found in phases array`,
      });
    }
  }

  validatePayloadSchema(ot, errors);
  validateCapabilitiesShape(ot, errors);
  validateTransitions(ot, errors);
}

function validatePayloadSchema(
  ot: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  if (!ot.payloadSchema || typeof ot.payloadSchema !== 'object') {
    errors.push({ field: 'payloadSchema', message: 'Missing payloadSchema' });
    return;
  }
  const schemaErrors = errors.withPath('payloadSchema');
  const schema = ot.payloadSchema as Record<string, unknown>;
  for (const [fieldName, fieldDef] of Object.entries(schema)) {
    const fieldErrors = schemaErrors.withPath(fieldName);
    if (!fieldDef || typeof fieldDef !== 'object') {
      fieldErrors.push({ message: 'Field definition must be an object' });
      continue;
    }
    const fd = fieldDef as Record<string, unknown>;
    if (typeof fd.type !== 'string' || !VALID_PAYLOAD_TYPES.has(fd.type)) {
      fieldErrors.push({
        field: 'type',
        message: `Invalid payload type "${fd.type}". Must be one of: ${[...VALID_PAYLOAD_TYPES].join(', ')}`,
      });
    }
    if (fd.type === 'enum' && (!Array.isArray(fd.enum) || fd.enum.length === 0)) {
      fieldErrors.push({
        field: 'enum',
        message: 'enum type requires non-empty enum array',
      });
    }
    // CC5: tier/carrier are optional and additive — only validated when present.
    if (fd.tier !== undefined && fd.tier !== 'core' && fd.tier !== 'operator-extensible') {
      fieldErrors.push({
        field: 'tier',
        message: `Invalid tier "${fd.tier}". Must be "core" or "operator-extensible".`,
      });
    }
    if (fd.carrier !== undefined) {
      const c = fd.carrier as Record<string, unknown>;
      if (!c || typeof c !== 'object' || c.octave !== 1) {
        fieldErrors.push({
          field: 'carrier',
          message: 'carrier must be { octave: 1 } (the only supported escalation tier).',
        });
      }
    }
  }
}

function validateCapabilitiesShape(
  ot: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  if (!ot.capabilities || typeof ot.capabilities !== 'object') {
    errors.push({ field: 'capabilities', message: 'Missing capabilities object' });
  }
}

function validateTransitions(
  ot: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  if (ot.transitions === undefined) return;
  if (!Array.isArray(ot.transitions)) {
    errors.push({ field: 'transitions', message: 'transitions must be an array' });
    return;
  }
  for (let j = 0; j < ot.transitions.length; j++) {
    const tr = ot.transitions[j] as Record<string, unknown>;
    const trErrors = errors.withPath('transitions').withPath(j);
    requireString(tr, 'fromPhase', trErrors);
    requireString(tr, 'toPhase', trErrors);

    if (Array.isArray(ot.phases)) {
      if (typeof tr.fromPhase === 'string' && !ot.phases.includes(tr.fromPhase)) {
        trErrors.push({
          field: 'fromPhase',
          message: `fromPhase "${tr.fromPhase}" not in phases`,
        });
      }
      if (typeof tr.toPhase === 'string' && !ot.phases.includes(tr.toPhase)) {
        trErrors.push({
          field: 'toPhase',
          message: `toPhase "${tr.toPhase}" not in phases`,
        });
      }
    }
  }
}

```
