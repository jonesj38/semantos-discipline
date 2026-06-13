---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-ops/src/wasm/memory-helpers.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.827502+00:00
---

# core/cell-ops/src/wasm/memory-helpers.ts

```ts
/**
 * Pure helpers for reading + writing slices of WASM linear memory.
 * Zero project imports — only depends on the platform `WebAssembly` and
 * `TextDecoder`/`TextEncoder` globals plus the standard `Buffer` type.
 *
 * Per the prompt-42 spec acceptance criterion: "memory-helpers.ts has
 * zero imports from outside this folder (purity)." These helpers
 * encapsulate the pointer-arithmetic + view-construction patterns that
 * every consumer of `PlexusKernelWasm` repeats; centralising them here
 * keeps the per-feature wrappers free of inline `new Uint8Array(mem,
 * ptr, len)` boilerplate.
 *
 * Conventions:
 *   - `read*` returns a *copy* unless explicitly named `*View` —
 *     callers should not retain views across calls that may grow
 *     linear memory (e.g. `kernel_load_*`), since views become
 *     detached on memory growth.
 *   - `write*` returns the number of bytes written for callers that
 *     need to advance their own offset.
 *   - `readCString` reads up to the first NUL byte, capped at
 *     `maxLen` to keep faulty pointer dereferences bounded.
 */

/** Minimal interface required to read/write WASM linear memory. */
export interface WasmMemoryLike {
  readonly buffer: ArrayBuffer | SharedArrayBuffer;
}

/**
 * Read `len` bytes starting at `ptr` and return a fresh `Uint8Array`.
 * The returned array does not share storage with WASM memory, so it
 * is safe to retain across calls that may grow linear memory.
 */
export function readBytes(
  memory: WasmMemoryLike,
  ptr: number,
  len: number,
): Uint8Array {
  if (len < 0) throw new RangeError(`readBytes: negative length ${len}`);
  if (len === 0) return new Uint8Array(0);
  const view = new Uint8Array(memory.buffer, ptr, len);
  return new Uint8Array(view);
}

/**
 * Read `len` bytes starting at `ptr` and return a *view* into linear
 * memory. The view is invalidated when WASM memory grows — only safe
 * for synchronous reads that don't trigger growth.
 */
export function readBytesView(
  memory: WasmMemoryLike,
  ptr: number,
  len: number,
): Uint8Array {
  if (len < 0) throw new RangeError(`readBytesView: negative length ${len}`);
  return new Uint8Array(memory.buffer, ptr, len);
}

/**
 * Write `bytes` into linear memory at `ptr`. Returns the number of
 * bytes written (always `bytes.length`). Throws if the destination
 * range overflows the underlying buffer.
 */
export function writeBytes(
  memory: WasmMemoryLike,
  ptr: number,
  bytes: ArrayLike<number> & { length: number },
): number {
  const dest = new Uint8Array(memory.buffer, ptr, bytes.length);
  dest.set(bytes as ArrayLike<number>);
  return bytes.length;
}

/**
 * Read a NUL-terminated C string starting at `ptr` from linear
 * memory. Reads at most `maxLen` bytes (default 4096) before
 * truncating, to bound faulty pointer dereferences.
 */
export function readCString(
  memory: WasmMemoryLike,
  ptr: number,
  maxLen = 4096,
): string {
  if (ptr === 0) return '';
  // Cap by remaining buffer space — `new Uint8Array(buffer, ptr, len)`
  // throws RangeError if the requested window overflows the buffer.
  const remaining = memory.buffer.byteLength - ptr;
  if (remaining <= 0) return '';
  const window = Math.min(maxLen, remaining);
  const bytes = new Uint8Array(memory.buffer, ptr, window);
  let end = 0;
  while (end < bytes.length && bytes[end] !== 0) end++;
  return new TextDecoder('utf-8').decode(bytes.subarray(0, end));
}

/**
 * Read exactly `len` bytes as a UTF-8 string (no NUL handling).
 */
export function readUtf8(
  memory: WasmMemoryLike,
  ptr: number,
  len: number,
): string {
  if (len <= 0) return '';
  const bytes = new Uint8Array(memory.buffer, ptr, len);
  return new TextDecoder('utf-8').decode(bytes);
}

/**
 * Encode `value` as UTF-8 and write into linear memory at `ptr`.
 * Returns the number of bytes written. Does NOT NUL-terminate.
 */
export function writeUtf8(
  memory: WasmMemoryLike,
  ptr: number,
  value: string,
): number {
  const encoded = new TextEncoder().encode(value);
  return writeBytes(memory, ptr, encoded);
}

/**
 * Read a 32-bit little-endian unsigned integer from linear memory.
 * Convenience wrapper around `DataView` for the common kernel-export
 * pattern where the caller is given a pointer and needs a u32.
 */
export function readU32LE(memory: WasmMemoryLike, ptr: number): number {
  const view = new DataView(memory.buffer, ptr, 4);
  return view.getUint32(0, true);
}

/**
 * Write a 32-bit little-endian unsigned integer into linear memory.
 */
export function writeU32LE(
  memory: WasmMemoryLike,
  ptr: number,
  value: number,
): void {
  const view = new DataView(memory.buffer, ptr, 4);
  view.setUint32(0, value >>> 0, true);
}

/**
 * Compute a pointer offset in bytes — pure arithmetic, exported so
 * call-sites can express `pointerAdd(base, i * stride)` instead of
 * spelling out the addition inline.
 */
export function pointerAdd(base: number, offset: number): number {
  if (!Number.isInteger(base) || !Number.isInteger(offset)) {
    throw new TypeError(
      `pointerAdd requires integer args, got base=${base} offset=${offset}`,
    );
  }
  return base + offset;
}

```
