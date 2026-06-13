---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-schema-registry/src/schemas/commerce.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.948490+00:00
---

# core/plexus-schema-registry/src/schemas/commerce.ts

```ts
/**
 * Commerce domain schema — migrated from the pre-Phase-H header fields
 * (`commercePhase`, `commerceDimension`, `commerceParentHash`,
 * `commercePrevState`). Registered under
 * `SemantosDomainFlags.COMMERCE = 0x0001FE01` per RM-004
 * (relocated from 0x00010101 — audit B-1, SUBSTRATE_SCHEMA page).
 *
 * Field layout (66 bytes encoded; padded to 72 by `encodePayload`):
 *   - phase           u8   @ 0   — pipeline phase byte
 *   - dimension       u8   @ 1   — taxonomy dimension byte
 *   - parentHash     u256  @ 2   — parent cell hash (32B)
 *   - prevStateHash  u256  @ 34  — previous-state hash (32B)
 *
 * Phase / dimension byte values match `core/cell-ops/src/typeHashRegistry.ts`
 * `PHASE_BYTES` and `DIMENSION_BYTES` exports.
 */
import type { DomainSchema } from '../types.js';

export const COMMERCE_DOMAIN_FLAG = 0x0001fe01;

export const commerceSchemaV1: DomainSchema = {
  domainFlag: COMMERCE_DOMAIN_FLAG,
  version: 1,
  commitmentMode: 'payload-digest',
  fields: [
    { name: 'phase', offset: 0, size: 1, type: 'u8' },
    { name: 'dimension', offset: 1, size: 1, type: 'u8' },
    { name: 'parentHash', offset: 2, size: 32, type: 'u256' },
    { name: 'prevStateHash', offset: 34, size: 32, type: 'u256' },
  ],
};

/** Phase byte values — mirror `core/cell-ops/src/typeHashRegistry.ts::PHASE_BYTES`. */
export const COMMERCE_PHASE = {
  source: 0x00,
  parse: 0x01,
  ast: 0x02,
  typecheck: 0x03,
  optimise: 0x04,
  codegen: 0x05,
  action: 0x06,
  outcome: 0x07,
  unknown: 0xff,
} as const;

/** Dimension byte values — mirror `core/cell-ops/src/typeHashRegistry.ts::DIMENSION_BYTES`. */
export const COMMERCE_DIMENSION = {
  composite: 0x00,
  what: 0x01,
  how: 0x02,
  instrument: 0x03,
} as const;

export type CommercePhaseName = keyof typeof COMMERCE_PHASE;
export type CommerceDimensionName = keyof typeof COMMERCE_DIMENSION;

/** Commerce payload shape — what `encodePayload(commerceSchemaV1, ...)` expects. */
export interface CommercePayload {
  phase: number; // byte
  dimension: number; // byte
  parentHash: Uint8Array; // 32B
  prevStateHash: Uint8Array; // 32B
}

/** Convenience: build a CommercePayload from named phase/dimension strings. */
export function commercePayload(input: {
  phase: CommercePhaseName | number;
  dimension: CommerceDimensionName | number;
  parentHash?: Uint8Array;
  prevStateHash?: Uint8Array;
}): CommercePayload {
  return {
    phase:
      typeof input.phase === 'string' ? COMMERCE_PHASE[input.phase] : input.phase,
    dimension:
      typeof input.dimension === 'string'
        ? COMMERCE_DIMENSION[input.dimension]
        : input.dimension,
    parentHash: input.parentHash ?? new Uint8Array(32),
    prevStateHash: input.prevStateHash ?? new Uint8Array(32),
  };
}

```
