---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.818862+00:00
---

# archive/apps-world-client/src/types.ts

```ts
// World wire types now live in @semantos/world-sdk — re-exported here so
// existing call sites in this app keep working without import changes.
export type {
  Vec3,
  Quat,
  Linearity,
  SpatialState,
  EntityDelta,
  WorldTick,
  WorldFrame,
  EntityAction,
} from "@semantos/world-sdk";

// Linearity display helper stays in cube-object (rendering concern).
export { linearityName } from "@semantos/cube-object/linearity";

```
