---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/crystallization/lib/lifecycle.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.555295+00:00
---

# tools/crystallization/lib/lifecycle.ts

```ts
import type {
  AnalysisConfig, ConceptDef, ConceptEpochStats, ConceptLifecycle,
  CorpusDoc, LifecycleType,
} from '../types';
import type { MiniPask } from './pask';

export function buildEpochStats(
  docs: CorpusDoc[],
  concepts: ConceptDef[],
  config: AnalysisConfig,
): ConceptEpochStats[] {
  const stats: ConceptEpochStats[] = [];
  const nEpochs = config.epochs.length;

  for (const concept of concepts) {
    for (let ei = 0; ei < nEpochs; ei++) {
      const epochDocs = docs.filter(d => d.epochIndex === ei);
      let totalMentions = 0;
      let docsCount = 0;
      const weeklyMap = new Map<string, number>();

      for (const doc of epochDocs) {
        const m = doc.mentions.get(concept.name) ?? 0;
        if (m > 0) {
          totalMentions += m;
          docsCount++;
          weeklyMap.set(doc.isoWeek, (weeklyMap.get(doc.isoWeek) ?? 0) + m);
        }
      }

      stats.push({
        concept:    concept.name,
        epochIndex: ei,
        epochName:  config.epochs[ei].name,
        docs:       docsCount,
        mentions:   totalMentions,
        weeklyPeak: weeklyMap.size > 0 ? Math.max(...weeklyMap.values()) : 0,
      });
    }
  }
  return stats;
}

export function classifyLifecycles(
  epochStats: ConceptEpochStats[],
  concepts: ConceptDef[],
  config: AnalysisConfig,
  pask: MiniPask,
): ConceptLifecycle[] {
  const nEpochs = config.epochs.length;
  const ampThreshold = config.amplificationThreshold ?? 10;
  const minMentions  = config.minMentions ?? 5;
  const results: ConceptLifecycle[] = [];

  for (const concept of concepts) {
    const counts = Array.from({ length: nEpochs }, (_, i) => {
      const s = epochStats.find(s => s.concept === concept.name && s.epochIndex === i);
      return s?.mentions ?? 0;
    });

    const totalMentions = counts.reduce((s, c) => s + c, 0);
    if (totalMentions < minMentions) continue;

    const firstEpoch = counts.findIndex(c => c > 0);
    const lastEpoch  = counts.reduce((last, c, i) => (c > 0 ? i : last), -1);
    const firstCount = counts[firstEpoch] ?? 0;
    const lastCount  = counts[lastEpoch]  ?? 0;
    const amp = firstCount === 0 ? Infinity : lastCount / firstCount;

    const type = classifyType({
      counts, nEpochs, firstEpoch, lastEpoch, amp, ampThreshold,
    });

    results.push({
      concept:     concept.name,
      type,
      epochCounts: counts,
      amplification: amp,
      firstEpoch,
      lastEpoch,
      paskScore: pask.stabilityScore(concept.name),
    });
  }

  return results.sort((a, b) => {
    const order: LifecycleType[] = [
      'CRYSTALLIZED','INVARIANT','FADING','CATALYTIC_BIRTH','LATE_EMERGENCE',
      'RESURRECTION','ABSORBED','PRUNED_EARLY','TRANSITION_ONLY',
    ];
    return order.indexOf(a.type) - order.indexOf(b.type);
  });
}

function classifyType(p: {
  counts: number[]; nEpochs: number; firstEpoch: number; lastEpoch: number;
  amp: number; ampThreshold: number;
}): LifecycleType {
  const { counts, nEpochs, firstEpoch, lastEpoch, amp, ampThreshold } = p;
  const presentEpochs = counts.filter(c => c > 0).length;
  const inFinal    = counts[nEpochs - 1] > 0;
  const inFirst    = counts[0] > 0;
  const middleEpochs = counts.slice(1, nEpochs - 1);
  const inMiddle   = middleEpochs.some(c => c > 0);
  const onlyMiddle = !inFirst && !inFinal && inMiddle;
  const onlyFirst  = inFirst && lastEpoch === 0;
  const onlyFinal  = !inFirst && !inMiddle && inFinal;

  if (onlyFirst)  return 'PRUNED_EARLY';
  if (onlyFinal)  return 'LATE_EMERGENCE';
  if (onlyMiddle) return 'TRANSITION_ONLY';

  if (inFirst && inFinal) {
    const absentMiddle = nEpochs > 2 && !inMiddle;
    if (absentMiddle)  return 'RESURRECTION';
    if (amp >= ampThreshold) return 'CRYSTALLIZED';
    const fadeRatio = counts[nEpochs - 1] / counts[0];
    if (fadeRatio < 0.2) return 'FADING';
    return 'INVARIANT';
  }

  // present in middle + final, not in first
  if (!inFirst && inFinal) return 'CATALYTIC_BIRTH';

  // present in middle, not in final (and not only middle)
  if (inFirst && !inFinal) {
    if (inMiddle) return 'ABSORBED';
    return 'FADING';
  }

  return 'INVARIANT';
}

```
