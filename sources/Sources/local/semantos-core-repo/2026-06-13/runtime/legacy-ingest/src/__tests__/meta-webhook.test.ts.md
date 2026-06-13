---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/meta-webhook.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.139781+00:00
---

# runtime/legacy-ingest/src/__tests__/meta-webhook.test.ts

```ts
import { describe, it, expect } from 'bun:test';
import { MetaWebhookServer } from '../webhook/meta-server';
import { MetaProvider } from '../providers/meta';
import { MemorySessionStore } from '../widget/session-store';
import type { LLMAdapter } from '../extractor/types';
import type { Proposal } from '../extractor/types';
import type { ConversationTurnEvent } from '../conversation/types';

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeProvider() {
  return new MetaProvider({
    verifyToken: 'test-verify-token',
    fetch: async () => new Response('{}', { status: 200 }),
  });
}

function makeHighConfidenceLLM(): LLMAdapter {
  return {
    async extract() {
      return {
        payload: {
          intent: 'quote_request',
          summary: 'Fence repair in Bondi',
          job: { description: 'Fix fence', location: 'Bondi' },
        },
        confidence: 0.92,
        raw: '{}',
      };
    },
  };
}

function makeLowConfidenceLLM(): LLMAdapter {
  return {
    async extract() {
      return {
        payload: { intent: 'inquiry', summary: 'Unclear enquiry', reply: "What job do you need?", done: false, facts: {} },
        confidence: 0.45,
        raw: '{}',
      };
    },
  };
}

function makeConversationLLM(decisions: Array<{ reply: string; done: boolean; facts?: object }>): LLMAdapter {
  let call = 0;
  return {
    async extract() {
      const d = decisions[Math.min(call++, decisions.length - 1)];
      return {
        payload: { intent: 'quote_request', summary: 'job', reply: d.reply, done: d.done, facts: d.facts ?? {} },
        confidence: 0.75,
        raw: '{}',
      };
    },
  };
}

function webhookPayload(text: string, opts: { senderId?: string; isEcho?: boolean } = {}) {
  return {
    object: 'page',
    entry: [{
      id: 'PAGE_ID',
      messaging: [{
        sender: { id: opts.senderId ?? 'USER_001' },
        recipient: { id: 'PAGE_ID' },
        timestamp: Date.now(),
        message: {
          mid: `MSG_${Date.now()}`,
          text,
          is_echo: opts.isEcho ?? false,
        },
      }],
    }],
  };
}

async function post(server: MetaWebhookServer, body: object): Promise<Response> {
  const req = new Request('http://localhost/meta/webhook', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  return server.handle(req);
}

async function get(server: MetaWebhookServer, params: Record<string, string>): Promise<Response> {
  const qs = new URLSearchParams(params).toString();
  const req = new Request(`http://localhost/meta/webhook?${qs}`, { method: 'GET' });
  return server.handle(req);
}

// ── Challenge verification ─────────────────────────────────────────────────

describe('MetaWebhookServer - challenge verification', () => {
  it('responds with challenge on valid subscribe', async () => {
    const server = new MetaWebhookServer({
      provider: makeProvider(),
      pageAccessToken: 'PAGE_TOKEN',
      llm: makeHighConfidenceLLM(),
    });
    const res = await get(server, {
      'hub.mode': 'subscribe',
      'hub.verify_token': 'test-verify-token',
      'hub.challenge': 'abc123',
    });
    expect(res.status).toBe(200);
    expect(await res.text()).toBe('abc123');
  });

  it('returns 403 on wrong verify token', async () => {
    const server = new MetaWebhookServer({
      provider: makeProvider(),
      pageAccessToken: 'PAGE_TOKEN',
      llm: makeHighConfidenceLLM(),
    });
    const res = await get(server, {
      'hub.mode': 'subscribe',
      'hub.verify_token': 'wrong',
      'hub.challenge': 'abc123',
    });
    expect(res.status).toBe(403);
  });

  it('returns 404 for unknown paths', async () => {
    const server = new MetaWebhookServer({
      provider: makeProvider(),
      pageAccessToken: 'PAGE_TOKEN',
      llm: makeHighConfidenceLLM(),
    });
    const req = new Request('http://localhost/meta/other', { method: 'GET' });
    const res = await server.handle(req);
    expect(res.status).toBe(404);
  });
});

// ── Event routing — high-confidence direct extraction ─────────────────────

describe('MetaWebhookServer - direct extraction (high confidence)', () => {
  it('emits a Proposal without starting a conversation', async () => {
    const proposals: Proposal[] = [];
    const sessions = new MemorySessionStore();
    const server = new MetaWebhookServer({
      provider: makeProvider(),
      pageAccessToken: 'PAGE_TOKEN',
      llm: makeHighConfidenceLLM(),
      sessions,
      onProposal: async (p) => { proposals.push(p); },
      extractionThreshold: 0.85,
    });

    const res = await post(server, webhookPayload(
      'I need a fence fixed at 12 Smith St Bondi, call me on 0411 222 333',
    ));

    expect(res.status).toBe(200);
    // Give async onProposal time to complete
    await new Promise(r => setTimeout(r, 20));
    expect(proposals).toHaveLength(1);
    expect(proposals[0].summary).toContain('Fence repair');
    // No session should have been created
    expect(sessions.size).toBe(0);
  });

  it('emits customer and assistant turn events for direct extraction', async () => {
    const events: ConversationTurnEvent[] = [];
    const server = new MetaWebhookServer({
      provider: makeProvider(),
      pageAccessToken: 'PAGE_TOKEN',
      llm: makeHighConfidenceLLM(),
      onConversationTurn: (event) => {
        events.push(event);
      },
      extractionThreshold: 0.85,
    });

    const res = await post(server, webhookPayload(
      'I need a fence fixed at 12 Smith St Bondi, call me on 0411 222 333',
    ));

    expect(res.status).toBe(200);
    await new Promise(r => setTimeout(r, 20));
    expect(events.map((event) => event.role)).toEqual(['customer', 'assistant']);
    expect(events[0]?.providerId).toBe('meta');
    expect(events[0]?.sessionId).toBe('meta:messenger:PAGE_ID:USER_001');
    expect(events[0]?.channel).toBe('meta_messenger');
    expect(events[0]?.recipientId).toBe('USER_001');
    expect(events[0]?.text).toContain('fence fixed');
    expect(events[1]?.text).toContain("we've got your message");
  });
});

// ── Event routing — low-confidence starts conversation ────────────────────

describe('MetaWebhookServer - conversation intake (low confidence)', () => {
  it('starts a session when extraction confidence is below threshold', async () => {
    const sessions = new MemorySessionStore();
    const server = new MetaWebhookServer({
      provider: makeProvider(),
      pageAccessToken: 'PAGE_TOKEN',
      llm: makeConversationLLM([
        { reply: "Hi! What job do you need done?", done: false },
      ]),
      sessions,
      extractionThreshold: 0.85,
    });

    const res = await post(server, webhookPayload('hi'));
    expect(res.status).toBe(200);
    await new Promise(r => setTimeout(r, 20));
    // A session should exist for this sender
    const session = await sessions.get('meta:messenger:PAGE_ID:USER_001');
    expect(session).not.toBeNull();
    expect(session?.state).toBe('gathering');
    expect(session?.turns.length).toBeGreaterThan(0);
  });

  it('emits turn events when a low-confidence message starts a conversation', async () => {
    const events: ConversationTurnEvent[] = [];
    const sessions = new MemorySessionStore();
    const server = new MetaWebhookServer({
      provider: makeProvider(),
      pageAccessToken: 'PAGE_TOKEN',
      llm: makeConversationLLM([
        { reply: 'placeholder for MessageExtractor', done: false, facts: {} },
        { reply: "What job do you need done?", done: false, facts: { jobDescription: 'fix tap' } },
      ]),
      sessions,
      extractionThreshold: 0.85,
      onConversationTurn: (event) => {
        events.push(event);
      },
    });

    const res = await post(server, webhookPayload('hi'));

    expect(res.status).toBe(200);
    await new Promise(r => setTimeout(r, 30));
    expect(events.map((event) => event.role)).toEqual(['customer', 'assistant']);
    expect(events[0]?.providerId).toBe('meta');
    expect(events[0]?.sessionId).toBe('meta:messenger:PAGE_ID:USER_001');
    expect(events[0]?.channel).toBe('meta_messenger');
    expect(events[0]?.text).toBe('hi');
    expect(events[1]?.text).toBe("What job do you need done?");
  });

  it('continues an existing session on subsequent messages', async () => {
    const sessions = new MemorySessionStore();
    // MessageExtractor consumes one LLM call for the *first* message before
    // ConversationEngine takes over. Decisions are indexed sequentially:
    //   [0] MessageExtractor("hi")       — confidence 0.75 < threshold → start conversation
    //   [1] ConversationEngine turn 1    — ask "What job?" + record jobDescription
    //   [2] ConversationEngine turn 2    — ask "Where?" (no new facts yet)
    //   [3] ConversationEngine turn 3    — done, record jobLocation
    const server = new MetaWebhookServer({
      provider: makeProvider(),
      pageAccessToken: 'PAGE_TOKEN',
      llm: makeConversationLLM([
        { reply: 'placeholder for MessageExtractor', done: false, facts: {} },           // [0] MessageExtractor
        { reply: "What job do you need done?", done: false, facts: { jobDescription: 'fix tap' } }, // [1] CE turn 1
        { reply: "Where is the job?", done: false, facts: {} },                          // [2] CE turn 2
        { reply: "Thanks, we'll be in touch!", done: true, facts: { jobLocation: 'Bondi' } }, // [3] CE turn 3
      ]),
      sessions,
      extractionThreshold: 0.85,
    });

    // First message — starts session; MessageExtractor uses decision[0], CE uses decision[1]
    await post(server, webhookPayload('hi'));
    await new Promise(r => setTimeout(r, 30));

    expect((await sessions.get('meta:messenger:PAGE_ID:USER_001'))?.facts.jobDescription).toBe('fix tap');

    // Second message — CE uses decision[2]
    await post(server, webhookPayload('Fix a leaking tap'));
    await new Promise(r => setTimeout(r, 30));

    // Third message — CE uses decision[3], session completes
    await post(server, webhookPayload('In Bondi'));
    await new Promise(r => setTimeout(r, 30));

    const final = await sessions.get('meta:messenger:PAGE_ID:USER_001');
    expect(final?.state).toBe('complete');
    expect(final?.facts.jobLocation).toBe('Bondi');
  });

  it('emits a Proposal when conversation completes', async () => {
    const proposals: Proposal[] = [];
    const sessions = new MemorySessionStore();
    const server = new MetaWebhookServer({
      provider: makeProvider(),
      pageAccessToken: 'PAGE_TOKEN',
      llm: makeConversationLLM([
        {
          reply: "Thanks!",
          done: true,
          facts: { jobDescription: 'paint fence', jobLocation: 'Newtown', customerName: 'Bob' },
        },
      ]),
      sessions,
      onProposal: async (p) => { proposals.push(p); },
      extractionThreshold: 0.85,
    });

    await post(server, webhookPayload('paint my fence in Newtown, Bob here'));
    await new Promise(r => setTimeout(r, 50));

    // Session should be complete and a proposal emitted
    const session = await sessions.get('meta:messenger:PAGE_ID:USER_001');
    expect(session?.state).toBe('complete');
    expect(proposals.length).toBeGreaterThan(0);
  });
});

// ── Echo filtering ─────────────────────────────────────────────────────────

describe('MetaWebhookServer - echo filtering', () => {
  it('ignores echo messages from the bot', async () => {
    const proposals: Proposal[] = [];
    const sessions = new MemorySessionStore();
    const server = new MetaWebhookServer({
      provider: makeProvider(),
      pageAccessToken: 'PAGE_TOKEN',
      llm: makeHighConfidenceLLM(),
      sessions,
      onProposal: async (p) => { proposals.push(p); },
    });

    await post(server, webhookPayload('Thanks for contacting us!', { isEcho: true }));
    await new Promise(r => setTimeout(r, 20));
    expect(proposals).toHaveLength(0);
    expect(sessions.size).toBe(0);
  });
});

// ── CORS on WidgetServer ───────────────────────────────────────────────────

describe('WidgetServer CORS', () => {
  it('responds to preflight with correct CORS headers', async () => {
    const { WidgetServer } = await import('../widget/server');
    const { OpenRouterAdapter } = await import('../extractor/openrouter');
    const server = new WidgetServer({
      llm: new OpenRouterAdapter({ apiKey: 'sk-test', fetch: async () => new Response('{}') }),
      allowedOrigins: ['https://oddjobtodd.info'],
    });
    const req = new Request('http://localhost/widget/chat/start', {
      method: 'OPTIONS',
      headers: { origin: 'https://oddjobtodd.info' },
    });
    const res = await server.handle(req);
    expect(res.status).toBe(204);
    expect(res.headers.get('access-control-allow-origin')).toBe('https://oddjobtodd.info');
    expect(res.headers.get('access-control-allow-methods')).toContain('POST');
  });

  it('returns 403 preflight for disallowed origin', async () => {
    const { WidgetServer } = await import('../widget/server');
    const { OpenRouterAdapter } = await import('../extractor/openrouter');
    const server = new WidgetServer({
      llm: new OpenRouterAdapter({ apiKey: 'sk-test', fetch: async () => new Response('{}') }),
      allowedOrigins: ['https://oddjobtodd.info'],
    });
    const req = new Request('http://localhost/widget/chat/start', {
      method: 'OPTIONS',
      headers: { origin: 'https://evil.example.com' },
    });
    const res = await server.handle(req);
    expect(res.status).toBe(403);
  });

  it('adds CORS header to successful POST /start response', async () => {
    const { WidgetServer } = await import('../widget/server');
    const { OpenRouterAdapter } = await import('../extractor/openrouter');
    const server = new WidgetServer({
      llm: new OpenRouterAdapter({ apiKey: 'sk-test', fetch: async () => new Response('{}') }),
      allowedOrigins: ['https://oddjobtodd.info'],
    });
    const req = new Request('http://localhost/widget/chat/start', {
      method: 'POST',
      headers: { 'content-type': 'application/json', origin: 'https://oddjobtodd.info' },
    });
    const res = await server.handle(req);
    expect(res.status).toBe(200);
    expect(res.headers.get('access-control-allow-origin')).toBe('https://oddjobtodd.info');
  });
});

```
