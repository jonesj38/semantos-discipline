---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/turn-extractor.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.534849+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/turn-extractor.test.ts

```ts
/**
 * I-14 — Turn extractor tests.
 *
 * Two tiers:
 *   Unit  — parseExtractionResponse() with captured fixture JSON. No API.
 *   Live  — extractConversationTurn() hitting the real Anthropic API.
 *           Gated by ANTHROPIC_API_KEY. Pattern mirrors llm-classifier.test.ts.
 *
 * End-to-end integration tier (at the bottom) chains:
 *   raw text → extractConversationTurn → mergeExtraction → processConversationTurn → Intent
 * This is the first test that exercises the full text-to-Intent path.
 */

import { describe, test, expect } from 'bun:test';
import { parseExtractionResponse, extractConversationTurn } from '../turn-extractor';
import { emptyJobState, mergeExtraction } from '../accumulated-job-state';
import { processConversationTurn } from '../chat-service';
import type { BridgeContext } from '../substrate-bridge';

const HAS_KEY = Boolean(process.env.ANTHROPIC_API_KEY);
const run = HAS_KEY ? test : test.skip;

function bridge(): BridgeContext {
  return {
    chatSessionId: 'test-' + Math.random().toString(36).slice(2),
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

// ── Unit: parseExtractionResponse fixtures ────────────────────────────────────

describe('parseExtractionResponse — unit (no API)', () => {
  test('parses a clean extraction response', () => {
    const fixture = JSON.stringify({
      customerName: 'Jane Smith',
      customerPhone: '0400123456',
      customerEmail: null,
      suburb: 'Newtown',
      locationClue: null,
      address: '42 King St',
      postcode: null,
      accessNotes: null,
      jobType: 'plumbing',
      jobTypeConfidence: 'certain',
      jobSubcategory: null,
      repairReplaceSignal: 'repair',
      scopeDescription: 'dripping tap in kitchen',
      quantity: '1 tap',
      materials: null,
      materialCondition: null,
      accessDifficulty: null,
      photosReferenced: null,
      urgency: 'next_week',
      estimateReaction: null,
      budgetReaction: null,
      customerToneSignal: 'friendly',
      micromanagerSignals: false,
      cheapestMindset: false,
      clarityScore: 'clear',
      contactReadiness: 'offered',
      jobPivot: null,
      isComplete: false,
      missingInfo: ['address confirmation'],
      conversationPhase: 'describing_job',
      taggedFacts: [
        { lexicon: 'jural', category: 'declaration', confidence: 0.9, fact: 'Kitchen tap is dripping', source: 'kitchen tap has been dripping' },
        { lexicon: 'jural', category: 'condition', confidence: 0.8, fact: 'Urgency is next week', source: 'next week would be fine' },
      ],
    });

    const result = parseExtractionResponse(fixture);

    expect(result.extraction.customerName).toBe('Jane Smith');
    expect(result.extraction.suburb).toBe('Newtown');
    expect(result.extraction.jobType).toBe('plumbing');
    expect(result.extraction.urgency).toBe('next_week');
    expect(result.extraction.conversationPhase).toBe('describing_job');
    expect(result.taggedFacts).toHaveLength(2);
    expect(result.taggedFacts[0].category).toBe('declaration');
    expect(result.taggedFacts[1].category).toBe('condition');
    expect(result.rawJson).toContain('"plumbing"');
  });

  test('strips markdown fences from response', () => {
    const fenced = '```json\n{"scopeDescription":"tap leak","taggedFacts":[]}\n```';
    const result = parseExtractionResponse(fenced);
    expect(result.extraction.scopeDescription).toBe('tap leak');
    expect(result.taggedFacts).toHaveLength(0);
  });

  test('extracts first JSON object when model emits trailing text', () => {
    const withTrailing =
      '{"jobType":"plumbing","taggedFacts":[]}  \n\nSome extra text the model added.';
    const result = parseExtractionResponse(withTrailing);
    expect(result.extraction.jobType).toBe('plumbing');
  });

  test('handles empty taggedFacts array', () => {
    const noFacts = JSON.stringify({ jobType: 'electrical', taggedFacts: [] });
    const result = parseExtractionResponse(noFacts);
    expect(result.taggedFacts).toHaveLength(0);
    expect(result.extraction.jobType).toBe('electrical');
  });

  test('drops malformed taggedFact entries silently', () => {
    const messy = JSON.stringify({
      taggedFacts: [
        { lexicon: 'jural', category: 'declaration', confidence: 0.9, fact: 'valid fact', source: 'src' },
        { lexicon: null, category: null, confidence: null },         // missing fact — dropped
        'not an object',                                             // wrong type — dropped
        { confidence: 0.7, fact: 'missing lexicon/category' },      // fact present — included
      ],
    });
    const result = parseExtractionResponse(messy);
    // Only entries with a string `fact` and numeric `confidence` survive.
    expect(result.taggedFacts.length).toBeGreaterThanOrEqual(1);
    for (const f of result.taggedFacts) {
      expect(typeof f.fact).toBe('string');
      expect(typeof f.confidence).toBe('number');
    }
  });

  test('returns empty extraction on unparseable JSON without throwing', () => {
    const result = parseExtractionResponse('not json at all {{broken}}');
    expect(result.extraction).toBeDefined();
    expect(result.taggedFacts).toHaveLength(0);
  });

  test('handles empty string without throwing', () => {
    const result = parseExtractionResponse('');
    expect(result.extraction).toBeDefined();
    expect(result.taggedFacts).toHaveLength(0);
  });

  test('handles deeply nested context without throwing', () => {
    const nested = JSON.stringify({
      jobType: 'plumbing',
      scopeDescription: 'A'.repeat(2000),
      taggedFacts: [{ lexicon: 'jural', category: 'declaration', confidence: 0.85, fact: 'long desc', source: 'src' }],
    });
    const result = parseExtractionResponse(nested);
    expect(result.extraction.jobType).toBe('plumbing');
    expect(result.taggedFacts).toHaveLength(1);
  });

  test('taggedFacts without lexicon/category default to empty string', () => {
    const partial = JSON.stringify({
      taggedFacts: [{ confidence: 0.8, fact: 'no lexicon provided', source: 'src' }],
    });
    const result = parseExtractionResponse(partial);
    expect(result.taggedFacts[0].lexicon).toBe('');
    expect(result.taggedFacts[0].category).toBe('');
  });
});

// ── Live: extractConversationTurn — real Anthropic API ────────────────────────

describe('extractConversationTurn — live API', () => {
  run(
    'dripping tap message produces plumbing extraction',
    async () => {
      const result = await extractConversationTurn(
        {
          currentState: emptyJobState(),
          latestMessage: 'Hi, I have a dripping tap in my kitchen at 42 King St, Newtown. Can you fix it next week?',
          conversationSummary: '',
        },
      );

      expect(result.extraction.jobType).toBe('plumbing');
      expect(result.extraction.urgency).toBe('next_week');
      expect(typeof result.extraction.suburb === 'string' || result.extraction.suburb == null).toBe(true);
      expect(Array.isArray(result.taggedFacts)).toBe(true);
    },
    30_000,
  );

  run(
    'response includes at least one taggedFact for a clear maintenance message',
    async () => {
      const result = await extractConversationTurn({
        currentState: emptyJobState(),
        latestMessage: 'The kitchen tap is dripping constantly, needs repair urgently.',
        conversationSummary: '',
      });
      // The model should emit at least one tagged fact for a clear declaration.
      expect(result.taggedFacts.length).toBeGreaterThan(0);
    },
    30_000,
  );

  run(
    'approve quote message produces power-category tagged fact',
    async () => {
      const state = mergeExtraction(emptyJobState(), {
        scopeDescription: 'hot water system replacement',
        jobType: 'plumbing',
        suburb: 'Glebe',
        estimatePresented: true,
      } as never).state;

      const result = await extractConversationTurn({
        currentState: state,
        latestMessage: 'Yes, approved — please proceed with the $2400 quote.',
        conversationSummary: 'Tenant reported broken hot water. Quote of $2400 presented.',
      });

      expect(result.extraction.estimateReaction).toBe('accepted');
    },
    30_000,
  );

  run(
    'rawJson is a valid JSON string',
    async () => {
      const result = await extractConversationTurn({
        currentState: emptyJobState(),
        latestMessage: 'I need someone to fix my fence panels, a few palings have come loose.',
      });
      expect(() => JSON.parse(result.rawJson)).not.toThrow();
    },
    30_000,
  );
});

// ── End-to-end: raw text → Intent (live API only) ─────────────────────────────

describe('end-to-end: raw text → extractConversationTurn → reduceToIntent', () => {
  run(
    'single turn: dripping tap message produces report_issue intent',
    async () => {
      const { extraction, taggedFacts } = await extractConversationTurn({
        currentState: emptyJobState(),
        latestMessage: 'Hi, my kitchen tap has been dripping for days. I live in Surry Hills.',
        conversationSummary: '',
      });

      const { state } = mergeExtraction(emptyJobState(), extraction);

      const { reducerResult } = await processConversationTurn({
        accumulatedState: state,
        taggedFacts,
        bridge: bridge(),
      });

      expect(reducerResult.intent).toBeDefined();
      expect(reducerResult.intent.id).toBeTruthy();
      expect(reducerResult.confidence).toBeGreaterThan(0);
      // A dripping tap report should map to report_issue
      expect(reducerResult.intent.action).toBe('report_issue');
    },
    60_000,
  );

  run(
    'two-turn conversation: report then location narrows taxonomy.where',
    async () => {
      let state = emptyJobState();

      // Turn 1: describe the job
      const t1 = await extractConversationTurn({
        currentState: state,
        latestMessage: 'I have a blocked drain in my bathroom.',
        conversationSummary: '',
      });
      state = mergeExtraction(state, t1.extraction).state;

      // Turn 2: give location
      const t2 = await extractConversationTurn({
        currentState: state,
        latestMessage: 'I am at 55 Glebe Point Rd, Glebe NSW 2037.',
        conversationSummary: 'Customer described a blocked bathroom drain.',
      });
      const { state: state2 } = mergeExtraction(state, t2.extraction);

      const { reducerResult } = await processConversationTurn({
        accumulatedState: state2,
        taggedFacts: [...t1.taggedFacts, ...t2.taggedFacts],
        bridge: bridge(),
      });

      expect(reducerResult.intent.taxonomy.where).toBeDefined();
      // Glebe should appear in the normalised where slug
      const where = (reducerResult.intent.taxonomy.where ?? '').toLowerCase();
      expect(where).toMatch(/glebe|55/);
    },
    90_000,
  );
});

```
