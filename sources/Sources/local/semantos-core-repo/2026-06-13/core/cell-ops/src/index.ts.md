---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.824296+00:00
---

# core/cell-ops/src/index.ts

```ts
/**
 * Cell engine — TypeScript cell operations and WASM binding interface.
 *
 * This is NOT the kernel. The kernel (2-PDA, opcode execution, linearity
 * enforcement) is Zig/WASM in packages/cell-engine/. This module provides:
 *
 *   - cellHeader: canonical header builder, packed offsets, dimension-axis hash helpers
 *     (composite typeHash moved to @semantos/protocol-types `buildTypeHash` per T2.a)
 *   - cellPacker: multi-cell structured packing (BUMP, BEEF, ENVELOPE, DATA, STATE)
 *   - merkleEnvelope: state chain proof structure (double-SHA256 merkle tree)
 *   - wasm-interface: WASM export/import contract (PlexusKernelWasm, host functions)
 *   - opcodes: opcode enum including custom 0xC0-0xCF range
 */

export * from './opcodes.js';
export * from './wasm-interface.js';
export * from './cellHeader.js';
export * from './cellPacker.js';
export * from './merkleEnvelope.js';
export * from './cell-signature.js';

```
