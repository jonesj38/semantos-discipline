---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/experience-cartridge/src/loader.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.951705+00:00
---

# core/experience-cartridge/src/loader.ts

```ts
/**
 * `loadCartridge(input) → LoadedCartridge` — the manifest-to-cartridge
 * adapter. Today it's a structural pass-through that copies the
 * supplied surfaces; the seam exists so future logic (validation,
 * lexicon-injectivity gating, grammar-extension verification) can land
 * in one place without touching every caller.
 */
import type { CartridgeInput, LoadedCartridge } from './types.js';

export function loadCartridge(input: CartridgeInput): LoadedCartridge {
  // Lightweight defensive copies of the array surfaces so downstream
  // mutations to the input arrays don't surprise the registry.
  return {
    manifest: input.manifest,
    ...(input.grammar !== undefined ? { grammar: input.grammar } : {}),
    ...(input.lexicons !== undefined ? { lexicons: [...input.lexicons] } : {}),
    ...(input.fsmEdges !== undefined ? { fsmEdges: [...input.fsmEdges] } : {}),
    ...(input.reducerPasses !== undefined
      ? { reducerPasses: [...input.reducerPasses] }
      : {}),
    ...(input.conversationHooks !== undefined
      ? { conversationHooks: input.conversationHooks }
      : {}),
    ...(input.peerView !== undefined ? { peerView: input.peerView } : {}),
    ...(input.cellTypes !== undefined ? { cellTypes: [...input.cellTypes] } : {}),
  };
}

```
