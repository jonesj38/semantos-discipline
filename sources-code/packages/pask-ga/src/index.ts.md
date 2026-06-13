---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/pask-ga/src/index.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.444636+00:00
---

# packages/pask-ga/src/index.ts

```ts
export { Orchestrator, type OrchestratorOptions } from './orchestrator';
export {
  type Genome,
  GENOME_DIM,
  newGenome,
  distance,
  mutate,
  crossover,
  genomeKey,
} from './genome';
export {
  type Cluster,
  type NodeRecord,
  EDGE_KIND_TOPOLOGY,
  EDGE_KIND_ENTAILMENT,
  EDGE_KIND_FUSION,
} from './types';
export { type Rng, mulberry32, weightedPick } from './rng';

```
