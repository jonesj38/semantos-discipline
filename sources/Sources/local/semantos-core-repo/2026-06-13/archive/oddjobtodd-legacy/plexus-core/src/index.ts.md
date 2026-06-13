---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/oddjobtodd-legacy/plexus-core/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.977681+00:00
---

# archive/oddjobtodd-legacy/plexus-core/src/index.ts

```ts
/**
 * @dusk-inc/plexus-core
 *
 * The Plexus semantic layer — what Plexus adds on top of the BSV stack.
 *
 * - types/      Semantic object classifications (LINEAR, AFFINE, RELEVANT),
 *               domain flags, capability tokens, transfer records, recovery payloads
 * - compiler/   Validation & enforcement of consumption rules per semantic type
 * - kernel/     WASM binding interface for the Zig 2-PDA script engine
 * - recovery/   Export payload assembly, challenge-response protocol
 * - metering/   8-state payment channel FSM, tick proofs, settlement
 *
 * Peer dependency: @bsv/sdk (key derivation, ECDH, signing, BEEF/BUMP, ProtoWallet)
 */

export * from './types/index.js';
export * as Compiler from './compiler/index.js';
export * as Kernel from './kernel/index.js';
export * as Recovery from './recovery/index.js';
export * as Metering from './metering/index.js';

```
