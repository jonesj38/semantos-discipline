---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-ir/src/canonical.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.005502+00:00
---

# core/semantos-ir/src/canonical.ts

```ts
/**
 * RFC 8785 — JSON Canonicalization Scheme (JCS).
 *
 * Deterministic JSON serialization: sorted keys, no trailing commas,
 * no insignificant whitespace. Used for golden-file testing — if two
 * IR programs serialize to the same canonical JSON, they're equivalent.
 *
 * Simplified implementation covering the types used in IRProgram:
 * string, number, boolean, null, arrays, plain objects.
 */

export function canonicalize(value: unknown): string {
  if (value === null) return 'null';
  if (value === undefined) return 'null';

  const t = typeof value;

  if (t === 'boolean') return value ? 'true' : 'false';

  if (t === 'number') {
    if (!isFinite(value as number)) return 'null';
    // IEEE 754 double → string per ES2015 Number.prototype.toString()
    return String(value);
  }

  if (t === 'string') return JSON.stringify(value);

  if (Array.isArray(value)) {
    const items = value.map(canonicalize);
    return `[${items.join(',')}]`;
  }

  if (t === 'object') {
    const obj = value as Record<string, unknown>;
    // RFC 8785 §3.2.3: sort keys by UTF-16 code units (same as default JS sort)
    const keys = Object.keys(obj)
      .filter(k => obj[k] !== undefined)
      .sort();
    const pairs = keys.map(k => `${JSON.stringify(k)}:${canonicalize(obj[k])}`);
    return `{${pairs.join(',')}}`;
  }

  return 'null';
}

```
