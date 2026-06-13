---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/conversation/accumulated-job-state.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.488995+00:00
---

# cartridges/oddjobz/brain/tests/conversation/accumulated-job-state.test.ts

```ts
/**
 * D-O7 — accumulated-job-state tests.
 *
 * Acceptance:
 *  - emptyJobState sets sane defaults.
 *  - calculateSubScores matches OJT's tuned weights/thresholds.
 *  - mergeExtraction overwrites only on non-null, returns delta.
 *  - mergeScopeDescription preserves the >60% overlap heuristic.
 */

import { describe, expect, test } from 'bun:test';
import {
  emptyJobState,
  calculateSubScores,
  mergeExtraction,
  mergeScopeDescription,
} from '../../src/conversation/accumulated-job-state.js';

describe('D-O7 — accumulated-job-state — emptyJobState', () => {
  test('all sub-scores zero, conversationPhase greeting', () => {
    const s = emptyJobState();
    expect(s.scopeClarity).toBe(0);
    expect(s.locationClarity).toBe(0);
    expect(s.contactReadinessScore).toBe(0);
    expect(s.estimateReadiness).toBe(0);
    expect(s.decisionReadiness).toBe(0);
    expect(s.completenessScore).toBe(0);
    expect(s.conversationPhase).toBe('greeting');
    expect(s.estimatePresented).toBe(false);
  });
});

describe('D-O7 — accumulated-job-state — calculateSubScores', () => {
  test('scopeClarity weights match OJT origin', () => {
    const s = {
      ...emptyJobState(),
      scopeDescription: 'paint',
      jobType: 'painting',
      repairReplaceSignal: 'replace',
      quantity: '3 rooms',
      materials: 'water-based',
      accessDifficulty: 'ground_level',
      photosReferenced: true,
      urgency: 'next_week',
    };
    const sub = calculateSubScores(s);
    // 35 + 15 + 10 + 15 + 10 + 5 + 5 + 5 = 100
    expect(sub.scopeClarity).toBe(100);
  });

  test('locationClarity prioritises suburb (60) + extras', () => {
    const s = {
      ...emptyJobState(),
      suburb: 'Noosa',
      address: '12 Beach Rd',
      postcode: '4567',
      accessNotes: 'side gate',
    };
    const sub = calculateSubScores(s);
    // 60 + 25 + 10 + 5 = 100
    expect(sub.locationClarity).toBe(100);
  });

  test('contactReadiness — phone alone is 40', () => {
    const s = { ...emptyJobState(), customerPhone: '0400111222' };
    const sub = calculateSubScores(s);
    expect(sub.contactReadiness).toBe(40);
  });

  test('decisionReadiness includes the scoring-presence bonus', () => {
    const s = {
      ...emptyJobState(),
      estimatePresented: true,
      estimateAcknowledged: true,
      estimateAckStatus: 'accepted' as const,
      customerFitScore: 50,
      quoteWorthinessScore: 50,
    };
    const sub = calculateSubScores(s);
    // 15 + 20 + 10 + 10 + 10 = 65 (no scope/location/contact yet)
    expect(sub.decisionReadiness).toBe(65);
  });
});

describe('D-O7 — accumulated-job-state — mergeExtraction', () => {
  test('non-null fields overwrite, null fields preserved', () => {
    const start = { ...emptyJobState(), suburb: 'Noosa' };
    const m = mergeExtraction(start, {
      jobType: 'fencing',
      suburb: null,
    });
    expect(m.state.jobType).toBe('fencing');
    expect(m.state.suburb).toBe('Noosa');
    expect(m.deltaCount).toBeGreaterThan(0);
  });

  test('delta tracks every changed field including sub-scores', () => {
    const start = emptyJobState();
    const m = mergeExtraction(start, {
      jobType: 'fencing',
      scopeDescription: 'paling fence repair on the side',
      suburb: 'Noosa',
    });
    expect(m.delta).toHaveProperty('jobType');
    expect(m.delta).toHaveProperty('scopeDescription');
    expect(m.delta).toHaveProperty('suburb');
    // Sub-scores recompute and show in the delta when they change.
    expect(m.delta).toHaveProperty('scopeClarity');
    expect(m.delta).toHaveProperty('locationClarity');
  });

  test('jobType triggers jobTypeConfidence to ride along', () => {
    const m = mergeExtraction(emptyJobState(), {
      jobType: 'painting',
      jobTypeConfidence: 'certain',
    });
    expect(m.state.jobTypeConfidence).toBe('certain');
  });

  test('conversationPhase override propagates', () => {
    const m = mergeExtraction(emptyJobState(), {
      conversationPhase: 'reviewing_estimate',
    });
    expect(m.state.conversationPhase).toBe('reviewing_estimate');
  });
});

describe('D-O7 — accumulated-job-state — mergeScopeDescription', () => {
  test('null existing → take incoming verbatim', () => {
    expect(mergeScopeDescription(null, 'fence repair')).toBe('fence repair');
  });

  test('high-overlap restatement keeps the longer one', () => {
    const existing = 'paint the front room with white walls';
    // 7 incoming words (>2 chars), 6 of them in existing → 6/7 ≈ 0.86 > 0.6.
    const incoming =
      'paint the front room with white walls and a single coat';
    const out = mergeScopeDescription(existing, incoming);
    expect(out).toBe(incoming);
  });

  test('low-overlap augmentation concatenates', () => {
    const existing = 'paint the front room';
    const incoming = 'replace 6m of paling fence';
    const out = mergeScopeDescription(existing, incoming);
    expect(out).toContain('paint');
    expect(out).toContain('paling fence');
    expect(out).toContain('. ');
  });
});

```
