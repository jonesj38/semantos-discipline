---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/surface-adapters/import.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.508088+00:00
---

# cartridges/oddjobz/brain/src/surface-adapters/import.ts

```ts
/**
 * D-OJ-conv-historical-import — historical CSV / IG legacy export surface adapter.
 *
 * Implements `ConversationSurfaceAdapter` for `surface='import'` — the read-only
 * historical conversation ingestion path.
 *
 * ## Scope
 *
 * This adapter maps historical message records (CSV exports, IG legacy exports,
 * or similar batch sources) to canonical `OddjobzConversationTurnPayload[]`.
 * One record → one canonical turn.
 *
 * `send()` MUST NOT throw and always returns `{ state: 'failed' }` — the import
 * surface is read-only by design (no outbound channel exists for historical data).
 *
 * ## §13.9 auto-lead policy
 *
 * When a historical message's contact handle cannot be resolved to an existing
 * entity via `ctx.resolveEntity`, the turn is still submitted (§6.3
 * lead-on-contact). `entityRef` stays absent; the operator can re-anchor later.
 * This matches the live inbound path (widget.ts / sms.ts lead-on-contact).
 *
 * ## Conversation id derivation
 *
 * Stable SHA-256 of `'import:' + (contactHandle?.value ?? importBatchId ?? 'unknown') + ':' + source`
 * so all messages in the same contact/source thread share a conversationId.
 * Computed using Node.js `crypto.createHash('sha256')`.
 *
 * ## Turn id
 *
 * `crypto.randomUUID()` per turn (or injected `generateId()` dep for tests).
 * Historical imports don't have a canonical stable id source like a Twilio SID,
 * so random UUIDs are appropriate. Deduplication is the caller's responsibility
 * (via `externalMessageId` → `correlationId`).
 *
 * ## Participant role / direction
 *
 * - Inbound (from customer/contact): `participantRole='customer'`, `direction='inbound'`.
 *   If `contactHandle` is present: `identityHandle = { tier: 'L1', value: handle.value }`
 *   mapped to `{ kind: handle.kind, value: handle.value }`.
 *   If absent: `identityHandle = { kind: 'free', value: 'unknown:' + index }` (L0 fallback).
 * - Outbound (from operator/business): `participantRole='operator'`, `direction='outbound'`.
 *   No `identityHandle` for operator turns (no L0/L1 handle for historical operator messages).
 *
 * ## No LLM calls
 *
 * Per `semantos_no_ai_in_substrate`: pure protocol↔canonical mapping.
 *
 * ## No sync-call back into the brain
 *
 * Per `semantos_brain_single_threaded_reactor`: `ctx.submitTurn` routes through
 * the detached-grandchild submitter (wired by the caller).
 */

import { randomUUID, createHash } from 'node:crypto';
import type {
  OddjobzConversationTurnPayload,
} from '../conversation/conversation-turn-patch.js';
import type {
  ConversationSurfaceAdapter,
  AdapterContext,
} from './contract.js';

// ── HistoricalMessagePayload ──────────────────────────────────────────────────

/**
 * The native payload shape for the import surface adapter.
 *
 * Covers CSV exports, IG legacy exports, and similar batch sources.
 * Each entry in `messages` becomes one canonical turn.
 */
export interface HistoricalMessagePayload {
  /** Source channel identifier: 'csv', 'ig_export', or similar. */
  readonly source: string;
  /** Ordered message rows (chronological order recommended; not enforced). */
  readonly messages: ReadonlyArray<{
    /** ISO-8601 string or unix milliseconds timestamp. */
    readonly timestamp: string | number;
    /** 'inbound' = from customer/contact; 'outbound' = from operator/business. */
    readonly direction: 'inbound' | 'outbound';
    /** Message body text. */
    readonly body: string;
    /** Contact identifier for entity resolution (inbound messages). */
    readonly contactHandle?: { readonly kind: 'phone' | 'email'; readonly value: string };
    /** Optional per-message id for deduplication (mapped to correlationId). */
    readonly externalMessageId?: string;
  }>;
  /** Import batch id — used as a fallback conversationId anchor and correlationId prefix. */
  readonly importBatchId?: string;
}

// ── ImportAdapterDeps ─────────────────────────────────────────────────────────

/**
 * Deps injected at construction time via `makeImportAdapter`.
 */
export interface ImportAdapterDeps {
  /**
   * Generate a unique id for turn ids.
   * Default: `randomUUID()`. Injected for deterministic tests.
   */
  readonly generateId?: () => string;

  /**
   * Current time in unix-millis (used as fallback when timestamp parse fails).
   * Default: `Date.now()`. Injected for deterministic tests.
   */
  readonly now?: () => number;
}

// ── Conversation id derivation ────────────────────────────────────────────────
//
// Stable SHA-256 of 'import:' + anchor + ':' + source.
// Same anchor + source → same conversationId (all messages in one thread share it).

function deriveConversationId(anchor: string, source: string): string {
  return createHash('sha256')
    .update(`import:${anchor}:${source}`)
    .digest('hex');
}

// ── Timestamp parsing ─────────────────────────────────────────────────────────

function parseTimestamp(value: string | number, fallback: number): number {
  if (typeof value === 'number') return value;
  // Try ISO-8601 parse.
  const d = new Date(value);
  const ms = d.getTime();
  return isNaN(ms) ? fallback : ms;
}

// ── makeImportAdapter ─────────────────────────────────────────────────────────

/**
 * Create a `ConversationSurfaceAdapter` for `surface='import'`.
 *
 * Usage:
 * ```ts
 * const adapter = makeImportAdapter();
 *
 * const turns = await adapter.ingest(payload, ctx);
 * // → OddjobzConversationTurnPayload[] (one per message row)
 *
 * // send() always fails — import is read-only.
 * const result = await adapter.send(turn, ctx);
 * // → { state: 'failed', error: 'import surface does not support outbound' }
 * ```
 *
 * The adapter is STATELESS; a single instance can serve many ingests.
 */
export function makeImportAdapter(deps: ImportAdapterDeps = {}): ConversationSurfaceAdapter {
  const generateId = deps.generateId ?? (() => randomUUID());
  const now = deps.now ?? (() => Date.now());

  return {
    surface: 'import',

    // ── ingest ───────────────────────────────────────────────────────────────
    //
    // Maps a HistoricalMessagePayload to one canonical turn per message row.
    // Calls `ctx.submitTurn(turn)` for each turn before returning.
    //
    // §13.9 auto-lead: if ctx.resolveEntity returns null, the turn is still
    // submitted without entityRef. The operator can re-anchor later.
    async ingest(
      payload: unknown,
      ctx: AdapterContext,
    ): Promise<OddjobzConversationTurnPayload[]> {
      if (!payload || typeof payload !== 'object') {
        throw new Error('import.ingest: payload must be an object');
      }

      const p = payload as HistoricalMessagePayload;

      if (typeof p.source !== 'string' || !p.source) {
        throw new Error('import.ingest: payload.source must be a non-empty string');
      }

      if (!Array.isArray(p.messages)) {
        throw new Error('import.ingest: payload.messages must be an array');
      }

      // Empty messages — valid; return early.
      if (p.messages.length === 0) {
        return [];
      }

      const nowMs = now();
      const turns: OddjobzConversationTurnPayload[] = [];

      for (let i = 0; i < p.messages.length; i++) {
        const msg = p.messages[i];

        // ── Conversation id ─────────────────────────────────────────────────
        //
        // Anchor: the contact handle value if present, else the importBatchId,
        // else 'unknown'. All messages in the same batch/thread share this anchor,
        // giving them the same conversationId.
        const anchor = msg.contactHandle?.value ?? p.importBatchId ?? 'unknown';
        const conversationId = deriveConversationId(anchor, p.source);

        // ── Turn id + correlation id ────────────────────────────────────────
        const turnId = generateId();
        const correlationId =
          msg.externalMessageId ??
          `${p.importBatchId ?? 'batch'}:${i}`;

        // ── Timestamp ───────────────────────────────────────────────────────
        const timestamp = parseTimestamp(msg.timestamp, nowMs);

        // ── Participant role + direction + identity ──────────────────────────
        const direction = msg.direction;
        const isInbound = direction === 'inbound';

        let participantRole: OddjobzConversationTurnPayload['participantRole'];
        let identityHandle: OddjobzConversationTurnPayload['identityHandle'];

        if (isInbound) {
          participantRole = 'customer';
          if (msg.contactHandle) {
            // L1 identity: phone or email handle from the contact.
            identityHandle = {
              kind: msg.contactHandle.kind,
              value: msg.contactHandle.value,
            };
          } else {
            // L0 fallback: no contact info available.
            identityHandle = {
              kind: 'free',
              value: `unknown:${i}`,
            };
          }
        } else {
          // Outbound (operator). No identityHandle for historical operator turns
          // (no L0/L1 handle for historical operator messages — XOR invariant).
          participantRole = 'operator';
        }

        // ── Entity resolution (§13.9 / §6.3) ───────────────────────────────
        //
        // Only for inbound turns. If the contact resolves to an existing entity,
        // populate entityRef. If not, the turn is submitted without entityRef
        // (lead-on-contact — operator re-anchors later).
        let entityRef: OddjobzConversationTurnPayload['entityRef'];
        if (isInbound && msg.contactHandle) {
          const resolved = await ctx.resolveEntity(msg.contactHandle);
          if (resolved) {
            entityRef = { kind: resolved.kind, cellHash: resolved.cellHash };
          }
          // null → §13.9 auto-lead; entityRef stays absent.
        }

        // ── Assemble the canonical turn ─────────────────────────────────────
        const turn: OddjobzConversationTurnPayload = {
          turnId,
          conversationId,
          participantRole,
          ...(identityHandle ? { identityHandle } : {}),
          surface: 'import',
          direction,
          bodyText: msg.body,
          correlationId,
          timestamp,
          ...(entityRef ? { entityRef } : {}),
        };

        await ctx.submitTurn(turn);
        turns.push(turn);
      }

      return turns;
    },

    // ── send ─────────────────────────────────────────────────────────────────
    //
    // Import is a read-only surface — historical data cannot be re-sent.
    // MUST NOT throw (per §6.1 contract).
    async send(
      _turn: OddjobzConversationTurnPayload,
      _ctx: AdapterContext,
    ): Promise<{ state: 'delivered' | 'failed'; surfaceMessageId?: string; error?: string }> {
      return {
        state: 'failed',
        error: 'import surface does not support outbound',
      };
    },
  };
}

```
