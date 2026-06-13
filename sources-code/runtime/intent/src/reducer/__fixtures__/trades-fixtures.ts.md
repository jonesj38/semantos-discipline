---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/reducer/__fixtures__/trades-fixtures.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.359684+00:00
---

# runtime/intent/src/reducer/__fixtures__/trades-fixtures.ts

```ts
/**
 * Golden fixtures for the trades vertical intent reducer.
 *
 * Each fixture is { input: ReducerInputState, grammar: GrammarSpec, expected: Partial<Intent> }.
 * The test suite (I-11) asserts that reduceToIntent produces an intent that
 * contains all expected fields. These are the RED commits — they fail until
 * passes I-2..I-9 are implemented.
 *
 * Fixture naming convention: T-{n}-{scenario}
 */

import type { ReducerInputState, GrammarSpec } from '../types';
import type { Intent } from '../../types';

// ---------------------------------------------------------------------------
// Grammar stub (structural match for TRADES_GRAMMAR from packages/extraction)
// ---------------------------------------------------------------------------

export const TRADES_GRAMMAR_STUB: GrammarSpec = {
  extensionId: 'odd-job-todd',
  domainFlag: 7,
  lexicon: {
    name: 'jural',
    categories: ['declaration', 'obligation', 'power', 'condition', 'transfer'],
  },
  defaultTaxonomyWhat: 'maintenance.job',
  objectTypes: [
    { name: 'maintenance.job', description: 'A property maintenance work order.' },
    { name: 'maintenance.quote', description: 'A priced estimate for a job.' },
    { name: 'maintenance.visit', description: 'A scheduled site visit.' },
    { name: 'maintenance.invoice', description: 'An invoice for completed work.' },
  ],
  actions: [
    { name: 'report_issue', category: 'declaration', authoredBy: ['tenant'], description: 'Tenant reports a maintenance issue.' },
    { name: 'request_quote', category: 'declaration', authoredBy: ['pm', 'rea'], description: 'Solicit a quote.' },
    { name: 'submit_quote', category: 'declaration', authoredBy: ['tradesperson'], description: 'Tradesperson submits a quote.' },
    { name: 'approve_quote', category: 'power', authoredBy: ['landlord', 'rea'], description: 'Authorise a quote.' },
    { name: 'schedule_visit', category: 'condition', authoredBy: ['pm', 'tradesperson'], description: 'Schedule a site visit.' },
    { name: 'mark_work_complete', category: 'declaration', authoredBy: ['tradesperson'], description: 'Mark job complete.' },
    { name: 'issue_invoice', category: 'transfer', authoredBy: ['tradesperson'], description: 'Issue an invoice.' },
    { name: 'pay_invoice', category: 'transfer', authoredBy: ['pm', 'landlord'], description: 'Pay the invoice.' },
  ],
  trustClass: 'interpretive',
  proofRequirement: 'attestation',
};

// ---------------------------------------------------------------------------
// T-1: Tenant reports a dripping tap (clear, single-turn, high confidence)
// ---------------------------------------------------------------------------

export const T1_REPORT_DRIPPING_TAP: {
  input: ReducerInputState;
  grammar: GrammarSpec;
  expected: Partial<Intent>;
} = {
  input: {
    conversationSummary: 'Tenant reports a dripping tap in the kitchen at the Newtown property.',
    taggedFacts: [
      { lexicon: 'jural', category: 'declaration', confidence: 0.92, fact: 'dripping tap in kitchen', source: 'turn-1' },
      { lexicon: 'jural', category: 'obligation', confidence: 0.71, fact: 'repair needed', source: 'turn-1' },
    ],
    suburb: 'Newtown',
    jobType: 'plumbing',
    scopeDescription: 'dripping tap in kitchen needs repair',
    urgency: 'next_week',
    location: '42 King St, Newtown',
  },
  grammar: TRADES_GRAMMAR_STUB,
  expected: {
    action: 'report_issue',
    summary: expect.stringContaining('dripping tap'),
    taxonomy: {
      what: 'maintenance.job',
      how: expect.stringContaining('how.'),
      why: expect.stringContaining('why.'),
    },
    category: {
      lexicon: 'jural',
      category: 'declaration',
    },
  } as Partial<Intent>,
};

// ---------------------------------------------------------------------------
// T-2: Landlord approves a quote (power category, authoritative trust tier)
// ---------------------------------------------------------------------------

export const T2_LANDLORD_APPROVES_QUOTE: {
  input: ReducerInputState;
  grammar: GrammarSpec;
  expected: Partial<Intent>;
} = {
  input: {
    conversationSummary: 'Landlord approves the $850 plumbing quote from Joe\'s Plumbing.',
    taggedFacts: [
      { lexicon: 'jural', category: 'power', confidence: 0.95, fact: 'landlord authorises $850 quote', source: 'turn-3' },
      { lexicon: 'jural', category: 'transfer', confidence: 0.60, fact: 'payment obligation arises', source: 'turn-3' },
    ],
    suburb: 'Newtown',
    jobType: 'plumbing',
    estimatedCostMin: 85000,
    estimatedCostMax: 85000,
  },
  grammar: TRADES_GRAMMAR_STUB,
  expected: {
    action: 'approve_quote',
    category: {
      lexicon: 'jural',
      category: 'power',
    },
    constraints: expect.arrayContaining([
      expect.objectContaining({ kind: 'value' }),
    ]),
  } as Partial<Intent>,
};

// ---------------------------------------------------------------------------
// T-3: Tradesperson schedules visit with datetime (music + geometry passes)
// ---------------------------------------------------------------------------

export const T3_SCHEDULE_VISIT: {
  input: ReducerInputState;
  grammar: GrammarSpec;
  expected: Partial<Intent>;
} = {
  input: {
    conversationSummary: 'Plumber Joe scheduled a visit for Wednesday 14 May at 9am.',
    taggedFacts: [
      { lexicon: 'jural', category: 'condition', confidence: 0.88, fact: 'visit scheduled Wednesday 9am', source: 'turn-4' },
    ],
    suburb: 'Newtown',
    preferredDatetime: '2026-05-14T09:00:00+10:00',
    location: '42 King St, Newtown',
  },
  grammar: TRADES_GRAMMAR_STUB,
  expected: {
    action: 'schedule_visit',
    category: {
      lexicon: 'jural',
      category: 'condition',
    },
    constraints: expect.arrayContaining([
      expect.objectContaining({ kind: 'temporal' }),
    ]),
    taxonomy: expect.objectContaining({
      where: expect.stringContaining('Newtown'),
    }),
  } as Partial<Intent>,
};

// ---------------------------------------------------------------------------
// T-4: Invoice issuance (transfer, value constraint for payment)
// ---------------------------------------------------------------------------

export const T4_ISSUE_INVOICE: {
  input: ReducerInputState;
  grammar: GrammarSpec;
  expected: Partial<Intent>;
} = {
  input: {
    conversationSummary: 'Tradesperson issues invoice #INV-042 for $850 for completed plumbing work.',
    taggedFacts: [
      { lexicon: 'jural', category: 'transfer', confidence: 0.93, fact: 'invoice $850 for plumbing work', source: 'turn-7' },
    ],
    jobType: 'plumbing',
    estimatedCostMin: 85000,
    estimatedCostMax: 85000,
  },
  grammar: TRADES_GRAMMAR_STUB,
  expected: {
    action: 'issue_invoice',
    category: {
      lexicon: 'jural',
      category: 'transfer',
    },
    constraints: expect.arrayContaining([
      expect.objectContaining({ kind: 'value' }),
    ]),
  } as Partial<Intent>,
};

// ---------------------------------------------------------------------------
// T-5: Ambiguous — low-confidence taggedFacts (reducer should flag, not reject)
// ---------------------------------------------------------------------------

export const T5_AMBIGUOUS_LOW_CONFIDENCE: {
  input: ReducerInputState;
  grammar: GrammarSpec;
  expectedFlags: string[];
} = {
  input: {
    conversationSummary: 'Something about the property, maybe a leak?',
    taggedFacts: [
      { lexicon: 'jural', category: 'declaration', confidence: 0.28, fact: 'possible issue', source: 'turn-1' },
    ],
    suburb: null,
    jobType: null,
  },
  grammar: TRADES_GRAMMAR_STUB,
  expectedFlags: expect.arrayContaining([
    expect.stringMatching(/low.?confidence|confidence/i),
  ]) as string[],
};

// ---------------------------------------------------------------------------
// Exports
// ---------------------------------------------------------------------------

export const TRADES_FIXTURES = [T1_REPORT_DRIPPING_TAP, T2_LANDLORD_APPROVES_QUOTE, T3_SCHEDULE_VISIT, T4_ISSUE_INVOICE];
export const TRADES_AMBIGUOUS_FIXTURES = [T5_AMBIGUOUS_LOW_CONFIDENCE];

```
