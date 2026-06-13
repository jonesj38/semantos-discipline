---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/conversation-turns-query-script.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.515673+00:00
---

# cartridges/oddjobz/brain/src/conversation/conversation-turns-query-script.ts

```ts
/**
 * D-OJ-conv-turns-query — bun subprocess: query conversation turns from sem_objects.
 *
 * Wire protocol (from conv_turns_query_http.zig / repl.zig):
 *   stdin:  { entityRef?: string, conversationId?: string,
 *             limit?: number, before?: number,
 *             direction?: 'inbound' | 'outbound',
 *             outboundState?: string }
 *   stdout: { ok: true,  turns: OddjobzConversationTurnPayload[] }
 *         | { ok: false, error: 'db_error' }
 *
 * Architecture constraints:
 *   - No self-calls into the brain HTTP/REPL (single-threaded reactor deadlock).
 *   - No AI calls (semantos_no_ai_in_substrate).
 *   - process.exit(0) mandatory — postgres.js pool holds the event loop open.
 */

import { getDatabaseOrNull } from './db.js';
import type { OddjobzConversationTurnPayload } from './conversation-turn-patch.js';
import { sql } from 'drizzle-orm';

// ── Read stdin ────────────────────────────────────────────────────────────────

const stdinChunks: Buffer[] = [];
for await (const chunk of process.stdin) stdinChunks.push(chunk as Buffer);
const input = JSON.parse(Buffer.concat(stdinChunks).toString()) as {
  entityRef?: string;
  conversationId?: string;
  limit?: number;
  before?: number;
  direction?: 'inbound' | 'outbound';
  outboundState?: string;
};

// ── Connect to DB ─────────────────────────────────────────────────────────────

const db = getDatabaseOrNull();
if (!db) {
  process.stdout.write(JSON.stringify({ ok: false, error: 'db_error' }) + '\n');
  process.exit(0);
}

// ── Build and run query ───────────────────────────────────────────────────────

const limit = Math.min(input.limit ?? 50, 200);

try {
  // Build the WHERE clauses dynamically using tagged-template sql.
  // drizzle's sql`` operator handles parameterisation; we compose clauses
  // by concatenating sql fragments (the only safe way without Drizzle schema).
  let query = sql`
    SELECT payload
    FROM sem_objects
    WHERE object_kind = ${'oddjobz.conversation.turn'}
  `;

  if (input.entityRef) {
    query = sql`${query} AND payload->'entityRef'->>'cellHash' = ${input.entityRef}`;
  }
  if (input.conversationId) {
    query = sql`${query} AND payload->>'conversationId' = ${input.conversationId}`;
  }
  if (input.direction) {
    query = sql`${query} AND payload->>'direction' = ${input.direction}`;
  }
  if (input.outboundState) {
    query = sql`${query} AND payload->>'outboundState' = ${input.outboundState}`;
  }
  if (input.before !== undefined) {
    // before is a ms-epoch timestamp; cast to bigint for comparison.
    query = sql`${query} AND (payload->>'timestamp')::bigint < ${input.before}`;
  }

  query = sql`${query} ORDER BY (payload->>'timestamp')::bigint ASC LIMIT ${limit}`;

  const rows = await (db as any).execute(query);

  const turns: OddjobzConversationTurnPayload[] = (rows as any[]).map(
    (row: { payload: OddjobzConversationTurnPayload }) => row.payload,
  );

  process.stdout.write(JSON.stringify({ ok: true, turns }) + '\n');
} catch (err) {
  process.stderr.write(
    `[conv-turns-query-script] query failed: ${err instanceof Error ? err.message : String(err)}\n`,
  );
  process.stdout.write(JSON.stringify({ ok: false, error: 'db_error' }) + '\n');
}

process.exit(0);

```
