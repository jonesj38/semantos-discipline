---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/pask-ga/src/orchestrator.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.445434+00:00
---

# packages/pask-ga/src/orchestrator.ts

```ts
/**
 * Orchestrator — owns one pask kernel instance, a global node registry
 * (keyed by genome), and a registry of clusters.
 *
 * Public API maps to Damian's spec:
 *
 *   addNode(cluster, genome, salience?)        — auto-wires k-nearest paskian edges
 *   removeNode(cluster, key)                   — graceful: redistributes momentum
 *   mergeClusters(a, b, into)                  — persistent edges, fusion bridges
 *   addEntailment(cluster, head, body[])       — typed structural edge
 *   runEntailmentStep(cluster)                 — body salience pulled toward head
 *   runGAStep(cluster, opts)                   — selection / crossover / mutation
 *
 * The pask kernel below is a single instance with namespaced cellIds.
 * That keeps the data flat and makes cross-cluster identity trivial:
 * the same genome → same cellId → same pask node.
 */

import type { PaskAdapter } from '../../../core/pask/bindings/ts/src';
import {
  type Genome,
  crossover,
  distance,
  genomeKey,
  mutate,
} from './genome';
import { type Rng, mulberry32, weightedPick } from './rng';
import {
  type Cluster,
  type NodeRecord,
  EDGE_KIND_ENTAILMENT,
  EDGE_KIND_FUSION,
  EDGE_KIND_TOPOLOGY,
} from './types';

export interface OrchestratorOptions {
  rngSeed?: number;
  /** k-nearest-neighbours auto-wire on addNode. */
  k?: number;
  /** Genome distance below this triggers a fusion bridge during merge. */
  fusionThreshold?: number;
  /** Default salience for newly-added nodes. */
  defaultSalience?: number;
  /** Mutation rate (per-dimension scale) for runGAStep. */
  mutationRate?: number;
  /** Caller clock fn — defaults to Date.now. Use a counter for fully-deterministic replay. */
  now?: () => number;
}

export class Orchestrator {
  readonly pask: PaskAdapter;
  readonly nodes = new Map<string, NodeRecord>(); // key → record
  readonly clusters = new Map<string, Cluster>();

  private rng: Rng;
  private k: number;
  private fusionThreshold: number;
  private defaultSalience: number;
  private mutationRate: number;
  private now: () => number;

  constructor(pask: PaskAdapter, opts: OrchestratorOptions = {}) {
    this.pask = pask;
    this.rng = mulberry32(opts.rngSeed ?? 42);
    this.k = opts.k ?? 3;
    this.fusionThreshold = opts.fusionThreshold ?? 0.5;
    this.defaultSalience = opts.defaultSalience ?? 0.5;
    this.mutationRate = opts.mutationRate ?? 0.05;
    this.now = opts.now ?? Date.now.bind(Date);
  }

  // ── Cluster lifecycle ───────────────────────────────────────────────

  createCluster(name: string): Cluster {
    if (this.clusters.has(name)) throw new Error(`cluster exists: ${name}`);
    const c: Cluster = {
      name,
      members: new Set(),
      entailment: new Map(),
      topologyEdges: new Set(),
      createdAtMs: this.now(),
    };
    this.clusters.set(name, c);
    return c;
  }

  // ── Node lifecycle ──────────────────────────────────────────────────

  /**
   * Register a genome (idempotent across clusters) and add it to the
   * given cluster. Auto-wires k-nearest paskian edges within the cluster.
   *
   * Mirrors Damian's add_node():
   *   - upserts node
   *   - sets initial salience.fitness = 0.5 (or defaultSalience)
   *   - auto-wires Paskian edges to k-nearest neighbours
   */
  async addNode(
    clusterName: string,
    genome: Genome,
    label?: string,
    initialSalience = this.defaultSalience,
  ): Promise<string> {
    const cluster = this.requireCluster(clusterName);
    const key = genomeKey(genome);

    if (!this.nodes.has(key)) {
      this.nodes.set(key, {
        key,
        genome,
        ...(label !== undefined ? { label } : {}),
        salience: { fitness: initialSalience, momentum: 0 },
        createdAtMs: this.now(),
      });
    }

    if (!cluster.members.has(key)) {
      cluster.members.add(key);

      // Find k-nearest neighbours WITHIN this cluster (excluding self).
      const neighbours = this.kNearest(genome, key, cluster, this.k);

      // Seed pask with the node + its auto-wired edges.
      await this.pask.interact({
        cellId: key,
        kind: EDGE_KIND_TOPOLOGY,
        strength: initialSalience,
        relatedCells: neighbours.map((n) => n.key),
        nowMs: this.now(),
      });

      for (const n of neighbours) {
        cluster.topologyEdges.add(edgeId(key, n.key));
      }
    }
    return key;
  }

  /**
   * Remove a node from one cluster while preserving Paskian "force balance".
   *
   * The node's velocity (= fitness * recent state) is redistributed to
   * its neighbours' momentum, so the network doesn't snap on removal.
   *
   * If this was the node's last cluster membership, the genome is left
   * in pask but flagged in the registry; pask's pruner will catch it.
   */
  async removeNode(clusterName: string, key: string): Promise<void> {
    const cluster = this.requireCluster(clusterName);
    const node = this.nodes.get(key);
    if (!node) return;
    if (!cluster.members.has(key)) return;

    // Redistribute momentum to topology-edge neighbours within this cluster.
    const neighbours = [...cluster.members].filter((m) => {
      if (m === key) return false;
      return cluster.topologyEdges.has(edgeId(key, m)) || cluster.topologyEdges.has(edgeId(m, key));
    });
    const velocity = node.salience.fitness;
    for (const nKey of neighbours) {
      const nb = this.nodes.get(nKey);
      if (!nb) continue;
      nb.salience.momentum += velocity * node.salience.fitness;
    }

    cluster.members.delete(key);
    // Drop topology edge bookkeeping on this side.
    for (const e of [...cluster.topologyEdges]) {
      if (e.startsWith(`${key}|`) || e.endsWith(`|${key}`)) cluster.topologyEdges.delete(e);
    }
    // Drop entailment edges referencing this node.
    cluster.entailment.delete(key);
    for (const bodies of cluster.entailment.values()) bodies.delete(key);

    // The pask kernel doesn't have an explicit "remove edge". Strategy:
    // we let the edge stay but stop reinforcing it. Pruning eventually
    // drops nodes whose inbound trend goes negative; here we hint at it
    // by submitting a small negative-strength interaction on the
    // (former) primary cell.
    await this.pask.interact({
      cellId: key,
      kind: EDGE_KIND_TOPOLOGY,
      strength: -0.2,
      relatedCells: [],
      nowMs: this.now(),
    });
  }

  // ── Entailment ─────────────────────────────────────────────────────

  /** Declare an entailment relationship: head requires bodies. */
  addEntailment(clusterName: string, head: string, bodies: string[]): void {
    const cluster = this.requireCluster(clusterName);
    let set = cluster.entailment.get(head);
    if (!set) {
      set = new Set<string>();
      cluster.entailment.set(head, set);
    }
    for (const b of bodies) set.add(b);
  }

  /**
   * Run one entailment step: for each head with high salience, push state
   * + salience into its body nodes. The "logical gravity" Damian describes.
   */
  async runEntailmentStep(clusterName: string, learningRate = 0.1): Promise<void> {
    const cluster = this.requireCluster(clusterName);
    for (const [headKey, bodies] of cluster.entailment) {
      if (!cluster.members.has(headKey)) continue;
      const head = this.nodes.get(headKey);
      if (!head) continue;
      const support = head.salience.fitness;
      // Aggregate body keys that are still in this cluster.
      const liveBodies = [...bodies].filter((b) => cluster.members.has(b));
      if (liveBodies.length === 0) continue;

      // Pask interaction: head → bodies with strength scaled by support.
      // This carries the "force" through pask's propagation.
      await this.pask.interact({
        cellId: headKey,
        kind: EDGE_KIND_ENTAILMENT,
        strength: support * learningRate,
        relatedCells: liveBodies,
        nowMs: this.now(),
      });

      // Boost body salience: "if you like the conclusion, you must like
      // the premises" (Damian's note).
      for (const bKey of liveBodies) {
        const b = this.nodes.get(bKey);
        if (b) b.salience.fitness += support * 0.1;
      }
    }
  }

  // ── Merge ──────────────────────────────────────────────────────────

  /**
   * Merge two clusters into a third. Preserves all topology edges from
   * both, then forms fusion bridges between cross-boundary pairs whose
   * genome distance is below the fusion threshold.
   */
  async mergeClusters(aName: string, bName: string, intoName: string): Promise<{
    cluster: Cluster;
    bridgesFormed: Array<{ from: string; to: string; distance: number }>;
  }> {
    const a = this.requireCluster(aName);
    const b = this.requireCluster(bName);
    if (this.clusters.has(intoName)) {
      throw new Error(`cluster ${intoName} already exists`);
    }
    const into: Cluster = {
      name: intoName,
      members: new Set([...a.members, ...b.members]),
      entailment: new Map(),
      topologyEdges: new Set([...a.topologyEdges, ...b.topologyEdges]),
      createdAtMs: this.now(),
    };
    // Merge entailment maps (both contribute).
    for (const [head, bodies] of a.entailment) {
      into.entailment.set(head, new Set(bodies));
    }
    for (const [head, bodies] of b.entailment) {
      const cur = into.entailment.get(head) ?? new Set<string>();
      for (const x of bodies) cur.add(x);
      into.entailment.set(head, cur);
    }
    this.clusters.set(intoName, into);

    // Cross-cluster fusion bridges: pairs where (a-only) genome is close
    // to a (b-only) genome. The persistent topology edges provide
    // structural integrity; fusion bridges fuse the learning systems.
    const aOnly = [...a.members].filter((m) => !b.members.has(m));
    const bOnly = [...b.members].filter((m) => !a.members.has(m));
    const bridges: Array<{ from: string; to: string; distance: number }> = [];
    for (const aKey of aOnly) {
      const aNode = this.nodes.get(aKey);
      if (!aNode) continue;
      for (const bKey of bOnly) {
        const bNode = this.nodes.get(bKey);
        if (!bNode) continue;
        const d = distance(aNode.genome, bNode.genome);
        if (d < this.fusionThreshold) {
          bridges.push({ from: aKey, to: bKey, distance: d });
          await this.pask.interact({
            cellId: aKey,
            kind: EDGE_KIND_FUSION,
            strength: 0.5,
            relatedCells: [bKey],
            nowMs: this.now(),
          });
          into.topologyEdges.add(edgeId(aKey, bKey));
        }
      }
    }
    return { cluster: into, bridgesFormed: bridges };
  }

  // ── GA step ─────────────────────────────────────────────────────────

  /**
   * One GA step over a cluster: evaluate fitness, select two parents
   * weighted by fitness, crossover + mutate to produce one offspring,
   * add it to the cluster.
   *
   * If the cluster has fewer than 2 members, this is a no-op.
   */
  async runGAStep(clusterName: string, label?: string): Promise<string | null> {
    const cluster = this.requireCluster(clusterName);
    const members = [...cluster.members];
    if (members.length < 2) return null;

    const records = members
      .map((k) => this.nodes.get(k))
      .filter((n): n is NodeRecord => n !== undefined);
    const weights = records.map((n) => Math.max(0.01, n.salience.fitness));
    const parentA = weightedPick(this.rng, records, weights);
    let parentB = weightedPick(this.rng, records, weights);
    let attempts = 0;
    while (parentB === parentA && attempts++ < 5 && records.length > 1) {
      parentB = weightedPick(this.rng, records, weights);
    }

    const childGenome = mutate(crossover(parentA.genome, parentB.genome, this.rng), this.rng, this.mutationRate);
    const childKey = await this.addNode(
      clusterName,
      childGenome,
      label ?? `${parentA.label ?? parentA.key.slice(0, 8)}×${parentB.label ?? parentB.key.slice(0, 8)}`,
      // Inherit average parental salience as the starting point.
      (parentA.salience.fitness + parentB.salience.fitness) / 2,
    );
    return childKey;
  }

  // ── Reads ──────────────────────────────────────────────────────────

  topByFitness(clusterName: string, n = 5): NodeRecord[] {
    const cluster = this.requireCluster(clusterName);
    const out = [...cluster.members]
      .map((k) => this.nodes.get(k))
      .filter((x): x is NodeRecord => !!x)
      .sort((a, b) => b.salience.fitness - a.salience.fitness)
      .slice(0, n);
    return out;
  }

  /** Summary of every cluster. */
  summary(): Array<{ name: string; nodes: number; entailmentEdges: number; topologyEdges: number }> {
    return [...this.clusters.values()].map((c) => ({
      name: c.name,
      nodes: c.members.size,
      entailmentEdges: [...c.entailment.values()].reduce((acc, s) => acc + s.size, 0),
      topologyEdges: c.topologyEdges.size,
    }));
  }

  // ── Internals ──────────────────────────────────────────────────────

  private requireCluster(name: string): Cluster {
    const c = this.clusters.get(name);
    if (!c) throw new Error(`unknown cluster: ${name}`);
    return c;
  }

  private kNearest(genome: Genome, selfKey: string, cluster: Cluster, k: number): NodeRecord[] {
    const candidates: Array<{ rec: NodeRecord; d: number }> = [];
    for (const m of cluster.members) {
      if (m === selfKey) continue;
      const rec = this.nodes.get(m);
      if (!rec) continue;
      candidates.push({ rec, d: distance(genome, rec.genome) });
    }
    candidates.sort((a, b) => a.d - b.d);
    return candidates.slice(0, k).map((c) => c.rec);
  }
}

function edgeId(a: string, b: string): string {
  return a < b ? `${a}|${b}` : `${b}|${a}`;
}

```
