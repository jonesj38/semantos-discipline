---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/validators/policy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.923578+00:00
---

# core/protocol-types/src/grammar/validators/policy.ts

```ts
/**
 * Policy section validator (taxonomyExtensions).
 *
 * Each `taxonomyExtension` declares a policy/governance subtree under
 * one of the four taxonomy axes (what / how / why / where) — the
 * grammar's contribution to the global policy taxonomy. The validator
 * checks the axis is one of the allowed four, that nodes have proper
 * shape, and recurses into children.
 *
 * Pure: never mutates input.
 */

import {
  VALID_TAXONOMY_AXES,
} from '../constants';
import {
  ValidationErrorCollector,
  requireString,
} from '../error-collector';

export function validatePolicySection(
  g: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  if (g.taxonomyExtensions === undefined) return;
  if (!Array.isArray(g.taxonomyExtensions)) {
    errors.push({
      field: 'taxonomyExtensions',
      message: 'taxonomyExtensions must be an array if provided',
    });
    return;
  }
  for (let i = 0; i < g.taxonomyExtensions.length; i++) {
    validateTaxonomyExtension(
      g.taxonomyExtensions[i] as Record<string, unknown>,
      errors.withPath('taxonomyExtensions').withPath(i),
    );
  }
}

function validateTaxonomyExtension(
  te: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  if (!te || typeof te !== 'object') {
    errors.push({ message: 'taxonomyExtension must be an object' });
    return;
  }

  if (typeof te.axis !== 'string' || !VALID_TAXONOMY_AXES.has(te.axis)) {
    errors.push({
      field: 'axis',
      message: `Invalid taxonomy axis "${te.axis}". Must be one of: ${[...VALID_TAXONOMY_AXES].join(', ')}`,
    });
  }

  requireString(te, 'parentPath', errors);

  if (!Array.isArray(te.nodes) || te.nodes.length === 0) {
    errors.push({
      field: 'nodes',
      message: 'nodes must be a non-empty array',
    });
    return;
  }
  for (let i = 0; i < te.nodes.length; i++) {
    validateTaxonomyNode(
      te.nodes[i] as Record<string, unknown>,
      errors.withPath('nodes').withPath(i),
    );
  }
}

function validateTaxonomyNode(
  node: Record<string, unknown>,
  errors: ValidationErrorCollector,
): void {
  if (!node || typeof node !== 'object') {
    errors.push({ message: 'taxonomy node must be an object' });
    return;
  }
  requireString(node, 'segment', errors);
  requireString(node, 'displayName', errors);
  requireString(node, 'description', errors);

  if (node.children === undefined) return;
  if (!Array.isArray(node.children)) {
    errors.push({ field: 'children', message: 'children must be an array' });
    return;
  }
  for (let i = 0; i < node.children.length; i++) {
    validateTaxonomyNode(
      node.children[i] as Record<string, unknown>,
      errors.withPath('children').withPath(i),
    );
  }
}

```
