---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/pask-ga/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.388201+00:00
---

# `extensions/pask-ga` — multi-cluster GA + entailment over pask

Adds three things to the pask kernel without changing it:

1. **Persistent node identity by genome**, independent of which clusters
   contain a node. A node carrying genome G has the same cellId in
   pask regardless of cluster membership; cluster membership is a
   TS-side `Set`.
2. **Network operations** — `addNode` (auto-wires k-nearest paskian
   edges), `removeNode` (momentum redistribution to neighbours),
   `mergeClusters` (persistent edges + cross-boundary fusion bridges
   when genome distance < threshold).
3. **Entailment as a structural force** — declare head→body edges, run
   `runEntailmentStep` to push body salience toward the head's, with
   the propagation flowing through pask's normal interact/edge machinery.

The pask kernel does the substrate work (constraint propagation,
stability detection, edge weighting, snapshot ABI). This layer adds
the GA + cluster + entailment semantics on top.

## Architecture

```
                  ┌─────────────────────────────────┐
                  │  Orchestrator (TS)              │
                  │   - clusters: Map<name, Cluster>│
                  │   - nodes: Map<key, NodeRecord> │
                  │   - rng (seeded)                │
                  │   - addNode / removeNode        │
                  │   - mergeClusters               │
                  │   - runEntailmentStep           │
                  │   - runGAStep                   │
                  └────────────┬────────────────────┘
                               │
                               ▼
                  ┌──────────────────────────────────┐
                  │  PaskAdapter (TS bindings)        │
                  └────────────┬──────────────────────┘
                               │
                               ▼
                  ┌──────────────────────────────────┐
                  │  pask.wasm — single instance      │
                  │  - one graph, namespaced cellIds  │
                  │  - propagation, stability, prune  │
                  └──────────────────────────────────┘
```

One pask instance holds the union of every cluster's nodes.
Cluster identity lives in TS. A node in cluster A and cluster B is
literally the same pask cellId (and therefore the same h_state, same
edges) — that's what makes "persistent identity across clusters" trivial.

## API

```ts
import { Orchestrator, newGenome } from '@semantos/pask-ga';
import { loadPask, PaskAdapter } from '@semantos/pask';

const pask = await loadPask(readFileSync('pask.wasm'));
const orch = new Orchestrator(new PaskAdapter(pask), {
  rngSeed: 42,           // determinism
  k: 3,                  // k-nearest auto-wire on addNode
  fusionThreshold: 2.0,  // genome distance below this bridges on merge
  mutationRate: 0.05,
});

orch.createCluster('CS');
orch.createCluster('Math');

const programmingLang = await orch.addNode('CS', vec, 'ProgrammingLanguage');
const algorithm       = await orch.addNode('CS', vec, 'Algorithm');
const calculus        = await orch.addNode('Math', vec, 'Calculus');

orch.addEntailment('CS', programmingLang, [algorithm]);
await orch.runEntailmentStep('CS');

await orch.removeNode('CS', algorithm);   // momentum redistributed

const offspring = await orch.runGAStep('CS');  // selection × crossover × mutation

const { cluster, bridgesFormed } = await orch.mergeClusters('CS', 'Math', 'Combined');
```

## What the demo shows

`bun run extensions/pask-ga/demo/wikipedia-concept-map.ts` runs an
end-to-end exercise:

1. Build a CS cluster (5 concepts) and a Math cluster (6 concepts)
2. Logic appears in both — same genome → same cellId, persistent across clusters
3. Wire entailment edges within each cluster
4. Run `runEntailmentStep`, observe body salience boosted toward head
5. Random 30% removal of node memberships, observe momentum redistribution
6. One GA step per cluster — produces offspring from top-fitness parents
7. Merge the two clusters into "Combined" — persistent topology edges, plus
   9 cross-cluster fusion bridges where genome distance < 2.0
   (Algorithm ↔ NumberTheory, Algorithm ↔ Calculus, etc.)
8. Three more GA steps in Combined to populate offspring
9. Pask kernel view: stable threads, top inbound traffic over the merged graph

The demo is reproducible run-to-run because the RNG is seeded and pask is
deterministic given a clock — same seed → same sequence → same output.

## Design notes

### Entailment as Paskian force

`runEntailmentStep` doesn't introduce a separate force loop. It calls
`pask.interact(head, bodies, support * lr)` for each (head, bodies)
pair, which carries the head's salience into the bodies through the
kernel's normal propagation. The pask edge between head and body
accumulates weight; the body's h_state moves toward the head's.

The TS layer additionally boosts the body's salience field directly
(by `support * 0.1`) — that's the GA-side hook ("if you like the
conclusion, you must like the premises"). Pask handles the structural
side; the orchestrator handles the salience side.

### Removal as graceful dissolution

`removeNode` doesn't drop the node from pask's array (pask doesn't
support arbitrary deletion — that would re-pack indices and break held
references). Instead:

- The node's TS-side cluster membership is dropped.
- Its salience.fitness × itself is added to neighbours' momentum
  (mirrors Damian's pseudocode `edge.opposite(node).momentum += node.velocity * node.fitness`).
- A small negative-strength interact lets pask's pruner mark it on the
  next sweep if the node falls out of all clusters.

This preserves the "force balance" the spec calls for — neighbours
inherit some of the removed node's velocity instead of the network
snapping.

### Merge keeps edges, finds bridges

`mergeClusters`:

- Takes the union of members.
- Takes the union of topology edges (every pre-merge edge persists).
- Takes the union of entailment edges (no dedup — both contribute).
- Walks (a-only × b-only) pairs, adds a fusion bridge wherever
  genome distance < threshold.

The result: meaning survives the merge (edges persist), and the GA's
new evaluation context starts forcing nodes near the boundary toward
each other.

### GA step

One GA step is one offspring:

- Sample two parents from the cluster's members weighted by fitness.
- Crossover their genomes (uniform splice).
- Mutate (Gaussian-ish noise per dim, scaled by mutationRate).
- Add the offspring to the cluster — same auto-wire as any addNode.

The new node's salience starts at the parental average. Subsequent
`runEntailmentStep` and pask propagation evolve it from there.

## Determinism

Three sources of nondeterminism, all controlled:

| Source | Control |
| --- | --- |
| Pask kernel state | Caller-supplied `now_ms` (default `Date.now`); for full replay determinism use a counter clock |
| GA random decisions | Mulberry32 seeded by `rngSeed` (default 42) |
| Map iteration order | JS Map is insertion-ordered by spec; consistent across V8/Bun |

For audit-grade replay, replace the orchestrator's `now` callback
with a deterministic counter and the entire run is bit-stable.

## What's NOT in here yet

- Per-cluster fitness contexts. Currently fitness is a single value
  per node regardless of which cluster it's evaluated in. The natural
  next step is `salience: Map<clusterName, { fitness, momentum }>`
  so a node's reputation can differ between contexts.
- A coherence metric for clusters. Damian's spec mentions GA evaluating
  cluster coherence post-merge; right now cluster size + fitness
  distribution is the only signal exposed. A ΣΣ pairwise distance /
  edge density score would surface "is this cluster coherent or not".
- Hooked into the helm attention surface. The same orchestrator can
  drive helm — operator actions become `interact` calls, and
  `topByFitness` → "what to surface". Sketched but not built.
