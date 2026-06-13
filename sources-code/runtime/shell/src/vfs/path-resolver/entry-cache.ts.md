---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/path-resolver/entry-cache.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.392072+00:00
---

# runtime/shell/src/vfs/path-resolver/entry-cache.ts

```ts
/**
 * Atom-backed cache for resolved VFS entries. Invalidated by an
 * effect that subscribes to `loomStateAtom` — anytime the loom state
 * mutates we drop the cache, ensuring readers never see stale
 * `getattr` snapshots.
 *
 * Keep the cache small: it lives only across consecutive `getattr` /
 * `read` calls within a single FUSE syscall handler, never persists.
 */

import { atom, effect, get, set, type Atom, type Dispose } from '@semantos/state';

import { loomStateAtom } from '@semantos/runtime-services';

import type { VfsEntry, VfsFileContent } from './types';

interface CacheValue {
  entry?: VfsEntry | null;
  content?: VfsFileContent | null;
}

export const vfsEntryCacheAtom: Atom<Map<string, CacheValue>> = atom(new Map());

export function getCachedEntry(path: string): VfsEntry | null | undefined {
  return get(vfsEntryCacheAtom).get(path)?.entry;
}

export function getCachedContent(path: string): VfsFileContent | null | undefined {
  return get(vfsEntryCacheAtom).get(path)?.content;
}

export function cacheEntry(path: string, entry: VfsEntry | null): void {
  const next = new Map(get(vfsEntryCacheAtom));
  const prior = next.get(path) ?? {};
  next.set(path, { ...prior, entry });
  set(vfsEntryCacheAtom, next);
}

export function cacheContent(path: string, content: VfsFileContent | null): void {
  const next = new Map(get(vfsEntryCacheAtom));
  const prior = next.get(path) ?? {};
  next.set(path, { ...prior, content });
  set(vfsEntryCacheAtom, next);
}

export function clearCache(): void {
  set(vfsEntryCacheAtom, new Map());
}

let invalidator: Dispose | null = null;

/**
 * Wire an effect that drops the cache whenever the loom state atom
 * fires. Idempotent — calling it more than once is safe.
 */
export function startCacheInvalidator(): void {
  if (invalidator) return;
  invalidator = effect((read) => {
    read(loomStateAtom);
    clearCache();
  });
}

export function stopCacheInvalidator(): void {
  invalidator?.();
  invalidator = null;
}

```
