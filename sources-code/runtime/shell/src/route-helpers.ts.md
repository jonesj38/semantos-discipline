---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/route-helpers.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.368123+00:00
---

# runtime/shell/src/route-helpers.ts

```ts
/**
 * Shared helpers for route handlers — eliminates repeated boilerplate
 * for object lookup, type resolution, and structured errors.
 */

import type { ShellContext } from './types';
import type { LoomObject } from '@semantos/runtime-services';
import type { ObjectTypeDefinition } from '@semantos/protocol-types';

// ── Structured error type ────────────────────────────────────

export interface ShellError {
  error: string;
  code: string;
  details?: Record<string, unknown>;
}

export type ShellResult<T = unknown> = T | ShellError;

/** Type guard for ShellError. */
export function isShellError(value: unknown): value is ShellError {
  return (
    typeof value === 'object' &&
    value !== null &&
    'error' in value &&
    'code' in value
  );
}

// ── Object lookup ────────────────────────────────────────────

/**
 * Require an object ID and resolve it from the store.
 * Returns the object or a structured error.
 */
export function requireObject(
  ctx: ShellContext,
  objectId: string | undefined,
  verb: string,
): ShellResult<LoomObject> {
  if (!objectId) {
    return {
      error: `Verb '${verb}' requires an object ID. Usage: semantos ${verb} <object-id>`,
      code: 'MISSING_OBJECT_ID',
    };
  }

  const obj = ctx.store.getState().objects.get(objectId) ?? null;
  if (!obj) {
    return {
      error: `Object not found: ${objectId}`,
      code: 'OBJECT_NOT_FOUND',
      details: { objectId },
    };
  }

  return obj;
}

// ── Type lookup ──────────────────────────────────────────────

/**
 * Resolve a type path to an ObjectTypeDefinition.
 * Searches by short name then by full category.name path.
 */
export function requireType(
  ctx: ShellContext,
  typePath: string | undefined,
  verb: string,
): ShellResult<ObjectTypeDefinition> {
  if (!typePath) {
    return {
      error: `Verb '${verb}' requires a type path. Usage: semantos ${verb} <type-path>`,
      code: 'MISSING_TYPE_PATH',
    };
  }

  const config = ctx.config.getConfig();
  if (!config) {
    return {
      error: 'No extension config loaded',
      code: 'NO_CONFIG',
    };
  }

  const segments = typePath.split('.');
  const typeName = segments[segments.length - 1];

  // Try short name match first
  for (const typeDef of config.objectTypes) {
    if (typeDef.name.toLowerCase() === typeName.toLowerCase()) {
      return typeDef;
    }
  }

  // Try full category.name match
  for (const typeDef of config.objectTypes) {
    const fullPath = typeDef.category
      ? `${typeDef.category}.${typeDef.name}`.toLowerCase()
      : typeDef.name.toLowerCase();
    if (fullPath === typePath.toLowerCase()) {
      return typeDef;
    }
  }

  const available = config.objectTypes.map(t => t.name).join(', ');
  return {
    error: `Unknown type '${typePath}'. Available types: ${available}`,
    code: 'UNKNOWN_TYPE',
    details: { typePath, available: config.objectTypes.map(t => t.name) },
  };
}

```
