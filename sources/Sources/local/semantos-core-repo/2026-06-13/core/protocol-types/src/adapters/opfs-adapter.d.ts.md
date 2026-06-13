---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/opfs-adapter.d.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.878209+00:00
---

# core/protocol-types/src/adapters/opfs-adapter.d.ts

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
export declare class OpfsAdapter implements StorageAdapter {
    private rootPromise;
    private getRoot;
    /**
     * Walk key segments to get the parent directory handle, creating dirs as needed.
     * Returns [dirHandle, fileName].
     */
    private resolve;
    read(key: string): Promise<Uint8Array | null>;
    write(key: string, data: Uint8Array): Promise<void>;
    exists(key: string): Promise<boolean>;
    list(prefix: string): Promise<string[]>;
    delete(key: string): Promise<boolean>;
    stat(key: string): Promise<StorageStat | null>;
}
//# sourceMappingURL=opfs-adapter.d.ts.map
```
