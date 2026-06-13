---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/pask-ga/src/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.444898+00:00
---

# packages/pask-ga/src/types.ts

```ts
/**
 * Shared types for the pask-ga layer.
 *
 * Identity model: a node's persistent identity is its genome. The
 * genomeKey (sha256-truncated) is the cellId we hand to pask. A node
 * with the same genome appears under the same cellId regardless of
 * which cluster it's in; cluster membership is a TS-side Set.
 *
 * Entailment edges are tracked TS-side (head → bodies). They're
 * propagated to pask as regular edges with strength scaled by
 * head salience; pask's stability/pruning machinery handles the rest.
 */

import type { Genome } from './genome';

/** What we know about a node, regardless of which cluster(s) it's in. */
export interface NodeRecord {
  /** Stable identity. Pask's cellId. */
  key: string;
  genome: Genome;
  /** Optional human label for demos. */
  label?: string;
  /** Salience drives GA selection pressure and entailment force. */
  salience: { fitness: number; momentum: number };
  /** When the node was first introduced (caller clock, ms). */
  createdAtMs: number;
}

export interface Cluster {
  name: string;
  /** Genome keys that belong to this cluster. */
  members: Set<string>;
  /** TS-side entailment edges: head key → set of body keys. */
  entailment: Map<string, Set<string>>;
  /** Topology edges this cluster owns: sorted "from-to" pairs. */
  topologyEdges: Set<string>;
  createdAtMs: number;
}

export const EDGE_KIND_TOPOLOGY = 'pask-ga.topology';
export const EDGE_KIND_ENTAILMENT = 'pask-ga.entail';
export const EDGE_KIND_FUSION = 'pask-ga.fusion';

```
