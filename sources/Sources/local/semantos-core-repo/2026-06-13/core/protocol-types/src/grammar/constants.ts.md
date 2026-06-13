---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/constants.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.896227+00:00
---

# core/protocol-types/src/grammar/constants.ts

```ts
/**
 * Constants & regex patterns used by the per-section grammar validators.
 *
 * These were extracted verbatim from the legacy
 * `extension-grammar-validator.ts` so error messages stay
 * byte-identical across the split.
 */

import type {
  CapabilityId,
  FieldTransformType,
  SourceFieldType,
} from '../extension-grammar';

export const VALID_SOURCE_PROTOCOLS = new Set([
  'rest', 'graphql', 'grpc', 'file', 'event-stream', 'database',
]);

export const VALID_AUTH_TYPES = new Set([
  'oauth2', 'api-key', 'bearer', 'basic', 'certificate', 'none',
]);

export const VALID_PAGINATION_TYPES = new Set([
  'cursor', 'offset', 'page-number', 'link-header', 'none',
]);

export const VALID_SOURCE_FIELD_TYPES = new Set<SourceFieldType>([
  'string', 'number', 'boolean', 'date', 'datetime', 'object', 'array', 'enum',
]);

export const VALID_PAYLOAD_TYPES = new Set([
  'string', 'number', 'boolean', 'date', 'datetime', 'object', 'array', 'enum',
]);

export const VALID_LINEARITY = new Set(['LINEAR', 'AFFINE', 'RELEVANT', 'FUNGIBLE']);

export const VALID_TRANSFORM_TYPES = new Set<FieldTransformType>([
  'concat', 'split', 'lookup', 'template',
  'lowercase', 'uppercase', 'trim',
  'map_enum', 'compute',
]);

export const VALID_CAPABILITY_IDS = new Set<CapabilityId>([
  'network.outbound', 'storage.write', 'storage.read',
  'identity.read', 'metering.consume', 'taxonomy.extend', 'governance.propose',
]);

export const VALID_RELATIONSHIP_TYPES = new Set([
  'has_many', 'has_one', 'belongs_to', 'many_to_many',
]);

export const VALID_CONDITION_OPERATORS = new Set([
  'eq', 'neq', 'in', 'not_in', 'exists', 'not_exists',
]);

export const VALID_TAXONOMY_AXES = new Set(['what', 'how', 'why', 'where']);

export const VALID_VISIBILITY = new Set([
  'visible', 'hidden', 'redacted_value', 'approval_required',
]);

/** Simple semver pattern: N.N.N with optional pre-release/build. */
export const SEMVER_REGEX = /^\d+\.\d+\.\d+(-[a-zA-Z0-9.]+)?(\+[a-zA-Z0-9.]+)?$/;

/** Dot-separated identifier (e.g., "com.semantos.propertyme"). */
export const GRAMMAR_ID_REGEX = /^[a-z][a-z0-9]*(\.[a-z][a-z0-9-]*)+$/;

/**
 * Constrained compute expression validator.
 * Only allows: source.<field> references, numeric literals, whitespace, and +, -, *, / operators.
 * No function calls, no string operations, no arbitrary code.
 */
export const COMPUTE_EXPRESSION_REGEX = /^(\s*(source\.[a-zA-Z_][a-zA-Z0-9_]*|\d+(\.\d+)?)\s*([+\-*/]\s*(source\.[a-zA-Z_][a-zA-Z0-9_]*|\d+(\.\d+)?)\s*)*)$/;

```
