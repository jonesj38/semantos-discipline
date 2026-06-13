---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/surface-adapters/voice.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.508449+00:00
---

# cartridges/oddjobz/brain/src/surface-adapters/voice.ts

```ts
/**
 * D-OJ-conv-voice-intake — voice surface adapter (capture-time-bound path only).
 *
 * Implements `ConversationSurfaceAdapter` for `surface='voice'` — the
 * operator voice-note intake path.
 *
 * ## Scope: capture-time-bound only
 *
 * The operator taps the voice-note button while viewing a specific job/site —
 * the entity is already known at capture time, so the turn is anchored
 * immediately on ingest. The payload carries `entityId` + `entityKind`
 * (set by the PWA when the note is captured), and the adapter maps them
 * directly onto `entityRef` on the canonical turn.
 *
 * The INFERRED-FROM-CONTENT path (free-form voice-to-self where the entity
 * is figured out later from transcript content) is DEFERRED — NOT built here.
 *
 * ## Voice notes are always inbound
 *
 * Operator voice notes are always the operator speaking INTO the system
 * (they are the note-taker, not a reply target). `direction='inbound'`,
 * `participantRole='operator'`.
 *
 * The `send()` method is a no-op stub: the voice surface does not support
 * outbound delivery. It returns `{ state: 'failed' }` and MUST NOT throw.
 *
 * ## Identity binding (§6.2)
 *
 * Operator identity is bound from `ctx.operatorCert.certId` (L2 cert-bound,
 * per the XOR invariant — no `identityHandle` for cert-bound operator turns).
 * `identityTier = 'L2'`, `participantRole = 'operator'`.
 *
 * ## conversationId
 *
 * Derived from `entityId + entityKind` using a stable hash so all voice notes
 * captured against the same entity share the same `conversationId`. This
 * matches the intent of voice notes as a running log per entity.
 *
 * ## correlationId
 *
 * When `recordingId` is present in the payload it becomes the `correlationId`
 * (stable, for deduplication — same recording id → same correlationId). When
 * absent, `turnId` is used as the fallback correlationId.
 *
 * The spec also asks for `recordingId` → `turn.correlationId` (VI7). We store
 * it there directly: `correlationId = recordingId ?? turnId`.
 *
 * ## No LLM calls
 *
 * Per `semantos_no_ai_in_substrate`: this adapter is pure protocol↔canonical
 * mapping. No LLM calls anywhere.
 *
 * ## No live-wiring
 *
 * The composition-root wiring (PWA endpoint, entity resolver, actual storage
 * configuration) is a separate follow-up. This module ships the adapter +
 * tests only.
 */

import { randomUUID, createHash } from 'node:crypto';
import type {
  ConversationSurfaceAdapter,
  AdapterContext,
} from './contract.js';
import type { OddjobzConversationTurnPayload } from '../conversation/conversation-turn-patch.js';

// ── VoiceNotePayload ──────────────────────────────────────────────────────────

/**
 * The native payload shape for a capture-time-bound voice note.
 *
 * Arrives at `ingest(payload, ctx)` from the PWA when the operator taps
 * the voice-note button while viewing a specific job/site — the entity is
 * already known at capture time.
 */
export interface VoiceNotePayload {
  /** Transcript text produced by the voice-extract script (already transcribed upstream). */
  transcript: string;
  /** The entity this voice note was captured against (known at capture time). */
  entityId: string;
  entityKind: 'job' | 'site' | 'customer';
  /** ISO-8601 timestamp when the note was recorded. */
  capturedAt: string;
  /** Optional: duration in seconds. */
  durationSeconds?: number;
  /** Optional: a unique id for this recording (for deduplication). */
  recordingId?: string;
}

// ── Runtime validation ────────────────────────────────────────────────────────

/**
 * Validate the inbound payload and return a typed `VoiceNotePayload`,
 * or `null` when the payload fails validation.
 *
 * Voice notes have only one mandatory validation outcome: `null` on failure
 * (the adapter returns `[]` without throwing — see VI4). Fields that must be
 * present and non-empty strings: `transcript`, `entityId`, `entityKind`,
 * `capturedAt`.
 */
function validateVoicePayload(payload: unknown): VoiceNotePayload | null {
  if (!payload || typeof payload !== 'object') return null;
  const p = payload as Record<string, unknown>;

  const transcript = typeof p.transcript === 'string' ? p.transcript : null;
  const entityId = typeof p.entityId === 'string' ? p.entityId : null;
  const entityKind = p.entityKind;
  const capturedAt = typeof p.capturedAt === 'string' ? p.capturedAt : null;

  if (transcript === null) return null;
  if (!entityId) return null;
  if (
    entityKind !== 'job' &&
    entityKind !== 'site' &&
    entityKind !== 'customer'
  )
    return null;
  if (!capturedAt) return null;

  return {
    transcript,
    entityId,
    entityKind: entityKind as 'job' | 'site' | 'customer',
    capturedAt,
    durationSeconds:
      typeof p.durationSeconds === 'number' ? p.durationSeconds : undefined,
    recordingId:
      typeof p.recordingId === 'string' && p.recordingId
        ? p.recordingId
        : undefined,
  };
}

// ── conversationId derivation ─────────────────────────────────────────────────

/**
 * Derive a stable conversation id for all voice notes captured against
 * the same entity. All notes for `entityKind:entityId` share this id.
 *
 * Namespaced to `'voice:' + entityKind + ':' + entityId` using SHA-256.
 */
function deriveVoiceConversationId(
  entityKind: string,
  entityId: string,
): string {
  return createHash('sha256')
    .update(`voice:${entityKind}:${entityId}`)
    .digest('hex');
}

// ── makeVoiceAdapter ──────────────────────────────────────────────────────────

/**
 * Create a `ConversationSurfaceAdapter` for `surface='voice'`.
 *
 * Capture-time-bound path only: the entity is known at ingest time and is
 * mapped directly onto `entityRef` on the canonical turn.
 *
 * Usage:
 * ```ts
 * const adapter = makeVoiceAdapter();
 *
 * const turns = await adapter.ingest(voiceNotePayload, ctx);
 * // → one turn with surface='voice', participantRole='operator',
 * //   direction='inbound', entityRef set from payload.entityId + entityKind
 *
 * // send() always returns { state: 'failed' } — voice is inbound only.
 * const result = await adapter.send(turn, ctx);
 * // → { state: 'failed', error: '...' }
 * ```
 *
 * The adapter is STATELESS; a single instance can serve many ingests.
 */
export function makeVoiceAdapter(): ConversationSurfaceAdapter {
  return {
    surface: 'voice',

    // ── ingest ───────────────────────────────────────────────────────────────
    //
    // Maps a VoiceNotePayload to one canonical inbound turn.
    //
    // Capture-time-bound: entity is known at ingest time → entityRef always
    // set when the payload is valid (no §6.3 lead-on-contact needed here).
    //
    // One voice note → one inbound turn:
    //   surface='voice', participantRole='operator', direction='inbound'
    //   actorCertId from ctx.operatorCert.certId (L2 cert-bound; XOR invariant
    //     — no identityHandle for cert-bound operator turns)
    //   entityRef = { kind: entityKind, cellHash: entityId }
    //   conversationId = sha256('voice:' + entityKind + ':' + entityId)
    //   turnId = crypto.randomUUID()
    //   correlationId = recordingId ?? turnId  (VI7)
    //   timestamp = Date.now()
    //
    // Returns [] (with no throw) when the payload fails validation (VI4).
    // Calls ctx.submitTurn(turn) before returning for valid payloads (VI6).
    async ingest(
      payload: unknown,
      ctx: AdapterContext,
    ): Promise<OddjobzConversationTurnPayload[]> {
      // Runtime validation — returns null on failure.
      const p = validateVoicePayload(payload);
      if (!p) {
        // Invalid payload: return [] without throwing (VI4).
        return [];
      }

      const turnId = randomUUID();
      const conversationId = deriveVoiceConversationId(p.entityKind, p.entityId);

      // correlationId: recordingId when present (deduplication anchor — VI7),
      // fallback to turnId so the field is always populated.
      const correlationId = p.recordingId ?? turnId;

      const timestamp = Date.now();

      // L2 cert-bound operator identity (XOR invariant: no identityHandle).
      // If certId is absent (test / early context), we leave actorCertId
      // undefined rather than fabricating — mirrors the email adapter §6.2 note.
      const certId = ctx.operatorCert?.certId || undefined;

      const turn: OddjobzConversationTurnPayload = {
        turnId,
        conversationId,
        participantRole: 'operator',
        ...(certId ? { actorCertId: certId } : {}),
        surface: 'voice',
        direction: 'inbound',
        bodyText: p.transcript,
        entityRef: {
          kind: p.entityKind,
          // Capture-time-bound: entityId IS the cell hash / entity reference
          // supplied by the PWA (the UI already resolved the entity when the
          // operator was viewing that job/site). No further lookup needed.
          cellHash: p.entityId,
        },
        correlationId,
        timestamp,
      };

      await ctx.submitTurn(turn);
      return [turn];
    },

    // ── send ─────────────────────────────────────────────────────────────────
    //
    // Voice notes are always inbound (operator → system). The voice surface
    // does not support outbound delivery.
    //
    // Returns { state: 'failed' } always. MUST NOT throw (§6.1 contract).
    async send(
      _turn: OddjobzConversationTurnPayload,
      _ctx: AdapterContext,
    ): Promise<{
      state: 'delivered' | 'failed';
      surfaceMessageId?: string;
      error?: string;
    }> {
      return {
        state: 'failed',
        error: 'voice surface does not support outbound',
      };
    },
  };
}

```
