---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/policy.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.152099+00:00
---

# runtime/legacy-ingest/src/__tests__/policy.test.ts

```ts
import { describe, it, expect } from 'bun:test';
import { IngestPolicy, type PaskQueryAdapter, type PolicyConfig } from '../policy';
import type { Proposal } from '../extractor/types';

function makeProposal(confidence: number, email = 'alice@example.com'): Proposal {
  return {
    proposalId: 'prop-001',
    confidence,
    status: 'pending',
    provenance: {
      providerId: 'gmail',
      providerItemId: 'msg-001',
      fetchedAt: 0,
      extractorVersion: 'email-rfc822-v0.2',
      promptHash: 'h00000000',
    },
    extractedAt: 0,
    program: {
      primaryNodeId: '$s0',
      programGovernance: {} as any,
      nodes: [{
        id: '$s0',
        category: {} as any,
        taxonomy: {} as any,
        identity: {} as any,
        governance: {} as any,
        action: 'create_quote_request',
        constraint: {} as any,
        target: { kind: 'identity', id: email } as any,
        provenance: { source: 'inferred', confidence, inferenceRunId: 'msg-001', expressedAt: '', trustAtExpression: 'cosmetic' },
      }],
    },
    summary: 'Quote request',
  };
}

function makePask(hStateByEmail: Record<string, number>): PaskQueryAdapter {
  return {
    stableThreads(_opts) {
      return Object.entries(hStateByEmail).map(([email, hState]) => ({
        cellId: `ingest:customer:${djb2(email)}`,
        hState,
        trafficCount: 5,
      }));
    },
  };
}

/** Mirror of the hash function in policy.ts for test assertions. */
function djb2(s: string): string {
  const lower = s.trim().toLowerCase();
  let h = 5381;
  for (let i = 0; i < lower.length; i++) {
    h = ((h << 5) + h) + lower.charCodeAt(i);
    h = h | 0;
  }
  return (h >>> 0).toString(16).padStart(8, '0');
}

describe('IngestPolicy.evaluate', () => {
  it('returns auto-ratify when Pask score and confidence are both high', () => {
    const pask = makePask({ 'alice@example.com': 10.0 }); // normalised → 1.0
    const policy = new IngestPolicy(pask, { autoRatifyThreshold: 0.80, minConfidence: 0.70 });
    const decision = policy.evaluate(makeProposal(0.90, 'alice@example.com'));
    expect(decision.action).toBe('auto-ratify');
    expect(decision.paskScore).toBeCloseTo(1.0);
    expect(decision.confidence).toBe(0.90);
  });

  it('does not auto-ratify when confidence is below minConfidence', () => {
    const pask = makePask({ 'alice@example.com': 10.0 });
    const policy = new IngestPolicy(pask, { minConfidence: 0.80, autoRatifyThreshold: 0.75 });
    const decision = policy.evaluate(makeProposal(0.65, 'alice@example.com'));
    expect(decision.action).not.toBe('auto-ratify');
  });

  it('returns flag-review for moderate combined score', () => {
    // paskScore = 0.4 (h=2.0), confidence = 0.6
    // combined = 0.4 * 0.40 + 0.6 * 0.60 = 0.16 + 0.36 = 0.52
    const pask = makePask({ 'bob@example.com': 2.0 });
    const policy = new IngestPolicy(pask, {
      autoRatifyThreshold: 0.80,
      flagReviewThreshold: 0.50,
    });
    const decision = policy.evaluate(makeProposal(0.60, 'bob@example.com'));
    expect(decision.action).toBe('flag-review');
    expect(decision.score).toBeGreaterThan(0.50);
    expect(decision.score).toBeLessThan(0.80);
  });

  it('returns skip for low combined score', () => {
    const pask = makePask({});
    const policy = new IngestPolicy(pask, {
      autoRatifyThreshold: 0.80,
      flagReviewThreshold: 0.50,
    });
    const decision = policy.evaluate(makeProposal(0.55, 'unknown@example.com'));
    // paskScore = 0, confidence = 0.55, combined = 0.55 * 0.60 = 0.33
    expect(decision.action).toBe('skip');
    expect(decision.paskScore).toBe(0);
  });

  it('uses zero pask score for unknown customer', () => {
    const pask = makePask({ 'alice@example.com': 8.0 });
    const policy = new IngestPolicy(pask);
    const decision = policy.evaluate(makeProposal(0.95, 'charlie@example.com'));
    expect(decision.paskScore).toBe(0);
  });

  it('normalises h-state: h=5.0 maps to paskScore=1.0, h=2.5 maps to 0.5', () => {
    for (const [hState, expected] of [[5.0, 1.0], [2.5, 0.5], [0.0, 0.0]] as const) {
      const pask = makePask({ 'dave@example.com': hState });
      const policy = new IngestPolicy(pask, { paskWeight: 1.0, minConfidence: 0, autoRatifyThreshold: 0 });
      const decision = policy.evaluate(makeProposal(0.0, 'dave@example.com'));
      expect(decision.paskScore).toBeCloseTo(expected, 5);
    }
  });

  it('h-state above 5.0 is clamped to paskScore=1.0', () => {
    const pask = makePask({ 'eve@example.com': 100.0 });
    const policy = new IngestPolicy(pask);
    const decision = policy.evaluate(makeProposal(0.9, 'eve@example.com'));
    expect(decision.paskScore).toBe(1.0);
  });

  it('includes a readable reason string', () => {
    const pask = makePask({ 'frank@example.com': 5.0 });
    const policy = new IngestPolicy(pask, { autoRatifyThreshold: 0.80, minConfidence: 0.70 });
    const decision = policy.evaluate(makeProposal(0.90, 'frank@example.com'));
    expect(decision.reason).toContain('combined=');
    expect(decision.reason).toContain('pask=');
    expect(decision.reason).toContain('conf=');
  });
});

describe('IngestPolicy.trustedCustomers', () => {
  it('returns customers whose paskScore meets the threshold', () => {
    const pask = makePask({
      'alice@example.com': 8.0,   // paskScore = 1.0 → trusted
      'bob@example.com': 1.0,     // paskScore = 0.2 → not trusted
      'carol@example.com': 5.0,   // paskScore = 1.0 → trusted
    });
    const policy = new IngestPolicy(pask, {
      autoRatifyThreshold: 0.80,
      paskWeight: 0.40,
    });
    const trusted = policy.trustedCustomers(10);
    // threshold for paskScore: autoRatifyThreshold * paskWeight = 0.80 * 0.40 = 0.32
    // alice=1.0, carol=1.0 both pass; bob=0.2 doesn't
    expect(trusted.length).toBe(2);
    expect(trusted.every(t => t.paskScore >= 0.32)).toBe(true);
  });

  it('respects the limit parameter', () => {
    const emails: Record<string, number> = {};
    for (let i = 0; i < 20; i++) emails[`user${i}@example.com`] = 6.0;
    const pask = makePask(emails);
    const policy = new IngestPolicy(pask);
    const trusted = policy.trustedCustomers(5);
    expect(trusted.length).toBeLessThanOrEqual(5);
  });
});

```
