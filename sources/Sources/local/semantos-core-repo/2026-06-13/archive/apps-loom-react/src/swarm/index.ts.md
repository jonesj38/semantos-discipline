---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/swarm/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.958029+00:00
---

# archive/apps-loom-react/src/swarm/index.ts

```ts
/**
 * Phase H5 — Swarm God View Dashboard barrel export.
 */

export { SwarmDashboardStore } from './SwarmDashboardStore';
export { SwarmDashboardProvider, useSwarmDashboard } from './SwarmDashboardProvider';
export { swarmDashboardStore } from './storeSingleton';
export { SwarmDashboard } from './SwarmDashboard';
export { PERSONA_COLORS, PERSONA_LABELS, createInitialState } from './types';
export type {
  SwarmDashboardState,
  PersonaId,
  NodeData,
  EdgeData,
  StatsUpdate,
  PersonaStats,
  PersonaStatsUpdate,
  HandCompletedEvent,
  BatchAnchoredEvent,
  SwarmConnectionStatus,
} from './types';

```
