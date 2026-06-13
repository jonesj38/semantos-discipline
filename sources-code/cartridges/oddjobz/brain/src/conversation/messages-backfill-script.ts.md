---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/messages-backfill-script.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.522292+00:00
---

# cartridges/oddjobz/brain/src/conversation/messages-backfill-script.ts

```ts
/**
 * D-OJ-conv-messages-backfill — one-shot CLI script.
 *
 * Reads `messages.jsonl` line by line and backfills all historical
 * email/Gmail turns as proper canonical `oddjobz.conversation.turn`
 * sem_objects rows.
 *
 * Usage:
 *   bun run messages-backfill-script.ts [--jsonl-path <path>] [--dry-run] [--channel email|all]
 *
 * Options:
 *   --jsonl-path <path>   Path to messages.jsonl (default: ~/.semantos/data/oddjobz/messages.jsonl;
 *                         SEMANTOS_MESSAGES_JSONL env var overrides, then --jsonl-path flag)
 *   --dry-run             Print what WOULD be inserted — no DB writes
 *   --channel email       Only process email/gmail channel rows (default)
 *   --channel all         Process ALL channels (email + meta + widget — for completeness)
 *
 * Wire protocol (stdout):
 *   { ok: true, processed: N, inserted: I, skipped: S, errors: E }
 *
 * Architecture constraints (project memories):
 *   - No self-calls into the brain HTTP/REPL (semantos_brain_single_threaded_reactor)
 *   - No AI calls (semantos_no_ai_in_substrate)
 *   - process.exit(0) at end is MANDATORY — postgres.js pool-linger bug
 */

import { createReadStream, existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import { getDatabaseOrNull, ODDJOBZ_TURN_OBJECT_KIND } from './db.js';
import { mapMessagePatchToCanonical } from './legacy-ingest-bridge.js';
import type { OddjobzMessagePatch } from '@semantos/legacy-ingest';
import { sql } from 'drizzle-orm';

// ── Prod-schema constants ─────────────────────────────────────────────────────
// The production sem_objects table was created by the OJT NextJS app and
// requires `vertical` (NOT NULL, no default) and `type_hash` (NOT NULL, no
// default). The Drizzle ORM schema in @semantos/semantic-objects omits these
// columns, so createObject() fails on prod. We use raw SQL here instead.
//
// type_hash = sha256('oddjobz.conversation.turn') — deterministic, stable.
const ODDJOBZ_VERTICAL = 'oddjobz';
const ODDJOBZ_TURN_TYPE_HASH = '3e98317d411eadb967a738007a4e5fe9b2e2d0b41670c0f21e81cc10d2fcda1d';

// ── Arg parsing ───────────────────────────────────────────────────────────────

function parseArgs(argv: string[]): {
  jsonlPath: string;
  dryRun: boolean;
  channel: 'email' | 'all';
} {
  const args = argv.slice(2); // strip 'bun' + script name

  let jsonlPath =
    process.env.SEMANTOS_MESSAGES_JSONL ??
    join(
      process.env.SEMANTOS_HOME ?? join(homedir(), '.semantos'),
      'data',
      'oddjobz',
      'messages.jsonl',
    );
  let dryRun = false;
  let channel: 'email' | 'all' = 'email';

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--jsonl-path' && args[i + 1]) {
      jsonlPath = args[++i];
    } else if (args[i] === '--dry-run') {
      dryRun = true;
    } else if (args[i] === '--channel' && args[i + 1]) {
      const val = args[++i];
      if (val === 'all') channel = 'all';
      else channel = 'email';
    }
  }

  return { jsonlPath, dryRun, channel };
}

// ── Channel filter ────────────────────────────────────────────────────────────

function shouldProcess(patch: OddjobzMessagePatch, channelFilter: 'email' | 'all'): boolean {
  if (channelFilter === 'all') return true;
  return patch.channel === 'email' || patch.channel === 'gmail';
}

// ── Idempotency check ─────────────────────────────────────────────────────────

/**
 * Returns true if a `sem_objects` row with objectKind='oddjobz.conversation.turn'
 * and `payload->>'correlationId' = correlationId` already exists.
 *
 * Used as the idempotency gate: we skip rows that are already persisted
 * (safe to re-run the backfill multiple times).
 */
async function isTurnAlreadyPersisted(db: NonNullable<ReturnType<typeof getDatabaseOrNull>>, correlationId: string): Promise<boolean> {
  // Use a raw SQL query on the sem_objects JSONB payload column.
  // The drizzle `sql` tag returns a result we can inspect.
  const result = await (db as any).execute(
    sql`SELECT id FROM sem_objects WHERE object_kind = ${ODDJOBZ_TURN_OBJECT_KIND} AND payload->>'correlationId' = ${correlationId} LIMIT 1`,
  );
  // drizzle-orm/postgres-js returns { rows: [...] } (postgres.js style)
  // drizzle-orm/pglite returns an array directly
  const rows: unknown[] = Array.isArray(result) ? result : (result?.rows ?? []);
  return rows.length > 0;
}

// ── Main ──────────────────────────────────────────────────────────────────────

const { jsonlPath, dryRun, channel } = parseArgs(process.argv);

if (!existsSync(jsonlPath)) {
  process.stderr.write(
    `[backfill] messages.jsonl not found at: ${jsonlPath}\n` +
      `  Set SEMANTOS_MESSAGES_JSONL or pass --jsonl-path <path>\n`,
  );
  process.stdout.write(JSON.stringify({ ok: false, error: 'jsonl_not_found', path: jsonlPath }) + '\n');
  process.exit(0);
}

// Resolve DB — skip if not available (unless --dry-run, which doesn't need it).
const db = getDatabaseOrNull();
if (!dryRun && !db) {
  process.stderr.write(
    `[backfill] DATABASE_URL is not set. Run with --dry-run to preview without DB, ` +
      `or set DATABASE_URL to a live Postgres connection.\n`,
  );
  process.stdout.write(JSON.stringify({ ok: false, error: 'no_database_url' }) + '\n');
  process.exit(0);
}

// (sinks factory not used here — we write with raw SQL for prod-schema compat)

let processed = 0;
let inserted = 0;
let skipped = 0;
let errors = 0;

// Count total lines for progress reporting (pass 1: fast scan).
// For large files we use a readline pass; small files fit in memory fine.
let total = 0;
{
  const rl = createInterface({
    input: createReadStream(jsonlPath),
    crlfDelay: Infinity,
  });
  for await (const _line of rl) total++;
}

// Pass 2: process each line.
const rl = createInterface({
  input: createReadStream(jsonlPath),
  crlfDelay: Infinity,
});

for await (const line of rl) {
  const trimmed = line.trim();
  if (!trimmed) continue;

  let patch: OddjobzMessagePatch;
  try {
    patch = JSON.parse(trimmed) as OddjobzMessagePatch;
    if (patch.schema !== 'oddjobz.message.v1') continue; // skip unrecognised rows
  } catch {
    // Malformed JSON — skip silently
    continue;
  }

  processed++;

  // Channel filter
  if (!shouldProcess(patch, channel)) {
    skipped++;
    continue;
  }

  // Map to canonical
  const turn = mapMessagePatchToCanonical(patch);
  if (!turn) {
    skipped++;
    continue;
  }

  if (dryRun) {
    process.stderr.write(
      `[backfill] DRY-RUN would insert: turnId=${turn.turnId} correlationId=${turn.correlationId} surface=${turn.surface} role=${turn.participantRole}\n`,
    );
    inserted++;
  } else {
    // Idempotency check
    try {
      const alreadyExists = await isTurnAlreadyPersisted(db!, turn.correlationId);
      if (alreadyExists) {
        skipped++;
        continue;
      }
    } catch (err) {
      process.stderr.write(
        `[backfill] idempotency check error for correlationId=${turn.correlationId}: ` +
          `${err instanceof Error ? err.message : String(err)}\n`,
      );
      errors++;
      continue;
    }

    // Insert — raw SQL to match prod schema (vertical + type_hash required).
    try {
      await (db as any).execute(
        sql`INSERT INTO sem_objects
              (id, vertical, object_kind, type_hash, current_state_hash,
               payload, created_by, created_at, updated_at)
            VALUES
              (${turn.turnId}, ${ODDJOBZ_VERTICAL}, ${ODDJOBZ_TURN_OBJECT_KIND},
               ${ODDJOBZ_TURN_TYPE_HASH}, ${''},
               ${JSON.stringify(turn)}::jsonb,
               ${turn.actorCertId ?? null}, now(), now())
            ON CONFLICT (id) DO NOTHING`,
      );
      inserted++;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      // Unique constraint = idempotent replay (race between check and insert)
      if (
        msg.includes('duplicate key') ||
        msg.includes('unique constraint') ||
        msg.includes('UNIQUE constraint')
      ) {
        skipped++;
      } else {
        process.stderr.write(
          `[backfill] insert error for turnId=${turn.turnId}: ${msg}\n`,
        );
        errors++;
      }
    }
  }

  // Progress (every 100 rows)
  if (processed % 100 === 0) {
    process.stderr.write(
      `[backfill] processed ${processed} / ${total} (skipped ${skipped} existing, inserted ${inserted} new)\n`,
    );
  }
}

// Final progress line
process.stderr.write(
  `[backfill] processed ${processed} / ${total} (skipped ${skipped} existing, inserted ${inserted} new, errors ${errors})\n`,
);

const result = { ok: true, processed, inserted, skipped, errors };
process.stdout.write(JSON.stringify(result) + '\n');

// MANDATORY: postgres.js holds the connection pool open. Hard exit.
process.exit(0);

```
