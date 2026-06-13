---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/stubs/fs-promises.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.946142+00:00
---

# archive/apps-loom-react/src/stubs/fs-promises.ts

```ts
/**
 * Browser stub for fs/promises.
 * Vite scans node-fs-adapter.js (via dynamic import in create-adapter)
 * and tries to resolve fs/promises. In browser this path is never called.
 */
export function mkdir() { throw new Error('fs/promises not available in browser'); }
export function readFile() { throw new Error('fs/promises not available in browser'); }
export function writeFile() { throw new Error('fs/promises not available in browser'); }
export function readdir() { throw new Error('fs/promises not available in browser'); }
export function unlink() { throw new Error('fs/promises not available in browser'); }
export function stat() { throw new Error('fs/promises not available in browser'); }

```
