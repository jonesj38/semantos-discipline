---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/wasm/host-imports.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.828339+00:00
---

# core/cell-ops/src/wasm/host-imports.ts

```ts
/**
 * `PlexusKernelHostImports` interface + builder utilities.
 *
 * Host functions that the WASM kernel imports from the Bun/Node
 * runtime. The Zig engine calls these via the `host` import object
 * for crypto, blocktime, host-cell fetching, and debug logging.
 *
 * Two sibling host-imports modules exist today:
 *
 *   - `packages/game-sdk/src/engine/host-imports.ts` — game-SDK
 *     side, builds imports backed by Node's `crypto.createHash` for
 *     a single embedded WASM kernel inside the game runtime.
 *
 *   - this file (`core/cell-ops/src/wasm/host-imports.ts`) — kernel
 *     side, the canonical *interface declaration* + a default-noop
 *     builder. The interface lives here because it is part of the
 *     core-tier WASM contract (anything that loads the kernel needs
 *     it); the noop builder is provided so tests + adapters can
 *     instantiate the kernel without supplying a real crypto host.
 *
 * Per the prompt-42 spec: kernel-side host imports are core-tier;
 * platform-specific implementations (Node crypto, browser SubtleCrypto)
 * live in higher tiers and supply their own builders.
 */

/**
 * Host functions that the WASM module imports from the runtime.
 * These provide crypto operations + blocktime + host-cell fetching
 * to the Zig engine.
 */
export interface PlexusKernelHostImports {
  /**
   * SHA256 hash. Writes 32 bytes to outPtr.
   */
  host_sha256(dataPtr: number, dataLen: number, outPtr: number): void;

  /**
   * HASH160 (SHA256 then RIPEMD160). Writes 20 bytes to outPtr.
   */
  host_hash160(dataPtr: number, dataLen: number, outPtr: number): void;

  /**
   * HASH256 (double SHA256). Writes 32 bytes to outPtr.
   */
  host_hash256(dataPtr: number, dataLen: number, outPtr: number): void;

  /**
   * Verify ECDSA signature (secp256k1).
   * @returns 1 if valid, 0 if invalid
   */
  host_checksig(
    pubkeyPtr: number,
    pubkeyLen: number,
    msgPtr: number,
    msgLen: number,
    sigPtr: number,
    sigLen: number,
  ): number;

  /**
   * Verify m-of-n multisig.
   * @returns 1 if valid, 0 if invalid
   */
  host_checkmultisig(
    pubkeysPtr: number,
    pubkeysCount: number,
    sigsPtr: number,
    sigsCount: number,
    msgPtr: number,
    msgLen: number,
    threshold: number,
  ): number;

  /**
   * Get current block timestamp for CHECKLOCKTIMEVERIFY.
   */
  host_get_blocktime(): number;

  /**
   * Get current sequence number for CHECKSEQUENCEVERIFY.
   */
  host_get_sequence(): number;

  /**
   * Log a debug message from WASM (development only).
   */
  host_log(msgPtr: number, msgLen: number): void;

  /**
   * Fetch a 1KB chunk from a higher-octave cell.
   * @returns 1 on success, 0 on failure
   */
  host_fetch_cell(
    octave: number,
    slot: number,
    offset: number,
    outPtr: number,
  ): number;
}

/**
 * Build a `PlexusKernelHostImports` whose every entry is a no-op
 * stub. Intended for tests + the embedded profile WASM where crypto
 * is supplied by the caller and not by host imports.
 *
 * - hash functions zero the output region (so verify-failed paths
 *   still return non-poisoned bytes)
 * - checksig / checkmultisig return 1 (always valid)
 * - blocktime returns the current epoch second
 * - sequence returns 0
 * - host_log + host_fetch_cell are no-ops returning 0
 *
 * This builder is *not* what production callers use — they should
 * supply real crypto via `crypto.createHash` (Node) or
 * `SubtleCrypto.digest` (browser). It exists to keep the kernel
 * boot path testable without dragging Node-specific imports into
 * the core tier.
 */
export function createNoopHostImports(
  memory: { buffer: ArrayBuffer | SharedArrayBuffer },
): PlexusKernelHostImports {
  return {
    host_sha256(_dataPtr, _dataLen, outPtr): void {
      new Uint8Array(memory.buffer, outPtr, 32).fill(0);
    },
    host_hash160(_dataPtr, _dataLen, outPtr): void {
      new Uint8Array(memory.buffer, outPtr, 20).fill(0);
    },
    host_hash256(_dataPtr, _dataLen, outPtr): void {
      new Uint8Array(memory.buffer, outPtr, 32).fill(0);
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
  };
}

```
