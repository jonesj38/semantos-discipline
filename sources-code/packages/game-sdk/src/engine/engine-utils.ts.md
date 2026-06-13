---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/game-sdk/src/engine/engine-utils.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.523858+00:00
---

# packages/game-sdk/src/engine/engine-utils.ts

```ts
/**
 * Internal helpers shared across the GameCellEngine ops modules.
 * Pure — no kernel, no storage. Safe to call from anywhere.
 */

/** Rewrite the ownerId field at offset 62 of a 1024-byte cell. */
export function rewriteOwnerId(cell: Uint8Array, newOwnerId: Uint8Array): Uint8Array {
  const copy = new Uint8Array(cell);
  const ownerBytes =
    newOwnerId.length >= 16 ? newOwnerId.subarray(0, 16) : padTo(newOwnerId, 16);
  copy.set(ownerBytes, 62);
  return copy;
}

/** Zero-pad `src` to `size` bytes. Returns a new array. */
export function padTo(src: Uint8Array, size: number): Uint8Array {
  const result = new Uint8Array(size);
  result.set(src, 0);
  return result;
}

/** Compare two byte arrays for equality. */
export function uint8Eq(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

/** Hex-encode bytes for use as a storage key segment. */
export function hexEncode(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

```
