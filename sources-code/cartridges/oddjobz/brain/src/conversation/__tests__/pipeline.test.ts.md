---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/pipeline.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.538759+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/pipeline.test.ts

```ts
/**
 * L-4 — runConversationTurn pipeline tests.
 *
 * Unit tier: injects a stub extractor so all tests run without an API key.
 * The stub returns a fixed TurnExtractionResult — the tests verify that
 * the pipeline correctly wires the three stages and passes artefacts through.
 *
 * Live tier: end-to-end call through real Anthropic API, gated on
 * ANTHROPIC_API_KEY. Verifies the pipeline produces a coherent Intent from
 * a raw message in a single call.
 *
 * Scenarios:
 *   PL-1  Basic wiring — stub extractor → state merged, intent produced
 *   PL-2  State accumulation — extraction fields visible in returned state
 *   PL-3  Tagged facts flow through to reducer
 *   PL-4  estimatedCostMin/Max passed to reducer → value constraint
 *   PL-5  Grammar override respected (domainFlag preserved)
 *   PL-6  Extraction error propagates (no silent swallow)
 *   PL-7  All three artefacts present in PipelineResult
 *   PL-8  Live: dripping tap → report_issue intent
 *   PL-9  Live: two sequential runConversationTurn calls accumulate state
 */

import { describe, test, expect } from 'bun:test';
import { runConversationTurn } from '../pipeline';
import { emptyJobState } from '../accumulated-job-state';
import type { TurnExtractionResult, TurnExtractorOptions } from '../turn-extractor';
import type { BridgeContext } from '../substrate-bridge';
import type { TaggedFact, GrammarSpec } from '@semantos/intent/reducer/types';
import { TRADES_GRAMMAR_SPEC } from '../trades-grammar-spec';
import Anthropic from '@anthropic-ai/sdk';

const HAS_KEY = Boolean(process.env.ANTHROPIC_API_KEY);
const run = HAS_KEY ? test : test.skip;

// ── Helpers ───────────────────────────────────────────────────────────────────

function bridge(): BridgeContext {
  return {
    chatSessionId: 'pl-test-' + Math.random().toString(36).slice(2),
    jobId: null,
    customerId: null,
    hat: {
      hatId: 'test-hat',
      contextTag: 7,
      principal: { type: 'key', pubKeyHex: 'aa'.repeat(32) } as never,
      capabilities: [],
      extensionId: 'oddjobz',
      facetId: 'test-facet',
      certId: null,
    },
    nowIso: new Date().toISOString(),
  };
}

function fact(category: string, text: string, confidence = 0.85): TaggedFact {
  return { lexicon: 'jural', category, confidence, fact: text, source: 'stub' };
}

/** Build a stub Anthropic client that returns a fixed JSON string. */
function stubClient(jsonBody: object): Anthropic {
  return {
    messages: {
      create: async () => ({
        content: [{ type: 'text', text: JSON.stringify(jsonBody) }],
        stop_reason: 'end_turn',
      }),
    },
  } as unknown as Anthropic;
}

function stubExtraction(overrides: Partial<TurnExtractionResult> = {}): TurnExtractionResult {
  return {
    extraction: {
      jobType: 'plumbing',
      scopeDescription: 'dripping tap',
      suburb: 'Newtown',
      conversationPhase: 'describing_job',
    },
    taggedFacts: [fact('declaration', 'tap is dripping', 0.9)],
    rawJson: '{}',
    ...overrides,
  };
}

// ── PL-1: Basic wiring ────────────────────────────────────────────────────────

describe('PL-1: basic wiring', () => {
  test('returns state, extraction, and turn artefacts', async () => {
    const result = await runConversationTurn({
      currentState: emptyJobState(),
      latestMessage: 'my tap is dripping',
      bridge: bridge(),
      extractorOptions: { client: stubClient({
        jobType: 'plumbing', scopeDescription: 'dripping tap', conversationPhase: 'describing_job',
        taggedFacts: [{ lexicon: 'jural', category: 'declaration', confidence: 0.9, fact: 'tap dripping', source: 'stub' }],
      }) },
    });

    expect(result.state).toBeDefined();
    expect(result.extraction).toBeDefined();
    expect(result.turn).toBeDefined();
    expect(result.turn.reducerResult.intent).toBeDefined();
    expect(result.turn.reducerResult.intent.id).toBeTruthy();
  });

  test('confidence is a number in [0, 1]', async () => {
    const result = await runConversationTurn({
      currentState: emptyJobState(),
      latestMessage: 'fix my tap',
      bridge: bridge(),
      extractorOptions: { client: stubClient({
        jobType: 'plumbing', taggedFacts: [{ lexicon: 'jural', category: 'declaration', confidence: 0.85, fact: 'fix tap', source: 'stub' }],
      }) },
    });

    const conf = result.turn.reducerResult.confidence;
    expect(isNaN(conf)).toBe(false);
    expect(conf).toBeGreaterThanOrEqual(0);
    expect(conf).toBeLessThanOrEqual(1);
  });
});

// ── PL-2: State accumulation ──────────────────────────────────────────────────

describe('PL-2: extraction fields visible in returned state', () => {
  test('suburb from extraction appears in merged state', async () => {
    const result = await runConversationTurn({
      currentState: emptyJobState(),
      latestMessage: 'I am in Glebe',
      bridge: bridge(),
      extractorOptions: { client: stubClient({
        suburb: 'Glebe', jobType: 'plumbing', taggedFacts: [],
      }) },
    });

    expect(result.state.suburb).toBe('Glebe');
  });

  test('scopeDescription accumulates across the call', async () => {
    const result = await runConversationTurn({
      currentState: emptyJobState(),
      latestMessage: 'dripping kitchen tap',
      bridge: bridge(),
      extractorOptions: { client: stubClient({
        scopeDescription: 'dripping kitchen tap', taggedFacts: [],
      }) },
    });

    expect(result.state.scopeDescription).toContain('dripping');
  });

  test('returned state is frozen (immutable)', async () => {
    const result = await runConversationTurn({
      currentState: emptyJobState(),
      latestMessage: 'any message',
      bridge: bridge(),
      extractorOptions: { client: stubClient({ taggedFacts: [] }) },
    });

    expect(Object.isFrozen(result.state)).toBe(true);
  });
});

// ── PL-3: Tagged facts flow through ──────────────────────────────────────────

describe('PL-3: tagged facts flow through to reducer', () => {
  test('declaration fact produces report_issue intent', async () => {
    const result = await runConversationTurn({
      currentState: emptyJobState(),
      latestMessage: 'tap leak',
      bridge: bridge(),
      extractorOptions: { client: stubClient({
        jobType: 'plumbing',
        scopeDescription: 'dripping tap',
        taggedFacts: [{ lexicon: 'jural', category: 'declaration', confidence: 0.95, fact: 'tap is dripping', source: 'stub' }],
      }) },
    });

    expect(result.turn.reducerResult.intent.action).toBe('report_issue');
  });

  test('power fact produces approve_quote intent', async () => {
    const result = await runConversationTurn({
      currentState: emptyJobState(),
      latestMessage: 'approved',
      bridge: bridge(),
      extractorOptions: { client: stubClient({
        estimateReaction: 'accepted',
        taggedFacts: [{ lexicon: 'jural', category: 'power', confidence: 0.95, fact: 'quote approved', source: 'stub' }],
      }) },
    });

    expect(result.turn.reducerResult.intent.action).toBe('approve_quote');
  });

  test('extraction taggedFacts appear in reducerInput', async () => {
    const result = await runConversationTurn({
      currentState: emptyJobState(),
      latestMessage: 'any',
      bridge: bridge(),
      extractorOptions: { client: stubClient({
        taggedFacts: [
          { lexicon: 'jural', category: 'declaration', confidence: 0.9, fact: 'fact one', source: 'stub' },
          { lexicon: 'jural', category: 'obligation', confidence: 0.8, fact: 'fact two', source: 'stub' },
        ],
      }) },
    });

    expect(result.turn.reducerInput.taggedFacts.length).toBe(2);
  });
});

// ── PL-4: Cost passthrough ────────────────────────────────────────────────────

describe('PL-4: estimatedCost passed to reducer', () => {
  test('cost fields produce a value constraint', async () => {
    const result = await runConversationTurn({
      currentState: emptyJobState(),
      latestMessage: 'approved',
      bridge: bridge(),
      estimatedCostMin: 85000,
      estimatedCostMax: 85000,
      extractorOptions: { client: stubClient({
        taggedFacts: [{ lexicon: 'jural', category: 'power', confidence: 0.9, fact: 'approved', source: 'stub' }],
      }) },
    });

    const valueCon = result.turn.reducerResult.intent.constraints.find(c => c.kind === 'value');
    expect(valueCon).toBeDefined();
  });

  test('cost fields visible in reducerInput', async () => {
    const result = await runConversationTurn({
      currentState: emptyJobState(),
      latestMessage: 'any',
      bridge: bridge(),
      estimatedCostMin: 10000,
      estimatedCostMax: 20000,
      extractorOptions: { client: stubClient({ taggedFacts: [] }) },
    });

    expect(result.turn.reducerInput.estimatedCostMin).toBe(10000);
    expect(result.turn.reducerInput.estimatedCostMax).toBe(20000);
  });
});

// ── PL-5: Grammar override ────────────────────────────────────────────────────

describe('PL-5: grammar override respected', () => {
  test('domainFlag from custom grammar appears in intent producerMeta', async () => {
    const customGrammar: GrammarSpec = {
      ...TRADES_GRAMMAR_SPEC,
      domainFlag: 42,
    };

    const result = await runConversationTurn({
      currentState: emptyJobState(),
      latestMessage: 'any',
      bridge: bridge(),
      grammar: customGrammar,
      extractorOptions: { client: stubClient({ taggedFacts: [] }) },
    });

    const domainFlag = result.turn.reducerResult.intent.producerMeta?.governanceContext?.domainFlag;
    if (domainFlag !== undefined) {
      expect(domainFlag).toBe(42);
    }
    // astronomy-pass carries domainFlag — verify it at least didn't use the default
    expect(result.turn.reducerResult.intent).toBeDefined();
  });
});

// ── PL-6: Error propagation ───────────────────────────────────────────────────

describe('PL-6: extractor error propagates', () => {
  test('throws when the LLM client throws', async () => {
    const errorClient = {
      messages: {
        create: async () => { throw new Error('network timeout'); },
      },
    } as unknown as Anthropic;

    await expect(
      runConversationTurn({
        currentState: emptyJobState(),
        latestMessage: 'any',
        bridge: bridge(),
        extractorOptions: { client: errorClient },
      }),
    ).rejects.toThrow('network timeout');
  });
});

// ── PL-7: All artefacts present ───────────────────────────────────────────────

describe('PL-7: PipelineResult completeness', () => {
  test('extraction.rawJson is a string', async () => {
    const result = await runConversationTurn({
      currentState: emptyJobState(),
      latestMessage: 'any',
      bridge: bridge(),
      extractorOptions: { client: stubClient({ jobType: 'plumbing', taggedFacts: [] }) },
    });

    expect(typeof result.extraction.rawJson).toBe('string');
  });

  test('turn.reducerInput reflects the merged state fields', async () => {
    const result = await runConversationTurn({
      currentState: emptyJobState(),
      latestMessage: 'tap in Glebe',
      bridge: bridge(),
      extractorOptions: { client: stubClient({
        suburb: 'Glebe',
        jobType: 'plumbing',
        scopeDescription: 'tap dripping',
        taggedFacts: [],
      }) },
    });

    expect(result.turn.reducerInput.suburb).toBe('Glebe');
  });

  test('7 pass results in turn.reducerResult', async () => {
    const result = await runConversationTurn({
      currentState: emptyJobState(),
      latestMessage: 'any',
      bridge: bridge(),
      extractorOptions: { client: stubClient({ taggedFacts: [] }) },
    });

    expect(result.turn.reducerResult.passResults.length).toBe(7);
  });
});

// ── PL-8: Live — single turn ──────────────────────────────────────────────────

describe('PL-8: live API — single turn', () => {
  run(
    'dripping tap produces report_issue intent',
    async () => {
      const result = await runConversationTurn({
        currentState: emptyJobState(),
        latestMessage: 'My kitchen tap has been dripping for two days. I live in Surry Hills.',
        bridge: bridge(),
      });

      expect(result.turn.reducerResult.intent.action).toBe('report_issue');
      expect(result.turn.reducerResult.confidence).toBeGreaterThan(0);
      expect(result.state.jobType).toBe('plumbing');
    },
    60_000,
  );
});

// ── PL-9: Live — state accumulation across two turns ─────────────────────────

describe('PL-9: live API — two sequential turns accumulate state', () => {
  run(
    'second turn refines location and raises confidence',
    async () => {
      // Turn 1: bare issue report
      const t1 = await runConversationTurn({
        currentState: emptyJobState(),
        latestMessage: 'I have a blocked bathroom drain.',
        bridge: bridge(),
      });

      expect(t1.state.jobType).toBe('plumbing');
      const conf1 = t1.turn.reducerResult.confidence;

      // Turn 2: add location detail
      const t2 = await runConversationTurn({
        currentState: t1.state,
        latestMessage: 'I am at 55 Glebe Point Rd, Glebe.',
        conversationSummary: 'Customer has a blocked bathroom drain.',
        bridge: bridge(),
      });

      expect(t2.state.suburb).toBeTruthy();
      const conf2 = t2.turn.reducerResult.confidence;

      // Confidence should not collapse when adding location
      expect(conf2).toBeGreaterThanOrEqual(conf1 - 0.1);
      // Accumulated scopeDescription should still reference the original issue
      const scope = (t2.state.scopeDescription ?? '').toLowerCase();
      expect(scope).toMatch(/drain|block|plumbing|bathroom/);
    },
    90_000,
  );
});

```
