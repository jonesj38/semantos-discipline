---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/pask-ga/demo/wikipedia-concept-map.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.445768+00:00
---

# packages/pask-ga/demo/wikipedia-concept-map.ts

```ts
#!/usr/bin/env bun
/**
 * Wikipedia-concept-map demo for the pask-GA layer.
 *
 *   bun run packages/pask-ga/demo/wikipedia-concept-map.ts
 *
 * Builds two clusters of related concepts, runs entailment, randomly
 * removes some nodes, fires GA steps, then merges the clusters and
 * prints what survives. The aim is to make every API surface
 * Damian asked for visible:
 *
 *   - addNode (auto-wires k-nearest pask edges)
 *   - removeNode (momentum redistribution to neighbours)
 *   - addEntailment (head → bodies)
 *   - runEntailmentStep (logical gravity pulls bodies toward head)
 *   - runGAStep (selection / crossover / mutation produces offspring)
 *   - mergeClusters (persistent edges + fusion bridges by genome distance)
 *
 * The demo uses a seeded RNG so output is reproducible run-to-run.
 *
 * Concept genomes are hand-tuned: concepts within a domain (CS, math)
 * have closer genomes; cross-domain bridges (e.g. Algorithm ↔ Logic)
 * have moderate distance. After merge, fusion bridges form where
 * genome distance < fusionThreshold.
 */

import { readFileSync } from 'node:fs';
import path from 'node:path';

import { loadPask, PaskAdapter } from '../../../core/pask/bindings/ts/src';
import {
  Orchestrator,
  type Genome,
  GENOME_DIM,
} from '../src';

const HERE = path.dirname(new URL(import.meta.url).pathname);
const REPO_ROOT = path.resolve(HERE, '../../..');
const PASK_WASM = path.join(REPO_ROOT, 'core/pask/zig-out/bin/pask.wasm');

// ── Concept catalogue ──────────────────────────────────────────────────
//
// Genome dimensions are hand-curated to make the structure visible:
//   dim 0..7: "CS-ness" — programming, machines, formal systems
//   dim 8..15: "math-ness" — abstraction, structures, proofs
// Both axes overlap (logic, set-theory, algorithms sit between).

interface ConceptSpec {
  label: string;
  vec: number[]; // length GENOME_DIM
}

const C: Record<string, ConceptSpec> = {
  // CS-leaning
  ProgrammingLanguage: { label: 'ProgrammingLanguage', vec: [0.9, 0.8, 0.7, 0.5, 0.3, 0.1, 0.0, 0.0,  0.0, 0.0, 0.0, 0.1, 0.0, 0.0, 0.0, 0.0] },
  Compiler:            { label: 'Compiler',            vec: [0.9, 0.7, 0.8, 0.6, 0.4, 0.2, 0.0, 0.0,  0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0] },
  Algorithm:           { label: 'Algorithm',           vec: [0.7, 0.5, 0.4, 0.6, 0.5, 0.4, 0.3, 0.2,  0.4, 0.5, 0.3, 0.2, 0.1, 0.0, 0.0, 0.0] },
  DataStructure:       { label: 'DataStructure',       vec: [0.8, 0.6, 0.5, 0.5, 0.4, 0.3, 0.2, 0.1,  0.3, 0.4, 0.5, 0.2, 0.0, 0.0, 0.0, 0.0] },
  OperatingSystem:     { label: 'OperatingSystem',     vec: [0.95,0.9, 0.85,0.7, 0.5, 0.2, 0.0, 0.0,  0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0] },
  // Bridge concepts (CS+math)
  Logic:               { label: 'Logic',               vec: [0.4, 0.3, 0.2, 0.4, 0.5, 0.6, 0.7, 0.5,  0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1, 0.0] },
  ComputabilityTheory: { label: 'ComputabilityTheory', vec: [0.5, 0.4, 0.3, 0.5, 0.6, 0.7, 0.6, 0.5,  0.6, 0.5, 0.4, 0.3, 0.2, 0.1, 0.0, 0.0] },
  // Math-leaning
  SetTheory:           { label: 'SetTheory',           vec: [0.0, 0.0, 0.0, 0.1, 0.3, 0.5, 0.7, 0.6,  0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1] },
  NumberTheory:        { label: 'NumberTheory',        vec: [0.0, 0.0, 0.0, 0.0, 0.1, 0.3, 0.5, 0.4,  0.7, 0.8, 0.6, 0.5, 0.7, 0.6, 0.4, 0.3] },
  Calculus:            { label: 'Calculus',            vec: [0.0, 0.0, 0.0, 0.0, 0.0, 0.2, 0.4, 0.5,  0.6, 0.7, 0.8, 0.7, 0.5, 0.4, 0.3, 0.5] },
  Topology:            { label: 'Topology',            vec: [0.0, 0.0, 0.0, 0.0, 0.0, 0.1, 0.3, 0.5,  0.6, 0.5, 0.7, 0.9, 0.8, 0.6, 0.5, 0.4] },
  Algebra:             { label: 'Algebra',             vec: [0.0, 0.0, 0.0, 0.0, 0.1, 0.3, 0.5, 0.4,  0.7, 0.6, 0.5, 0.4, 0.6, 0.8, 0.9, 0.7] },
};

function vec(name: keyof typeof C): Genome {
  const v = C[name]!.vec;
  if (v.length !== GENOME_DIM) throw new Error(`bad vec for ${name}`);
  return new Float64Array(v);
}

// ── Helpers ─────────────────────────────────────────────────────────────

function header(label: string) {
  console.log('\n' + '─'.repeat(60));
  console.log(label);
  console.log('─'.repeat(60));
}

function summary(orch: Orchestrator, label?: string) {
  if (label) console.log(label);
  for (const s of orch.summary()) {
    console.log(`  ${s.name.padEnd(28)} nodes=${String(s.nodes).padStart(2)}  topology-edges=${String(s.topologyEdges).padStart(2)}  entailment=${String(s.entailmentEdges).padStart(2)}`);
  }
}

function topByFitness(orch: Orchestrator, cluster: string, n = 5) {
  const tops = orch.topByFitness(cluster, n);
  console.log(`  top-${n} fitness in ${cluster}:`);
  for (const t of tops) {
    console.log(`    fitness=${t.salience.fitness.toFixed(3)}  momentum=${t.salience.momentum.toFixed(3)}  ${t.label ?? t.key.slice(0, 8)}`);
  }
}

// ── Demo ───────────────────────────────────────────────────────────────

async function main() {
  console.log('=== pask-GA: Wikipedia concept-map demo ===');
  console.log(`(seed=42, deterministic)`);

  const pask = await loadPask(readFileSync(PASK_WASM));
  const orch = new Orchestrator(new PaskAdapter(pask, {
    propagationDepth: 2,
    minInteractions: 1,
    stabilityCheckEvery: 0,
    pruneEvery: 0,
    stabilityWindowMs: 1_000_000,
  }), { rngSeed: 42, k: 3, fusionThreshold: 2.0, mutationRate: 0.05 });

  // ── Step 1: build the two clusters ────────────────────────────────
  header('STEP 1 — build CS and Math clusters');
  orch.createCluster('CS');
  orch.createCluster('Math');

  const csConcepts = ['ProgrammingLanguage', 'Compiler', 'Algorithm', 'DataStructure', 'OperatingSystem', 'Logic'] as const;
  const mathConcepts = ['SetTheory', 'NumberTheory', 'Calculus', 'Topology', 'Algebra', 'Logic', 'ComputabilityTheory'] as const;

  for (const name of csConcepts) {
    await orch.addNode('CS', vec(name), name);
  }
  for (const name of mathConcepts) {
    await orch.addNode('Math', vec(name), name);
  }

  // Logic appears in both — same genome → same key → cross-cluster identity.
  console.log(`Logic key in CS == Logic key in Math: ${
    [...orch.clusters.get('CS')!.members].some(k =>
      orch.clusters.get('Math')!.members.has(k) &&
      orch.nodes.get(k)?.label === 'Logic'
    )
  }`);

  // ── Step 2: entailment ─────────────────────────────────────────────
  header('STEP 2 — entailment: heads necessitate bodies');

  // CS cluster: ProgrammingLanguage entails (Algorithm, DataStructure, Logic)
  // Compiler entails (ProgrammingLanguage, Algorithm)
  const keyOf = (label: string) => {
    for (const [k, n] of orch.nodes) if (n.label === label) return k;
    throw new Error(`unknown label: ${label}`);
  };
  orch.addEntailment('CS', keyOf('ProgrammingLanguage'), [keyOf('Algorithm'), keyOf('DataStructure'), keyOf('Logic')]);
  orch.addEntailment('CS', keyOf('Compiler'), [keyOf('ProgrammingLanguage'), keyOf('Algorithm')]);
  orch.addEntailment('CS', keyOf('OperatingSystem'), [keyOf('ProgrammingLanguage')]);

  // Math cluster: Calculus entails (Algebra, NumberTheory, Logic)
  // Topology entails (SetTheory, Algebra)
  // ComputabilityTheory entails (Logic, SetTheory)
  orch.addEntailment('Math', keyOf('Calculus'), [keyOf('Algebra'), keyOf('NumberTheory'), keyOf('Logic')]);
  orch.addEntailment('Math', keyOf('Topology'), [keyOf('SetTheory'), keyOf('Algebra')]);
  orch.addEntailment('Math', keyOf('ComputabilityTheory'), [keyOf('Logic'), keyOf('SetTheory')]);

  summary(orch, 'after entailment wiring:');

  // Boost a few heads to make entailment forces visible.
  orch.nodes.get(keyOf('Compiler'))!.salience.fitness = 0.9;
  orch.nodes.get(keyOf('Calculus'))!.salience.fitness = 0.9;

  // ── Step 3: run entailment ─────────────────────────────────────────
  header('STEP 3 — run entailment step (logical gravity)');
  const beforeLogic = orch.nodes.get(keyOf('Logic'))!.salience.fitness;
  await orch.runEntailmentStep('CS');
  await orch.runEntailmentStep('Math');
  const afterLogic = orch.nodes.get(keyOf('Logic'))!.salience.fitness;
  console.log(`  Logic salience: before=${beforeLogic.toFixed(3)}  after=${afterLogic.toFixed(3)}  (boosted by entailment from Compiler+Calculus)`);
  topByFitness(orch, 'CS', 4);
  topByFitness(orch, 'Math', 4);

  // ── Step 4: random removal ────────────────────────────────────────
  header('STEP 4 — random node removal (~30% across clusters)');
  const targets: Array<{ cluster: string; key: string; label: string }> = [];
  for (const cName of ['CS', 'Math']) {
    const c = orch.clusters.get(cName)!;
    for (const k of c.members) {
      const n = orch.nodes.get(k);
      if (!n) continue;
      // Don't remove the boosted heads; we want entailment effects to remain visible.
      if (n.label === 'Compiler' || n.label === 'Calculus') continue;
      targets.push({ cluster: cName, key: k, label: n.label ?? k.slice(0, 8) });
    }
  }
  // Seeded shuffle.
  const rng = (() => { let s = 1234; return () => { s = (s * 1103515245 + 12345) & 0x7fffffff; return s / 0x7fffffff; }; })();
  for (let i = targets.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [targets[i], targets[j]] = [targets[j]!, targets[i]!];
  }
  const toRemove = targets.slice(0, Math.floor(targets.length * 0.3));
  console.log(`  removing ${toRemove.length} memberships:`);
  for (const t of toRemove) {
    await orch.removeNode(t.cluster, t.key);
    console.log(`    ${t.cluster.padEnd(6)} ✗  ${t.label}`);
  }
  summary(orch, '\nafter removals:');

  // Show how momentum was redistributed.
  console.log('\n  momentum field (non-zero only):');
  for (const [, n] of orch.nodes) {
    if (Math.abs(n.salience.momentum) > 1e-9) {
      console.log(`    ${(n.label ?? n.key.slice(0, 8)).padEnd(24)} momentum=${n.salience.momentum.toFixed(3)}`);
    }
  }

  // ── Step 5: GA step on each cluster ────────────────────────────────
  header('STEP 5 — GA step (selection × crossover × mutation per cluster)');
  for (const cName of ['CS', 'Math']) {
    const childKey = await orch.runGAStep(cName);
    if (childKey) {
      const child = orch.nodes.get(childKey)!;
      console.log(`  ${cName}: spawned ${child.label}  fitness=${child.salience.fitness.toFixed(3)}`);
    } else {
      console.log(`  ${cName}: GA skipped (cluster too small)`);
    }
  }
  summary(orch, '\nafter GA:');

  // ── Step 6: merge ──────────────────────────────────────────────────
  header('STEP 6 — merge CS and Math into "Combined"');
  const csBefore = orch.clusters.get('CS')!.members;
  const mathBefore = orch.clusters.get('Math')!.members;
  const sharedAtMerge = [...csBefore].filter((k) => mathBefore.has(k))
    .map((k) => orch.nodes.get(k)?.label ?? k.slice(0, 8));
  console.log(`  cross-cluster shared (already in both pre-merge): ${sharedAtMerge.join(', ') || '(none)'}`);

  const { cluster: combined, bridgesFormed } = await orch.mergeClusters('CS', 'Math', 'Combined');
  console.log(`  members: ${combined.members.size}  topology-edges: ${combined.topologyEdges.size}  fusion-bridges: ${bridgesFormed.length}`);
  for (const b of bridgesFormed.slice(0, 6)) {
    const fromLabel = orch.nodes.get(b.from)?.label ?? b.from.slice(0, 8);
    const toLabel = orch.nodes.get(b.to)?.label ?? b.to.slice(0, 8);
    console.log(`    fusion: ${fromLabel.padEnd(20)} ↔ ${toLabel.padEnd(20)}  d=${b.distance.toFixed(3)}`);
  }

  // ── Step 7: run entailment + GA in the merged cluster ──────────────
  header('STEP 7 — run entailment + 3 GA steps in Combined');
  await orch.runEntailmentStep('Combined');
  for (let i = 0; i < 3; i++) {
    await orch.runGAStep('Combined', `gen${i + 1}.offspring`);
  }
  summary(orch, 'final:');
  topByFitness(orch, 'Combined', 6);

  // ── Step 8: pask's view of the resulting graph ─────────────────────
  header('STEP 8 — pask kernel view (raw graph)');
  orch.pask.finalize();
  const snap = orch.pask.snapshot();
  console.log(`  pask graph: ${snap.nodes.length} nodes, ${snap.edges.length} edges`);
  console.log(`              ${snap.nodes.filter(n => n.isStable).length} stable, ${snap.nodes.filter(n => n.isPruned).length} pruned`);
  // Top 5 inbound traffic — the most-pinned concepts in the merged graph.
  const inbound = new Map<string, number>();
  for (const e of snap.edges) inbound.set(e.toCell, (inbound.get(e.toCell) ?? 0) + e.interactionCount);
  const labelOf = (k: string) => orch.nodes.get(k)?.label ?? k.slice(0, 8);
  const top = [...inbound.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5);
  console.log('  top inbound traffic (most-referenced concepts):');
  for (const [k, n] of top) console.log(`    in=${String(n).padStart(2)}  ${labelOf(k)}`);

  console.log('\n=== demo complete ===');
}

main().catch((err) => { console.error(err); process.exit(1); });

```
