---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/navigator/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.441465+00:00
---

# packages/navigator/src/index.ts

```ts
/**
 * @semantos/navigator — Core Navigation Layer
 *
 * Like Finder/Explorer for the semantic OS. Navigates any extension's
 * types through lenses (attention allocation dimensions), object
 * presentation, and consumer binding.
 *
 * Lenses are the primitive: 7 default dimensions of attention
 * (Mind, Body, Spirit, Tribe, Home, Craft, Wealth) that filter
 * and organize objects from any extension for the UI.
 *
 * The navigator doesn't track state — extensions do that.
 * The navigator knows how to present, filter, and traverse.
 *
 * @module @semantos/navigator
 */

// ─── Lenses ─────────────────────────────────────────────────────────
export type {
  Lens,
  LensGroup,
  ObjectPresentation,
} from './types/navigator-types.js';

export {
  DEFAULT_LENSES,
  DEFAULT_LENS_GROUPS,
  DIMENSION_TO_LENS,
} from './types/navigator-types.js';

```
