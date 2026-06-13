---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/validators/manifest.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.921194+00:00
---

# core/protocol-types/src/grammar/validators/manifest.ts

```ts
/**
 * Top-level manifest validator.
 *
 * Validates the outer envelope of an extension grammar — identity
 * (grammarId / version / displayName / description / author), the
 * `extends` reference, and the `taxonomyNamespace`. Per-section
 * validators (capabilities / verbs / schemas / bindings / policy)
 * are dispatched separately by the orchestrator.
 *
 * Pure: no side effects beyond pushing to the error collector.
 */

import {
  GRAMMAR_ID_REGEX,
  SEMVER_REGEX,
} from '../constants';
import {
  ValidationErrorCollector,
  requireString,
} from '../error-collector';

/** Validate the top-level identity / metadata fields. */
export function validateManifest(
  g: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  // ── Identity strings ────────────────────────────────────────────
  requireString(g, 'metaSchemaVersion', errors);
  requireString(g, 'grammarId', errors);
  requireString(g, 'grammarVersion', errors);
  requireString(g, 'displayName', errors);
  requireString(g, 'description', errors);

  // grammarId format
  if (typeof g.grammarId === 'string' && !GRAMMAR_ID_REGEX.test(g.grammarId)) {
    errors.push({
      field: 'grammarId',
      message: `Invalid grammarId format "${g.grammarId}". Must be dot-separated lowercase segments (e.g., "com.semantos.propertyme")`,
    });
  }

  // grammarVersion semver
  if (typeof g.grammarVersion === 'string' && !SEMVER_REGEX.test(g.grammarVersion)) {
    errors.push({
      field: 'grammarVersion',
      message: `Invalid semver "${g.grammarVersion}". Expected format: N.N.N`,
    });
  }

  // ── Author ──────────────────────────────────────────────────────
  if (!g.author || typeof g.author !== 'object') {
    errors.push({ field: 'author', message: 'Missing or invalid author object' });
  } else {
    const authorErrors = errors.withPath('author');
    const author = g.author as Record<string, unknown>;
    requireString(author, 'certId', authorErrors);
    requireString(author, 'name', authorErrors);
  }

  // ── Extends (optional) ──────────────────────────────────────────
  if (g.extends !== undefined) {
    if (!g.extends || typeof g.extends !== 'object') {
      errors.push({ field: 'extends', message: 'extends must be an object if provided' });
    } else {
      const extErrors = errors.withPath('extends');
      const ext = g.extends as Record<string, unknown>;
      requireString(ext, 'grammarId', extErrors);
      requireString(ext, 'versionRange', extErrors);
    }
  }

  // ── Taxonomy Namespace ──────────────────────────────────────────
  requireString(g, 'taxonomyNamespace', errors);
}

/** Validate optional `migrations[]` array. */
export function validateMigrations(
  g: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  if (g.migrations === undefined) return;
  if (!Array.isArray(g.migrations)) {
    errors.push({
      field: 'migrations',
      message: 'migrations must be an array if provided',
    });
    return;
  }
  for (let i = 0; i < g.migrations.length; i++) {
    validateMigration(
      g.migrations[i] as Record<string, unknown>,
      errors.withPath('migrations').withPath(i),
    );
  }
}

function validateMigration(
  mig: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  if (!mig || typeof mig !== 'object') {
    errors.push({ message: 'migration must be an object' });
    return;
  }
  requireString(mig, 'fromVersion', errors);
  requireString(mig, 'toVersion', errors);

  if (typeof mig.fromVersion === 'string' && !SEMVER_REGEX.test(mig.fromVersion)) {
    errors.push({
      field: 'fromVersion',
      message: `Invalid semver "${mig.fromVersion}"`,
    });
  }
  if (typeof mig.toVersion === 'string' && !SEMVER_REGEX.test(mig.toVersion)) {
    errors.push({
      field: 'toVersion',
      message: `Invalid semver "${mig.toVersion}"`,
    });
  }
}

```
