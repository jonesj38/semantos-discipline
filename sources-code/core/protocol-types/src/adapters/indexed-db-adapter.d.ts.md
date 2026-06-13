---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/indexed-db-adapter.d.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.877932+00:00
---

# core/protocol-types/src/adapters/indexed-db-adapter.d.ts

```ts
/**
 * IndexedDbAdapter — StorageAdapter wrapping IndexedDB as browser fallback.
 *
 * Used when OPFS is not available. Database: 'semantos-storage', store: 'kv'.
 * No watch() — IndexedDB has no change notification API.
 */
import type { StorageAdapter, StorageStat } from '../storage';
export declare class IndexedDbAdapter implements StorageAdapter {
    private dbPromise;
    private getDb;
    read(key: string): Promise<Uint8Array | null>;
    write(key: string, data: Uint8Array): Promise<void>;
    exists(key: string): Promise<boolean>;
    list(prefix: string): Promise<string[]>;
    delete(key: string): Promise<boolean>;
    stat(key: string): Promise<StorageStat | null>;
}
//# sourceMappingURL=indexed-db-adapter.d.ts.map
```
