---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-34E-PASKIAN-MESH-LEARNING.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.717414+00:00
---

# Phase 34E — Paskian Learning over SRv6 Mesh DAG

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 1 week
**Prerequisites**: Phase 34A (SRv6 primitives), Phase 34B (provenance extractor + multicast manager), Phase 33A (DePIN grammar + adapters), Paskian core (`packages/paskian/`)
**Branch**: `phase-34e-paskian-mesh-learning`

---

## Context

The SRv6 mesh (Phase 34A–D) produces a DAG of RELEVANT cells through normal operation: relay attestations, tick proofs, device certs, multicast group memberships. All of this flows through the StorageAdapter and persists on the gateway. The Paskian constraint graph learner (`packages/paskian/`) already knows how to learn over cells — nodes are RELEVANT, edges are RELEVANT, pruning is LINEAR.

Phase 34E connects these two systems: the Paskian learner observes the SRv6 mesh DAG and learns optimal routing, sensor correlation, and anomaly detection — all from the same cell stream that's already being stored and anchored.

### The TSP Mitigation

The core insight: optimal multicast routing in a mesh is a variant of the Steiner tree problem (NP-hard, reduces to TSP). Phase 34E doesn't solve it — it converges toward approximate solutions through three interlocking mechanisms:

**1. Economic pressure (End.S.TICK)** — every SRv6 hop costs satoshis. Senders pay per-hop. Relay nodes earn per-hop. This creates a market: senders prefer shorter paths (lower cost), relay nodes compete to offer efficient service (higher throughput = more revenue). The economic gradient drives the network toward minimum-cost routes without any node computing a global optimum.

**2. Paskian learning (constraint graph)** — the constraint graph observes relay performance. Edges that consistently deliver cells quickly and cheaply get high weights. Edges that are slow, lossy, or expensive decay and get pruned. The propagation rule (depth k) discovers transitive efficiencies: if A→B and B→C are both efficient, the A→B→C path gets reinforced. Over learning cycles, the graph converges on a set of high-weight edges that approximate the minimum spanning tree — the TSP lower bound for multicast delivery.

**3. Semantic clustering (type-hash multicast)** — subscribers are grouped by type hash. Devices subscribing to related types tend to be physically co-located (sensors in the same field, nodes in the same building). The type structure reduces the effective problem dimension. The multicast routing trie provides structure that pure topology-based routing lacks — the "cities" in the TSP are semantically clustered, not arbitrary.

The convergence is measurable. The Paskian stability metric (ΔH < epsilon) tells you when routing has stabilised. The gap between current routing cost (sum of tick payments across all paths) and the theoretical optimum shrinks with each learning cycle. When the graph is stable, the routing approximation is as good as the mesh can achieve given its physical constraints.

This is structurally analogous to ant colony optimisation:

| ACO Concept | Semantos Equivalent |
|-------------|---------------------|
| Pheromone deposit | End.S.TICK payment (BSV micropayment) |
| Pheromone evaporation | Paskian pruning (weight < pruneThreshold → LINEAR prune event) |
| Ant memory | RELEVANT edge cells in StorageAdapter |
| Colony convergence | Paskian stability (ΔH < epsilon) |
| Solution quality | Total tick cost across all active paths |

But stronger than ACO because: the pheromone is real economic value (BSV, not a simulation), the evaporation follows a formal constraint propagation rule (not exponential decay), and the colony memory is permanent, auditable, and anchored to blockchain.

---

## Architecture

### The Mesh DAG as Constraint Graph

The SRv6 mesh produces cells through normal operation. Phase 34E interprets these cells as a Paskian constraint graph:

```
Mesh Operation              → Paskian Graph Element
───────────────────────────   ─────────────────────────────────────
Device joins mesh           → paskian.graph.node (RELEVANT)
                              h_i = initial state vector for this BCA

Cell relayed A→B            → paskian.graph.edge (RELEVANT)
                              C_ij weight updated by relay quality

Consistent relay path       → paskian.graph.stable (RELEVANT)
                              ΔH for this edge < epsilon

Unreliable path removed     → paskian.graph.pruned (LINEAR)
                              edge consumed, routing updated

Correlated sensor readings  → paskian.graph.edge (RELEVANT)
                              C_ij weight updated by data correlation

Stable sensor correlation   → paskian.graph.stable (RELEVANT)
                              scientific finding, anchored to BSV
```

### Two Learning Layers

The Paskian learner operates at two layers simultaneously over the same mesh DAG:

#### Layer 1 — Topology Learning (Route Optimisation)

Input: SRH provenance from every cell arrival.

For each cell that arrives at the gateway:
1. Extract SRH → ordered list of (BCA, segment function, latency, tick cost)
2. For each hop pair (A→B) in the path:
   - Look up `paskian.graph.edge` for this pair in StorageAdapter
   - If not found, create new edge with initial weight from `learningRate`
   - If found, update weight: `w_new = w_old + learningRate * quality_signal`
   - Quality signal = f(latency, success, tick_cost) — lower cost and latency → positive signal
3. Run Paskian propagation (k iterations):
   - For each node i, update h_i based on weighted sum of neighbor constraints
   - Propagation depth k discovers transitive efficiencies (A→B→C)
4. Check stability for each edge:
   - If |ΔH| < stabilityEpsilon for `minInteractions` consecutive observations: declare stable
   - Create `paskian.graph.stable` cell, anchor to BSV
5. Prune weak edges:
   - If weight < pruneThreshold: create `paskian.graph.pruned` cell (LINEAR, consumed once)
   - Remove edge from active graph
   - Notify mesh: affected relay nodes should update their routing tables

**Output**: an optimised routing graph where high-weight edges approximate minimum-cost multicast paths. New cells published by devices can use this graph to construct better SRH segment lists (shorter paths, cheaper hops).

#### Layer 2 — Data Learning (Sensor Correlation)

Input: cell payloads from sensor readings (after LINEAR consumption at gateway).

For each sensor reading that arrives:
1. Extract: device BCA, type hash, reading value, timestamp
2. For each other recent reading of the same type (within `stabilityWindow`):
   - Compute correlation signal between the two readings
   - Look up `paskian.graph.edge` between the two sensor BCAs
   - Update weight: `w_new = w_old + learningRate * correlation_signal`
3. The mesh topology provides a spatial prior:
   - Sensors that are mesh-adjacent (short relay paths in Layer 1) get a proximity boost
   - `proximity_weight = 1.0 / (hop_count + 1)` — closer sensors have stronger prior
   - Correlation weighted by proximity: `effective_correlation = correlation * proximity_weight`
4. Run Paskian propagation (depth k, typically 4 for spatial data)
5. Check stability → declare stable correlations as findings
6. Prune spurious correlations → discard weak data relationships

**Output**: a correlation graph over sensors. Stable clusters = groups of sensors showing consistent patterns. For electroculture: treatment cluster vs control cluster separation, with the treatment effect measurable as the inter-cluster edge weakness.

### The Feedback Loop

Layer 1 and Layer 2 share the same graph. A relay path that carries correlated sensor data gets reinforced by both layers — it's a good relay path (Layer 1) AND it carries meaningful data (Layer 2). This creates a virtuous cycle:

```
Better routing → more data delivered → better correlation learning
Better correlations → more valuable data → more tick payments → more economic incentive for good routing
```

The convergence accelerates because the economic signal (ticks) and the learning signal (constraint weights) reinforce each other. Relay nodes that serve high-value data paths earn more and get discovered faster by the learner.

---

## Deliverables

### D34E.1 — Mesh Topology Observer

New file: `packages/paskian/src/mesh-observer.ts`

Watches the StorageAdapter for incoming cells with SRH provenance and feeds them into the Paskian constraint graph.

```typescript
/**
 * MeshTopologyObserver — connects SRv6 provenance to Paskian learning.
 *
 * Observes cells arriving via the NetworkAdapter, extracts SRH provenance,
 * and updates the Paskian constraint graph with relay quality observations.
 *
 * This is Layer 1: topology learning for route optimisation.
 */
export class MeshTopologyObserver {
  constructor(
    private storage: StorageAdapter,
    private identity: IdentityAdapter,
    private graph: PaskianGraph,
    private config: PaskianConfig,
  ) {}

  /**
   * Process an incoming cell with SRH provenance.
   * Extracts hop pairs, updates edge weights, runs propagation.
   */
  async observeCell(
    cellBytes: Uint8Array,
    provenance: SRv6Provenance,
  ): Promise<GraphUpdateResult>;

  /**
   * Run a full propagation cycle over the current graph.
   * Called periodically (e.g. every 60s) or after N observations.
   */
  async propagate(): Promise<PropagationResult>;

  /**
   * Check all edges for stability and prune weak ones.
   * Returns list of stable edges (newly discovered efficient routes)
   * and pruned edges (removed unreliable paths).
   */
  async stabiliseAndPrune(): Promise<{
    stable: PaskianStableEvent[];
    pruned: PaskianPruneEvent[];
  }>;

  /**
   * Export the current routing graph as a weighted adjacency list.
   * Used by SRH construction (Phase 34A) to build better segment lists.
   */
  getRoutingGraph(): WeightedGraph;
}

export interface GraphUpdateResult {
  edgesUpdated: number;
  edgesCreated: number;
  nodesCreated: number;
}

export interface PropagationResult {
  iterations: number;
  maxDeltaH: number;
  converged: boolean;
}

export interface WeightedGraph {
  nodes: Map<string, { bca: string; certId: string; h: number[] }>;
  edges: Map<string, { from: string; to: string; weight: number; cost: number; latency: number }>;
}
```

### D34E.2 — Sensor Correlation Learner

New file: `packages/paskian/src/sensor-correlator.ts`

Layer 2: learns correlations between sensor readings using the same Paskian constraint graph, weighted by mesh proximity from Layer 1.

```typescript
/**
 * SensorCorrelationLearner — discovers data correlations across the mesh.
 *
 * Observes sensor readings (after LINEAR consumption), computes pairwise
 * correlations, and updates the Paskian constraint graph. Uses mesh
 * topology from Layer 1 as a spatial prior (closer sensors → stronger
 * correlation prior).
 *
 * For electroculture: discovers treatment vs control cluster separation.
 * For cold chain: discovers temperature anomaly propagation patterns.
 * For smart building: discovers HVAC zone correlations.
 *
 * Vertical-agnostic: works for any grammar that produces sensor readings.
 */
export class SensorCorrelationLearner {
  constructor(
    private storage: StorageAdapter,
    private graph: PaskianGraph,
    private topologyObserver: MeshTopologyObserver,
    private config: PaskianConfig,
  ) {}

  /**
   * Observe a sensor reading and update correlations with recent readings
   * from other sensors of the same type.
   */
  async observeReading(
    sensorBCA: string,
    typeHash: Buffer,
    value: number,
    timestamp: number,
  ): Promise<CorrelationUpdateResult>;

  /**
   * Get the current sensor correlation graph.
   * Clusters in this graph represent groups of sensors with correlated behavior.
   */
  getCorrelationGraph(): CorrelationGraph;

  /**
   * Identify stable clusters in the correlation graph.
   * Returns groups of sensors that show consistent co-variation.
   */
  identifyClusters(): SensorCluster[];

  /**
   * Compute the treatment effect between two clusters.
   * For electroculture: treatment cluster vs control cluster.
   * Returns the inter-cluster edge weakness as a measure of effect separation.
   */
  computeClusterSeparation(
    clusterA: string[],  // BCAs
    clusterB: string[],  // BCAs
  ): ClusterSeparation;
}

export interface CorrelationUpdateResult {
  pairsEvaluated: number;
  edgesUpdated: number;
  edgesCreated: number;
  proximityBoosted: number;
}

export interface SensorCluster {
  id: string;
  members: string[];  // BCAs
  avgInternalWeight: number;
  stableEdgeCount: number;
  dominantType: string;  // most common type hash in cluster
}

export interface ClusterSeparation {
  interClusterWeight: number;  // weak = good separation
  intraClusterWeightA: number; // strong = coherent cluster
  intraClusterWeightB: number;
  effectSize: number;           // (intraA + intraB) / 2 - inter
  significant: boolean;         // effectSize > significance threshold
  confidence: number;           // based on minInteractions met + stability
}
```

### D34E.3 — Routing Feedback Loop

New file: `packages/paskian/src/routing-feedback.ts`

Connects the learned routing graph back to SRH construction, closing the optimisation loop.

```typescript
/**
 * RoutingFeedbackLoop — feeds Paskian routing insights back into SRH construction.
 *
 * When a device or gateway needs to build an SRH for a new cell, it consults
 * the Paskian routing graph (Layer 1) to select the optimal segment list.
 * This replaces the default "shortest path from Thread routing table" with
 * "cheapest reliable path from learned constraint graph."
 *
 * The loop:
 *   Cells flow → provenance observed → graph learns → routing improves →
 *   better cells flow → better provenance → graph learns more → ...
 *
 * Convergence is measured by Paskian stability (ΔH < epsilon).
 * The total tick cost across all paths decreases as the graph stabilises.
 */
export class RoutingFeedbackLoop {
  constructor(
    private topologyObserver: MeshTopologyObserver,
    private config: PaskianConfig,
  ) {}

  /**
   * Select the optimal segment list for a cell being published.
   *
   * Uses the Paskian routing graph to find the lowest-cost path
   * from source BCA to border router BCA that satisfies the
   * required segment functions for this linearity class.
   *
   * Falls back to Thread mesh routing table if graph has insufficient
   * data (fewer than minInteractions observations for the path).
   */
  selectSegmentList(opts: {
    sourceBCA: string;
    destinationBCA: string;
    cellLinearity: number;
    requiredFunctions: SegmentFunction[];
  }): SRv6Segment[];

  /**
   * Get current routing efficiency metrics.
   */
  getMetrics(): RoutingMetrics;
}

export interface RoutingMetrics {
  /** Average tick cost per cell delivery. */
  avgTickCost: number;
  /** Average hop count per cell delivery. */
  avgHopCount: number;
  /** Percentage of paths using learned routes vs default routes. */
  learnedRouteRatio: number;
  /** Overall graph stability (max ΔH across all edges). */
  maxDeltaH: number;
  /** Number of stable edges (converged routes). */
  stableEdgeCount: number;
  /** Number of pruned edges since last reset. */
  prunedEdgeCount: number;
  /** Estimated savings vs default routing (% tick cost reduction). */
  estimatedSavings: number;
}
```

### D34E.4 — Paskian Mesh Config per Vertical

Extend the `PaskianGrammar` interface to include mesh learning parameters:

```typescript
export interface PaskianMeshConfig {
  /** Enable Layer 1 topology learning. Default: true. */
  topologyLearning: boolean;
  /** Enable Layer 2 sensor correlation learning. Default: true for verticals with sensor types. */
  correlationLearning: boolean;
  /** Correlation function for sensor readings. */
  correlationFunction: 'pearson' | 'spearman' | 'dtw';  // dynamic time warping for temporal data
  /** Proximity weight function: how much mesh distance affects correlation prior. */
  proximityDecay: 'linear' | 'exponential' | 'none';
  /** Minimum readings before correlation learning starts. */
  correlationMinSamples: number;
  /** How often to run propagation (ms). 0 = on every observation. */
  propagationInterval: number;
  /** How often to run stability check and pruning (ms). */
  stabilityCheckInterval: number;
  /** Significance threshold for cluster separation (effect size). */
  significanceThreshold: number;
  /** Maximum graph nodes (prevents unbounded growth on large meshes). */
  maxNodes: number;
  /** Maximum graph edges per node. */
  maxEdgesPerNode: number;
}
```

Default configs per vertical class:

```typescript
/** Agricultural / environmental sensors — slow signals, spatial correlation matters. */
export const AGRICULTURAL_MESH_CONFIG: PaskianMeshConfig = {
  topologyLearning: true,
  correlationLearning: true,
  correlationFunction: 'dtw',  // dynamic time warping handles temporal lag between sensors
  proximityDecay: 'exponential',  // strong proximity effect — nearby sensors are more relevant
  correlationMinSamples: 48,      // 12 hours at 15-min intervals
  propagationInterval: 60_000,    // propagate every minute
  stabilityCheckInterval: 3_600_000,  // check stability hourly
  significanceThreshold: 0.3,     // moderate threshold for ag research
  maxNodes: 500,
  maxEdgesPerNode: 20,
};

/** Cold chain / logistics — fast signals, sequential correlation matters. */
export const LOGISTICS_MESH_CONFIG: PaskianMeshConfig = {
  topologyLearning: true,
  correlationLearning: true,
  correlationFunction: 'pearson',  // simple correlation for temperature tracking
  proximityDecay: 'linear',       // moderate proximity effect
  correlationMinSamples: 10,      // fast convergence needed for cold chain alerts
  propagationInterval: 10_000,    // propagate every 10 seconds
  stabilityCheckInterval: 300_000,  // check stability every 5 minutes
  significanceThreshold: 0.5,     // high threshold — false positives are expensive
  maxNodes: 200,
  maxEdgesPerNode: 10,
};

/** Smart building — periodic signals, zone-based correlation. */
export const BUILDING_MESH_CONFIG: PaskianMeshConfig = {
  topologyLearning: true,
  correlationLearning: true,
  correlationFunction: 'pearson',
  proximityDecay: 'exponential',
  correlationMinSamples: 96,      // 24 hours at 15-min intervals (captures diurnal cycle)
  propagationInterval: 300_000,   // propagate every 5 minutes
  stabilityCheckInterval: 86_400_000,  // daily stability check
  significanceThreshold: 0.4,
  maxNodes: 1000,
  maxEdgesPerNode: 30,
};
```

### D34E.5 — TSP Approximation Quality Metric

New file: `packages/paskian/src/tsp-metric.ts`

Measures how close the learned routing is to optimal.

```typescript
/**
 * TSP Approximation Quality — measures routing efficiency vs theoretical optimum.
 *
 * The theoretical optimum for multicast delivery is the minimum Steiner tree
 * connecting all subscribers in the multicast group. Computing this exactly
 * is NP-hard. But we can compute lower bounds and measure how close the
 * Paskian-learned routing gets.
 *
 * Metrics:
 * - Total tick cost of current routing vs MST lower bound
 * - Convergence rate: how quickly ΔH decreases over learning cycles
 * - Stability duration: how long the routing stays stable before topology changes force re-learning
 * - Economic efficiency: tick cost per successfully delivered cell
 */

/**
 * Compute the minimum spanning tree (MST) of the current mesh topology.
 * This is a lower bound on the optimal multicast tree cost.
 * Uses Kruskal's algorithm on the weighted edge graph from Layer 1.
 */
export function computeMSTLowerBound(graph: WeightedGraph): number;

/**
 * Compute the current routing cost (sum of tick payments for delivering
 * one cell to all subscribers in a multicast group).
 */
export function computeCurrentRoutingCost(
  graph: WeightedGraph,
  multicastGroup: string,
  subscriberBCAs: string[],
): number;

/**
 * The approximation ratio: currentCost / mstLowerBound.
 * A ratio of 1.0 means optimal. Typical converged ratio: 1.2–1.5.
 */
export function approximationRatio(
  graph: WeightedGraph,
  multicastGroup: string,
  subscriberBCAs: string[],
): number;

/**
 * Track convergence over time.
 * Records (timestamp, approximationRatio, maxDeltaH) triples.
 * Used to visualise how the routing improves over learning cycles.
 */
export interface ConvergenceTracker {
  record(timestamp: number, ratio: number, maxDeltaH: number): void;
  getHistory(): { timestamp: number; ratio: number; maxDeltaH: number }[];
  getConvergenceRate(): number;  // slope of ratio over time (negative = improving)
  isConverged(epsilon: number): boolean;
}
```

### D34E.6 — Integration: Gateway Learning Pipeline

New file: `packages/paskian/src/gateway-learner.ts`

The main integration point that runs on the border router gateway:

```typescript
/**
 * GatewayLearner — the learning pipeline that runs on the border router.
 *
 * Composes MeshTopologyObserver (Layer 1), SensorCorrelationLearner (Layer 2),
 * and RoutingFeedbackLoop into a single pipeline that processes every
 * incoming cell.
 *
 * Lifecycle:
 *   1. Cell arrives with SRH provenance
 *   2. Layer 1: update topology graph from provenance
 *   3. Layer 2: update sensor correlation graph from reading payload
 *   4. Periodic: run propagation, check stability, prune
 *   5. Periodic: update routing feedback (better SRH construction)
 *   6. Periodic: anchor stable findings to BSV
 *
 * Everything flows through the four adapters:
 *   StorageAdapter — persist graph state (RELEVANT edge/node/stable cells)
 *   IdentityAdapter — resolve BCAs to device certs
 *   AnchorAdapter — anchor stability events and pruning to BSV
 *   NetworkAdapter — subscribe to multicast groups, receive cells
 */
export class GatewayLearner {
  constructor(
    storage: StorageAdapter,
    identity: IdentityAdapter,
    anchor: AnchorAdapter,
    network: NetworkAdapter,
    config: PaskianConfig,
    meshConfig: PaskianMeshConfig,
  ) {}

  /** Start the learning pipeline. Subscribes to all vertical multicast groups. */
  async start(): Promise<void>;

  /** Stop the learning pipeline. */
  async stop(): Promise<void>;

  /** Process a single incoming cell (called by network subscription callback). */
  async processCell(cellBytes: Uint8Array, provenance: SRv6Provenance): Promise<void>;

  /** Get Layer 1 topology observer. */
  getTopologyObserver(): MeshTopologyObserver;

  /** Get Layer 2 correlation learner. */
  getCorrelationLearner(): SensorCorrelationLearner;

  /** Get routing feedback loop. */
  getRoutingFeedback(): RoutingFeedbackLoop;

  /** Get TSP approximation metrics. */
  getTSPMetrics(): ConvergenceTracker;
}
```

---

## TDD Gate

Create `packages/__tests__/phase34e-gate.test.ts`.

### T1–T4: Topology Learning

```
T1: MeshTopologyObserver creates graph nodes for new BCAs observed in provenance
T2: MeshTopologyObserver updates edge weights on repeated relay observations
T3: Propagation converges (maxDeltaH decreases) over 100 simulated cell arrivals
T4: Weak edges (below pruneThreshold) are pruned as LINEAR paskian.graph.pruned cells
```

### T5–T8: Sensor Correlation

```
T5: SensorCorrelationLearner discovers positive correlation between co-varying sensors
T6: Mesh proximity boosts correlation weight (adjacent sensors > distant sensors)
T7: identifyClusters() separates treatment and control groups in simulated electroculture data
T8: computeClusterSeparation() returns significant effect for clearly separated clusters
```

### T9–T11: Routing Feedback

```
T9: RoutingFeedbackLoop selects shorter path than default when graph is stable
T10: Total tick cost decreases over 500 simulated cell arrivals (convergence)
T11: Falls back to default routing when graph has insufficient data
```

### T12–T14: TSP Metric

```
T12: computeMSTLowerBound() returns a value ≤ current routing cost
T13: approximationRatio() decreases toward 1.0 over learning cycles
T14: ConvergenceTracker reports negative convergenceRate (improving)
```

### T15: Integration

```
T15: GatewayLearner processes 1000 simulated cells end-to-end:
     — graph grows, stabilises, prunes
     — routing cost decreases
     — at least one paskian.graph.stable cell written to storage
     — at least one paskian.graph.pruned cell written to storage
     — approximation ratio < 2.0 (within 2x of MST lower bound)
```

---

## Completion Criteria

- [ ] `packages/paskian/src/mesh-observer.ts` — Layer 1 topology learning
- [ ] `packages/paskian/src/sensor-correlator.ts` — Layer 2 data correlation learning
- [ ] `packages/paskian/src/routing-feedback.ts` — routing feedback loop
- [ ] `packages/paskian/src/tsp-metric.ts` — TSP approximation quality measurement
- [ ] `packages/paskian/src/gateway-learner.ts` — integrated gateway learning pipeline
- [ ] `PaskianMeshConfig` interface added to grammar types
- [ ] Default configs for agricultural, logistics, and building verticals
- [ ] Tests T1–T15 all pass
- [ ] `bun check` produces zero TypeScript errors
- [ ] `bun run build` succeeds
- [ ] Routing cost demonstrably decreases over learning cycles in T10
- [ ] TSP approximation ratio demonstrably improves in T13
- [ ] All graph state persisted via StorageAdapter (no in-memory-only state)
- [ ] Stable findings and pruning events produce cells (not just log messages)
- [ ] All commits follow `phase-34e/D34E.N:` naming convention
- [ ] Branch is `phase-34e-paskian-mesh-learning`

---

## The Convergence Proof

Phase 34E must demonstrate convergence in the integration test (T15). The test simulates a mesh of 20 devices with known optimal routing (small enough to compute MST exactly). Over 1000 cell arrivals, the Paskian-learned routing must:

1. Start with default routing (approximation ratio ≈ 2.0–3.0)
2. Converge toward MST (approximation ratio < 2.0)
3. Stabilise (maxDeltaH < epsilon for at least 100 consecutive observations)
4. Remain stable after topology perturbation (one node leaves, re-converges within 200 observations)

This proves the system works as a decentralised, incentive-compatible TSP approximation — not just in theory, but in measurable practice.

---

## Next Phase

Phase 34F (future): Geo-aware routing. The WHERE axis (geohash) influences multicast tree construction. The Paskian learner incorporates geographic distance as a constraint weight, enabling "show me all readings within 5km" as a network-layer query. Uses the shomee-era `GeoHashUtils.ts` as design reference.
