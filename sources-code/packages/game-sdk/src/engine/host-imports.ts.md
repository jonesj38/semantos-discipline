---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/host-imports.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.525989+00:00
---

# packages/game-sdk/src/engine/host-imports.ts

```ts
/**
 * Minimal `PlexusKernelHostImports` builder used by the game-SDK
 * cell-engine wrapper. Extracted from the legacy `engine.ts` so
 * the WASM-loading path is testable in isolation.
 */

import { createHash } from 'crypto';

import type { PlexusKernelHostImports } from '../../../../core/cell-ops/src/wasm-interface';

export interface HostImportOptions {
  hostRegistry?: { call(name: string): number };
}

/**
 * Build a fresh imports object backed by a shared `memory.buffer`
 * proxy. The caller mutates `memory.buffer` after WASM
 * instantiation so host fns can read/write live linear memory.
 */
export function createHostImports(
  memory: { buffer: ArrayBuffer },
  opts: HostImportOptions = {},
): PlexusKernelHostImports {
  return {
    host_sha256(dataPtr: number, dataLen: number, outPtr: number): void {
      const data = new Uint8Array(memory.buffer, dataPtr, dataLen);
      const hash = createHash('sha256').update(data).digest();
      new Uint8Array(memory.buffer, outPtr, 32).set(hash);
    },
    host_hash160(dataPtr: number, dataLen: number, outPtr: number): void {
      const sha = createHash('sha256')
        .update(new Uint8Array(memory.buffer, dataPtr, dataLen))
        .digest();
      const ripemd = createHash('ripemd160').update(sha).digest();
      new Uint8Array(memory.buffer, outPtr, 20).set(ripemd);
    },
    host_hash256(dataPtr: number, dataLen: number, outPtr: number): void {
      const first = createHash('sha256')
        .update(new Uint8Array(memory.buffer, dataPtr, dataLen))
        .digest();
      const second = createHash('sha256').update(first).digest();
      new Uint8Array(memory.buffer, outPtr, 32).set(second);
    },
    host_checksig(): number {
      return 1;
    },
    host_checkmultisig(): number {
      return 1;
    },
    host_get_blocktime(): number {
      return Math.floor(Date.now() / 1000);
    },
    host_get_sequence(): number {
      return 0;
    },
    host_log(): void {},
    host_fetch_cell(): number {
      return 0;
    },
    host_call_by_name(namePtr: number, nameLen: number): number {
      if (!opts.hostRegistry) return 0xffffffff;
      const name = new TextDecoder().decode(
        new Uint8Array(memory.buffer, namePtr, nameLen),
      );
      return opts.hostRegistry.call(name);
    },
  };
}

```
