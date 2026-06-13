---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/tools/voice-note-intake.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.469385+00:00
---

# cartridges/oddjobz/brain/tools/voice-note-intake.ts

```ts
#!/usr/bin/env bun
/**
 * D-OJ-conv-voice-intake — voice note intake CLI.
 *
 * Phase 5 of OJT-UNIFIED-QUOTE-INVOICE-PLAN: wires the capture-time-bound
 * voice note path so operator voice notes recorded while viewing a specific
 * job are stored as ConversationTurns anchored to that job's entityRef.
 *
 * Called by the brain Zig handler for `POST /api/v1/voice-note`.
 *
 * Wire shape:
 *
 *     stdin  → {
 *                "transcript":      string,
 *                "entity_id":       string,   // 64-hex job/site/customer cellId
 *                "entity_kind":     "job"|"site"|"customer",
 *                "captured_at":     string,   // ISO-8601
 *                "duration_seconds"?: number,
 *                "recording_id"?:   string,   // dedup anchor
 *                "operator_cert_id"?: string,
 *                "data_dir":        string    // brain data directory
 *              }
 *     stdout → { "ok": true,  "turn_id": string }
 *            | { "ok": false, "error": string }
 *
 * Architecture: this CLI runs as a direct Bun child of the brain Zig
 * reactor (synchronous shell-out, like voice-extract.ts). It writes
 * the turn directly to Postgres via `makeSemObjectSink` from
 * `src/conversation/db.ts`. This is safe because Postgres is an
 * external service — there is NO call back into the brain's HTTP/REPL
 * surface (per `semantos_brain_single_threaded_reactor` memory: the
 * 2026-05-18 deadlock was an intake child calling the brain's REPL;
 * this CLI only talks to Postgres).
 *
 * When DATABASE_URL is unset the turn is dropped (no-op, ok:true
 * still returned so the operator isn't blocked; the jsonl audit trail
 * captures the attempt).
 */

import { readFileSync, appendFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { makeVoiceAdapter } from '../src/surface-adapters/voice.js';
import {
  getDatabaseOrNull,
  makeSemObjectSink,
  makeOddjobzSinks,
} from '../src/conversation/db.js';
import type {
  OddjobzConversationTurnPayload,
  BelongsToEntityRelation,
} from '../src/conversation/conversation-turn-patch.js';
import type { AdapterContext } from '../src/surface-adapters/contract.js';

// ── Input ─────────────────────────────────────────────────────────────────────

interface VoiceNoteInput {
  transcript: string;
  entity_id: string;
  entity_kind: 'job' | 'site' | 'customer';
  captured_at: string;
  duration_seconds?: number;
  recording_id?: string;
  operator_cert_id?: string;
  data_dir: string;
}

function readInput(): VoiceNoteInput {
  const raw = readFileSync('/dev/stdin', 'utf8').trim();
  return JSON.parse(raw) as VoiceNoteInput;
}

function validateInput(input: unknown): input is VoiceNoteInput {
  if (!input || typeof input !== 'object') return false;
  const p = input as Record<string, unknown>;
  if (typeof p.transcript !== 'string' || !p.transcript) return false;
  if (typeof p.entity_id !== 'string' || !p.entity_id) return false;
  if (
    p.entity_kind !== 'job' &&
    p.entity_kind !== 'site' &&
    p.entity_kind !== 'customer'
  )
    return false;
  if (typeof p.captured_at !== 'string' || !p.captured_at) return false;
  if (typeof p.data_dir !== 'string' || !p.data_dir) return false;
  return true;
}

// ── Audit log ─────────────────────────────────────────────────────────────────

function appendAuditLog(dataDir: string, record: Record<string, unknown>): void {
  try {
    const oddjobzDir = join(dataDir, '..', 'oddjobz');
    mkdirSync(oddjobzDir, { recursive: true });
    const logPath = join(oddjobzDir, 'voice-note.log');
    appendFileSync(
      logPath,
      JSON.stringify({ ts: new Date().toISOString(), ...record }) + '\n',
      'utf8',
    );
  } catch {
    /* best-effort */
  }
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  let input: unknown;
  try {
    input = readInput();
  } catch (e) {
    process.stdout.write(
      JSON.stringify({ ok: false, error: 'input_parse_failed' }),
    );
    process.exit(0);
  }

  if (!validateInput(input)) {
    process.stdout.write(
      JSON.stringify({
        ok: false,
        error: 'missing_required_fields',
        hint: 'transcript, entity_id, entity_kind, captured_at, data_dir',
      }),
    );
    process.exit(0);
  }

  // Build the VoiceNotePayload for the adapter (camelCase per the adapter's
  // validated payload contract).
  const voicePayload = {
    transcript: input.transcript,
    entityId: input.entity_id,
    entityKind: input.entity_kind,
    capturedAt: input.captured_at,
    ...(typeof input.duration_seconds === 'number'
      ? { durationSeconds: input.duration_seconds }
      : {}),
    ...(input.recording_id ? { recordingId: input.recording_id } : {}),
  };

  // Build a minimal AdapterContext: operatorCert from stdin (or env),
  // submitTurn wired to direct Postgres write when DATABASE_URL is set.
  const certId =
    input.operator_cert_id ||
    process.env.ODDJOBZ_AGENT_CERT_ID ||
    undefined;

  let submittedTurnId: string | null = null;

  const db = getDatabaseOrNull();
  const semObjectSink = db ? makeSemObjectSink(db) : null;
  const oddjobzSinks = db ? makeOddjobzSinks(db) : null;

  // Build a minimal AdapterContext.  The voice adapter reads only
  // ctx.operatorCert?.certId (never calls resolveEntity — entity is
  // known at capture time). We satisfy the interface with a minimal shim.
  const ctx: AdapterContext = {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    operatorCert: { certId: certId ?? 'operator' } as any,
    resolveEntity: async () => null,
    submitTurn: async (turn: OddjobzConversationTurnPayload): Promise<void> => {
      submittedTurnId = turn.turnId;
      // Both DB writes are best-effort: if Postgres is unreachable (e.g.
      // DATABASE_URL set but no Postgres process on this VPS), the turn
      // is dropped silently.  The operator gets a fast 201 and the audit
      // log records the attempt.  The connect_timeout:5 on the postgres
      // client caps the hang to 5s max even if the TCP connection stalls.
      if (semObjectSink) {
        try {
          await semObjectSink(turn);
        } catch {
          /* best-effort — DB unavailable; turn audited below */
        }
      }
      // Write BELONGS_TO_ENTITY relation so the turn is reachable by entityRef
      // queries (same sink used by the widget intake path).
      if (oddjobzSinks && turn.entityRef) {
        try {
          const rel: BelongsToEntityRelation = {
            kind: 'BELONGS_TO_ENTITY',
            turnId: turn.turnId,
            entityCellHash: turn.entityRef.cellHash,
            entityKind: turn.entityRef.kind as 'job' | 'site' | 'customer',
          };
          await oddjobzSinks.relationSink(rel);
        } catch {
          /* best-effort — turn already persisted */
        }
      }
    },
  };

  const adapter = makeVoiceAdapter();

  try {
    const turns = await adapter.ingest(voicePayload, ctx);

    appendAuditLog(input.data_dir, {
      entityId: input.entity_id,
      entityKind: input.entity_kind,
      turnCount: turns.length,
      turnId: submittedTurnId,
    });

    process.stdout.write(
      JSON.stringify({
        ok: true,
        turn_id: submittedTurnId ?? turns[0]?.turnId ?? '',
      }),
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    appendAuditLog(input.data_dir, {
      error: msg,
      entityId: input.entity_id,
    });
    process.stdout.write(JSON.stringify({ ok: false, error: msg }));
  }
}

main().catch((e) => {
  process.stderr.write(
    `voice-note-intake fatal: ${e instanceof Error ? e.message : String(e)}\n`,
  );
  process.stdout.write(JSON.stringify({ ok: false, error: 'fatal' }));
  process.exit(0);
});

```
