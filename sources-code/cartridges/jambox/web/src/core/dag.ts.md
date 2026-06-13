---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/core/dag.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.608908+00:00
---

# cartridges/jambox/web/src/core/dag.ts

```ts
// Cell DAG now lives in @semantos/world-sdk — re-export for backward compat.
export type { Hat, Patch, CellState, Dag } from "@semantos/world-sdk/dag";
export {
  emptyDag,
  hashHex,
  pushCell,
  appendGenesis,
  fork,
  edit,
} from "@semantos/world-sdk/dag";

```
