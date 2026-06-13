---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/legacy-ingest-bridge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.518393+00:00
---

# cartridges/oddjobz/brain/src/conversation/legacy-ingest-bridge.ts

```ts
/**
 * D-OJ-conv-legacy-ingest-bridge — keystone unification (2026-05-22).
 *
 * Bridges the OLD parallel conversation engine in `runtime/legacy-ingest/`
 * onto the NEW canonical conversation spine so the surface-intake
 * deliverables (email/meta/sms) stop being three forks.
 *
 * ## What this module does
 *
 * 1. `mapConversationTurnEventToCanonical(event)` — pure mapper from the
 *    legacy `ConversationTurnEvent` shape to `OddjobzConversationTurnPayload`.
 *
 * 2. `makeCanonicalTurnSink(db, opts?)` — returns a `ConversationTurnSink`
 *    (injectable into legacy-ingest's webhook/widget servers) that maps
 *    each event and persists the canonical turn via `makeOddjobzSinks(db)`.
 *    Best-effort + isolated: sink failure does NOT break legacy intake.
 *
 * ## THE SEAM
 *
 * `runtime/legacy-ingest/src/conversation/types.ts` defines:
 *   `ConversationTurnSink = (event: ConversationTurnEvent) => Promise<void>|void`
 *
 * This is the injection point. The legacy servers (`meta-server.ts`,
 * `widget/server.ts`) already accept an optional `onConversationTurn` sink.
 * The canonical sink produced here CAN BE INJECTED alongside the existing
 * `JsonlConversationTurnPatchSink` (dual-sink, additive — legacy path is
 * kept intact). The rip-out / cutover of the legacy conversation model is
 * a FOLLOW-UP deliverable.
 *
 * ## Mapping table
 *
 * | legacy field          | canonical field            | notes                                   |
 * |-----------------------|----------------------------|-----------------------------------------|
 * | channel='meta_messenger'/'meta_instagram' | surface='meta-inbox' | both Meta channels → single surface |
 * | channel='widget'      | surface='widget'           |                                         |
 * | role='customer'       | participantRole='external', direction='inbound' | un-cert'd customer |
 * | role='assistant'      | participantRole='ai', direction='outbound'      | AI turn      |
 * | sessionId             | conversationId             | direct mapping                          |
 * | recipientId (customer turn) | identityHandle (kind determined by channel) | meta→'fb'/'ig', widget→'cookie' |
 * | recipientId (assistant turn) | actorCertId=AI_CERT_PENDING_SENTINEL | per XOR invariant |
 * | text                  | bodyText                   | direct mapping                          |
 * | timestamp             | timestamp                  | direct mapping (unix ms)                |
 * | —                     | turnId                     | deterministic from event fields         |
 * | —                     | correlationId              | deterministic from sessionId+timestamp  |
 *
 * ## Identity handle kind for meta recipientId
 *
 * The legacy `recipientId` on a Meta customer turn is the sender's PSID
 * (Page-Scoped ID) — a Facebook/Instagram platform identity. It maps to:
 *   - `channel='meta_messenger'` → `identityHandle = { kind: 'fb', value: recipientId }`
 *   - `channel='meta_instagram'` → `identityHandle = { kind: 'ig', value: recipientId }`
 *
 * These are the `IdentityHandleKind` values defined in `conversation-turn-patch.ts`
 * as L1-equivalent social handles (`'ig'|'fb'` — "L1-equiv — Instagram/Facebook
 * handle (Meta inbox)"). The `D-OJ-conv-identity-merge` deliverable will merge
 * these handles when a phone/email is later provided.
 *
 * For widget customer turns `recipientId` is the session id (e.g. `widget:<uuid>`).
 * Since a raw session id is not a typed identity handle, we fall back to a
 * `cookie` kind (L0 anonymous session marker) — the same as the widget adapter
 * uses for anonymous widget sessions with no phone/email yet.
 *
 * ## No self-call deadlock
 *
 * `makeOddjobzSinks(db)` writes directly to Postgres (external). It does NOT
 * call back into the brain's HTTP/REPL. Per project memory
 * `semantos_brain_single_threaded_reactor`, the caller must supply a `db`
 * obtained at the brain-reactor boundary (NOT from the spawned intake child).
 * This matches the existing `db.ts` sink discipline.
 *
 * ## Additive / dual-sink discipline
 *
 * The legacy `JsonlConversationTurnPatchSink` (writing `oddjobz.message.v1`
 * JSONL) is NOT removed here. Both sinks fire side-by-side — identical to
 * the foundation PR's dual-sink pattern (D-ODDJOBZ-turns-as-sem-objects).
 * The legacy JSONL is kept as the V1 audit log until a future cutover PR
 * (tracked below).
 *
 * ## Follow-up scope: rip-out / cutover
 *
 * The legacy conversation model in `runtime/legacy-ingest/src/conversation/`
 * (ConversationEngine, turn-patch-store, graph-resolver, dispatch-router,
 * dispatch-decision-store) is NOT removed here — only the CONVERSATION MODEL
 * is being retired (the canonical spine replaces it). The transport
 * infrastructure (gmail, meta, widget HTTP, OAuth) is KEPT. The rip-out of
 * the conversation model is a separate deliverable once:
 *   1. This bridge is verified live and the canonical sem_objects rows are
 *      confirmed to be landing correctly.
 *   2. All downstream consumers (attention projector, ratification queue) are
 *      confirmed to read from `sem_objects` rather than the JSONL.
 *
 * ## Wire-in status
 *
 * `meta-server.ts` and `widget/server.ts` both accept `onConversationTurn`
 * optionally. The bridge sink CAN be injected there at the brain composition
 * root by adding:
 *
 * ```ts
 * const db = getDatabaseOrNull();
 * const canonicalSink = db ? makeCanonicalTurnSink(db) : undefined;
 * new MetaWebhookServer({ ..., onConversationTurn: canonicalSink });
 * new WidgetServer({ ..., onConversationTurn: canonicalSink });
 * ```
 *
 * The live legacy sink (`JsonlConversationTurnPatchSink`) fires via the
 * `onConversationTurn` slot too — so the injection needs to compose them:
 *
 * ```ts
 * const legacySink = new JsonlConversationTurnPatchSink({ ... });
 * const composedSink: ConversationTurnSink = async (event) => {
 *   legacySink.append(event);               // legacy JSONL
 *   await canonicalSink?.(event);           // canonical sem_objects (best-effort)
 * };
 * ```
 *
 * Wiring the above at the brain composition root (`runtime/brain/src/` or
 * wherever the `WidgetServer`/`MetaWebhookServer` are constructed) is the
 * cutover follow-up. This bridge module provides all the pieces; the caller
 * does the final composition.
 *
 * Pure, injectable. No LLM calls. Per `semantos_no_ai_in_substrate`.
 */

import { randomUUID, createHash } from 'node:crypto';
import type { ConversationTurnEvent, ConversationTurnSink, OddjobzMessagePatch } from '@semantos/legacy-ingest';
import type { Database } from '@semantos/semantic-objects';
import {
  bindParticipantIdentity,
  AI_CERT_PENDING_SENTINEL,
  type OddjobzConversationTurnPayload,
  type ConversationSurface,
  type IdentityHandle,
} from './conversation-turn-patch.js';
import { makeOddjobzSinks } from './db.js';

// ── Surface mapping ────────────────────────────────────────────────────────────

/**
 * Map a legacy ConversationChannel to the canonical ConversationSurface.
 *
 * Both Meta channels (meta_messenger + meta_instagram) collapse to
 * 'meta-inbox'. Widget → 'widget'.
 */
function mapSurface(
  channel: ConversationTurnEvent['channel'],
): ConversationSurface {
  switch (channel) {
    case 'meta_messenger':
    case 'meta_instagram':
      return 'meta-inbox';
    case 'widget':
      return 'widget';
    default:
      return 'widget'; // safe fallback — log at the sink layer
  }
}

// ── Identity handle mapping ────────────────────────────────────────────────────

/**
 * Map a Meta PSID / widget session recipientId to an IdentityHandle for
 * the inbound (customer) turn. Meta PSIDs are platform-scoped handles:
 *   - meta_messenger → kind='fb'  (Facebook Page-Scoped ID)
 *   - meta_instagram → kind='ig'  (Instagram account id)
 *   - widget         → kind='cookie' (anonymous session marker; L0)
 *
 * 'fb' and 'ig' are IdentityHandleKind values from conversation-turn-patch.ts
 * defined as "L1-equiv — Facebook/Instagram handle (Meta inbox)".
 */
function mapInboundIdentityHandle(
  event: ConversationTurnEvent,
): IdentityHandle {
  switch (event.channel) {
    case 'meta_messenger':
      return { kind: 'fb', value: event.recipientId };
    case 'meta_instagram':
      return { kind: 'ig', value: event.recipientId };
    case 'widget':
      // widget recipientId is the session id — treat as L0 cookie marker
      return { kind: 'cookie', value: event.recipientId };
    default:
      return { kind: 'free', value: event.recipientId };
  }
}

// ── Deterministic id derivation ────────────────────────────────────────────────

/**
 * Derive a stable turn id from the event fields (same fnv-1a-64 approach
 * used in `stablePatchId` in turn-patch-store.ts, but namespaced to 'turn').
 */
function stableTurnId(parts: unknown[]): string {
  const input = JSON.stringify(parts);
  const bytes = new TextEncoder().encode(input);
  let hash = 0xcbf29ce484222325n;
  for (const byte of bytes) {
    hash ^= BigInt(byte);
    hash = BigInt.asUintN(64, hash * 0x100000001b3n);
  }
  return `turn-${hash.toString(16).padStart(16, '0')}`;
}

function deriveTurnId(event: ConversationTurnEvent): string {
  return stableTurnId([
    'legacy-ingest-turn',
    event.providerId,
    event.sessionId,
    event.channel,
    event.recipientId,
    event.role,
    event.timestamp,
    event.text,
  ]);
}

function deriveCorrelationId(event: ConversationTurnEvent): string {
  return stableTurnId([
    'legacy-ingest-corr',
    event.sessionId,
    // Round to 5-second buckets so inbound+outbound turns from the same
    // interaction share a correlationId (they fire within the same tick).
    Math.floor(event.timestamp / 5000),
  ]);
}

// ── Pure mapper ────────────────────────────────────────────────────────────────

/**
 * Map a legacy `ConversationTurnEvent` to an `OddjobzConversationTurnPayload`.
 *
 * This is the authoritative mapping function for the D-OJ-conv-legacy-ingest-
 * bridge deliverable. See the module doc-comment for the full mapping table.
 *
 * Pure — no IO.
 */
export function mapConversationTurnEventToCanonical(
  event: ConversationTurnEvent,
  opts: {
    /** Override the deterministic id generator (for tests). */
    readonly generateId?: () => string;
  } = {},
): OddjobzConversationTurnPayload {
  const surface = mapSurface(event.channel);
  const turnId = deriveTurnId(event);
  const correlationId = deriveCorrelationId(event);

  if (event.role === 'customer') {
    // Inbound: the customer message.
    // Role → 'external'. Identity handle derived from channel + recipientId.
    const identityHandle = mapInboundIdentityHandle(event);
    const bound = bindParticipantIdentity('external', {
      // We can't know phone/email from a legacy event (they weren't captured
      // at the ConversationTurnEvent level). Use the platform handle.
      // pickHandle prefers phone>email>cookie, but we inject a synthetic
      // 'cookie' field here so the binding falls through to identityHandle.
      // For 'fb'/'ig' kinds we do NOT use bindParticipantIdentity's pickHandle
      // (which only understands phone/email/cookie) — we set the handle
      // directly after the binding call, overriding its result.
    });

    // Direct override: bindParticipantIdentity for 'external' with no context
    // returns { role: 'external' } (no handle). We set the handle directly.
    return {
      turnId,
      conversationId: event.sessionId,
      participantRole: 'external',
      identityHandle,
      surface,
      direction: 'inbound',
      bodyText: event.text,
      correlationId,
      timestamp: event.timestamp,
    };
  } else {
    // Outbound: the assistant reply.
    // Role → 'ai'. Carries actorCertId (AI_CERT_PENDING_SENTINEL) per XOR
    // invariant — no identityHandle on cert-bound roles.
    return {
      turnId,
      conversationId: event.sessionId,
      participantRole: 'ai',
      actorCertId: AI_CERT_PENDING_SENTINEL,
      surface,
      direction: 'outbound',
      bodyText: event.text,
      correlationId,
      timestamp: event.timestamp,
    };
  }
}

// ── Email address extraction ──────────────────────────────────────────────────

/**
 * Strip the display-name from a `From:` header value, keeping only the
 * bare email address.  Examples:
 *   "John Smith <john@example.com>" → "john@example.com"
 *   "john@example.com"             → "john@example.com"
 */
function extractEmailAddress(from: string): string {
  const angleMatch = from.match(/<([^>]+)>/);
  if (angleMatch) return angleMatch[1].trim();
  return from.trim();
}

// ── mapMessagePatchToCanonical ────────────────────────────────────────────────

/**
 * Map an `OddjobzMessagePatch` (JSONL row with `schema: 'oddjobz.message.v1'`)
 * to an `OddjobzConversationTurnPayload`.
 *
 * Returns `null` if:
 *   - `patch.text` is blank/empty (nothing to persist)
 *
 * This is the email-surface complement to `mapConversationTurnEventToCanonical`,
 * which handles the live Meta / widget paths. It covers:
 *   - `channel='email'` or `channel='gmail'` → surface='email'
 *   - `channel='meta_messenger'`              → surface='meta-inbox' (backfill only)
 *   - `channel='widget'`                      → surface='widget'     (backfill only)
 *
 * ## Mapping table
 *
 * | patch field             | canonical field            | notes                                  |
 * |-------------------------|----------------------------|----------------------------------------|
 * | channel in ['email','gmail'] | surface='email'       |                                        |
 * | channel='meta_messenger'    | surface='meta-inbox'  | backfill path                          |
 * | channel='widget'            | surface='widget'      | backfill path                          |
 * | role='customer'        | participantRole='external', direction='inbound' | |
 * | role='assistant'       | participantRole='ai', direction='outbound', actorCertId=AI_CERT_PENDING_SENTINEL | |
 * | role='operator'        | participantRole='operator', direction='outbound' | |
 * | source.from (email)    | identityHandle = { kind:'email', value: bare address } | display name stripped |
 * | recipientId            | identityHandle.value for non-email channels (fallback) | |
 * | source.threadId ?? sessionId | conversationId | SHA-256 fallback if blank |
 * | source.messageId ?? patchId  | correlationId  |                          |
 * | text                   | bodyText                   |                                        |
 * | timestamp              | timestamp                  |                                        |
 *
 * ## Entity anchoring
 *
 * `entityRef` is intentionally absent. Per §13.9, the operator re-anchors
 * via `POST /api/v1/conversation/turn/:id/re-anchor` once the job cell exists.
 *
 * Pure — no IO.
 */
export function mapMessagePatchToCanonical(
  patch: OddjobzMessagePatch,
): OddjobzConversationTurnPayload | null {
  // Skip blank turns — nothing to persist.
  if (!patch.text?.trim()) return null;

  // ── Surface ────────────────────────────────────────────────────────────────
  let surface: ConversationSurface;
  if (patch.channel === 'email' || patch.channel === 'gmail') {
    surface = 'email';
  } else if (patch.channel === 'meta_messenger' || patch.channel === 'meta_instagram') {
    surface = 'meta-inbox';
  } else {
    surface = 'widget';
  }

  // ── conversationId ─────────────────────────────────────────────────────────
  const rawConversationId = patch.source?.threadId ?? patch.sessionId;
  const conversationId = rawConversationId?.trim()
    ? rawConversationId.trim()
    : createHash('sha256').update('email:' + patch.sessionId).digest('hex').slice(0, 16);

  // ── correlationId ──────────────────────────────────────────────────────────
  const correlationId = patch.source?.messageId ?? patch.patchId;

  // ── turnId ─────────────────────────────────────────────────────────────────
  const turnId =
    'turn-email-' +
    createHash('sha256')
      .update(patch.source?.messageId ?? patch.patchId)
      .digest('hex')
      .slice(0, 20);

  // ── Role / direction / identity ────────────────────────────────────────────
  if (patch.role === 'customer') {
    // Inbound: derive identityHandle from source.from (email) or recipientId.
    let identityHandle: IdentityHandle;
    if ((surface === 'email') && patch.source?.from) {
      identityHandle = {
        kind: 'email',
        value: extractEmailAddress(patch.source.from),
      };
    } else if (surface === 'meta-inbox') {
      // Meta backfill: recipientId is a PSID.
      const kind = patch.channel === 'meta_instagram' ? 'ig' : 'fb';
      identityHandle = { kind, value: patch.recipientId };
    } else {
      identityHandle = { kind: 'cookie', value: patch.recipientId };
    }

    return {
      turnId,
      conversationId,
      participantRole: 'external',
      identityHandle,
      surface,
      direction: 'inbound',
      bodyText: patch.text,
      correlationId,
      timestamp: patch.timestamp,
    };
  } else if (patch.role === 'assistant') {
    return {
      turnId,
      conversationId,
      participantRole: 'ai',
      actorCertId: AI_CERT_PENDING_SENTINEL,
      surface,
      direction: 'outbound',
      bodyText: patch.text,
      correlationId,
      timestamp: patch.timestamp,
    };
  } else {
    // operator
    return {
      turnId,
      conversationId,
      participantRole: 'operator',
      surface,
      direction: 'outbound',
      bodyText: patch.text,
      correlationId,
      timestamp: patch.timestamp,
    };
  }
}

// ── Canonical turn sink factory ────────────────────────────────────────────────

export interface MakeCanonicalTurnSinkOpts {
  /**
   * Override the id generator used when a fallback random id is needed.
   * Default: `randomUUID`. Injected for deterministic tests.
   */
  readonly generateId?: () => string;
  /**
   * Override the mapper (for tests that want to inspect the mapped turn
   * before it's persisted, or inject a no-op mapper).
   */
  readonly mapTurn?: (event: ConversationTurnEvent) => OddjobzConversationTurnPayload;
}

/**
 * Create a `ConversationTurnSink` that maps each legacy event to the
 * canonical turn shape and persists it via `makeOddjobzSinks(db)`.
 *
 * BEST-EFFORT + ISOLATED: a failure in this sink MUST NOT break the legacy
 * intake path. The caller (legacy-ingest webhook/widget server) already
 * wraps its `onConversationTurn` invocations in a try/catch that swallows
 * failures — this sink adds an additional layer.
 *
 * ADDITIVE: this sink DOES NOT replace the legacy `JsonlConversationTurnPatchSink`.
 * Both fire together (dual-sink). The legacy JSONL is kept as the V1 audit log.
 *
 * DIRECT POSTGRES — NO DEADLOCK: `makeOddjobzSinks(db)` writes to an
 * external Postgres database. This does NOT call back into the brain's
 * HTTP/REPL — no self-call deadlock risk (per project memory
 * `semantos_brain_single_threaded_reactor`).
 *
 * @param db - Real Database handle (from `getDatabaseOrNull()` at the brain
 *             reactor boundary, or a PGlite test database).
 * @param opts - Optional overrides for testing.
 *
 * @example Wire into legacy-ingest at the brain composition root:
 * ```ts
 * const db = getDatabaseOrNull();
 * const canonicalSink = db ? makeCanonicalTurnSink(db) : undefined;
 * const legacySink = new JsonlConversationTurnPatchSink({ ... });
 * const composedSink: ConversationTurnSink = async (event) => {
 *   legacySink.append(event);            // always fires (legacy JSONL)
 *   await canonicalSink?.(event);        // fires when db is available
 * };
 * new MetaWebhookServer({ ..., onConversationTurn: composedSink });
 * new WidgetServer({ ..., onConversationTurn: composedSink });
 * ```
 */
export function makeCanonicalTurnSink(
  db: Database,
  opts: MakeCanonicalTurnSinkOpts = {},
): ConversationTurnSink {
  const sinks = makeOddjobzSinks(db);
  const mapper = opts.mapTurn ?? mapConversationTurnEventToCanonical;

  return async (event: ConversationTurnEvent): Promise<void> => {
    try {
      const turn = mapper(event);
      await sinks.semObjectSink(turn);
      // BELONGS_TO_ENTITY and REPLIES_TO relations are NOT emitted here:
      // - entityRef is absent (legacy-ingest events carry no entity context;
      //   entity anchoring is a separate deliverable once the cell hash is
      //   thread-able through the legacy event).
      // - quotedTurnId is absent (legacy events carry no explicit quote ref;
      //   the quote affordance is a surface-adapter concern, not the legacy sink).
    } catch {
      // Best-effort: swallow all failures. The legacy intake path (JSONL
      // sink + the server's own try/catch) is the authoritative durable log;
      // this canonical sink is additive.
    }
  };
}

```
