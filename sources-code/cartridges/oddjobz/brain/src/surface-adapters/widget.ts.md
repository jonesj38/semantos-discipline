---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/surface-adapters/widget.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.509397+00:00
---

# cartridges/oddjobz/brain/src/surface-adapters/widget.ts

```ts
/**
 * D-OJ-conv-widget-intake — widget surface adapter.
 *
 * Implements `ConversationSurfaceAdapter` for `surface='widget'` — the
 * Oddjobz chat-widget WebSocket intake path.
 *
 * ## Relationship to the live intake path
 *
 * The existing `intake-handler.ts` → `recordIntakeTurn` → `buildCanonicalTurns`
 * path is the LIVE widget intake path and MUST NOT BREAK. This adapter
 * FORMALISES that path behind the §6.1 abstract interface WITHOUT forking it:
 *
 *  - `ingest` reuses `buildCanonicalTurns` (the exact same function the live
 *    path uses) to produce the canonical turn pair from a WS payload.
 *  - `send` posts an outbound turn back over the WS session.
 *  - The adapter does NOT duplicate the canonical-shape construction logic
 *    from `conversation-turn-patch.ts`.
 *
 * The live entry point (`intake-handler.ts` `main()`) continues to call
 * `recordIntakeTurn` directly — it is not gated behind this adapter. The
 * adapter wraps/shares the same logic for consumers that need the formal
 * interface (e.g. tests that assert the interface contract, future router
 * code that dispatches between surfaces).
 *
 * ## Identity binding (§6.2)
 *
 * Widget intake: `external` by phone (pre-cert'd customer flow). The inbound
 * participant role is 'external' (the customer is anonymous at widget time;
 * no Plexus cert). Identity binding uses `bindParticipantIdentity` with the
 * phone from the WS payload when present, or falls back to a cookie/session
 * marker (L0 if no phone).
 *
 * ## §6.3 lead-on-contact policy
 *
 * If `ctx.resolveEntity` returns null (no existing job/site/customer for the
 * caller's phone), the adapter sets `entityRef` to absent (does NOT fabricate
 * an entity cell hash). The SD2 lead-on-contact job creation is delegated to
 * the DETACHED GRANDCHILD SUBMITTER (intake-handler.ts `runDetachedSubmit`) —
 * the same out-of-band path used today. This keeps the adapter from needing
 * a Postgres or REPL write for a case that already has a working path.
 *
 * The `entityRef` is set when `ctx.resolveEntity` returns a hit, allowing the
 * BELONGS_TO_ENTITY relation sink to fire downstream.
 *
 * ## submitTurn routing
 *
 * `ctx.submitTurn(turn)` MUST route via the detached-grandchild submitter
 * pattern (NOT a sync-call into the brain's HTTP/REPL). In the default
 * production wiring, the context is built at the brain-reactor boundary
 * and `submitTurn` writes directly to Postgres via `makeOddjobzSinks(db)`
 * (Postgres is external — no deadlock risk). See `semantos_brain_single_threaded_reactor`.
 *
 * ## send() implementation
 *
 * In the live widget path, the brain sends the reply over the same WebSocket
 * session that delivered the inbound message. The adapter's `send` method
 * accepts an injected `WsSender` function so the transport can be mocked in
 * tests. Production callers inject the brain's actual WS send function; tests
 * inject a mock.
 *
 * ## No LLM calls
 *
 * Per `semantos_no_ai_in_substrate`: this adapter is pure protocol↔canonical
 * mapping + persistence. The LLM-reply generation lives in
 * `reply-generator.ts` (at the edge), not here.
 */

import { randomUUID } from 'node:crypto';
import {
  buildCanonicalTurns,
  bindParticipantIdentity,
  type OddjobzConversationTurnPayload,
  type RecordIntakeTurnArgs,
} from '../conversation/conversation-turn-patch.js';
import type {
  ConversationSurfaceAdapter,
  AdapterContext,
} from './contract.js';

// ── Widget WS payload type ────────────────────────────────────────────────────

/**
 * The native payload shape from the Oddjobz chat-widget WebSocket.
 *
 * Mirrors the fields from `HandlerInput` (intake-handler.ts) plus the
 * identity fields added by D-OJ-conv-multiparty-identity and the surface
 * adapter interface:
 *
 *  - `message`    — the customer's text message (required).
 *  - `sessionId`  — the WS session / intake session id (required).
 *  - `phone`      — customer's E.164 phone (L1 identity; optional, may be
 *                   absent on first contact / anonymous session).
 *  - `email`      — customer's email (L1 identity; optional).
 *  - `cookie`     — browser session cookie / anonymous session marker
 *                   (L0 identity; optional — used when no phone/email yet).
 *  - `inReplyToTurnId` — explicit prior-turn quote reference (optional;
 *                        maps to the inbound turn's `quotedTurnId` per
 *                        D-ODDJOBZ-quote-affordance).
 *  - `correlationId`   — caller-supplied correlation id (optional; if
 *                        absent, the adapter generates one via `randomUUID`).
 *  - `reply`           — the AI/operator reply text (populated for outbound
 *                        turn construction; typically set by the caller
 *                        after LLM reply generation).
 *  - `model`           — LLM model id used for the reply (optional; used
 *                        for outbound turn bodyParts/intakeMeta).
 *  - `action`          — the decision-tree action (optional).
 *  - `assembledPrompt` — the exact assembled prompt (optional).
 */
export interface WidgetWsPayload {
  /** The customer's inbound message. */
  readonly message: string;
  /** WS session / intake session id. Canonical `conversationId`. */
  readonly sessionId: string;
  /** E.164 phone for L1 identity binding (optional). */
  readonly phone?: string;
  /** Email for L1 identity binding (optional). */
  readonly email?: string;
  /** Browser cookie for L0 anonymous identity binding (optional). */
  readonly cookie?: string;
  /** Explicit quote reference — prior turn id this message replies to. */
  readonly inReplyToTurnId?: string;
  /** Caller-supplied correlation id (generated if absent). */
  readonly correlationId?: string;
  /** The AI/operator reply text (used for outbound canonical turn). */
  readonly reply?: string;
  /** LLM model id used for the reply (optional). */
  readonly model?: string;
  /** Decision-tree action (optional; used in outbound bodyParts). */
  readonly action?: { readonly type: string; readonly [k: string]: unknown };
  /** Exact assembled prompt (optional). */
  readonly assembledPrompt?: string;
  /** Agent cert id when the reply was AI-produced (optional). */
  readonly agentCertId?: string;
}

// ── WS sender abstraction (injected; no concrete WS dep here) ─────────────────

/**
 * A function that posts an outbound turn back over the WS session.
 *
 * In production, this is the brain's actual WS send function (injected at
 * `makeWidgetAdapter` time). In tests, a mock is injected.
 *
 * Signature: async (sessionId, turn) → surfaceMessageId | undefined.
 * Throws when the send fails (adapter converts to `{ state: 'failed' }`).
 */
export type WidgetWsSender = (
  sessionId: string,
  turn: OddjobzConversationTurnPayload,
) => Promise<string | undefined>;

// ── WidgetAdapterDeps ─────────────────────────────────────────────────────────

/**
 * Deps injected at construction time via `makeWidgetAdapter`.
 */
export interface WidgetAdapterDeps {
  /**
   * Generate a unique id for turns / correlation ids.
   * Default: `randomUUID()`. Injected for deterministic tests.
   */
  readonly generateId?: () => string;

  /**
   * Current time in unix-millis.
   * Default: `Date.now()`. Injected for deterministic tests.
   */
  readonly now?: () => number;

  /**
   * WS sender for outbound turns. When absent, `send` always returns
   * `{ state: 'failed', error: 'no WS sender configured' }`.
   *
   * Production: inject the brain's WS send function.
   * Tests: inject a mock that records calls.
   */
  readonly wsSender?: WidgetWsSender;
}

// ── makeWidgetAdapter ─────────────────────────────────────────────────────────

/**
 * Create a `ConversationSurfaceAdapter` for `surface='widget'`.
 *
 * Usage:
 * ```ts
 * const adapter = makeWidgetAdapter({ wsSender: myBrainWsSend });
 * const turns = await adapter.ingest(wsPayload, ctx);
 * // then adapter.send(outboundTurn, ctx) to echo back
 * ```
 *
 * The adapter is STATELESS; a single instance can serve many sessions.
 */
export function makeWidgetAdapter(deps: WidgetAdapterDeps = {}): ConversationSurfaceAdapter {
  const generateId = deps.generateId ?? (() => randomUUID());
  const now = deps.now ?? (() => Date.now());
  const wsSender = deps.wsSender;

  return {
    surface: 'widget',

    // ── ingest ───────────────────────────────────────────────────────────────
    //
    // Maps a WS payload to canonical turn(s) and submits via ctx.submitTurn.
    //
    // Turn construction delegates to `buildCanonicalTurns` (the exact same
    // function the live intake-handler path uses) to avoid shape drift. The
    // adapter wraps the payload into `RecordIntakeTurnArgs` and passes it
    // through.
    //
    // §6.3 lead-on-contact: if `ctx.resolveEntity` finds no entity for the
    // caller's phone/email, `entityRef` stays absent. The SD2 lead-on-contact
    // job is created by the detached-grandchild submitter (runDetachedSubmit),
    // not here. This matches the live path's behaviour.
    //
    // Identity binding:
    //  - Inbound: 'external' by phone (L1) or email (L1) or cookie (L0).
    //    Uses `bindParticipantIdentity` from conversation-turn-patch.ts.
    //  - Outbound: 'ai' by default (widget replies are AI-generated);
    //    agentCertId from payload when set.
    async ingest(
      payload: unknown,
      ctx: AdapterContext,
    ): Promise<OddjobzConversationTurnPayload[]> {
      // Validate / coerce the payload shape.
      if (!payload || typeof payload !== 'object') {
        throw new Error('widget.ingest: payload must be an object');
      }
      const p = payload as Record<string, unknown>;
      const message = typeof p.message === 'string' ? p.message : '';
      if (!message) {
        throw new Error('widget.ingest: payload.message is required');
      }
      const sessionId = typeof p.sessionId === 'string' ? p.sessionId : generateId();
      const phone = typeof p.phone === 'string' ? p.phone : undefined;
      const email = typeof p.email === 'string' ? p.email : undefined;
      const cookie = typeof p.cookie === 'string' ? p.cookie : undefined;
      const inReplyToTurnId = typeof p.inReplyToTurnId === 'string' ? p.inReplyToTurnId : undefined;
      const correlationId = typeof p.correlationId === 'string' ? p.correlationId : generateId();
      const reply = typeof p.reply === 'string' ? p.reply : '';
      const model = typeof p.model === 'string' ? p.model : 'widget-adapter';
      const action = (p.action && typeof p.action === 'object')
        ? (p.action as { type: string; [k: string]: unknown })
        : { type: 'widget_message' };
      const assembledPrompt = typeof p.assembledPrompt === 'string'
        ? p.assembledPrompt
        : 'widget-surface-adapter';
      const agentCertId = typeof p.agentCertId === 'string' ? p.agentCertId : undefined;

      // §6.3 entity resolution.
      // Try to resolve the entity from the caller's contact identity.
      // Widget identity is phone > email > cookie. Use the first available.
      let entityRef: { kind: 'job' | 'site' | 'customer'; cellHash: string } | undefined;

      const identityForResolution = phone
        ? { kind: 'phone', value: phone }
        : email
          ? { kind: 'email', value: email }
          : cookie
            ? { kind: 'cookie', value: cookie }
            : null;

      if (identityForResolution) {
        const resolved = await ctx.resolveEntity(identityForResolution);
        if (resolved) {
          entityRef = { kind: resolved.kind, cellHash: resolved.cellHash };
        }
        // If null: §6.3 — entityRef absent; SD2 lead-on-contact handles the
        // job creation via the detached-grandchild submitter out-of-band.
        // The adapter does NOT fabricate an entity cell hash.
      }

      // Build the canonical turn pair using the shared builder.
      // This is the EXACT same construction the live intake-handler path uses;
      // extracting it here avoids any shape drift.
      const inboundTurnId = `turn-in-${generateId()}`;
      const outboundTurnId = `turn-out-${generateId()}`;
      const timestamp = now();

      // Compose args matching RecordIntakeTurnArgs so buildCanonicalTurns
      // receives the full context.
      const args: RecordIntakeTurnArgs = {
        objectId: sessionId,
        hatId: 'oddjobz-widget-adapter',
        message,
        reply,
        action,
        model,
        assembledPrompt,
        correlationId,
        surface: 'widget',
        inboundParticipantRole: 'external',
        outboundParticipantRole: 'ai',
        // Identity fields for inbound:
        ...(phone ? { inboundPhone: phone } : {}),
        ...(email ? { inboundEmail: email } : {}),
        ...(cookie ? { inboundCookie: cookie } : {}),
        // Identity fields for outbound (AI agent):
        ...(agentCertId ? { agentCertId } : {}),
        // Entity anchoring (set when resolveEntity hit):
        ...(entityRef ? { entityRef } : {}),
        // Quote affordance:
        ...(inReplyToTurnId ? { inReplyToTurnId } : {}),
      };

      const { inbound, outbound } = buildCanonicalTurns(
        args,
        correlationId,
        timestamp,
        inboundTurnId,
        outboundTurnId,
      );

      // Submit both turns via the standard intake path (ctx.submitTurn).
      // This routes through the detached-grandchild submitter or direct
      // Postgres write (the context wires the right impl) — never a
      // sync-call into the brain REPL.
      await ctx.submitTurn(inbound);
      await ctx.submitTurn(outbound);

      return [inbound, outbound];
    },

    // ── send ─────────────────────────────────────────────────────────────────
    //
    // Post an outbound canonical turn back over the WS session.
    //
    // Looks up the sessionId from the turn's `conversationId` (which the
    // widget path sets from `sessionId`). The `wsSender` dep does the actual
    // WS post; if it throws, `send` catches and returns `{ state: 'failed' }`.
    //
    // `send` MUST NOT throw (per the §6.1 contract).
    async send(
      turn: OddjobzConversationTurnPayload,
      _ctx: AdapterContext,
    ): Promise<{ state: 'delivered' | 'failed'; surfaceMessageId?: string; error?: string }> {
      if (!wsSender) {
        return {
          state: 'failed',
          error: 'widget.send: no WS sender configured',
        };
      }

      // For the widget surface, the sessionId IS the conversationId.
      const sessionId = turn.conversationId;

      try {
        const surfaceMessageId = await wsSender(sessionId, turn);
        return {
          state: 'delivered',
          ...(surfaceMessageId ? { surfaceMessageId } : {}),
        };
      } catch (err) {
        return {
          state: 'failed',
          error: err instanceof Error ? err.message : String(err),
        };
      }
    },
  };
}

```
