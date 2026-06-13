---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/evidence.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.452579+00:00
---

# packages/extraction/src/evidence.ts

```ts
/**
 * Evidence accumulator — mutable container that travels with records through stages.
 *
 * Each stage appends its evidence to the accumulator. The commit stage reads
 * the full chain and persists it alongside the semantic object.
 */

import type {
  ExtractionEvidence,
  FetchEvidence,
  ParseEvidence,
  TypecheckEvidence,
  InferenceEvidence,
  CommitEvidence,
} from './stages';

export class EvidenceAccumulator {
  private entries: ExtractionEvidence[] = [];

  constructor(private grammarVersion: string) {}

  addFetch(data: FetchEvidence): void {
    this.entries.push({
      stage: 'fetch',
      timestamp: Date.now(),
      grammarVersion: this.grammarVersion,
      stageData: data,
    });
  }

  addParse(data: ParseEvidence): void {
    this.entries.push({
      stage: 'parse',
      timestamp: Date.now(),
      grammarVersion: this.grammarVersion,
      stageData: data,
    });
  }

  addTypecheck(data: TypecheckEvidence): void {
    this.entries.push({
      stage: 'typecheck',
      timestamp: Date.now(),
      grammarVersion: this.grammarVersion,
      stageData: data,
    });
  }

  addInference(data: InferenceEvidence): void {
    this.entries.push({
      stage: 'infer',
      timestamp: Date.now(),
      grammarVersion: this.grammarVersion,
      stageData: data,
    });
  }

  addCommit(data: CommitEvidence): void {
    this.entries.push({
      stage: 'commit',
      timestamp: Date.now(),
      grammarVersion: this.grammarVersion,
      stageData: data,
    });
  }

  toArray(): ExtractionEvidence[] {
    return [...this.entries];
  }

  get length(): number {
    return this.entries.length;
  }
}

```
