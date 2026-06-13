---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/src/conversation/customer-link-resolve-script.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.516553+00:00
---

# cartridges/oddjobz/brain/src/conversation/customer-link-resolve-script.ts

```ts
/**
 * D-OJ-conv-propose-outbound — bun subprocess: resolve a customer link token.
 *
 * Wire protocol (from propose_turn_http.zig GET /api/v1/c/{token}):
 *   stdin:  { token: string }
 *   stdout: { ok: true,  conversationId: string, entityTitle: string }
 *         | { ok: false, error: 'not_found' }
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
import { resolveCustomerLink } from './customer-link.js';

// ── Read stdin ────────────────────────────────────────────────────────────────

const stdinChunks: Buffer[] = [];
for await (const chunk of process.stdin) stdinChunks.push(chunk as Buffer);
const input = JSON.parse(Buffer.concat(stdinChunks).toString()) as {
  token: string;
};

// ── Connect to DB ─────────────────────────────────────────────────────────────

const db = getDatabaseOrNull();
if (!db) {
  process.stdout.write(JSON.stringify({ ok: false, error: 'db_error' }) + '\n');
  process.exit(0);
}

// ── Resolve ───────────────────────────────────────────────────────────────────

try {
  const result = await resolveCustomerLink(db, input.token);
  if (!result) {
    process.stdout.write(JSON.stringify({ ok: false, error: 'not_found' }) + '\n');
  } else {
    process.stdout.write(
      JSON.stringify({
        ok: true,
        conversationId: result.conversationId,
        entityTitle: result.entityTitle,
      }) + '\n',
    );
  }
} catch (err) {
  process.stderr.write(
    `[customer-link-resolve-script] Unexpected error: ${err instanceof Error ? err.message : String(err)}\n`,
  );
  process.stdout.write(JSON.stringify({ ok: false, error: 'db_error' }) + '\n');
}

// Force exit: postgres.js holds the connection pool open (active socket) after
// all work is done, which prevents bun's event loop from draining naturally.
// Since this is a one-shot subprocess, a hard exit is correct — no cleanup needed.
process.exit(0);

```
