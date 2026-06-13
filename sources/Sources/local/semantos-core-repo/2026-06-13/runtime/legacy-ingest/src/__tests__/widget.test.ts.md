---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/__tests__/widget.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.153240+00:00
---

# runtime/legacy-ingest/src/__tests__/widget.test.ts

```ts
import { describe, it, expect } from 'bun:test';
import { WidgetServer, WidgetTransport } from '../widget/server';
import { MemorySessionStore } from '../widget/session-store';
import type { LLMAdapter } from '../extractor/types';
import type { ConversationTurnEvent } from '../conversation/types';

// ── Test helpers ──────────────────────────────────────────────────────────────

function makeLLM(decisions: Array<{ reply: string; done: boolean; facts?: object }>): LLMAdapter {
  let call = 0;
  return {
    async extract() {
      const d = decisions[Math.min(call++, decisions.length - 1)];
      const payload = { reply: d.reply, done: d.done, facts: d.facts ?? {}, intent: 'quote_request', summary: 'test' };
      return { payload, confidence: 0.85, raw: JSON.stringify(payload) };
    },
  };
}

function makeServer(overrides: {
  decisions?: Array<{ reply: string; done: boolean; facts?: object }>;
  onConversationTurn?: (event: ConversationTurnEvent) => Promise<void> | void;
} = {}) {
  const sessions = new MemorySessionStore();
  const proposals: object[] = [];
  const llm = makeLLM(overrides.decisions ?? [
    { reply: "Hi! What's the job?", done: false },
    { reply: "Where is it?", done: false },
    { reply: "Thanks, we'll be in touch!", done: true, facts: { jobDescription: 'fix tap', jobLocation: 'Bondi' } },
  ]);
  const server = new WidgetServer({
    llm,
    sessions,
    onProposal: async (p) => { proposals.push(p); },
    onConversationTurn: overrides.onConversationTurn,
    pathPrefix: '/widget',
  });
  return { server, sessions, proposals };
}

async function post(server: WidgetServer, path: string, body?: object): Promise<Response> {
  const req = new Request(`http://localhost${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  return server.handle(req);
}

async function get(server: WidgetServer, path: string): Promise<Response> {
  const req = new Request(`http://localhost${path}`, { method: 'GET' });
  return server.handle(req);
}

// ── WidgetTransport tests ─────────────────────────────────────────────────────

describe('WidgetTransport', () => {
  it('captures reply and clears on takeReply', async () => {
    const t = new WidgetTransport();
    await t.send('client', 'Hello there!');
    expect(t.takeReply()).toBe('Hello there!');
    expect(t.takeReply()).toBeNull();
  });
});

// ── WidgetServer tests ────────────────────────────────────────────────────────

describe('WidgetServer - health', () => {
  it('GET /widget/chat/health returns ok', async () => {
    const { server } = makeServer();
    const res = await get(server, '/widget/chat/health');
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean };
    expect(body.ok).toBe(true);
  });

  it('returns 404 for unknown paths', async () => {
    const { server } = makeServer();
    const res = await get(server, '/widget/unknown');
    expect(res.status).toBe(404);
  });
});

describe('WidgetServer - /start', () => {
  it('creates a new session and returns a sessionId', async () => {
    const { server, sessions } = makeServer();
    const res = await post(server, '/widget/chat/start');
    expect(res.status).toBe(200);
    const body = await res.json() as { sessionId: string };
    expect(body.sessionId).toMatch(/^widget:/);
    const stored = await sessions.get(body.sessionId);
    expect(stored).not.toBeNull();
    expect(stored?.channel).toBe('widget');
  });
});

describe('WidgetServer - /turn', () => {
  it('processes a turn and returns the reply', async () => {
    const { server } = makeServer();
    const startRes = await post(server, '/widget/chat/start');
    const { sessionId } = await startRes.json() as { sessionId: string };

    const turnRes = await post(server, '/widget/chat/turn', {
      sessionId,
      message: 'I need a fence fixed',
    });
    expect(turnRes.status).toBe(200);
    const body = await turnRes.json() as { reply: string; completed: boolean };
    expect(body.reply).toBe("Hi! What's the job?");
    expect(body.completed).toBe(false);
  });

  it('returns completed: true when engine finishes', async () => {
    const { server } = makeServer({
      decisions: [
        { reply: "Thanks, we'll be in touch!", done: true, facts: { jobDescription: 'paint shed' } },
      ],
    });
    const startRes = await post(server, '/widget/chat/start');
    const { sessionId } = await startRes.json() as { sessionId: string };

    const turnRes = await post(server, '/widget/chat/turn', {
      sessionId,
      message: 'Can you paint my shed?',
    });
    const body = await turnRes.json() as { reply: string; completed: boolean };
    expect(body.completed).toBe(true);
  });

  it('returns 404 for unknown sessionId', async () => {
    const { server } = makeServer();
    const res = await post(server, '/widget/chat/turn', {
      sessionId: 'widget:does-not-exist',
      message: 'hello',
    });
    expect(res.status).toBe(404);
  });

  it('returns 400 for missing sessionId', async () => {
    const { server } = makeServer();
    const res = await post(server, '/widget/chat/turn', { message: 'hello' });
    expect(res.status).toBe(400);
  });

  it('returns 400 for missing message', async () => {
    const { server } = makeServer();
    const startRes = await post(server, '/widget/chat/start');
    const { sessionId } = await startRes.json() as { sessionId: string };
    const res = await post(server, '/widget/chat/turn', { sessionId });
    expect(res.status).toBe(400);
  });

  it('returns 410 for a completed session', async () => {
    const { server, sessions } = makeServer();
    const startRes = await post(server, '/widget/chat/start');
    const { sessionId } = await startRes.json() as { sessionId: string };
    const session = await sessions.get(sessionId);
    session!.state = 'complete';
    await sessions.set(session!);

    const res = await post(server, '/widget/chat/turn', { sessionId, message: 'hello' });
    expect(res.status).toBe(410);
  });

  it('multi-turn conversation accumulates session state', async () => {
    const { server, sessions } = makeServer({
      decisions: [
        { reply: "Where is it?", done: false, facts: { jobDescription: 'fix roof' } },
        { reply: "When do you need it?", done: false, facts: { jobLocation: 'Redfern' } },
        { reply: "Perfect, thanks!", done: true, facts: { desiredDate: 'ASAP' } },
      ],
    });
    const { sessionId } = await (await post(server, '/widget/chat/start')).json() as { sessionId: string };

    await post(server, '/widget/chat/turn', { sessionId, message: 'Fix my roof' });
    await post(server, '/widget/chat/turn', { sessionId, message: 'In Redfern' });
    await post(server, '/widget/chat/turn', { sessionId, message: 'As soon as possible' });

    const session = await sessions.get(sessionId);
    expect(session?.facts.jobDescription).toBe('fix roof');
    expect(session?.facts.jobLocation).toBe('Redfern');
    expect(session?.facts.desiredDate).toBe('ASAP');
    expect(session?.state).toBe('complete');
  });

  it('emits a conversation turn event for the customer and assistant turns', async () => {
    const events: ConversationTurnEvent[] = [];
    const { server } = makeServer({
      decisions: [
        { reply: "Where is it?", done: false, facts: { jobDescription: 'fix tap' } },
      ],
      onConversationTurn: (event) => {
        events.push(event);
      },
    });
    const { sessionId } = await (await post(server, '/widget/chat/start')).json() as { sessionId: string };

    await post(server, '/widget/chat/turn', { sessionId, message: 'Fix my tap' });

    expect(events.map((event) => event.role)).toEqual(['customer', 'assistant']);
    expect(events[0]?.providerId).toBe('widget');
    expect(events[0]?.sessionId).toBe(sessionId);
    expect(events[0]?.text).toBe('Fix my tap');
    expect(events[1]?.text).toBe('Where is it?');
  });
});

// ── /auth/callback OAuth landing page ────────────────────────────────────────

describe('WidgetServer - /auth/callback', () => {
  it('renders an HTML success page with the full bun resume command', async () => {
    const { server } = makeServer();
    const res = await get(server, '/auth/callback?state=xyz&code=abc');
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toMatch(/^text\/html/);
    const body = await res.text();
    // Full bun invocation — operators without a `legacy` shell alias can
    // copy-paste this verbatim. Bare `legacy resume <state> <code>` would
    // double the verb when pasted after `bun apps/legacy-cli/src/cli.ts`.
    expect(body).toContain('bun apps/legacy-cli/src/cli.ts resume xyz abc');
    expect(body).toContain('OAuth connection complete');
    // Alias hint mentions the short form for operators who add the alias.
    expect(body).toContain("alias legacy='bun apps/legacy-cli/src/cli.ts'");
  });

  it('sets Cache-Control: no-store on the success page', async () => {
    const { server } = makeServer();
    const res = await get(server, '/auth/callback?state=s1&code=c1');
    expect(res.headers.get('cache-control')).toBe('no-store');
  });

  it('renders an HTML error page when the provider returns ?error=', async () => {
    const { server } = makeServer();
    const res = await get(
      server,
      '/auth/callback?state=xyz&error=access_denied&error_description=User%20denied',
    );
    expect(res.status).toBe(200);
    expect(res.headers.get('content-type')).toMatch(/^text\/html/);
    const body = await res.text();
    expect(body).toContain('OAuth connection failed');
    expect(body).toContain('access_denied');
    expect(body).toContain('User denied');
    // Error page must NOT contain a resume command — there's nothing to resume.
    expect(body).not.toContain('resume xyz');
  });

  it('returns 400 when neither state/code nor error is supplied', async () => {
    const { server } = makeServer();
    const res = await get(server, '/auth/callback');
    expect(res.status).toBe(400);
    expect(res.headers.get('content-type')).toMatch(/^text\/html/);
    const body = await res.text();
    expect(body).toContain('bad request');
  });

  it('returns 400 when code is missing but state is present (no error)', async () => {
    const { server } = makeServer();
    const res = await get(server, '/auth/callback?state=onlystate');
    expect(res.status).toBe(400);
  });

  it('HTML-escapes state and code so XSS via OAuth params is impossible', async () => {
    const { server } = makeServer();
    const xss = '<script>alert(1)</script>';
    const res = await get(
      server,
      `/auth/callback?state=${encodeURIComponent(xss)}&code=${encodeURIComponent(xss)}`,
    );
    expect(res.status).toBe(200);
    const body = await res.text();
    // The literal <script> tag from user input MUST NOT appear unescaped
    // anywhere in the rendered HTML body for the user-controlled values.
    // The page does contain a legitimate inline <script> for the copy
    // button — assert the unescaped XSS payload is not present.
    expect(body).not.toContain('<script>alert(1)</script>');
    // The escaped form must appear (twice — once for state, once for code).
    expect(body).toContain('&lt;script&gt;alert(1)&lt;/script&gt;');
  });

  it('HTML-escapes error and error_description on the error page', async () => {
    const { server } = makeServer();
    const xss = '<img src=x onerror=alert(1)>';
    const res = await get(
      server,
      `/auth/callback?error=${encodeURIComponent(xss)}&error_description=${encodeURIComponent(xss)}`,
    );
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).not.toContain('<img src=x onerror=alert(1)>');
    expect(body).toContain('&lt;img src=x onerror=alert(1)&gt;');
  });

  it('renders no third-party network resources', async () => {
    const { server } = makeServer();
    const res = await get(server, '/auth/callback?state=ok&code=ok');
    const body = await res.text();
    // No external CSS, scripts, fonts, images, iframes, or analytics.
    expect(body).not.toMatch(/<link[^>]+href=["']https?:/i);
    expect(body).not.toMatch(/<script[^>]+src=["']https?:/i);
    expect(body).not.toMatch(/<img[^>]+src=["']https?:/i);
    expect(body).not.toMatch(/<iframe/i);
    expect(body).not.toMatch(/@import\s+url\(/i);
  });

  it('rejects POST to /auth/callback (only GET is allowed)', async () => {
    const { server } = makeServer();
    const req = new Request('http://localhost/auth/callback?state=x&code=y', {
      method: 'POST',
    });
    const res = await server.handle(req);
    expect(res.status).toBe(404);
  });
});

describe('MemorySessionStore', () => {
  it('stores and retrieves sessions', async () => {
    const store = new MemorySessionStore();
    const session = {
      sessionId: 'widget:abc',
      channel: 'widget' as const,
      recipientId: 'widget:abc',
      turns: [],
      facts: {},
      state: 'gathering' as const,
      createdAt: 0,
      updatedAt: 0,
    };
    await store.set(session);
    expect(await store.get('widget:abc')).toBe(session);
    expect(store.size).toBe(1);
    await store.delete('widget:abc');
    expect(await store.get('widget:abc')).toBeNull();
    expect(store.size).toBe(0);
  });
});

```
