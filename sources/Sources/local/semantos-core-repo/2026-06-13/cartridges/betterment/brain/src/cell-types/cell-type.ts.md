---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/betterment/brain/src/cell-types/cell-type.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.566627+00:00
---

# cartridges/betterment/brain/src/cell-types/cell-type.ts

```ts
/**
 * Self cell-type factory — thin shim over the canonical
 * `buildTypeHash` from `@semantos/protocol-types` (T1/T5.a).
 *
 * Unlike oddjobz's parallel `defineCellType` factory, this one:
 *   - Uses the canonical structured |8|8|8|8| algorithm directly
 *     (no local SHA256-of-colon-triple)
 *   - Reads triples from `cartridges/betterment/cartridge.json` cellTypes[]
 *     via the manifest-loader path; this file just provides the
 *     in-process TS-side validator wrapper
 *
 * Pattern: per-cell-type module exports `<name>CellType = defineCellType({...})`
 * with name, triple, linearity, and a `validate(payload)` function that
 * throws if the payload doesn't match the schema in cartridge.json.
 */

import { buildTypeHash, typeHashToHex } from '@semantos/protocol-types';

export type ManifestLinearity =
  | 'LINEAR'
  | 'AFFINE'
  | 'PERSISTENT'
  | 'RELEVANT'
  | 'DEBUG';

export interface CellTypeTriple {
  readonly segment1: string;
  readonly segment2: string;
  readonly segment3: string;
  readonly segment4: string;
}

export interface DefineCellTypeInput<T> {
  /** Canonical name — must match the cartridge.json `cellTypes[].name`. */
  readonly name: string;
  /** Triple — must match the cartridge.json `cellTypes[].triple`. */
  readonly triple: CellTypeTriple;
  /** Linearity class — must match the cartridge.json `cellTypes[].linearity`. */
  readonly linearity: ManifestLinearity;
  /** Throws if payload doesn't conform.  Called at ratification. */
  readonly validate: (payload: unknown) => asserts payload is T;
}

export interface CellTypeDef<T> {
  readonly name: string;
  readonly triple: CellTypeTriple;
  readonly linearity: ManifestLinearity;
  /** 32-byte canonical typeHash, computed once at module load. */
  readonly typeHash: Uint8Array;
  /** Lowercase hex of `typeHash`. */
  readonly typeHashHex: string;
  readonly validate: (payload: unknown) => asserts payload is T;
  /** Phantom marker for the payload type — useful in generic helpers. */
  readonly _payloadType?: T;
}

export function defineCellType<T>(input: DefineCellTypeInput<T>): CellTypeDef<T> {
  const typeHash = buildTypeHash(
    input.triple.segment1,
    input.triple.segment2,
    input.triple.segment3,
    input.triple.segment4,
  );
  return Object.freeze({
    name: input.name,
    triple: input.triple,
    linearity: input.linearity,
    typeHash,
    typeHashHex: typeHashToHex(typeHash),
    validate: input.validate,
  });
}

```
