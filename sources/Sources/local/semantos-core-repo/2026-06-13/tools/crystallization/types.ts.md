---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/crystallization/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.544763+00:00
---

# tools/crystallization/types.ts

```ts
export interface ConceptDef {
  name:        string;
  aliases:     string[];   // all strings to search for (case-insensitive)
  description: string;
}

export interface EpochConfig {
  name:       string;        // e.g. "Discovery"
  path:       string;        // absolute path to repo/directory
  label?:     string;        // short label for tables
  dateRange?: [string, string]; // ISO dates — filter docs by git timestamp
}

export interface AnalysisConfig {
  project:                 string;
  epochs:                  EpochConfig[];
  vocabularyFile?:         string;           // path to vocab JSON file
  autoVocabSize?:          number;           // concepts to auto-extract if no vocab
  burstFactor?:            number;           // burst = week > N × trailing avg (default 3)
  amplificationThreshold?: number;           // crystallized if amp ≥ N (default 10)
  minMentions?:            number;           // ignore concepts with < N total mentions
  paskMinCoocs?:           number;           // min co-occurrences for Pask edge (default 3)
}

/** One document in the corpus. */
export interface CorpusDoc {
  path:          string;
  epochIndex:    number;
  epochName:     string;
  commitTs:      number;    // unix seconds (0 if unknown)
  isoWeek:       string;    // "YYYY-WNN"
  wordCount:     number;
  /** concept name → mention count in this doc */
  mentions:      Map<string, number>;
}

/** Per-concept, per-epoch aggregated stats. */
export interface ConceptEpochStats {
  concept:     string;
  epochIndex:  number;
  epochName:   string;
  docs:        number;   // docs mentioning it
  mentions:    number;   // total mentions
  weeklyPeak:  number;   // highest mentions in a single week
}

/** Weekly mention count for a concept. */
export interface WeeklyPoint {
  concept:   string;
  isoWeek:   string;
  mentions:  number;
}

export type LifecycleType =
  | 'CRYSTALLIZED'       // low epoch-1, high final (amplified ≥ threshold)
  | 'INVARIANT'          // consistently present, no dramatic change
  | 'FADING'             // high epoch-1, low final
  | 'CATALYTIC_BIRTH'    // first appears in a middle epoch, survives to final
  | 'LATE_EMERGENCE'     // first appears only in the final epoch
  | 'RESURRECTION'       // present epoch-1, absent middle, returns final
  | 'ABSORBED'           // present in middle epochs only, gone in final
  | 'PRUNED_EARLY'       // present only in first epoch
  | 'TRANSITION_ONLY';   // present only in middle epoch(s)

export interface ConceptLifecycle {
  concept:           string;
  type:              LifecycleType;
  epochCounts:       number[];          // mention count per epoch
  amplification:     number;            // final / first (Infinity if first=0)
  firstEpoch:        number;            // index of first epoch with mentions
  lastEpoch:         number;            // index of last epoch with mentions
  paskScore:         number;            // stability score from mini-Pask
}

export interface BurstEvent {
  concept:    string;
  isoWeek:    string;
  mentions:   number;
  trailingAvg: number;
  magnitude:  number;   // mentions / trailingAvg
}

export interface CrossoverEvent {
  isoWeek:   string;
  rising:    string;   // concept that overtook
  falling:   string;   // concept it overtook
}

export interface PaskEdge {
  a:       string;
  b:       string;
  coocs:   number;    // co-occurrence count
  score:   number;    // normalised stability score
}

export interface AnalysisResult {
  config:      AnalysisConfig;
  concepts:    ConceptDef[];
  docs:        CorpusDoc[];
  lifecycles:  ConceptLifecycle[];
  paskEdges:   PaskEdge[];
  bursts:      BurstEvent[];
  crossovers:  CrossoverEvent[];
}

```
