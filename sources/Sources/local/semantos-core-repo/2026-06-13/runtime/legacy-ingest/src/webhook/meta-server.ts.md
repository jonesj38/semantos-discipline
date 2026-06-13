---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/legacy-ingest/src/webhook/meta-server.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.137491+00:00
---

# runtime/legacy-ingest/src/webhook/meta-server.ts

```ts
/**
 * Meta webhook server — receives Messenger + Instagram DM events.
 *
 * Routes:
 *   GET  /meta/webhook  — Meta challenge verification (subscribe flow)
 *   POST /meta/webhook  — receive message events
 *
 * Routing logic per inbound message
 * ─────────────────────────────────
 * 1. If sender has an ACTIVE ConversationSession → continue via ConversationEngine.
 * 2. If no active session:
 *    a. Run MessageExtractor on the message.
 *    b. confidence >= extractionThreshold (default 0.85) → emit Proposal directly.
 *    c. confidence < threshold  → start a ConversationSession and let the engine
 *       ask clarifying questions (same as the widget flow).
 *
 * This means a fully-detailed first message ("fix leaking tap at 12 Smith St Bondi,
 * ASAP, call me on 0411 222 333") gets extracted immediately, while "hi" or "are
 * you available?" kicks off the conversation intake.
 *
 * The MetaTransport is constructed per-message (stateless) using the supplied
 * page access token so replies go back into the same thread.
 */

import type { LLMAdapter } from '../extractor/types';
import type { Proposal } from '../extractor/types';
import { MessageExtractor } from '../extractor/message';
import { ConversationEngine } from '../conversation/engine';
import type { ConversationSession, ConversationTurn, ConversationTurnSink } from '../conversation/types';
import { MetaProvider, MetaTransport } from '../providers/meta';
import type { MetaChannel } from '../providers/meta';
import type { SessionPersistence } from '../widget/session-store';
import { MemorySessionStore } from '../widget/session-store';
import { ConversationExtractor } from '../conversation/extractor';

export interface MetaWebhookServerOpts {
  provider: MetaProvider;
  /** Page access token (string or live provider). */
  pageAccessToken: string | (() => string | null);
  llm: LLMAdapter;
  sessions?: SessionPersistence;
  onProposal?: (proposal: Proposal) => Promise<void> | void;
  /**
   * Optional audit sink invoked for each customer/assistant turn. Hosts use
   * this to write oddjobz.message.v1 or intent conversation patches without
   * coupling the webhook transport to Oddjobz storage.
   */
  onConversationTurn?: ConversationTurnSink;
  /**
   * Confidence threshold above which a one-shot MessageExtraction is accepted
   * without starting a conversation. Default: 0.85.
   */
  extractionThreshold?: number;
  /** Max conversation turns before forcing completion. Default: 8. */
  maxTurns?: number;
  /** URL path prefix. Default: '/meta'. */
  pathPrefix?: string;
}

export class MetaWebhookServer {
  private readonly provider: MetaProvider;
  private readonly tokenProvider: () => string | null;
  private readonly llm: LLMAdapter;
  private readonly sessions: SessionPersistence;
  private readonly onProposal: ((p: Proposal) => Promise<void> | void) | null;
  private readonly onConversationTurn: ConversationTurnSink | null;
  private readonly extractionThreshold: number;
  private readonly maxTurns: number;
  private readonly pathPrefix: string;
  private readonly messageExtractor = new MessageExtractor();
  private readonly conversationExtractor = new ConversationExtractor();

  constructor(opts: MetaWebhookServerOpts) {
    this.provider = opts.provider;
    const t = opts.pageAccessToken;
    this.tokenProvider = typeof t === 'function' ? t : () => t;
    this.llm = opts.llm;
    this.sessions = opts.sessions ?? new MemorySessionStore();
    this.onProposal = opts.onProposal ?? null;
    this.onConversationTurn = opts.onConversationTurn ?? null;
    this.extractionThreshold = opts.extractionThreshold ?? 0.85;
    this.maxTurns = opts.maxTurns ?? 8;
    this.pathPrefix = opts.pathPrefix ?? '/meta';
  }

  async handle(req: Request): Promise<Response> {
    const url = new URL(req.url);
    const path = url.pathname;
    const prefix = this.pathPrefix;

    if (path === `${prefix}/webhook`) {
      if (req.method === 'GET') return this.handleChallenge(url);
      if (req.method === 'POST') return this.handleEvent(req);
    }

    return new Response('Not found', { status: 404 });
  }

  // ── GET — challenge verification ─────────────────────────────────────────

  private handleChallenge(url: URL): Response {
    const mode = url.searchParams.get('hub.mode') ?? '';
    const token = url.searchParams.get('hub.verify_token') ?? '';
    const challenge = url.searchParams.get('hub.challenge') ?? '';

    const result = this.provider.verifyChallenge({ mode, token, challenge });
    if (result === null) {
      return new Response('Forbidden', { status: 403 });
    }
    return new Response(result, { status: 200, headers: { 'content-type': 'text/plain' } });
  }

  // ── POST — receive events ────────────────────────────────────────────────

  private async handleEvent(req: Request): Promise<Response> {
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return new Response('Bad Request', { status: 400 });
    }

    const items = this.provider.parseWebhookPayload(body);

    // Process each message in parallel — they are independent per-sender events
    await Promise.all(items.map(item => this.routeMessage(item).catch(() => {
      // Individual message failures must not fail the 200 OK that Meta needs
    })));

    // Meta requires a fast 200 OK regardless of processing outcome
    return new Response('OK', { status: 200 });
  }

  // ── Routing ──────────────────────────────────────────────────────────────

  private async routeMessage(item: import('../types').RawItem): Promise<void> {
    const meta = parseMetaBytes(item.bytes);
    if (!meta) return;
    if (meta.isEchoOrAd) return; // ignore bot's own replies

    const channel = meta.channel as MetaChannel;
    const sessionId = `meta:${meta.threadId}`;

    // Check for an active conversation session
    const existing = await this.sessions.get(sessionId);
    if (existing && existing.state !== 'complete' && existing.state !== 'abandoned') {
      await this.continueConversation(existing, meta.text ?? '', channel);
      return;
    }

    // No active session — try one-shot extraction first. Tier 1.7 changed
    // ContentExtractor.extract to return an array (so the email extractor
    // can fan out across PDF bundles). MessageExtractor only ever produces
    // one outcome per inbound webhook message, so we read element 0.
    const outcomes = await this.messageExtractor.extract(item, this.llm);
    const outcome = outcomes[0];

    if (outcome.kind === 'extracted' && outcome.proposal.confidence >= this.extractionThreshold) {
      // High-confidence extraction — emit Proposal directly, no conversation needed
      await this.emitSingleTurn({
        sessionId,
        channel: channel === 'instagram' ? 'meta_instagram' : 'meta_messenger',
        recipientId: meta.senderId,
        role: 'customer',
        text: meta.text ?? '',
        timestamp: meta.timestamp ?? item.fetchedAt,
      });
      await this.onProposal?.(outcome.proposal);
      // Send a brief acknowledgement so the customer knows we received it
      const ack = await this.sendAck(meta.senderId, channel);
      if (ack) {
        await this.emitSingleTurn({
          sessionId,
          channel: channel === 'instagram' ? 'meta_instagram' : 'meta_messenger',
          recipientId: meta.senderId,
          role: 'assistant',
          text: ack,
          timestamp: Date.now(),
        });
      }
      return;
    }

    // Low confidence or non-business message — either start a conversation or ignore
    if (outcome.kind === 'pre-filtered') return; // echo, empty, etc.

    // Start a new ConversationSession and let the engine ask what it needs
    const session = makeSession(sessionId, channel, meta.senderId);
    await this.sessions.set(session);
    await this.continueConversation(session, meta.text ?? '', channel);
  }

  private async continueConversation(
    session: ConversationSession,
    text: string,
    channel: MetaChannel,
  ): Promise<void> {
    const transport = new MetaTransport({
      provider: this.provider,
      pageAccessToken: this.tokenProvider,
      channel,
    });

    const engine = new ConversationEngine({
      llm: this.llm,
      transport,
      maxTurns: this.maxTurns,
    });

    const turnStart = session.turns.length;
    const result = await engine.handleTurn(session, text);
    await this.sessions.set(session);
    await this.emitSessionTurns(session, session.turns.slice(turnStart));

    if (result.completed && result.extractedText) {
      await this.extractCompletedSession(session);
    }
  }

  private async extractCompletedSession(session: ConversationSession): Promise<void> {
    if (!this.onProposal) return;

    const rawItem = {
      providerId: 'meta',
      providerItemId: session.sessionId,
      fetchedAt: Date.now(),
      contentType: 'widget/chat',
      bytes: new TextEncoder().encode(JSON.stringify(session)),
      metadata: { channel: session.channel, sessionId: session.sessionId },
    };

    // Tier 1.7 — ContentExtractor.extract returns an array. Conversations
    // are 1:1 with a session, so the array always has length 1.
    const outcomes = await this.conversationExtractor.extract(rawItem, this.llm).catch(() => null);
    const outcome = outcomes?.[0];
    if (outcome?.kind === 'extracted') {
      await this.onProposal(outcome.proposal);
    }
  }

  private async sendAck(recipientId: string, _channel: MetaChannel): Promise<string | null> {
    const token = this.tokenProvider();
    if (!token) return null;
    const ack = "Thanks — we've got your message and will be in touch shortly!";
    const sent = await this.provider.sendMessage(token, recipientId, ack).then(
      () => true,
      () => false,
    );
    if (!sent) {
      // Ack failure is non-fatal — the proposal was already captured
      return null;
    }
    return ack;
  }

  private async emitSessionTurns(
    session: ConversationSession,
    turns: ConversationTurn[],
  ): Promise<void> {
    for (const turn of turns) {
      await this.emitSingleTurn({
        sessionId: session.sessionId,
        channel: session.channel,
        recipientId: session.recipientId,
        role: turn.role,
        text: turn.text,
        timestamp: turn.timestamp,
      });
    }
  }

  private async emitSingleTurn(event: {
    sessionId: string;
    channel: ConversationSession['channel'];
    recipientId: string;
    role: ConversationTurn['role'];
    text: string;
    timestamp: number;
  }): Promise<void> {
    if (!this.onConversationTurn) return;
    try {
      await this.onConversationTurn({
        providerId: 'meta',
        ...event,
      });
    } catch {
      // The sink should do its own durable retry. Do not make Meta retry the
      // whole webhook and duplicate the conversation.
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function parseMetaBytes(bytes: Uint8Array) {
  try {
    return JSON.parse(new TextDecoder().decode(bytes)) as {
      channel: string;
      senderId: string;
      threadId: string;
      text?: string;
      timestamp?: number;
      isEchoOrAd: boolean;
    };
  } catch {
    return null;
  }
}

function makeSession(
  sessionId: string,
  channel: MetaChannel,
  recipientId: string,
): ConversationSession {
  return {
    sessionId,
    channel: channel === 'instagram' ? 'meta_instagram' : 'meta_messenger',
    recipientId,
    turns: [],
    facts: {},
    state: 'greeting',
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };
}

```
