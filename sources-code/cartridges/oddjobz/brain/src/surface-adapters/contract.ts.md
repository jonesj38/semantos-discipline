---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/surface-adapters/contract.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.508757+00:00
---

# cartridges/oddjobz/brain/src/surface-adapters/contract.ts

```ts
/**
 * D-OJ-conv-widget-intake — §6.1 ConversationSurfaceAdapter contract.
 *
 * This is the SHARED abstract interface that ALL surface adapters
 * (widget, email, sms, meta-inbox, voice, import) must implement.
 * Email / SMS / Meta-inbox adapters are SEPARATE deliverables — this
 * file only defines the contract they will import and implement.
 *
 * Design notes:
 *
 * - `Brc52Cert` is the REAL canonical type from `@semantos/protocol-types`
 *   (W1.5C-1 promoted it from @plexus/contracts; certId is the stable
 *   SHA-256 identity hash; full wire format per §4.2 of protocol-v0.5.md).
 *   The `operatorCert` field is used by adapters to sign outbound messages
 *   and authenticate to upstream provider APIs as the operator.
 *
 * - `submitTurn` MUST route through the brain's EXISTING intent submission
 *   path via the DETACHED-GRANDCHILD SUBMITTER PATTERN (the 2026-05-18
 *   self-call deadlock fix — `intake-handler.ts` `runDetachedSubmit`).
 *   Adapters MUST NOT sync-call back into the brain's HTTP/REPL. Persisting
 *   canonical turns directly to Postgres via `makeOddjobzSinks` is fine
 *   (Postgres is external, not the brain reactor). See project memories:
 *   `semantos_brain_single_threaded_reactor`, `semantos_streams_shell_native`.
 *
 * - `resolveEntity` decouples the adapter from the storage substrate: the
 *   adapter maps a contact handle (phone, email, IG handle…) to the canonical
 *   entity cell. If the entity is not found, the §6.3 lead-on-contact policy
 *   applies (see `widget.ts` — make a lead-state job and anchor the turn there).
 *
 * Per `semantos_no_ai_in_substrate`: adapters are pure protocol↔canonical
 * mapping + persistence. No LLM calls.
 *
 * Per `semantos_streams_shell_native`: these adapters live substrate-side,
 * NOT as cartridges.
 */

import type { Brc52Cert } from '@semantos/protocol-types';
import type { OddjobzConversationTurnPayload } from '../conversation/conversation-turn-patch.js';

// ── Re-export Brc52Cert for adapter consumers ─────────────────────────────────
export type { Brc52Cert };

// ── ConversationSurface discriminant ─────────────────────────────────────────
//
// Matches `ConversationSurface` in conversation-turn-patch.ts. Repeated here
// so the contract module is self-contained — adapters import from here.
export type SurfaceKind =
  | 'widget'
  | 'meta-inbox'
  | 'email'
  | 'voice'
  | 'sms'
  | 'import';

// ── AdapterContext ────────────────────────────────────────────────────────────

/**
 * The context provided to an adapter's `ingest` and `send` methods.
 *
 * Adapters receive this at call time (not at construction time) so that
 * the context can carry per-request values (which cert is active, which
 * entity resolver is scoped to the current session, etc.).
 */
export interface AdapterContext {
  /**
   * The operator's Plexus-issued BRC-52 cert. Adapters use it to:
   *  - Sign outbound messages (so the external service knows the sender).
   *  - Authenticate to upstream provider APIs as the operator.
   *
   * Type: `Brc52Cert` from `@semantos/protocol-types` (canonical; W1.5C-1).
   * Fields: certId (SHA-256 stable id), subjectPublicKey, certifierPublicKey,
   * type, serialNumber, fields, signature. See `core/protocol-types/src/identity.ts`.
   */
  readonly operatorCert: Brc52Cert;

  /**
   * Resolve a surface handle (phone, email, IG handle, etc.) to the
   * canonical entity cell (job/site/customer) it belongs to.
   *
   * Returns the cell hash + entity kind when found; `null` when not found.
   *
   * When `null`, §6.3 lead-on-contact policy applies: the adapter should
   * create a `lead`-state job and anchor the turn there (SD2 lead-on-contact).
   * The operator can re-anchor later.
   *
   * Pure lookup — no side effects. The entity creation (lead-on-contact) is
   * the ADAPTER's responsibility, not this function's.
   */
  resolveEntity(
    handle: { kind: string; value: string },
  ): Promise<{ cellHash: string; kind: 'job' | 'site' | 'customer' } | null>;

  /**
   * Submit a fully-formed canonical turn through the STANDARD INTAKE PATH.
   *
   * CONTRACT: this MUST use the detached-grandchild submitter pattern
   * (NOT a sync-call back into the brain's HTTP/REPL). See
   * `intake-handler.ts` `runDetachedSubmit` / `--detached-submit` and
   * project memory `semantos_brain_single_threaded_reactor`.
   *
   * In practice, for brain-reactor-boundary adapters (like the widget
   * adapter) this means either:
   *  (a) Writing directly to Postgres via `makeOddjobzSinks(db)` — Postgres
   *      is external, not the brain reactor — which is what the widget
   *      adapter does via the injected `submitTurn` dep, OR
   *  (b) Spawning a detached grandchild that calls the loopback REPL.
   *
   * The adapter itself does not choose which implementation to use; it
   * calls `ctx.submitTurn(turn)` and the caller that built the context
   * wires the right implementation.
   */
  submitTurn(turn: OddjobzConversationTurnPayload): Promise<void>;
}

// ── ConversationSurfaceAdapter ────────────────────────────────────────────────

/**
 * §6.1 Abstract surface-adapter contract.
 *
 * Every protocol bridge that feeds into Oddjobz conversation substrate
 * implements this interface. It maps a native protocol payload onto the
 * canonical turn shape (§4) and sends outbound canonical turns over the
 * native protocol.
 *
 * Implementations live at
 *   `cartridges/oddjobz/brain/src/surface-adapters/<surface>.ts`
 *
 * Current adapters:
 *   - `widget.ts` (`makeWidgetAdapter`) — Oddjobz chat-widget WS payload.
 *     This deliverable (D-OJ-conv-widget-intake) ALSO establishes this file.
 *
 * Future adapters (separate deliverables):
 *   - `meta-inbox.ts` — IG/FB Graph API DM webhook.
 *   - `email.ts` — Gmail watch/pubsub envelope.
 *   - `voice.ts` — voice-note payload.
 *   - `sms.ts` — Twilio inbound webhook.
 *   - `import.ts` — historical CSV / IG legacy export.
 *
 * CONTRACT:
 *   - `ingest` is pure protocol→canonical mapping + identity binding.
 *     No LLM calls (per `semantos_no_ai_in_substrate`). May return many
 *     turns (e.g. an email thread import is many turns).
 *   - `send` is canonical→protocol marshalling + delivery. Returns
 *     `delivered`/`failed` terminal state with optional surface message id.
 *   - `submitTurn` in the AdapterContext routes via the detached-grandchild
 *     submitter (never sync-calls the brain REPL).
 */
export interface ConversationSurfaceAdapter {
  /**
   * Surface identifier. MUST match the `surface` field on all canonical
   * turns produced by this adapter's `ingest` method.
   */
  readonly surface: SurfaceKind;

  /**
   * Map a native protocol payload to canonical turn(s).
   *
   * May return many turns (e.g. an email thread is many turns; a voice note
   * may produce a transcript turn + a metadata turn). Must return at least
   * one turn for a successful ingest. Returns an empty array when the payload
   * is a control message that should produce no turn (e.g. a read-receipt).
   *
   * The adapter MUST call `ctx.submitTurn(turn)` for each produced turn
   * before returning — `ingest` both builds AND submits.
   *
   * Identity binding: each adapter maps its native identity token (phone,
   * email, handle, cookie) onto `identityHandle` via `bindParticipantIdentity`
   * from `conversation-turn-patch.ts`. §6.3: if `ctx.resolveEntity` misses,
   * the adapter creates a `lead`-state job and anchors the turn there.
   *
   * @param payload - The native protocol payload (WS message, webhook body, etc.).
   * @param ctx - The adapter context for the current request.
   * @returns The canonical turn(s) produced (after they have been submitted).
   */
  ingest(
    payload: unknown,
    ctx: AdapterContext,
  ): Promise<OddjobzConversationTurnPayload[]>;

  /**
   * Send an outbound canonical turn over the native protocol.
   *
   * The adapter is responsible for:
   *  1. Looking up the destination (from the entity's contact info or
   *     the turn's `identityHandle`).
   *  2. Marshalling the canonical turn to the native protocol shape.
   *  3. Sending and returning the delivery state.
   *
   * Returns `{ state: 'delivered' }` on success, `{ state: 'failed', error }`
   * on failure. The `surfaceMessageId` (e.g. WS correlation id, email
   * message-id, Twilio SID) is returned when available for cross-reference.
   *
   * This method MUST NOT throw — errors are captured in `{ state: 'failed' }`.
   *
   * @param turn - The outbound canonical turn to send.
   * @param ctx - The adapter context for the current request.
   */
  send(
    turn: OddjobzConversationTurnPayload,
    ctx: AdapterContext,
  ): Promise<{
    state: 'delivered' | 'failed';
    surfaceMessageId?: string;
    error?: string;
  }>;
}

```
