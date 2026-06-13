---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/inference/swagger-ingester.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.461704+00:00
---

# packages/extraction/src/inference/swagger-ingester.ts

```ts
/**
 * G-4 — Swagger/OpenAPI ingester.
 *
 * Builds an EntityGraph from a static OpenAPI 3.x spec document.
 * This is the alternative input path to the live API probe runner (G-3).
 * Both paths produce the same EntityGraph shape; downstream stages are
 * agnostic about which path was used.
 *
 * Entity extraction strategy:
 *   - Each schema that appears as a GET response body → entity node
 *   - Schema properties → InferredField entries (types mapped from JSON Schema)
 *   - $ref chains → belongs_to/has_one/has_many relationships (max depth 2)
 *   - allOf compositions → fields merged into a single entity
 *
 * The ingester stops $ref chains at depth 2 to avoid combinatorial
 * explosion. Residual ambiguity is resolved by the Pask TaxonomyMapper.
 *
 * See docs/textbook/33-automated-grammar-synthesis.md §Stage 1 (Swagger)
 */

import { analyzeStructure } from './structure-analyzer';
import type { EntityGraph, RawResponse } from './types';

// ---------------------------------------------------------------------------
// OpenAPI 3.x minimal type surface (we only parse what we need)
// ---------------------------------------------------------------------------

interface OpenAPISchema {
  type?: string;
  format?: string;
  properties?: Record<string, OpenAPISchema>;
  items?: OpenAPISchema;
  allOf?: OpenAPISchema[];
  $ref?: string;
  enum?: unknown[];
  description?: string;
  required?: string[];
  nullable?: boolean;
  example?: unknown;
}

interface OpenAPIResponse {
  description?: string;
  content?: Record<string, { schema?: OpenAPISchema }>;
}

interface OpenAPIOperation {
  operationId?: string;
  summary?: string;
  responses?: Record<string, OpenAPIResponse>;
  parameters?: Array<{ name: string; in: string; schema?: OpenAPISchema }>;
  tags?: string[];
}

interface OpenAPIPath {
  get?: OpenAPIOperation;
  post?: OpenAPIOperation;
  put?: OpenAPIOperation;
  delete?: OpenAPIOperation;
}

export interface OpenAPIObject {
  openapi?: string;
  info?: { title?: string; version?: string };
  paths?: Record<string, OpenAPIPath>;
  components?: {
    schemas?: Record<string, OpenAPISchema>;
  };
}

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------

export interface SwaggerIngesterOptions {
  /** The OpenAPI document (pre-parsed). */
  spec: OpenAPIObject;
  /** Optional source URL for the spec (for provenance). */
  sourceUrl?: string;
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

/**
 * Ingest an OpenAPI spec and return an EntityGraph.
 *
 * The ingester converts each GET response schema into a synthetic
 * RawResponse, then passes the collection to StructureAnalyzer — the
 * same code path as the live probe runner.
 */
export function ingestSwagger(options: SwaggerIngesterOptions): EntityGraph {
  const { spec, sourceUrl } = options;
  const synthResponses: RawResponse[] = [];

  if (!spec.paths) return analyzeStructure([]);

  // Walk all GET operations and extract response body schemas
  for (const [pathStr, pathItem] of Object.entries(spec.paths)) {
    const operation = pathItem.get;
    if (!operation) continue;

    const schema = extractSuccessSchema(operation, spec);
    if (!schema) continue;

    // Materialise the schema into a synthetic JSON sample
    const sample = schemaToPseudoSample(schema, spec, 0);
    if (sample === null || typeof sample !== 'object') continue;

    // Wrap in a list if the response is an array
    const body = Array.isArray(sample) ? sample : [sample];

    synthResponses.push({
      url: sourceUrl ? `${sourceUrl}${pathStr}` : pathStr,
      statusCode: 200,
      sampledAt: new Date().toISOString(),
      body,
    });
  }

  return analyzeStructure(synthResponses);
}

// ---------------------------------------------------------------------------
// Schema extraction helpers
// ---------------------------------------------------------------------------

function extractSuccessSchema(op: OpenAPIOperation, spec: OpenAPIObject): OpenAPISchema | null {
  if (!op.responses) return null;

  // Look for 200 or 2xx response
  for (const code of ['200', '201', '2XX', 'default']) {
    const resp = op.responses[code];
    if (!resp?.content) continue;

    for (const mediaType of Object.values(resp.content)) {
      if (mediaType.schema) {
        return resolveRef(mediaType.schema, spec, 0);
      }
    }
  }
  return null;
}

/**
 * Resolve a $ref to its target schema. Stops at depth 2 to avoid loops.
 */
function resolveRef(schema: OpenAPISchema, spec: OpenAPIObject, depth: number): OpenAPISchema {
  if (!schema.$ref || depth > 2) return schema;

  const refPath = schema.$ref.replace('#/', '').split('/');
  let current: unknown = spec;
  for (const segment of refPath) {
    if (typeof current === 'object' && current !== null && segment in (current as Record<string, unknown>)) {
      current = (current as Record<string, unknown>)[segment];
    } else {
      return schema; // unresolvable $ref — return original
    }
  }
  return resolveRef(current as OpenAPISchema, spec, depth + 1);
}

/**
 * Convert a schema to a pseudo-sample JSON value that StructureAnalyzer
 * can parse. Uses enum values and examples where available; otherwise
 * generates plausible placeholder values by type.
 */
function schemaToPseudoSample(schema: OpenAPISchema, spec: OpenAPIObject, depth: number): unknown {
  if (depth > 2) return null;

  const resolved = resolveRef(schema, spec, 0);

  // allOf: merge all sub-schemas
  if (resolved.allOf) {
    const merged: Record<string, unknown> = {};
    for (const sub of resolved.allOf) {
      const subResolved = resolveRef(sub, spec, 0);
      const subSample = schemaToPseudoSample(subResolved, spec, depth + 1);
      if (subSample && typeof subSample === 'object' && !Array.isArray(subSample)) {
        Object.assign(merged, subSample);
      }
    }
    return merged;
  }

  // Array: generate a 2-element sample array
  if (resolved.type === 'array' || resolved.items) {
    const itemSchema = resolved.items ?? {};
    return [
      schemaToPseudoSample(itemSchema, spec, depth + 1),
      schemaToPseudoSample(itemSchema, spec, depth + 1),
    ].filter(Boolean);
  }

  // Object: generate field samples
  if (resolved.type === 'object' || resolved.properties) {
    const obj: Record<string, unknown> = {};
    for (const [fieldName, fieldSchema] of Object.entries(resolved.properties ?? {})) {
      obj[fieldName] = fieldValueSample(fieldName, resolveRef(fieldSchema, spec, 0));
    }
    return obj;
  }

  // Use example if provided
  if (resolved.example !== undefined) return resolved.example;

  // Scalar fallback
  return scalarSample(resolved);
}

function fieldValueSample(name: string, schema: OpenAPISchema): unknown {
  if (schema.example !== undefined) return schema.example;
  if (schema.enum && schema.enum.length > 0) return schema.enum[0];

  const fmt = schema.format ?? '';
  const lname = name.toLowerCase();

  if (fmt === 'date-time' || lname.endsWith('_at') || lname.endsWith('_time') || lname === 'timestamp') {
    return '2026-05-09T10:00:00Z';
  }
  if (fmt === 'date' || lname.endsWith('_date') || lname === 'date') {
    return '2026-05-09';
  }
  if (fmt === 'uuid' || lname === 'id' || lname.endsWith('_id')) {
    return '00000000-0000-0000-0000-000000000001';
  }
  if (schema.type === 'integer' || schema.type === 'number') return 42;
  if (schema.type === 'boolean') return false;
  if (schema.type === 'string') return `sample_${name}`;

  return scalarSample(schema);
}

function scalarSample(schema: OpenAPISchema): unknown {
  switch (schema.type) {
    case 'integer':
    case 'number':  return 0;
    case 'boolean': return false;
    case 'array':   return [];
    default:        return '';
  }
}

```
