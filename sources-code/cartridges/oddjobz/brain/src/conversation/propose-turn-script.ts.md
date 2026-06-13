---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/propose-turn-script.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.521393+00:00
---

# cartridges/oddjobz/brain/src/conversation/propose-turn-script.ts

```ts
/**
 * D-OJ-conv-propose-outbound — bun subprocess: store a proposed outbound turn.
 *
 * Wire protocol (from propose_turn_http.zig):
 *   stdin:  { conversationId: string, surface: string, bodyText: string,
 *             participantRole: string, recipientHandle: { kind: string, value: string },
 *             includeCustomerLink?: boolean, entityRef?: { kind: string, cellHash: string },
 *             quotedTurnId?: string }
 *   stdout: { ok: true,  turnId: string, state: 'proposed' }
 *         | { ok: false, error: 'db_error' }
 *
 * Architecture constraints (project memories):
 *   - No self-calls back into the brain HTTP/REPL
 *     (semantos_brain_single_threaded_reactor). This script connects
 *     directly to Postgres via DATABASE_URL — external IO, safe.
 *   - No AI calls (semantos_no_ai_in_substrate).
 *   - ESM imports use .js extensions for relative paths.
 *   - process.exit(0) at end is MANDATORY — postgres.js pool keeps the
 *     event loop alive otherwise (pool-linger bug).
 */

import { getDatabaseOrNull } from './db.js';
import type {
  OddjobzConversationTurnPayload,
  ConversationSurface,
  ParticipantRole,
  IdentityHandle,
} from './conversation-turn-patch.js';
import { sql } from 'drizzle-orm';

// ── Read stdin ────────────────────────────────────────────────────────────────

const stdinChunks: Buffer[] = [];
for await (const chunk of process.stdin) stdinChunks.push(chunk as Buffer);
const input = JSON.parse(Buffer.concat(stdinChunks).toString()) as {
  conversationId: string;
  surface: ConversationSurface;
  bodyText: string;
  participantRole: ParticipantRole;
  recipientHandle: IdentityHandle;
  includeCustomerLink?: boolean;
  entityRef?: { kind: 'job' | 'site' | 'customer' | 'lead'; cellHash: string };
  quotedTurnId?: string;
};

// ── Validate required fields ──────────────────────────────────────────────────

if (!input.conversationId || !input.surface || !input.bodyText || !input.participantRole || !input.recipientHandle) {
  process.stdout.write(JSON.stringify({ ok: false, error: 'missing_fields' }) + '\n');
  process.exit(0);
}

// ── Connect to DB ─────────────────────────────────────────────────────────────

const db = getDatabaseOrNull();
if (!db) {
  process.stdout.write(JSON.stringify({ ok: false, error: 'db_error' }) + '\n');
  process.exit(0);
}

// ── Generate turnId ───────────────────────────────────────────────────────────

const turnId = `turn-out-${crypto.randomUUID().replace(/-/g, '')}`;
const timestamp = Date.now();

// ── Construct payload ─────────────────────────────────────────────────────────

const turnPayload: OddjobzConversationTurnPayload = {
  turnId,
  conversationId: input.conversationId,
  ...(input.entityRef
    ? {
        entityRef: {
          kind: input.entityRef.kind as 'job' | 'site' | 'customer',
          cellHash: input.entityRef.cellHash,
        },
      }
    : {}),
  participantRole: input.participantRole,
  actorCertId: 'operator',
  surface: input.surface,
  direction: 'outbound',
  bodyText: input.bodyText,
  outboundState: 'proposed',
  recipientHandle: input.recipientHandle,
  ...(input.includeCustomerLink !== undefined
    ? { includeCustomerLink: input.includeCustomerLink }
    : {}),
  ...(input.quotedTurnId ? { quotedTurnId: input.quotedTurnId } : {}),
  correlationId: turnId,
  timestamp,
};

// ── Insert into sem_objects ───────────────────────────────────────────────────
// Raw SQL to match the prod schema — which has `vertical` and `type_hash`
// as required NOT NULL columns without defaults, and uses `created_by`
// (not `created_by_cert_id`). The @semantos/semantic-objects Drizzle schema
// diverges from the OJT NextJS-app-created prod schema, so we bypass Drizzle
// and write the columns that actually exist.
//
// type_hash = sha256('oddjobz.conversation.turn') — deterministic, stable.

try {
  await (db as any).execute(
    sql`INSERT INTO sem_objects
          (id, vertical, object_kind, type_hash, current_state_hash,
           payload, created_by, created_at, updated_at)
        VALUES
          (${turnId}, ${'oddjobz'}, ${'oddjobz.conversation.turn'},
           ${'3e98317d411eadb967a738007a4e5fe9b2e2d0b41670c0f21e81cc10d2fcda1d'}, ${''},
           ${JSON.stringify(turnPayload)}::jsonb,
           ${'operator'}, now(), now())
        ON CONFLICT (id) DO NOTHING`,
  );
  process.stdout.write(
    JSON.stringify({ ok: true, turnId, state: 'proposed' }) + '\n',
  );
} catch (err) {
  process.stderr.write(
    `[propose-turn-script] DB insert failed: ${err instanceof Error ? err.message : String(err)}\n`,
  );
  process.stdout.write(JSON.stringify({ ok: false, error: 'db_error' }) + '\n');
}

// Force exit: postgres.js holds the connection pool open (active socket) after
// all work is done, which prevents bun's event loop from draining naturally.
// Since this is a one-shot subprocess, a hard exit is correct — no cleanup needed.
process.exit(0);

```
