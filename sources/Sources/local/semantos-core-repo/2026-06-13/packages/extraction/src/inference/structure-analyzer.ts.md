---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/inference/structure-analyzer.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.464588+00:00
---

# packages/extraction/src/inference/structure-analyzer.ts

```ts
/**
 * D36C.1 — Structure Analyzer
 *
 * Deterministic parsing of raw API responses into an EntityGraph.
 * Detects entity boundaries, field types, cardinality, relationships,
 * ID/timestamp fields, and enum fields. No LLM calls.
 *
 * Every inference step produces a confidence score (0.0–1.0).
 */

import type {
  RawResponse,
  EntityGraph,
  Entity,
  InferredField,
  EntityRelationship,
} from './types';

// ── Detection Patterns ─────────────────────────────────────────

const ID_FIELD_PATTERN = /^_?id$|_id$/;
const TIMESTAMP_FIELD_PATTERN = /^created|^updated|_at$|_time$|^timestamp$/;
const ISO_8601_DATE = /^\d{4}-\d{2}-\d{2}$/;
const ISO_8601_DATETIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const UNIX_TIMESTAMP_RANGE = { min: 946684800, max: 2524608000 }; // 2000-01-01 to 2050-01-01

/** Maximum enum cardinality — string fields with more unique values are not enums. */
const MAX_ENUM_CARDINALITY = 10;

/** Nesting depth warning threshold. */
const MAX_NESTING_DEPTH = 4;

// ── Main Entry Point ───────────────────────────────────────────

/**
 * Analyze raw API responses and detect entity boundaries, field types,
 * nesting, cardinality, and relationships.
 *
 * Completely deterministic — no LLM calls.
 */
export function analyzeStructure(responses: RawResponse[]): EntityGraph {
  if (responses.length === 0) {
    return { nodes: [], edges: [], nestedPaths: {} };
  }

  // Extract entity object arrays from each response
  const entityArrays = new Map<string, unknown[][]>();
  const nestedPaths: Record<string, string[]> = {};

  for (const response of responses) {
    // Seed the path from the URL's last path segment so that top-level
    // arrays from different endpoints get distinct entity IDs.
    const urlSeedPath = urlLastSegment(response.url);
    const detected = detectEntityArrays(response.body, urlSeedPath, 0);
    for (const { path, entityId, objects, depth } of detected) {
      if (!entityArrays.has(entityId)) {
        entityArrays.set(entityId, []);
      }
      entityArrays.get(entityId)!.push(objects);

      if (!nestedPaths[path]) {
        nestedPaths[path] = [];
      }
      if (!nestedPaths[path].includes(entityId)) {
        nestedPaths[path].push(entityId);
      }
    }
  }

  // If no arrays of objects found, treat the root as a single entity
  if (entityArrays.size === 0) {
    for (const response of responses) {
      if (isPlainObject(response.body)) {
        const entityId = 'root';
        if (!entityArrays.has(entityId)) {
          entityArrays.set(entityId, []);
        }
        entityArrays.get(entityId)!.push([response.body]);
      }
    }
  }

  // Build entities from collected samples
  const entities: Entity[] = [];
  for (const [entityId, sampleArrays] of entityArrays) {
    const allObjects = sampleArrays.flat();
    if (allObjects.length === 0) continue;

    const fields = inferFields(allObjects);
    const nestingLevel = computeNestingLevel(entityId, nestedPaths);

    entities.push({
      id: entityId,
      displayName: toDisplayName(entityId),
      fields,
      nestingLevel,
      sampleCount: sampleArrays.length,
    });
  }

  // Detect relationships between entities
  const edges = detectRelationships(entities);

  return { nodes: entities, edges, nestedPaths };
}

// ── Entity Detection ───────────────────────────────────────────

interface DetectedArray {
  path: string;
  entityId: string;
  objects: unknown[];
  depth: number;
}

/**
 * Walk a JSON tree looking for arrays of similar objects (entity boundaries).
 * Also detects paginated responses with a `data` field.
 */
function detectEntityArrays(
  value: unknown,
  path: string,
  depth: number,
): DetectedArray[] {
  if (depth > MAX_NESTING_DEPTH + 2) return [];
  const results: DetectedArray[] = [];

  if (Array.isArray(value)) {
    const objects = value.filter(isPlainObject);
    if (objects.length >= 1 && objects.length === value.length) {
      // All elements are objects — this is an entity array
      const entityId = inferEntityIdFromPath(path);
      results.push({ path, entityId, objects, depth });
    }
    return results;
  }

  if (!isPlainObject(value)) return results;

  const obj = value as Record<string, unknown>;

  // Check for paginated response pattern: { data: [...], next_cursor, total_count }
  if ('data' in obj && Array.isArray(obj.data)) {
    const objects = (obj.data as unknown[]).filter(isPlainObject);
    if (objects.length >= 1) {
      const entityId = inferEntityIdFromPath(path || 'data');
      results.push({ path: path ? `${path}.data` : 'data', entityId, objects, depth });
    }
    return results;
  }

  // Check for named data fields: { properties: [...], leases: [...] }
  for (const [key, val] of Object.entries(obj)) {
    if (Array.isArray(val)) {
      const objects = val.filter(isPlainObject);
      if (objects.length >= 1 && objects.length === val.length) {
        const childPath = path ? `${path}.${key}` : key;
        const entityId = singularize(key);
        results.push({ path: childPath, entityId, objects, depth: depth + 1 });
      }
    } else if (isPlainObject(val)) {
      // Recurse into nested objects
      const childPath = path ? `${path}.${key}` : key;
      results.push(...detectEntityArrays(val, childPath, depth + 1));
    }
  }

  return results;
}

// ── Field Inference ────────────────────────────────────────────

/**
 * Infer field types, required/optional, and special field roles from
 * a collection of entity objects.
 */
function inferFields(objects: unknown[]): InferredField[] {
  if (objects.length === 0) return [];

  // Collect all field names across all objects
  const fieldNames = new Set<string>();
  for (const obj of objects) {
    if (isPlainObject(obj)) {
      for (const key of Object.keys(obj as Record<string, unknown>)) {
        fieldNames.add(key);
      }
    }
  }

  const fields: InferredField[] = [];

  for (const name of fieldNames) {
    const values: unknown[] = [];
    let presentCount = 0;

    for (const obj of objects) {
      const record = obj as Record<string, unknown>;
      if (name in record) {
        presentCount++;
        if (record[name] != null) {
          values.push(record[name]);
        }
      }
    }

    const required = presentCount === objects.length;
    const { type, confidence, cardinality, enumValues } = inferFieldType(name, values);

    // Collect first 3 non-null sample values
    const sampleValues = values.slice(0, 3);

    fields.push({
      name,
      type,
      required,
      cardinality,
      enumValues,
      sampleValues,
      detectionConfidence: confidence,
    });
  }

  return fields;
}

interface TypeInference {
  type: string;
  confidence: number;
  cardinality?: { min: number; max: number };
  enumValues?: string[];
}

/**
 * Infer the type of a field from its observed values.
 * Uses the most frequent non-null type and heuristics for dates, enums, etc.
 */
function inferFieldType(fieldName: string, values: unknown[]): TypeInference {
  if (values.length === 0) {
    return { type: 'string', confidence: 0.0 };
  }

  // Count type occurrences
  const typeCounts = new Map<string, number>();
  const uniqueStringValues = new Set<string>();
  let arrayMinLen = Infinity;
  let arrayMaxLen = 0;

  for (const val of values) {
    const t = detectValueType(fieldName, val);
    typeCounts.set(t, (typeCounts.get(t) ?? 0) + 1);

    if (typeof val === 'string') {
      uniqueStringValues.add(val);
    }
    if (Array.isArray(val)) {
      arrayMinLen = Math.min(arrayMinLen, val.length);
      arrayMaxLen = Math.max(arrayMaxLen, val.length);
    }
  }

  // Find the most frequent type
  let bestType = 'string';
  let bestCount = 0;
  for (const [t, count] of typeCounts) {
    if (count > bestCount) {
      bestType = t;
      bestCount = count;
    }
  }

  const confidence = bestCount / values.length;

  const result: TypeInference = { type: bestType, confidence };

  // Check for enum: string field with small cardinality.
  // Must have at least 2 values AND the cardinality must be less than the sample count
  // (if every value is unique, it's not an enum — it's a free-form string).
  if (bestType === 'string' &&
      uniqueStringValues.size <= MAX_ENUM_CARDINALITY &&
      uniqueStringValues.size >= 2 &&
      uniqueStringValues.size < values.length) {
    result.type = 'enum';
    result.enumValues = [...uniqueStringValues].sort();
  }

  // Add cardinality for arrays
  if (bestType === 'array') {
    result.cardinality = {
      min: arrayMinLen === Infinity ? 0 : arrayMinLen,
      max: arrayMaxLen,
    };
  }

  return result;
}

/**
 * Detect the type of a single value, considering field name heuristics.
 */
function detectValueType(fieldName: string, value: unknown): string {
  if (value === null || value === undefined) return 'string';

  if (typeof value === 'boolean') return 'boolean';
  if (typeof value === 'number') {
    // Check for Unix timestamp
    if (TIMESTAMP_FIELD_PATTERN.test(fieldName) &&
        value > UNIX_TIMESTAMP_RANGE.min &&
        value < UNIX_TIMESTAMP_RANGE.max) {
      return 'datetime';
    }
    return 'number';
  }

  if (typeof value === 'string') {
    // Check for datetime first (more specific)
    if (ISO_8601_DATETIME.test(value)) return 'datetime';
    // Then date
    if (ISO_8601_DATE.test(value)) return 'date';
    return 'string';
  }

  if (Array.isArray(value)) return 'array';
  if (isPlainObject(value)) return 'object';

  return 'string';
}

// ── Relationship Detection ─────────────────────────────────────

/**
 * Detect relationships between entities by looking for foreign key patterns
 * and embedded arrays.
 */
function detectRelationships(entities: Entity[]): EntityRelationship[] {
  const edges: EntityRelationship[] = [];
  const entityIds = new Set(entities.map(e => e.id));

  for (const entity of entities) {
    for (const field of entity.fields) {
      // Check for foreign key: field named <entity>_id matching another entity
      if (field.name.endsWith('_id') && field.name !== 'id') {
        const refEntityId = field.name.slice(0, -3); // strip _id
        if (entityIds.has(refEntityId)) {
          edges.push({
            source: entity.id,
            target: refEntityId,
            type: 'belongs_to',
            foreignKey: field.name,
            confidence: 0.9,
          });
        } else {
          // Foreign key to unknown entity — lower confidence
          edges.push({
            source: entity.id,
            target: refEntityId,
            type: 'belongs_to',
            foreignKey: field.name,
            confidence: 0.5,
          });
        }
      }

      // Check for has_many: array field whose name matches another entity (plural)
      if (field.type === 'array' || field.type === 'object') {
        const singularName = singularize(field.name);
        if (entityIds.has(singularName) && singularName !== entity.id) {
          edges.push({
            source: entity.id,
            target: singularName,
            type: 'has_many',
            foreignKey: `${entity.id}_id`,
            confidence: 0.7,
          });
        }
      }
    }
  }

  return edges;
}

// ── Utilities ──────────────────────────────────────────────────

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

/**
 * Extract a path-friendly seed from a URL's last non-empty segment.
 * E.g. "https://api.example.com/properties" → "properties"
 *      "/v1/tenancies" → "tenancies"
 * Returns empty string if no useful segment is found.
 */
function urlLastSegment(url: string | undefined): string {
  if (!url) return '';
  try {
    // Handle both full URLs and bare paths
    const pathname = url.startsWith('http') ? new URL(url).pathname : url;
    const segments = pathname.split('/').filter(Boolean);
    // Skip version segments like v1, v2, api
    const useful = segments.filter(s => !/^(v\d+|api)$/i.test(s));
    return useful[useful.length - 1] ?? '';
  } catch {
    return '';
  }
}

/** Infer entity ID from a JSON path. */
function inferEntityIdFromPath(path: string): string {
  const segments = path.split('.');
  const last = segments[segments.length - 1] || 'entity';
  return singularize(last);
}

/** Naive singularize: strip trailing 's' if present. */
function singularize(word: string): string {
  if (word.endsWith('ies')) return word.slice(0, -3) + 'y';
  if (word.endsWith('sses')) return word.slice(0, -2); // "dresses" → "dress"
  if (word.endsWith('ches') || word.endsWith('shes') || word.endsWith('xes') || word.endsWith('zes')) {
    return word.slice(0, -2); // "watches" → "watch"
  }
  if (word.endsWith('s') && !word.endsWith('ss') && !word.endsWith('us')) return word.slice(0, -1);
  return word;
}

/** Convert snake_case or camelCase to Title Case. */
function toDisplayName(id: string): string {
  return id
    .replace(/_/g, ' ')
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/\b\w/g, c => c.toUpperCase());
}

/** Compute nesting level from nested paths. */
function computeNestingLevel(entityId: string, nestedPaths: Record<string, string[]>): number {
  for (const [path, entities] of Object.entries(nestedPaths)) {
    if (entities.includes(entityId)) {
      return path.split('.').length - 1;
    }
  }
  return 0;
}

```
