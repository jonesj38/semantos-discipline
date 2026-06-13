---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/indexed-db-adapter.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.874808+00:00
---

# core/protocol-types/src/adapters/indexed-db-adapter.js

```js
/**
 * IndexedDbAdapter — StorageAdapter wrapping IndexedDB as browser fallback.
 *
 * Used when OPFS is not available. Database: 'semantos-storage', store: 'kv'.
 * No watch() — IndexedDB has no change notification API.
 */
const DB_NAME = 'semantos-storage';
const STORE_NAME = 'kv';
const DB_VERSION = 1;
async function sha256Hex(data) {
    const hash = await crypto.subtle.digest('SHA-256', data);
    return Array.from(new Uint8Array(hash))
        .map(b => b.toString(16).padStart(2, '0'))
        .join('');
}
function openDb() {
    return new Promise((resolve, reject) => {
        const req = indexedDB.open(DB_NAME, DB_VERSION);
        req.onupgradeneeded = () => {
            const db = req.result;
            if (!db.objectStoreNames.contains(STORE_NAME)) {
                db.createObjectStore(STORE_NAME);
            }
        };
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
    });
}
function txGet(db, key) {
    return new Promise((resolve, reject) => {
        const tx = db.transaction(STORE_NAME, 'readonly');
        const store = tx.objectStore(STORE_NAME);
        const req = store.get(key);
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
    });
}
function txPut(db, key, value) {
    return new Promise((resolve, reject) => {
        const tx = db.transaction(STORE_NAME, 'readwrite');
        const store = tx.objectStore(STORE_NAME);
        const req = store.put(value, key);
        req.onsuccess = () => resolve();
        req.onerror = () => reject(req.error);
    });
}
function txDelete(db, key) {
    return new Promise((resolve, reject) => {
        const tx = db.transaction(STORE_NAME, 'readwrite');
        const store = tx.objectStore(STORE_NAME);
        // Check if key exists first
        const getReq = store.get(key);
        getReq.onsuccess = () => {
            if (getReq.result === undefined) {
                resolve(false);
            }
            else {
                const delReq = store.delete(key);
                delReq.onsuccess = () => resolve(true);
                delReq.onerror = () => reject(delReq.error);
            }
        };
        getReq.onerror = () => reject(getReq.error);
    });
}
function txKeys(db, lower, upper) {
    return new Promise((resolve, reject) => {
        const tx = db.transaction(STORE_NAME, 'readonly');
        const store = tx.objectStore(STORE_NAME);
        const range = IDBKeyRange.bound(lower, upper, false, false);
        const req = store.getAllKeys(range);
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(req.error);
    });
}
export class IndexedDbAdapter {
    dbPromise = null;
    getDb() {
        if (!this.dbPromise) {
            this.dbPromise = openDb();
        }
        return this.dbPromise;
    }
    async read(key) {
        const db = await this.getDb();
        const result = await txGet(db, key);
        if (result === undefined)
            return null;
        return new Uint8Array(result);
    }
    async write(key, data) {
        const db = await this.getDb();
        await txPut(db, key, data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength));
    }
    async exists(key) {
        const db = await this.getDb();
        const result = await txGet(db, key);
        return result !== undefined;
    }
    async list(prefix) {
        const normalizedPrefix = prefix.endsWith('/') ? prefix : prefix + '/';
        const db = await this.getDb();
        const keys = await txKeys(db, normalizedPrefix, normalizedPrefix + '\uffff');
        return keys.map(k => k.slice(normalizedPrefix.length));
    }
    async delete(key) {
        const db = await this.getDb();
        return txDelete(db, key);
    }
    async stat(key) {
        const db = await this.getDb();
        const result = await txGet(db, key);
        if (result === undefined)
            return null;
        const data = new Uint8Array(result);
        return {
            size: data.byteLength,
            modifiedAt: Date.now(), // IDB doesn't track mtime
            contentHash: await sha256Hex(data),
        };
    }
}
//# sourceMappingURL=indexed-db-adapter.js.map
```
