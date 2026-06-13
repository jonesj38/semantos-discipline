---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/opfs-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.875637+00:00
---

# core/protocol-types/src/adapters/opfs-adapter.ts

```ts
/**
 * OpfsAdapter — StorageAdapter wrapping the browser Origin Private File System API.
 *
 * OPFS is a real hierarchical filesystem in the browser sandbox — no permission
 * prompts, real directories. This is NOT IndexedDB.
 *
 * Uses createWritable() for main-thread writes. Synchronous access handles
 * (createSyncAccessHandle) only work in Web Workers and are not used here.
 *
 * No watch() — OPFS has no native change notification API.
 */

import type { StorageAdapter, StorageStat } from '../storage';

async function sha256Hex(data: Uint8Array): Promise<string> {
  const hash = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hash))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

export class OpfsAdapter implements StorageAdapter {
  private rootPromise: Promise<FileSystemDirectoryHandle> | null = null;

  private getRoot(): Promise<FileSystemDirectoryHandle> {
    if (!this.rootPromise) {
      this.rootPromise = navigator.storage.getDirectory();
    }
    return this.rootPromise;
  }

  /**
   * Walk key segments to get the parent directory handle, creating dirs as needed.
   * Returns [dirHandle, fileName].
   */
  private async resolve(
    key: string,
    create: boolean,
  ): Promise<[FileSystemDirectoryHandle, string]> {
    const segments = key.split('/').filter(Boolean);
    if (segments.length === 0) throw new Error('Invalid key: empty');
    const fileName = segments.pop()!;
    let dir = await this.getRoot();
    for (const seg of segments) {
      dir = await dir.getDirectoryHandle(seg, { create });
    }
    return [dir, fileName];
  }

  async read(key: string): Promise<Uint8Array | null> {
    try {
      const [dir, name] = await this.resolve(key, false);
      const fileHandle = await dir.getFileHandle(name);
      const file = await fileHandle.getFile();
      const buf = await file.arrayBuffer();
      return new Uint8Array(buf);
    } catch (err: unknown) {
      if (err instanceof DOMException && err.name === 'NotFoundError') return null;
      throw err;
    }
  }

  async write(key: string, data: Uint8Array): Promise<void> {
    const [dir, name] = await this.resolve(key, true);
    const fileHandle = await dir.getFileHandle(name, { create: true });
    const writable = await fileHandle.createWritable();
    await writable.write(data);
    await writable.close();
  }

  async exists(key: string): Promise<boolean> {
    try {
      const [dir, name] = await this.resolve(key, false);
      await dir.getFileHandle(name);
      return true;
    } catch {
      return false;
    }
  }

  async list(prefix: string): Promise<string[]> {
    const results: string[] = [];
    try {
      const segments = prefix.split('/').filter(Boolean);
      let dir = await this.getRoot();
      for (const seg of segments) {
        dir = await dir.getDirectoryHandle(seg);
      }
      await walkOpfs(dir, '', results);
    } catch (err: unknown) {
      if (err instanceof DOMException && err.name === 'NotFoundError') return [];
      throw err;
    }
    return results;
  }

  async delete(key: string): Promise<boolean> {
    try {
      const [dir, name] = await this.resolve(key, false);
      await dir.removeEntry(name);
      return true;
    } catch (err: unknown) {
      if (err instanceof DOMException && err.name === 'NotFoundError') return false;
      throw err;
    }
  }

  async stat(key: string): Promise<StorageStat | null> {
    try {
      const [dir, name] = await this.resolve(key, false);
      const fileHandle = await dir.getFileHandle(name);
      const file = await fileHandle.getFile();
      const buf = await file.arrayBuffer();
      const data = new Uint8Array(buf);
      return {
        size: data.byteLength,
        modifiedAt: file.lastModified,
        contentHash: await sha256Hex(data),
      };
    } catch (err: unknown) {
      if (err instanceof DOMException && err.name === 'NotFoundError') return null;
      throw err;
    }
  }

  // No watch() — OPFS has no native change notification API.
}

async function walkOpfs(
  dir: FileSystemDirectoryHandle,
  prefix: string,
  results: string[],
): Promise<void> {
  for await (const [name, handle] of (dir as any).entries()) {
    const path = prefix ? `${prefix}/${name}` : name;
    if (handle.kind === 'directory') {
      await walkOpfs(handle as FileSystemDirectoryHandle, path, results);
    } else {
      results.push(path);
    }
  }
}

```
