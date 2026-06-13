---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/surface-adapters/sms.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.509081+00:00
---

# cartridges/oddjobz/brain/src/surface-adapters/sms.ts

```ts
/**
 * D-OJ-conv-sms-intake — SMS (Twilio) surface adapter.
 *
 * Implements `ConversationSurfaceAdapter` for `surface='sms'` — the
 * Twilio inbound SMS webhook intake path.
 *
 * ## Scope
 *
 * This adapter maps a Twilio inbound SMS webhook payload (x-www-form-
 * urlencoded) to one canonical `OddjobzConversationTurnPayload` and
 * sends outbound canonical turns via the Twilio Messaging REST API.
 *
 * This is a PURE adapter — no live Twilio webhook route is registered
 * here, and no composition-root wiring is included. That wiring (which
 * port, which express middleware, which operator config to inject) is a
 * separate follow-up needing Todd's steer.
 *
 * ## SMS is a DISTINCT surface
 *
 * `surface='sms'` has no overlap with the widget, email, or meta-inbox
 * paths. There is NO double-write risk: SMS turns are produced by this
 * adapter only.
 *
 * ## Twilio inbound webhook
 *
 * Twilio POSTs `application/x-www-form-urlencoded` to the webhook URL
 * you register:
 *
 * ```
 * MessageSid=SM...
 * AccountSid=AC...
 * From=+61412345678      ← customer E.164
 * To=+61299990000        ← operator Twilio number (E.164)
 * Body=Hello there       ← SMS text
 * NumMedia=0
 * ```
 *
 * All fields come from Twilio; the `From` is always a valid E.164 number.
 *
 * ## Conversation id
 *
 * Stable hash of the phone pair so inbound (From=customer) and outbound
 * (To=customer) share the same `conversationId`:
 *
 *   `sha256hex('sms:' + normalise(operatorNumber) + ':' + normalise(customerNumber))`
 *
 * where `normalise(s)` = s.trim().toLowerCase(). This is deterministic
 * and symmetric for the pair.
 *
 * ## Turn id
 *
 * FNV-1a-64 hash namespaced to `'sms-inbound'` seeded with the Twilio
 * `MessageSid`. Same MessageSid → same turnId (determinism invariant).
 * The MessageSid uniquely identifies the message in Twilio's platform.
 *
 * ## Participant role / direction
 *
 * - Inbound webhook (From=customer): `participantRole='external'`,
 *   `direction='inbound'`.
 * - Outbound send (To=customer): `participantRole='operator'`,
 *   `direction='outbound'`. Operator cert id from `ctx.operatorCert`
 *   when available (XOR invariant — no identityHandle for operator turns).
 *
 * ## Identity handle
 *
 * `identityHandle = { kind: 'phone', value: from }` for the external
 * party (inbound turns). The E.164 value comes directly from Twilio
 * (already normalised by Twilio's platform).
 *
 * ## §6.3 entity resolution
 *
 * Only for inbound turns (external party). If `ctx.resolveEntity` finds
 * no existing job/site/customer for the caller's phone, `entityRef` stays
 * absent. The SD2 lead-on-contact creation is delegated to the
 * detached-grandchild submitter, matching the live path.
 *
 * ## Outbound (send)
 *
 * An injected `TwilioHttpSend` function handles the actual REST call to:
 *   POST https://api.twilio.com/2010-04-01/Accounts/{AccountSid}/Messages.json
 *
 * If no sender is configured (absent in tests / early integration),
 * `send` returns `{ state: 'failed', error: 'no twilio sender configured' }`.
 *
 * In production: inject with a real `fetch`-based sender. In tests: inject
 * a mock that records calls.
 *
 * ## No LLM calls
 *
 * Per `semantos_no_ai_in_substrate`: this adapter is pure protocol↔canonical
 * mapping. No LLM calls anywhere.
 *
 * ## Single-threaded reactor / no self-calls
 *
 * `ctx.submitTurn()` routes via detached-grandchild submitter. The adapter
 * MUST NOT sync-call back into the brain's HTTP/REPL.
 *
 * ## No live-wiring (follow-up scope)
 *
 * The composition-root wiring (Twilio webhook route, operator config,
 * entity resolver) needs Todd's steer. This module ships the adapter +
 * tests only.
 */

import { createHash } from 'node:crypto';
import type {
  ConversationSurfaceAdapter,
  AdapterContext,
} from './contract.js';
import type { OddjobzConversationTurnPayload } from '../conversation/conversation-turn-patch.js';

// ── Twilio inbound SMS webhook payload ───────────────────────────────────────

/**
 * The fields from a Twilio inbound SMS webhook (x-www-form-urlencoded).
 *
 * Twilio always sends E.164 for From/To. All string fields.
 * NumMedia is '0'..'9'; MediaUrl0 present when NumMedia > 0.
 */
export interface TwilioInboundSmsWebhook {
  /** SM... — unique message identifier. Used as turnId seed. */
  readonly MessageSid: string;
  /** AC... — Twilio account identifier. */
  readonly AccountSid: string;
  /** Customer's E.164 phone (always valid E.164 from Twilio). */
  readonly From: string;
  /** Operator's Twilio number (E.164). */
  readonly To: string;
  /** SMS text body. */
  readonly Body: string;
  /** Number of attached media files ('0' when none). */
  readonly NumMedia?: string;
  /** First media URL when NumMedia > 0. */
  readonly MediaUrl0?: string;
  /** Content-type of the first media when NumMedia > 0. */
  readonly MediaContentType0?: string;
}

// ── Twilio HTTP sender abstraction (injected; no concrete dep here) ──────────

/**
 * A function that sends one SMS via the Twilio Messaging REST API.
 *
 * Signature matches the REST call:
 *   POST /2010-04-01/Accounts/{AccountSid}/Messages.json
 *   Authorization: Basic base64(AccountSid:AuthToken)
 *   Body: To=<e164>&From=<operator>&Body=<text>
 *
 * In production: inject with a real `fetch` sender.
 * In tests: inject a mock that records calls.
 *
 * Throws on failure (the adapter converts to `{ state: 'failed' }`).
 */
export type TwilioHttpSend = (params: {
  readonly to: string;
  readonly from: string;
  readonly body: string;
}) => Promise<{ sid: string }>;

// ── SmsAdapterDeps ────────────────────────────────────────────────────────────

/**
 * Deps injected at construction time via `makeSmsAdapter`.
 */
export interface SmsAdapterDeps {
  /**
   * Twilio Account SID (AC...). Required to build the REST endpoint URL
   * and the Basic Auth header.
   */
  readonly accountSid: string;

  /**
   * Twilio Auth Token. Combined with AccountSid for Basic Auth.
   */
  readonly authToken: string;

  /**
   * The operator's Twilio phone number (E.164). Used as the `From`
   * field for outbound messages.
   */
  readonly fromNumber: string;

  /**
   * Injected HTTP sender for outbound Twilio REST calls. When absent,
   * `send()` always returns `{ state: 'failed', error: 'no twilio sender configured' }`.
   *
   * Production: inject a `fetch`-based sender.
   * Tests: inject a mock that records calls.
   */
  readonly httpSend?: TwilioHttpSend;
}

// ── FNV-1a-64 deterministic id derivation ────────────────────────────────────
//
// Same approach as email.ts and legacy-ingest-bridge.ts.
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

/**
 * Derive the stable turn id for an inbound SMS from the MessageSid.
 *
 * Namespaced to 'sms-inbound' + MessageSid so the id is globally unique
 * and deterministic: same MessageSid → same turnId.
 */
function deriveSmsInboundTurnId(messageSid: string): string {
  return stableTurnId(['sms-inbound', messageSid]);
}

/**
 * Derive the stable turn id for an outbound SMS.
 *
 * Namespaced to 'sms-outbound' + Twilio SID (when available) or
 * a composed seed when the SID is not yet known (pre-send).
 */
function deriveSmsOutboundTurnId(seed: string): string {
  return stableTurnId(['sms-outbound', seed]);
}

/**
 * Derive the stable correlation id for an SMS conversation.
 *
 * Namespaced to 'sms-corr' + conversationId. All turns in the same
 * phone-pair conversation share this correlation id.
 */
function deriveSmsCorrelationId(conversationId: string): string {
  return stableTurnId(['sms-corr', conversationId]);
}

// ── Conversation id derivation ────────────────────────────────────────────────
//
// Stable hash of the phone pair (operator number + customer number).
// Both inbound (From=customer, To=operator) and outbound (To=customer,
// From=operator) produce the same conversationId so all turns in the
// same phone-pair thread share a single conversation aggregate.

/**
 * Normalise an E.164 phone number for hashing.
 * Strips whitespace and lower-cases.
 */
function normalisePhone(phone: string): string {
  return phone.trim().toLowerCase();
}

/**
 * Derive the stable conversation id for a phone pair.
 *
 * Hashes 'sms:' + operatorNumber + ':' + customerNumber using SHA-256.
 * The order is always operator-first so the hash is direction-independent:
 * inbound (From=customer, To=operator) and outbound (To=customer) share
 * the same conversationId.
 */
function deriveConversationId(
  operatorNumber: string,
  customerNumber: string,
): string {
  const seed = `sms:${normalisePhone(operatorNumber)}:${normalisePhone(customerNumber)}`;
  return createHash('sha256').update(seed).digest('hex');
}

// ── Payload validation ────────────────────────────────────────────────────────

/**
 * Validate and extract fields from a raw Twilio inbound SMS webhook payload.
 *
 * The payload arrives as a plain object (parsed from x-www-form-urlencoded).
 * Returns the typed fields or throws a descriptive error.
 */
function validateTwilioPayload(payload: unknown): TwilioInboundSmsWebhook {
  if (!payload || typeof payload !== 'object') {
    throw new Error('sms.ingest: payload must be an object');
  }
  const p = payload as Record<string, unknown>;

  const MessageSid = typeof p.MessageSid === 'string' ? p.MessageSid : '';
  const AccountSid = typeof p.AccountSid === 'string' ? p.AccountSid : '';
  const From = typeof p.From === 'string' ? p.From.trim() : '';
  const To = typeof p.To === 'string' ? p.To.trim() : '';
  const Body = typeof p.Body === 'string' ? p.Body : null;
  const NumMedia = typeof p.NumMedia === 'string' ? p.NumMedia : undefined;
  const MediaUrl0 = typeof p.MediaUrl0 === 'string' ? p.MediaUrl0 : undefined;
  const MediaContentType0 =
    typeof p.MediaContentType0 === 'string' ? p.MediaContentType0 : undefined;

  if (!MessageSid) {
    throw new Error('sms.ingest: payload.MessageSid is required');
  }
  if (!From) {
    throw new Error('sms.ingest: payload.From (customer E.164) is required');
  }
  if (!To) {
    throw new Error('sms.ingest: payload.To (operator number) is required');
  }
  if (Body === null) {
    throw new Error('sms.ingest: payload.Body is required');
  }

  // Validate E.164 format for From (must start with +).
  // Twilio always delivers valid E.164, but we guard defensively.
  if (!From.startsWith('+')) {
    throw new Error(
      `sms.ingest: payload.From must be E.164 (starts with +), got: ${From}`,
    );
  }

  return {
    MessageSid,
    AccountSid,
    From,
    To,
    Body,
    NumMedia,
    MediaUrl0,
    MediaContentType0,
  };
}

// ── makeSmsAdapter ────────────────────────────────────────────────────────────

/**
 * Create a `ConversationSurfaceAdapter` for `surface='sms'`.
 *
 * Usage:
 * ```ts
 * const adapter = makeSmsAdapter({
 *   accountSid: 'ACxxx',
 *   authToken: 'xxx',
 *   fromNumber: '+61299990000',
 *   httpSend: myTwilioSend,   // inject real fetch sender in prod
 * });
 *
 * // Inbound webhook (already parsed from x-www-form-urlencoded):
 * const turns = await adapter.ingest(twilioWebhookFields, ctx);
 *
 * // Outbound reply:
 * await adapter.send(outboundTurn, ctx);
 * ```
 *
 * The adapter is STATELESS; a single instance can serve many calls.
 */
export function makeSmsAdapter(deps: SmsAdapterDeps): ConversationSurfaceAdapter {
  const { fromNumber, httpSend } = deps;

  return {
    surface: 'sms',

    // ── ingest ───────────────────────────────────────────────────────────────
    //
    // Maps a Twilio inbound SMS webhook payload to one canonical inbound turn.
    //
    // One inbound SMS → one inbound turn:
    //   surface='sms', participantRole='external', direction='inbound'
    //   identityHandle = { kind: 'phone', value: From }  ← L1 identity
    //   conversationId = sha256('sms:' + To + ':' + From)
    //   turnId = stableTurnId(['sms-inbound', MessageSid])
    //
    // §6.3 entity resolution: tries to resolve the entity from the caller's
    // E.164 phone. If null, entityRef stays absent; SD2 lead-on-contact
    // creation is delegated to the detached-grandchild submitter.
    //
    // Calls ctx.submitTurn(turn) before returning.
    async ingest(
      payload: unknown,
      ctx: AdapterContext,
    ): Promise<OddjobzConversationTurnPayload[]> {
      // Validate and extract the Twilio webhook fields.
      const webhook = validateTwilioPayload(payload);

      const { MessageSid, From, To, Body } = webhook;
      const customerPhone = From; // E.164, already validated
      const operatorPhone = To;   // E.164 (operator's Twilio number)

      const conversationId = deriveConversationId(operatorPhone, customerPhone);
      const turnId = deriveSmsInboundTurnId(MessageSid);
      const correlationId = deriveSmsCorrelationId(conversationId);
      const timestamp = Date.now();

      // §6.3 entity resolution — only for inbound (external party).
      let entityRef: OddjobzConversationTurnPayload['entityRef'];
      const identityHandle = { kind: 'phone' as const, value: customerPhone };
      const resolved = await ctx.resolveEntity(identityHandle);
      if (resolved) {
        entityRef = { kind: resolved.kind, cellHash: resolved.cellHash };
      }
      // If null: §6.3 — entityRef absent; SD2 lead-on-contact handles
      // job creation via the detached-grandchild submitter out-of-band.

      const turn: OddjobzConversationTurnPayload = {
        turnId,
        conversationId,
        participantRole: 'external',
        identityHandle,
        surface: 'sms',
        direction: 'inbound',
        bodyText: Body,
        correlationId,
        timestamp,
        ...(entityRef ? { entityRef } : {}),
      };

      await ctx.submitTurn(turn);
      return [turn];
    },

    // ── send ─────────────────────────────────────────────────────────────────
    //
    // Send an outbound canonical turn via the Twilio Messaging REST API.
    //
    // The destination phone is read from the turn's `identityHandle.value`
    // (the customer's E.164, which the inbound turn recorded). The text body
    // is `turn.bodyText`.
    //
    // Returns `{ state: 'delivered', surfaceMessageId }` on success,
    // `{ state: 'failed', error }` on failure. MUST NOT throw.
    async send(
      turn: OddjobzConversationTurnPayload,
      _ctx: AdapterContext,
    ): Promise<{
      state: 'delivered' | 'failed';
      surfaceMessageId?: string;
      error?: string;
    }> {
      if (!httpSend) {
        return {
          state: 'failed',
          error: 'sms.send: no twilio sender configured',
        };
      }

      // Resolve the destination phone from the turn's identityHandle.
      // The SMS surface uses `identityHandle.kind='phone'` for the
      // external customer, set during ingest.
      const to =
        turn.identityHandle?.kind === 'phone'
          ? turn.identityHandle.value
          : undefined;

      if (!to) {
        return {
          state: 'failed',
          error:
            'sms.send: turn has no phone identityHandle; cannot determine destination',
        };
      }

      try {
        const result = await httpSend({
          to,
          from: fromNumber,
          body: turn.bodyText,
        });
        return {
          state: 'delivered',
          surfaceMessageId: result.sid,
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
