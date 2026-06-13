---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/scg/brain/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.556476+00:00
---

# cartridges/scg/brain/src/index.ts

```ts
/**
 * @semantos/scg — SCG extension (RM-021).
 *
 * Ships the SCG grammar + manifest so the cartridge registry can
 * mount SCG-aware conversations alongside other extensions. The
 * actual relation primitives live in `@semantos/scg-relations`; the
 * substrate-level auto-emit helper lives in
 * `@semantos/conversation-graph`. This package is the
 * registration / discovery surface.
 */
export * from './grammar.js';
export * from './manifest.js';

```
