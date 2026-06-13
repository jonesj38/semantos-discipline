---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/conversation.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.139480+00:00
---

# runtime/legacy-ingest/src/__tests__/conversation.test.ts

```ts
import { describe, it, expect } from 'bun:test';
import { ConversationEngine } from '../conversation/engine';
import { ConversationExtractor } from '../conversation/extractor';
import type { ConversationSession, ConversationTransport } from '../conversation/types';
import type { LLMAdapter } from '../extractor/types';

// ── Test helpers ──────────────────────────────────────────────────────────────

function makeSession(overrides: Partial<ConversationSession> = {}): ConversationSession {
  return {
    sessionId: 'widget:test-session-1',
    channel: 'widget',
    recipientId: 'client-abc',
    turns: [],
    facts: {},
    state: 'greeting',
    createdAt: Date.now(),
    updatedAt: Date.now(),
    ...overrides,
  };
}

function makeTransport(): { transport: ConversationTransport; sent: Array<{ to: string; text: string }> } {
  const sent: Array<{ to: string; text: string }> = [];
  const transport: ConversationTransport = {
    async send(recipientId, text) {
      sent.push({ to: recipientId, text });
    },
  };
  return { transport, sent };
}

function makeLLM(decisions: Array<{ reply: string; done: boolean; facts?: object }>): LLMAdapter {
  let call = 0;
  return {
    async extract() {
      const d = decisions[Math.min(call++, decisions.length - 1)];
      const payload = { reply: d.reply, done: d.done, facts: d.facts ?? {} };
      return { payload, confidence: 0.8, raw: JSON.stringify(payload) };
    },
  };
}

// ── ConversationEngine tests ──────────────────────────────────────────────────

describe('ConversationEngine', () => {
  it('sends LLM reply via transport and marks session gathering', async () => {
    const { transport, sent } = makeTransport();
    const llm = makeLLM([{ reply: "Great! What's the job?", done: false }]);
    const engine = new ConversationEngine({ llm, transport });
    const session = makeSession();

    const result = await engine.handleTurn(session, 'Hi I need some work done');

    expect(result.completed).toBe(false);
    expect(result.replySent).toBe("Great! What's the job?");
    expect(sent).toHaveLength(1);
    expect(sent[0].to).toBe('client-abc');
    expect(session.state).toBe('gathering');
    expect(session.turns).toHaveLength(2); // customer + assistant
  });

  it('marks session complete and returns extractedText when LLM sets done: true', async () => {
    const { transport } = makeTransport();
    const llm = makeLLM([{
      reply: "Thanks! We'll be in touch.",
      done: true,
      facts: {
        customerName: 'Bob Smith',
        customerPhone: '0411 222 333',
        jobDescription: 'Fix leaking tap',
        jobLocation: 'Bondi',
        desiredDate: 'next week',
      },
    }]);
    const engine = new ConversationEngine({ llm, transport });
    const session = makeSession();

    const result = await engine.handleTurn(session, 'I need a tap fixed in Bondi');

    expect(result.completed).toBe(true);
    expect(result.extractedText).toBeDefined();
    expect(result.extractedText).toContain('Fix leaking tap');
    expect(result.extractedText).toContain('Bondi');
    expect(result.extractedText).toContain('Bob Smith');
    expect(session.state).toBe('complete');
    expect(session.facts.customerName).toBe('Bob Smith');
  });

  it('accumulates facts across multiple turns', async () => {
    const { transport } = makeTransport();
    const llm = makeLLM([
      { reply: "Where is the job?", done: false, facts: { jobDescription: 'Paint fence' } },
      { reply: "When would you like it?", done: false, facts: { jobLocation: 'Manly' } },
      { reply: "Thanks, all noted!", done: true, facts: { desiredDate: 'Saturday' } },
    ]);
    const engine = new ConversationEngine({ llm, transport });
    const session = makeSession();

    await engine.handleTurn(session, 'Paint my fence');
    await engine.handleTurn(session, 'In Manly');
    await engine.handleTurn(session, 'This Saturday');

    expect(session.facts.jobDescription).toBe('Paint fence');
    expect(session.facts.jobLocation).toBe('Manly');
    expect(session.facts.desiredDate).toBe('Saturday');
  });

  it('forces completion after maxTurns customer turns', async () => {
    const { transport } = makeTransport();
    const llm = makeLLM([{ reply: 'OK, noted.', done: false }]);
    const engine = new ConversationEngine({ llm, transport, maxTurns: 2 });
    const session = makeSession();

    await engine.handleTurn(session, 'turn 1');
    const result = await engine.handleTurn(session, 'turn 2');

    expect(result.completed).toBe(true);
    expect(session.state).toBe('complete');
  });

  it('synthesised text includes channel and all facts', async () => {
    const { transport } = makeTransport();
    const llm = makeLLM([{
      reply: "Thanks!",
      done: true,
      facts: {
        customerName: 'Jane Doe',
        customerPhone: '0400 000 000',
        jobDescription: 'Bathroom renovation',
        jobLocation: 'Newtown',
        desiredDate: 'March',
      },
    }]);
    const engine = new ConversationEngine({ llm, transport });
    const session = makeSession({ channel: 'meta_messenger', recipientId: 'USER_PSIDxyz' });

    const result = await engine.handleTurn(session, 'Need a bathroom reno');

    expect(result.extractedText).toContain('meta_messenger');
    expect(result.extractedText).toContain('Jane Doe');
    expect(result.extractedText).toContain('Newtown');
  });
});

// ── ConversationExtractor tests ───────────────────────────────────────────────

function makeCompletedSession(facts = {}): ConversationSession {
  return {
    sessionId: 'widget:sess-1',
    channel: 'widget',
    recipientId: 'client-xyz',
    turns: [
      { role: 'customer', text: 'I need a tap fixed', timestamp: 1000 },
      { role: 'assistant', text: "Where is the job?", timestamp: 1001 },
      { role: 'customer', text: 'In Bondi', timestamp: 1002 },
      { role: 'assistant', text: "Thanks, we'll be in touch!", timestamp: 1003 },
    ],
    facts: {
      jobDescription: 'Fix leaking tap',
      jobLocation: 'Bondi',
      customerName: 'Alice',
      ...facts,
    },
    state: 'complete',
    createdAt: 1000,
    updatedAt: 1003,
  };
}

function makeSessionRawItem(session: ConversationSession) {
  return {
    providerId: 'widget',
    providerItemId: session.sessionId,
    fetchedAt: Date.now(),
    contentType: 'widget/chat',
    bytes: new TextEncoder().encode(JSON.stringify(session)),
    metadata: { channel: session.channel, sessionId: session.sessionId },
  };
}

describe('ConversationExtractor', () => {
  it('extracts a proposal from a completed session', async () => {
    const extractor = new ConversationExtractor();
    const session = makeCompletedSession();
    const item = makeSessionRawItem(session);
    const llm: LLMAdapter = {
      async extract() {
        return {
          payload: {
            intent: 'quote_request',
            summary: 'Leaking tap repair in Bondi',
            job: { description: 'Fix leaking tap', location: 'Bondi' },
          },
          confidence: 0.88,
          raw: '{}',
        };
      },
    };
    const outcomes = await extractor.extract(item, llm);
    expect(outcomes.length).toBe(1);
    const outcome = outcomes[0];
    expect(outcome.kind).toBe('extracted');
    if (outcome.kind === 'extracted') {
      expect(outcome.proposal.summary).toBe('Leaking tap repair in Bondi');
      expect(outcome.proposal.threadKey).toBe('widget:sess-1');
    }
  });

  it('pre-filters invalid JSON bytes', async () => {
    const extractor = new ConversationExtractor();
    const item = {
      providerId: 'widget', providerItemId: 'x', fetchedAt: 0,
      contentType: 'widget/chat', bytes: new TextEncoder().encode('not json'), metadata: {},
    };
    const outcomes = await extractor.extract(item, { extract: async () => ({ payload: {}, confidence: 1, raw: '' }) });
    expect(outcomes.length).toBe(1);
    const outcome = outcomes[0];
    expect(outcome.kind).toBe('pre-filtered');
  });

  it('pre-filters empty session', async () => {
    const extractor = new ConversationExtractor();
    const session: ConversationSession = {
      ...makeCompletedSession(),
      turns: [],
    };
    const item = makeSessionRawItem(session);
    const outcomes = await extractor.extract(item, { extract: async () => ({ payload: {}, confidence: 1, raw: '' }) });
    expect(outcomes.length).toBe(1);
    const outcome = outcomes[0];
    expect(outcome.kind).toBe('pre-filtered');
  });

  it('carries referenceNumber from facts when LLM does not extract it', async () => {
    const extractor = new ConversationExtractor();
    const session = makeCompletedSession({ referenceNumber: 'PM-9001' });
    const item = makeSessionRawItem(session);
    const llm: LLMAdapter = {
      async extract() {
        return {
          payload: { intent: 'quote_request', summary: 'some job' },
          confidence: 0.75,
          raw: '{}',
        };
      },
    };
    const outcomes = await extractor.extract(item, llm);
    expect(outcomes.length).toBe(1);
    const outcome = outcomes[0];
    expect(outcome.kind).toBe('extracted');
    if (outcome.kind === 'extracted') {
      expect(outcome.proposal.referenceNumber).toBe('PM-9001');
    }
  });

  it('drops low-confidence extractions', async () => {
    const extractor = new ConversationExtractor();
    const item = makeSessionRawItem(makeCompletedSession());
    const llm: LLMAdapter = {
      async extract() {
        return { payload: { intent: 'other', summary: 'unclear' }, confidence: 0.3, raw: '{}' };
      },
    };
    const outcomes = await extractor.extract(item, llm);
    expect(outcomes.length).toBe(1);
    const outcome = outcomes[0];
    expect(outcome.kind).toBe('low-confidence');
  });
});

```
