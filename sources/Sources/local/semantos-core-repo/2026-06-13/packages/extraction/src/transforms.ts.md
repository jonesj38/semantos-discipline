---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/transforms.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.452026+00:00
---

# packages/extraction/src/transforms.ts

```ts
/**
 * Field transform engine — pure functions for each FieldTransformType.
 *
 * All transforms are declarative and side-effect-free.
 * The 'compute' type is constrained to basic arithmetic on source fields.
 */

import type { FieldTransform } from '@semantos/protocol-types';

/** Apply a single field transform to a value. */
export function applyTransform(
  value: unknown,
  transform: FieldTransform,
  sourceRecord: Record<string, unknown>,
): unknown {
  switch (transform.type) {
    case 'concat':
      return applyConcat(transform.parts ?? [], sourceRecord);
    case 'split':
      return applySplit(value, transform.delimiter ?? ',');
    case 'lookup':
      return applyLookup(value, transform.lookupTable ?? {});
    case 'template':
      return applyTemplate(transform.template ?? '', sourceRecord);
    case 'lowercase':
      return typeof value === 'string' ? value.toLowerCase() : value;
    case 'uppercase':
      return typeof value === 'string' ? value.toUpperCase() : value;
    case 'trim':
      return typeof value === 'string' ? value.trim() : value;
    case 'map_enum':
      return applyMapEnum(value, transform.enumMap ?? {});
    case 'compute':
      return applyCompute(transform.expression ?? '', sourceRecord);
    default:
      return value;
  }
}

/** Concat: join source fields and/or literals. */
function applyConcat(
  parts: (string | { literal: string })[],
  sourceRecord: Record<string, unknown>,
): string {
  return parts
    .map(part => {
      if (typeof part === 'string') {
        // It's a source field reference
        return String(resolveNestedField(sourceRecord, part) ?? '');
      }
      // It's a literal
      return part.literal;
    })
    .join('');
}

/** Split: split on delimiter, return array. */
function applySplit(value: unknown, delimiter: string): string[] {
  if (typeof value !== 'string') return [];
  return value.split(delimiter).map(s => s.trim());
}

/** Lookup: map value via lookup table. */
function applyLookup(value: unknown, table: Record<string, string>): string {
  const key = String(value);
  return table[key] ?? key;
}

/** Template: mustache-style {{field}} substitution. */
function applyTemplate(template: string, sourceRecord: Record<string, unknown>): string {
  return template.replace(/\{\{([^}]+)\}\}/g, (_match, fieldPath: string) => {
    const resolved = resolveNestedField(sourceRecord, fieldPath.trim());
    return resolved !== undefined ? String(resolved) : '';
  });
}

/** Enum map: source enum value → target enum value. */
function applyMapEnum(value: unknown, enumMap: Record<string, string>): string {
  const key = String(value);
  return enumMap[key] ?? key;
}

/**
 * Compute: constrained arithmetic expression.
 * Only allows: source.<field> references, numeric literals, and +,-,*,/ operators.
 */
function applyCompute(expression: string, sourceRecord: Record<string, unknown>): number {
  // Validate expression safety
  const SAFE_COMPUTE = /^(\s*(source\.[a-zA-Z_][a-zA-Z0-9_]*|\d+(\.\d+)?)\s*([+\-*/]\s*(source\.[a-zA-Z_][a-zA-Z0-9_]*|\d+(\.\d+)?)\s*)*)$/;
  if (!SAFE_COMPUTE.test(expression)) {
    throw new Error(`Unsafe compute expression: ${expression}`);
  }

  // Replace source.<field> references with values
  const resolved = expression.replace(/source\.([a-zA-Z_][a-zA-Z0-9_]*)/g, (_match, field: string) => {
    const val = sourceRecord[field];
    return typeof val === 'number' ? String(val) : '0';
  });

  // Evaluate simple arithmetic
  return evaluateArithmetic(resolved);
}

/** Evaluate a simple arithmetic expression with +, -, *, /. */
function evaluateArithmetic(expr: string): number {
  const tokens = tokenize(expr);
  return parseExpression(tokens, { pos: 0 });
}

function tokenize(expr: string): string[] {
  const tokens: string[] = [];
  let i = 0;
  while (i < expr.length) {
    if (expr[i] === ' ') { i++; continue; }
    if ('+-*/'.includes(expr[i])) {
      tokens.push(expr[i]);
      i++;
    } else {
      let num = '';
      while (i < expr.length && (expr[i] >= '0' && expr[i] <= '9' || expr[i] === '.')) {
        num += expr[i];
        i++;
      }
      if (num) tokens.push(num);
    }
  }
  return tokens;
}

function parseExpression(tokens: string[], ctx: { pos: number }): number {
  let left = parseTerm(tokens, ctx);
  while (ctx.pos < tokens.length && (tokens[ctx.pos] === '+' || tokens[ctx.pos] === '-')) {
    const op = tokens[ctx.pos++];
    const right = parseTerm(tokens, ctx);
    left = op === '+' ? left + right : left - right;
  }
  return left;
}

function parseTerm(tokens: string[], ctx: { pos: number }): number {
  let left = parseFactor(tokens, ctx);
  while (ctx.pos < tokens.length && (tokens[ctx.pos] === '*' || tokens[ctx.pos] === '/')) {
    const op = tokens[ctx.pos++];
    const right = parseFactor(tokens, ctx);
    left = op === '*' ? left * right : (right !== 0 ? left / right : 0);
  }
  return left;
}

function parseFactor(tokens: string[], ctx: { pos: number }): number {
  if (ctx.pos >= tokens.length) return 0;
  return parseFloat(tokens[ctx.pos++]) || 0;
}

// ── Nested Field Resolution ─────────────────────────────────────

/** Resolve a dot-notation path into a nested object. */
export function resolveNestedField(obj: unknown, dotPath: string): unknown {
  const segments = dotPath.split('.');
  let current: unknown = obj;

  for (const seg of segments) {
    if (current === null || current === undefined) return undefined;
    if (typeof current !== 'object') return undefined;
    current = (current as Record<string, unknown>)[seg];
  }

  return current;
}

/** Extract records from a response body using a JSONPath-like dataPath. */
export function extractRecordsFromResponse(
  body: unknown,
  dataPath: string,
): unknown[] {
  // Strip leading "$." if present (e.g., "$.data.properties" → "data.properties")
  const cleanPath = dataPath.startsWith('$.') ? dataPath.slice(2) : dataPath;

  const data = resolveNestedField(body, cleanPath);

  if (Array.isArray(data)) return data;
  if (data !== null && data !== undefined) return [data];
  return [];
}

```
