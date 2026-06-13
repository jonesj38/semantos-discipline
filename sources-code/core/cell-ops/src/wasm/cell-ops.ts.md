---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/wasm/cell-ops.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.828889+00:00
---

# core/cell-ops/src/wasm/cell-ops.ts

```ts
/**
 * Phase 1 — cell packing + multi-cell packing export contract.
 *
 * The `PlexusKernelCellOpsExports` interface lists the cell-pack /
 * cell-unpack / multicell-pack / multicell-unpack / cell-validate-magic
 * exports that exist in *both* WASM profiles. These are the WASM-side
 * counterparts to the TypeScript `core/cell-ops/src/packer/*` modules
 * (prompt 41) — both implementations exist because the kernel can pack
 * cells natively for embedded use, and the TS side handles the more
 * elaborate continuation-aware multi-cell assembly.
 */

/**
 * Phase 1 cell packing exports (both profiles).
 */
export interface PlexusKernelCellOpsExports {
  /**
   * Pack a cell header and payload into a 1KB cell.
   * @returns 0 on success, error code otherwise
   */
  cell_pack(
    headerPtr: number,
    payloadPtr: number,
    payloadLen: number,
    outPtr: number,
  ): number;

  /**
   * Unpack a 1KB cell into header and payload.
   * @returns 0 on success, error code otherwise
   */
  cell_unpack(
    cellPtr: number,
    headerOutPtr: number,
    payloadOutPtr: number,
  ): number;

  /**
   * Validate the magic bytes of a packed cell.
   * @returns 0 if valid, error code otherwise
   */
  cell_validate_magic(cellPtr: number): number;

  /**
   * Pack a multi-cell container with continuations.
   * @returns 0 on success, error code otherwise
   */
  multicell_pack(
    headerPtr: number,
    payloadPtr: number,
    payloadLen: number,
    contTypesPtr: number,
    contOffsetsPtr: number,
    contSizesPtr: number,
    contDataPtr: number,
    contCount: number,
    outPtr: number,
  ): number;

  /**
   * Unpack a multi-cell buffer, returning cell count.
   * @returns Number of cells on success, negative error code otherwise
   */
  multicell_unpack(bufferPtr: number, bufferLen: number): number;
}

```
