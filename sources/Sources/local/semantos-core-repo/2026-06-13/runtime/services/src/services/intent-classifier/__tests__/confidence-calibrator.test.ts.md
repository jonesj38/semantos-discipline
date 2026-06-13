---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/intent-classifier/__tests__/confidence-calibrator.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.123331+00:00
---

# runtime/services/src/services/intent-classifier/__tests__/confidence-calibrator.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  buildEmbeddingHint,
  calibrateConfidence,
  EMBEDDING_AGREE_BOOST,
  EMBEDDING_DISAGREE_PENALTY,
} from '../confidence-calibrator';
import type { UtteranceEmbeddingResult } from '../utterance-embedding-cache';

const result = (
  ranked: Array<{ path: string; score: number }>,
  latencyMs = 12,
): UtteranceEmbeddingResult => ({
  vector: new Float32Array([1, 2, 3]),
  ranked,
  latencyMs,
});

describe('calibrateConfidence', () => {
  test('1. clamps below 0', () => {
    expect(calibrateConfidence(0.05, -0.5)).toBe(0);
  });
  test('2. clamps above 1', () => {
    expect(calibrateConfidence(0.95, 0.5)).toBe(1);
  });
  test('3. applies positive adjustment', () => {
    expect(calibrateConfidence(0.5, 0.05)).toBeCloseTo(0.55, 5);
  });
  test('4. applies negative adjustment', () => {
    expect(calibrateConfidence(0.5, -0.1)).toBeCloseTo(0.4, 5);
  });
  test('5. returns base when adjustment is zero', () => {
    expect(calibrateConfidence(0.7, 0)).toBe(0.7);
  });
});

describe('buildEmbeddingHint', () => {
  test('6. agrees on direct match', () => {
    const hint = buildEmbeddingHint(result([{ path: 'create.job', score: 0.91 }]), 'create.job');
    expect(hint.embeddingAgreed).toBe(true);
    expect(hint.confidenceAdjustment).toBe(EMBEDDING_AGREE_BOOST);
  });
  test('7. agrees when LLM intent is suffix of embedding pick', () => {
    const hint = buildEmbeddingHint(result([{ path: 'create.job', score: 0.88 }]), 'job');
    expect(hint.embeddingAgreed).toBe(true);
  });
  test('8. agrees when embedding pick is suffix of LLM intent', () => {
    const hint = buildEmbeddingHint(result([{ path: 'job', score: 0.88 }]), 'create.job');
    expect(hint.embeddingAgreed).toBe(true);
  });
  test('9. disagrees on different paths', () => {
    const hint = buildEmbeddingHint(
      result([{ path: 'discover.asset', score: 0.7 }]),
      'create.job',
    );
    expect(hint.embeddingAgreed).toBe(false);
    expect(hint.confidenceAdjustment).toBe(EMBEDDING_DISAGREE_PENALTY);
  });
  test('10. disagrees when ranked is empty', () => {
    const hint = buildEmbeddingHint(result([]), 'create.job');
    expect(hint.embeddingAgreed).toBe(false);
    expect(hint.confidenceAdjustment).toBe(EMBEDDING_DISAGREE_PENALTY);
  });
  test('11. forwards latencyMs and rankedOptions', () => {
    const hint = buildEmbeddingHint(
      result([{ path: 'a', score: 1 }], 99),
      'a',
    );
    expect(hint.embeddingLatencyMs).toBe(99);
    expect(hint.rankedOptions).toEqual([{ path: 'a', score: 1 }]);
  });
});

```
