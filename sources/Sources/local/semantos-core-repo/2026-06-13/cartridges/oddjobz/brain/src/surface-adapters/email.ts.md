---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/surface-adapters/email.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.509711+00:00
---

# cartridges/oddjobz/brain/src/surface-adapters/email.ts

```ts
/**
 * D-OJ-conv-email-intake — email surface adapter.
 *
 * Implements `ConversationSurfaceAdapter` for `surface='email'` — the RFC822
 * email intake path.
 *
 * ## Scope
 *
 * This adapter maps raw RFC822 email payloads (single messages and threads)
 * to canonical `OddjobzConversationTurnPayload[]`. It does NOT stand up a
 * live Gmail watch/pubsub fetch loop and is NOT wired into the live composition
 * root (`apps/legacy-cli`). That live-wiring + the "which widget is canonical"
 * composition question is a SEPARATE follow-up needing Todd's steer.
 *
 * ## Email is a DISTINCT surface
 *
 * `surface='email'` has no overlap with the live widget or meta-inbox paths.
 * There is NO double-write risk: email turns are produced by this adapter only.
 *
 * ## Relationship to the live intake path
 *
 * The existing `legacy-ingest` pipeline (EmailExtractor → ProposalStore →
 * ratification) is the LIVE email-to-job path. This adapter is ADDITIVE: it
 * maps the same underlying RFC822 bytes onto canonical conversation turns
 * WITHOUT forking or replacing the legacy extraction path.
 *
 * - `ingest` receives a raw email payload (bytes or thread) and calls
 *   `parseRfc822` + `parseEmailMimeParts` from `@semantos/legacy-ingest`
 *   (reuse, no reimplementation of RFC822 parsing).
 * - `send` routes an outbound canonical turn back over the email surface
 *   via an injected sender function (SMTP / Gmail API / no-op for tests).
 *
 * ## Thread mapping
 *
 * An email THREAD is a turn stream — each message is one canonical turn:
 *
 * - `surface = 'email'`
 * - `conversationId` is derived from the thread's root Message-ID.
 *   For a single message with no In-Reply-To, the message's own Message-ID
 *   is the conversationId. For a thread, all messages share the root
 *   Message-ID as the conversationId.
 * - `timestamp` from the Date header (unix ms).
 * - `bodyText` = plain-text body (from parseEmailMimeParts plainText).
 * - `bodyParts` = attachments (image/pdf/other).
 * - `quotedTurnId` from In-Reply-To when it resolves to a prior message in
 *   the thread.
 *
 * ## Participant role + direction
 *
 * - Message FROM external/customer (From address NOT in the operator's own
 *   addresses) → `participantRole='external'`, `direction='inbound'`.
 * - Message FROM the operator (From address in the operator's known addresses
 *   per `OJT_SELF_FORWARD_ADDRESSES` + operatorEmails dep) →
 *   `participantRole='operator'`, `direction='outbound'`.
 *
 * Decision: when no `operatorCert` is available at the adapter level (tests
 * and pre-cert contexts), we fall back to the operator-emails list only.
 * This mirrors the widget adapter's identity treatment: we do NOT fabricate
 * identity from a cert that isn't present. Documented choice per §6.2.
 *
 * ## Identity handle
 *
 * `identityHandle = { kind: 'email', value: <fromAddress> }` for the external
 * party (inbound turns). Operator turns carry `actorCertId` from the
 * `operatorCert` when available; absent → no actorCertId (XOR invariant).
 *
 * ## Deterministic id derivation
 *
 * `turnId` and `correlationId` use the same FNV-1a-64 approach as
 * `legacy-ingest-bridge.ts` (`stableTurnId`), namespaced to 'email-turn'.
 * Same email → same turnId (determinism invariant).
 *
 * ## Attachment mapping
 *
 * `parseEmailMimeParts` from `@semantos/legacy-ingest` splits the MIME body.
 * `plainText` → `bodyText`. Each `EmailMimePart` with `kind !== 'text'` →
 * one `OddjobzTurnBodyPart` with `kind: 'attachment'`.
 *
 * ## No LLM calls
 *
 * Per `semantos_no_ai_in_substrate`: this adapter is pure protocol↔canonical
 * mapping. The LLM-based intent extraction (EmailExtractor / ProposalStore /
 * ratification) is downstream compression — NOT built here.
 *
 * ## No live-wiring (follow-up scope)
 *
 * The composition-root wiring (which storage provider, which entity resolver,
 * which email sender to inject) + the "which widget is canonical" composition
 * question need Todd's steer. Tracked as a follow-up. This module ships the
 * adapter + tests only.
 */

import { randomUUID } from 'node:crypto';
import {
  parseRfc822,
  parseEmailMimeParts,
  OJT_SELF_FORWARD_ADDRESSES,
} from '@semantos/legacy-ingest';
import type { EmailMimePart } from '@semantos/legacy-ingest';
import {
  bindParticipantIdentity,
  type OddjobzConversationTurnPayload,
  type OddjobzTurnBodyPart,
} from '../conversation/conversation-turn-patch.js';
import type {
  ConversationSurfaceAdapter,
  AdapterContext,
} from './contract.js';

// ── ParsedEmail re-export (adapter-visible shape) ─────────────────────────────
//
// `parseRfc822` from legacy-ingest returns a plain ParsedEmail object.
// We use it directly; the type is inlined here so the adapter is self-contained.

interface ParsedEmail {
  readonly headers: Readonly<Record<string, string>>;
  readonly body: string;
  readonly messageId: string | null;
  readonly inReplyTo: string | null;
  readonly references: string | null;
  readonly subject: string;
  readonly from: string;
}

// ── EmailRawPayload ───────────────────────────────────────────────────────────

/**
 * A raw RFC822 email payload ingested by the email adapter.
 *
 * Two forms:
 *  - `{ kind: 'single', bytes }` — one raw RFC822 message.
 *  - `{ kind: 'thread', messages }` — ordered array of raw RFC822 messages
 *    that form a single conversation thread (oldest first).
 *
 * IMPORTANT: callers must supply messages in chronological order (oldest
 * first) for the `thread` form. The adapter does NOT re-sort by Date header;
 * it relies on the caller having ordered the thread correctly (e.g. Gmail's
 * thread list in message-date order).
 */
export type EmailRawPayload =
  | { readonly kind: 'single'; readonly bytes: Uint8Array }
  | { readonly kind: 'thread'; readonly messages: ReadonlyArray<Uint8Array> };

// ── Email sender abstraction (injected; no concrete SMTP/API dep here) ─────────

/**
 * A function that delivers an outbound turn via the email surface.
 *
 * In production: injected with a real SMTP send or Gmail API send function.
 * In tests: inject a mock that records calls.
 *
 * Signature: async (turn) → surfaceMessageId | undefined.
 * Throws when the send fails (adapter converts to `{ state: 'failed' }`).
 */
export type EmailSender = (
  turn: OddjobzConversationTurnPayload,
) => Promise<string | undefined>;

// ── EmailAdapterDeps ──────────────────────────────────────────────────────────

/**
 * Deps injected at construction time via `makeEmailAdapter`.
 */
export interface EmailAdapterDeps {
  /**
   * Generate a unique id for turns / correlation ids.
   * Default: `randomUUID()`. Injected for deterministic tests.
   */
  readonly generateId?: () => string;

  /**
   * Current time in unix-millis (used as fallback when no Date header).
   * Default: `Date.now()`. Injected for deterministic tests.
   */
  readonly now?: () => number;

  /**
   * The operator's own email addresses. Used to classify whether a message
   * is inbound (FROM external) or outbound (FROM operator). Defaults to
   * `OJT_SELF_FORWARD_ADDRESSES` from `@semantos/legacy-ingest`.
   *
   * In production: inject from operator configuration.
   * In tests: inject known operator addresses.
   */
  readonly operatorEmailAddresses?: readonly string[];

  /**
   * Email sender for outbound turns. When absent, `send` always returns
   * `{ state: 'failed', error: 'no email sender configured' }`.
   *
   * Production: inject the SMTP/Gmail API send function.
   * Tests: inject a mock that records calls.
   */
  readonly emailSender?: EmailSender;
}

// ── FNV-1a-64 deterministic id derivation ────────────────────────────────────
//
// Mirrors the approach in `legacy-ingest-bridge.ts` (`stableTurnId`).
// Same inputs → same id (determinism invariant).

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

function deriveEmailTurnId(
  messageId: string | null,
  conversationId: string,
  fromAddress: string,
  direction: 'inbound' | 'outbound',
  timestamp: number,
): string {
  return stableTurnId([
    'email-turn',
    messageId ?? `no-msgid:${conversationId}:${timestamp}`,
    conversationId,
    fromAddress,
    direction,
    timestamp,
  ]);
}

function deriveEmailCorrelationId(conversationId: string): string {
  return stableTurnId(['email-corr', conversationId]);
}

// ── Conversation id derivation from thread headers ────────────────────────────
//
// For a single message with no In-Reply-To, the message's own Message-ID
// is the conversationId. For a thread, we walk In-Reply-To + References to
// find the root Message-ID.
//
// This matches the `threadKey` approach from `legacy-ingest`'s Proposal.
// We use the root Message-ID to give all messages in a thread the same
// conversationId.

function deriveConversationId(parsed: ParsedEmail, fallback: string): string {
  // If this is a reply, the conversation root is the earliest message in the
  // References chain. Gmail populates References as a space-separated list of
  // Message-IDs in chronological order. The FIRST entry is the root.
  if (parsed.references) {
    const refs = parsed.references.trim().split(/\s+/).filter(Boolean);
    const rootRef = refs[0];
    if (rootRef) {
      // Strip <...> if present (parseRfc822 already strips them via pickAngled,
      // but References may carry raw <...> form if not through pickAngled).
      const stripped = rootRef.replace(/^<|>$/g, '');
      if (stripped.length > 0) return stripped;
    }
  }

  // No References chain: use the In-Reply-To as a fallback grouper, or
  // the message's own Message-ID for a standalone message.
  if (parsed.inReplyTo) return parsed.inReplyTo;
  if (parsed.messageId) return parsed.messageId;

  // Last resort: the caller-supplied fallback (generated id).
  return fallback;
}

// ── Turn-id map for quotedTurnId resolution ───────────────────────────────────
//
// Within a thread ingest, we build a map from Message-ID → turnId so that
// In-Reply-To references can be resolved to a prior turn's id.

type MessageIdToTurnId = Map<string, string>;

// ── Email address extraction + operator detection ─────────────────────────────

/**
 * Extract the bare `user@domain.tld` from an RFC5322 address string.
 * Handles `Name <email>` form as well as bare addresses.
 * Returns empty string on parse failure.
 */
function extractEmailAddress(raw: string): string {
  if (!raw) return '';
  const m = raw.match(/<([^<>\s]+@[^<>\s]+)>/);
  if (m) return m[1].trim().toLowerCase();
  const bare = raw.match(/([^\s,;<>]+@[^\s,;<>]+)/);
  if (bare) return bare[1].trim().toLowerCase();
  return '';
}

/**
 * Determine if a From-address is the operator's own address.
 * Returns true when the lowercased address matches any of the
 * configured `operatorEmailAddresses`.
 */
function isOperatorAddress(
  fromAddress: string,
  operatorAddresses: readonly string[],
): boolean {
  const lc = fromAddress.toLowerCase();
  return operatorAddresses.some(addr => addr.toLowerCase() === lc);
}

// ── Parse a Date header to unix-ms ───────────────────────────────────────────

function parseDateHeader(dateHeader: string | undefined, fallback: number): number {
  if (!dateHeader) return fallback;
  const d = new Date(dateHeader);
  const ms = d.getTime();
  return isNaN(ms) ? fallback : ms;
}

// ── Build bodyParts from EmailMimePart[] ──────────────────────────────────────

/**
 * Map `EmailMimePart[]` from `parseEmailMimeParts` onto `OddjobzTurnBodyPart[]`.
 *
 * Non-text attachments (image, pdf, other) each become one `'attachment'` body
 * part. Text parts are already reflected in `bodyText` (via `plainText`) and
 * are NOT duplicated in `bodyParts`.
 */
function buildBodyParts(
  attachments: EmailMimePart[],
): OddjobzTurnBodyPart[] | undefined {
  const parts: OddjobzTurnBodyPart[] = attachments
    .filter(att => att.kind !== 'text')
    .map(att => ({
      kind: 'attachment' as const,
      payload: {
        contentType: att.contentType,
        filename: att.filename ?? undefined,
        sizeBytes: att.bytes.length,
        attachmentKind: att.kind,
      },
    }));
  return parts.length > 0 ? parts : undefined;
}

// ── Per-message turn builder ──────────────────────────────────────────────────

function buildTurnForMessage(
  parsed: ParsedEmail,
  conversationId: string,
  msgIdToTurnId: MessageIdToTurnId,
  operatorAddresses: readonly string[],
  ctx: AdapterContext,
  nowMs: number,
): OddjobzConversationTurnPayload {
  const fromAddress = extractEmailAddress(parsed.from);
  const timestamp = parseDateHeader(parsed.headers['date'], nowMs);
  const isOperator = isOperatorAddress(fromAddress, operatorAddresses);
  const direction: 'inbound' | 'outbound' = isOperator ? 'outbound' : 'inbound';

  const turnId = deriveEmailTurnId(
    parsed.messageId,
    conversationId,
    fromAddress,
    direction,
    timestamp,
  );
  const correlationId = deriveEmailCorrelationId(conversationId);

  // Parse MIME parts for plain text + attachments.
  const rootContentType = parsed.headers['content-type'] ?? '';
  let bodyText: string;
  let attachments: EmailMimePart[] = [];

  if (rootContentType.toLowerCase().startsWith('multipart/')) {
    const parts = parseEmailMimeParts(parsed.body, rootContentType);
    bodyText = parts.plainText || parsed.body;
    attachments = parts.attachments;
  } else {
    // Non-multipart: body is the plain text (or HTML, decoded by parseRfc822).
    bodyText = parsed.body;
  }

  const bodyParts = buildBodyParts(attachments);

  // Resolve quotedTurnId from In-Reply-To header.
  // The In-Reply-To header carries the Message-ID of the message being replied to.
  // If that Message-ID is in our msgIdToTurnId map (i.e. it belongs to a prior
  // message in the current thread), set quotedTurnId.
  let quotedTurnId: string | undefined;
  if (parsed.inReplyTo) {
    const referencedTurnId = msgIdToTurnId.get(parsed.inReplyTo);
    if (referencedTurnId && referencedTurnId !== turnId) {
      quotedTurnId = referencedTurnId;
    }
  }

  // Identity binding.
  // - Inbound (external): identityHandle = { kind: 'email', value: fromAddress }
  // - Outbound (operator): actorCertId from operatorCert when available;
  //   absent → no actorCertId (XOR invariant; do NOT fabricate).
  //
  // Decision: when `operatorCert` is available at the adapter level, we use
  // its certId for outbound operator turns. This is the same cert provided
  // in the AdapterContext. We do NOT fall back to identityHandle for a cert-
  // bound role (XOR invariant per §5.2).
  let participantRole: OddjobzConversationTurnPayload['participantRole'];
  let actorCertId: string | undefined;
  let identityHandle: OddjobzConversationTurnPayload['identityHandle'];

  if (isOperator) {
    participantRole = 'operator';
    // Use the operatorCert's certId when available. This reflects the cert-bound
    // role (L2) per §5.2. When the cert is absent (e.g. in test contexts without
    // a real cert), we leave actorCertId undefined — we do NOT invent a value.
    const certId = ctx.operatorCert?.certId;
    if (certId) {
      actorCertId = certId;
    }
    // identityHandle is absent for cert-bound operator role (XOR invariant).
  } else {
    // External party (inbound).
    participantRole = 'external';
    // L1 email identity handle.
    if (fromAddress) {
      identityHandle = { kind: 'email', value: fromAddress };
    }
    // actorCertId is absent for un-cert'd external role (XOR invariant).
  }

  // Bind identity via bindParticipantIdentity for the record; we assemble
  // the turn directly using the role + cert/handle determined above since
  // bindParticipantIdentity operates on phone/email/cookie keys for un-cert'd
  // parties (its pickHandle doesn't know about 'email' in the IdentityHandle
  // kind sense — it looks for the `email` field in IdentityBindingContext).
  // We set identityHandle directly to preserve the `kind: 'email'` semantics.
  void bindParticipantIdentity; // imported; used in widget.ts pattern; direct assembly here

  const turn: OddjobzConversationTurnPayload = {
    turnId,
    conversationId,
    participantRole,
    ...(actorCertId ? { actorCertId } : {}),
    ...(identityHandle ? { identityHandle } : {}),
    surface: 'email',
    direction,
    bodyText: bodyText.trim(),
    ...(bodyParts ? { bodyParts } : {}),
    ...(quotedTurnId ? { quotedTurnId } : {}),
    correlationId,
    timestamp,
  };

  // Register this turn's Message-ID → turnId so later messages in the thread
  // can reference it via In-Reply-To.
  if (parsed.messageId) {
    msgIdToTurnId.set(parsed.messageId, turnId);
  }

  return turn;
}

// ── makeEmailAdapter ──────────────────────────────────────────────────────────

/**
 * Create a `ConversationSurfaceAdapter` for `surface='email'`.
 *
 * Usage:
 * ```ts
 * const adapter = makeEmailAdapter({
 *   operatorEmailAddresses: ['operator@example.com'],
 *   emailSender: mySmtpSend,
 * });
 *
 * // Single message:
 * const turns = await adapter.ingest(
 *   { kind: 'single', bytes: rawEmailBytes },
 *   ctx,
 * );
 *
 * // Thread (ordered oldest→newest):
 * const turns = await adapter.ingest(
 *   { kind: 'thread', messages: [rawMsg1, rawMsg2, rawMsg3] },
 *   ctx,
 * );
 *
 * // Outbound (reply):
 * await adapter.send(outboundTurn, ctx);
 * ```
 *
 * The adapter is STATELESS; a single instance can serve many ingests.
 */
export function makeEmailAdapter(deps: EmailAdapterDeps = {}): ConversationSurfaceAdapter {
  const generateId = deps.generateId ?? (() => randomUUID());
  const now = deps.now ?? (() => Date.now());
  const operatorAddresses: readonly string[] = deps.operatorEmailAddresses
    ?? OJT_SELF_FORWARD_ADDRESSES;
  const emailSender = deps.emailSender;

  return {
    surface: 'email',

    // ── ingest ───────────────────────────────────────────────────────────────
    //
    // Maps an RFC822 email payload (single or thread) to canonical turn(s).
    // Calls `ctx.submitTurn` for each produced turn before returning.
    //
    // §6.3 lead-on-contact: tries to resolve the entity from the external
    // party's email address. If `ctx.resolveEntity` returns null, `entityRef`
    // stays absent. The SD2 lead-on-contact job creation is delegated to the
    // detached-grandchild submitter (not done here).
    //
    // Thread ordering: messages are processed in the order supplied by the
    // caller (oldest first expected). The msgIdToTurnId map is built
    // progressively so In-Reply-To references resolve correctly.
    async ingest(
      payload: unknown,
      ctx: AdapterContext,
    ): Promise<OddjobzConversationTurnPayload[]> {
      if (!payload || typeof payload !== 'object') {
        throw new Error('email.ingest: payload must be an object');
      }
      const p = payload as Record<string, unknown>;

      if (p.kind !== 'single' && p.kind !== 'thread') {
        throw new Error(
          'email.ingest: payload.kind must be "single" or "thread"',
        );
      }

      // Build the list of raw message bytes to process.
      let rawMessages: Uint8Array[];
      if (p.kind === 'single') {
        if (!(p.bytes instanceof Uint8Array)) {
          throw new Error('email.ingest: payload.bytes must be a Uint8Array for kind="single"');
        }
        rawMessages = [p.bytes as Uint8Array];
      } else {
        if (!Array.isArray(p.messages) || p.messages.length === 0) {
          throw new Error('email.ingest: payload.messages must be a non-empty array for kind="thread"');
        }
        if (!p.messages.every(m => m instanceof Uint8Array)) {
          throw new Error('email.ingest: payload.messages must contain Uint8Array elements');
        }
        rawMessages = p.messages as Uint8Array[];
      }

      const nowMs = now();
      const turns: OddjobzConversationTurnPayload[] = [];

      // Message-ID → turnId map for In-Reply-To resolution within the thread.
      const msgIdToTurnId: MessageIdToTurnId = new Map();

      // Derive the conversation id from the first message in the thread.
      // All messages in the thread share the same conversationId.
      const firstParsed = parseRfc822(rawMessages[0]) as unknown as ParsedEmail;
      const fallbackConvId = generateId();
      const conversationId = deriveConversationId(firstParsed, fallbackConvId);

      for (const rawMsg of rawMessages) {
        const parsed = parseRfc822(rawMsg) as unknown as ParsedEmail;
        const turn = buildTurnForMessage(
          parsed,
          conversationId,
          msgIdToTurnId,
          operatorAddresses,
          ctx,
          nowMs,
        );

        // §6.3 entity resolution: try to resolve the entity from the external
        // party's email identity. Only for inbound turns (external party).
        // Operator turns do not need entity resolution.
        let entityRef: OddjobzConversationTurnPayload['entityRef'];
        if (turn.direction === 'inbound' && turn.identityHandle) {
          const resolved = await ctx.resolveEntity(turn.identityHandle);
          if (resolved) {
            entityRef = { kind: resolved.kind, cellHash: resolved.cellHash };
          }
          // If null: §6.3 — entityRef absent; SD2 lead-on-contact handles
          // job creation via the detached-grandchild submitter out-of-band.
        }

        // Apply entityRef if resolved.
        const finalTurn: OddjobzConversationTurnPayload = entityRef
          ? { ...turn, entityRef }
          : turn;

        await ctx.submitTurn(finalTurn);
        turns.push(finalTurn);
      }

      return turns;
    },

    // ── send ─────────────────────────────────────────────────────────────────
    //
    // Deliver an outbound canonical turn over the email surface.
    //
    // In production, the emailSender dep sends via SMTP/Gmail API.
    // If no sender is configured, returns `{ state: 'failed' }` gracefully.
    //
    // `send` MUST NOT throw (per the §6.1 contract).
    async send(
      turn: OddjobzConversationTurnPayload,
      _ctx: AdapterContext,
    ): Promise<{ state: 'delivered' | 'failed'; surfaceMessageId?: string; error?: string }> {
      if (!emailSender) {
        return {
          state: 'failed',
          error: 'email.send: no email sender configured',
        };
      }

      try {
        const surfaceMessageId = await emailSender(turn);
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
