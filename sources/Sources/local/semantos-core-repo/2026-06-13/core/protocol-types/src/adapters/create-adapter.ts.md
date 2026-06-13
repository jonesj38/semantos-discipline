---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/create-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.882383+00:00
---

# core/protocol-types/src/adapters/create-adapter.ts

```ts
/**
 * createAdapter — runtime adapter selection based on environment detection.
 *
 * Detection order:
 * 1. Explicit override via options.adapter → use it directly
 * 2. process.env.NODE_ENV === 'test' → MemoryAdapter
 * 3. typeof window === 'undefined' → NodeFsAdapter
 * 4. navigator.storage?.getDirectory available → OpfsAdapter
 * 5. typeof indexedDB !== 'undefined' → IndexedDbAdapter
 * 6. Fallback → MemoryAdapter (ephemeral, warn in console)
 *
 * If options.fallback is provided, wraps the result in OverlayAdapter.
 */

import type { StorageAdapter } from '../storage';
import { MemoryAdapter } from './memory-adapter';
import { OverlayAdapter } from './overlay-adapter';

export interface CreateAdapterOptions {
  /** Use this adapter directly — bypasses environment detection. */
  adapter?: StorageAdapter;
  /** Root directory for NodeFsAdapter. */
  root?: string;
  /** If provided, wrap selected adapter in OverlayAdapter(selected, fallback). */
  fallback?: StorageAdapter;
}

export async function createAdapter(options?: CreateAdapterOptions): Promise<StorageAdapter> {
  let selected: StorageAdapter;

  if (options?.adapter) {
    // 1. Explicit override
    selected = options.adapter;
  } else if (typeof process !== 'undefined' && process.env?.NODE_ENV === 'test') {
    // 2. Test environment
    selected = new MemoryAdapter();
  } else if (typeof (globalThis as any).window === 'undefined') {
    // 3. Node.js environment — dynamic import to avoid bundling fs in browser
    const { NodeFsAdapter } = await import('./node-fs-adapter');
    selected = new NodeFsAdapter(options?.root);
  } else if (
    typeof (globalThis as any).navigator !== 'undefined' &&
    (globalThis as any).navigator.storage &&
    typeof (globalThis as any).navigator.storage.getDirectory === 'function'
  ) {
    // 4. Browser with OPFS
    const { OpfsAdapter } = await import('./opfs-adapter');
    selected = new OpfsAdapter();
  } else if (typeof (globalThis as any).indexedDB !== 'undefined') {
    // 5. Browser fallback to IndexedDB
    const { IndexedDbAdapter } = await import('./indexed-db-adapter');
    selected = new IndexedDbAdapter();
  } else {
    // 6. Last resort — ephemeral memory
    console.warn('[semantos] No persistent storage available — using ephemeral MemoryAdapter');
    selected = new MemoryAdapter();
  }

  // Wrap in overlay if fallback provided
  if (options?.fallback) {
    return new OverlayAdapter(selected, options.fallback);
  }

  return selected;
}

```
