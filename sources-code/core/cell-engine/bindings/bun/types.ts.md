---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/bindings/bun/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.002645+00:00
---

# core/cell-engine/bindings/bun/types.ts

```ts
/**
 * CellEngine-specific types for the typed API wrapper.
 *
 * Imports shared types from @semantos/protocol-types where they exist;
 * defines engine-specific result types here.
 *
 * TODO: Evaluate moving these to @semantos/protocol-types in Phase 8.
 */

// Re-export shared types from protocol-types
export type {
  CellHeader,
  BCAInput,
  BCAOutput,
  ScriptResult,
} from '@semantos/protocol-types';

/** Input for a multi-cell continuation. */
export interface ContinuationInput {
  cellType: number;
  data: Uint8Array;
}

/** Result of a single debug step. */
export interface StepResult {
  /** 0 = stepped successfully, 1 = script complete, negative = error */
  status: number;
  pc: number;
  currentOp: number;
}

/** Result of SPV verification. */
export interface VerifyResult {
  valid: boolean;
  errorCode: number;
}

/** BEEF version detection result. */
export interface BeefVersion {
  /** 1=BRC-62 V1, 2=BRC-96 V2, 3=BRC-95 Atomic, -1=invalid */
  version: number;
}

/** Pointer cell payload — octave memory addressing. */
export interface PointerPayload {
  octave: number;
  slot: number;
  offset: number;
  contentHash: Uint8Array;
  typeHash: Uint8Array;
  totalSize: bigint;
  flags: number;
  fragmentCount: number;
}

```
