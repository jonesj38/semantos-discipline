---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/create-adapter.d.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.880948+00:00
---

# core/protocol-types/src/adapters/create-adapter.d.ts

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
export interface CreateAdapterOptions {
    /** Use this adapter directly — bypasses environment detection. */
    adapter?: StorageAdapter;
    /** Root directory for NodeFsAdapter. */
    root?: string;
    /** If provided, wrap selected adapter in OverlayAdapter(selected, fallback). */
    fallback?: StorageAdapter;
}
export declare function createAdapter(options?: CreateAdapterOptions): Promise<StorageAdapter>;
//# sourceMappingURL=create-adapter.d.ts.map
```
