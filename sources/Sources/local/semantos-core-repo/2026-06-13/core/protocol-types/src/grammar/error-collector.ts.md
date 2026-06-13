---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/error-collector.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.895404+00:00
---

# core/protocol-types/src/grammar/error-collector.ts

```ts
/**
 * Validation error collector with immutable path tracking.
 *
 * Each `withPath(segment)` returns a NEW collector instance that
 * shares the underlying `errors` array (writes are confined to the
 * sole `push` method below). The collector itself never mutates
 * its `path` field — that field is set once in the constructor.
 *
 * This shape lets per-section validators thread context naturally:
 *   `errors.withPath('source').push({ message, severity })`
 * without ever mutating the parent collector.
 *
 * Errors collected here are surfaced by the orchestrator in
 * `grammar-validator.ts` via `toResult()`.
 */

import type {
  GrammarValidationError,
  GrammarValidationResult,
} from '../extension-grammar';

export interface CollectorEntry {
  /** Field/segment relative to the current path (joined with `.`). */
  field?: string;
  /** Pre-built path; if provided, used verbatim. */
  path?: string;
  /** Human-readable message. */
  message: string;
  /** Severity (defaults to 'error'). */
  severity?: 'error' | 'warning';
}

/**
 * Append-only error sink. Internal — the public surface is the
 * `ValidationErrorCollector` class below.
 */
class ErrorSink {
  readonly errors: GrammarValidationError[] = [];
}

export class ValidationErrorCollector {
  private readonly sink: ErrorSink;
  /** Immutable. The path scope this collector is attached to. */
  readonly path: string;

  private constructor(sink: ErrorSink, path: string) {
    this.sink = sink;
    this.path = path;
  }

  /** Build a fresh root collector. */
  static create(): ValidationErrorCollector {
    return new ValidationErrorCollector(new ErrorSink(), '');
  }

  /**
   * Return a NEW collector scoped to `<this.path>.<segment>` (or
   * `<this.path>[segment]` if `segment` looks like an index).
   * Shares the underlying error sink.
   */
  withPath(segment: string | number): ValidationErrorCollector {
    const seg = typeof segment === 'number' ? `[${segment}]` : segment;
    const next = this.path
      ? seg.startsWith('[') ? `${this.path}${seg}` : `${this.path}.${seg}`
      : seg;
    return new ValidationErrorCollector(this.sink, next);
  }

  /**
   * Append an error to the shared sink. Never mutates `this.path`.
   * If `entry.path` is provided it is used as-is; otherwise the
   * collector's path is joined with `entry.field` (if any).
   */
  push(entry: CollectorEntry): void {
    let path: string;
    if (entry.path !== undefined) {
      path = entry.path;
    } else if (entry.field) {
      path = this.path ? `${this.path}.${entry.field}` : entry.field;
    } else {
      path = this.path;
    }
    this.sink.errors.push({
      path,
      message: entry.message,
      severity: entry.severity ?? 'error',
    });
  }

  /** Snapshot of all errors accumulated so far. */
  snapshot(): readonly GrammarValidationError[] {
    return this.sink.errors;
  }

  /** Compose into the public result shape (unchanged from legacy). */
  toResult(): GrammarValidationResult {
    const errors = [...this.sink.errors];
    const hasErrors = errors.some(e => e.severity === 'error');
    return { valid: !hasErrors, errors };
  }
}

/**
 * Helper: assert a string field exists and is non-empty, pushing a
 * standard error to the collector when missing. Reused across all
 * per-section validators.
 */
export function requireString(
  obj: Record<string, unknown>,
  field: string,
  errors: ValidationErrorCollector,
): void {
  if (typeof obj[field] !== 'string' || (obj[field] as string).length === 0) {
    errors.push({
      field,
      message: `Missing or empty required field "${field}"`,
    });
  }
}

```
