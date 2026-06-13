---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/content-store-local-fs/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.488595+00:00
---

# packages/content-store-local-fs/src/index.ts

```ts
/**
 * @semantos/content-store-local-fs
 *
 * Filesystem ContentStore. Each blob lives at
 * `{root}/<hex(hash)[0:2]>/<hex(hash)>`. No advertise — local-only.
 *
 * Reads verify the content hash and throw ContentHashMismatchError on
 * corruption. Writes are content-addressed so puts are naturally
 * idempotent.
 */

import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import {
  ContentHashMismatchError,
  ContentNotFoundError,
  hashBytes,
  makeHash,
  type ContentRef,
  type ContentStore,
  type Hash,
  type ContentPutOptions,
} from "@semantos/protocol-types";

export interface LocalFsContentStoreConfig {
  root: string;
}

function hexOfHash(h: Hash): string {
  let s = "";
  for (let i = 0; i < h.length; i++) s += h[i]!.toString(16).padStart(2, "0");
  return s;
}

export class LocalFsContentStore implements ContentStore {
  private readonly root: string;

  constructor(config: LocalFsContentStoreConfig) {
    if (!config.root) throw new Error("LocalFsContentStore: root is required");
    this.root = config.root;
  }

  private pathFor(hash: Hash): { dir: string; file: string } {
    const hex = hexOfHash(hash);
    const dir = join(this.root, hex.slice(0, 2));
    return { dir, file: join(dir, hex) };
  }

  async put(
    bytes: Uint8Array,
    opts?: ContentPutOptions,
  ): Promise<ContentRef> {
    const hash = await hashBytes(bytes);
    const { dir, file } = this.pathFor(hash);
    await mkdir(dir, { recursive: true });
    // Content-addressed: overwriting with identical bytes is the idempotent case.
    await writeFile(file, bytes);
    return {
      hash,
      sizeBytes: bytes.length,
      locator: file,
      ...(opts?.mimeType ? { mimeType: opts.mimeType } : {}),
    };
  }

  async get(hash: Hash): Promise<Uint8Array> {
    const { file } = this.pathFor(hash);
    let buf: Buffer;
    try {
      buf = await readFile(file);
    } catch (err: unknown) {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") {
        throw new ContentNotFoundError(hash);
      }
      throw err;
    }
    const bytes = new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
    const actual = await hashBytes(bytes);
    for (let i = 0; i < 32; i++) {
      if (actual[i] !== hash[i]) {
        throw new ContentHashMismatchError(hash, actual);
      }
    }
    return bytes;
  }

  async find(hash: Hash): Promise<ContentRef | null> {
    const { file } = this.pathFor(hash);
    try {
      const st = await stat(file);
      return {
        hash: makeHash(new Uint8Array(hash)),
        sizeBytes: st.size,
        locator: file,
      };
    } catch (err: unknown) {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
      throw err;
    }
  }
}

```
