---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/cell-store/content-hasher.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.890855+00:00
---

# core/protocol-types/src/cell-store/content-hasher.ts

```ts
/**
 * Content hasher — bindable port wrapping a SHA-256 digest function.
 *
 * The default implementation prefers `globalThis.crypto.subtle` (Web
 * Crypto, available in modern Node, Bun, browsers, workers) and falls
 * back to Node's `node:crypto` for older runtimes. Tests bind a
 * deterministic stub via `contentHasherPort.bind({ sha256: ... })`.
 *
 * Hex helpers live next to the port so every cell-store module can use
 * the same byte ↔ hex conventions without re-implementing them.
 */

import { port, type Port } from '@semantos/state';

export interface ContentHasher {
  sha256(data: Uint8Array): Promise<string>;
}

/** SHA-256 hash of `data` as lowercase hex. Web Crypto preferred, Node fallback. */
export async function defaultSha256(data: Uint8Array): Promise<string> {
  if (typeof globalThis.crypto?.subtle !== 'undefined') {
    const hash = await globalThis.crypto.subtle.digest('SHA-256', data);
    return hexFromBuffer(new Uint8Array(hash));
  }
  const { createHash } = await import('crypto');
  return createHash('sha256').update(data).digest('hex');
}

export const contentHasherPort: Port<ContentHasher> = port<ContentHasher>('content-hasher');

/** Convenience: invoke the bound port, falling back to default. */
export async function sha256(data: Uint8Array): Promise<string> {
  if (contentHasherPort.isBound()) return contentHasherPort.get().sha256(data);
  return defaultSha256(data);
}

export function hexFromBuffer(buf: Uint8Array): string {
  let hex = '';
  for (let i = 0; i < buf.length; i++) {
    hex += (buf[i] as number).toString(16).padStart(2, '0');
  }
  return hex;
}

export function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

/** Bind the default SHA-256 implementation. Idempotent — call once at boot. */
export function bindDefaultContentHasher(): void {
  if (contentHasherPort.isBound()) return;
  contentHasherPort.bind({ sha256: defaultSha256 });
}

```
