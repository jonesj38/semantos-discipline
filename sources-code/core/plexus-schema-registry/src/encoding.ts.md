---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-schema-registry/src/encoding.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.947057+00:00
---

# core/plexus-schema-registry/src/encoding.ts

```ts
/**
 * Payload + schema encoding/decoding.
 *
 * Numerics are LITTLE-ENDIAN throughout, matching the kernel
 * (`core/cell-engine/src/constants.zig`'s u32 layout). Fields are
 * written at their declared offsets; gaps are zero-filled.
 *
 * `encodeSchema` produces a canonical byte representation used for
 * signature verification — JSON with sorted keys, no whitespace, UTF-8.
 * This is a stable, cross-implementation format intentionally tied to
 * the schema's declarative shape, not its in-memory TS form.
 */
import {
  FIELD_SIZE,
  type DomainSchema,
  type FieldDescriptor,
} from './types.js';

// ── Payload encoding ────────────────────────────────────────────────

/**
 * Encode a typed payload to bytes laid out per the schema. The result
 * has length = max(field.offset + field.size) across all fields,
 * rounded up to the next multiple of 8 (cache-friendly).
 */
export function encodePayload(
  schema: DomainSchema,
  values: Record<string, unknown>,
): Uint8Array {
  const totalSize = computePayloadSize(schema);
  const bytes = new Uint8Array(totalSize);
  const view = new DataView(bytes.buffer);

  for (const field of schema.fields) {
    if (!(field.name in values)) {
      throw new Error(
        `encodePayload: field '${field.name}' is missing from values`,
      );
    }
    writeField(view, bytes, field, values[field.name]);
  }
  return bytes;
}

/** Decode bytes back into a Record using the schema. */
export function decodePayload(
  schema: DomainSchema,
  bytes: Uint8Array,
): Record<string, unknown> {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const out: Record<string, unknown> = {};
  for (const field of schema.fields) {
    out[field.name] = readField(view, bytes, field);
  }
  return out;
}

function computePayloadSize(schema: DomainSchema): number {
  let max = 0;
  for (const f of schema.fields) {
    max = Math.max(max, f.offset + f.size);
  }
  // Pad up to the next 8-byte boundary so packed payloads align with
  // 64-bit reads in the kernel.
  return Math.ceil(max / 8) * 8;
}

function writeField(
  view: DataView,
  bytes: Uint8Array,
  field: FieldDescriptor,
  value: unknown,
): void {
  const { offset, size, type, name } = field;
  switch (type) {
    case 'u8':
      assertSize(size, 1, field);
      view.setUint8(offset, asNumber(value, name));
      return;
    case 'u16':
      assertSize(size, 2, field);
      view.setUint16(offset, asNumber(value, name), /*littleEndian*/ true);
      return;
    case 'u32':
      assertSize(size, 4, field);
      view.setUint32(offset, asNumber(value, name), true);
      return;
    case 'u64': {
      assertSize(size, 8, field);
      const big = typeof value === 'bigint' ? value : BigInt(asNumber(value, name));
      view.setBigUint64(offset, big, true);
      return;
    }
    case 'u256': {
      assertSize(size, 32, field);
      const buf = asBytes(value, name);
      if (buf.byteLength !== 32) {
        throw new Error(`field '${name}' expected 32 bytes, got ${buf.byteLength}`);
      }
      bytes.set(buf, offset);
      return;
    }
    case 'bytes': {
      const buf = asBytes(value, name);
      if (buf.byteLength > size) {
        throw new Error(
          `field '${name}': value ${buf.byteLength}B exceeds declared size ${size}B`,
        );
      }
      bytes.set(buf, offset);
      return;
    }
    case 'utf8': {
      const text = typeof value === 'string' ? value : String(value);
      const enc = new TextEncoder().encode(text);
      if (enc.byteLength > size) {
        throw new Error(
          `field '${name}': utf8 value ${enc.byteLength}B exceeds declared size ${size}B`,
        );
      }
      bytes.set(enc, offset);
      return;
    }
  }
}

function readField(view: DataView, bytes: Uint8Array, field: FieldDescriptor): unknown {
  const { offset, size, type } = field;
  switch (type) {
    case 'u8':
      return view.getUint8(offset);
    case 'u16':
      return view.getUint16(offset, true);
    case 'u32':
      return view.getUint32(offset, true);
    case 'u64':
      return view.getBigUint64(offset, true);
    case 'u256':
      return bytes.slice(offset, offset + 32);
    case 'bytes':
      return bytes.slice(offset, offset + size);
    case 'utf8': {
      const sub = bytes.slice(offset, offset + size);
      // Strip trailing NUL padding.
      let end = sub.length;
      while (end > 0 && sub[end - 1] === 0) end--;
      return new TextDecoder().decode(sub.slice(0, end));
    }
  }
}

function asNumber(value: unknown, name: string): number {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'bigint') return Number(value);
  throw new Error(`field '${name}' expected a number, got ${typeof value}`);
}

function asBytes(value: unknown, name: string): Uint8Array {
  if (value instanceof Uint8Array) return value;
  if (Array.isArray(value) && value.every((v) => typeof v === 'number')) {
    return new Uint8Array(value as number[]);
  }
  if (typeof value === 'string') {
    // Treat as hex.
    const clean = value.startsWith('0x') ? value.slice(2) : value;
    if (clean.length % 2 !== 0) {
      throw new Error(`field '${name}': hex string has odd length`);
    }
    const out = new Uint8Array(clean.length / 2);
    for (let i = 0; i < out.length; i++) {
      const byte = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
      if (Number.isNaN(byte)) {
        throw new Error(`field '${name}': invalid hex`);
      }
      out[i] = byte;
    }
    return out;
  }
  throw new Error(`field '${name}' expected bytes (Uint8Array / number[] / hex string)`);
}

function assertSize(actual: number, expected: number, field: FieldDescriptor): void {
  if (actual !== expected) {
    throw new Error(
      `field '${field.name}' of type ${field.type} declared size ${actual}, expected ${expected}`,
    );
  }
}

// ── Schema encoding (for signature) ─────────────────────────────────

/**
 * Canonical UTF-8 byte representation of a schema. Used as the
 * signature preimage. Stable across implementations:
 *   - JSON, no whitespace, sorted keys
 *   - `authority` field excluded (signature signs the unsigned schema)
 *
 * Cross-impl vector tests pin this exact format.
 */
export function encodeSchema(schema: DomainSchema): Uint8Array {
  const canonical = {
    commitmentMode: schema.commitmentMode,
    domainFlag: schema.domainFlag,
    fields: schema.fields.map((f) => ({
      name: f.name,
      offset: f.offset,
      size: f.size,
      type: f.type,
    })),
    version: schema.version,
  };
  return new TextEncoder().encode(stableStringify(canonical));
}

function stableStringify(v: unknown): string {
  if (v === null || typeof v !== 'object') return JSON.stringify(v);
  if (Array.isArray(v)) return '[' + v.map(stableStringify).join(',') + ']';
  const keys = Object.keys(v as Record<string, unknown>).sort();
  return (
    '{' +
    keys
      .map(
        (k) =>
          JSON.stringify(k) + ':' + stableStringify((v as Record<string, unknown>)[k]),
      )
      .join(',') +
    '}'
  );
}

// ── Structural validation ───────────────────────────────────────────

/** Validate a schema's field layout — declared sizes match types,
 *  offsets are non-overlapping, no field has a negative offset. */
export function validateSchemaLayout(schema: DomainSchema): { ok: true } | { ok: false; message: string } {
  if (schema.fields.length === 0) {
    return { ok: false, message: 'schema has no fields' };
  }
  // Field-by-field structural checks.
  for (const f of schema.fields) {
    if (f.offset < 0 || f.size <= 0) {
      return {
        ok: false,
        message: `field '${f.name}' has invalid offset=${f.offset} or size=${f.size}`,
      };
    }
    if (f.type !== 'bytes' && f.type !== 'utf8') {
      const expected = FIELD_SIZE[f.type];
      if (f.size !== expected) {
        return {
          ok: false,
          message: `field '${f.name}' type=${f.type} requires size=${expected}, got ${f.size}`,
        };
      }
    }
  }
  // Overlap check.
  const sorted = [...schema.fields].sort((a, b) => a.offset - b.offset);
  for (let i = 1; i < sorted.length; i++) {
    const prev = sorted[i - 1]!;
    const curr = sorted[i]!;
    if (curr.offset < prev.offset + prev.size) {
      return {
        ok: false,
        message:
          `field '${curr.name}' (offset=${curr.offset}) overlaps ` +
          `'${prev.name}' (offset=${prev.offset}, size=${prev.size})`,
      };
    }
  }
  // Name uniqueness.
  const names = new Set<string>();
  for (const f of schema.fields) {
    if (names.has(f.name)) {
      return { ok: false, message: `duplicate field name '${f.name}'` };
    }
    names.add(f.name);
  }
  return { ok: true };
}

```
