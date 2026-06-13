---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/cell-types/cell-type.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.501491+00:00
---

# cartridges/oddjobz/brain/src/cell-types/cell-type.ts

```ts
/**
 * Cell-type framework — every oddjobz cell type binds together:
 *   - the type-hash identifier (`whatPath:howSlug:instPath` digest)
 *   - the linearity flag (per §O2)
 *   - a deterministic pack(value) → bytes
 *   - a matching unpack(bytes) → value
 *
 * Cell-types here describe the *payload* shape of an `oddjobz.*.v1`
 * cell. The wire-level cell envelope (256-byte header + payload) is
 * built downstream by `core/cell-ops` when the cell is actually
 * minted; this module concerns itself only with the canonical
 * payload bytes that flow into that envelope.
 *
 * Round-trip invariant (asserted in the conformance tests):
 *   pack(unpack(pack(v))) === pack(v)   byte-for-byte
 *
 * The `typeHash` constant is computed once at module load and frozen.
 * Tests assert that the recomputed hash matches the value committed
 * in `docs/canon/glossary.yml`.
 */

import {
  computeTypeHash,
  typeHashHex,
  type TypeHashInput,
} from './type-hash.js';
import { type Linearity, linearityWire, type WireLinearityCode } from './linearity.js';
import {
  encodeCanonicalJson,
  decodeCanonicalJson,
  type CanonicalValue,
} from './canonical-json.js';

/** Definition of an oddjobz cell type. */
export interface CellTypeDef<T> {
  /** The fully-qualified canonical name, e.g. `oddjobz.job.v1`. */
  readonly name: string;
  /** The (what, how, inst) triple feeding the type-hash digest. */
  readonly identity: TypeHashInput;
  /** High-level linearity label per §O2. */
  readonly linearity: Linearity;
  /** Frozen 32-byte type hash (SHA-256 of `whatPath:howSlug:instPath`). */
  readonly typeHash: Uint8Array;
  /** Lowercase hex of `typeHash` (canonical on-disk form). */
  readonly typeHashHex: string;
  /** Wire-level linearity code at cell-header offset 16. */
  readonly wireLinearity: WireLinearityCode;
  /** Encode a value to canonical payload bytes. */
  pack(value: T): Uint8Array;
  /** Decode payload bytes back into a typed value. */
  unpack(bytes: Uint8Array): T;
}

/**
 * Build a cell-type definition.
 *
 * `validate` runs on every pack call (and after every unpack call) to
 * surface schema violations early. It's expected to throw on bad input.
 *
 * `toCanonical` projects a typed value onto a JSON-shaped value (omit
 * undefined fields, coerce Date → ISO string, etc.). `fromCanonical`
 * does the reverse. They MUST be inverses (modulo `validate`).
 */
export function defineCellType<T>(opts: {
  readonly name: string;
  readonly identity: TypeHashInput;
  readonly linearity: Linearity;
  /** Project a typed value onto a JSON-shaped value. The returned value
   * MUST be canonical-JSON-encodable: no Date/bigint/undefined; all
   * objects must have string keys with values that are themselves
   * canonical. The runtime check is deferred to the encoder; the type
   * here is `unknown` to spare each cell-type module a cast. */
  readonly toCanonical: (value: T) => unknown;
  readonly fromCanonical: (canonical: unknown) => T;
  readonly validate: (value: T) => void;
}): CellTypeDef<T> {
  const typeHash = computeTypeHash(opts.identity);
  // typeHash is a fresh Uint8Array; we don't expose a mutator and the
  // tests assert byte-equality after recomputation, which catches any
  // accidental mutation in transit.
  const typeHashHexValue = typeHashHex(typeHash);
  const wireLinearity = linearityWire[opts.linearity];

  return Object.freeze({
    name: opts.name,
    identity: Object.freeze({ ...opts.identity }),
    linearity: opts.linearity,
    typeHash,
    typeHashHex: typeHashHexValue,
    wireLinearity,
    pack(value: T): Uint8Array {
      opts.validate(value);
      const canonical = opts.toCanonical(value) as CanonicalValue;
      return encodeCanonicalJson(canonical);
    },
    unpack(bytes: Uint8Array): T {
      const canonical = decodeCanonicalJson(bytes) as unknown;
      const value = opts.fromCanonical(canonical);
      opts.validate(value);
      return value;
    },
  });
}

```
