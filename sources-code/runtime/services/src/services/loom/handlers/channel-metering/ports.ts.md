---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/loom/handlers/channel-metering/ports.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.120253+00:00
---

# runtime/services/src/services/loom/handlers/channel-metering/ports.ts

```ts
/** Composite port bundle the channel-metering handlers consume. */

import type {
  CashLanesPort,
  FlowRunnerPort,
  HashPort,
  PlexusPort,
} from '../../ports';

export interface ChannelMeteringPorts {
  plexus: PlexusPort;
  cashLanes: CashLanesPort;
  flowRunner: FlowRunnerPort;
  hash: HashPort;
}

```
