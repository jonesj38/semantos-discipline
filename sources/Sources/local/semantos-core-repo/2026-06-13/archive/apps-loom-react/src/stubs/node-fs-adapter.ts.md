---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/stubs/node-fs-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.946405+00:00
---

# archive/apps-loom-react/src/stubs/node-fs-adapter.ts

```ts
/**
 * Browser stub for node-fs-adapter.
 * In browser, createAdapter() never reaches the Node.js code path,
 * but Vite's import analysis still resolves the dynamic import target.
 */
export class NodeFsAdapter {
  constructor(_root?: string) {
    throw new Error('NodeFsAdapter is not available in browser');
  }
}

```
