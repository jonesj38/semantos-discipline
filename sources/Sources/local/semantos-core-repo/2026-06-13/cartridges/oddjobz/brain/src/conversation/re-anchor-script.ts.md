---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/re-anchor-script.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.523939+00:00
---

# cartridges/oddjobz/brain/src/conversation/re-anchor-script.ts

```ts
/**
 * D-OJ-conv-re-anchor — bun subprocess: execute a turn re-anchor.
 *
 * Wire protocol (from re_anchor_http.zig):
 *   stdin:  { turnId: string, newEntityCellHash: string, newEntityKind: string,
 *             operatorCertId?: string }
 *   stdout: { ok: true,  newRelationId: string, supersededRelationId: string }
 *         | { ok: false, error: 'turn_not_found' }
 *         | { ok: false, error: 'entity_not_found' }
 *         | { ok: false, error: 'no_existing_anchor' }
 *         | { ok: false, error: 'already_anchored' }
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
import { reAnchorTurn } from './re-anchor.js';
import type { ReAnchorRequest } from './re-anchor.js';

// ── Read stdin ────────────────────────────────────────────────────────────────

const stdinChunks: Buffer[] = [];
for await (const chunk of process.stdin) stdinChunks.push(chunk as Buffer);
const input = JSON.parse(Buffer.concat(stdinChunks).toString()) as {
  turnId: string;
  newEntityCellHash: string;
  newEntityKind: 'job' | 'site' | 'customer' | 'lead';
  operatorCertId?: string;
};

// ── Connect to DB ─────────────────────────────────────────────────────────────

const db = getDatabaseOrNull();
if (!db) {
  process.stdout.write(JSON.stringify({ ok: false, error: 'db_error' }) + '\n');
  process.exit(0);
}

// ── Build request ─────────────────────────────────────────────────────────────

const req: ReAnchorRequest = {
  turnId: input.turnId,
  newEntityCellHash: input.newEntityCellHash,
  newEntityKind: input.newEntityKind,
  ...(input.operatorCertId !== undefined
    ? { operatorCertId: input.operatorCertId }
    : {}),
};

// ── Execute re-anchor ─────────────────────────────────────────────────────────

try {
  const result = await reAnchorTurn(db, req);

  if (!result.ok) {
    switch (result.reason) {
      case 'turn_not_found':
        process.stdout.write(JSON.stringify({ ok: false, error: 'turn_not_found' }) + '\n');
        break;

      case 'entity_not_found':
        process.stdout.write(JSON.stringify({ ok: false, error: 'entity_not_found' }) + '\n');
        break;

      case 'no_existing_anchor':
        process.stdout.write(JSON.stringify({ ok: false, error: 'no_existing_anchor' }) + '\n');
        break;

      case 'already_anchored_to_same_entity':
        process.stdout.write(JSON.stringify({ ok: false, error: 'already_anchored' }) + '\n');
        break;

      case 'db_error':
        process.stdout.write(JSON.stringify({ ok: false, error: 'db_error' }) + '\n');
        break;

      default:
        process.stdout.write(JSON.stringify({ ok: false, error: 'db_error' }) + '\n');
    }
  } else {
    process.stdout.write(
      JSON.stringify({
        ok: true,
        newRelationId: result.newRelationId,
        supersededRelationId: result.supersededRelationId,
      }) + '\n',
    );
  }
} catch (err) {
  process.stderr.write(
    `[re-anchor-script] Unexpected error: ${err instanceof Error ? err.message : String(err)}\n`,
  );
  process.stdout.write(JSON.stringify({ ok: false, error: 'db_error' }) + '\n');
}

// Force exit: postgres.js holds the connection pool open (active socket) after
// all work is done, which prevents bun's event loop from draining naturally.
// Since this is a one-shot subprocess, a hard exit is correct — no cleanup needed.
process.exit(0);

```
