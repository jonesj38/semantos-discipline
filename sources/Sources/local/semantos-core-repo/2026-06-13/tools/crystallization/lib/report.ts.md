---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/crystallization/lib/report.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.555841+00:00
---

# tools/crystallization/lib/report.ts

```ts
import { writeFileSync } from 'fs';
import type { AnalysisResult, LifecycleType } from '../types';

const LIFECYCLE_EMOJI: Record<LifecycleType, string> = {
  CRYSTALLIZED:     '💎',
  INVARIANT:        '🔷',
  FADING:           '📉',
  CATALYTIC_BIRTH:  '🌱',
  LATE_EMERGENCE:   '🌟',
  RESURRECTION:     '🔄',
  ABSORBED:         '🔀',
  PRUNED_EARLY:     '✂️',
  TRANSITION_ONLY:  '⚡',
};

function fmt(n: number): string {
  return n === Infinity ? '∞' : n.toFixed(n >= 10 ? 0 : 1);
}

export function printReport(r: AnalysisResult): void {
  const { config, docs, concepts, lifecycles, paskEdges, bursts, crossovers } = r;
  const nEpochs = config.epochs.length;

  // ── Header ─────────────────────────────────────────────────────────────────
  console.log(`\n${'═'.repeat(72)}`);
  console.log(`Architectural Crystallization Analysis — ${config.project}`);
  console.log(`${'═'.repeat(72)}`);

  // ── Corpus summary ─────────────────────────────────────────────────────────
  console.log('\n── Corpus');
  for (let ei = 0; ei < nEpochs; ei++) {
    const epochDocs = docs.filter(d => d.epochIndex === ei);
    const words = epochDocs.reduce((s, d) => s + d.wordCount, 0);
    console.log(`  ${config.epochs[ei].name.padEnd(20)} ${epochDocs.length.toString().padStart(5)} docs   ${words.toLocaleString().padStart(10)} words`);
  }
  console.log(`  ${'TOTAL'.padEnd(20)} ${docs.length.toString().padStart(5)} docs   ${docs.reduce((s, d) => s + d.wordCount, 0).toLocaleString().padStart(10)} words`);

  // ── Lifecycle summary ──────────────────────────────────────────────────────
  const byType = new Map<LifecycleType, typeof lifecycles>();
  for (const lc of lifecycles) {
    const arr = byType.get(lc.type) ?? [];
    arr.push(lc);
    byType.set(lc.type, arr);
  }

  console.log('\n── Lifecycle types');
  for (const [type, items] of [...byType.entries()].sort((a, b) => b[1].length - a[1].length)) {
    console.log(`  ${LIFECYCLE_EMOJI[type]} ${type.padEnd(20)} ${items.length}`);
  }

  // ── Crystallized concepts ──────────────────────────────────────────────────
  const crystallized = (byType.get('CRYSTALLIZED') ?? [])
    .sort((a, b) => b.amplification - a.amplification);
  if (crystallized.length > 0) {
    console.log('\n── Crystallized concepts (amplified ≥ ' + (config.amplificationThreshold ?? 10) + '×)');
    console.log(`  ${'concept'.padEnd(22)} ${'×amp'.padStart(8)}   epoch counts`);
    for (const lc of crystallized) {
      const bar = lc.epochCounts.map(c => c.toString().padStart(7)).join(' ');
      const amp = lc.amplification === Infinity ? '∞' : `${lc.amplification.toFixed(0)}×`;
      console.log(`  ${lc.concept.padEnd(22)} ${amp.padStart(8)}   ${bar}`);
    }
  }

  // ── Burst events ──────────────────────────────────────────────────────────
  if (bursts.length > 0) {
    console.log('\n── Burst events (top 15)');
    for (const b of bursts.slice(0, 15)) {
      console.log(`  ${b.isoWeek}  ${b.concept.padEnd(22)} ${b.mentions.toString().padStart(5)} mentions  ${b.magnitude.toFixed(0)}× trailing avg`);
    }
  }

  // ── Crossover events ──────────────────────────────────────────────────────
  if (crossovers.length > 0) {
    console.log('\n── Crossover events');
    for (const c of crossovers) {
      console.log(`  ${c.isoWeek}  ${c.rising} overtook ${c.falling}`);
    }
  }

  // ── Stable concept pairs (Pask) ────────────────────────────────────────────
  if (paskEdges.length > 0) {
    console.log('\n── Top stable concept pairs (Pask co-occurrence stability)');
    for (const e of paskEdges.slice(0, 15)) {
      console.log(`  score=${e.score.toFixed(3)}  coocs=${e.coocs.toString().padStart(4)}  ${e.a} ↔ ${e.b}`);
    }
  }

  console.log(`\n${'═'.repeat(72)}\n`);
}

export function writeMarkdownReport(r: AnalysisResult, outputPrefix: string): void {
  const { config, docs, concepts, lifecycles, paskEdges, bursts, crossovers } = r;
  const nEpochs = config.epochs.length;
  const epochHeaders = config.epochs.map(e => e.name).join(' | ');

  const epochSummaryRows = config.epochs.map((e, ei) => {
    const d = docs.filter(x => x.epochIndex === ei);
    const w = d.reduce((s, x) => s + x.wordCount, 0);
    return `| ${e.name} | ${d.length} | ${w.toLocaleString()} |`;
  }).join('\n');

  const lifecycleRows = lifecycles.map(lc => {
    const amp = lc.amplification === Infinity ? '∞' : `${lc.amplification.toFixed(0)}×`;
    const counts = lc.epochCounts.join(' / ');
    return `| ${LIFECYCLE_EMOJI[lc.type]} ${lc.type} | ${lc.concept} | ${amp} | ${counts} | ${lc.paskScore.toFixed(3)} |`;
  }).join('\n');

  const burstRows = bursts.slice(0, 20).map(b =>
    `| ${b.isoWeek} | ${b.concept} | ${b.mentions} | ${b.magnitude.toFixed(1)}× |`
  ).join('\n');

  const crossoverRows = crossovers.map(c =>
    `| ${c.isoWeek} | ${c.rising} | ${c.falling} |`
  ).join('\n');

  const paskRows = paskEdges.slice(0, 20).map(e =>
    `| ${e.a} ↔ ${e.b} | ${e.coocs} | ${e.score.toFixed(3)} |`
  ).join('\n');

  const crystallized = lifecycles.filter(l => l.type === 'CRYSTALLIZED');
  const byType = new Map<LifecycleType, number>();
  for (const lc of lifecycles) byType.set(lc.type, (byType.get(lc.type) ?? 0) + 1);
  const typeRows = [...byType.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([t, n]) => `| ${LIFECYCLE_EMOJI[t]} ${t} | ${n} |`)
    .join('\n');

  const md = `# Architectural Crystallization Analysis: ${config.project}

**Generated:** ${new Date().toISOString().slice(0, 10)}
**Epochs:** ${nEpochs}  |  **Concepts tracked:** ${concepts.length}  |  **Documents:** ${docs.length}

## Corpus summary

| Epoch | Documents | Words |
|---|---|---|
${epochSummaryRows}

## Lifecycle type distribution

| Type | Count |
|---|---|
${typeRows}

## Concept lifecycle table

| Type | Concept | Amplification | Epoch counts (${epochHeaders}) | Pask score |
|---|---|---|---|---|
${lifecycleRows}

## Crystallized concepts (${crystallized.length})

${crystallized.length === 0 ? '_None at current threshold._' : crystallized
  .sort((a, b) => b.amplification - a.amplification)
  .map(lc => `- **${lc.concept}** — ${lc.amplification === Infinity ? '∞' : lc.amplification.toFixed(0)}× amplification  (${lc.epochCounts.join(' → ')})`)
  .join('\n')}

## Burst events

| Week | Concept | Mentions | Magnitude |
|---|---|---|---|
${burstRows || '_No burst events detected._'}

## Crossover events

| Week | Rising | Falling |
|---|---|---|
${crossoverRows || '_No crossovers detected._'}

## Top stable concept pairs (Pask co-occurrence)

| Pair | Co-occurrences | Score |
|---|---|---|
${paskRows || '_No stable pairs above threshold._'}
`;

  writeFileSync(`${outputPrefix}.md`, md);
  writeFileSync(`${outputPrefix}.json`, JSON.stringify({
    meta:       { project: config.project, epochs: config.epochs.map(e => e.name), concepts: concepts.length, docs: docs.length },
    lifecycles: lifecycles.map(lc => ({ ...lc, amplification: lc.amplification === Infinity ? null : lc.amplification })),
    bursts:     bursts.slice(0, 50),
    crossovers,
    paskEdges:  paskEdges.slice(0, 50),
  }, null, 2));
}

```
