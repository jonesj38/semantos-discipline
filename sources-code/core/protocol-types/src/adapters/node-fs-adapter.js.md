---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/node-fs-adapter.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.881231+00:00
---

# core/protocol-types/src/adapters/node-fs-adapter.js

```js
/**
 * NodeFsAdapter — StorageAdapter wrapping Node.js fs/promises.
 *
 * Root directory is configurable (default: ~/.semantos or $SEMANTOS_HOME).
 * Keys are slash-delimited paths under the root. Path traversal is rejected.
 */
import { mkdir, readFile, writeFile, readdir, unlink, stat } from 'fs/promises';
import { join, resolve, relative, normalize } from 'path';
import { createHash } from 'crypto';
import { homedir } from 'os';
function defaultRoot() {
    return process.env.SEMANTOS_HOME ?? join(homedir(), '.semantos');
}
function validateKey(key) {
    if (key.includes('\0')) {
        throw new Error(`Invalid key: contains null byte`);
    }
    if (key.startsWith('/')) {
        throw new Error(`Invalid key: must not start with /`);
    }
    // Normalize and check for traversal
    const normalized = normalize(key);
    if (normalized.startsWith('..') || normalized.includes('/../') || normalized.includes('\\..\\')) {
        throw new Error(`Invalid key: path traversal not allowed`);
    }
    // Extra check: split segments
    for (const seg of key.split('/')) {
        if (seg === '..') {
            throw new Error(`Invalid key: path traversal not allowed`);
        }
    }
}
function sha256(data) {
    return createHash('sha256').update(data).digest('hex');
}
export class NodeFsAdapter {
    root;
    rootEnsured = false;
    constructor(root) {
        this.root = resolve(root ?? defaultRoot());
    }
    async ensureRoot() {
        if (this.rootEnsured)
            return;
        await mkdir(this.root, { recursive: true });
        this.rootEnsured = true;
    }
    resolvePath(key) {
        validateKey(key);
        const full = join(this.root, key);
        // Double-check resolved path is under root
        const rel = relative(this.root, full);
        if (rel.startsWith('..')) {
            throw new Error(`Invalid key: resolves outside root`);
        }
        return full;
    }
    async read(key) {
        const path = this.resolvePath(key);
        try {
            const buf = await readFile(path);
            return new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
        }
        catch (err) {
            if (err.code === 'ENOENT')
                return null;
            throw err;
        }
    }
    async write(key, data) {
        await this.ensureRoot();
        const path = this.resolvePath(key);
        // Create intermediate directories
        const dir = path.substring(0, path.lastIndexOf('/'));
        if (dir)
            await mkdir(dir, { recursive: true });
        await writeFile(path, data);
    }
    async exists(key) {
        const path = this.resolvePath(key);
        try {
            await stat(path);
            return true;
        }
        catch {
            return false;
        }
    }
    async list(prefix) {
        validateKey(prefix || '.');
        const dir = prefix ? join(this.root, prefix) : this.root;
        const results = [];
        try {
            await walkDir(dir, dir, results);
        }
        catch (err) {
            if (err.code === 'ENOENT')
                return [];
            throw err;
        }
        return results;
    }
    async delete(key) {
        const path = this.resolvePath(key);
        try {
            await unlink(path);
            return true;
        }
        catch (err) {
            if (err.code === 'ENOENT')
                return false;
            throw err;
        }
    }
    async stat(key) {
        const path = this.resolvePath(key);
        try {
            const st = await stat(path);
            const data = await readFile(path);
            return {
                size: st.size,
                modifiedAt: st.mtimeMs,
                contentHash: sha256(new Uint8Array(data.buffer, data.byteOffset, data.byteLength)),
            };
        }
        catch (err) {
            if (err.code === 'ENOENT')
                return null;
            throw err;
        }
    }
}
async function walkDir(base, dir, results) {
    const entries = await readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
        const full = join(dir, entry.name);
        if (entry.isDirectory()) {
            await walkDir(base, full, results);
        }
        else {
            results.push(relative(base, full));
        }
    }
}
//# sourceMappingURL=node-fs-adapter.js.map
```
