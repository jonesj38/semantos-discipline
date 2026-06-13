---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/lead-extract.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.473921+00:00
---

# cartridges/oddjobz/brain/src/lead-extract.ts

```ts
/**
 * D-O6b — Public chat v1.0 — lead-extract resource.
 *
 * Reads ALL `oddjobz.message.v1` cells for a given chatSessionId, runs
 * them through `llm.complete` with a lead-extraction system prompt,
 * and returns `{has_lead, draft_estimate, confidence}`. The drafted
 * Estimate is NOT yet signed — that's the ratification queue's job.
 *
 * Per `BRAIN-DISPATCHER-UNIFICATION.md` §2.5 the carpenter-musician
 * motivating example calls out this resource verbatim:
 *   "resource: oddjobz.lead_extract (uses llm.complete with carpenter
 *    scope)"
 *
 * The TS-layer module here is the PURE shape of the resource — given
 * an `LlmCompleteFn` callback (typically wired to the dispatcher's
 * `llm.complete` resource), it builds the prompt, parses the response,
 * and returns the typed result. The brain-side dispatcher registration
 * lives at `runtime/semantos-brain/src/resources/lead_extract_handler.zig` (out
 * of scope for this PR — TS layer demonstrates the canon).
 *
 * Confidence policy: the LLM is asked to return a confidence score
 * in [0, 1]. The TS layer treats values < 0.5 as has_lead=false even
 * if the LLM said true (defensive — operator's time is expensive).
 */

import type { OddjobzMessage } from './cell-types/message.js';
import type { OddjobzEstimate } from './cell-types/estimate.js';

/**
 * Callback for invoking the dispatcher's `llm.complete` resource.
 * The TS-layer lead-extract is parameterised over this so tests can
 * inject a deterministic mock; the Semantos Brain-side dispatcher registration
 * provides a real-LLM callback.
 */
export type LlmCompleteFn = (args: {
  readonly prompt: string;
  readonly system_prompt: string;
  readonly scope: string;
}) => Promise<{ readonly text: string }>;

/** Input for the `oddjobz.lead_extract.extract` command. */
export interface LeadExtractInput {
  /** The chat session id to extract from. */
  readonly chatSessionId: string;
  /** All persisted messages for the session (visitor + ai). */
  readonly messages: readonly OddjobzMessage[];
  /** ISO-8601 wall-clock timestamp to stamp on the draft Estimate. */
  readonly nowIso: string;
  /** UUID v4 to use for the drafted Estimate's stable id. */
  readonly draftEstimateId: string;
  /** UUID v4 placeholder for the (not-yet-existing) Job. */
  readonly placeholderJobId: string;
  /**
   * Confidence floor — drafts below this are returned as has_lead=false.
   * Default 0.5 per the policy in the module head.
   */
  readonly confidenceFloor?: number;
  /** The dispatcher-mediated `llm.complete` callback. */
  readonly llmComplete: LlmCompleteFn;
}

/** Output for the `oddjobz.lead_extract.extract` command. */
export interface LeadExtractResult {
  /** Whether a lead-shaped inquiry was detected. */
  readonly hasLead: boolean;
  /**
   * Drafted Estimate cell shape (NOT yet signed). null when no lead
   * was detected. The Estimate's jobId is a placeholder — the
   * ratification step substitutes the freshly-minted Job's id.
   */
  readonly draftEstimate: OddjobzEstimate | null;
  /** LLM-self-reported confidence in [0, 1]. */
  readonly confidence: number;
  /**
   * Customer-hint string extracted from the chat (name, contact, brief
   * description). Empty string when the LLM didn't surface one.
   */
  readonly customerHint: string;
  /** The raw LLM response, for audit / debug. */
  readonly rawResponse: string;
}

/**
 * Build the lead-extraction system prompt. Stable, deterministic —
 * reused across calls so the LLM's response shape is predictable.
 * Pure function; tests assert the prompt's invariants (e.g. it
 * mentions the JSON output shape verbatim).
 */
export function buildLeadExtractionPrompt(): string {
  return [
    'You are a lead-extraction agent for a tradesperson business.',
    'You scan chat messages between a visitor and an AI assistant for an inquiry about real trades work',
    '(e.g. plumbing, electrical, carpentry, deck repair, kitchen renovation, painting, tiling, etc.).',
    '',
    'If the conversation contains a lead — that is, the visitor described a job they want done',
    'and gave any contact information (phone, name, suburb) — extract a draft Estimate.',
    '',
    'Output ONLY a single JSON object with this exact shape:',
    '{',
    '  "has_lead": <true|false>,',
    '  "confidence": <number in [0, 1]>,',
    '  "customer_hint": "<name + contact + brief job description, or empty string>",',
    '  "draft": {',
    '    "estimate_type": "auto_rom",',
    '    "effort_band": "<quick|short|half_day|full_day|multi_day|null>",',
    '    "cost_min_cents": <integer or null>,',
    '    "cost_max_cents": <integer or null>,',
    '    "scope_summary": "<one-paragraph job description>",',
    '    "urgency": "<low|medium|high>",',
    '    "assumption_notes": "<one-line assumptions, or empty>"',
    '  }',
    '}',
    '',
    'If has_lead is false, set draft to null.',
    'Cost figures should be in CENTS (so $3000 = 300000 cents).',
    'Be conservative on confidence: only return >0.7 when you are sure.',
    'Output ONLY the JSON object — no preamble, no markdown fences.',
  ].join('\n');
}

/**
 * Render the messages into a flat transcript for the LLM. Visitor
 * messages are prefixed with `Visitor:` and AI messages with `AI:`
 * — gives the model a clean view of the dialogue.
 */
export function renderTranscript(
  messages: readonly OddjobzMessage[],
): string {
  const lines: string[] = [];
  for (const m of messages) {
    if (m.senderType === 'customer') {
      lines.push('Visitor: ' + m.rawContent);
    } else if (m.senderType === 'ai') {
      lines.push('AI: ' + m.rawContent);
    } else if (m.senderType === 'operator') {
      lines.push('Operator: ' + m.rawContent);
    } else {
      lines.push('System: ' + m.rawContent);
    }
  }
  return lines.join('\n');
}

const ALLOWED_EFFORT_BANDS = new Set([
  'quick',
  'short',
  'half_day',
  'full_day',
  'multi_day',
]);

interface ParsedDraft {
  readonly estimateType: 'auto_rom';
  readonly effortBand?: string;
  readonly costMin?: number;
  readonly costMax?: number;
  readonly scopeSummary: string;
  readonly urgency: 'low' | 'medium' | 'high';
  readonly assumptionNotes: string;
}

interface ParsedResponse {
  readonly hasLead: boolean;
  readonly confidence: number;
  readonly customerHint: string;
  readonly draft: ParsedDraft | null;
}

/** Parse the LLM response. Defensive — bad shapes fall back to no-lead. */
export function parseExtractionResponse(raw: string): ParsedResponse {
  let text = raw.trim();
  // Strip markdown fences if the LLM ignored the prompt.
  if (text.startsWith('```')) {
    const idx = text.indexOf('\n');
    if (idx > 0) text = text.slice(idx + 1);
    if (text.endsWith('```')) text = text.slice(0, -3).trim();
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return { hasLead: false, confidence: 0, customerHint: '', draft: null };
  }
  if (typeof parsed !== 'object' || parsed === null) {
    return { hasLead: false, confidence: 0, customerHint: '', draft: null };
  }
  const o = parsed as Record<string, unknown>;
  const hasLead = o.has_lead === true;
  const confidence =
    typeof o.confidence === 'number' && Number.isFinite(o.confidence)
      ? Math.max(0, Math.min(1, o.confidence))
      : 0;
  const customerHint =
    typeof o.customer_hint === 'string' ? o.customer_hint.slice(0, 4000) : '';

  let draft: ParsedDraft | null = null;
  if (hasLead && typeof o.draft === 'object' && o.draft !== null) {
    const d = o.draft as Record<string, unknown>;
    const effortBandRaw = typeof d.effort_band === 'string' ? d.effort_band : '';
    const effortBand = ALLOWED_EFFORT_BANDS.has(effortBandRaw)
      ? effortBandRaw
      : undefined;
    const costMin =
      typeof d.cost_min_cents === 'number' && Number.isInteger(d.cost_min_cents) && d.cost_min_cents >= 0
        ? d.cost_min_cents
        : undefined;
    const costMax =
      typeof d.cost_max_cents === 'number' && Number.isInteger(d.cost_max_cents) && d.cost_max_cents >= 0
        ? d.cost_max_cents
        : undefined;
    const scopeSummary =
      typeof d.scope_summary === 'string' ? d.scope_summary.slice(0, 4000) : '';
    const urgencyRaw = typeof d.urgency === 'string' ? d.urgency : 'medium';
    const urgency: 'low' | 'medium' | 'high' =
      urgencyRaw === 'low' || urgencyRaw === 'high' ? urgencyRaw : 'medium';
    const assumptionNotes =
      typeof d.assumption_notes === 'string'
        ? d.assumption_notes.slice(0, 4000)
        : '';
    draft = {
      estimateType: 'auto_rom',
      effortBand,
      costMin,
      costMax,
      scopeSummary,
      urgency,
      assumptionNotes,
    };
  }

  return { hasLead, confidence, customerHint, draft };
}

/**
 * Build the draft Estimate cell shape from a parsed LLM response.
 * The Estimate's jobId is a placeholder — the ratification step
 * substitutes the freshly-minted Job's id.
 */
function buildDraftEstimate(
  draft: ParsedDraft,
  draftEstimateId: string,
  placeholderJobId: string,
  nowIso: string,
): OddjobzEstimate {
  // Build via a mutable record so the TS readonly flags on the
  // OddjobzEstimate interface aren't violated, then cast back to the
  // typed shape on return.
  const out: Record<string, unknown> = {
    estimateId: draftEstimateId,
    jobId: placeholderJobId,
    estimateType: 'auto_rom',
    createdAt: nowIso,
    updatedAt: nowIso,
  };
  if (draft.effortBand !== undefined) {
    out.effortBand = draft.effortBand;
  }
  if (draft.costMin !== undefined) out.costMin = draft.costMin;
  if (draft.costMax !== undefined) out.costMax = draft.costMax;
  if (draft.assumptionNotes.length > 0) {
    // The cell-type's assumptionNotes is operator-supplied free text;
    // we plumb the LLM's notes through here so the ratification UI
    // shows the full inferred context.
    out.assumptionNotes = draft.assumptionNotes;
  }
  if (draft.scopeSummary.length > 0) {
    // materialsNote is the closest existing field for a free-form
    // scope description. The cell-type doesn't have a dedicated
    // scope_summary field; we plumb here to avoid forking the schema.
    out.materialsNote = draft.scopeSummary;
  }
  return out as unknown as OddjobzEstimate;
}

/**
 * Run lead extraction over a chat session's messages.
 *
 * Pure orchestration: builds the prompt, calls the LLM, parses the
 * response, applies the confidence floor, returns the drafted
 * Estimate (if any).
 */
export async function extractLead(
  input: LeadExtractInput,
): Promise<LeadExtractResult> {
  const transcript = renderTranscript(input.messages);
  const systemPrompt = buildLeadExtractionPrompt();
  const userPrompt =
    'Chat session id: ' +
    input.chatSessionId +
    '\n' +
    'Transcript:\n' +
    transcript;

  const response = await input.llmComplete({
    prompt: userPrompt,
    system_prompt: systemPrompt,
    scope: 'oddjobz-internal',
  });

  const parsed = parseExtractionResponse(response.text);
  const floor = input.confidenceFloor ?? 0.5;
  const meetsFloor = parsed.confidence >= floor;
  const finalHasLead = parsed.hasLead && meetsFloor && parsed.draft !== null;

  let draftEstimate: OddjobzEstimate | null = null;
  if (finalHasLead && parsed.draft !== null) {
    draftEstimate = buildDraftEstimate(
      parsed.draft,
      input.draftEstimateId,
      input.placeholderJobId,
      input.nowIso,
    );
  }

  return {
    hasLead: finalHasLead,
    draftEstimate,
    confidence: parsed.confidence,
    customerHint: parsed.customerHint,
    rawResponse: response.text,
  };
}

```
