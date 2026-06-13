---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/overlay-adapter.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.876012+00:00
---

# core/protocol-types/src/adapters/overlay-adapter.js

```js
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
export class OverlayAdapter {
    primary;
    fallback;
    constructor(primary, fallback) {
        this.primary = primary;
        this.fallback = fallback;
    }
    async read(key) {
        const result = await this.primary.read(key);
        if (result !== null)
            return result;
        return this.fallback.read(key);
    }
    async write(key, data) {
        return this.primary.write(key, data);
    }
    async exists(key) {
        return (await this.primary.exists(key)) || (await this.fallback.exists(key));
    }
    async list(prefix) {
        const [primaryKeys, fallbackKeys] = await Promise.all([
            this.primary.list(prefix),
            this.fallback.list(prefix),
        ]);
        const set = new Set([...primaryKeys, ...fallbackKeys]);
        return [...set];
    }
    async delete(key) {
        return this.primary.delete(key);
    }
    async stat(key) {
        const result = await this.primary.stat(key);
        if (result !== null)
            return result;
        return this.fallback.stat(key);
    }
    watch(prefix, callback) {
        if (this.primary.watch) {
            return this.primary.watch(prefix, callback);
        }
        return undefined;
    }
}
//# sourceMappingURL=overlay-adapter.js.map
```
