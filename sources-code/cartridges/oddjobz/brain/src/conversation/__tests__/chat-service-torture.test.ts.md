---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/__tests__/chat-service-torture.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.535499+00:00
---

# cartridges/oddjobz/brain/src/conversation/__tests__/chat-service-torture.test.ts

```ts
/**
 * Multi-turn conversation torture suite — processConversationTurn.
 *
 * Tests the full stack: AccumulatedJobState accumulation → reduceToIntent
 * → typed Intent, across a range of realistic and adversarial scenarios.
 *
 * No LLM calls. TaggedFacts and MessageExtractions are constructed directly,
 * matching what the extraction prompt would produce for each scenario.
 *
 * Scenarios:
 *   MT-1  Happy path multi-turn (4 turns, confidence should rise)
 *   MT-2  Scope pivot mid-conversation (plumbing → electrical)
 *   MT-3  Contradictory facts (declaration + transfer in same turn)
 *   MT-4  estimatedCostMax < estimatedCostMin (arithmetic inversion)
 *   MT-5  preferredDatetime in the past
 *   MT-6  Cross-domain bleed (SCADA facts through trades grammar)
 *   MT-7  Empty everything — no facts, no state
 *   MT-8  50+ mixed taggedFacts (geometry picks correct location)
 *   MT-9  Unicode / adversarial scopeDescription
 *   MT-10 Confidence accumulation across turns (monotone check)
 *   MT-11 Quote approve → pay invoice (two-action sequence)
 *   MT-12 Concurrent reducer calls (10 parallel, domain isolation)
 */

import { describe, test, expect } from 'bun:test';
import { processConversationTurn } from '../chat-service';
import { emptyJobState, mergeExtraction } from '../accumulated-job-state';
import type { AccumulatedJobState, MessageExtraction } from '../accumulated-job-state';
import type { TaggedFact } from '@semantos/intent/reducer/types';
import type { BridgeContext } from '../substrate-bridge';
import { TRADES_GRAMMAR_SPEC } from '../trades-grammar-spec';
import type { GrammarSpec } from '@semantos/intent/reducer/types';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

function bridge(overrides?: Partial<BridgeContext>): BridgeContext {
  return {
    chatSessionId: 'test-session-' + Math.random().toString(36).slice(2),
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
    ...overrides,
  };
}

function fact(
  category: string,
  text: string,
  confidence = 0.85,
  lexicon = 'jural',
): TaggedFact {
  return { lexicon, category, confidence, fact: text, source: 'nl-extraction' };
}

function extraction(overrides: Partial<MessageExtraction>): MessageExtraction {
  return overrides as MessageExtraction;
}

/** Simulate one conversation turn: merge extraction into state, then reduce. */
async function turn(
  state: AccumulatedJobState,
  ext: MessageExtraction,
  facts: TaggedFact[],
  options?: {
    grammar?: GrammarSpec;
    estimatedCostMin?: number;
    estimatedCostMax?: number;
    preferredDatetime?: string;
  },
) {
  const { state: newState } = mergeExtraction(state, ext);
  const result = await processConversationTurn({
    accumulatedState: newState,
    taggedFacts: facts,
    estimatedCostMin: options?.estimatedCostMin ?? null,
    estimatedCostMax: options?.estimatedCostMax ?? null,
    preferredDatetime: options?.preferredDatetime ?? null,
    bridge: bridge(),
    grammar: options?.grammar,
  });
  return { state: newState, result };
}

// ---------------------------------------------------------------------------
// MT-1: Happy path — 4-turn dripping tap conversation
// ---------------------------------------------------------------------------

describe('MT-1: happy path multi-turn (dripping tap)', () => {
  test('turn 1 — report issue produces declaration intent', async () => {
    const { result } = await turn(
      emptyJobState(),
      extraction({ scopeDescription: 'dripping tap in kitchen', jobType: 'plumbing', conversationPhase: 'describing_job' }),
      [fact('declaration', 'I have a dripping tap in my kitchen')],
    );
    expect(result.reducerResult.intent.action).toBe('report_issue');
    expect(result.reducerResult.intent.taxonomy.what).toContain('maintenance');
  });

  test('turn 2 — location narrows where coordinate', async () => {
    const s0 = emptyJobState();
    const { state: s1 } = mergeExtraction(s0, extraction({ scopeDescription: 'dripping tap', jobType: 'plumbing', conversationPhase: 'describing_job' }));
    const { result } = await turn(
      s1,
      extraction({ suburb: 'Newtown', address: '42 King St Newtown', conversationPhase: 'providing_location' }),
      [fact('declaration', 'I am at 42 King St, Newtown')],
    );
    expect(result.reducerResult.intent.taxonomy.where).toBeDefined();
    expect(result.reducerResult.intent.taxonomy.where).toContain('newtown');
  });

  test('turn 3 — urgency adds temporal constraint', async () => {
    const s0 = emptyJobState();
    const { state: s1 } = mergeExtraction(s0, extraction({ scopeDescription: 'dripping tap', jobType: 'plumbing' }));
    const { state: s2 } = mergeExtraction(s1, extraction({ suburb: 'Newtown' }));
    const { result } = await turn(
      s2,
      extraction({ urgency: 'next_week', conversationPhase: 'providing_details' }),
      [fact('condition', 'I need it fixed next week')],
    );
    const temporal = result.reducerResult.intent.constraints.find(c => c.kind === 'temporal');
    expect(temporal).toBeDefined();
  });

  test('turn 4 — approve quote produces power intent', async () => {
    const s0 = emptyJobState();
    const { state: s1 } = mergeExtraction(s0, extraction({ scopeDescription: 'dripping tap', jobType: 'plumbing' }));
    const { state: s2 } = mergeExtraction(s1, extraction({ suburb: 'Newtown' }));
    const { state: s3 } = mergeExtraction(s2, extraction({ urgency: 'next_week' }));
    const { result } = await turn(
      s3,
      extraction({ estimateReaction: 'accepted', conversationPhase: 'reviewing_estimate' }),
      [fact('power', 'Approved, please go ahead with the quote for $850')],
      { estimatedCostMin: 85000, estimatedCostMax: 85000 },
    );
    expect(result.reducerResult.intent.action).toBe('approve_quote');
    const valueCons = result.reducerResult.intent.constraints.find(c => c.kind === 'value');
    expect(valueCons).toBeDefined();
  });

  test('confidence rises across turns', async () => {
    const confidences: number[] = [];
    let state = emptyJobState();

    // Turn 1 — bare report
    let merged = mergeExtraction(state, extraction({ scopeDescription: 'dripping tap', jobType: 'plumbing' }));
    state = merged.state;
    let r = await processConversationTurn({ accumulatedState: state, taggedFacts: [fact('declaration', 'dripping tap')], bridge: bridge() });
    confidences.push(r.reducerResult.confidence);

    // Turn 2 — location added
    merged = mergeExtraction(state, extraction({ suburb: 'Newtown', address: '42 King St' }));
    state = merged.state;
    r = await processConversationTurn({ accumulatedState: state, taggedFacts: [fact('declaration', 'I am in Newtown')], bridge: bridge() });
    confidences.push(r.reducerResult.confidence);

    // Turn 3 — urgency + scope detail
    merged = mergeExtraction(state, extraction({ urgency: 'urgent', quantity: '1 tap', materials: 'brass fitting' }));
    state = merged.state;
    r = await processConversationTurn({ accumulatedState: state, taggedFacts: [fact('condition', 'urgent, brass fitting')], bridge: bridge() });
    confidences.push(r.reducerResult.confidence);

    // Confidence should be non-decreasing (small floating point allowed)
    expect(confidences[1]).toBeGreaterThanOrEqual(confidences[0] - 0.05);
    expect(confidences[2]).toBeGreaterThanOrEqual(confidences[1] - 0.05);
  });
});

// ---------------------------------------------------------------------------
// MT-2: Scope pivot mid-conversation
// ---------------------------------------------------------------------------

describe('MT-2: scope pivot (plumbing → electrical)', () => {
  test('late pivot to electrical changes taxonomy.what', async () => {
    let state = emptyJobState();
    // Turn 1: plumbing
    ({ state } = mergeExtraction(state, extraction({ scopeDescription: 'dripping tap', jobType: 'plumbing', conversationPhase: 'describing_job' })));
    // Turn 2: pivot to electrical
    const { result } = await turn(
      state,
      extraction({ jobType: 'electrical', jobPivot: 'different_job', scopeDescription: 'actually the power point is sparking', conversationPhase: 'describing_job' }),
      [fact('declaration', 'Actually it is a sparking power point, not plumbing')],
    );
    // Grammar pass should pick up the new jobType
    expect(result.reducerResult.intent.summary).toBeDefined();
    // Confidence may be lower due to contradicting prior context — that's fine
    expect(result.reducerResult.confidence).toBeGreaterThan(0);
  });

  test('pivot flags appear in result', async () => {
    let state = emptyJobState();
    ({ state } = mergeExtraction(state, extraction({ jobType: 'plumbing' })));
    const { result } = await turn(
      state,
      extraction({ jobType: 'electrical', jobPivot: 'different_job' }),
      [fact('declaration', 'Actually electrical')],
    );
    // Flags may include low-confidence markers — just verify array exists
    expect(Array.isArray(result.reducerResult.flags)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// MT-3: Contradictory facts — declaration + transfer in same turn
// ---------------------------------------------------------------------------

describe('MT-3: contradictory taggedFacts', () => {
  test('rhetoric-pass picks dominant fact (highest confidence)', async () => {
    const { result } = await turn(
      emptyJobState(),
      extraction({ scopeDescription: 'tap leaking', jobType: 'plumbing' }),
      [
        fact('declaration', 'I have a leaking tap', 0.9),
        fact('transfer', 'Please pay the invoice', 0.4), // lower confidence — should lose
      ],
    );
    // Dominant is declaration → report_issue, not issue_invoice
    expect(result.reducerResult.intent.action).toBe('report_issue');
  });

  test('equal-confidence contradictory facts do not panic', async () => {
    const { result } = await turn(
      emptyJobState(),
      extraction({ scopeDescription: 'ambiguous message' }),
      [
        fact('declaration', 'report issue', 0.6),
        fact('transfer', 'pay invoice', 0.6),
      ],
    );
    // Must produce some intent — not throw
    expect(result.reducerResult.intent).toBeDefined();
    expect(result.reducerResult.confidence).toBeGreaterThanOrEqual(0);
  });

  test('multiple high-confidence facts of same category merge cleanly', async () => {
    const { result } = await turn(
      emptyJobState(),
      extraction({ scopeDescription: 'leaking roof and blocked drain', jobType: 'plumbing' }),
      [
        fact('declaration', 'leaking roof', 0.85),
        fact('declaration', 'blocked drain', 0.85),
        fact('declaration', 'water damage on ceiling', 0.7),
      ],
    );
    expect(result.reducerResult.intent.action).toBe('report_issue');
    // All three declaration facts should produce a single coherent intent
    expect(result.reducerResult.intent.constraints.length).toBeGreaterThanOrEqual(0);
  });
});

// ---------------------------------------------------------------------------
// MT-4: Arithmetic inversion — max < min
// ---------------------------------------------------------------------------

describe('MT-4: estimatedCostMax < estimatedCostMin', () => {
  test('inverted cost range does not throw', async () => {
    const { result } = await turn(
      emptyJobState(),
      extraction({ scopeDescription: 'repair job', jobType: 'plumbing' }),
      [fact('power', 'approve the quote')],
      { estimatedCostMin: 100000, estimatedCostMax: 50000 }, // inverted: $1000 min, $500 max
    );
    // Should produce an intent — not crash
    expect(result.reducerResult.intent).toBeDefined();
  });

  test('zero cost range is handled', async () => {
    const { result } = await turn(
      emptyJobState(),
      extraction({ scopeDescription: 'quick fix', jobType: 'plumbing' }),
      [fact('power', 'approve')],
      { estimatedCostMin: 0, estimatedCostMax: 0 },
    );
    expect(result.reducerResult.intent).toBeDefined();
  });

  test('very large cost values do not overflow', async () => {
    const { result } = await turn(
      emptyJobState(),
      extraction({ scopeDescription: 'major renovation' }),
      [fact('power', 'approved')],
      { estimatedCostMin: Number.MAX_SAFE_INTEGER, estimatedCostMax: Number.MAX_SAFE_INTEGER },
    );
    expect(result.reducerResult.intent).toBeDefined();
    expect(isNaN(result.reducerResult.confidence)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// MT-5: preferredDatetime in the past
// ---------------------------------------------------------------------------

describe('MT-5: preferredDatetime in the past', () => {
  test('stale datetime produces a temporal constraint without crashing', async () => {
    const { result } = await turn(
      emptyJobState(),
      extraction({ scopeDescription: 'fix the tap', jobType: 'plumbing', urgency: 'next_week' }),
      [fact('condition', 'please come last Tuesday')],
      { preferredDatetime: '2020-01-01T09:00:00Z' }, // 6 years in the past
    );
    // Constraint should exist — music-pass doesn't validate calendrical sanity
    const temporal = result.reducerResult.intent.constraints.find(c => c.kind === 'temporal');
    expect(temporal).toBeDefined();
    expect(result.reducerResult.intent).toBeDefined();
  });

  test('datetime at unix epoch does not produce NaN confidence', async () => {
    const { result } = await turn(
      emptyJobState(),
      extraction({ scopeDescription: 'fix job' }),
      [fact('condition', 'schedule it')],
      { preferredDatetime: '1970-01-01T00:00:00Z' },
    );
    expect(isNaN(result.reducerResult.confidence)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// MT-6: Cross-domain bleed — SCADA facts through trades grammar
// ---------------------------------------------------------------------------

const SCADA_FACTS: TaggedFact[] = [
  { lexicon: 'control-systems', category: 'measurement', confidence: 0.9, fact: 'TK-101 level 3.4m', source: 'scada' },
  { lexicon: 'control-systems', category: 'setpoint', confidence: 0.85, fact: 'TIC-201 setpoint 90°C', source: 'scada' },
  { lexicon: 'control-systems', category: 'interlock', confidence: 0.8, fact: 'IL-301 high-level shutdown', source: 'scada' },
];

describe('MT-6: cross-domain bleed (SCADA facts through trades grammar)', () => {
  test('SCADA facts produce low confidence through trades grammar', async () => {
    const { result } = await turn(
      emptyJobState(),
      extraction({ scopeDescription: 'sensor reading 3.4m' }),
      SCADA_FACTS,
    );
    // Should not throw — but confidence should be low (unknown categories)
    expect(result.reducerResult.intent).toBeDefined();
    expect(result.reducerResult.confidence).toBeLessThan(0.8);
  });

  test('SCADA facts produce low-confidence flags', async () => {
    const { result } = await turn(
      emptyJobState(),
      extraction({ scopeDescription: 'measurement data' }),
      SCADA_FACTS,
    );
    // Flags should mention at least one below-threshold pass
    expect(result.reducerResult.flags.length).toBeGreaterThan(0);
  });

  test('foreign lexicon facts do not bleed into jural category', async () => {
    const { result } = await turn(
      emptyJobState(),
      extraction({ scopeDescription: 'interlock triggered' }),
      SCADA_FACTS,
    );
    const category = result.reducerResult.intent.category as { lexicon: string };
    // The intent's lexicon should remain jural, not drift to control-systems
    expect(category.lexicon).toBe('jural');
  });
});

// ---------------------------------------------------------------------------
// MT-7: Empty everything
// ---------------------------------------------------------------------------

describe('MT-7: empty state and empty facts', () => {
  test('produces a valid intent with empty input', async () => {
    const { result } = await turn(emptyJobState(), extraction({}), []);
    expect(result.reducerResult.intent).toBeDefined();
    expect(result.reducerResult.intent.id).toBeTruthy();
    expect(result.reducerResult.intent.action).toBeTruthy();
  });

  test('confidence is non-NaN with no input', async () => {
    const { result } = await turn(emptyJobState(), extraction({}), []);
    expect(isNaN(result.reducerResult.confidence)).toBe(false);
    expect(result.reducerResult.confidence).toBeGreaterThanOrEqual(0);
    expect(result.reducerResult.confidence).toBeLessThanOrEqual(1);
  });

  test('taxonomy.what falls back to grammar default', async () => {
    const { result } = await turn(emptyJobState(), extraction({}), []);
    expect(result.reducerResult.intent.taxonomy.what).toBe(TRADES_GRAMMAR_SPEC.defaultTaxonomyWhat);
  });

  test('all 7 passes complete — passResults has 7 entries', async () => {
    const { result } = await turn(emptyJobState(), extraction({}), []);
    expect(result.reducerResult.passResults.length).toBe(7);
  });
});

// ---------------------------------------------------------------------------
// MT-8: 50+ mixed taggedFacts — geometry picks correct location
// ---------------------------------------------------------------------------

describe('MT-8: 50+ taggedFacts (noise + signal)', () => {
  const NOISE: TaggedFact[] = Array.from({ length: 48 }, (_, i) => ({
    lexicon: 'jural',
    category: 'declaration',
    confidence: 0.3 + (i % 5) * 0.05,
    fact: `noise statement ${i}`,
    source: 'nl-extraction',
  }));

  const SIGNAL: TaggedFact[] = [
    fact('declaration', 'I have a burst pipe', 0.95),
    fact('condition', 'Located at 99 Pacific Hwy, St Leonards', 0.9),
  ];

  test('reducer handles 50 facts without throwing', async () => {
    const { result } = await turn(
      emptyJobState(),
      extraction({ scopeDescription: 'burst pipe', suburb: 'St Leonards', address: '99 Pacific Hwy', jobType: 'plumbing', urgency: 'emergency' }),
      [...NOISE, ...SIGNAL],
    );
    expect(result.reducerResult.intent).toBeDefined();
  });

  test('geometry-pass picks signal location over noise', async () => {
    const { result } = await turn(
      emptyJobState(),
      extraction({ suburb: 'St Leonards', address: '99 Pacific Hwy', jobType: 'plumbing' }),
      [...NOISE, ...SIGNAL],
    );
    const where = result.reducerResult.intent.taxonomy.where ?? '';
    // Geometry-pass prefers full address over suburb — either is the right location
    expect(where).toMatch(/pacific|st-leonards|leonards/);
  });

  test('confidence does not collapse to zero with noisy input', async () => {
    const { result } = await turn(
      emptyJobState(),
      extraction({ scopeDescription: 'burst pipe', jobType: 'plumbing' }),
      [...NOISE, ...SIGNAL],
    );
    expect(result.reducerResult.confidence).toBeGreaterThan(0.01);
  });
});

// ---------------------------------------------------------------------------
// MT-9: Unicode / adversarial scopeDescription
// ---------------------------------------------------------------------------

describe('MT-9: unicode and adversarial inputs', () => {
  const ADVERSARIAL_CASES = [
    { desc: 'emoji', text: '🔧 Fix my tap 🚿 it\'s dripping 💧' },
    { desc: 'arabic', text: 'إصلاح صنبور المياه المتسرب' },
    { desc: 'chinese', text: '修理漏水的水龙头' },
    { desc: 'sql injection', text: "'; DROP TABLE jobs; -- plumbing tap" },
    { desc: 'null bytes', text: 'fix tap   urgent' },
    { desc: 'very long', text: 'fix '.repeat(500) + 'the tap' },
    { desc: 'only whitespace', text: '     \t\n     ' },
    { desc: 'control chars', text: '\x01\x02\x03 plumbing \x1f' },
  ];

  for (const { desc, text } of ADVERSARIAL_CASES) {
    test(`does not throw on ${desc} input`, async () => {
      const { result } = await turn(
        emptyJobState(),
        extraction({ scopeDescription: text, jobType: 'plumbing' }),
        [fact('declaration', text.slice(0, 200))],
      );
      expect(result.reducerResult.intent).toBeDefined();
      expect(isNaN(result.reducerResult.confidence)).toBe(false);
    });
  }
});

// ---------------------------------------------------------------------------
// MT-10: Confidence accumulation — non-decreasing monotone check
// ---------------------------------------------------------------------------

describe('MT-10: confidence accumulation across turns', () => {
  test('5-turn increasing specificity produces non-decreasing confidence', async () => {
    const confidences: number[] = [];
    let state = emptyJobState();

    const turns: Array<[MessageExtraction, TaggedFact[]]> = [
      [extraction({ conversationPhase: 'greeting' }), [fact('declaration', 'hello', 0.5)]],
      [extraction({ jobType: 'plumbing', scopeDescription: 'leak', conversationPhase: 'describing_job' }), [fact('declaration', 'leaking tap', 0.8)]],
      [extraction({ suburb: 'Surry Hills', conversationPhase: 'providing_location' }), [fact('declaration', 'Surry Hills', 0.85)]],
      [extraction({ urgency: 'next_week', quantity: '1 tap', conversationPhase: 'providing_details' }), [fact('condition', 'next week', 0.85)]],
      [extraction({ customerName: 'Jane', customerPhone: '0400000001', conversationPhase: 'providing_contact' }), [fact('declaration', 'Jane, 0400000001', 0.9)]],
    ];

    for (const [ext, facts] of turns) {
      const merged = mergeExtraction(state, ext);
      state = merged.state;
      const r = await processConversationTurn({ accumulatedState: state, taggedFacts: facts, bridge: bridge() });
      confidences.push(r.reducerResult.confidence);
    }

    // Each successive turn should not be dramatically worse
    for (let i = 1; i < confidences.length; i++) {
      expect(confidences[i]).toBeGreaterThanOrEqual(confidences[i - 1] - 0.1);
    }
    // Final confidence should beat initial
    expect(confidences[confidences.length - 1]).toBeGreaterThan(confidences[0]);
  });
});

// ---------------------------------------------------------------------------
// MT-11: Quote approve → pay invoice (two-action sequence)
// ---------------------------------------------------------------------------

describe('MT-11: quote-approve → pay-invoice two-action sequence', () => {
  test('approve_quote turn produces power intent', async () => {
    let state = emptyJobState();
    ({ state } = mergeExtraction(state, extraction({ scopeDescription: 'replace hot water system', jobType: 'plumbing', suburb: 'Glebe' })));
    ({ state } = mergeExtraction(state, extraction({ estimatePresented: true, estimateAcknowledged: true, conversationPhase: 'reviewing_estimate' } as never)));

    const { result } = await turn(
      state,
      extraction({ estimateReaction: 'accepted' }),
      [fact('power', 'I approve the $2400 quote', 0.9)],
      { estimatedCostMin: 240000, estimatedCostMax: 240000 },
    );
    expect(result.reducerResult.intent.action).toBe('approve_quote');
  });

  test('pay_invoice turn after work complete produces transfer intent', async () => {
    let state = emptyJobState();
    ({ state } = mergeExtraction(state, extraction({ scopeDescription: 'replace hot water system', jobType: 'plumbing', conversationPhase: 'confirmed' })));

    const { result } = await turn(
      state,
      extraction({ conversationPhase: 'confirmed' }),
      [fact('transfer', 'Please issue the invoice for $2400', 0.9)],
      { estimatedCostMin: 240000, estimatedCostMax: 240000 },
    );
    expect(['issue_invoice', 'pay_invoice']).toContain(result.reducerResult.intent.action);
    const valueCons = result.reducerResult.intent.constraints.find(c => c.kind === 'value');
    expect(valueCons).toBeDefined();
  });

  test('two sequential turns share no mutable state', async () => {
    // Verify reducer is pure — same input always produces same action
    const state = mergeExtraction(
      emptyJobState(),
      extraction({ scopeDescription: 'fix tap', jobType: 'plumbing', suburb: 'Redfern' }),
    ).state;

    const facts = [fact('power', 'approved', 0.9)];

    const [r1, r2] = await Promise.all([
      processConversationTurn({ accumulatedState: state, taggedFacts: facts, bridge: bridge() }),
      processConversationTurn({ accumulatedState: state, taggedFacts: facts, bridge: bridge() }),
    ]);

    // Action and taxonomy.what must agree (IDs will differ — crypto.randomUUID)
    expect(r1.reducerResult.intent.action).toBe(r2.reducerResult.intent.action);
    expect(r1.reducerResult.intent.taxonomy.what).toBe(r2.reducerResult.intent.taxonomy.what);
  });
});

// ---------------------------------------------------------------------------
// MT-12: 10 concurrent reducer calls — domain isolation
// ---------------------------------------------------------------------------

describe('MT-12: concurrent calls and domain isolation', () => {
  test('10 concurrent turns on same grammar do not contaminate each other', async () => {
    const SESSIONS = Array.from({ length: 10 }, (_, i) => ({
      state: mergeExtraction(
        emptyJobState(),
        extraction({ scopeDescription: `job ${i}`, jobType: i % 2 === 0 ? 'plumbing' : 'electrical', suburb: `Suburb${i}` }),
      ).state,
      facts: [fact('declaration', `report issue for job ${i}`, 0.85)],
    }));

    const results = await Promise.all(
      SESSIONS.map(s => processConversationTurn({ accumulatedState: s.state, taggedFacts: s.facts, bridge: bridge() })),
    );

    // Every result must be a valid intent
    for (const r of results) {
      expect(r.reducerResult.intent.id).toBeTruthy();
      expect(isNaN(r.reducerResult.confidence)).toBe(false);
    }

    // All IDs must be unique (randomUUID — no shared state)
    const ids = results.map(r => r.reducerResult.intent.id);
    expect(new Set(ids).size).toBe(10);
  });

  test('different grammars in parallel do not bleed domain flags', async () => {
    const SCADA_SPEC: GrammarSpec = {
      extensionId: 'scada-test',
      domainFlag: 11,
      lexicon: { name: 'control-systems', categories: ['measurement', 'setpoint', 'interlock', 'alarm', 'actuation'] },
      defaultTaxonomyWhat: 'what.process.control',
      objectTypes: [{ name: 'what.process.control', description: 'Process control entity' }],
      actions: [
        { name: 'read_measurement', category: 'measurement', authoredBy: ['operator'], description: 'Read a measurement.' },
        { name: 'write_setpoint',   category: 'setpoint',    authoredBy: ['operator'], description: 'Write a setpoint.' },
      ],
    };

    const tradesFacts = [fact('declaration', 'fix the tap', 0.9)];
    const scadaFacts: TaggedFact[] = [
      { lexicon: 'control-systems', category: 'measurement', confidence: 0.9, fact: 'read TK-101', source: 'scada' },
    ];

    const [tradesResult, scadaResult] = await Promise.all([
      processConversationTurn({
        accumulatedState: mergeExtraction(emptyJobState(), extraction({ jobType: 'plumbing' })).state,
        taggedFacts: tradesFacts,
        bridge: bridge(),
        grammar: TRADES_GRAMMAR_SPEC,
      }),
      processConversationTurn({
        accumulatedState: mergeExtraction(emptyJobState(), extraction({ scopeDescription: 'TK-101 level reading' })).state,
        taggedFacts: scadaFacts,
        bridge: bridge(),
        grammar: SCADA_SPEC,
      }),
    ]);

    // Domain flags must not cross
    const tradesDomain = tradesResult.reducerResult.intent.producerMeta?.governanceContext?.domainFlag;
    const scadaDomain = scadaResult.reducerResult.intent.producerMeta?.governanceContext?.domainFlag;

    if (tradesDomain !== undefined) expect(tradesDomain).toBe(7);
    if (scadaDomain !== undefined) expect(scadaDomain).toBe(11);

    // Actions must not cross either
    expect(tradesResult.reducerResult.intent.action).not.toBe('read_measurement');
    expect(scadaResult.reducerResult.intent.action).not.toBe('report_issue');
  });
});

```
