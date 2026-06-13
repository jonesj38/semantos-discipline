---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/conversation/extractor.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.161672+00:00
---

# runtime/legacy-ingest/src/conversation/extractor.ts

```ts
/**
 * ConversationExtractor — ContentExtractor for completed chat sessions.
 *
 * When the ConversationEngine marks a session complete, it serialises the
 * session as a `widget/chat` or `meta/message-session` RawItem (JSON bytes).
 * This extractor turns that into a structured Proposal using the same LLM
 * extraction pipeline as the email and message extractors.
 *
 * The synthesised text (from ConversationEngine.synthesiseText) gives the LLM
 * enough context: channel, facts gathered, and the full transcript.
 */

import type { SIRProgram } from '@semantos/semantos-sir';
import type { RawItem } from '../types';
import type { ContentExtractor, ExtractionOutcome, LLMAdapter, Proposal } from '../extractor/types';
import type { ConversationSession } from './types';

export const CONVERSATION_EXTRACTOR_VERSION = 'conversation-v0.1';

export interface ConversationExtractionPayload {
  intent: 'lead' | 'quote_request' | 'booking' | 'inquiry' | 'reply' | 'other';
  summary: string;
  customer?: {
    name?: string;
    email?: string;
    phone?: string;
  };
  job?: {
    description?: string;
    location?: string;
    desiredDate?: string;
    referenceNumber?: string;
  };
  rationale?: string;
}

const SCHEMA = {
  type: 'object',
  properties: {
    intent: { enum: ['lead', 'quote_request', 'booking', 'inquiry', 'reply', 'other'] },
    summary: { type: 'string' },
    customer: { type: 'object' },
    job: {
      type: 'object',
      properties: {
        description: { type: 'string' },
        location: { type: 'string' },
        desiredDate: { type: 'string' },
        referenceNumber: { type: 'string' },
      },
    },
    rationale: { type: 'string' },
  },
  required: ['intent', 'summary'],
} as const;

const PROMPT_TEMPLATE = `You are extracting a structured job lead from a completed intake conversation.
The conversation was conducted via {{CHANNEL}} and the transcript is below.

{{TEXT}}

Extract the intent and job details. Most conversations that reach completion should
be classified as 'lead' or 'quote_request'. Only use 'other' if it's clearly not
a job enquiry.`;

const PROMPT_HASH = hashString(PROMPT_TEMPLATE + '\n' + JSON.stringify(SCHEMA));

export interface ConversationExtractorOpts {
  acceptThreshold?: number;
  highConfidenceThreshold?: number;
}

export class ConversationExtractor implements ContentExtractor {
  readonly contentType = 'widget/chat';
  readonly extractorVersion = CONVERSATION_EXTRACTOR_VERSION;
  private readonly acceptThreshold: number;
  private readonly highConfidenceThreshold: number;

  constructor(opts: ConversationExtractorOpts = {}) {
    this.acceptThreshold = opts.acceptThreshold ?? 0.5;
    this.highConfidenceThreshold = opts.highConfidenceThreshold ?? 0.85;
    void this.highConfidenceThreshold;
  }

  async extract(item: RawItem, llm: LLMAdapter): Promise<ExtractionOutcome[]> {
    return [await this.extractOne(item, llm)];
  }

  // The Tier 1.7 ContentExtractor contract returns ExtractionOutcome[]
  // so the email extractor's bundle-fan-out path can produce N
  // proposals from a single bundle email. Conversation sessions are
  // 1:1 with a proposal — wrap in a single-element array.
  private async extractOne(item: RawItem, llm: LLMAdapter): Promise<ExtractionOutcome> {
    const session = parseSession(item.bytes);
    if (!session) {
      return { kind: 'pre-filtered', reason: 'invalid conversation session payload' };
    }

    if (session.turns.length === 0) {
      return { kind: 'pre-filtered', reason: 'empty conversation session' };
    }

    const channelLabel = channelDisplayName(session.channel);
    const text = synthesiseText(session);
    const prompt = PROMPT_TEMPLATE
      .replace('{{CHANNEL}}', channelLabel)
      .replace('{{TEXT}}', text.slice(0, 8000));

    const llmResult = await llm.extract<ConversationExtractionPayload>({ prompt, schema: SCHEMA });

    if (llmResult.confidence < this.acceptThreshold) {
      return {
        kind: 'low-confidence',
        confidence: llmResult.confidence,
        reason: `confidence ${llmResult.confidence.toFixed(2)} < threshold ${this.acceptThreshold}`,
      };
    }

    const proposal: Proposal = {
      proposalId: cryptoRandomId(),
      confidence: llmResult.confidence,
      status: 'pending',
      provenance: {
        providerId: item.providerId,
        providerItemId: item.providerItemId,
        fetchedAt: item.fetchedAt,
        extractorVersion: this.extractorVersion,
        promptHash: PROMPT_HASH,
      },
      extractedAt: Date.now(),
      program: buildMinimalProgram(llmResult.payload, session),
      threadKey: session.sessionId,
      referenceNumber: llmResult.payload.job?.referenceNumber ?? session.facts.referenceNumber,
      summary: llmResult.payload.summary,
    };

    return { kind: 'extracted', proposal };
  }
}

// ── Internal helpers ──────────────────────────────────────────────────────────

function parseSession(bytes: Uint8Array): ConversationSession | null {
  try {
    return JSON.parse(new TextDecoder().decode(bytes)) as ConversationSession;
  } catch {
    return null;
  }
}

function channelDisplayName(channel: string): string {
  switch (channel) {
    case 'meta_messenger': return 'Facebook Messenger';
    case 'meta_instagram': return 'Instagram DM';
    case 'widget':         return 'website chat widget';
    default:               return channel;
  }
}

function synthesiseText(session: ConversationSession): string {
  const lines: string[] = [`Channel: ${channelDisplayName(session.channel)}`];
  const f = session.facts;
  if (f.customerName) lines.push(`Customer name: ${f.customerName}`);
  if (f.customerPhone) lines.push(`Phone: ${f.customerPhone}`);
  if (f.jobDescription) lines.push(`Job: ${f.jobDescription}`);
  if (f.jobLocation) lines.push(`Location: ${f.jobLocation}`);
  if (f.desiredDate) lines.push(`Desired date: ${f.desiredDate}`);
  if (f.referenceNumber) lines.push(`Reference: ${f.referenceNumber}`);
  lines.push('', 'Conversation:');
  for (const turn of session.turns) {
    lines.push(`  ${turn.role === 'customer' ? 'Customer' : 'Us'}: ${turn.text}`);
  }
  return lines.join('\n');
}

function buildMinimalProgram(
  payload: ConversationExtractionPayload,
  session: ConversationSession,
): SIRProgram {
  const action = mapIntentToAction(payload.intent);
  const expressedAt = new Date().toISOString();
  return {
    primaryNodeId: '$s0',
    programGovernance: {
      trustClass: 'cosmetic',
      domainBinding: { flag: 0, mode: 'declared' },
    } as any,
    nodes: [
      {
        id: '$s0',
        category: { lexicon: 'jural', category: 'declaration' } as any,
        taxonomy: {} as any,
        identity: {} as any,
        governance: {
          trustClass: 'cosmetic',
          domainBinding: { flag: 0, mode: 'declared' },
        } as any,
        action,
        constraint: { kind: 'literal', value: 'true' } as any,
        target: { kind: 'identity', id: `${session.channel}:${session.recipientId}` } as any,
        provenance: {
          source: 'inferred',
          confidence: 0.7,
          inferenceRunId: session.sessionId,
          expressedAt,
          trustAtExpression: 'cosmetic',
        },
      },
    ],
  };
}

function mapIntentToAction(kind: ConversationExtractionPayload['intent']): string {
  switch (kind) {
    case 'lead':          return 'create_lead';
    case 'quote_request': return 'create_quote_request';
    case 'booking':       return 'create_booking';
    case 'inquiry':       return 'log_inquiry';
    case 'reply':         return 'attach_reply';
    case 'other':         return 'noop';
  }
}

function cryptoRandomId(): string {
  const bytes = new Uint8Array(16);
  globalThis.crypto.getRandomValues(bytes);
  return [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');
}

function hashString(s: string): string {
  let h = 5381;
  for (let i = 0; i < s.length; i++) {
    h = ((h << 5) + h) + s.charCodeAt(i);
    h = h | 0;
  }
  return `h${(h >>> 0).toString(16)}`;
}

```
