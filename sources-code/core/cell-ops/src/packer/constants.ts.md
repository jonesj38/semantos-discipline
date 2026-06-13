---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/packer/constants.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.831462+00:00
---

# core/cell-ops/src/packer/constants.ts

```ts
/**
 * Cell-packing constants — pinned by the on-wire format. Touching
 * these breaks every receiver. The whole reason this lives in its
 * own module is so byte-layout changes are reviewable in one place.
 */

export const CELL_SIZE = 1024;
export const HEADER_SIZE = 256;
export const PAYLOAD_SIZE = CELL_SIZE - HEADER_SIZE; // 768

/** Continuation cells share an 8-byte header at byte 0. */
export const CONTINUATION_HEADER_SIZE = 8;
export const CONTINUATION_PAYLOAD_SIZE = CELL_SIZE - CONTINUATION_HEADER_SIZE; // 1016

/**
 * Continuation cell type tags (first byte of each continuation cell).
 * LIFO pop order from the alt stack: BUMP → BEEF → ENVELOPE → DATA.
 */
export const CONTINUATION_TYPE = {
  BUMP: 0x01,
  ATOMIC_BEEF: 0x02,
  ENVELOPE: 0x03,
  DATA: 0x04,
  STATE: 0x05,
  POINTER: 0x06,
} as const;

/** Atomic BEEF prefix: 0x01010101 (4 bytes). */
export const ATOMIC_BEEF_PREFIX = Buffer.from([0x01, 0x01, 0x01, 0x01]);

```
