---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/__tests__/d-o6b-pipeline.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.511582+00:00
---

# cartridges/oddjobz/brain/src/__tests__/d-o6b-pipeline.test.ts

```ts
/**
 * D-O6b — End-to-end pipeline test (Deliverable 6).
 *
 * Simulates the full flow:
 *
 *   visitor types a message about "deck repair, urgent, three grand budget"
 *     → brain persists 2 oddjobz.message.v1 cells (visitor + ai)
 *     → oddjobz.lead_extract identifies it as a lead
 *     → enqueue lands the draft Estimate on the ratification queue
 *     → operator (REPL) ratifies
 *     → oddjobz.lead.v1 + oddjobz.estimate.v1 + oddjobz.job.v1 (in `lead`
 *       state) all exist as cells
 *     → the §O4 Job FSM `∅ → lead` genesis transition has fired,
 *       cap.oddjobz.write_customer is what was spent
 *
 * Single test that covers the full pipeline. Stub LLM that returns a
 * deterministic well-shaped extraction response. No real network.
 */

import { describe, expect, test } from 'bun:test';
import {
  buildChatTurn,
  reconstructChatThread,
} from '../chat-persistence.js';
import { extractLead } from '../lead-extract.js';
import { RatificationQueue, makeMemoryStorage } from '../ratification-queue.js';
import { capWriteCustomer } from '../capabilities.js';
import { messageCellType } from '../cell-types/message.js';
import { estimateCellType } from '../cell-types/estimate.js';
import { leadCellType } from '../cell-types/lead.js';
import { jobCellType } from '../cell-types/job.js';

const SESSION = 'session-deck-repair-abc-123';
const TURN_NOW = '2026-05-01T09:00:00Z';
const TURN1_NOW = '2026-05-01T09:01:00Z';
const RATIFY_NOW = '2026-05-01T09:30:00Z';
const OP_CERT = '20202020202040208020202020202020';
const DRAFT_EST_ID = '13131313-1313-4131-8131-131313131313';
const PLACEHOLDER_JOB_ID = '00000000-0000-4000-8000-000000000000';

describe('§O6b — end-to-end pipeline', () => {
  test('visitor message → cells → extract → enqueue → ratify → 3 canonical cells', async () => {
    // ── Step 1: visitor turn 0 ───────────────────────────────────────
    const turn0 = buildChatTurn({
      chatSessionId: SESSION,
      visitorText:
        'Hi, my deck is rotting. I need it repaired urgently. About 12 sqm. Budget around three grand.',
      aiText: 'Sure — what suburb are you in, and what is your name + best phone number?',
      turnIndex: 0,
      nowIso: TURN_NOW,
    });
    // The visitor + ai cells are now bytes-on-disk via files.write. We
    // assert they round-trip through the cell-type as part of the canon.
    expect(messageCellType.unpack(turn0.visitorBytes).senderType).toBe(
      'customer',
    );
    expect(messageCellType.unpack(turn0.aiBytes).senderType).toBe('ai');

    // ── Step 2: visitor turn 1 — they give contact details ───────────
    const turn1 = buildChatTurn({
      chatSessionId: SESSION,
      visitorText: 'Sam Tradie, 0400-111-222, Coogee. Tuesday morning works.',
      aiText:
        'Got it — I will pass that to the operator and they will get back to you.',
      turnIndex: 1,
      nowIso: TURN1_NOW,
    });

    // ── Step 3: lead-extract reads ALL session messages ──────────────
    const allMessages = [
      turn0.visitorCell,
      turn0.aiCell,
      turn1.visitorCell,
      turn1.aiCell,
    ];
    const sessionMessages = reconstructChatThread(allMessages, SESSION);
    expect(sessionMessages).toHaveLength(4);

    // Stub LLM — returns a well-shaped lead extraction.
    const stubExtraction = JSON.stringify({
      has_lead: true,
      confidence: 0.88,
      customer_hint: 'Sam Tradie / 0400-111-222 / Coogee — urgent deck repair',
      draft: {
        estimate_type: 'auto_rom',
        effort_band: 'half_day',
        cost_min_cents: 250000,
        cost_max_cents: 350000,
        scope_summary: 'Replace ~12 sqm of rotting deck boards. Joists assumed sound.',
        urgency: 'high',
        assumption_notes: 'Joists assumed sound; existing structure intact',
      },
    });
    const extractResult = await extractLead({
      chatSessionId: SESSION,
      messages: sessionMessages,
      nowIso: TURN1_NOW,
      draftEstimateId: DRAFT_EST_ID,
      placeholderJobId: PLACEHOLDER_JOB_ID,
      llmComplete: async () => ({ text: stubExtraction }),
    });
    expect(extractResult.hasLead).toBe(true);
    expect(extractResult.draftEstimate).not.toBeNull();
    expect(extractResult.confidence).toBe(0.88);
    expect(extractResult.customerHint).toContain('Sam Tradie');

    // ── Step 4: enqueue the draft on the ratification queue ─────────
    const queue = new RatificationQueue(makeMemoryStorage());
    const entry = queue.enqueue({
      provenance: 'from_chat',
      chatSessionId: SESSION,
      customerHint: extractResult.customerHint,
      draftEstimate: extractResult.draftEstimate!,
      nowIso: TURN1_NOW,
      queueIdOverride: '40404040-4040-4040-8040-404040404040',
    });
    expect(queue.listPending()).toHaveLength(1);
    expect(entry.status).toBe('pending');

    // ── Step 5: operator ratifies (REPL `brain chat ratify --queue-id ...`) ─
    const ratifyResult = queue.ratify({
      queueId: entry.queueId,
      operatorCertId: OP_CERT,
      nowIso: RATIFY_NOW,
      writeCustomerCap: { kind: 'structural', domainFlag: capWriteCustomer.domainFlag },
      newJobId: '50505050-5050-4050-8050-505050505050',
      newEstimateId: '51515151-5151-4151-8151-515151515151',
      newLeadId: '52525252-5252-4252-8252-525252525252',
    });
    expect(ratifyResult.ok).toBe(true);
    if (!ratifyResult.ok) throw new Error('ratify failed');

    // ── Step 6: assert all three canonical cells exist + are valid ──
    const { estimate, lead, job, estimateBytes, leadBytes, jobBytes } =
      ratifyResult.value;

    // (a) The signed Estimate carries the freshly-minted Job's id.
    expect(estimate.estimateId).toBe('51515151-5151-4151-8151-515151515151');
    expect(estimate.jobId).toBe('50505050-5050-4050-8050-505050505050');
    expect(estimate.materialsNote).toContain('rotting deck boards');

    // (b) The Lead cell anchors the chat session, the Estimate, and
    //     the Job under the operator's cert.
    expect(lead.leadId).toBe('52525252-5252-4252-8252-525252525252');
    expect(lead.chatSessionId).toBe(SESSION);
    expect(lead.extractedEstimateId).toBe(estimate.estimateId);
    expect(lead.jobId).toBe(job.jobId);
    expect(lead.ratifiedBy).toBe(OP_CERT);
    expect(lead.ratifiedAt).toBe(RATIFY_NOW);
    expect(lead.provenance).toBe('from_chat');

    // (c) The Job is in `lead` state — the §O4 ∅ → lead transition fired.
    expect(job.jobId).toBe('50505050-5050-4050-8050-505050505050');
    expect(job.status).toBe('lead');
    expect(job.createdAt).toBe(RATIFY_NOW);

    // (d) All three cells round-trip through their canonical packers
    //     byte-identical — they're substrate-ready.
    const eUnpacked = estimateCellType.unpack(estimateBytes);
    const lUnpacked = leadCellType.unpack(leadBytes);
    const jUnpacked = jobCellType.unpack(jobBytes);
    expect(eUnpacked.estimateId).toBe(estimate.estimateId);
    expect(lUnpacked.leadId).toBe(lead.leadId);
    expect(jUnpacked.jobId).toBe(job.jobId);
    expect(jUnpacked.status).toBe('lead');

    // (e) The queue entry is marked ratified — replay-protected.
    expect(queue.getEntry(entry.queueId)!.status).toBe('ratified');
    expect(queue.listPending()).toHaveLength(0);
  });

  test('rejecting a draft does NOT emit any canonical cells', async () => {
    const turn0 = buildChatTurn({
      chatSessionId: SESSION,
      visitorText: 'just chatting, not a real lead',
      aiText: 'ok!',
      turnIndex: 0,
      nowIso: TURN_NOW,
    });
    const stubExtraction = JSON.stringify({
      has_lead: true,
      confidence: 0.6,
      customer_hint: 'maybe',
      draft: {
        estimate_type: 'auto_rom',
        effort_band: 'short',
        scope_summary: 'unclear request',
        urgency: 'low',
        assumption_notes: '',
      },
    });
    const r = await extractLead({
      chatSessionId: SESSION,
      messages: [turn0.visitorCell, turn0.aiCell],
      nowIso: TURN_NOW,
      draftEstimateId: DRAFT_EST_ID,
      placeholderJobId: PLACEHOLDER_JOB_ID,
      llmComplete: async () => ({ text: stubExtraction }),
    });
    expect(r.hasLead).toBe(true);

    const queue = new RatificationQueue(makeMemoryStorage());
    const entry = queue.enqueue({
      provenance: 'from_chat',
      chatSessionId: SESSION,
      customerHint: r.customerHint,
      draftEstimate: r.draftEstimate!,
      nowIso: TURN_NOW,
      queueIdOverride: '40404040-4040-4040-8040-404040404040',
    });

    expect(queue.reject(entry.queueId)).toBe(true);
    expect(queue.getEntry(entry.queueId)!.status).toBe('rejected');
    expect(queue.listPending()).toHaveLength(0);

    // No further cells emitted. We don't have a "no cells" assertion
    // (cells aren't auto-tracked), but the surface contract is: only
    // `ratify` returns RatifyResult. `reject` returns boolean.
  });
});

```
