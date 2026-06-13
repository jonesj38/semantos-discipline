---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.337387+00:00
---

# src/index.ts

```ts
/**
 * @semantos/core
 *
 * Semantic object type system — classifications (LINEAR, AFFINE, RELEVANT),
 * domain flags, capability tokens, transfer records,
 * and the consumption/validation compiler.
 *
 * - types/      Semantic object classifications, domain flags, capability tokens,
 *               transfer records, recovery payload types, metering types
 * - compiler/   Validation & enforcement of consumption rules per semantic type
 *
 * Extracted packages:
 * - @semantos/cell-ops    TypeScript cell operations + WASM binding interface
 * - @semantos/metering    8-state payment channel FSM, tick proofs, settlement
 * - @semantos/recovery    Export payload assembly, challenge-response protocol
 *
 * Peer dependency: @bsv/sdk (key derivation, ECDH, signing, BEEF/BUMP, ProtoWallet)
 */

export * from './types/index.js';
export * as Compiler from './compiler/index.js';

```
