---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/memory-adapter.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.879434+00:00
---

# core/protocol-types/src/adapters/memory-adapter.js

```js
/**
 * MemoryAdapter — in-memory StorageAdapter backed by a Map.
 *
 * Used for tests and ephemeral sessions. Supports watch().
 */
import { createHash } from 'crypto';
export class MemoryAdapter {
    store = new Map();
    watchers = [];
    async read(key) {
        const entry = this.store.get(key);
        return entry ? entry.data : null;
    }
    async write(key, data) {
        this.store.set(key, { data, modifiedAt: Date.now() });
        this.notify({ type: 'write', key, contentHash: sha256(data) });
    }
    async exists(key) {
        return this.store.has(key);
    }
    async list(prefix) {
        const normalizedPrefix = prefix.endsWith('/') ? prefix : prefix + '/';
        const results = [];
        for (const key of this.store.keys()) {
            if (key.startsWith(normalizedPrefix)) {
                results.push(key.slice(normalizedPrefix.length));
            }
        }
        return results;
    }
    async delete(key) {
        const entry = this.store.get(key);
        if (!entry)
            return false;
        const hash = sha256(entry.data);
        this.store.delete(key);
        this.notify({ type: 'delete', key, contentHash: hash });
        return true;
    }
    async stat(key) {
        const entry = this.store.get(key);
        if (!entry)
            return null;
        return {
            size: entry.data.byteLength,
            modifiedAt: entry.modifiedAt,
            contentHash: sha256(entry.data),
        };
    }
    watch(prefix, callback) {
        const watcher = { prefix, callback };
        this.watchers.push(watcher);
        return () => {
            const idx = this.watchers.indexOf(watcher);
            if (idx >= 0)
                this.watchers.splice(idx, 1);
        };
    }
    /** Clear all entries. Not on the StorageAdapter interface — for test cleanup. */
    clear() {
        this.store.clear();
        this.watchers = [];
    }
    notify(event) {
        for (const w of this.watchers) {
            if (event.key.startsWith(w.prefix)) {
                w.callback(event);
            }
        }
    }
}
function sha256(data) {
    return createHash('sha256').update(data).digest('hex');
}
//# sourceMappingURL=memory-adapter.js.map
```
