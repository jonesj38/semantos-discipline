---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/swarm/storeSingleton.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.958595+00:00
---

# archive/apps-loom-react/src/swarm/storeSingleton.ts

```ts
/**
 * Singleton SwarmDashboardStore instance.
 * Separated to avoid circular imports between store and provider.
 */

import { SwarmDashboardStore } from './SwarmDashboardStore';

export const swarmDashboardStore = new SwarmDashboardStore();

```
