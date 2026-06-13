---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/extractor/message.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.157693+00:00
---

# runtime/legacy-ingest/src/extractor/message.ts

```ts
/**
 * Message extractor — handles 'meta/message' content type.
 *
 * Converts a MetaWebhookMessage (stored as JSON bytes by MetaProvider) into
 * a structured Proposal using the same LLM extraction pipeline as the email
 * extractor. The threadKey is the sender's PSID / IGSID, so all messages in
 * a conversation collapse into a single proposal via collapseThreads().
 *
 * Echo messages (bot's own replies stored for audit) are pre-filtered here —
 * they will never generate proposals.
 */

import type { SIRProgram } from '@semantos/semantos-sir';
import type { RawItem } from '../types';
import type { ContentExtractor, ExtractionOutcome, LLMAdapter, Proposal } from './types';
import type { MetaWebhookMessage } from '../providers/meta';
import { classifyForExtraction } from './pre-classifier';

export const MESSAGE_EXTRACTOR_VERSION = 'meta-message-v0.1';

export interface MessageExtractionPayload {
  intent: 'lead' | 'quote_request' | 'booking' | 'inquiry' | 'reply' | 'other';
  summary: string;
  customer?: {
    name?: string;
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

const PROMPT_TEMPLATE = `You are extracting a structured intent from a direct message
sent to a tradesperson's business inbox via {{CHANNEL}}.
Decide whether this is a job-related enquiry and, if so, what the customer is asking for.

Channel: {{CHANNEL}}
Message:
---
{{TEXT}}
---

Respond with a JSON object matching the schema. If this is not a business enquiry
(spam, automated platform notification, ad click), respond with intent: 'other'.`;

const PROMPT_HASH = hashString(PROMPT_TEMPLATE + '\n' + JSON.stringify(SCHEMA));

export interface MessageExtractorOpts {
  acceptThreshold?: number;
  highConfidenceThreshold?: number;
}

export class MessageExtractor implements ContentExtractor {
  readonly contentType = 'meta/message';
  readonly extractorVersion = MESSAGE_EXTRACTOR_VERSION;
  private readonly acceptThreshold: number;
  private readonly highConfidenceThreshold: number;

  constructor(opts: MessageExtractorOpts = {}) {
    this.acceptThreshold = opts.acceptThreshold ?? 0.5;
    this.highConfidenceThreshold = opts.highConfidenceThreshold ?? 0.85;
    void this.highConfidenceThreshold;
  }

  async extract(item: RawItem, llm: LLMAdapter): Promise<ExtractionOutcome[]> {
    return [await this.extractOne(item, llm)];
  }

  // The Tier 1.7 ContentExtractor contract returns ExtractionOutcome[]
  // so the email extractor's bundle-fan-out path can produce N
  // proposals from a single bundle email. For Meta DM messages
  // there's only ever one outcome per inbound webhook payload — we
  // delegate to a private one-shot helper and wrap in a single-element
  // array. Behaviour is unchanged.
  private async extractOne(item: RawItem, llm: LLMAdapter): Promise<ExtractionOutcome> {
    const pre = classifyForExtraction(item);
    if (!pre.shouldExtract) {
      return { kind: 'pre-filtered', reason: pre.droppedReason ?? 'pre-classifier' };
    }

    const meta = parseMetaMessage(item.bytes);
    if (!meta) {
      return { kind: 'pre-filtered', reason: 'invalid meta/message payload' };
    }

    if (meta.isEchoOrAd) {
      return { kind: 'pre-filtered', reason: 'meta echo message (bot own reply)' };
    }

    const text = meta.text?.trim() ?? '';
    if (text.length === 0) {
      return { kind: 'pre-filtered', reason: 'no text in meta message (attachment/sticker only)' };
    }

    const channelLabel = meta.channel === 'instagram' ? 'Instagram DM' : 'Facebook Messenger';
    const prompt = PROMPT_TEMPLATE
      .replace(/\{\{CHANNEL\}\}/g, channelLabel)
      .replace('{{TEXT}}', text.slice(0, 4000));

    const llmResult = await llm.extract<MessageExtractionPayload>({ prompt, schema: SCHEMA });

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
      program: buildMinimalProgram(llmResult.payload, meta),
      threadKey: `meta:${meta.threadId}`,
      referenceNumber: llmResult.payload.job?.referenceNumber,
      summary: llmResult.payload.summary,
    };

    return { kind: 'extracted', proposal };
  }
}

// ── Internal helpers ──────────────────────────────────────────────────────────

function parseMetaMessage(bytes: Uint8Array): MetaWebhookMessage | null {
  try {
    return JSON.parse(new TextDecoder().decode(bytes)) as MetaWebhookMessage;
  } catch {
    return null;
  }
}

function buildMinimalProgram(
  payload: MessageExtractionPayload,
  meta: MetaWebhookMessage,
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
        target: { kind: 'identity', id: `meta:${meta.senderId}` } as any,
        provenance: {
          source: 'inferred',
          confidence: 0.7,
          inferenceRunId: meta.messageId,
          expressedAt,
          trustAtExpression: 'cosmetic',
        },
      },
    ],
  };
}

function mapIntentToAction(kind: MessageExtractionPayload['intent']): string {
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
