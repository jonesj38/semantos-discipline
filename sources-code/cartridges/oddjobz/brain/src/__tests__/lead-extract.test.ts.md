---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/__tests__/lead-extract.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.512580+00:00
---

# cartridges/oddjobz/brain/src/__tests__/lead-extract.test.ts

```ts
/**
 * D-O6b — Deliverable 2 — lead-extract resource tests.
 *
 * Acceptance:
 *  - The system prompt is stable + carries the JSON-output schema.
 *  - The transcript renders Visitor / AI / Operator turns correctly.
 *  - parseExtractionResponse handles well-formed LLM output, malformed
 *    output (markdown fences, prose preamble, broken JSON), and
 *    out-of-range numerics.
 *  - extractLead with a deterministic mock LLM produces the expected
 *    drafted Estimate.
 *  - The confidence floor causes a low-confidence "lead" to be
 *    suppressed.
 */

import { describe, expect, test } from 'bun:test';
import {
  buildLeadExtractionPrompt,
  renderTranscript,
  parseExtractionResponse,
  extractLead,
  type LlmCompleteFn,
} from '../lead-extract.js';
import { buildVisitorMessageCell, buildAiMessageCell } from '../chat-persistence.js';
import type { OddjobzMessage } from '../cell-types/message.js';

const SESSION = 'session-deck-repair-abc-123';
const NOW = '2026-05-01T09:00:00Z';
const DRAFT_EST_ID = '13131313-1313-4131-8131-131313131313';
const PLACEHOLDER_JOB_ID = '00000000-0000-4000-8000-000000000000';

function mockMessages(): OddjobzMessage[] {
  const t0 = {
    chatSessionId: SESSION,
    visitorText: 'Hi, my deck is rotting. Need it repaired urgently. About 12 sqm. Budget around $3000.',
    aiText: 'Sure — what suburb are you in, and what is your name + best phone number?',
    turnIndex: 0,
    nowIso: NOW,
  };
  const t1 = {
    chatSessionId: SESSION,
    visitorText: 'Sam Tradie, 0400-111-222, Coogee. Can you come this week?',
    aiText: 'Yes, Tuesday morning at 10 AM works. I will get back to you with a firm quote.',
    turnIndex: 1,
    nowIso: '2026-05-01T09:01:00Z',
  };
  return [
    buildVisitorMessageCell(t0),
    buildAiMessageCell(t0),
    buildVisitorMessageCell(t1),
    buildAiMessageCell(t1),
  ];
}

function mockLlm(text: string): LlmCompleteFn {
  return async () => ({ text });
}

describe('§O6b — lead-extract — prompt + transcript', () => {
  test('system prompt mentions the JSON output schema', () => {
    const p = buildLeadExtractionPrompt();
    expect(p).toContain('has_lead');
    expect(p).toContain('confidence');
    expect(p).toContain('customer_hint');
    expect(p).toContain('draft');
    expect(p).toContain('scope_summary');
    expect(p).toContain('urgency');
    expect(p).toContain('CENTS');
  });

  test('renderTranscript prefixes turns by sender', () => {
    const msgs = mockMessages();
    const t = renderTranscript(msgs);
    expect(t).toContain('Visitor: Hi, my deck is rotting');
    expect(t).toContain('AI: Sure');
    expect(t).toContain('Visitor: Sam Tradie');
    expect(t).toContain('AI: Yes, Tuesday morning');
  });

  test('renderTranscript handles operator + system senders', () => {
    const operatorMsg: OddjobzMessage = {
      messageId: '00000001-0000-4000-8000-000000000001',
      jobId: '00000003-0000-4000-8000-000000000003',
      senderType: 'operator',
      senderOperatorId: '20202020-2020-4020-8020-202020202020',
      messageType: 'text',
      rawContent: 'Operator typed this',
      createdAt: NOW,
    };
    const systemMsg: OddjobzMessage = {
      messageId: '00000002-0000-4000-8000-000000000002',
      jobId: '00000003-0000-4000-8000-000000000003',
      senderType: 'system',
      messageType: 'system',
      rawContent: 'system event',
      createdAt: NOW,
    };
    const t = renderTranscript([operatorMsg, systemMsg]);
    expect(t).toContain('Operator: Operator typed this');
    expect(t).toContain('System: system event');
  });
});

describe('§O6b — lead-extract — parseExtractionResponse', () => {
  test('parses a well-formed has_lead=true response', () => {
    const raw = JSON.stringify({
      has_lead: true,
      confidence: 0.85,
      customer_hint: 'Sam Tradie / 0400-111-222 / Coogee',
      draft: {
        estimate_type: 'auto_rom',
        effort_band: 'half_day',
        cost_min_cents: 250000,
        cost_max_cents: 350000,
        scope_summary: 'Replace 12 sqm of rotting deck boards',
        urgency: 'high',
        assumption_notes: 'Joists assumed sound',
      },
    });
    const r = parseExtractionResponse(raw);
    expect(r.hasLead).toBe(true);
    expect(r.confidence).toBe(0.85);
    expect(r.customerHint).toContain('Sam Tradie');
    expect(r.draft).not.toBeNull();
    expect(r.draft!.effortBand).toBe('half_day');
    expect(r.draft!.costMin).toBe(250000);
    expect(r.draft!.costMax).toBe(350000);
    expect(r.draft!.urgency).toBe('high');
  });

  test('parses a has_lead=false response', () => {
    const raw = JSON.stringify({
      has_lead: false,
      confidence: 0.1,
      customer_hint: '',
      draft: null,
    });
    const r = parseExtractionResponse(raw);
    expect(r.hasLead).toBe(false);
    expect(r.draft).toBeNull();
  });

  test('strips markdown fences', () => {
    const raw =
      '```json\n' +
      JSON.stringify({
        has_lead: true,
        confidence: 0.6,
        customer_hint: 'Pat',
        draft: {
          estimate_type: 'auto_rom',
          effort_band: 'quick',
          scope_summary: 'tap fix',
          urgency: 'low',
          assumption_notes: '',
        },
      }) +
      '\n```';
    const r = parseExtractionResponse(raw);
    expect(r.hasLead).toBe(true);
    expect(r.draft!.scopeSummary).toBe('tap fix');
  });

  test('falls back to no-lead on broken JSON', () => {
    const r = parseExtractionResponse('this is not json at all');
    expect(r.hasLead).toBe(false);
    expect(r.draft).toBeNull();
  });

  test('rejects out-of-range effort_band', () => {
    const raw = JSON.stringify({
      has_lead: true,
      confidence: 0.7,
      customer_hint: '',
      draft: {
        estimate_type: 'auto_rom',
        effort_band: 'fortnight',
        scope_summary: 's',
        urgency: 'medium',
        assumption_notes: '',
      },
    });
    const r = parseExtractionResponse(raw);
    expect(r.draft!.effortBand).toBeUndefined();
  });

  test('clamps confidence to [0, 1]', () => {
    const r1 = parseExtractionResponse(
      JSON.stringify({ has_lead: false, confidence: 99, customer_hint: '', draft: null }),
    );
    expect(r1.confidence).toBe(1);
    const r2 = parseExtractionResponse(
      JSON.stringify({ has_lead: false, confidence: -5, customer_hint: '', draft: null }),
    );
    expect(r2.confidence).toBe(0);
  });

  test('rejects non-integer / negative cost cents', () => {
    const raw = JSON.stringify({
      has_lead: true,
      confidence: 0.7,
      customer_hint: '',
      draft: {
        estimate_type: 'auto_rom',
        effort_band: 'short',
        cost_min_cents: -100,
        cost_max_cents: 12.5,
        scope_summary: 's',
        urgency: 'medium',
        assumption_notes: '',
      },
    });
    const r = parseExtractionResponse(raw);
    expect(r.draft!.costMin).toBeUndefined();
    expect(r.draft!.costMax).toBeUndefined();
  });
});

describe('§O6b — lead-extract — extractLead', () => {
  test('happy path: visitor describes a deck repair, returns drafted Estimate', async () => {
    const llmText = JSON.stringify({
      has_lead: true,
      confidence: 0.85,
      customer_hint: 'Sam Tradie / 0400-111-222 / Coogee',
      draft: {
        estimate_type: 'auto_rom',
        effort_band: 'half_day',
        cost_min_cents: 250000,
        cost_max_cents: 350000,
        scope_summary: 'Replace 12 sqm of rotting deck boards',
        urgency: 'high',
        assumption_notes: 'Joists assumed sound',
      },
    });
    const r = await extractLead({
      chatSessionId: SESSION,
      messages: mockMessages(),
      nowIso: NOW,
      draftEstimateId: DRAFT_EST_ID,
      placeholderJobId: PLACEHOLDER_JOB_ID,
      llmComplete: mockLlm(llmText),
    });
    expect(r.hasLead).toBe(true);
    expect(r.confidence).toBe(0.85);
    expect(r.customerHint).toContain('Sam Tradie');
    expect(r.draftEstimate).not.toBeNull();
    expect(r.draftEstimate!.estimateId).toBe(DRAFT_EST_ID);
    expect(r.draftEstimate!.jobId).toBe(PLACEHOLDER_JOB_ID);
    expect(r.draftEstimate!.effortBand).toBe('half_day');
    expect(r.draftEstimate!.costMin).toBe(250000);
    expect(r.draftEstimate!.costMax).toBe(350000);
    expect(r.draftEstimate!.materialsNote).toContain('rotting deck boards');
  });

  test('confidence floor suppresses low-confidence "leads"', async () => {
    const llmText = JSON.stringify({
      has_lead: true,
      confidence: 0.3,
      customer_hint: 'maybe',
      draft: {
        estimate_type: 'auto_rom',
        effort_band: 'short',
        scope_summary: 'something vague',
        urgency: 'medium',
        assumption_notes: '',
      },
    });
    const r = await extractLead({
      chatSessionId: SESSION,
      messages: mockMessages(),
      nowIso: NOW,
      draftEstimateId: DRAFT_EST_ID,
      placeholderJobId: PLACEHOLDER_JOB_ID,
      confidenceFloor: 0.5,
      llmComplete: mockLlm(llmText),
    });
    expect(r.hasLead).toBe(false);
    expect(r.draftEstimate).toBeNull();
    expect(r.confidence).toBe(0.3);
  });

  test('no lead detected — returns has_lead=false', async () => {
    const llmText = JSON.stringify({
      has_lead: false,
      confidence: 0.05,
      customer_hint: '',
      draft: null,
    });
    const r = await extractLead({
      chatSessionId: SESSION,
      messages: mockMessages(),
      nowIso: NOW,
      draftEstimateId: DRAFT_EST_ID,
      placeholderJobId: PLACEHOLDER_JOB_ID,
      llmComplete: mockLlm(llmText),
    });
    expect(r.hasLead).toBe(false);
    expect(r.draftEstimate).toBeNull();
  });

  test('passes through a chat-session id and full transcript to the LLM', async () => {
    let capturedSystem = '';
    let capturedPrompt = '';
    const llm: LlmCompleteFn = async (args) => {
      capturedSystem = args.system_prompt;
      capturedPrompt = args.prompt;
      expect(args.scope).toBe('oddjobz-internal');
      return { text: '{"has_lead":false,"confidence":0,"customer_hint":"","draft":null}' };
    };
    await extractLead({
      chatSessionId: SESSION,
      messages: mockMessages(),
      nowIso: NOW,
      draftEstimateId: DRAFT_EST_ID,
      placeholderJobId: PLACEHOLDER_JOB_ID,
      llmComplete: llm,
    });
    expect(capturedSystem).toContain('lead-extraction agent');
    expect(capturedPrompt).toContain(SESSION);
    expect(capturedPrompt).toContain('Visitor: Hi, my deck is rotting');
    expect(capturedPrompt).toContain('AI: Sure');
  });
});

```
