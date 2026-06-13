---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-settlement/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.705569+00:00
---

# archive/apps-settlement/src/index.ts

```ts
/**
 * @semantos/settlement — BSV settlement layer for the cell engine.
 *
 * A dynamic constraint graph where coherence emerges through local
 * propagation. Learning is defined not as optimisation over data,
 * but as the emergence of stable structures under repeated interaction.
 *
 * Usage:
 *
 *   import {
 *     PaskianAdapter,
 *     PaskianStoryGrammar,
 *     paskianSystem,
 *     paskianInteract,
 *   } from '@semantos/settlement';
 *
 *   // Create the adapter (with optional SQLite persistence)
 *   const paskian = new PaskianAdapter({ dbPath: './paskian.db' });
 *
 *   // In your game loop, after syncToCell:
 *   await paskianSystem(world, paskian);
 *
 *   // Or fire explicit interactions from game code:
 *   await paskianInteract(paskian, cellId, 'paskian.story.thread', 1.0, [relatedCellId]);
 *
 *   // Query the learned world state:
 *   const stable = paskian.stableThreads();
 *   const emerging = paskian.emergingThreads();
 */

// Grammar
export {
  PaskianStoryGrammar,
  PASKIAN_GRAPH_TYPES,
  PASKIAN_STORY_TYPES,
  DEFAULT_PASKIAN_CONFIG,
  DEFAULT_ANCHOR_POLICY,
  type PaskianGrammar,
  type PaskianConfig,
  type AnchorPolicy,
} from './grammar';

// Types
export type {
  PaskianNode,
  PaskianEdge,
  ConstraintDelta,
  StabilityRecord,
  PruningRecord,
  PaskianInteraction,
  PaskianEvents,
  StableThread,
  EmergingThread,
} from './types';

// Store
export { PaskianStore } from './store';

// Adapter (core engine)
export { PaskianAdapter, type PaskianAdapterOptions } from './adapter';

// Narrative oracle (Claude bridge)
export {
  StubNarrativeOracle,
  type NarrativeOracle,
  type WorldContext,
  type InteractionDelta,
  type NarrativeResponse,
} from './narrative-oracle';

// ECS system
export {
  paskianSystem,
  paskianInteract,
  paskianForget,
  DEFAULT_PASKIAN_SYSTEM_CONFIG,
  type PaskianSystemConfig,
} from './ecs/paskian-system';

```
