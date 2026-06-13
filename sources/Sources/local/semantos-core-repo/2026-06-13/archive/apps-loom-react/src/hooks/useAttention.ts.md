---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/hooks/useAttention.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.962038+00:00
---

# archive/apps-loom-react/src/hooks/useAttention.ts

```ts
import { useSyncExternalStore } from 'react';
import type { AttentionEngine, AttentionSnapshot } from '../services/AttentionEngine';

export function useAttention(engine: AttentionEngine): AttentionSnapshot {
  return useSyncExternalStore(engine.stableSubscribe, engine.getSnapshot);
}

```
