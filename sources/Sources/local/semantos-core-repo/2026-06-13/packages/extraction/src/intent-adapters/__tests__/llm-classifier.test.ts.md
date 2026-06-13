---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/intent-adapters/__tests__/llm-classifier.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.465545+00:00
---

# packages/extraction/src/intent-adapters/__tests__/llm-classifier.test.ts

```ts
/**
 * Live tests for the Anthropic-backed classifier.
 *
 * These tests hit the real Claude API. Set ANTHROPIC_API_KEY in .env
 * or in your shell to run them; otherwise they are skipped.
 *
 *   export ANTHROPIC_API_KEY=sk-ant-...
 *   cd packages/extraction && bun test
 */

import { describe, expect, test } from 'bun:test';
import { createAnthropicClassifier } from '../llm-classifier';
import { TRADES_GRAMMAR } from '../trades-grammar';
import type {
  ClassifierInput,
  HatContext,
  PatchId,
  Signature,
} from '@semantos/intent';

const HAS_KEY = Boolean(process.env.ANTHROPIC_API_KEY);
const run = HAS_KEY ? test : test.skip;

const stubSig: Signature = {
  bytes: new Uint8Array([0xaa, 0xbb]),
  algorithm: 'stub-ed25519',
  keyId: 'test-key-1',
};

const mkHat = (over: Partial<HatContext> = {}): HatContext => ({
  hatId: 'hat-tenant',
  facetId: 'hat-tenant',
  certId: 'cert-tenant',
  capabilities: [1, 2, 3],
  extensionId: 'odd-job-todd',
  domainFlag: 7,
  maxTrustClass: 'interpretive',
  ...over,
});

let intentCounter = 0;
const classifier = createAnthropicClassifier({
  grammar: TRADES_GRAMMAR,
  sign: () => stubSig,
  generateIntentId: () => `intent-live-${++intentCounter}`,
});

const mkInput = (over: Partial<ClassifierInput>): ClassifierInput => ({
  body: '',
  conversationPatchId: 'patch-live-1' as PatchId,
  objectId: 'job-live-42',
  hat: mkHat(),
  source: 'nl',
  pendingProposals: [],
  ...over,
});

describe('Anthropic classifier — live API', () => {
  run(
    'NO_INTENT: chit-chat message → no_intent',
    async () => {
      const outcome = await classifier.classify(
        mkInput({ body: 'thanks, got it' }),
      );
      expect(outcome.kind).toBe('no_intent');
      if (outcome.kind === 'no_intent') {
        expect(outcome.reason.length).toBeGreaterThan(0);
      }
    },
    30_000,
  );

  run(
    'PROPOSES: tenant reports a dripping tap → proposes with report_issue action',
    async () => {
      const outcome = await classifier.classify(
        mkInput({
          body: 'the kitchen tap has been dripping for three days, can someone take a look?',
          hat: mkHat({ hatId: 'hat-tenant' }),
        }),
      );
      expect(outcome.kind).toBe('proposes');
      if (outcome.kind === 'proposes') {
        expect(outcome.intent.action).toBe('report_issue');
        expect(outcome.intent.category).toBe('declaration');
        expect(outcome.intent.summary.length).toBeGreaterThan(0);
        expect(outcome.intent.taxonomy.what).toContain('maintenance');
        expect(outcome.intent.source).toBe('nl');
      }
    },
    30_000,
  );

  run(
    'RATIFIES: landlord "approved" with a pending quote-approval proposal',
    async () => {
      const pendingPatchId = 'cell-quote-approval-1' as PatchId;
      const outcome = await classifier.classify(
        mkInput({
          body: 'approved, proceed with the plumber',
          hat: mkHat({
            hatId: 'hat-landlord',
            capabilities: [1, 2, 3, 7, 8],
          }),
          pendingProposals: [
            {
              patchId: pendingPatchId,
              summary: '$850 plumber quote awaiting landlord approval',
            },
          ],
        }),
      );
      expect(outcome.kind).toBe('ratifies');
      if (outcome.kind === 'ratifies') {
        expect(outcome.pendingPatchId).toBe(pendingPatchId);
        expect(outcome.attestation.algorithm).toBe('stub-ed25519');
        expect(outcome.attestation.bytes.length).toBeGreaterThan(0);
      }
    },
    30_000,
  );

  run(
    'RATIFIES vs PROPOSES disambiguation: "approved" without pending proposal → proposes or no_intent, never ratifies',
    async () => {
      const outcome = await classifier.classify(
        mkInput({
          body: 'approved, proceed',
          hat: mkHat({ hatId: 'hat-landlord' }),
          pendingProposals: [],
        }),
      );
      // With no pending proposals, the classifier should not invent one.
      expect(outcome.kind).not.toBe('ratifies');
    },
    30_000,
  );
});

describe('Anthropic classifier — env gating', () => {
  test('skip message when ANTHROPIC_API_KEY is not set', () => {
    if (!HAS_KEY) {
      console.log(
        '[llm-classifier.test] ANTHROPIC_API_KEY not set — skipping live tests. ' +
          'Set the env var (e.g. in .env) to exercise the real API path.',
      );
    }
    expect(true).toBe(true);
  });
});

```
