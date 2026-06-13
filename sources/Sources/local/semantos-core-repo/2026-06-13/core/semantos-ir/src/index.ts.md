---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/semantos-ir/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.003981+00:00
---

# core/semantos-ir/src/index.ts

```ts
/**
 * @semantos/semantos-ir — ANF intermediate representation for the cell engine.
 *
 * Nanopass pipeline:
 *   ConstraintExpr  ──lower()──►  IRProgram  ──emit()──►  Uint8Array (opcodes)
 *
 * The IR proves the shape of the compilation pipeline before rewiring
 * LispCompiler.compile() to go through it.
 */

export type { IRBinding, IRProgram, IRKind, ConstraintExpr } from './types';
export { lower } from './lower';
export { emit } from './emit';
export { canonicalize } from './canonical';

```
