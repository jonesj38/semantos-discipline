---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tests/conversation/state-manager.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.489772+00:00
---

# cartridges/oddjobz/brain/tests/conversation/state-manager.test.ts

```ts
/**
 * D-O7 — conversation state-manager tests.
 *
 * Tests grounded in the operator-tuned thresholds + the six findings
 * from D-O7-OJT-SALVAGE-REPORT.md. Each finding has at least one test
 * that proves the cascade behaves as the salvage requires.
 */

import { describe, expect, test } from 'bun:test';
import {
  evaluateConversationState,
  generateSystemInjection,
  detectNeedsSiteVisit,
  buildSummary,
  THRESHOLDS,
  type ConversationAction,
} from '../../src/conversation/state-manager.js';
import {
  emptyJobState,
  type AccumulatedJobState,
} from '../../src/conversation/accumulated-job-state.js';

const baseState = (
  patch: Partial<AccumulatedJobState> = {},
): AccumulatedJobState => ({
  ...emptyJobState(),
  ...patch,
});

describe('D-O7 — conversation state-manager — early exit branches', () => {
  test('low fit + estimate presented → not_worth_pursuing', () => {
    const state = baseState({
      customerFitScore: 10,
      estimatePresented: true,
    });
    const a = evaluateConversationState(state);
    expect(a.type).toBe('not_worth_pursuing');
  });

  test('estimate rejected → not_worth_pursuing', () => {
    const state = baseState({
      estimatePresented: true,
      estimateAcknowledged: true,
      estimateAckStatus: 'rejected',
    });
    const a = evaluateConversationState(state);
    expect(a.type).toBe('not_worth_pursuing');
    if (a.type === 'not_worth_pursuing') {
      expect(a.reason).toMatch(/rejected/i);
    }
  });

  test('confirmed phase falls through to cascade (summarise_and_close when contact + estimate met)', () => {
    // 'confirmed' no longer short-circuits to continue; it falls through
    // so summarise_and_close can fire once contact + estimate conditions hold.
    const state = baseState({
      conversationPhase: 'confirmed',
      decisionReadiness: 80,
      scopeClarity: 50,
      estimatePresented: true,
      estimateAcknowledged: true,
      estimateAckStatus: 'accepted',
      customerPhone: '0400123456',
      scopeDescription: 'paint front room',
      suburb: 'Noosa',
    });
    expect(evaluateConversationState(state).type).toBe('summarise_and_close');
  });

  test('disengaged phase → continue', () => {
    const state = baseState({ conversationPhase: 'disengaged' });
    expect(evaluateConversationState(state).type).toBe('continue');
  });
});

describe('D-O7 — conversation state-manager — site-visit branch', () => {
  test('hazardous keyword "asbestos" forces site_visit', () => {
    const state = baseState({
      scopeDescription: 'asbestos roof tiles need removal',
      jobType: 'roofing',
    });
    const reason = detectNeedsSiteVisit(state);
    expect(reason).toMatch(/hazardous/i);
  });

  test('hazardous keyword "structural damage" forces site_visit', () => {
    const state = baseState({
      scopeDescription: 'fence has structural damage',
    });
    const reason = detectNeedsSiteVisit(state);
    expect(reason).toMatch(/hazardous|structural/i);
  });

  test('two concerning keywords ("rotten" + "sagging") force site_visit', () => {
    const state = baseState({
      scopeDescription: 'deck has rotten posts and is sagging at the back',
    });
    const reason = detectNeedsSiteVisit(state);
    expect(reason).toMatch(/concerning/i);
  });

  test('one concerning keyword + bad material condition forces site_visit', () => {
    const state = baseState({
      scopeDescription: 'rotten boards on the deck',
      materialCondition: 'rot through the joists, water damage everywhere',
    });
    const reason = detectNeedsSiteVisit(state);
    expect(reason).not.toBeNull();
  });

  test('clean scope, no condition → no site_visit', () => {
    const state = baseState({
      scopeDescription: 'replace some palings, all in good shape',
    });
    expect(detectNeedsSiteVisit(state)).toBeNull();
  });
});

describe('D-O7 — conversation state-manager — present_estimate branches', () => {
  test('emits EstimatorRequest at presentEstimateReadiness threshold', () => {
    const state = baseState({
      jobType: 'fencing',
      scopeDescription: 'replace 6m of paling fence with concreted posts',
      suburb: 'Noosa Heads',
      quantity: '6m',
      materials: 'paling',
      estimateReadiness: THRESHOLDS.presentEstimateReadiness,
      locationClarity: 40, // first-pass present_estimate now gates on suburb && locationClarity >= 40
    });
    const a = evaluateConversationState(state);
    expect(a.type).toBe('present_estimate');
    if (a.type === 'present_estimate') {
      expect(a.request.jobType).toBe('fencing');
      expect(a.request.scopeDescription).toContain('paling');
      expect(a.request.allowWidenedBand).toBe(true);
    }
  });

  test('vague hourly seeker suppresses present_estimate', () => {
    const state = baseState({
      jobType: 'general',
      scopeDescription: 'small fix',
      suburb: 'Noosa Heads',
      estimateReadiness: 80,
      customerToneSignal: 'price_focused',
      clarityScore: 'vague',
    });
    expect(evaluateConversationState(state).type).not.toBe('present_estimate');
  });

  test('forces present_estimate at borderline readiness when scope passes forcePresentEstimateScope', () => {
    const state = baseState({
      jobType: 'painting',
      scopeDescription:
        'paint the front room, single coat over existing white walls, no prep',
      suburb: 'Noosaville',
      estimateReadiness: 40, // below presentEstimateReadiness
      scopeClarity: THRESHOLDS.forcePresentEstimateScope, // hits the borderline branch
    });
    const a = evaluateConversationState(state);
    expect(a.type).toBe('present_estimate');
    if (a.type === 'present_estimate') {
      expect(a.request.allowWidenedBand).toBe(false);
    }
  });
});

describe('D-O7 — conversation state-manager — close branches', () => {
  test('high decision-readiness + acknowledged + contact → summarise_and_close', () => {
    const state = baseState({
      decisionReadiness: 80,
      scopeClarity: 50, // above scopeUnclearAfterEstimate threshold (25)
      estimatePresented: true,
      estimateAcknowledged: true,
      estimateAckStatus: 'accepted',
      customerName: 'Sam',
      customerPhone: '0400123456',
      scopeDescription: 'paint front room',
      suburb: 'Noosa',
    });
    const a = evaluateConversationState(state);
    expect(a.type).toBe('summarise_and_close');
    if (a.type === 'summarise_and_close') {
      expect(a.summary).toContain('Sam');
      expect(a.summary).toContain('Noosa');
    }
  });

  test('worthiness gate offers free_quote_visit when worthy', () => {
    const state = baseState({
      scopeClarity: 50,
      estimatePresented: true,
      estimateAcknowledged: true,
      estimateAckStatus: 'accepted',
      quoteWorthinessScore: 60,
      customerFitScore: 60,
      scopeDescription: 'fence repair',
      suburb: 'Noosa',
    });
    const a = evaluateConversationState(state);
    expect(a.type).toBe('offer_free_quote_visit');
  });

  test('worthiness gate declines free_quote_visit when below threshold', () => {
    const state = baseState({
      scopeClarity: 50,
      estimatePresented: true,
      estimateAcknowledged: true,
      estimateAckStatus: 'accepted',
      quoteWorthinessScore: 30, // below freeQuoteWorthiness
      customerFitScore: 30,
      scopeDescription: 'tap washer fix',
      suburb: 'Noosa',
    });
    const a = evaluateConversationState(state);
    expect(a.type).toBe('not_worth_pursuing');
  });
});

describe('D-O7 — conversation state-manager — ask_contact + pushback', () => {
  test('estimate acknowledged but unaccepted + no contact → ask_contact', () => {
    const state = baseState({
      scopeClarity: 50,
      estimatePresented: true,
      estimateAcknowledged: true,
      estimateAckStatus: 'unclear',
      scopeDescription: 'paint a room',
      suburb: 'Noosa',
    });
    const a = evaluateConversationState(state);
    expect(a.type).toBe('ask_contact');
  });

  test('estimate pushback → continue (let LLM address concern)', () => {
    const state = baseState({
      scopeClarity: 50,
      estimatePresented: true,
      estimateAcknowledged: true,
      estimateAckStatus: 'pushback',
      scopeDescription: 'paint a room',
      suburb: 'Noosa',
    });
    const a = evaluateConversationState(state);
    expect(a.type).toBe('continue');
  });
});

describe('D-O7 — conversation state-manager — generateSystemInjection', () => {
  test('present_estimate emits the ROM-not-quote framing', () => {
    const action: ConversationAction = {
      type: 'present_estimate',
      request: {
        jobType: 'fencing',
        subcategory: null,
        quantity: '6m',
        scopeDescription: 'paling fence',
        materials: 'paling',
        accessDifficulty: null,
        allowWidenedBand: true,
      },
    };
    const inj = generateSystemInjection(action);
    expect(inj).toMatch(/ROUGH ORDER OF MAGNITUDE/);
    expect(inj).toMatch(/expectation-check/);
  });

  test('ask_contact substitutes operator name into the {OPERATOR} placeholder', () => {
    const inj = generateSystemInjection({ type: 'ask_contact' }, 'Alex');
    expect(inj).toMatch(/Alex can get in touch/);
    expect(inj).not.toMatch(/\{OPERATOR\}/);
  });

  test('continue returns null', () => {
    expect(generateSystemInjection({ type: 'continue' })).toBeNull();
  });

  test('not_worth_pursuing matches OJT operator-approved tone', () => {
    const inj = generateSystemInjection(
      { type: 'not_worth_pursuing', reason: 'r' },
      'Todd',
    );
    expect(inj).toMatch(/Wrap up politely/);
    expect(inj).toMatch(/Do NOT offer a site visit/);
  });

  test('needs_site_visit emits the inspect-first framing', () => {
    const inj = generateSystemInjection(
      { type: 'needs_site_visit', reason: 'r' },
      'Todd',
    );
    expect(inj).toMatch(/site visit before any ballpark/);
    expect(inj).toMatch(/this visit is free/);
  });
});

describe('D-O7 — conversation state-manager — buildSummary', () => {
  test('summary includes job, location, urgency labels, contact', () => {
    const state = baseState({
      scopeDescription: 'fence repair',
      suburb: 'Noosa Heads',
      urgency: 'urgent',
      customerName: 'Sam',
      customerPhone: '0400123456',
      customerEmail: 'sam@example.com',
    });
    const s = buildSummary(state);
    expect(s).toContain('Job: fence repair');
    expect(s).toContain('Location: Noosa Heads');
    expect(s).toContain('Timing: Urgent');
    expect(s).toContain('Name: Sam');
    expect(s).toContain('Phone: 0400123456');
    expect(s).toContain('Email: sam@example.com');
  });

  test('omits unspecified urgency', () => {
    const state = baseState({
      scopeDescription: 'fix',
      suburb: 'Noosa',
      urgency: 'unspecified',
    });
    const s = buildSummary(state);
    expect(s).not.toMatch(/Timing/);
  });
});

```
