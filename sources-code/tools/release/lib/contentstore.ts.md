---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/release/lib/contentstore.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.560789+00:00
---

# tools/release/lib/contentstore.ts

```ts
/**
 * Tiny LocalFs ContentStore — same on-disk layout as
 * @semantos/content-store-local-fs ({root}/<hex[0:2]>/<hex>) so blobs
 * one tool puts are readable by the other adapter implementations.
 *
 * Inlined here to keep the release tools standalone (no workspace
 * package wiring needed for tooling). When/if helm or another runtime
 * needs to consume releases live, swap in the real
 * @semantos/content-store-local-fs adapter — it has the same shape.
 */

import { createHash } from 'node:crypto';
import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';

export function sha256Hex(bytes: Uint8Array): string {
  return createHash('sha256').update(bytes).digest('hex');
}

export interface ContentRef {
  sha256: string;
  sizeBytes: number;
  path: string;
}

export class LocalContentStore {
  constructor(public readonly root: string) {}

  pathFor(hashHex: string): string {
    return path.join(this.root, hashHex.slice(0, 2), hashHex);
  }

  /** Idempotent: identical bytes go to the same content-addressed path. */
  put(bytes: Uint8Array): ContentRef {
    const sha256 = sha256Hex(bytes);
    const file = this.pathFor(sha256);
    const dir = path.dirname(file);
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
    if (!existsSync(file)) writeFileSync(file, bytes);
    return { sha256, sizeBytes: bytes.length, path: file };
  }

  /** Read + verify. Throws on missing or corrupted. */
  get(hashHex: string): Uint8Array {
    const file = this.pathFor(hashHex);
    if (!existsSync(file)) {
      throw new Error(`blob not in ContentStore: ${hashHex}\n  expected: ${file}`);
    }
    const bytes = new Uint8Array(readFileSync(file));
    const actual = sha256Hex(bytes);
    if (actual !== hashHex) {
      throw new Error(
        `ContentStore corruption: ${file}\n  claimed:    ${hashHex}\n  recomputed: ${actual}`,
      );
    }
    return bytes;
  }
}

```
