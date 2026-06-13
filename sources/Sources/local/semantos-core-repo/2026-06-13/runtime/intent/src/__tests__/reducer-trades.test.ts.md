---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/__tests__/reducer-trades.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.358356+00:00
---

# runtime/intent/src/__tests__/reducer-trades.test.ts

```ts
/**
 * I-11 — Integration test: trades vertical intent reducer.
 *
 * RED commits — these tests fail until passes I-2..I-9 are implemented.
 * The reduceToIntent function does not exist yet; this file will error
 * on import until the reducer/index.ts is created.
 *
 * See docs/prd/INTENT-REDUCER-GRAMMAR-AUTOMATION-PLAN.md (I-11)
 * and docs/textbook/32-trivium-quadrivium-intent-reducer.md
 */

import { describe, expect, test } from 'bun:test';
import { reduceToIntent } from '../reducer/index';
import {
  TRADES_FIXTURES,
  TRADES_AMBIGUOUS_FIXTURES,
  T1_REPORT_DRIPPING_TAP,
  T2_LANDLORD_APPROVES_QUOTE,
  T3_SCHEDULE_VISIT,
  T4_ISSUE_INVOICE,
  T5_AMBIGUOUS_LOW_CONFIDENCE,
} from '../reducer/__fixtures__/trades-fixtures';

describe('Trades vertical intent reducer', () => {
  describe('T-1: report_issue — tenant reports dripping tap', () => {
    test('produces action: report_issue', async () => {
      const { intent } = await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar);
      expect(intent.action).toBe('report_issue');
    });

    test('produces jural declaration category', async () => {
      const { intent } = await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar);
      expect(intent.category).toMatchObject({ lexicon: 'jural', category: 'declaration' });
    });

    test('taxonomy.what resolves to maintenance.job', async () => {
      const { intent } = await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar);
      expect(intent.taxonomy.what).toBe('maintenance.job');
    });

    test('summary contains job description', async () => {
      const { intent } = await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar);
      expect(intent.summary.toLowerCase()).toContain('dripping tap');
    });

    test('confidence >= 0.6 (grammar threshold)', async () => {
      const result = await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar);
      expect(result.confidence).toBeGreaterThanOrEqual(0.6);
    });

    test('all 7 pass results present', async () => {
      const result = await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar);
      const pasNames = result.passResults.map(p => p.pass);
      expect(pasNames).toContain('grammar');
      expect(pasNames).toContain('logic');
      expect(pasNames).toContain('rhetoric');
      expect(pasNames).toContain('arithmetic');
      expect(pasNames).toContain('geometry');
      expect(pasNames).toContain('music');
      expect(pasNames).toContain('astronomy');
    });
  });

  describe('T-2: approve_quote — landlord exercises power', () => {
    test('produces action: approve_quote', async () => {
      const { intent } = await reduceToIntent(T2_LANDLORD_APPROVES_QUOTE.input, T2_LANDLORD_APPROVES_QUOTE.grammar);
      expect(intent.action).toBe('approve_quote');
    });

    test('produces jural power category', async () => {
      const { intent } = await reduceToIntent(T2_LANDLORD_APPROVES_QUOTE.input, T2_LANDLORD_APPROVES_QUOTE.grammar);
      expect(intent.category).toMatchObject({ lexicon: 'jural', category: 'power' });
    });

    test('value constraint present for $850 quote', async () => {
      const { intent } = await reduceToIntent(T2_LANDLORD_APPROVES_QUOTE.input, T2_LANDLORD_APPROVES_QUOTE.grammar);
      const valueConstraints = intent.constraints.filter(c => c.kind === 'value');
      expect(valueConstraints.length).toBeGreaterThan(0);
    });
  });

  describe('T-3: schedule_visit — temporal + geometry passes', () => {
    test('produces action: schedule_visit', async () => {
      const { intent } = await reduceToIntent(T3_SCHEDULE_VISIT.input, T3_SCHEDULE_VISIT.grammar);
      expect(intent.action).toBe('schedule_visit');
    });

    test('temporal constraint present for 14 May 9am', async () => {
      const { intent } = await reduceToIntent(T3_SCHEDULE_VISIT.input, T3_SCHEDULE_VISIT.grammar);
      const temporalConstraints = intent.constraints.filter(c => c.kind === 'temporal');
      expect(temporalConstraints.length).toBeGreaterThan(0);
    });

    test('taxonomy.where includes newtown (normalised)', async () => {
      const { intent } = await reduceToIntent(T3_SCHEDULE_VISIT.input, T3_SCHEDULE_VISIT.grammar);
      expect(intent.taxonomy.where ?? '').toContain('newtown');
    });
  });

  describe('T-4: issue_invoice — transfer with value', () => {
    test('produces action: issue_invoice', async () => {
      const { intent } = await reduceToIntent(T4_ISSUE_INVOICE.input, T4_ISSUE_INVOICE.grammar);
      expect(intent.action).toBe('issue_invoice');
    });

    test('produces jural transfer category', async () => {
      const { intent } = await reduceToIntent(T4_ISSUE_INVOICE.input, T4_ISSUE_INVOICE.grammar);
      expect(intent.category).toMatchObject({ lexicon: 'jural', category: 'transfer' });
    });

    test('value constraint present for invoice amount', async () => {
      const { intent } = await reduceToIntent(T4_ISSUE_INVOICE.input, T4_ISSUE_INVOICE.grammar);
      const valueConstraints = intent.constraints.filter(c => c.kind === 'value');
      expect(valueConstraints.length).toBeGreaterThan(0);
    });
  });

  describe('T-5: ambiguous low-confidence input', () => {
    test('completes without throwing', async () => {
      await expect(
        reduceToIntent(T5_AMBIGUOUS_LOW_CONFIDENCE.input, T5_AMBIGUOUS_LOW_CONFIDENCE.grammar),
      ).resolves.toBeDefined();
    });

    test('raises confidence flags', async () => {
      const result = await reduceToIntent(T5_AMBIGUOUS_LOW_CONFIDENCE.input, T5_AMBIGUOUS_LOW_CONFIDENCE.grammar);
      expect(result.flags.length).toBeGreaterThan(0);
      const hasConfidenceFlag = result.flags.some(f => /confidence|low/i.test(f));
      expect(hasConfidenceFlag).toBe(true);
    });

    test('composite confidence below grammar threshold', async () => {
      const result = await reduceToIntent(T5_AMBIGUOUS_LOW_CONFIDENCE.input, T5_AMBIGUOUS_LOW_CONFIDENCE.grammar);
      expect(result.confidence).toBeLessThan(0.6);
    });
  });

  describe('Geometry pass — domain flag propagation', () => {
    test('domainFlag 7 propagates into governance context', async () => {
      const result = await reduceToIntent(T1_REPORT_DRIPPING_TAP.input, T1_REPORT_DRIPPING_TAP.grammar);
      const astronomyPass = result.passResults.find(p => p.pass === 'astronomy');
      expect(astronomyPass).toBeDefined();
      // GovernanceContext lives in intent, not directly on passResult — check it via intent
      // The astronomy pass contributes to intent.constraints (domain constraint)
      const domainConstraints = result.intent.constraints.filter(c => c.kind === 'domain');
      expect(domainConstraints.length).toBeGreaterThan(0);
    });
  });
});

```
