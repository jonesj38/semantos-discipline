---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/memory-adapter.d.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.880354+00:00
---

# core/protocol-types/src/adapters/memory-adapter.d.ts

```ts
/**
 * MemoryAdapter — in-memory StorageAdapter backed by a Map.
 *
 * Used for tests and ephemeral sessions. Supports watch().
 */
import type { StorageAdapter, StorageStat, StorageEvent } from '../storage';
export declare class MemoryAdapter implements StorageAdapter {
    private store;
    private watchers;
    read(key: string): Promise<Uint8Array | null>;
    write(key: string, data: Uint8Array): Promise<void>;
    exists(key: string): Promise<boolean>;
    list(prefix: string): Promise<string[]>;
    delete(key: string): Promise<boolean>;
    stat(key: string): Promise<StorageStat | null>;
    watch(prefix: string, callback: (event: StorageEvent) => void): () => void;
    /** Clear all entries. Not on the StorageAdapter interface — for test cleanup. */
    clear(): void;
    private notify;
}
//# sourceMappingURL=memory-adapter.d.ts.map
```
