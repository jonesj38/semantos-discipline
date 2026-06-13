---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/widget/server.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.164830+00:00
---

# runtime/legacy-ingest/src/widget/server.ts

```ts
/**
 * Widget chat server — HTTP intake endpoint for oddjobtodd.info chat widget.
 *
 * Routes:
 *   POST /widget/chat/start  — create a new session, returns { sessionId }
 *   POST /widget/chat/turn   — submit a customer message, returns { reply, completed }
 *   GET  /widget/chat/health — liveness probe
 *   GET  /auth/callback      — OAuth redirect landing page (renders the
 *                              `legacy resume <state> <code>` command for
 *                              the operator to paste into the REPL). Lives
 *                              outside the widget pathPrefix because it has
 *                              to match the URI registered with the OAuth
 *                              provider (Google/Meta/etc.) verbatim.
 *
 * The same ConversationEngine runs here as for Meta DM; the only difference is
 * the transport. The widget uses a synchronous HTTP response — the engine's
 * reply is captured via WidgetTransport and returned in the POST response body.
 *
 * On session completion the server serialises the session as a `widget/chat`
 * RawItem and runs ConversationExtractor to produce a Proposal for the
 * ratification queue. Callers supply an `onProposal` callback (or a
 * ProposalStore) to persist it.
 */

import type {
  ConversationSession,
  ConversationTransport,
  ConversationTurn,
  ConversationTurnSink,
} from '../conversation/types';
import type { LLMAdapter } from '../extractor/types';
import type { Proposal } from '../extractor/types';
import { ConversationEngine } from '../conversation/engine';
import { ConversationExtractor } from '../conversation/extractor';
import type { SessionPersistence } from './session-store';
import { MemorySessionStore } from './session-store';

// ── WidgetTransport ───────────────────────────────────────────────────────────

/**
 * Synchronous transport for the widget HTTP server.
 * `send()` stores the reply for immediate return in the HTTP response —
 * no WebSocket or SSE push needed for the basic flow.
 */
export class WidgetTransport implements ConversationTransport {
  private _lastReply: string | null = null;

  async send(_recipientId: string, text: string): Promise<void> {
    this._lastReply = text;
  }

  /** Consume and clear the last reply. */
  takeReply(): string | null {
    const r = this._lastReply;
    this._lastReply = null;
    return r;
  }
}

// ── Request/response shapes ───────────────────────────────────────────────────

export interface StartResponse {
  sessionId: string;
}

export interface TurnRequest {
  sessionId: string;
  message: string;
}

export interface TurnResponse {
  reply: string;
  completed: boolean;
  sessionId: string;
}

// ── Widget server handler ─────────────────────────────────────────────────────

export interface WidgetServerOpts {
  llm: LLMAdapter;
  sessions?: SessionPersistence;
  onProposal?: (proposal: Proposal) => Promise<void> | void;
  /**
   * Optional audit sink invoked for each customer/assistant turn. Hosts use
   * this to write oddjobz.message.v1 or intent conversation patches.
   */
  onConversationTurn?: ConversationTurnSink;
  /** Max turns before forcing completion. Default: 8. */
  maxTurns?: number;
  /** Path prefix. Default: '/widget'. */
  pathPrefix?: string;
  /**
   * Allowed CORS origins. Supply your widget host(s) so browser-side JS can
   * POST from oddjobtodd.info (or any other domain). Requests whose Origin
   * is not listed receive a 403. Pass `['*']` to allow all origins (not
   * recommended for production).
   */
  allowedOrigins?: string[];
}

/**
 * Framework-agnostic request handler. Accepts a standard `Request` and
 * returns a `Response` — compatible with Bun.serve(), Hono, and any
 * fetch-compatible router.
 */
export class WidgetServer {
  private readonly llm: LLMAdapter;
  private readonly sessions: SessionPersistence;
  private readonly onProposal: ((p: Proposal) => Promise<void> | void) | null;
  private readonly onConversationTurn: ConversationTurnSink | null;
  private readonly maxTurns: number;
  private readonly pathPrefix: string;
  private readonly allowedOrigins: Set<string> | '*';
  private readonly extractor = new ConversationExtractor();

  constructor(opts: WidgetServerOpts) {
    this.llm = opts.llm;
    this.sessions = opts.sessions ?? new MemorySessionStore();
    this.onProposal = opts.onProposal ?? null;
    this.onConversationTurn = opts.onConversationTurn ?? null;
    this.maxTurns = opts.maxTurns ?? 8;
    this.pathPrefix = opts.pathPrefix ?? '/widget';
    const ao = opts.allowedOrigins;
    this.allowedOrigins = ao
      ? ao.includes('*') ? '*' : new Set(ao)
      : new Set<string>(); // no CORS by default (same-origin only)
  }

  async handle(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const path = url.pathname;
    const prefix = this.pathPrefix;
    const origin = req.headers.get('origin') ?? '';

    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
      return this.corsPreflightResponse(origin);
    }

    if (path === `${prefix}/chat/health` && req.method === 'GET') {
      return this.addCors(json({ ok: true }), origin);
    }

    if (path === `${prefix}/chat/start` && req.method === 'POST') {
      if (!this.originAllowed(origin)) return new Response('Forbidden', { status: 403 });
      return this.addCors(this.handleStart(), origin);
    }

    if (path === `${prefix}/chat/turn` && req.method === 'POST') {
      if (!this.originAllowed(origin)) return new Response('Forbidden', { status: 403 });
      return this.addCors(await this.handleTurn(req), origin);
    }

    // OAuth callback landing page. Lives at a fixed path (not under
    // pathPrefix) because the URI must match what's registered with the
    // OAuth provider verbatim. CORS doesn't apply — this is a top-level
    // GET navigation from the provider's redirect, not an XHR.
    if (path === '/auth/callback' && req.method === 'GET') {
      return this.handleAuthCallback(url);
    }

    return new Response('Not found', { status: 404 });
  }

  private originAllowed(origin: string): boolean {
    if (this.allowedOrigins === '*') return true;
    if (this.allowedOrigins.size === 0) return true; // same-origin: no Origin header = allowed
    return origin === '' || this.allowedOrigins.has(origin);
  }

  private corsPreflightResponse(origin: string): Response {
    if (!this.originAllowed(origin)) return new Response('Forbidden', { status: 403 });
    const headers = new Headers({
      'access-control-allow-origin': this.allowedOrigins === '*' ? '*' : origin,
      'access-control-allow-methods': 'POST, GET, OPTIONS',
      'access-control-allow-headers': 'content-type',
      'access-control-max-age': '86400',
    });
    return new Response(null, { status: 204, headers });
  }

  private addCors(res: Response, origin: string): Response {
    if (this.allowedOrigins === '*' || (this.allowedOrigins as Set<string>).has(origin)) {
      const h = new Headers(res.headers);
      h.set('access-control-allow-origin', this.allowedOrigins === '*' ? '*' : origin);
      return new Response(res.body, { status: res.status, headers: h });
    }
    return res;
  }

  // ── Handlers ─────────────────────────────────────────────────────────────

  private handleStart(): Response {
    const sessionId = `widget:${cryptoRandomId()}`;
    const session: ConversationSession = {
      sessionId,
      channel: 'widget',
      recipientId: sessionId,
      turns: [],
      facts: {},
      state: 'greeting',
      createdAt: Date.now(),
      updatedAt: Date.now(),
    };
    // Fire-and-forget persist — session is not needed until the first turn
    void this.sessions.set(session);
    return json<StartResponse>({ sessionId });
  }

  private async handleTurn(req: Request): Promise<Response> {
    let body: TurnRequest;
    try {
      body = await req.json() as TurnRequest;
    } catch {
      return error('invalid JSON body', 400);
    }

    if (!body.sessionId || typeof body.sessionId !== 'string') {
      return error('sessionId is required', 400);
    }
    if (!body.message || typeof body.message !== 'string') {
      return error('message is required', 400);
    }

    const session = await this.sessions.get(body.sessionId);
    if (!session) {
      return error('session not found — call /start first', 404);
    }

    if (session.state === 'complete' || session.state === 'abandoned') {
      return error('session is already closed', 410);
    }

    const transport = new WidgetTransport();
    const engine = new ConversationEngine({ llm: this.llm, transport, maxTurns: this.maxTurns });

    const turnStart = session.turns.length;
    const result = await engine.handleTurn(session, body.message);
    await this.sessions.set(session);
    await this.emitSessionTurns(session, session.turns.slice(turnStart));

    if (result.completed && result.extractedText) {
      void this.extractAndNotify(session, result.extractedText);
    }

    const reply = result.replySent ?? transport.takeReply() ?? "Thanks, we'll be in touch!";
    return json<TurnResponse>({
      reply,
      completed: result.completed,
      sessionId: body.sessionId,
    });
  }

  /**
   * OAuth callback landing page. Renders the `legacy resume <state> <code>`
   * command for the operator to paste into their REPL. Does NOT perform
   * the token exchange — that's `legacy resume`'s job. This handler is
   * purely a presentation layer for the auth code that the provider just
   * delivered via redirect.
   *
   * Security:
   *   - All query params are HTML-escaped before being rendered (XSS via
   *     OAuth state is a real attack surface — Google won't filter it).
   *   - Cache-Control: no-store prevents the auth code from being cached
   *     by the operator's browser or any intermediary.
   *   - No external resources, no analytics, no fetch/XHR. The only
   *     scripted behaviour is an inline clipboard-copy button.
   */
  private handleAuthCallback(url: URL): Response {
    const state = url.searchParams.get('state');
    const code = url.searchParams.get('code');
    const errorCode = url.searchParams.get('error');
    const errorDescription = url.searchParams.get('error_description');

    // Malformed: nothing useful in the query string. Bail with 400.
    if (!state && !code && !errorCode) {
      return htmlResponse(renderMalformedCallbackPage(), 400);
    }

    // Provider reported an error (e.g. user denied consent).
    if (errorCode) {
      return htmlResponse(renderErrorCallbackPage(errorCode, errorDescription));
    }

    // Happy path requires both state and code.
    if (!state || !code) {
      return htmlResponse(renderMalformedCallbackPage(), 400);
    }

    return htmlResponse(renderSuccessCallbackPage(state, code));
  }

  private async extractAndNotify(
    session: ConversationSession,
    _extractedText: string,
  ): Promise<void> {
    if (!this.onProposal) return;

    const rawItem = {
      providerId: 'widget',
      providerItemId: session.sessionId,
      fetchedAt: Date.now(),
      contentType: 'widget/chat',
      bytes: new TextEncoder().encode(JSON.stringify(session)),
      metadata: { channel: session.channel, sessionId: session.sessionId },
    };

    // Tier 1.7 — ContentExtractor.extract returns an array. Conversations
    // are 1:1 with a session, so the array always has length 1.
    const outcomes = await this.extractor.extract(rawItem, this.llm).catch(() => null);
    const outcome = outcomes?.[0];
    if (outcome?.kind === 'extracted') {
      await this.onProposal(outcome.proposal);
    }
  }

  private async emitSessionTurns(
    session: ConversationSession,
    turns: ConversationTurn[],
  ): Promise<void> {
    if (!this.onConversationTurn) return;
    for (const turn of turns) {
      try {
        await this.onConversationTurn({
          providerId: 'widget',
          sessionId: session.sessionId,
          channel: session.channel,
          recipientId: session.recipientId,
          role: turn.role,
          text: turn.text,
          timestamp: turn.timestamp,
        });
      } catch {
        // The sink should do its own durable retry. A logging failure should
        // not break the customer-facing chat response.
      }
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function json<T>(body: T, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

function error(message: string, status: number): Response {
  return json({ error: message }, status);
}

function cryptoRandomId(): string {
  const bytes = new Uint8Array(16);
  globalThis.crypto.getRandomValues(bytes);
  return [...bytes].map(b => b.toString(16).padStart(2, '0')).join('');
}

// ── OAuth callback page rendering ─────────────────────────────────────────────
//
// All renderers below MUST escape user-controlled values (state, code,
// error, error_description) before interpolation. Provider-side OAuth
// errors are not sanitised by Google — any HTML-special character that
// reaches this page is an XSS vector.

function htmlResponse(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      // The auth code is single-use but still sensitive in flight.
      // no-store keeps it out of the browser cache and any intermediary.
      'cache-control': 'no-store',
      'referrer-policy': 'no-referrer',
      'x-content-type-options': 'nosniff',
    },
  });
}

function escapeHtml(input: string): string {
  return input
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function renderSuccessCallbackPage(state: string, code: string): string {
  const safeState = escapeHtml(state);
  const safeCode = escapeHtml(code);
  // The command rendered for the operator. Both fragments are escaped above.
  // We render the FULL bun invocation (not the bare `legacy resume <state>
  // <code>` short form) because most operators don't have a `legacy` shell
  // alias — copying a `legacy resume …` literal into a terminal that's been
  // typing `bun apps/legacy-cli/src/cli.ts <verb>` doubles the verb and
  // mis-parses. The operator alias hint below tells operators how to opt
  // into the shorter form for future runs.
  const command = `bun apps/legacy-cli/src/cli.ts resume ${safeState} ${safeCode}`;
  return baseHtmlShell('OAuth connection complete', `
    <h1>OAuth connection complete</h1>
    <p>Paste the command below into a terminal in the repo root to finish wiring the grant. The token exchange happens locally on your machine — no third party sees your auth code.</p>
    <div class="cmd-row">
      <pre id="resume-cmd"><code>${command}</code></pre>
      <button type="button" id="copy-btn" aria-label="Copy command to clipboard">Copy</button>
    </div>
    <p class="note">You can close this tab once the command is in your terminal.</p>
    <p class="note">Tip: <code>alias legacy='bun apps/legacy-cli/src/cli.ts'</code> in your shell rc lets you use the shorter <code>legacy resume &lt;state&gt; &lt;code&gt;</code> form for future grants.</p>
    <script>
      (function () {
        var btn = document.getElementById('copy-btn');
        var pre = document.getElementById('resume-cmd');
        if (!btn || !pre) return;
        btn.addEventListener('click', function () {
          var text = pre.innerText;
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(function () {
              btn.textContent = 'Copied';
              setTimeout(function () { btn.textContent = 'Copy'; }, 1500);
            }).catch(function () {
              btn.textContent = 'Copy failed';
            });
          } else {
            btn.textContent = 'Clipboard unavailable';
          }
        });
      })();
    </script>
  `);
}

function renderErrorCallbackPage(errorCode: string, errorDescription: string | null): string {
  const safeErr = escapeHtml(errorCode);
  const safeDesc = errorDescription ? escapeHtml(errorDescription) : '';
  const descBlock = safeDesc
    ? `<p class="err-desc">${safeDesc}</p>`
    : '';
  return baseHtmlShell('OAuth connection failed', `
    <h1>OAuth connection failed</h1>
    <p>The OAuth provider returned an error. No grant was created.</p>
    <pre class="err-code"><code>${safeErr}</code></pre>
    ${descBlock}
    <p class="note">Run <code>bun apps/legacy-cli/src/cli.ts connect &lt;provider&gt;</code> again in your terminal to retry. If the error persists, check that the OAuth client config (client id, redirect URI) matches what's registered with the provider.</p>
  `);
}

function renderMalformedCallbackPage(): string {
  return baseHtmlShell('OAuth callback — bad request', `
    <h1>OAuth callback — bad request</h1>
    <p>This URL was opened without an OAuth <code>state</code>+<code>code</code> pair (and without an <code>error</code>). Either the redirect from the OAuth provider was incomplete, or this page was opened directly.</p>
    <p class="note">Start the flow with <code>bun apps/legacy-cli/src/cli.ts connect &lt;provider&gt;</code> in your terminal.</p>
  `);
}

function baseHtmlShell(title: string, bodyInner: string): string {
  // No external CSS, no external fonts, no analytics. All styles inline.
  // The page must work fully offline once delivered.
  const safeTitle = escapeHtml(title);
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>${safeTitle}</title>
<style>
  :root { color-scheme: light dark; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; max-width: 720px; margin: 2rem auto; padding: 0 1.25rem; line-height: 1.55; }
  h1 { font-size: 1.6rem; margin-bottom: 0.75rem; }
  p { margin: 0.75rem 0; }
  code { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 0.95rem; }
  pre { background: rgba(127,127,127,0.12); padding: 1rem; border-radius: 6px; overflow-x: auto; font-size: 1.05rem; margin: 0; flex: 1; user-select: all; }
  pre code { font-size: 1.05rem; }
  .cmd-row { display: flex; gap: 0.5rem; align-items: stretch; margin: 1rem 0; }
  button { padding: 0 1rem; font-size: 0.95rem; border: 1px solid currentColor; background: transparent; color: inherit; border-radius: 6px; cursor: pointer; }
  button:hover { background: rgba(127,127,127,0.1); }
  .note { font-size: 0.9rem; opacity: 0.75; }
  .err-code { color: #b00; }
  .err-desc { font-size: 0.95rem; }
</style>
</head>
<body>
${bodyInner}
</body>
</html>
`;
}

```
