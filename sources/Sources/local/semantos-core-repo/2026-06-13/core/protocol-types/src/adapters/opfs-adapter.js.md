---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/opfs-adapter.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.874520+00:00
---

# core/protocol-types/src/adapters/opfs-adapter.js

```js
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
async function sha256Hex(data) {
    const hash = await crypto.subtle.digest('SHA-256', data);
    return Array.from(new Uint8Array(hash))
        .map(b => b.toString(16).padStart(2, '0'))
        .join('');
}
export class OpfsAdapter {
    rootPromise = null;
    getRoot() {
        if (!this.rootPromise) {
            this.rootPromise = navigator.storage.getDirectory();
        }
        return this.rootPromise;
    }
    /**
     * Walk key segments to get the parent directory handle, creating dirs as needed.
     * Returns [dirHandle, fileName].
     */
    async resolve(key, create) {
        const segments = key.split('/').filter(Boolean);
        if (segments.length === 0)
            throw new Error('Invalid key: empty');
        const fileName = segments.pop();
        let dir = await this.getRoot();
        for (const seg of segments) {
            dir = await dir.getDirectoryHandle(seg, { create });
        }
        return [dir, fileName];
    }
    async read(key) {
        try {
            const [dir, name] = await this.resolve(key, false);
            const fileHandle = await dir.getFileHandle(name);
            const file = await fileHandle.getFile();
            const buf = await file.arrayBuffer();
            return new Uint8Array(buf);
        }
        catch (err) {
            if (err instanceof DOMException && err.name === 'NotFoundError')
                return null;
            throw err;
        }
    }
    async write(key, data) {
        const [dir, name] = await this.resolve(key, true);
        const fileHandle = await dir.getFileHandle(name, { create: true });
        const writable = await fileHandle.createWritable();
        await writable.write(data);
        await writable.close();
    }
    async exists(key) {
        try {
            const [dir, name] = await this.resolve(key, false);
            await dir.getFileHandle(name);
            return true;
        }
        catch {
            return false;
        }
    }
    async list(prefix) {
        const results = [];
        try {
            const segments = prefix.split('/').filter(Boolean);
            let dir = await this.getRoot();
            for (const seg of segments) {
                dir = await dir.getDirectoryHandle(seg);
            }
            await walkOpfs(dir, '', results);
        }
        catch (err) {
            if (err instanceof DOMException && err.name === 'NotFoundError')
                return [];
            throw err;
        }
        return results;
    }
    async delete(key) {
        try {
            const [dir, name] = await this.resolve(key, false);
            await dir.removeEntry(name);
            return true;
        }
        catch (err) {
            if (err instanceof DOMException && err.name === 'NotFoundError')
                return false;
            throw err;
        }
    }
    async stat(key) {
        try {
            const [dir, name] = await this.resolve(key, false);
            const fileHandle = await dir.getFileHandle(name);
            const file = await fileHandle.getFile();
            const buf = await file.arrayBuffer();
            const data = new Uint8Array(buf);
            return {
                size: data.byteLength,
                modifiedAt: file.lastModified,
                contentHash: await sha256Hex(data),
            };
        }
        catch (err) {
            if (err instanceof DOMException && err.name === 'NotFoundError')
                return null;
            throw err;
        }
    }
}
async function walkOpfs(dir, prefix, results) {
    for await (const [name, handle] of dir.entries()) {
        const path = prefix ? `${prefix}/${name}` : name;
        if (handle.kind === 'directory') {
            await walkOpfs(handle, path, results);
        }
        else {
            results.push(path);
        }
    }
}
//# sourceMappingURL=opfs-adapter.js.map
```
