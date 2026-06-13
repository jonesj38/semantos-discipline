---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/create-adapter.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.875363+00:00
---

# core/protocol-types/src/adapters/create-adapter.js

```js
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
import { MemoryAdapter } from './memory-adapter';
import { OverlayAdapter } from './overlay-adapter';
export async function createAdapter(options) {
    let selected;
    if (options?.adapter) {
        // 1. Explicit override
        selected = options.adapter;
    }
    else if (typeof process !== 'undefined' && process.env?.NODE_ENV === 'test') {
        // 2. Test environment
        selected = new MemoryAdapter();
    }
    else if (typeof window === 'undefined') {
        // 3. Node.js environment — dynamic import to avoid bundling fs in browser
        const { NodeFsAdapter } = await import('./node-fs-adapter');
        selected = new NodeFsAdapter(options?.root);
    }
    else if (typeof navigator !== 'undefined' &&
        navigator.storage &&
        typeof navigator.storage.getDirectory === 'function') {
        // 4. Browser with OPFS
        const { OpfsAdapter } = await import('./opfs-adapter');
        selected = new OpfsAdapter();
    }
    else if (typeof indexedDB !== 'undefined') {
        // 5. Browser fallback to IndexedDB
        const { IndexedDbAdapter } = await import('./indexed-db-adapter');
        selected = new IndexedDbAdapter();
    }
    else {
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
//# sourceMappingURL=create-adapter.js.map
```
