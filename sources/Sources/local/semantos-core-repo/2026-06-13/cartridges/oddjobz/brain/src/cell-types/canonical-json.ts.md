---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/canonical-json.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.506558+00:00
---

# cartridges/oddjobz/brain/src/cell-types/canonical-json.ts

```ts
/**
 * Canonical JSON encoder — produces byte-identical UTF-8 output for
 * structurally-equal values. Required for round-trip determinism on
 * cell payloads: pack → unpack → pack MUST be byte-equal, regardless
 * of insertion-order quirks of `JSON.stringify` over plain objects.
 *
 * Rules:
 *   - object keys are emitted in lexicographic order
 *   - numbers are emitted via `Number.prototype.toString` (the IEEE-754
 *     round-trip form); NaN and Infinity are rejected
 *   - strings use the standard JSON escape grammar (`\\`, `\"`, `\n`,
 *     `\r`, `\t`, `\b`, `\f`, and `\uXXXX` for control chars < 0x20)
 *   - undefined values inside objects/arrays are rejected (vs JSON's
 *     silently-drop semantics) — this keeps pack/unpack symmetric
 *   - Date is rejected; callers must serialise to ISO-8601 strings or
 *     epoch-millis numbers explicitly
 *   - bigints are rejected (forces explicit decimal-string encoding
 *     where a domain calls for them; cell payloads stay schema-typed)
 *
 * The encoding round-trips through `JSON.parse` for plain JSON inputs
 * (no Date / bigint / undefined), which keeps unpack a one-liner.
 */

export type CanonicalValue =
  | null
  | boolean
  | number
  | string
  | readonly CanonicalValue[]
  | { readonly [k: string]: CanonicalValue };

/**
 * Encode a value to a canonical UTF-8 byte sequence.
 *
 * Throws if the input contains non-finite numbers, undefined leaves,
 * Date, bigint, or Symbol.
 */
export function encodeCanonicalJson(value: CanonicalValue): Uint8Array {
  const text = stringify(value);
  return new TextEncoder().encode(text);
}

/**
 * Decode a canonical-JSON byte sequence back into a value. The result
 * is structurally identical to the input passed to `encodeCanonicalJson`
 * (subject to the schema contract — typed-cell unpack functions cast
 * back to their declared shapes).
 */
export function decodeCanonicalJson(bytes: Uint8Array): CanonicalValue {
  const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  return JSON.parse(text) as CanonicalValue;
}

function stringify(value: CanonicalValue): string {
  if (value === null) return 'null';
  if (typeof value === 'boolean') return value ? 'true' : 'false';
  if (typeof value === 'number') {
    if (!Number.isFinite(value)) {
      throw new Error(`canonical-json: non-finite number not allowed: ${value}`);
    }
    return numberToCanonical(value);
  }
  if (typeof value === 'string') return stringToCanonical(value);
  if (Array.isArray(value)) {
    const parts: string[] = [];
    for (const item of value) {
      if (item === undefined) {
        throw new Error('canonical-json: undefined element not allowed in array');
      }
      parts.push(stringify(item));
    }
    return `[${parts.join(',')}]`;
  }
  if (typeof value === 'object') {
    const obj = value as { readonly [k: string]: CanonicalValue };
    const keys = Object.keys(obj).sort();
    const parts: string[] = [];
    for (const k of keys) {
      const v = obj[k];
      if (v === undefined) {
        throw new Error(`canonical-json: undefined value at key ${JSON.stringify(k)}`);
      }
      parts.push(`${stringToCanonical(k)}:${stringify(v)}`);
    }
    return `{${parts.join(',')}}`;
  }
  // Reject bigint, symbol, function, Date
  if (typeof value === 'bigint') {
    throw new Error('canonical-json: bigint not allowed; use a decimal string');
  }
  if (typeof value === 'undefined') {
    throw new Error('canonical-json: undefined not allowed');
  }
  throw new Error(`canonical-json: unsupported value of typeof ${typeof value}`);
}

function numberToCanonical(n: number): string {
  // -0 must serialise as 0 (JSON.parse can't recover -0 anyway)
  if (Object.is(n, -0)) return '0';
  return n.toString();
}

function stringToCanonical(s: string): string {
  let out = '"';
  for (let i = 0; i < s.length; i++) {
    const code = s.charCodeAt(i);
    switch (code) {
      case 0x22: out += '\\"'; break;        // "
      case 0x5c: out += '\\\\'; break;       // \
      case 0x08: out += '\\b'; break;
      case 0x09: out += '\\t'; break;
      case 0x0a: out += '\\n'; break;
      case 0x0c: out += '\\f'; break;
      case 0x0d: out += '\\r'; break;
      default:
        if (code < 0x20) {
          out += `\\u${code.toString(16).padStart(4, '0')}`;
        } else {
          out += s.charAt(i);
        }
    }
  }
  out += '"';
  return out;
}

```
