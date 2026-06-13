---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/crystallization/lib/temporal.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.556678+00:00
---

# tools/crystallization/lib/temporal.ts

```ts
import type { BurstEvent, ConceptDef, CorpusDoc, CrossoverEvent, WeeklyPoint } from '../types';

export function buildWeeklyTimeline(docs: CorpusDoc[], concepts: ConceptDef[]): WeeklyPoint[] {
  const map = new Map<string, number>(); // "concept\0week" → mentions
  for (const doc of docs) {
    for (const concept of concepts) {
      const m = doc.mentions.get(concept.name) ?? 0;
      if (m === 0) continue;
      const key = `${concept.name}\0${doc.isoWeek}`;
      map.set(key, (map.get(key) ?? 0) + m);
    }
  }
  return [...map.entries()].map(([key, mentions]) => {
    const [concept, isoWeek] = key.split('\0');
    return { concept, isoWeek, mentions };
  }).sort((a, b) => a.isoWeek.localeCompare(b.isoWeek));
}

export function detectBursts(weekly: WeeklyPoint[], burstFactor: number): BurstEvent[] {
  const byConcept = new Map<string, WeeklyPoint[]>();
  for (const pt of weekly) {
    const arr = byConcept.get(pt.concept) ?? [];
    arr.push(pt);
    byConcept.set(pt.concept, arr);
  }

  const bursts: BurstEvent[] = [];
  for (const [concept, points] of byConcept) {
    const sorted = [...points].sort((a, b) => a.isoWeek.localeCompare(b.isoWeek));
    for (let i = 4; i < sorted.length; i++) {
      const trailing = (sorted[i-1].mentions + sorted[i-2].mentions + sorted[i-3].mentions + sorted[i-4].mentions) / 4;
      if (trailing < 1) continue;
      const magnitude = sorted[i].mentions / trailing;
      if (magnitude >= burstFactor) {
        bursts.push({ concept, isoWeek: sorted[i].isoWeek, mentions: sorted[i].mentions, trailingAvg: trailing, magnitude });
      }
    }
  }
  return bursts.sort((a, b) => b.magnitude - a.magnitude);
}

export function detectCrossovers(weekly: WeeklyPoint[], topN = 20): CrossoverEvent[] {
  // Build cumulative mention series per concept
  const allWeeks = [...new Set(weekly.map(w => w.isoWeek))].sort();
  const byConcept = new Map<string, Map<string, number>>();
  for (const pt of weekly) {
    const m = byConcept.get(pt.concept) ?? new Map();
    m.set(pt.isoWeek, pt.mentions);
    byConcept.set(pt.concept, m);
  }

  // Cumulative per concept per week
  const cumulative = new Map<string, number[]>(); // concept → cumulative by week index
  for (const [concept, weekMap] of byConcept) {
    let cum = 0;
    cumulative.set(concept, allWeeks.map(w => { cum += weekMap.get(w) ?? 0; return cum; }));
  }

  const concepts = [...cumulative.keys()];
  const crossovers: CrossoverEvent[] = [];

  for (let i = 0; i < concepts.length; i++) {
    for (let j = i + 1; j < concepts.length; j++) {
      const seriesA = cumulative.get(concepts[i])!;
      const seriesB = cumulative.get(concepts[j])!;
      // Find where A overtook B and where B overtook A
      for (let w = 1; w < allWeeks.length; w++) {
        const prevDiff = seriesA[w-1] - seriesB[w-1];
        const currDiff = seriesA[w]   - seriesB[w];
        if (prevDiff <= 0 && currDiff > 0) {
          crossovers.push({ isoWeek: allWeeks[w], rising: concepts[i], falling: concepts[j] });
        } else if (prevDiff >= 0 && currDiff < 0) {
          crossovers.push({ isoWeek: allWeeks[w], rising: concepts[j], falling: concepts[i] });
        }
      }
    }
  }

  return crossovers
    .sort((a, b) => a.isoWeek.localeCompare(b.isoWeek))
    .slice(0, topN);
}

```
