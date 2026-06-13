---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/intent-classifier/__tests__/embedding-ranker.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.123023+00:00
---

# runtime/services/src/services/intent-classifier/__tests__/embedding-ranker.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  buildScoreMap,
  rankFastPathByEmbedding,
  scoreOptionsForLevel,
} from '../embedding-ranker';
import type { FastPathEntry, IntentTaxonomyNode } from '../../IntentTaxonomy';
import type { UtteranceEmbeddingResult } from '../utterance-embedding-cache';

const result = (
  ranked: Array<{ path: string; score: number }>,
): UtteranceEmbeddingResult => ({
  vector: new Float32Array([0]),
  ranked,
  latencyMs: 1,
});

describe('buildScoreMap', () => {
  test('1. empty input → empty map', () => {
    expect(buildScoreMap(result([]))).toEqual(new Map());
  });
  test('2. preserves insertion order via Map semantics', () => {
    const map = buildScoreMap(result([{ path: 'a', score: 0.1 }, { path: 'b', score: 0.2 }]));
    expect([...map.keys()]).toEqual(['a', 'b']);
  });
});

describe('rankFastPathByEmbedding', () => {
  const entries: FastPathEntry[] = [
    { intent: 'job', flowId: 'f-job', nodeId: 'create.job', examples: ['create job'] },
    { intent: 'pet', flowId: 'f-pet', nodeId: 'add.pet', examples: ['add pet'] },
    { intent: 'mystery', flowId: 'f-myst', nodeId: 'unknown.path', examples: [] },
  ];

  test('3. orders by ranked score', () => {
    const ranked = rankFastPathByEmbedding(
      entries,
      result([{ path: 'add.pet', score: 0.8 }, { path: 'create.job', score: 0.6 }]),
    );
    expect(ranked.map((e) => e.intent)).toEqual(['pet', 'job', 'mystery']);
  });

  test('4. unscored entries fall to the back', () => {
    const ranked = rankFastPathByEmbedding(
      entries,
      result([{ path: 'create.job', score: 0.9 }]),
    );
    expect(ranked[0]!.intent).toBe('job');
    // The other two are unscored — relative order is fine, but neither is first.
    expect(ranked.slice(1).map((e) => e.intent).sort()).toEqual(['mystery', 'pet']);
  });

  test('5. empty ranked leaves order untouched', () => {
    const ranked = rankFastPathByEmbedding(entries, result([]));
    expect(ranked.map((e) => e.intent)).toEqual(['job', 'pet', 'mystery']);
  });
});

describe('scoreOptionsForLevel', () => {
  const node = (id: string, label = id): IntentTaxonomyNode =>
    ({ id, label, description: '', examples: [] }) as unknown as IntentTaxonomyNode;

  test('6. scores by direct path match', () => {
    const scored = scoreOptionsForLevel(
      ['create'],
      [node('job'), node('asset')],
      result([{ path: 'create.job', score: 0.9 }, { path: 'create.asset', score: 0.5 }]),
    );
    expect(scored.map((s) => s.opt.id)).toEqual(['job', 'asset']);
    expect(scored[0]!.score).toBe(0.9);
  });

  test('7. falls back to best child score on prefix match', () => {
    const scored = scoreOptionsForLevel(
      [],
      [node('create')],
      result([
        { path: 'create.job.plumbing', score: 0.6 },
        { path: 'create.job.electric', score: 0.85 },
      ]),
    );
    expect(scored[0]!.opt.id).toBe('create');
    expect(scored[0]!.score).toBe(0.85);
  });

  test('8. unscored options sort behind scored ones', () => {
    const scored = scoreOptionsForLevel(
      ['create'],
      [node('job'), node('mystery')],
      result([{ path: 'create.job', score: 0.7 }]),
    );
    expect(scored[0]!.opt.id).toBe('job');
    expect(scored[1]!.score).toBeUndefined();
  });
});

```
