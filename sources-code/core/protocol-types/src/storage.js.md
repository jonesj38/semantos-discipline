---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/storage.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.848780+00:00
---

# core/protocol-types/src/storage.js

```js
/**
 * Unified storage abstraction for Semantos.
 * All persistence (Node fs, browser OPFS/IndexedDB, memory, overlay network)
 * goes through this interface.
 *
 * Keys are slash-delimited paths (e.g. "objects/create/job/plumbing/job-1774/latest.cell").
 * Values are raw bytes (Uint8Array). The adapter does not interpret content.
 *
 * Cross-references:
 *   Phase 25B CellStore wraps this with cell structure
 *   Phase 25C SemanticFS maps taxonomy paths to storage keys
 *   Phase 25D BsvOverlayAdapter implements this against BSV overlay network
 */
export {};
//# sourceMappingURL=storage.js.map
```
