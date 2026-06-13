---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/type-hash.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.504561+00:00
---

# cartridges/oddjobz/brain/src/cell-types/type-hash.ts

```ts
/**
 * Type-hash computation — deterministic SHA-256 over the canonical
 * `whatPath:howSlug:instPath` triple, per `docs/spec/protocol-v0.5.md`
 * §3.7 and the existing cell-ops registry
 * (`core/cell-ops/src/typeHashRegistry.ts`).
 *
 *   typeHash = SHA-256(whatPath || ":" || howSlug || ":" || instPath)
 *
 * The hash is a 32-byte buffer. Hex form is the on-disk representation
 * in glossary.yml and the conformance vectors.
 */

import { createHash } from 'node:crypto';

/** The three-tuple identifying a cell type. */
export interface TypeHashInput {
  /** WHAT axis: domain classification path, e.g. `oddjobz.job`. */
  readonly whatPath: string;
  /** HOW axis: operation-mode slug, e.g. `worktrack`. */
  readonly howSlug: string;
  /** INSTRUMENT axis: artefact path, e.g. `inst.work.job-record`. */
  readonly instPath: string;
}

/**
 * Compute a 32-byte SHA-256 type hash from the canonical triple.
 *
 * Deterministic and stable across runs/implementations: same triple →
 * same digest, byte-for-byte.
 */
export function computeTypeHash(input: TypeHashInput): Uint8Array {
  const canonical = `${input.whatPath}:${input.howSlug}:${input.instPath}`;
  const hash = createHash('sha256').update(canonical, 'utf-8').digest();
  return new Uint8Array(hash);
}

/** Render a typeHash buffer as lowercase hex (the canonical on-disk form). */
export function typeHashHex(hash: Uint8Array): string {
  let out = '';
  for (let i = 0; i < hash.length; i++) {
    out += (hash[i] as number).toString(16).padStart(2, '0');
  }
  return out;
}

/** Parse hex back into a 32-byte buffer (helper for tests / vectors). */
export function typeHashFromHex(hex: string): Uint8Array {
  const clean = hex.replace(/^0x/, '');
  if (clean.length % 2 !== 0) throw new Error(`odd-length hex string: ${hex}`);
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) {
    const byte = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
    if (Number.isNaN(byte)) throw new Error(`invalid hex byte at ${i}: ${hex}`);
    out[i] = byte;
  }
  return out;
}

/** Compare two type hashes byte-for-byte. */
export function typeHashEquals(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

```
