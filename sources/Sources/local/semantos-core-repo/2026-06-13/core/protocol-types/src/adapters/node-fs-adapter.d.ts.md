---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/adapters/node-fs-adapter.d.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.876585+00:00
---

# core/protocol-types/src/adapters/node-fs-adapter.d.ts

```ts
/**
 * NodeFsAdapter — StorageAdapter wrapping Node.js fs/promises.
 *
 * Root directory is configurable (default: ~/.semantos or $SEMANTOS_HOME).
 * Keys are slash-delimited paths under the root. Path traversal is rejected.
 */
import type { StorageAdapter, StorageStat } from '../storage';
export declare class NodeFsAdapter implements StorageAdapter {
    private root;
    private rootEnsured;
    constructor(root?: string);
    private ensureRoot;
    private resolvePath;
    read(key: string): Promise<Uint8Array | null>;
    write(key: string, data: Uint8Array): Promise<void>;
    exists(key: string): Promise<boolean>;
    list(prefix: string): Promise<string[]>;
    delete(key: string): Promise<boolean>;
    stat(key: string): Promise<StorageStat | null>;
}
//# sourceMappingURL=node-fs-adapter.d.ts.map
```
