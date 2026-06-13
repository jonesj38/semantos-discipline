---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/conversation/engine.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.162503+00:00
---

# runtime/legacy-ingest/src/conversation/engine.ts

```ts
/**
 * ConversationEngine — LLM-driven multi-turn intake.
 *
 * Each inbound message is processed here. The engine:
 *   1. Appends the customer's turn to the session.
 *   2. Calls the LLM to decide what to ask next (or signal completion).
 *   3. Sends the reply via the transport.
 *   4. When the LLM signals `done: true`, closes the session and returns
 *      a synthesised text blob suitable for the extraction pipeline.
 *
 * The LLM plays the role of a friendly intake assistant who gathers:
 *   - what the job is
 *   - where it is (suburb / address)
 *   - when the customer wants it done
 *   - their name and best contact number
 *
 * We stop asking once all four are present OR after MAX_TURNS turns to avoid
 * interrogating people who give short answers.
 */

import type { LLMAdapter } from '../extractor/types';
import type {
  ConversationFacts,
  ConversationSession,
  ConversationTurn,
  ConversationTransport,
  TurnResult,
} from './types';

const MAX_TURNS = 8; // customer turns before we accept whatever we have

const SYSTEM_PROMPT = `You are a friendly intake assistant for a trades business.
Your job is to gather enough information about the customer's job request so the
tradesperson can decide whether to quote.

You need to collect (if not already known):
1. What the job is (brief description)
2. Where it is (suburb or address)
3. When they'd like it done
4. Their name and best phone number

Keep your replies short and conversational — one question at a time.
When you have all four pieces (or after several turns), respond with a JSON object:
{
  "reply": "<your next message to the customer, or a friendly wrap-up>",
  "done": true | false,
  "facts": {
    "customerName": "...",
    "customerPhone": "...",
    "jobDescription": "...",
    "jobLocation": "...",
    "desiredDate": "..."
  }
}

If done is true, the reply should thank the customer and let them know the
tradesperson will be in touch soon.`;

interface EngineDecision {
  reply: string;
  done: boolean;
  facts: Partial<ConversationFacts>;
}

export interface ConversationEngineOpts {
  llm: LLMAdapter;
  transport: ConversationTransport;
  /** Max customer turns before forcing completion. Default: 8. */
  maxTurns?: number;
}

export class ConversationEngine {
  private readonly llm: LLMAdapter;
  private readonly transport: ConversationTransport;
  private readonly maxTurns: number;

  constructor(opts: ConversationEngineOpts) {
    this.llm = opts.llm;
    this.transport = opts.transport;
    this.maxTurns = opts.maxTurns ?? MAX_TURNS;
  }

  /**
   * Process one inbound customer turn. Updates the session in-place and
   * returns a TurnResult describing what happened.
   */
  async handleTurn(session: ConversationSession, customerText: string): Promise<TurnResult> {
    const customerTurn: ConversationTurn = {
      role: 'customer',
      text: customerText,
      timestamp: Date.now(),
    };
    session.turns.push(customerTurn);
    session.updatedAt = Date.now();

    const customerTurnCount = session.turns.filter(t => t.role === 'customer').length;
    const forceComplete = customerTurnCount >= this.maxTurns;

    const decision = await this.askLLM(session, forceComplete);

    // Merge any newly extracted facts
    Object.assign(session.facts, filterDefined(decision.facts));

    const replyTurn: ConversationTurn = {
      role: 'assistant',
      text: decision.reply,
      timestamp: Date.now(),
    };
    session.turns.push(replyTurn);
    session.updatedAt = Date.now();

    await this.transport.send(session.recipientId, decision.reply);

    if (decision.done || forceComplete) {
      session.state = 'complete';
      const extractedText = synthesiseText(session);
      return { replySent: decision.reply, completed: true, extractedText };
    }

    session.state = 'gathering';
    return { replySent: decision.reply, completed: false };
  }

  private async askLLM(session: ConversationSession, forceComplete: boolean): Promise<EngineDecision> {
    const conversationLog = session.turns
      .map(t => `${t.role === 'customer' ? 'Customer' : 'Assistant'}: ${t.text}`)
      .join('\n');

    const knownFacts = JSON.stringify(session.facts, null, 2);
    const prompt = `${SYSTEM_PROMPT}

Current conversation:
---
${conversationLog}
---

Facts gathered so far:
${knownFacts}
${forceComplete ? '\n[INSTRUCTION: We have reached the turn limit. Set done: true in your response.]' : ''}

Respond ONLY with a JSON object in the shape described above.`;

    const schema = {
      type: 'object',
      properties: {
        reply: { type: 'string' },
        done: { type: 'boolean' },
        facts: { type: 'object' },
      },
      required: ['reply', 'done', 'facts'],
    };

    const result = await this.llm.extract<EngineDecision>({ prompt, schema });
    return {
      reply: result.payload.reply ?? "Thanks for your message! I'll pass this along.",
      done: Boolean(result.payload.done),
      facts: result.payload.facts ?? {},
    };
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function synthesiseText(session: ConversationSession): string {
  const lines: string[] = [
    `Channel: ${session.channel}`,
    `Session: ${session.sessionId}`,
  ];
  const f = session.facts;
  if (f.customerName) lines.push(`Customer name: ${f.customerName}`);
  if (f.customerPhone) lines.push(`Phone: ${f.customerPhone}`);
  if (f.jobDescription) lines.push(`Job: ${f.jobDescription}`);
  if (f.jobLocation) lines.push(`Location: ${f.jobLocation}`);
  if (f.desiredDate) lines.push(`Desired date: ${f.desiredDate}`);
  if (f.referenceNumber) lines.push(`Reference: ${f.referenceNumber}`);
  lines.push('');
  lines.push('Conversation transcript:');
  for (const turn of session.turns) {
    lines.push(`  ${turn.role === 'customer' ? 'Customer' : 'Us'}: ${turn.text}`);
  }
  return lines.join('\n');
}

function filterDefined<T extends object>(obj: T): Partial<T> {
  const out: Partial<T> = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v !== undefined && v !== null && v !== '') {
      (out as Record<string, unknown>)[k] = v;
    }
  }
  return out;
}

```
