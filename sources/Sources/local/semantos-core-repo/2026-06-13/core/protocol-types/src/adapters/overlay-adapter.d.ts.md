---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/overlay-adapter.d.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.881503+00:00
---

# core/protocol-types/src/adapters/overlay-adapter.d.ts

```ts
/**
 * OverlayAdapter — layered read-through StorageAdapter.
 *
 * Reads try the primary adapter first, then fall back to the secondary.
 * Writes always go to primary. Deletes only affect primary (fallback is read-only).
 *
 * This is NOT the BSV overlay network (Phase 25D). The name refers to layering
 * one adapter over another — e.g., browser reads from OPFS, falls back to
 * bundled configs in a MemoryAdapter.
 */
import type { StorageAdapter, StorageStat, StorageEvent } from '../storage';
export declare class OverlayAdapter implements StorageAdapter {
    private primary;
    private fallback;
    constructor(primary: StorageAdapter, fallback: StorageAdapter);
    read(key: string): Promise<Uint8Array | null>;
    write(key: string, data: Uint8Array): Promise<void>;
    exists(key: string): Promise<boolean>;
    list(prefix: string): Promise<string[]>;
    delete(key: string): Promise<boolean>;
    stat(key: string): Promise<StorageStat | null>;
    watch(prefix: string, callback: (event: StorageEvent) => void): (() => void) | undefined;
}
//# sourceMappingURL=overlay-adapter.d.ts.map
```
